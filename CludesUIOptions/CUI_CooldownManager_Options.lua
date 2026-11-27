if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CludesUICooldownManager_Options.lua
--  Registers CDM Effects module with CludesUI
--  Tab 1: CDM Bars  (Bar Glows + Tracking Bars disabled pending rewrite)
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUICooldownManager"
local mod = CUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then return end -- module disabled: no options page

-- Controller cursor for the CDM's hand-built popups: the shared
-- CludesUI.PadPopupOpen (CludesUI_UICore.lua). On ns: no main-chunk local.
mod.PadPopupOpen = CUI.PadPopupOpen

-- Gates a row under Blizzard Style only: the classic kit draws chrome round
-- the user's own fill and background, so those settings stay live there.
local function GateBlizzardOnly(key, rowConf)
    if CUI.BlizzStyle.Active(key) == "blizzard" then return CUI.BlizzStyle.Gate(key, rowConf) end
    return rowConf
end

local PAGE_BAR_GLOWS = "Bar Glows"
local PAGE_BUFF_BARS = "Tracking Bars"
local PAGE_CDM_BARS = "CDM Bars"
local PAGE_ROTATION_ICON = "Rotation Assist Icon"

local PAGE_UNLOCK = "Layout Mode"

local SEC_MAPPINGS = "GLOW MAPPINGS"
local SEC_LAYOUT = "LAYOUT"
local SEC_APPEARANCE = "APPEARANCE"
local SEC_FILTER = "FILTER"
local SEC_BEHAVIOR = "BEHAVIOR"

CUI.AtOptionsLogin(function()
    local Pix = CUI.PanelPP
    -- The options page pool (CludesUI_FramePool.lua): a frame made here under
    -- a pool host (a reused page or header, a kept menu) is handed out again reset
    -- to fresh; anywhere else this is the plain CreateFrame. A menu made per open
    -- is one kept frame for the session (PoolKept), dressed again on each open.
    local Pool = CUI._Pool
    local CreateFrame = Pool.CreateFrame
    local PoolKept, PoolGen = Pool.Kept, Pool.Gen

    local saved
    C_Timer.After(0, function() saved = _G._CUCME_AceDB end)

    local function DB()
        if not saved then saved = _G._CUCME_AceDB end
        return saved and saved.profile
    end

    local function ApplyCDM()
        if _G._CUCME_Apply then _G._CUCME_Apply() end
    end

    -- Add/RemoveTrackedSpell already rebuild routes + queue reanchor; force an immediate
    -- CollectAndReanchor (not the throttled queue), then rebuild the page with
    -- _skipNextApplyRebuild to skip the redundant FullCDMRebuild.
    local function RefreshCDPreview()
        if mod.CollectAndReanchor then mod.CollectAndReanchor() end
        mod._skipNextApplyRebuild = true
        C_Timer.After(0.05, function()
            if mod.CDMApplyVisibility then mod.CDMApplyVisibility() end
            if mod.ApplyCachedKeybinds then mod.ApplyCachedKeybinds() end
            CUI:RefreshPage(true)
        end)
    end

    -- Inline text input helper (no W:InputBox exists)
    local FONT_PATH = (CUI.GetFontPath("cdm"))
        or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

    local GetCDMOptOutline = CUI.GetFontOutlineFlag

    -- Auto-widens break-out menus (flyouts/Apply-to strip/item pickers) to the longest
    -- RENDERED caption so text doesn't overflow (option rows) or ellipsize (item rows):
    -- grow-only from nominal width, capped at MAX_W (tooltip/ellipsis fallback past cap).
    -- pad = text inset + right-edge furniture; hidden rows count too -- never resize mid-hover/typing.
    local function FitMenuWidth(labels, nominalW, pad)
        local MAX_W = 340
        local widest = 0
        for i = 1, #labels do
            local fontStr = labels[i]
            local wid = fontStr and fontStr:GetStringWidth() or 0
            if wid > widest then widest = wid end
        end
        local fit = math.ceil(widest + (pad or 40))
        if fit < nominalW then fit = nominalW end
        if fit > MAX_W then fit = MAX_W end
        return fit
    end
    local SetPVFont = CUI.ApplyModuleFont

    ---------------------------------------------------------------------------
    --  Buff spell list from viewer pool (Bar Glows page glow assignments)
    ---------------------------------------------------------------------------
    local BAR_BUTTON_PREFIXES = {
        [1] = "ActionButton",
        [2] = "MultiBarBottomLeftButton",
        [3] = "MultiBarBottomRightButton",
        [4] = "MultiBarRightButton",
        [5] = "MultiBarLeftButton",
        [6] = "MultiBar5Button",
        [7] = "MultiBar6Button",
        [8] = "MultiBar7Button",
    }

    -- Action bar shape masks/borders (for preview rendering)
    local AB_SHAPE_MASKS = CUI.SHAPE_MASKS
    local AB_SHAPE_BORDERS = CUI.SHAPE_BORDERS

    -- Action bar entries (1-8) are stable; CDM bar entries are built dynamically via
    -- BuildBGTargetList since users can add extra cooldown/utility/buff bars beyond defaults.
    local BG_ACTION_BAR_LABELS = {
        [1] = "Action Bar 1 (Main)",
        [2] = "Action Bar 2",
        [3] = "Action Bar 3",
        [4] = "Action Bar 4",
        [5] = "Action Bar 5",
        [6] = "Action Bar 6",
        [7] = "Action Bar 7",
        [8] = "Action Bar 8",
    }

    -- Legacy installs saved selectedBar as 101/102 for the default cooldowns/
    -- utility CDM bars; normalize to the bar key string (new saves use the key).
    local function NormalizeSelectedBar(selection)
        if selection == 101 then return "cooldowns" end
        if selection == 102 then return "utility" end
        return selection
    end

    -- Live dropdown list: {value,label} in display order -- CDM bars from p.cdmBars.bars
    -- (skipping ghost/custom_buff) then action bars 1-8; value = bar key string or int 1-8.
    local function BuildBGTargetList()
        local entries = {}
        local p = mod.ECME and mod.ECME.db and mod.ECME.db.profile
        if p and p.cdmBars and p.cdmBars.bars then
            for _, edge in ipairs(p.cdmBars.bars) do
                if edge.enabled and not edge.isGhostBar and edge.barType ~= "custom_buff" then
                    entries[#entries + 1] = {
                        value = edge.key,
                        label = CUI.Lf("CDM Bar - %s", CUI.L(edge.name or edge.key)),
                    }
                end
            end
        end
        for i = 1, 8 do
            entries[#entries + 1] = { value = i, label = CUI.L(BG_ACTION_BAR_LABELS[i]) }
        end
        return entries
    end

    local function GetBGTargetLabel(selection)
        selection = NormalizeSelectedBar(selection)
        if type(selection) == "number" then
            return CUI.L(BG_ACTION_BAR_LABELS[selection] or ("Action Bar " .. selection))
        end
        local p = mod.ECME and mod.ECME.db and mod.ECME.db.profile
        if p and p.cdmBars and p.cdmBars.bars then
            for _, edge in ipairs(p.cdmBars.bars) do
                if edge.key == selection then
                    return CUI.Lf("CDM Bar - %s", CUI.L(edge.name or edge.key))
                end
            end
        end
        return tostring(selection)
    end

    -- Presets/custom spell IDs/racials/trinkets/custom buffs are CludesUI-injected
    -- icons (no stable cooldownID), so they are NOT glow-assignable -- the Bar Glows preview leaves them inert.
    local function IsNonGlowableCDMIcon(widget)
        if not widget then return false end
        -- Overflow-diverted icons are session-only: their glow identity/slot-index
        -- fallback key belongs to the source bar, so they aren't listed while diverted
        -- (existing cdm_-keyed glows still RENDER -- the render pass is key-driven, not list-driven).
        if mod.CdmFrameOverflowBar and mod.CdmFrameOverflowBar(widget) then return true end
        return (
            widget._isRacialFrame
            or widget._isTrinketFrame
            or widget._isPresetFrame
            or widget._isItemPresetFrame
            or widget._isCustomSpellFrame
            or widget._isCustomBuffFrame
        )
                and true
            or false
    end

    -- True if any icon on a buff bar has per-icon "Always Show Buff" = on (or
    -- "missing" -- Show When Missing also injects inactive placeholders), so
    -- it's mutually exclusive with "Keep Buffs in Same Place".
    local function AnyIconAlwaysShowOn(barId)
        -- Per-spell entries live in the spec FAMILY store; rawget skips bar-tier
        -- inheritance (checked separately below).
        local st = mod.GetSpellSettingsStore and mod.GetSpellSettingsStore(barId)
        if st then
            for _, ss in pairs(st) do
                if type(ss) == "table" then
                    local as = rawget(ss, "alwaysShow")
                    if as == "on" or as == "missing" then return true end
                end
            end
        end
        local sd = mod.GetBarSpellData and mod.GetBarSpellData(barId)
        local tier = mod.GetBarTierSettings and mod.GetBarTierSettings(sd, barId)
        if tier and (tier.alwaysShow == "on" or tier.alwaysShow == "missing") then return true end
        return false
    end

    -- Build glow style dropdown values from ns.GLOW_STYLES
    local function GetGlowStyleValues()
        local labels, sequence = {}, {}
        if mod.GLOW_STYLES then
            for _, i in ipairs(mod.GLOW_VIEW.ordered) do
                local record = mod.GLOW_STYLES[i]
                labels[i] = (record.name and CUI.L(record.name)) or ("Style " .. i)
                sequence[#sequence + 1] = i
            end
        end
        if #sequence == 0 then
            labels[1] = "Action Button Glow"
            sequence[1] = 1
        end
        return labels, sequence
    end

    ---------------------------------------------------------------------------
    --  Glow sites for Global Settings > Glows: per-bar Pandemic Glow, Buff Glow
    --  and Pixel Glow parameters, Tracked Buff Bars (active spec) and Rotation
    --  Assist, as shared glow descriptors over the bars' own keys.
    ---------------------------------------------------------------------------
    do
        local GO = CUI.GlowOptions
        local function CdmBarList()
            local p = mod.ECME and mod.ECME.db and mod.ECME.db.profile
            return p and p.cdmBars
        end
        local function Rebuild()
            if mod.BuildAllCDMBars then mod.BuildAllCDMBars() end
        end
        -- Shared per-bar refreshes: the Glows page runs each distinct onChange once
        -- per Apply, so every bar's descriptor must hand out the same function.
        local function RebuildBuffGlows()
            Rebuild()
            if mod.RefreshBuffGlows then mod.RefreshBuffGlows() end
        end
        local function RebuildPixelGlows()
            Rebuild()
            if mod.RequestBarGlowUpdate then mod.RequestBarGlowUpdate() end
        end
        local function RebuildTBB()
            if mod.BuildTrackedBuffBars then mod.BuildTrackedBuffBars() end
        end
        local function ColorKeys(tbl, key)
            local color = tbl[key]
            if color then return color.r, color.g, color.b end
        end
        -- pandemicGlow* keys, shared by a bar's Pandemic Glow and the Tracked Buff
        -- Bars (style reads differ, see the descriptors).
        local function PandemicGet(edge, f)
            if f == "mode" then return edge.pandemicGlowMode or "default" end
            return CUI.GlowOptions.FlatGet(edge, "pandemicGlow", f)
        end
        local function PandemicSet(edge, f, a, b2, c2)
            if f == "style" then
                if a == 0 then
                    edge.pandemicGlow = false
                else
                    edge.pandemicGlow = true
                    edge.pandemicGlowStyle = a
                end
            elseif f == "mode" then
                edge.pandemicGlowMode = a
                -- Custom with no color stored draws the default look on the bar
                -- while the swatch and the preview show yellow: store it.
                if a == "custom" and not edge.pandemicGlowColor then
                    edge.pandemicGlowColor = { r = 1, g = 1, b = 0 }
                end
            else
                CUI.GlowOptions.FlatSet(edge, "pandemicGlow", f, a, b2, c2)
            end
        end

        -- Pandemic Glow of one CDM bar, shared by the Glows page and the CDM Bars
        -- page row. getBd resolves the bar at call time; onChange defaults to the
        -- shared rebuild (the bar page passes its own). nil pandemicGlow = never
        -- configured = Blizzard Default, not None: the built-in bars never seed the
        -- key (the templates that do ship true + -1) and Blizzard's PandemicIcon
        -- still draws for them, so only an explicit false reads as None.
        -- WoW Forever: the anti-clip glow (CUI_CDM_ForeverAntiClip.lua) has no
        -- Blizzard look, so there Blizzard Default is not offered and an unset or
        -- Blizzard Default bar reads as None, as the bar draws it.
        local function PandemicDesc(getBd, changed)
            local antiClip = mod.CDM_ANTI_CLIP
            return {
                view = mod.GLOW_VIEW,
                host = "icon",
                excludes = { [4] = true },
                extras = not antiClip and { { value = -1, label = "Blizzard Default" } } or nil,
                caps = { mode = true, params = true, bg = true },
                defaultColor = { r = 1, g = 1, b = 0 },
                onChange = changed or Rebuild,
                get = function(f)
                    local edge = getBd()
                    if not edge then return nil end
                    if f == "style" then
                        if edge.pandemicGlow == false then return 0 end
                        if edge.pandemicGlow == nil then return antiClip and 0 or -1 end
                        local style = edge.pandemicGlowStyle or 1
                        if antiClip and style == -1 then return 0 end
                        return style
                    end
                    return PandemicGet(edge, f)
                end,
                set = function(f, a, b2, c2)
                    local edge = getBd()
                    if edge then PandemicSet(edge, f, a, b2, c2) end
                end,
            }
        end
        mod._CDM_PandemicGlowDesc = PandemicDesc

        -- Buff Glow of one buff-family bar (flat buffGlow* keys); getBd and
        -- onChange as for PandemicDesc.
        local function BuffGlowDesc(getBd, changed)
            return {
                view = mod.GLOW_VIEW,
                host = "icon",
                excludes = { [4] = true },
                caps = { mode = true, params = true, bg = true },
                defaultColor = { r = 1, g = 0.788, b = 0.137 },
                onChange = changed or RebuildBuffGlows,
                get = function(f)
                    local edge = getBd()
                    if not edge then return nil end
                    if f == "style" then
                        return edge.buffGlowType or 0
                    elseif f == "mode" then
                        return edge.buffGlowMode or "default"
                    elseif f == "color" then
                        if edge.buffGlowR then return edge.buffGlowR, edge.buffGlowG, edge.buffGlowB end
                    -- Same fallbacks as the Buff Glow renderer (8/2/4), not the pixelGlow* keys.
                    elseif f == "lines" then
                        return edge.buffGlowLines
                    elseif f == "thickness" then
                        return edge.buffGlowThickness
                    elseif f == "speed" then
                        return edge.buffGlowSpeed
                    elseif f == "bg" then
                        return edge.buffGlowBackground == true
                    elseif f == "bgColor" then
                        if edge.buffGlowBackgroundR then
                            return edge.buffGlowBackgroundR,
                                edge.buffGlowBackgroundG,
                                edge.buffGlowBackgroundB
                        end
                    end
                end,
                set = function(f, a, b2, c2)
                    local edge = getBd()
                    if not edge then return end
                    if f == "style" then
                        edge.buffGlowType = a
                    elseif f == "mode" then
                        edge.buffGlowMode = a
                    elseif f == "color" then
                        edge.buffGlowR, edge.buffGlowG, edge.buffGlowB = a, b2, c2
                    elseif f == "lines" then
                        edge.buffGlowLines = a
                    elseif f == "thickness" then
                        edge.buffGlowThickness = a
                    elseif f == "speed" then
                        edge.buffGlowSpeed = a
                    elseif f == "bg" then
                        edge.buffGlowBackground = a
                    elseif f == "bgColor" then
                        edge.buffGlowBackgroundR, edge.buffGlowBackgroundG, edge.buffGlowBackgroundB =
                            a, b2, c2
                    end
                end,
            }
        end
        mod._CDM_BuffGlowDesc = BuffGlowDesc

        -- Pixel Glow parameters of a cooldown bar: the per-spell glows assigned on
        -- its icons read these (no style or color of their own).
        local function PixelParamsDesc(edge)
            return {
                paramsOnly = true,
                host = "icon",
                caps = { params = true, bg = true },
                onChange = RebuildPixelGlows,
                get = function(f)
                    if f == "lines" then
                        return edge.pixelGlowLines
                    elseif f == "thickness" then
                        return edge.pixelGlowThickness
                    elseif f == "speed" then
                        return edge.pixelGlowSpeed
                    elseif f == "bg" then
                        return edge.pixelGlowBackground == true
                    elseif f == "bgColor" then
                        if edge.pixelGlowBackgroundR then
                            return edge.pixelGlowBackgroundR,
                                edge.pixelGlowBackgroundG,
                                edge.pixelGlowBackgroundB
                        end
                    elseif f == "mode" then
                        return "default"
                    end
                end,
                set = function(f, a, b2, c2)
                    if f == "lines" then
                        edge.pixelGlowLines = a
                    elseif f == "thickness" then
                        edge.pixelGlowThickness = a
                    elseif f == "speed" then
                        edge.pixelGlowSpeed = a
                    elseif f == "bg" then
                        edge.pixelGlowBackground = a
                    elseif f == "bgColor" then
                        edge.pixelGlowBackgroundR, edge.pixelGlowBackgroundG, edge.pixelGlowBackgroundB =
                            a, b2, c2
                    end
                end,
            }
        end

        -- Pandemic Glow of one Tracked Buff Bar (rectangle: Pixel and Auto-Cast only;
        -- any other stored style or Blizzard Default shows and renders as Pixel, see
        -- ns.PG_TbbEffectiveStyle). getBd resolves the bar at call time, so the
        -- Tracking Bars page (selected bar) and the Glows page share this.
        local function TbbDesc(getBd, changed)
            return {
                view = mod.GLOW_VIEW,
                host = "bar",
                excludes = CUI.Glows.RECT_EXCLUDES,
                caps = { mode = true, params = true, bg = true },
                defaultColor = { r = 1, g = 1, b = 0 },
                isOff = function()
                    local edge = getBd()
                    return not edge or edge.pandemicGlow ~= true
                end,
                onChange = changed,
                get = function(f)
                    local edge = getBd()
                    if not edge then return nil end
                    if f == "style" then return mod.PG_TbbEffectiveStyle(edge) end
                    return PandemicGet(edge, f)
                end,
                set = function(f, a, b2, c2)
                    local edge = getBd()
                    if edge then PandemicSet(edge, f, a, b2, c2) end
                end,
            }
        end
        mod._CDM_TbbGlowDesc = TbbDesc

        -- Rotation Assist (profile-wide): string-keyed styles; Blizzard Default and
        -- Solid Border are extras, never template targets.
        local ROT_TO_SHARED =
            { pixel = 1, button = 2, autocast = 3, shape = 4, gcd = 5, modern = 6, classic = 7 }
        local SHARED_TO_ROT = {}
        for keyName, val in pairs(ROT_TO_SHARED) do
            SHARED_TO_ROT[val] = keyName
        end
        -- Why the CDM highlight cannot show, nil while it can: Blizzard's
        -- Assisted Highlight off (always on Forever) or Show Rotation Helper off.
        local function RotationLockTip()
            if not mod.RotationAssistAvailable() then
                return "This option requires Blizzard's Assisted Highlight to be enabled"
            end
            local c = CdmBarList()
            if c and c.hideRotationHelper then return "Show Rotation Helper" end
        end
        local function RotationHelperOff() return RotationLockTip() ~= nil end
        -- The CDM Bars page builds its Rotation Assist rows only while this is false.
        mod._CDM_RotationHelperOff = RotationHelperOff
        -- Blizzard's Assisted Highlight switched in its own options (fires only on
        -- a real change): those rows were built for the old state, and a cached
        -- page comes back without a rebuild. Drop the cached CDM pages and rebuild
        -- the one on screen (a closed panel rebuilds on its next show); the Glows
        -- page lists this site per build. Not on Forever.
        if not CUI.IS_FOREVER then
            EventRegistry:RegisterCallback("AssistedCombatManager.OnSetUseAssistedHighlight", function()
                CUI:InvalidateModulePageCache("CludesUICooldownManager")
                local m = CUI:GetActiveModule()
                if
                    m == "CludesUICooldownManager"
                    or (m == CUI.GLOBAL_KEY and CUI:GetActivePage() == "Glows")
                then
                    CUI:RefreshPage(true)
                end
            end, "ECME_Options_AssistedHighlight")
        end
        local function RotationDesc()
            local desc = {
                host = "icon",
                noNone = true,
                toShared = function(val) return ROT_TO_SHARED[val] end,
                fromShared = function(i) return SHARED_TO_ROT[i] end,
                order = { "pixel", "shape", "button", "autocast", "gcd", "modern", "classic" },
                extras = {
                    { value = "blizzard", label = "Blizzard Default" },
                    { value = "solid", label = "Solid Border", colored = true },
                },
                caps = { mode = true, params = true, bg = true },
                thicknessMax = 8,
                defaultColor = { r = 1, g = 0, b = 0 },
                -- Off and locked while the highlight cannot show.
                isOff = RotationHelperOff,
                disabled = RotationHelperOff,
                disabledTooltip = RotationLockTip,
                onChange = function()
                    if mod.UpdateRotationHighlights then mod.UpdateRotationHighlights() end
                end,
                get = function(f)
                    local c = CdmBarList()
                    if not c then return nil end
                    if f == "style" then
                        return c.rotationAssistStyle or "blizzard"
                    elseif f == "mode" then
                        return c.rotationAssistColorMode or "default"
                    elseif f == "color" then
                        return c.rotationAssistColorR or 1,
                            c.rotationAssistColorG or 0,
                            c.rotationAssistColorB or 0
                    elseif f == "lines" then
                        return c.rotationAssistLines
                    -- The renderer draws 3 when unset and allows up to 8 (thicknessMax).
                    elseif f == "thickness" then
                        return c.rotationAssistThickness or 3
                    elseif f == "speed" then
                        return c.rotationAssistSpeed
                    elseif f == "bg" then
                        return c.rotationAssistBackground == true
                    elseif f == "bgColor" then
                        return ColorKeys(c, "rotationAssistBackgroundColor")
                    end
                end,
                set = function(f, a, b2, c2)
                    local c = CdmBarList()
                    if not c then return end
                    if f == "style" then
                        c.rotationAssistStyle = a
                    elseif f == "mode" then
                        c.rotationAssistColorMode = a
                    elseif f == "color" then
                        c.rotationAssistColorR, c.rotationAssistColorG, c.rotationAssistColorB = a, b2, c2
                    elseif f == "lines" then
                        c.rotationAssistLines = a
                    elseif f == "thickness" then
                        c.rotationAssistThickness = a
                    elseif f == "speed" then
                        c.rotationAssistSpeed = a
                    elseif f == "bg" then
                        c.rotationAssistBackground = a
                    elseif f == "bgColor" then
                        c.rotationAssistBackgroundColor = { r = a, g = b2, b = c2 }
                    end
                end,
            }
            return desc
        end
        -- The CDM Bars page's Rotation Assist cog reuses the shared rows.
        mod._CDM_RotationGlowDesc = RotationDesc
        -- Which glow rows a bar shows on the CDM Bars page; the Glows page lists
        -- exactly these. EXTRAS (Pandemic Glow): not custom aura bars or FocusKick.
        function mod.CDM_BarHasExtras(edge) return edge.barType ~= "custom_buff" and edge.key ~= "focuskick" end
        -- Pixel Glow Thickness row: cooldown and utility bars (buff bars use Buff Glow).
        function mod.CDM_BarHasPixelRow(edge)
            return not (mod.IsBarBuffFamily and mod.IsBarBuffFamily(edge))
                and (edge.barType == "cooldowns" or edge.barType == "utility")
        end

        do
            -- Open Settings targets: the CDM Bars page with the bar selected first.
            local function BarNav(key, section, highlight)
                return {
                    page = PAGE_CDM_BARS,
                    section = section,
                    highlight = highlight,
                    preSelect = function()
                        if CUI._setCDMBar then CUI._setCDMBar(key) end
                    end,
                }
            end
            -- Rotation Assist, listed per page build: while the highlight cannot
            -- show, the row reads None and Off, stays locked and opens Show
            -- Rotation Helper (the style has no None of its own, so only that
            -- listing offers one). Not on Forever: no Assisted Highlight there.
            if not CUI.IS_FOREVER then
                local rotOn = { { label = "Rotation Assist Style", desc = RotationDesc() } }
                local offDesc = RotationDesc()
                offDesc.noNone = nil
                -- Locked for good: a cached page keeps this listing until it rebuilds.
                offDesc.disabled = function() return true end
                local rotOff = {
                    {
                        label = "Rotation Assist Style",
                        desc = offDesc,
                        nav = BarNav("cooldowns", "EXTRAS", "Show Rotation Helper"),
                    },
                }
                -- sub: the group heading on the Glows page card (General, one
                -- per bar, Tracking Bars); labels stay short beneath it.
                GO.RegisterSite({
                    id = "cdm_rotation",
                    label = "Rotation Assist Style",
                    group = "bar",
                    sub = CUI.L("General"),
                    module = "CludesUICooldownManager",
                    page = PAGE_CDM_BARS,
                    section = "EXTRAS",
                    highlight = "Rotation Assist Style",
                    preSelect = BarNav("cooldowns").preSelect,
                    list = function() return RotationHelperOff() and rotOff or rotOn end,
                })
            end
            -- Per-icon glows and Bar Glows stay per entry (never template targets):
            -- hint entries counting the active spec's own settings. Read-only, raw
            -- entry values only (inherited bar tiers and explicit false don't count).
            -- Style keys only: a glow style is a number > 0 (0 = explicit None); a
            -- color alone draws nothing.
            local PER_ICON_GLOW_KEYS = { "procGlow", "activeGlow", "maxStacksGlow", "buffGlow" }
            local PER_ICON_FAMILIES = { "cooldowns", "buffs" }
            local function HasOwnGlow(e)
                if type(e) ~= "table" then return false end
                for i = 1, #PER_ICON_GLOW_KEYS do
                    local val = rawget(e, PER_ICON_GLOW_KEYS[i])
                    if type(val) == "number" and val > 0 then return true end
                end
                -- Cooldown State Effect glow: its own key decides (false = none),
                -- else a glow saved in cdStateEffect, the single-value form.
                local g = rawget(e, "cdStateGlow")
                if g ~= nil then return type(g) == "string" end
                local cse = rawget(e, "cdStateEffect")
                return type(cse) == "string" and mod.CD_STATE_GLOWS[cse] ~= nil
            end
            local function CountPerIconGlows()
                local num = 0
                for _, fam in ipairs(PER_ICON_FAMILIES) do
                    local st = mod.GetSpellSettingsStore and mod.GetSpellSettingsStore(fam)
                    for _, entry in pairs(st or {}) do
                        if HasOwnGlow(entry) then num = num + 1 end
                    end
                end
                -- Preset and custom spells keep theirs in the profile-level
                -- customActiveStates store (read directly: its getter creates it).
                local prof = mod.ECME and mod.ECME.db and mod.ECME.db.profile
                for _, entry in pairs((prof and prof.customActiveStates) or {}) do
                    if HasOwnGlow(entry) then num = num + 1 end
                end
                return num
            end
            GO.RegisterSite({
                id = "cdm_per_icon",
                label = "Per-Icon Glows",
                module = "CludesUICooldownManager",
                page = PAGE_CDM_BARS,
                info = {
                    glyph = "icon",
                    tooltip = "Proc Glow, Active State Glow, Max Charges Glow, Buff Glow, CD Ready Glow and Glow Effect Color can be set per icon: right-click an icon in the CDM Bars preview. Counted for the current specialization; the template never changes them.",
                    text = function()
                        return CUI.Lf("%d icon(s) with their own glow settings", CountPerIconGlows())
                    end,
                },
            })
            GO.RegisterSite({
                id = "cdm_bar_glows",
                label = "Bar Glows",
                module = "CludesUICooldownManager",
                page = PAGE_BAR_GLOWS,
                info = {
                    glyph = "bar",
                    tooltip = "Glows on action bar and CDM buttons while a tracked buff is active (or missing), set per entry on the Bar Glows page. Counted for the current specialization; the template never changes them.",
                    text = function()
                        -- Read-only: ns.GetBarGlows would create the spec's table.
                        local specKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
                        local spellRec = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
                        local backdrop = specKey
                            and spellRec
                            and spellRec[specKey]
                            and spellRec[specKey].barGlows
                        local num = 0
                        for _, entries in pairs((backdrop and backdrop.assignments) or {}) do
                            if type(entries) == "table" then num = num + #entries end
                        end
                        if backdrop and backdrop.enabled == false then
                            return CUI.Lf("%d bar glow(s), turned off", num)
                        end
                        return CUI.Lf("%d bar glow(s)", num)
                    end,
                },
            })
            -- Per-bar sites are rebuilt on every page build (bars come and go).
            GO.RegisterSite({
                id = "cdm_bars",
                label = "Cooldown Manager Bars",
                group = "bar",
                module = "CludesUICooldownManager",
                list = function()
                    local result = {}
                    local c = CdmBarList()
                    -- WoW Forever: the bars' Pandemic Glow rows read Anti-Clip Glow.
                    local panLabel = mod.CDM_ANTI_CLIP and "Anti-Clip Glow" or "Pandemic Glow"
                    for _, edge in ipairs((c and c.bars) or {}) do
                        -- Ghost and custom buff bars stay out, like the pandemic sync.
                        if not edge.isGhostBar and edge.barType ~= "custom_buff" then
                            local name = CUI.L(edge.name or edge.key or "?")
                            if mod.CDM_BarHasExtras(edge) then
                                result[#result + 1] = {
                                    label = panLabel,
                                    sub = name,
                                    desc = PandemicDesc(function() return edge end),
                                    nav = BarNav(edge.key, "EXTRAS", panLabel),
                                }
                            end
                            if mod.IsBarBuffFamily and mod.IsBarBuffFamily(edge) then
                                result[#result + 1] = {
                                    label = "Buff Glow",
                                    sub = name,
                                    desc = BuffGlowDesc(function() return edge end),
                                    nav = BarNav(edge.key, "ICON DISPLAY", "Buff Glow"),
                                }
                            elseif mod.CDM_BarHasPixelRow(edge) then
                                result[#result + 1] = {
                                    label = "Pixel Glow",
                                    sub = name,
                                    desc = PixelParamsDesc(edge),
                                    nav = BarNav(edge.key, "ICON DISPLAY", "Pixel Glow Thickness"),
                                }
                            end
                        end
                    end
                    local tbb = mod.GetTrackedBuffBars and mod.GetTrackedBuffBars()
                    local tbbSub = CUI.L("Tracking Bars")
                        .. " - "
                        .. (mod.CDM_ANTI_CLIP and CUI.L("Anti-Clip Glow") or CUI.L("Pandemic Glow"))
                    for i, edge in ipairs((tbb and tbb.bars) or {}) do
                        result[#result + 1] = {
                            label = edge.name or "?",
                            sub = tbbSub,
                            desc = TbbDesc(function() return edge end, RebuildTBB),
                            nav = {
                                page = PAGE_BUFF_BARS,
                                section = "EXTRAS",
                                highlight = panLabel,
                                preSelect = function()
                                    if mod._TBBSelectBar then mod._TBBSelectBar(i) end
                                end,
                            },
                        }
                    end
                    return result
                end,
            })
        end
    end

    -- Cross-surface pandemic-glow sync (CDM bars + Nameplates) lives in CDM core as
    -- ApplyPandemicGlowToAll/IsPandemicGlowSyncedToAll (best-effort, name-based so styles
    -- never shift across surfaces); callers build a payload via PandemicPayloadFrom*.

    -- Check if a specific bar target uses a custom shape (not "none"/"cropped").
    -- barIdx can be a number 1-8 (action bar) or a string (CDM bar key).
    local function BarHasCustomShape(barIndex)
        barIndex = NormalizeSelectedBar(barIndex)
        if type(barIndex) == "string" then
            local barData = mod.barDataByKey and mod.barDataByKey[barIndex]
            if
                barData
                and barData.iconShape
                and barData.iconShape ~= "none"
                and barData.iconShape ~= "cropped"
            then
                return true
            end
            return false
        end
        local barKeys = { "MainBar", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8" }
        local barId = barKeys[barIndex]
        if not barId then return false end
        local success, ABAR = pcall(CUI.Lite.GetAddon, "CludesUIActionBars")
        if success and ABAR and ABAR.db and ABAR.db.profile and ABAR.db.profile.bars then
            local cfg = ABAR.db.profile.bars[barId]
            if cfg and cfg.buttonShape and cfg.buttonShape ~= "none" and cfg.buttonShape ~= "cropped" then
                return true
            end
        end
        return false
    end

    -- Preview glow state tracking
    local _bgPreviewGlowActive = {}
    local _bgPreviewGlowOverlays = {}
    local _bgSpellPickerMenu

    CUI:RegisterOnHide(function()
        if _bgSpellPickerMenu then _bgSpellPickerMenu:Hide() end
    end)

    local function ShowBarGlowSpellPicker(anchor, barIndex, btnIdx, onChanged, overrideAssignKey)
        local backdrop = mod.GetBarGlows()
        local assignmentKey = overrideAssignKey or (barIndex .. "_" .. btnIdx)
        local buffList = backdrop.assignments[assignmentKey] or {}

        local assignedSet = {}
        for _, record in ipairs(buffList) do
            if record.spellID then assignedSet[record.spellID] = true end
        end

        -- Immediate update: save picker position, rebuild, re-anchor
        local function ImmediateUpdate()
            if not onChanged then return end
            local menuRef = _bgSpellPickerMenu
            if not menuRef then
                onChanged()
                return
            end
            -- Save absolute screen position before rebuild
            local cx, cy = menuRef:GetCenter()
            local mScale = menuRef:GetEffectiveScale()
            onChanged()
            -- Re-anchor to saved absolute position so page rebuild doesn't shift us
            menuRef = _bgSpellPickerMenu
            if menuRef and menuRef:IsShown() then
                menuRef:ClearAllPoints()
                local uiScale = UIParent:GetEffectiveScale()
                menuRef:SetPoint(
                    "CENTER",
                    UIParent,
                    "BOTTOMLEFT",
                    cx * mScale / uiScale,
                    cy * mScale / uiScale
                )
            end
        end

        -- The shared Bar Glows buff menu (CUI_CooldownManager_BarGlowConditions.lua):
        -- one reused frame, the boxes repainted after each toggle.
        -- The button's own ability: its "spell_<id>" key, else the spell on its
        -- action slot. The top "Glow When Usable" row stands for it, and every
        -- entry added here records it.
        local buttonSid = tonumber(assignmentKey:match("^spell_(%d+)$"))
        local iconSid
        if type(barIndex) == "string" then
            -- CDM bar: the icon's own spell, as the runtime reads it (icon only).
            local icon = mod.cdmBarIcons and mod.cdmBarIcons[barIndex] and mod.cdmBarIcons[barIndex][btnIdx]
            iconSid = icon and mod.BarGlowButtonSpell(icon)
        elseif not buttonSid then
            local prefixText = BAR_BUTTON_PREFIXES[barIndex]
            local realButton = prefixText and _G[prefixText .. btnIdx]
            if realButton and realButton.action then
                local aType, ident = GetActionInfo(realButton.action)
                buttonSid = aType == "spell" and ident or nil
            end
        end
        iconSid = iconSid or buttonSid
        local buttonInfo = iconSid and C_Spell.GetSpellInfo(iconSid)
        local usableIcon = buttonInfo and buttonInfo.iconID
        local dropMenu = mod.ShowBarGlowBuffMenu(anchor, {
            usableItem = { icon = usableIcon },
            isChecked = function(spellRef) return assignedSet[spellRef] end,
            onClick = function(spellRec, refreshChecks)
                if assignedSet[spellRec.spellID] then
                    assignedSet[spellRec.spellID] = nil
                    for idx = #buffList, 1, -1 do
                        if buffList[idx].spellID == spellRec.spellID then
                            table.remove(buffList, idx)
                            break
                        end
                    end
                else
                    -- Add with defaults
                    assignedSet[spellRec.spellID] = true
                    local newEntry = {
                        spellID = spellRec.spellID,
                        glowStyle = 1,
                        mode = spellRec.usable and "USABLE" or "ACTIVE",
                        onlyInCombat = false,
                    }
                    newEntry.actionSpellID = buttonSid
                    buffList[#buffList + 1] = newEntry
                end
                refreshChecks()
                backdrop.assignments[assignmentKey] = buffList
                ApplyCDM()
                ImmediateUpdate()
            end,
        })
        if not dropMenu then return end
        dropMenu._btnIdx = btnIdx
        _bgSpellPickerMenu = dropMenu
    end

    ---------------------------------------------------------------------------
    --  Bar Glows: BuildBarGlowsPage
    ---------------------------------------------------------------------------
    local _glowHeaderBuilder -- stored for cache restore via getHeaderBuilder
    local _glowSelectedButton = nil -- UI-only selection state (not saved)
    local _glowBtnFrames = {} -- button frames from last header build, indexed by button number

    -- Live preview on action-bar paging (stance, mount, vehicle), which changes
    -- the icons the preview copies. One event frame for the session, registered
    -- only while the page shows (its page frame's OnShow and OnHide), so nothing
    -- listens while the page is hidden; a burst of events draws once, 0.15 s
    -- after the first. The preview alone is drawn again, unless a button is
    -- selected (the rows below belong to its current ability, which paging
    -- changes) or a preview glow was lit on a preview button: then the whole
    -- page is built again.
    local glowPreview =
        { events = { "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "PLAYER_MOUNT_DISPLAY_CHANGED" } }
    function glowPreview.Flush()
        glowPreview.pending = false
        if
            not (
                CUI:IsShown()
                and CUI:GetActiveModule() == ADDON_NAME
                and CUI:GetActivePage() == PAGE_BAR_GLOWS
            )
        then
            return
        end
        if _glowSelectedButton or next(_bgPreviewGlowOverlays) then
            CUI:RefreshPage(true)
        else
            CUI:SetContentHeader(_glowHeaderBuilder)
        end
    end
    function glowPreview.OnEvent()
        if glowPreview.pending then return end
        glowPreview.pending = true
        C_Timer.After(0.15, glowPreview.Flush)
    end
    function glowPreview.Arm()
        local frame = glowPreview.frame
        for i = 1, #glowPreview.events do
            frame:RegisterEvent(glowPreview.events[i])
        end
    end
    function glowPreview.Disarm() glowPreview.frame:UnregisterAllEvents() end

    local function BuildBarGlowsPage(pageTitle, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height

        local backdrop = mod.GetBarGlows()
        local curBar = NormalizeSelectedBar(backdrop.selectedBar or "cooldowns")
        local curBtn = _glowSelectedButton -- nil = no selection

        local ACCENT = CUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }

        -------------------------------------------------------------------
        --  Content Header: Live Action Bar Preview (replica of BuildLivePreview)
        -------------------------------------------------------------------
        CUI:ClearContentHeader()

        -- Stop any lingering preview glows
        for idx, shade in pairs(_bgPreviewGlowOverlays) do
            mod.StopNativeGlow(shade)
        end
        wipe(_bgPreviewGlowOverlays)
        wipe(_bgPreviewGlowActive)

        _glowHeaderBuilder = function(header, width)
            -- Re-read current state each build
            local bgData = mod.GetBarGlows()
            local selection = NormalizeSelectedBar(bgData.selectedBar or 1)
            local cdmBar = (type(selection) == "string")
            -- For CDM bars: cdmBarKey is the bar key string. For action bars:
            -- barIdx is the integer 1-8 used for prefix lookup.
            local cdmBarKey = cdmBar and selection or nil
            local barIndex = cdmBar and nil or selection
            local success, EAB_ADDON = pcall(CUI.Lite.GetAddon, "CludesUIActionBars")
            if not success then EAB_ADDON = nil end
            local barKeyList = { "MainBar", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8" }
            local barKeyStr = (not cdmBar) and (barKeyList[barIndex] or "MainBar") or nil
            local barConf = nil
            if barKeyStr and EAB_ADDON and EAB_ADDON.db and EAB_ADDON.db.profile then
                barConf = EAB_ADDON.db.profile.bars[barKeyStr]
            end

            -- CDM bars: count icons dynamically; action bars: always 12.
            -- Overflow-diverted icons are tail-appended to the target's array
            -- and excluded here, so every native icon keeps its slot index
            -- (stable glow-assignment fallback keys).
            local NUM_BUTTONS = 12
            if cdmBar and mod.cdmBarIcons and mod.cdmBarIcons[cdmBarKey] then
                NUM_BUTTONS = 0
                for _, ic in ipairs(mod.cdmBarIcons[cdmBarKey]) do
                    if not (mod.CdmFrameOverflowBar and mod.CdmFrameOverflowBar(ic)) then
                        NUM_BUTTONS = NUM_BUTTONS + 1
                    end
                end
                if NUM_BUTTONS == 0 then NUM_BUTTONS = 1 end
            end
            local prefixText = (not cdmBar) and (BAR_BUTTON_PREFIXES[barIndex] or "ActionButton") or nil

            -- Dropdown at top
            local DD_H = 34
            local ddW = 350
            local DDS = CUI.DD_STYLE
            local mBgR = DDS.BG_R
            local mBgG = DDS.BG_G
            local mBgB = DDS.BG_B
            local mBgA = DDS.BG_A
            local mBgHA = DDS.BG_HA
            local mBrdA = DDS.BRD_A
            local mBrdHA = DDS.BRD_HA or 0.30
            local mTxtA = DDS.TXT_A
            local mTxtHA = DDS.TXT_HA or 1
            local hlA = DDS.ITEM_HL_A
            local selA = DDS.ITEM_SEL_A
            local tDimR = CUI.TEXT_DIM_R or 0.7
            local tDimG = CUI.TEXT_DIM_G or 0.7
            local tDimB = CUI.TEXT_DIM_B or 0.7
            local tDimA = CUI.TEXT_DIM_A or 0.85
            local ITEM_H = 26

            local dropdownBtn = CreateFrame("Button", nil, header)
            Pix.Size(dropdownBtn, ddW, DD_H)
            dropdownBtn:SetFrameLevel(header:GetFrameLevel() + 5)
            local ddBg = dropdownBtn:CreateTexture(nil, "BACKGROUND")
            ddBg:SetAllPoints()
            ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
            local ddBrd = CUI.MakeRoundedBorder(dropdownBtn, 1, 1, 1, mBrdA, ddBg)
            local dropCaption = dropdownBtn:CreateFontString(nil, "OVERLAY")
            dropCaption:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            dropCaption:SetAlpha(mTxtA)
            dropCaption:SetJustifyH("LEFT")
            dropCaption:SetWordWrap(false)
            dropCaption:SetMaxLines(1)
            dropCaption:SetPoint("LEFT", dropdownBtn, "LEFT", 12, 0)
            local ddArrow = CUI.MakeDropdownArrow(dropdownBtn, 12, CUI.PanelPP)
            dropCaption:SetPoint("RIGHT", ddArrow, "LEFT", -5, 0)
            dropCaption:SetText(GetBGTargetLabel(selection))

            local ddMenu
            local function BuildDDMenu()
                if ddMenu then
                    ddMenu:Hide()
                    ddMenu = nil
                end
                -- One menu frame for the session, dressed again on every open
                -- (its rows are pooled under it).
                local dropMenu = PoolKept(mod, "cdmGlowTargetMenu", "Frame", UIParent)
                dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                dropMenu:SetFrameLevel(300)
                dropMenu:SetClampedToScreen(true)
                dropMenu:SetPoint("TOPLEFT", dropdownBtn, "BOTTOMLEFT", 0, -2)
                dropMenu:SetPoint("TOPRIGHT", dropdownBtn, "BOTTOMRIGHT", 0, -2)
                local bg2 = dropMenu:CreateTexture(nil, "BACKGROUND")
                bg2:SetAllPoints()
                bg2:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
                CUI.MakeRoundedBorder(dropMenu, 1, 1, 1, mBrdA, bg2, nil, true)
                local menuH = 4
                local targets = BuildBGTargetList()
                for _, t in ipairs(targets) do
                    local entryVal = t.value
                    local entry = CreateFrame("Button", nil, dropMenu)
                    entry:SetHeight(ITEM_H)
                    entry:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -menuH)
                    entry:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -menuH)
                    entry:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                    local iLbl = entry:CreateFontString(nil, "OVERLAY")
                    iLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    iLbl:SetJustifyH("LEFT")
                    iLbl:SetWordWrap(false)
                    iLbl:SetMaxLines(1)
                    iLbl:SetPoint("LEFT", entry, "LEFT", 10, 0)
                    iLbl:SetText(t.label)
                    local iHl = entry:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints()
                    iHl:SetColorTexture(1, 1, 1, 1)
                    local isCurrent = (entryVal == selection)
                    iHl:SetAlpha(isCurrent and selA or 0)
                    entry:SetScript("OnEnter", function()
                        iLbl:SetTextColor(1, 1, 1, 1)
                        iHl:SetAlpha(hlA)
                    end)
                    entry:SetScript("OnLeave", function()
                        iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        iHl:SetAlpha(isCurrent and selA or 0)
                    end)
                    entry:SetScript("OnClick", function()
                        dropMenu:Hide()
                        bgData.selectedBar = entryVal
                        bgData.selectedButton = nil
                        _glowSelectedButton = nil
                        CUI:RefreshPage(true)
                    end)
                    menuH = menuH + ITEM_H
                end
                dropMenu:SetHeight(menuH + 4)
                dropMenu:SetScript("OnUpdate", function(frame)
                    if
                        not frame:IsMouseOver()
                        and not dropdownBtn:IsMouseOver()
                        and IsMouseButtonDown("LeftButton")
                    then
                        frame:Hide()
                    end
                end)
                dropMenu:HookScript("OnHide", function(m) m:SetScript("OnUpdate", nil) end)
                dropMenu:Show()
                ddMenu = dropMenu
            end

            dropdownBtn:SetScript("OnEnter", function()
                dropCaption:SetAlpha(mTxtHA)
                ddBrd:SetColor(1, 1, 1, mBrdHA)
                ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
            end)
            dropdownBtn:SetScript("OnLeave", function()
                if ddMenu and ddMenu:IsShown() then return end
                dropCaption:SetAlpha(mTxtA)
                ddBrd:SetColor(1, 1, 1, mBrdA)
                ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
            end)
            dropdownBtn:SetScript("OnClick", function()
                if ddMenu and ddMenu:IsShown() then
                    ddMenu:Hide()
                else
                    BuildDDMenu()
                end
            end)
            dropdownBtn:HookScript("OnHide", function()
                if ddMenu then ddMenu:Hide() end
            end)
            Pix.Point(dropdownBtn, "TOP", header, "TOP", 0, -20)

            -- (i) next to the picker: what the page does, on hover
            local details = CreateFrame("Frame", nil, header)
            Pix.Size(details, 16, 16)
            Pix.Point(details, "LEFT", dropdownBtn, "RIGHT", 10, 0)
            details:SetFrameLevel(dropdownBtn:GetFrameLevel())
            details:SetMouseClickEnabled(false)
            details:SetMouseMotionEnabled(true)
            local infoIco = details:CreateTexture(nil, "OVERLAY")
            infoIco:SetAllPoints()
            if infoIco.SetSnapToPixelGrid then
                infoIco:SetSnapToPixelGrid(false)
                infoIco:SetTexelSnappingBias(0)
            end
            infoIco:SetTexture([[Interface\AddOns\CludesUI\media\icons\cui-info.png]])
            infoIco:SetVertexColor(1, 1, 1, 0.45)
            details:SetScript("OnEnter", function(self)
                infoIco:SetVertexColor(1, 1, 1, 0.9)
                CUI.ShowWidgetTooltip(
                    self,
                    CUI.L(
                        "Makes buttons glow when a chosen buff is active or missing, or when their ability is usable."
                    )
                )
            end)
            details:SetScript("OnLeave", function()
                infoIco:SetVertexColor(1, 1, 1, 0.45)
                CUI.HideWidgetTooltip()
            end)

            -- Button grid below dropdown
            local gridTopY = -(20 + DD_H + 20)

            local realBtnW, realBtnH = 36, 36
            if cdmBar then
                local barData = mod.barDataByKey and mod.barDataByKey[cdmBarKey]
                if barData then
                    realBtnW = barData.iconSize or 36
                    realBtnH = realBtnW
                end
                -- The live icon's on-screen size (width/height match, UI scale) in this panel's scale
                local liveW =
                    mod.BarGlowPreviewIconSize(mod.cdmBarIcons and mod.cdmBarIcons[cdmBarKey], header)
                if liveW then
                    realBtnW, realBtnH = liveW, liveW
                end
            else
                local btn1 = _G[prefixText .. "1"]
                realBtnW = (btn1 and btn1:GetWidth() or 36)
                realBtnH = (btn1 and btn1:GetHeight() or 36)
            end
            if realBtnW < 1 then realBtnW = 36 end
            if realBtnH < 1 then realBtnH = 36 end

            -- Read bar size (no scale -- width/height based)
            local buttonW = math.floor(realBtnW + 0.5)
            local scaledBtnH = math.floor(realBtnH + 0.5)

            -- CDM bar data reference (reused for shape, spacing, zoom, border)
            local barData = cdmBar and mod.barDataByKey and mod.barDataByKey[cdmBarKey] or nil

            -- Custom shape expansion
            local shapeKey
            if cdmBar then
                shapeKey = (barData and barData.iconShape) or "none"
            else
                shapeKey = (barConf and barConf.buttonShape) or "none"
            end
            if shapeKey ~= "none" and shapeKey ~= "cropped" then
                local shapeExp = 10
                buttonW = buttonW + shapeExp
                scaledBtnH = scaledBtnH + shapeExp
            end
            if shapeKey == "cropped" then
                scaledBtnH = math.floor(scaledBtnH * (cdmBar and mod.CdmCropFactor(barData) or 0.80) + 0.5)
            end

            local spacing = cdmBar and ((barData and barData.spacing) or 2)
                or ((barConf and barConf.buttonPadding) or 2)
            local scaledPad = spacing

            -- How many buttons visible
            local numVisible = NUM_BUTTONS
            if not cdmBar and barConf then
                local shade = barConf.overrideNumIcons
                if shade and shade > 0 and shade < numVisible then numVisible = shade end
            end

            -- Read zoom
            local zoom = cdmBar and ((barData and barData.iconZoom) or 0.08)
                or (((barConf and barConf.iconZoom) or 5.5) / 100)
            local square = (not cdmBar) and EAB_ADDON and EAB_ADDON.db and EAB_ADDON.db.profile.squareIcons

            -- Read border settings
            local brdSize = 0
            local brdColor, brdClassColor
            if cdmBar and barData then
                brdSize = barData.borderSize or 1
                -- This preview draws a solid border, so an exact size (borderSizePx)
                -- shows here only while the bar's style is Solid.
                local cdmTex = barData.borderTexture or "solid"
                local cdmPx = CUI.BorderPx(barData.borderSizePx, brdSize, cdmTex)
                if cdmPx and cdmTex == "solid" then brdSize = cdmPx end
                brdColor = {
                    r = barData.borderR or 0,
                    g = barData.borderG or 0,
                    b = barData.borderB or 0,
                    a = barData.borderA or 1,
                }
                brdClassColor = barData.borderClassColor
            elseif not cdmBar and barConf then
                -- None..Strong are the steps 0-4; an unknown or numeric value renders as Thin, as the bar does.
                local thickness = barConf.borderThickness or "thin"
                brdSize = CUI.BORDER_STEP_OF_LABEL[thickness] or 1
                local abTex = barConf.borderTexture or "solid"
                local abPx = CUI.BorderPx(barConf.borderThicknessPx, brdSize, abTex)
                if abPx and abTex == "solid" then brdSize = abPx end
                brdColor = barConf.borderColor
                brdClassColor = barConf.borderClassColor
            end
            if not brdColor then brdColor = { r = 0, g = 0, b = 0, a = 1 } end

            local gridW = numVisible * buttonW + (numVisible - 1) * scaledPad
            -- Live-sized CDM icons can outgrow the preview width: shrink to fit
            if cdmBar and width and width > 0 and gridW > width then
                local f = width / gridW
                buttonW = math.floor(buttonW * f)
                scaledBtnH = math.floor(scaledBtnH * f)
                scaledPad = scaledPad * f
                gridW = numVisible * buttonW + (numVisible - 1) * scaledPad
            end
            local startX = math.max(0, math.floor((width - gridW) / 2))
            local startY = gridTopY

            local UnsnapTex = CUI.PP.DisablePixelSnap

            -- Clear button frame refs from previous build
            wipe(_glowBtnFrames)

            for i = 1, NUM_BUTTONS do
                if i > numVisible then break end

                local xOff = startX + (i - 1) * (buttonW + scaledPad)
                local isSelected = (_glowSelectedButton == i)

                local barFrame = CreateFrame("Button", nil, header)
                barFrame:SetSize(buttonW, scaledBtnH)
                barFrame:SetPoint("TOPLEFT", header, "TOPLEFT", xOff, startY)
                _glowBtnFrames[i] = barFrame
                barFrame:RegisterForClicks("LeftButtonUp", "RightButtonDown")

                local bgTex = barFrame:CreateTexture(nil, "BACKGROUND")
                bgTex:SetAllPoints()
                bgTex:SetColorTexture(0.062, 0.070, 0.082, 0.5)

                -- Icon from real action button or CDM bar icon
                local realButton
                if cdmBar then
                    local cdmIcons = mod.cdmBarIcons and mod.cdmBarIcons[cdmBarKey]
                    realButton = cdmIcons and cdmIcons[i]
                    -- Native equipment frames are parked off the live bar (items
                    -- are preset-lane-only), but the icon registry can still hold
                    -- one from a prior pass -- never replicate it into the preview.
                    if
                        realButton
                        and realButton.cooldownID
                        and C_CooldownViewer
                        and C_CooldownViewer.GetCooldownViewerCooldownInfo
                    then
                        local rinfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(realButton.cooldownID)
                        if rinfo and rinfo.equipSlot then realButton = nil end
                    end
                else
                    realButton = prefixText and _G[prefixText .. i]
                end
                -- Non-glowable icons (see IsNonGlowableCDMIcon) are left inert -- no hover, clicks do nothing.
                local nonGlowable = cdmBar and IsNonGlowableCDMIcon(realButton)
                local _rbTex = realButton
                    and (
                        (mod._hookFrameData[realButton] and mod._hookFrameData[realButton].tex)
                        or realButton._tex
                    )
                local hasAction = realButton
                    and (
                        (realButton.icon and realButton.icon:GetTexture()) or (_rbTex and _rbTex:GetTexture())
                    )
                local iconTexture = barFrame:CreateTexture(nil, "ARTWORK")
                iconTexture:SetAllPoints()
                UnsnapTex(iconTexture)
                if hasAction then
                    local srcTex = (realButton.icon and realButton.icon:GetTexture())
                        or (_rbTex and _rbTex:GetTexture())
                    iconTexture:SetTexture(srcTex)
                    -- Desaturate (preview only) non-glowable icons so it's visually clear they're not assignable.
                    if nonGlowable then iconTexture:SetDesaturated(true) end
                    local z = zoom
                    if shapeKey == "cropped" then
                        local t = cdmBar and mod.CdmCropTrim(barData) or 0.10
                        iconTexture:SetTexCoord(z, 1 - z, z + t, 1 - z - t)
                    elseif z > 0 or square then
                        iconTexture:SetTexCoord(z, 1 - z, z, 1 - z)
                    else
                        iconTexture:SetTexCoord(0, 1, 0, 1)
                    end
                else
                    iconTexture:SetColorTexture(0, 0, 0, 0.5)
                end

                -- Shape mask
                local SHAPE_MASKS = cdmBar and mod.CDM_SHAPE_MASKS or AB_SHAPE_MASKS
                local SHAPE_BORDERS = cdmBar and mod.CDM_SHAPE_BORDERS or AB_SHAPE_BORDERS
                if shapeKey ~= "none" and shapeKey ~= "cropped" and SHAPE_MASKS and SHAPE_MASKS[shapeKey] then
                    local mask = barFrame:CreateMaskTexture()
                    mask:SetAllPoints(barFrame)
                    mask:SetTexture(SHAPE_MASKS[shapeKey], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    iconTexture:AddMaskTexture(mask)
                    bgTex:AddMaskTexture(mask)
                    -- Store shape metadata for glow preview (StartNativeGlow reads these)
                    barFrame._shapeApplied = true
                    barFrame._shapeName = shapeKey
                    barFrame._shapeMask = mask
                    -- Shape border (always created for hover/accent tinting; invisible when brdSize == 0)
                    if SHAPE_BORDERS and SHAPE_BORDERS[shapeKey] then
                        local sbt = barFrame:CreateTexture(nil, "OVERLAY", nil, 6)
                        sbt:SetAllPoints(barFrame)
                        sbt:SetTexture(SHAPE_BORDERS[shapeKey])
                        -- Direct ref for accent/hover tinting below. Never locate via a GetRegions
                        -- scan -- a freshly tracked CD's icon region carries secret values, and
                        -- GetDrawLayer comparisons on it error out mid page-build.
                        barFrame._sbt = sbt
                        if brdSize > 0 then
                            local cr, cg, checkBtn = brdColor.r, brdColor.g, brdColor.b
                            if brdClassColor then
                                local _, classTok = UnitClass("player")
                                if classTok then
                                    local classColor = RAID_CLASS_COLORS[classTok]
                                    if classColor then
                                        cr, cg, checkBtn = classColor.r, classColor.g, classColor.b
                                    end
                                end
                            end
                            sbt:SetVertexColor(cr, cg, checkBtn, brdColor.a or 1)
                        else
                            sbt:SetVertexColor(0, 0, 0, 0)
                        end
                    end
                elseif brdSize > 0 then
                    -- Square borders via unified PP system
                    local cr, cg, checkBtn, ca = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
                    if brdClassColor then
                        local _, classTok = UnitClass("player")
                        if classTok then
                            local classColor = RAID_CLASS_COLORS[classTok]
                            if classColor then
                                cr, cg, checkBtn = classColor.r, classColor.g, classColor.b
                            end
                        end
                    end
                    local Pix = CUI and CUI.PP
                    if Pix then Pix.CreateBorder(barFrame, cr, cg, checkBtn, ca, brdSize, "OVERLAY", 7) end
                end

                -- Accent border for buttons that have assignments
                local assignmentKey
                if cdmBar and realButton and realButton.cooldownID then
                    assignmentKey = "cdm_" .. realButton.cooldownID
                else
                    -- Per ability, so a stance's repaged bar never shares glows.
                    assignmentKey = mod.BarGlowAbilityKey(realButton) or (barIndex .. "_" .. i)
                end
                barFrame._assignKey = assignmentKey
                local assigns = bgData.assignments[assignmentKey]
                local hasAssign = assigns and #assigns > 0

                -- Pre-create accent border on every button (hidden unless needed)
                local accentHolder = CreateFrame("Frame", nil, barFrame)
                accentHolder:SetAllPoints()
                accentHolder:SetFrameLevel(barFrame:GetFrameLevel() + 2)
                local PP2 = CUI and CUI.PP

                -- Active button gets accent border; assigned (non-active) buttons get white border
                -- For custom shapes, tint the shape border instead of showing square PP borders
                local isCustomShape = shapeKey ~= "none"
                    and shapeKey ~= "cropped"
                    and shapeKey ~= "square"
                    and shapeKey ~= "csquare"
                    and SHAPE_MASKS
                    and SHAPE_MASKS[shapeKey]
                local accentEdge
                if not isCustomShape then
                    if isSelected then
                        accentEdge = PP2
                            and PP2.CreateBorder(
                                accentHolder,
                                ACCENT.r,
                                ACCENT.g,
                                ACCENT.b,
                                1,
                                2,
                                "OVERLAY",
                                7
                            )
                    else
                        accentEdge = PP2 and PP2.CreateBorder(accentHolder, 1, 1, 1, 0.6, 2, "OVERLAY", 7)
                    end
                    if accentEdge then accentEdge:Hide() end
                end

                -- Show active state
                if isSelected then
                    if isCustomShape then
                        if barFrame._sbt then
                            barFrame._sbt:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                        end
                    elseif accentEdge then
                        accentEdge:Show()
                    end
                end

                -- Show white border for assigned buttons (even if not active)
                if hasAssign and not isSelected then
                    if isCustomShape then
                        if barFrame._sbt then barFrame._sbt:SetVertexColor(1, 1, 1, 0.6) end
                    elseif accentEdge then
                        accentEdge:Show()
                    end
                end

                -- Store refs so click handler can activate inline
                barFrame._accentBrd = accentEdge
                barFrame._accentCont = accentHolder

                -- Button alpha: unassigned = 50%, assigned/active = 100%
                if isSelected or hasAssign then
                    barFrame:SetAlpha(1)
                else
                    barFrame:SetAlpha(0.50)
                end

                -- Hover swaps border to accent; active button needs none (already accent)
                barFrame._shapeBorderTex = isCustomShape and barFrame._sbt or nil
                local origBrdR, origBrdG, origBrdB, origBrdA =
                    brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
                if cdmBar and barData then
                    origBrdR = barData.borderR or 0
                    origBrdG = barData.borderG or 0
                    origBrdB = barData.borderB or 0
                    origBrdA = (barData.borderSize or 1) > 0 and (barData.borderA or 1) or 0
                elseif brdSize == 0 then
                    origBrdA = 0
                end
                if not isSelected and not nonGlowable then
                    if hasAssign then
                        barFrame:SetScript("OnEnter", function()
                            if isCustomShape and barFrame._shapeBorderTex then
                                barFrame._shapeBorderTex:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                            elseif PP2 and accentHolder then
                                PP2.SetBorderColor(accentHolder, ACCENT.r, ACCENT.g, ACCENT.b, 1)
                            end
                        end)
                        barFrame:SetScript("OnLeave", function()
                            if isCustomShape and barFrame._shapeBorderTex then
                                barFrame._shapeBorderTex:SetVertexColor(1, 1, 1, 0.6)
                            elseif PP2 and accentHolder then
                                PP2.SetBorderColor(accentHolder, 1, 1, 1, 0.6)
                            end
                        end)
                    else
                        barFrame:SetScript("OnEnter", function()
                            barFrame:SetAlpha(0.55)
                            if isCustomShape and barFrame._shapeBorderTex then
                                barFrame._shapeBorderTex:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                            else
                                if PP2 and accentHolder then
                                    PP2.SetBorderColor(accentHolder, ACCENT.r, ACCENT.g, ACCENT.b, 1)
                                end
                                if accentEdge then accentEdge:Show() end
                            end
                        end)
                        barFrame:SetScript("OnLeave", function()
                            barFrame:SetAlpha(0.50)
                            if isCustomShape and barFrame._shapeBorderTex then
                                barFrame._shapeBorderTex:SetVertexColor(
                                    origBrdR,
                                    origBrdG,
                                    origBrdB,
                                    origBrdA
                                )
                            else
                                if accentEdge then accentEdge:Hide() end
                            end
                        end)
                    end
                end

                -- Helper: visually activate this button without a full rebuild
                local function ActivateInline()
                    local PP3 = CUI and CUI.PP
                    -- Clear previous active button visuals
                    if header._activeBtnRef and header._activeBtnRef ~= barFrame then
                        local prev = header._activeBtnRef
                        -- Revert border: if prev has assignments, switch to white; otherwise hide
                        local prevKey = prev._assignKey or (barIndex .. "_" .. (prev._btnIdx or 0))
                        local prevAssigns = bgData.assignments[prevKey]
                        local prevHasAssign = prevAssigns and #prevAssigns > 0
                        if prevHasAssign then
                            if PP3 and prev._accentCont then
                                PP3.SetBorderColor(prev._accentCont, 1, 1, 1, 0.6)
                            end
                        else
                            if prev._accentBrd then prev._accentBrd:Hide() end
                            prev:SetAlpha(0.50)
                            -- Restore hover scripts
                            prev:SetScript("OnEnter", function()
                                prev:SetAlpha(0.55)
                                if PP3 and prev._accentCont then
                                    PP3.SetBorderColor(prev._accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1)
                                end
                                if prev._accentBrd then prev._accentBrd:Show() end
                            end)
                            prev:SetScript("OnLeave", function()
                                prev:SetAlpha(0.50)
                                if prev._accentBrd then prev._accentBrd:Hide() end
                            end)
                        end
                    end
                    -- Show this button as active with accent color + full alpha
                    barFrame:SetAlpha(1)
                    if PP3 and accentHolder then
                        PP3.SetBorderColor(accentHolder, ACCENT.r, ACCENT.g, ACCENT.b, 1)
                    end
                    if accentEdge then accentEdge:Show() end
                    -- Remove hover toggle since border is now permanent
                    barFrame:SetScript("OnEnter", nil)
                    barFrame:SetScript("OnLeave", nil)
                    header._activeBtnRef = barFrame
                end
                barFrame._btnIdx = i

                -- Track the initially active button
                if isSelected then header._activeBtnRef = barFrame end

                -- Left click: select this button. Right click: select + toggle spell picker.
                barFrame:SetScript("OnClick", function(self, btnFrame)
                    -- Non-glowable icons ignore both clicks so no glow can be added.
                    if nonGlowable then return end
                    local pickerOpen = _bgSpellPickerMenu and _bgSpellPickerMenu:IsShown()
                    local pickerOnThis = pickerOpen and _bgSpellPickerMenu._btnIdx == i

                    if btnFrame == "LeftButton" then
                        -- Close picker first if open (before rebuild destroys anchor)
                        if pickerOpen then _bgSpellPickerMenu:Hide() end
                        _glowSelectedButton = i
                        ActivateInline()
                        CUI:RefreshPage(true)
                    elseif btnFrame == "RightButton" then
                        if pickerOnThis then
                            _bgSpellPickerMenu:Hide()
                            return
                        end
                        if pickerOpen then _bgSpellPickerMenu:Hide() end
                        _glowSelectedButton = i
                        ActivateInline()
                        CUI:RefreshPage(true)
                        C_Timer.After(0, function()
                            local newBf = _glowBtnFrames[i]
                            if newBf then
                                ShowBarGlowSpellPicker(newBf, barIndex, i, function()
                                    _glowSelectedButton = i
                                    CUI:RefreshPage(true)
                                end, newBf._assignKey)
                            end
                        end)
                    end
                end)
            end

            -- Tip text below the button grid
            local tipFS = header:CreateFontString(nil, "OVERLAY")
            tipFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            tipFS:SetTextColor(1, 1, 1, 0.70)
            tipFS:SetPoint("TOP", header, "TOP", 0, -(20 + DD_H + 20 + scaledBtnH + 20))
            tipFS:SetText(CUI.L("Left click a button to edit its glow, right click to add a new glow"))

            return 20 + DD_H + 20 + scaledBtnH + 20 + 14 + 15
        end

        CUI:SetContentHeader(_glowHeaderBuilder)

        -- Live-updates the preview on action-bar paging (glowLive above): listening from
        -- now on, again whenever this page shows, never while it is hidden. Skipped
        -- during a hidden search pre-build: nothing to preview while indexing.
        if not CUI._prebuilding then
            if not glowPreview.frame then
                glowPreview.frame = CreateFrame("Frame")
                glowPreview.frame:SetScript("OnEvent", glowPreview.OnEvent)
            end
            if hostFrame:IsVisible() then glowPreview.Arm() end
            hostFrame:HookScript("OnShow", glowPreview.Arm)
            hostFrame:HookScript("OnHide", glowPreview.Disarm)
        end

        -------------------------------------------------------------------
        --  Scrollable content area
        -------------------------------------------------------------------

        _, height = W:Spacer(hostFrame, cursorY, 8)
        cursorY = cursorY - height

        -- A selected slot that is (now) non-glowable shows no glow settings (the header tip stays).
        if curBtn and type(curBar) == "string" then
            local cdmIcons = mod.cdmBarIcons and mod.cdmBarIcons[curBar]
            if IsNonGlowableCDMIcon(cdmIcons and cdmIcons[curBtn]) then curBtn = nil end
        end

        -- No selection: the tip under the button grid is the only hint
        if curBtn then
            local assignmentKey, cdmSid
            local isCurCDM = (type(curBar) == "string")
            if isCurCDM then
                local cdmIcons = mod.cdmBarIcons and mod.cdmBarIcons[curBar]
                local icon = cdmIcons and cdmIcons[curBtn]
                if icon and icon.cooldownID then
                    assignmentKey = "cdm_" .. icon.cooldownID
                    cdmSid = mod.BarGlowButtonSpell(icon)
                end
            end
            if not assignmentKey then
                local prefixText = BAR_BUTTON_PREFIXES[curBar]
                local curRealBtn = prefixText and _G[prefixText .. curBtn]
                assignmentKey = mod.BarGlowAbilityKey(curRealBtn) or (curBar .. "_" .. curBtn)
            end
            local buffList = backdrop.assignments[assignmentKey] or {}
            hostFrame._showRowDivider = true

            if #buffList == 0 then
                _, height = W:Spacer(hostFrame, cursorY, 8)
                cursorY = cursorY - height
                local emptyFrame = CreateFrame("Frame", nil, hostFrame)
                emptyFrame:SetSize(hostFrame:GetWidth(), 30)
                emptyFrame:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, cursorY)
                local emptyText = emptyFrame:CreateFontString(nil, "OVERLAY")
                emptyText:SetFont(FONT_PATH, 12, GetCDMOptOutline())
                emptyText:SetTextColor(0.5, 0.5, 0.5, 1)
                emptyText:SetPoint("LEFT", 22, 0)
                emptyText:SetText(
                    CUI.L("No buffs assigned. Right click a button in the preview to assign buffs.")
                )
                cursorY = cursorY - 30
            else
                local glowLabels, glowOrder = GetGlowStyleValues()

                for aIdx, record in ipairs(buffList) do
                    -- Collapse bar across the top of the glow; collapsed shows the buff
                    -- icon and name and skips the rows below.
                    local expanded
                    cursorY, expanded = mod.BuildBarGlowHeader(hostFrame, cursorY, record, aIdx, cdmSid)
                    if expanded then
                        -- Row 1: When (icon) <buff> is [Active] | And [buff] is [Active] (toggle)
                        -- (CUI_CooldownManager_BarGlowConditions.lua)
                        local removeAIdx = aIdx
                        cursorY = mod.BuildBarGlowWhenRow(W, hostFrame, cursorY, record, ApplyCDM, cdmSid)

                        -- Helper: resolve current glow color and restart preview if active
                        local pvKey = assignmentKey .. "_" .. aIdx
                        local function SyncPreviewGlow()
                            if not _bgPreviewGlowActive[pvKey] then return end
                            local shade = _bgPreviewGlowOverlays[pvKey]
                            if not shade then return end
                            local style = BarHasCustomShape(curBar) and 2 or (record.glowStyle or 1)
                            local cr, cg, checkBtn
                            if record.colorMode == "class" then
                                local classColor = CUI.GetClassColor(CUI._playerClass)
                                cr, cg, checkBtn = classColor.r, classColor.g, classColor.b
                            elseif record.colorMode == "custom" and record.glowColor then
                                cr, cg, checkBtn = record.glowColor.r, record.glowColor.g, record.glowColor.b
                            end
                            mod.StopNativeGlow(shade)
                            -- Blackout reads its fill opacity from the extras; every other
                            -- style takes the shared panel extras.
                            mod.StartNativeGlow(
                                shade,
                                style,
                                cr,
                                cg,
                                checkBtn,
                                style == 8 and { panel = true, alpha = record.glowAlpha }
                                    or CUI.Glows.PANEL_EXTRA
                            )
                        end

                        -- At Stacks (toggle) + gear (Comparison / Stack Count), paired with
                        -- Glow Type so every row stays filled. Same operator set and same
                        -- fail-open bias as the per-icon Glow at Stacks feature (Stack Text
                        -- and Glows cog): an unknown/secret application count never blocks
                        -- the glow.
                        local stackRow
                        stackRow, height = W:DualRow(hostFrame, cursorY, {
                            type = "toggle",
                            text = "At Stacks",
                            tooltip = "Only glow once the buff's stack count matches the comparison set via the gear.",
                            disabled = function() return record.mode == "MISSING" or record.mode == "USABLE" end,
                            disabledTooltip = "Only available for a buff in Active mode",
                            getValue = function() return record.stackEnabled == true end,
                            setValue = function(val)
                                record.stackEnabled = val or nil
                                ApplyCDM()
                                CUI:RefreshPage()
                            end,
                        }, {
                            type = "dropdown",
                            text = "Glow Type",
                            values = glowLabels,
                            order = glowOrder,
                            disabled = function() return BarHasCustomShape(curBar) end,
                            disabledTooltip = "This option is not available for custom shaped icons",
                            getValue = function()
                                if BarHasCustomShape(curBar) then return 2 end
                                return record.glowStyle or 1
                            end,
                            setValue = function(val)
                                record.glowStyle = tonumber(val) or 1
                                ApplyCDM()
                                SyncPreviewGlow()
                                CUI:RefreshPage()
                            end,
                        })
                        cursorY = cursorY - height
                        do
                            local region = stackRow._leftRegion
                            CUI.BuildInlineCog(region, {
                                title = "At Stacks",
                                disabled = function()
                                    return record.mode == "MISSING"
                                        or record.mode == "USABLE"
                                        or not record.stackEnabled
                                end,
                                disabledTooltip = function()
                                    if record.mode == "MISSING" then
                                        return "This option is not available in Buff Missing mode"
                                    end
                                    if record.mode == "USABLE" then
                                        return "This option is not available in Glow When Usable mode"
                                    end
                                    return "At Stacks"
                                end,
                                frameStrata = "FULLSCREEN_DIALOG",
                                frameLevel = 350,
                                rows = {
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
                                        get = function() return record.stackOperator or "gte" end,
                                        set = function(val)
                                            record.stackOperator = val ~= "gte" and val or nil
                                            ApplyCDM()
                                        end,
                                    },
                                    {
                                        type = "input",
                                        label = "Stack Count",
                                        inputWidth = 42,
                                        commitOnBlur = true,
                                        get = function()
                                            return tostring(tonumber(record.stackThreshold) or 2)
                                        end,
                                        set = function(val)
                                            local t = math.floor(tonumber(val) or 2)
                                            if t < 1 then t = 1 end
                                            if t > 99 then t = 99 end
                                            record.stackThreshold = t
                                            ApplyCDM()
                                        end,
                                    },
                                },
                            })
                        end

                        -- Eyeball preview toggle (on right region of the At Stacks / Glow Type row)
                        if not CUI._prebuilding then
                            local EYE_VIS = CUI.EYE_VISIBLE_ICON
                            local EYE_INVIS = CUI.EYE_INVISIBLE_ICON
                            local leftRegion = stackRow._rightRegion
                            if leftRegion and leftRegion._control then
                                local eyeButton = CreateFrame("Button", nil, leftRegion)
                                eyeButton:SetSize(26, 26)
                                eyeButton:SetPoint("RIGHT", leftRegion._control, "LEFT", -8, 0)
                                eyeButton:SetFrameLevel(leftRegion:GetFrameLevel() + 5)
                                CUI.SetGlyphAlpha(eyeButton, 0.4)
                                local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
                                eyeTex:SetAllPoints()
                                local function RefreshEye()
                                    eyeTex:SetTexture(_bgPreviewGlowActive[pvKey] and EYE_INVIS or EYE_VIS)
                                end
                                RefreshEye()
                                eyeButton:SetScript("OnClick", function()
                                    local previewBtn = _glowBtnFrames[curBtn]
                                    if not previewBtn then return end
                                    if not _bgPreviewGlowOverlays[pvKey] then
                                        local shade = CreateFrame("Frame", nil, previewBtn)
                                        shade:SetAllPoints(previewBtn)
                                        shade:SetFrameLevel(previewBtn:GetFrameLevel() + 10)
                                        shade._cuiGlowPreview = true -- exempt from Show Glows Only in Combat
                                        _bgPreviewGlowOverlays[pvKey] = shade
                                    end
                                    local shade = _bgPreviewGlowOverlays[pvKey]
                                    if _bgPreviewGlowActive[pvKey] then
                                        mod.StopNativeGlow(shade)
                                        _bgPreviewGlowActive[pvKey] = false
                                        -- Restore accent border
                                        if previewBtn._accentBrd then previewBtn._accentBrd:Show() end
                                    else
                                        local style = BarHasCustomShape(curBar) and 2
                                            or (record.glowStyle or 1)
                                        local cr, cg, checkBtn
                                        if record.colorMode == "class" then
                                            local classColor = CUI.GetClassColor(CUI._playerClass)
                                            cr, cg, checkBtn = classColor.r, classColor.g, classColor.b
                                        elseif record.colorMode == "custom" and record.glowColor then
                                            cr, cg, checkBtn =
                                                record.glowColor.r, record.glowColor.g, record.glowColor.b
                                        end
                                        mod.StartNativeGlow(
                                            shade,
                                            style,
                                            cr,
                                            cg,
                                            checkBtn,
                                            style == 8 and { panel = true, alpha = record.glowAlpha }
                                                or CUI.Glows.PANEL_EXTRA
                                        )
                                        _bgPreviewGlowActive[pvKey] = true
                                        -- Hide accent border so glow is visible
                                        if previewBtn._accentBrd then previewBtn._accentBrd:Hide() end
                                    end
                                    RefreshEye()
                                end)
                                eyeButton:SetScript(
                                    "OnEnter",
                                    function(self) CUI.SetGlyphAlpha(self, 0.7) end
                                )
                                eyeButton:SetScript(
                                    "OnLeave",
                                    function(self) CUI.SetGlyphAlpha(self, 0.4) end
                                )

                                -- Blackout fill opacity, in a cog chained left of the eye. Locked
                                -- unless the entry renders Blackout (custom-shaped bars always
                                -- draw Shape Glow); the Glow Type setter's page refresh re-checks it.
                                leftRegion._lastInline = eyeButton
                                CUI.BuildInlineCog(leftRegion, {
                                    title = "Blackout",
                                    disabled = function()
                                        return (BarHasCustomShape(curBar) and 2 or (record.glowStyle or 1))
                                            ~= 8
                                    end,
                                    disabledTooltip = function()
                                        return BarHasCustomShape(curBar)
                                                and "This option is not available for custom shaped icons"
                                            or "This option requires the Blackout glow type"
                                    end,
                                    frameStrata = "FULLSCREEN_DIALOG",
                                    frameLevel = 350,
                                    rows = {
                                        {
                                            type = "slider",
                                            label = "Opacity",
                                            min = 1,
                                            max = 100,
                                            step = 1,
                                            get = function()
                                                return math.floor((record.glowAlpha or 1) * 100 + 0.5)
                                            end,
                                            set = function(val)
                                                record.glowAlpha = val / 100
                                                -- Restarts the lit Bar Glows with the new opacity (fires
                                                -- per drag step, so no full CDM rebuild here).
                                                if mod.RequestBarGlowUpdate then
                                                    mod.RequestBarGlowUpdate()
                                                end
                                                SyncPreviewGlow()
                                            end,
                                        },
                                    },
                                })
                            end
                        end

                        -- Retail: Only In Combat | Hero Talent, then Glow Color (swatches) |
                        -- (icon) [Duplicate] [Remove]. WoW Forever has no Hero Talent half,
                        -- so the slots re-pair there: Only In Combat | Glow Color, then the
                        -- buttons in the left half of the last row.
                        local glowColorCfg = { type = "label", text = "Glow Color" }
                        local removeCfg = {
                            type = "labeledButton",
                            text = "",
                            buttonText = "Remove",
                            width = 150,
                            onClick = function()
                                table.remove(buffList, removeAIdx)
                                if #buffList == 0 then backdrop.assignments[assignmentKey] = nil end
                                ApplyCDM()
                                CUI:RefreshPage(true)
                            end,
                        }
                        local colorRow, colorRgn, removeRgn
                        if CUI.IS_FOREVER then
                            colorRow, height = W:DualRow(
                                hostFrame,
                                cursorY,
                                mod.BarGlowCombatCfg(record, ApplyCDM),
                                glowColorCfg
                            )
                            cursorY = cursorY - height
                            colorRgn = colorRow._rightRegion
                            local removeRow
                            removeRow, height =
                                W:DualRow(hostFrame, cursorY, removeCfg, CUI.BlankRowCfg())
                            cursorY = cursorY - height
                            removeRgn = removeRow._leftRegion
                        else
                            cursorY = mod.BuildBarGlowCombatRow(W, hostFrame, cursorY, record, ApplyCDM)
                            colorRow, height = W:DualRow(hostFrame, cursorY, glowColorCfg, removeCfg)
                            cursorY = cursorY - height
                            colorRgn, removeRgn = colorRow._leftRegion, colorRow._rightRegion
                        end

                        -- Inline color swatch for glow color
                        if not CUI._prebuilding then
                            local leftRegion = colorRgn
                            if leftRegion and CUI.BuildTrioColorSwatch then
                                local glowSwatch, defaultSwatch, classSwatch =
                                    CUI.BuildTrioColorSwatch(leftRegion, colorRow:GetFrameLevel() + 3, {
                                        getMode = function() return record.colorMode or "default" end,
                                        setMode = function(m) record.colorMode = m end,
                                        getCustomRGB = function()
                                            local color = record.glowColor
                                                or { r = 1.0, g = 0.788, b = 0.137 }
                                            return color.r, color.g, color.b
                                        end,
                                        setCustomRGB = function(red, green, blue)
                                            record.glowColor = { r = red, g = green, b = blue }
                                        end,
                                        hasClassColor = true,
                                        onChange = function()
                                            ApplyCDM()
                                            SyncPreviewGlow()
                                            CUI:RefreshPage()
                                        end,
                                        overrideSize = 20,
                                    })
                                Pix.Point(classSwatch, "RIGHT", leftRegion, "RIGHT", -20, 0)
                                Pix.Point(glowSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
                                Pix.Point(defaultSwatch, "RIGHT", glowSwatch, "LEFT", -8, 0)
                            end
                        end

                        -- Duplicate, then the buff icon (spell tooltip on hover), LEFT of Remove
                        if not CUI._prebuilding then
                            local rightRegion = removeRgn
                            if rightRegion and rightRegion._control then
                                local button = rightRegion._control
                                local dupBtn = mod.BarGlowDuplicateButton(
                                    rightRegion,
                                    button,
                                    buffList,
                                    aIdx,
                                    function()
                                        ApplyCDM()
                                        CUI:RefreshPage(true)
                                    end
                                )
                                local ico = mod.BarGlowSpellIcon(
                                    rightRegion,
                                    button:GetHeight(),
                                    record.mode == "USABLE" and (record.actionSpellID or cdmSid)
                                        or record.spellID
                                )
                                Pix.Point(ico, "RIGHT", dupBtn or button, "LEFT", -8, 0)
                            end
                        end
                    end
                end
            end
        end

        return math.abs(cursorY)
    end

    -- Tracking Bars page with its state and hooks (CooldownManager_Options\
    -- BuffBarsPage_Options.lua), set up here so the hooks keep their order.
    local BuildBuffBarsPage, RefreshTBBPopout = mod.CDMO_InitBuffBarsPage(
        Pix,
        DB,
        ApplyCDM,
        FONT_PATH,
        GetCDMOptOutline,
        GateBlizzardOnly,
        PAGE_BUFF_BARS
    )

    ---------------------------------------------------------------------------
    --  CDM Bars page
    ---------------------------------------------------------------------------
    -- Mutable state shared with the pickers and page builders under
    -- CooldownManager_Options\. A table instead of locals so every file reads
    -- and writes the live value.
    local optionState = {}
    local growValues = CUI.GROW_DIR_VALUES_BASE
    local growOrder = { "RIGHT", "LEFT", "DOWN", "UP" } -- this dropdown's own sequence (DOWN before UP)
    local durationPositionValues = {
        center = "Center",
        top = "Above Icon",
        bottom = "Below Icon",
        left = "Left of Icon",
        right = "Right of Icon",
    }
    local durationPositionOrder = { "center", "top", "bottom", "left", "right" }

    -- Track which bar is selected in the CDM Bars tab
    optionState.selectedCDMBarIndex = 1

    -- Deep-link helper: select a CDM bar by key or barType (used by the What's
    -- New "Always Show Buffs" card preSelect -- that per-bar toggle only renders
    -- when a buff-family bar is selected). Sets the index immediately, like
    -- CludesUI._setUnitFrameUnit, so header and rebuilt page both reflect it.
    function CUI._setCDMBar(keyOrType)
        local profile = DB()
        local barList = profile and profile.cdmBars and profile.cdmBars.bars
        if not barList then return end
        for bi, bb in ipairs(barList) do
            if bb.key == keyOrType or bb.barType == keyOrType then
                optionState.selectedCDMBarIndex = bi
                return
            end
        end
    end

    -- CDM Bars preview state, nil until built: optState._cdmPreview is the
    -- preview frame, optState._cdmHeaderBuilder the content header builder
    optionState._cdmHeaderFixedH = 0

    -- CludesUI._cdmHeaderPreview: this module's own header preview slot (the
    -- Action Bars preview, kept alive by its own header, never answers here).
    local function UpdateCDMPreview()
        if not optionState._cdmPreview and CUI._cdmHeaderPreview then
            optionState._cdmPreview = CUI._cdmHeaderPreview
        end
        if optionState._cdmPreview and optionState._cdmPreview.Update then
            optionState._cdmPreview:Update()
        end
    end

    local function UpdateCDMPreviewAndResize()
        UpdateCDMPreview()
        if optionState._cdmPreview and optionState._cdmHeaderFixedH > 0 then
            -- Wrapper height is already capped by the Update function's resize logic
            local wrapperH = optionState._cdmPreview._wrapper and optionState._cdmPreview._wrapper:GetHeight()
                or math.min(
                    optionState._cdmPreview:GetHeight() * (optionState._cdmPreview:GetScale() or 1),
                    200
                )
            CUI:UpdateContentHeaderHeight(optionState._cdmHeaderFixedH + wrapperH)
        end
    end

    -- Panel shown, or unfolded from its mini window (the panel stayed shown
    -- while folded, so no show callback runs then): the CDM Bars preview
    -- catches up on what it skipped while hidden, only while it shows (a page
    -- left behind keeps its preview, hidden, and brings it up to date as it
    -- shows again: onPageCacheRestore).
    local function CatchUpCDMPreview()
        local preview = optionState._cdmPreview or CUI._cdmHeaderPreview
        if preview and preview:IsVisible() then UpdateCDMPreview() end
    end
    CUI:RegisterOnShow(CatchUpCDMPreview)
    CUI:RegisterOnCollapse(function(on)
        if not on then CatchUpCDMPreview() end
    end)

    -- Refresh our preview when user closes Blizzard's CDM settings panel
    -- (they may have added/removed spells from the viewer)
    if CooldownViewerSettings then
        CooldownViewerSettings:HookScript("OnHide", function()
            C_Timer.After(0.3, function()
                if CUI._mainFrame and CUI._mainFrame:IsShown() then CUI:RefreshPage(true) end
            end)
        end)
    end

    --- Get the currently selected CDM bar data
    local function SelectedCDMBar()
        local profile = DB()
        if not profile or not profile.cdmBars or not profile.cdmBars.bars then return nil end
        local barList = profile.cdmBars.bars
        if optionState.selectedCDMBarIndex < 1 then optionState.selectedCDMBarIndex = 1 end
        if optionState.selectedCDMBarIndex > #barList then optionState.selectedCDMBarIndex = #barList end
        return barList[optionState.selectedCDMBarIndex]
    end

    -- Active state preview on first icon
    local _cdmActivePreviewOn = false
    local _cdmActivePreviewOverlay = nil -- glow overlay frame on first preview slot
    local _cdmActivePreviewToken = 0 -- incremented each start to invalidate stale timers

    local function StopActiveStatePreview()
        if _cdmActivePreviewOverlay then mod.StopNativeGlow(_cdmActivePreviewOverlay) end
        -- Stop fake cooldown on preview slot
        if optionState._cdmPreview and optionState._cdmPreview._previewSlots then
            local slotFrame = optionState._cdmPreview._previewSlots[1]
            if slotFrame and slotFrame._previewCD then
                slotFrame._previewCD:Clear()
                slotFrame._previewCD:Hide()
            end
        end
    end

    local function StartActiveStatePreview()
        if not _cdmActivePreviewOn then return end
        _cdmActivePreviewToken = _cdmActivePreviewToken + 1
        local myToken = _cdmActivePreviewToken
        local edge = SelectedCDMBar()
        if not edge then return end
        local anim = edge.activeStateAnim or "blizzard"
        if not optionState._cdmPreview or not optionState._cdmPreview._previewSlots then return end
        local slotFrame = optionState._cdmPreview._previewSlots[1]
        if not slotFrame or not slotFrame:IsShown() then return end

        -- Ensure cooldown widget exists on preview slot
        if not slotFrame._previewCD then
            local cdFrame = CreateFrame("Cooldown", nil, slotFrame, "CooldownFrameTemplate")
            cdFrame:SetAllPoints()
            cdFrame:SetDrawEdge(false)
            cdFrame:SetDrawSwipe(true)
            cdFrame:SetDrawBling(false)
            cdFrame:SetReverse(false)
            cdFrame:SetHideCountdownNumbers(false)
            -- Blizzard Style: the viewer's rounded swipe, matching its mask
            -- (classic icons are square and keep the plain swipe).
            cdFrame:SetSwipeTexture(
                (CUI.BlizzStyle.Active("cdmicons") == "blizzard" and mod.CDM_BLIZZ_SWIPE)
                    or "Interface\\Buttons\\WHITE8x8"
            )
            if cdFrame.SetSnapToPixelGrid then
                cdFrame:SetSnapToPixelGrid(false)
                cdFrame:SetTexelSnappingBias(0)
            end
            slotFrame._previewCD = cdFrame
        end

        -- The timers below stand down once the preview slot was dressed again
        -- for a rebuilt preview (page reuse): its state belongs to that build.
        local slotGen = PoolGen(slotFrame)
        -- Always refresh font (smaller than the bar's cooldown font size, shadow style)
        C_Timer.After(0, function()
            if PoolGen(slotFrame) ~= slotGen or not slotFrame._previewCD then return end
            local fSize = (edge.cooldownFontSize or 12) - 2
            if fSize < 6 then fSize = 6 end
            local fontFile = (CUI.GetFontPath("cdm")) or STANDARD_TEXT_FONT
            for _, regionFrame in ipairs({ slotFrame._previewCD:GetRegions() }) do
                if regionFrame:GetObjectType() == "FontString" then
                    SetPVFont(regionFrame, fontFile, fSize)
                    if mod.AnchorCooldownText then
                        mod.AnchorCooldownText(
                            regionFrame,
                            slotFrame._previewCD,
                            edge.cooldownTextPosition or "center",
                            edge.cooldownTextX or 0,
                            edge.cooldownTextY or 0
                        )
                    end
                    break
                end
            end
        end)

        -- Ensure glow overlay exists
        if not slotFrame._glowOverlay then
            local shade = CreateFrame("Frame", nil, slotFrame)
            shade:SetAllPoints(slotFrame)
            -- Above the Blizzard Style ring (+15) as on the live icons (+16).
            shade:SetFrameLevel(slotFrame:GetFrameLevel() + (CUI.BlizzStyle.Get("cdmicons") and 16 or 3))
            shade:SetAlpha(0)
            shade._cuiGlowPreview = true -- exempt from Show Glows Only in Combat
            slotFrame._glowOverlay = shade
        end
        _cdmActivePreviewOverlay = slotFrame._glowOverlay

        -- Resolve active animation color
        local animR, animG, animB = 1.0, 0.85, 0.0
        if edge.activeAnimClassColor then
            local _, classTok = UnitClass("player")
            if classTok then
                local classColor = RAID_CLASS_COLORS[classTok]
                if classColor then
                    animR, animG, animB = classColor.r, classColor.g, classColor.b
                end
            end
        elseif edge.activeAnimR then
            animR = edge.activeAnimR
            animG = edge.activeAnimG or 0.85
            animB = edge.activeAnimB or 0.0
        end

        local swAlpha = edge.swipeAlpha or 0.7
        local PREVIEW_DURATION = 5 -- seconds

        if anim == "none" then
            slotFrame._previewCD:SetSwipeColor(0, 0, 0, swAlpha)
            slotFrame._previewCD:SetCooldown(GetTime(), PREVIEW_DURATION)
            slotFrame._previewCD:Show()
            mod.StopNativeGlow(_cdmActivePreviewOverlay)
        else
            slotFrame._previewCD:SetSwipeColor(animR, animG, animB, swAlpha)
            slotFrame._previewCD:SetCooldown(GetTime(), PREVIEW_DURATION)
            slotFrame._previewCD:Show()

            if anim ~= "blizzard" then
                local glowIdx = tonumber(anim)
                if glowIdx then
                    mod.StartNativeGlow(
                        _cdmActivePreviewOverlay,
                        glowIdx,
                        animR,
                        animG,
                        animB,
                        CUI.Glows.PANEL_EXTRA
                    )
                end
            else
                mod.StopNativeGlow(_cdmActivePreviewOverlay)
            end
        end

        -- Auto-stop glow after preview duration ends
        C_Timer.After(PREVIEW_DURATION, function()
            if myToken ~= _cdmActivePreviewToken or PoolGen(slotFrame) ~= slotGen then return end
            if _cdmActivePreviewOverlay then mod.StopNativeGlow(_cdmActivePreviewOverlay) end
            if slotFrame._previewCD then
                slotFrame._previewCD:Clear()
                slotFrame._previewCD:Hide()
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Spell picker dropdown (right-click on icon or click "+" button)
    ---------------------------------------------------------------------------
    -- Close the spell picker when the main CUI options panel closes
    CUI:RegisterOnHide(function()
        if optionState._spellPickerMenu and optionState._spellPickerMenu:IsShown() then
            optionState._spellPickerMenu:Hide()
        end
    end)
    -- Normalize a spell ID to its base (undo talent overrides), and resolve
    -- a base id to its current live version (talent overrides) -- both
    -- delegate to the resident module (CludesUICdmSpellPicker.lua) so
    -- every consumer, including the resident keep/drop reconcile pass,
    -- shares one implementation instead of a second local copy drifting out of sync.
    local NormalizeToBase = mod.NormalizeToBase
    local ResolveToLive = mod.ResolveToLive

    -- Texture-only sibling: tracked-buff slots hold AURA ids, which carry no override
    -- when a talent replaces the spell, so the icon needs the shared resolver's spellbook
    -- bridge (+ the slot's cdID to reach linked replacement ids). Deliberately NOT folded
    -- into ResolveToLive, which also feeds learned-state/catalog membership tests (incl.
    -- the keep/drop pass) -- a bridged id there could drop a spell from a saved bar.
    -- Only the art moves; identity stays untouched.
    local function ResolveIconArt(spellRef, cdID)
        if not spellRef or spellRef <= 0 then return spellRef end
        if mod.LustPresetIconSpellID then spellRef = mod.LustPresetIconSpellID(spellRef) end
        if mod.ResolvePlaceholderIconSID then
            local live = mod.ResolvePlaceholderIconSID(spellRef, cdID)
            if type(live) == "number" and live > 0 then return live end
        end
        return ResolveToLive(spellRef)
    end

    -- Keybind color swatch and text cog on a Show Keybind row. lockTip
    -- (optional): why the whole row is locked, nil while it is live; the
    -- swatch and cog give that reason first, then Show Keybind.
    local function BuildKeybindStyleControls(kbRow, BD, RefreshKeybindStyle, lockTip)
        if not CUI._prebuilding then
            local region = kbRow._rightRegion
            local kbFonts, kbFontOrder = CUI.BuildFontDropdownData()
            kbFonts.__global = { text = "CDM Font" }
            local function DisabledTip()
                local tipText = lockTip and lockTip()
                if tipText then return tipText end
                if BD().showKeybind ~= true then return "Show Keybind" end
            end

            CUI.BuildInlineCog(region, {
                title = "Keybind Text Settings",
                disabled = function() return DisabledTip() ~= nil end,
                disabledTooltip = DisabledTip,
                rows = {
                    {
                        type = "dropdown",
                        label = "Font",
                        values = kbFonts,
                        order = kbFontOrder,
                        get = function() return BD().keybindFont or "__global" end,
                        set = function(val)
                            BD().keybindFont = val
                            RefreshKeybindStyle()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Text Outline",
                        values = {
                            inherit = "CDM Outline",
                            NONE = "None",
                            OUTLINE = "Outline",
                            THICKOUTLINE = "Thick Outline",
                        },
                        order = { "inherit", "NONE", "OUTLINE", "THICKOUTLINE" },
                        get = function() return BD().keybindOutline or "inherit" end,
                        set = function(val)
                            BD().keybindOutline = val
                            RefreshKeybindStyle()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 20,
                        step = 1,
                        get = function() return BD().keybindSize or 10 end,
                        set = function(val)
                            BD().keybindSize = val
                            RefreshKeybindStyle()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Anchor",
                        values = {
                            TOPLEFT = "Top Left",
                            TOP = "Top",
                            TOPRIGHT = "Top Right",
                            LEFT = "Left",
                            CENTER = "Center",
                            RIGHT = "Right",
                            BOTTOMLEFT = "Bottom Left",
                            BOTTOM = "Bottom",
                            BOTTOMRIGHT = "Bottom Right",
                        },
                        order = {
                            "TOPLEFT",
                            "TOP",
                            "TOPRIGHT",
                            "LEFT",
                            "CENTER",
                            "RIGHT",
                            "BOTTOMLEFT",
                            "BOTTOM",
                            "BOTTOMRIGHT",
                        },
                        get = function()
                            return BD().keybindAnchor
                                or (BD().keybindAlign == "right" and "TOPRIGHT" or "TOPLEFT")
                        end,
                        set = function(val)
                            BD().keybindAnchor = val
                            RefreshKeybindStyle()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -30,
                        max = 30,
                        step = 1,
                        get = function() return BD().keybindOffsetX or 2 end,
                        set = function(val)
                            BD().keybindOffsetX = val
                            RefreshKeybindStyle()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -30,
                        max = 30,
                        step = 1,
                        get = function() return BD().keybindOffsetY or -2 end,
                        set = function(val)
                            BD().keybindOffsetY = val
                            RefreshKeybindStyle()
                        end,
                    },
                    {
                        type = "colorpicker",
                        label = "Background Color",
                        hasAlpha = true,
                        tooltip = "Set opacity to 0% for text without a background.",
                        get = function()
                            return BD().keybindBackgroundR or 0,
                                BD().keybindBackgroundG or 0,
                                BD().keybindBackgroundB or 0,
                                BD().keybindBackgroundA or 0
                        end,
                        set = function(red, green, blue, a)
                            local d = BD()
                            d.keybindBackgroundR = red
                            d.keybindBackgroundG = green
                            d.keybindBackgroundB = blue
                            d.keybindBackgroundA = a
                            RefreshKeybindStyle()
                        end,
                    },
                    {
                        type = "colorpicker",
                        label = "Border Color",
                        hasAlpha = true,
                        tooltip = "Set opacity to 0% to hide the keybind badge border.",
                        get = function()
                            return BD().keybindBorderR or 1,
                                BD().keybindBorderG or 1,
                                BD().keybindBorderB or 1,
                                BD().keybindBorderA or 0
                        end,
                        set = function(red, green, blue, a)
                            local d = BD()
                            d.keybindBorderR = red
                            d.keybindBorderG = green
                            d.keybindBorderB = blue
                            d.keybindBorderA = a
                            RefreshKeybindStyle()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Border Size",
                        min = 0,
                        max = 4,
                        step = 1,
                        get = function() return BD().keybindBorderSize or 1 end,
                        set = function(val)
                            BD().keybindBorderSize = val
                            RefreshKeybindStyle()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Background Padding",
                        min = 0,
                        max = 8,
                        step = 1,
                        get = function() return BD().keybindPadding or 2 end,
                        set = function(val)
                            BD().keybindPadding = val
                            RefreshKeybindStyle()
                        end,
                    },
                    -- Global, not per-bar: there is one shared keybind cache
                    -- for every CDM bar, so this toggle is labelled as such.
                    {
                        type = "toggle",
                        label = "Keep Keys on Bar Swap (global)",
                        tooltip = 'Keep keybind text identical when your action bar swaps -- rogue stealth, druid forms, skyriding. Also covers conditional macros like "/cast [bonusbar:1] Backstab; Shadow Dance", where the key would otherwise jump to whichever branch is live.\n\nThe key then only changes when you actually move the ability or rebind it.\n\nOn by default. Applies to every CDM bar at once.',
                        get = function()
                            local profile = DB()
                            return (profile and profile.cdmBars and profile.cdmBars.stableKeybinds) == true
                        end,
                        set = function(val)
                            local profile = DB()
                            if not profile or not profile.cdmBars then return end
                            profile.cdmBars.stableKeybinds = val and true or false
                            -- Changes how the cache is built, not just how it is
                            -- drawn -- needs a full rebuild, not an apply pass.
                            if mod.UpdateCDMKeybinds then mod.UpdateCDMKeybinds() end
                            RefreshKeybindStyle()
                        end,
                    },
                },
            })

            local kbSwatch, updateKbSwatch = CUI.BuildColorSwatch(
                region,
                kbRow:GetFrameLevel() + 3,
                function()
                    return BD().keybindR or 1, BD().keybindG or 1, BD().keybindB or 1, BD().keybindA or 0.9
                end,
                function(red, green, blue, a)
                    BD().keybindR = red
                    BD().keybindG = green
                    BD().keybindB = blue
                    BD().keybindA = a
                    RefreshKeybindStyle()
                end,
                true,
                20
            )
            Pix.Point(kbSwatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = kbSwatch

            local swatchBlock = CUI.NewSwatchBlocker(kbSwatch)
            swatchBlock:SetScript("OnEnter", function()
                local tipText = DisabledTip()
                if tipText then CUI.ShowWidgetTooltip(kbSwatch, CUI.DisabledTooltip(tipText)) end
            end)
            swatchBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            local function SwatchState()
                updateKbSwatch()
                local on = DisabledTip() == nil
                kbSwatch:SetAlpha(on and 1 or 0.3)
                swatchBlock:SetShown(not on)
            end
            CUI.RegisterWidgetRefresh(SwatchState)
            SwatchState()
        end
    end

    -- Shared helpers for the pickers and page builders under
    -- CooldownManager_Options\ (loaded before this file, read when a picker
    -- opens or a page is built).
    mod._CDMO_OptEnv = {
        _cdmActivePreviewOn = _cdmActivePreviewOn,
        AnyIconAlwaysShowOn = AnyIconAlwaysShowOn,
        BuildKeybindStyleControls = BuildKeybindStyleControls,
        DB = DB,
        durationPositionOrder = durationPositionOrder,
        durationPositionValues = durationPositionValues,
        FitMenuWidth = FitMenuWidth,
        FONT_PATH = FONT_PATH,
        GetCDMOptOutline = GetCDMOptOutline,
        NormalizeToBase = NormalizeToBase,
        optState = optionState,
        PP = Pix,
        Refresh = ApplyCDM,
        RefreshCDPreview = RefreshCDPreview,
        ResolveIconArt = ResolveIconArt,
        ResolveToLive = ResolveToLive,
        SelectedCDMBar = SelectedCDMBar,
        SetPVFont = SetPVFont,
        StartActiveStatePreview = StartActiveStatePreview,
        StopActiveStatePreview = StopActiveStatePreview,
        UpdateCDMPreview = UpdateCDMPreview,
        UpdateCDMPreviewAndResize = UpdateCDMPreviewAndResize,
    }

    ---------------------------------------------------------------------------
    --  Standalone Rotation Assist Icon (independent of the selected CDM bar)
    ---------------------------------------------------------------------------
    local function BuildRotationAssistIconPage(pageTitle, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height, heading
        hostFrame._showRowDivider = true
        local function Settings() return DB().rotationAssistIcon end
        local function ApplyAssistIcon()
            mod.RefreshRotationAssistIcon()
            CUI:RefreshPage()
        end
        -- Why the icon's rows are locked, nil while they are live: Blizzard's
        -- Assisted Highlight off, or the icon itself off.
        local function IconLockTip()
            if not mod.RotationAssistAvailable() then
                return "This option requires Blizzard's Assisted Highlight to be enabled"
            end
            if Settings().enabled ~= true then return "Show Rotation Assist Icon" end
        end
        local function IconOff() return IconLockTip() ~= nil end
        -- The saved position, else the runtime's default (read only).
        local function Position() return Settings().position or mod.CDM_ROTATION_ICON_DEFAULT_POS end
        local function SetOffset(axis, value)
            local cfg = Settings()
            local place = cfg.position or CopyTable(mod.CDM_ROTATION_ICON_DEFAULT_POS)
            place[axis] = CUI.PP.FromPixels(value)
            cfg.position = place
            mod.RefreshRotationAssistIcon()
        end

        heading, height = W:SectionHeader(hostFrame, "ROTATION ASSIST ICON", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "ECME_RotationAssistIcon", disabled = IconOff, disabledTooltip = IconLockTip }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Rotation Assist Icon",
            tooltip = "Show Blizzard's current recommendation in a separate icon. Requires Assisted Highlight to be enabled in Blizzard's options. Press the spell's normal keybind; this display never casts spells. Blizzard supplies one recommendation, not a queue of future casts.",
            -- Locked only while off: an icon left on after the highlight was
            -- switched off can always be turned off here.
            disabled = function() return not mod.RotationAssistAvailable() and Settings().enabled ~= true end,
            disabledTooltip = "This option requires Blizzard's Assisted Highlight to be enabled",
            rawTooltip = true,
            getValue = function() return Settings().enabled == true end,
            setValue = function(val)
                Settings().enabled = val
                ApplyAssistIcon()
            end,
        }, {
            type = "slider",
            text = "Icon Size",
            min = 16,
            max = 128,
            step = 1,
            disabled = IconOff,
            disabledTooltip = IconLockTip,
            getValue = function() return Settings().iconSize or 48 end,
            setValue = function(val)
                Settings().iconSize = val
                mod.RefreshRotationAssistIcon()
            end,
        })
        cursorY = cursorY - height
        local kbRow
        kbRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Only in Combat",
            tooltip = "Hide outside combat. Edit Layout shows a placeholder when no recommendation is available.",
            disabled = IconOff,
            disabledTooltip = IconLockTip,
            getValue = function() return Settings().onlyInCombat == true end,
            setValue = function(val)
                Settings().onlyInCombat = val
                ApplyAssistIcon()
            end,
        }, {
            type = "toggle",
            text = "Show Keybind",
            tooltip = "Use the CDM keybind mapping. Configure the font, outline, position, background and border with the cog.",
            disabled = IconOff,
            disabledTooltip = IconLockTip,
            getValue = function() return Settings().showKeybind == true end,
            setValue = function(val)
                Settings().showKeybind = val
                ApplyAssistIcon()
            end,
        })
        cursorY = cursorY - height
        BuildKeybindStyleControls(kbRow, Settings, ApplyAssistIcon, IconLockTip)
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "X Offset",
            min = -2000,
            max = 2000,
            step = 1,
            tooltip = "Horizontal screen offset. You can also drag the Rotation Assist Icon in Edit Layout.",
            disabled = IconOff,
            disabledTooltip = IconLockTip,
            getValue = function() return CUI.PP.ToPixels(Position().x or 0) end,
            setValue = function(val) SetOffset("x", val) end,
        }, {
            type = "slider",
            text = "Y Offset",
            min = -1200,
            max = 1200,
            step = 1,
            tooltip = "Vertical screen offset. You can also drag the Rotation Assist Icon in Edit Layout.",
            disabled = IconOff,
            disabledTooltip = IconLockTip,
            getValue = function() return CUI.PP.ToPixels(Position().y or 0) end,
            setValue = function(val) SetOffset("y", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show GCD",
            tooltip = "Show the global cooldown as a swipe over the recommended ability. The swipe shows when the GCD ends; casting, channeling and ability requirements can still delay your next action.",
            disabled = IconOff,
            disabledTooltip = IconLockTip,
            getValue = function() return Settings().showGCD == true end,
            setValue = function(val)
                Settings().showGCD = val
                ApplyAssistIcon()
            end,
        }, CUI.BlankRowCfg())
        cursorY = cursorY - height
        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Unlock Mode page  (opens CludesUI Unlock Mode overlay)
    ---------------------------------------------------------------------------
    local function BuildUnlockPage(pageTitle, hostFrame, yOffset)
        C_Timer.After(0, function()
            if CUI and CUI._openUnlockMode then CUI._openUnlockMode() end
        end)
        return 0
    end

    ---------------------------------------------------------------------------
    --  One-time CDM button settings tip (shown on first CDM Bars page open)
    ---------------------------------------------------------------------------
    local _cdmButtonTip
    local function ShowCDMButtonTip()
        if CludesUIDB and CludesUIDB.cdmButtonTipSeen then return end
        -- The CDM header's own preview (this module's header preview slot).
        local preview = optionState._cdmPreview or CUI._cdmHeaderPreview
        if not preview then return end

        if not _cdmButtonTip then
            _cdmButtonTip = CUI.BuildTipCallout(CUI._panelBody, {
                width = 360,
                height = 105,
                text = CUI.L(
                    "CDM buttons can have their glow and active states\nset per icon or synced to the bar. Click a button\nto show its settings."
                ),
                font = (CUI.GetFontPath("cdm"))
                    or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF",
                textTop = 15,
                spacing = 4,
                btnBottom = 11,
                onOkay = function()
                    if CludesUIDB then CludesUIDB.cdmButtonTipSeen = true end
                end,
            })
        end

        -- The preview is rebuilt with its page, so anchor on every call: a tip
        -- already showing moves onto the preview that replaced the old one.
        _cdmButtonTip:ClearAllPoints()
        _cdmButtonTip:SetPoint("TOP", preview, "BOTTOM", 0, -12)
        _cdmButtonTip:Show()
    end
    -- Hidden whenever the player leaves the CDM Bars page (page switch, module
    -- switch, panel close); it returns on that page until dismissed with Okay.
    local function HideCdmTip()
        if _cdmButtonTip then _cdmButtonTip:Hide() end
    end
    -- Shown a beat after the Bars page renders; the player may already have
    -- moved on by then, so the timer re-checks the page before showing.
    local function QueueCDMButtonTip()
        C_Timer.After(0.1, function()
            if mod._cdmBarsPageOpen then ShowCDMButtonTip() end
        end)
    end

    ---------------------------------------------------------------------------
    --  Buff bar overlay: REMOVED (no locator ghost over the live buff bar
    --  while options are open). ShowBuffBarOverlay is a no-op stub so the
    --  existing call sites (page open/close) need no changes.
    ---------------------------------------------------------------------------
    local _buffBarOverlay
    local function ShowBuffBarOverlay() end

    local function HideBarOverlay()
        if _buffBarOverlay then _buffBarOverlay:Hide() end
    end
    mod.ShowBuffBarOverlay = ShowBuffBarOverlay
    mod.HideBuffBarOverlay = HideBarOverlay

    -- Hook: show tip when CDM Bars page first renders with a preview visible
    local _cdmButtonTipQueued = false
    CUI:RegisterOnHide(function()
        HideCdmTip()
        -- Hide overlay and custom aura preview when panel closes
        HideBarOverlay()
        mod._cdmBarsPageOpen = false
        if mod.UpdateCustomBuffBars then mod.UpdateCustomBuffBars() end
    end)

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    CUI:RegisterModule("CludesUICooldownManager", {
        title = "Cooldown Manager",
        description = "CDM bar customization, action bar glows, and buff bars.",
        -- Rotation Assist Icon: the far-right tab; none on Forever (no Assisted
        -- Highlight there).
        pages = CUI.IS_FOREVER and { PAGE_CDM_BARS, PAGE_BAR_GLOWS, PAGE_BUFF_BARS }
            or { PAGE_CDM_BARS, PAGE_BAR_GLOWS, PAGE_BUFF_BARS, PAGE_ROTATION_ICON },
        -- Shown name (the page key stays: links and saved places use it).
        tabLabels = { [PAGE_CDM_BARS] = "Cooldown Bars" },
        disabledPages = {},
        disabledPageTooltips = {},
        buildPage = function(pageTitle, hostFrame, yOffset)
            -- ns._tbbPlaceholderMode / ns._cdmBarsPageOpen reflect the page the player
            -- is REALLY on, not the pageName being built. A hidden search pre-build
            -- cycles pageName through all three pages, so the "switched away" cleanup
            -- below (buff-bar injection/removal, placeholder toggling, settings tip)
            -- would fire against what the player is actually seeing -- during
            -- pre-build, only build content. PAGE_BUFF_BARS is skipped entirely: its
            -- builder unconditionally calls UpdateTBBPlaceholder() at its tail, which
            -- grabs the REAL tracked-buff-bar frames via ns.GetTBBFrame(i) (not scoped
            -- to `parent`) and forces them :Show() with unlock placeholders -- building
            -- it here would pop the live buff bars onto the screen. It's indexed
            -- normally the first time the player visits it live.
            if CUI._prebuilding then
                if pageTitle == PAGE_CDM_BARS then
                    return mod.CDMO_BuildCDMBarsPage(pageTitle, hostFrame, yOffset)
                elseif pageTitle == PAGE_ROTATION_ICON then
                    return BuildRotationAssistIconPage(pageTitle, hostFrame, yOffset)
                elseif pageTitle == PAGE_BAR_GLOWS then
                    return BuildBarGlowsPage(pageTitle, hostFrame, yOffset)
                end
                return
            end
            -- Clear TBB placeholders when switching to any non-Tracking Bars page
            if pageTitle ~= PAGE_BUFF_BARS and mod._tbbPlaceholderMode then
                mod._tbbPlaceholderMode = false
                if mod.HideTBBPlaceholders then mod.HideTBBPlaceholders() end
            end
            -- Manage custom aura bar preview: flag-based, not GetActivePage
            if pageTitle ~= PAGE_CDM_BARS and mod._cdmBarsPageOpen then
                mod._cdmBarsPageOpen = false
                if mod.UpdateCustomBuffBars then mod.UpdateCustomBuffBars() end
                -- Page closed: reanchor so buff-bar injected custom/preset buffs
                -- that were shown for configuration (cdmPageOpen) hide unless active.
                if mod.QueueReanchor then mod.QueueReanchor() end
                HideBarOverlay()
                HideCdmTip()
            end
            if pageTitle == PAGE_CDM_BARS then
                mod._cdmBarsPageOpen = true
                local h2 = mod.CDMO_BuildCDMBarsPage(pageTitle, hostFrame, yOffset)
                if mod.UpdateCustomBuffBars then mod.UpdateCustomBuffBars() end
                ShowBuffBarOverlay()
                -- Show one-time button settings tip after preview renders
                QueueCDMButtonTip()
                return h2
            elseif pageTitle == PAGE_ROTATION_ICON then
                return BuildRotationAssistIconPage(pageTitle, hostFrame, yOffset)
            elseif pageTitle == PAGE_BAR_GLOWS then
                return BuildBarGlowsPage(pageTitle, hostFrame, yOffset)
            elseif pageTitle == PAGE_BUFF_BARS then
                return BuildBuffBarsPage(pageTitle, hostFrame, yOffset)
            end
        end,
        getHeaderBuilder = function(pageTitle)
            if pageTitle == PAGE_CDM_BARS then
                return optionState._cdmHeaderBuilder
            elseif pageTitle == PAGE_BAR_GLOWS then
                return _glowHeaderBuilder
            end
            -- Tracking Bars has no content header (popout preview instead)
            return nil
        end,
        -- CDM Bars content is gated on the selected bar (e.g. FocusKick-only
        -- rows render only while barData.key == "focuskick"), and the default
        -- selection is almost never FocusKick -- without this, a hidden pre-build only
        -- ever sees one bar's options and every other bar's unique settings stay
        -- unsearchable until the player visits them live. Build once per distinct bar
        -- SHAPE (cooldowns/utility/buffs/ custom_buff/focuskick), not per bar instance:
        -- several custom bars of one shape expose identical options, so indexing more
        -- than one of a shape would be a wasted rebuild.
        getPrebuildVariants = function(pageTitle)
            if pageTitle ~= PAGE_CDM_BARS then return nil end
            local profile = DB()
            local barList = profile and profile.cdmBars and profile.cdmBars.bars
            if not barList or #barList == 0 then return nil end
            local seenShapes = {}
            local keyList = {}
            for _, bar in ipairs(barList) do
                local shape = (bar.key == "focuskick") and "focuskick" or bar.barType
                if shape and not seenShapes[shape] then
                    seenShapes[shape] = true
                    keyList[#keyList + 1] = bar.key
                end
            end
            if optionState.selectedCDMBarIndex < 1 then optionState.selectedCDMBarIndex = 1 end
            if optionState.selectedCDMBarIndex > #barList then optionState.selectedCDMBarIndex = #barList end
            local currentBar = barList[optionState.selectedCDMBarIndex]
            return {
                setter = CUI._setCDMBar,
                keys = keyList,
                currentKey = currentBar and currentBar.key,
            }
        end,
        onPageCacheRestore = function(pageTitle)
            -- Same flag management as buildPage
            if pageTitle ~= PAGE_BUFF_BARS and mod._tbbPlaceholderMode then
                mod._tbbPlaceholderMode = false
                if mod.HideTBBPlaceholders then mod.HideTBBPlaceholders() end
            end
            if pageTitle ~= PAGE_CDM_BARS and mod._cdmBarsPageOpen then
                mod._cdmBarsPageOpen = false
                if mod.UpdateCustomBuffBars then mod.UpdateCustomBuffBars() end
                -- Page closed: reanchor so buff-bar injected custom/preset buffs
                -- that were shown for configuration (cdmPageOpen) hide unless active.
                if mod.QueueReanchor then mod.QueueReanchor() end
                HideBarOverlay()
                HideCdmTip()
            end
            if pageTitle == PAGE_BUFF_BARS then
                if mod.ShowTBBPlaceholders then mod.ShowTBBPlaceholders() end
                RefreshTBBPopout()
            end
            if pageTitle == PAGE_CDM_BARS then
                mod._cdmBarsPageOpen = true
                if mod.UpdateCustomBuffBars then mod.UpdateCustomBuffBars() end
                ShowBuffBarOverlay()
                -- The undismissed tip returns with the Bars page
                QueueCDMButtonTip()
                -- Re-sync _cdmPreview after cache restore and refresh the preview
                if not optionState._cdmPreview and CUI._cdmHeaderPreview then
                    optionState._cdmPreview = CUI._cdmHeaderPreview
                end
                if optionState._cdmPreview and optionState._cdmPreview.Update then
                    optionState._cdmPreview:Update()
                end
            end
        end,
        -- Leaving the module: the button settings tip is a child of the main
        -- frame, so nothing else would take it down with the page.
        onModuleLeave = function() HideCdmTip() end,
        onReset = function()
            if _G._CUCME_AceDB then
                _G._CUCME_AceDB:ResetProfile()
                -- Clear the per-install capture flag so the snapshot re-runs
                -- after reload and picks up Blizzard's current CDM layout.
                if _G._CUCME_AceDB.sv then _G._CUCME_AceDB.sv._capturedOnce_CDM = nil end
            end
            -- Learned variant->base pairs are game data rather than settings,
            -- but they sit on the SV root where StripDefaults and the profile
            -- system never reach, so a pair learned wrong would survive every
            -- other reset. This is the only path that clears them.
            if mod.ResetVariantBaseStore then mod.ResetVariantBaseStore() end
            -- Wipe spell assignments for the current spec so the init snapshot re-populates
            -- from Blizzard's CDM. Spell data lives in CludesUIDB (per-profile store), not the
            -- AceDB profile, so ResetProfile doesn't touch it. Only clear the ACTIVE profile's current spec to preserve other specs and other profiles.
            if mod and mod.GetActiveSpecProfiles then
                local spellRec = mod.GetActiveSpecProfiles()
                local specKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
                if spellRec and specKey and specKey ~= "0" then
                    spellRec[specKey] = nil
                    -- WoW Forever: the class reads one of several keys (its
                    -- Forever spec key, then its retail specs); clear them all
                    -- so the reload starts the class fresh.
                    if CUI.IS_FOREVER then
                        local token = select(2, UnitClass("player"))
                        local ids = CUI.ForeverClassSpecIDs(token)
                        for i = 1, (ids and #ids or 0) do
                            spellRec[tostring(ids[i])] = nil
                        end
                        local lk = CUI.FOREVER_CLASS_SPEC[token]
                        if lk then spellRec[tostring(lk)] = nil end
                    end
                end
            end
            -- No reload here: Reset CUI Module Settings reloads after this returns.
        end,
    })

    SLASH_ECMEOPT1 = "/ccmeopt"
    SlashCmdList.ECMEOPT = function()
        if InCombatLockdown and InCombatLockdown() then return end
        CUI:ShowModule("CludesUICooldownManager")
    end
end)
