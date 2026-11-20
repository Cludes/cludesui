if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local addon, mod = ...
if
    not (
        CludesUI
        and CludesUI._ModuleNS
        and CludesUI.NewInternals
        and CludesUI.NewCombatQueue
        and CludesUI._Pool
        and CludesUI.Glows
        and CludesUI.Glows.FlatKeys
        and CludesUI.AbbreviateValue
        and CludesUI.IsZeroValue
        and CludesUI.UnitNameFormat
        and CludesUI.OwnSurnameHidden
        and CludesUI.ApplyModuleFontFamily
        and CludesUI.SetFontFamily
        and CludesUI.SetFontObjectFace
        and CludesUI.SnapshotFontObject
        and CludesUI.RestoreFontObject
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the health texts format through the parent's AbbreviateValue, the [absorb:abr] tags blank at zero through its IsZeroValue, the Name Format asks its UnitNameFormat, the [name:last] and [target:last] tags its OwnSurnameHidden, the plate texts take font families through its ApplyModuleFontFamily / SetFontFamily, and the friendly name-only fonts change through its SetFontObjectFace / SnapshotFontObject / RestoreFontObject)
CludesUI._ModuleNS[addon] = mod -- LOD options files read this module ns via the registry
mod.CombatQueue = CludesUI.NewCombatQueue(CreateFrame("Frame"))

local ENP = CludesUI.Lite.NewAddon("CludesUINameplates")

-- Profile alias: set in OnInitialize; getters fall back to defaults while nil.
local p

local ipairs = ipairs
local Pix = CludesUI.PP
local UnitIsUnit = UnitIsUnit
-- The core's table of the options page frame pool (CludesUI_PixelPerfect.lua
-- makes it, the options addon fills it): the builders the options preview shares
-- with the plates create through it, so a preview frame is handed back to the
-- preview's next build. A plate's parent is no pool host: a plain CreateFrame.
local Pool = CludesUI._Pool

local function GetFont()
    return CludesUI.GetFontPath("nameplates")
end
-- Slug-gated at the source (GetFontOutlineFlag); SetFSFont gates the
-- explicit-flag path too, so aura literals are covered.
local function GetNPOutline()
    return CludesUI.GetFontOutlineFlag("nameplates")
end
local function GetNPUseShadow()
    return CludesUI.GetFontUseShadow("nameplates")
end
-- Every plate text takes a font family (names, guilds, titles and cast targets can be
-- other players' writing): the chosen font draws what it can, Blizzard's Cyrillic,
-- Korean and Chinese faces the rest. Once a string has its family, every later font
-- write to it goes through this helper (or SetFontFamily), never a plain SetFont.
local function SetFSFont(fontStr, size, flags)
    -- "Never Show Slug": gates the explicit-flag path so hardcoded aura
    -- "OUTLINE, SLUG" literals drop the slug (body text is gated at the source).
    CludesUI.ApplyModuleFontFamily(
        fontStr,
        nil,
        size or 11,
        "nameplates",
        CludesUI.SlugFlag(flags or GetNPOutline())
    )
end

mod.GetFont = GetFont
mod.GetNPOutline = GetNPOutline
mod.GetNPUseShadow = GetNPUseShadow
mod.SetFSFont = SetFSFont
mod.plates = {}
_G.CludesNameplates_NS = mod

-- Weak-keyed external state for nameplate Y-offsets: never write custom keys
-- onto Blizzard C_NamePlate frames (taint).
local _npYOffsetState = setmetatable({}, { __mode = "k" })

-- Health text bar slots; file scope to avoid per-call alloc in UpdateHealthValues.
-- The corner slots hang under the health bar's bottom corners (bottom) or over its
-- top corners (top) and never truncate (corner); see PlaceSlotText. They follow the
-- three bar slots, and every entry is also read by index (bottom 4, 5; top 6, 7).
local HP_BAR_SLOTS = {
    { key = "textSlotRight", anchor = "RIGHT", point = "RIGHT", xOff = -2 },
    { key = "textSlotLeft", anchor = "LEFT", point = "LEFT", xOff = 4 },
    { key = "textSlotCenter", anchor = "CENTER", point = "CENTER", xOff = 0 },
    {
        key = "textSlotBottomLeft",
        anchor = "TOPLEFT",
        point = "BOTTOMLEFT",
        xOff = 0,
        justify = "LEFT",
        bottom = true,
        corner = true,
        xKey = "textSlotBottomLeftXOffset",
        yKey = "textSlotBottomLeftYOffset",
    },
    {
        key = "textSlotBottomRight",
        anchor = "TOPRIGHT",
        point = "BOTTOMRIGHT",
        xOff = 0,
        justify = "RIGHT",
        bottom = true,
        corner = true,
        xKey = "textSlotBottomRightXOffset",
        yKey = "textSlotBottomRightYOffset",
    },
    {
        key = "textSlotTopLeft",
        anchor = "BOTTOMLEFT",
        point = "TOPLEFT",
        xOff = 0,
        justify = "LEFT",
        top = true,
        corner = true,
        xKey = "textSlotTopLeftXOffset",
        yKey = "textSlotTopLeftYOffset",
    },
    {
        key = "textSlotTopRight",
        anchor = "BOTTOMRIGHT",
        point = "TOPRIGHT",
        xOff = 0,
        justify = "RIGHT",
        top = true,
        corner = true,
        xKey = "textSlotTopRightXOffset",
        yKey = "textSlotTopRightYOffset",
    },
}

mod.NP_ABSORB_STYLE_TEX = {
    blizzard = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\blizzard-nameplates.png",
    striped = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped3.tga",
    clean = "Interface\\Buttons\\WHITE8X8",
    pixelsShield = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\pixels-shield.tga",
    pixelsShieldEdge = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\pixels-shield-edge.tga",
    pixelsShieldFill = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\pixels-shield-fill.tga",
}
mod.NP_ABSORB_STYLE_ALPHA = {
    blizzard = 0.8,
    striped = 0.8,
    clean = 0.3,
}

-- Overflow for _displayPresetKeys; outside the main function scope to stay
-- under Lua 5.1's 200-local limit.
function mod._appendDisplayPresetKeys(t)
    for _, k in ipairs({
        "topSlotSize",
        "topSlotXOffset",
        "topSlotYOffset",
        "topSlotRaiseStrata",
        "rightSlotSize",
        "rightSlotXOffset",
        "rightSlotYOffset",
        "rightSlotRaiseStrata",
        "leftSlotSize",
        "leftSlotXOffset",
        "leftSlotYOffset",
        "leftSlotRaiseStrata",
        "toprightSlotSize",
        "toprightSlotXOffset",
        "toprightSlotYOffset",
        "toprightSlotGrowth",
        "toprightSlotRaiseStrata",
        "topleftSlotSize",
        "topleftSlotXOffset",
        "topleftSlotYOffset",
        "topleftSlotGrowth",
        "topleftSlotRaiseStrata",
        -- Core Positions chains: the order of a slot's elements (a string) and their spacing.
        "topSlotOrder",
        "rightSlotOrder",
        "leftSlotOrder",
        "toprightSlotOrder",
        "topleftSlotOrder",
        "bottomSlotOrder",
        "topSlotElementSpacing",
        "rightSlotElementSpacing",
        "leftSlotElementSpacing",
        "toprightSlotElementSpacing",
        "topleftSlotElementSpacing",
        "bottomSlotElementSpacing",
        "textSlotTopSize",
        "textSlotTopXOffset",
        "textSlotTopYOffset",
        "textSlotTopStrata",
        "textSlotRightSize",
        "textSlotRightXOffset",
        "textSlotRightYOffset",
        "textSlotRightStrata",
        "textSlotLeftSize",
        "textSlotLeftXOffset",
        "textSlotLeftYOffset",
        "textSlotLeftStrata",
        "textSlotCenterSize",
        "textSlotCenterXOffset",
        "textSlotCenterYOffset",
        "textSlotCenterStrata",
        "textSlotBottomLeftSize",
        "textSlotBottomLeftXOffset",
        "textSlotBottomLeftYOffset",
        "textSlotBottomLeftStrata",
        "textSlotBottomRightSize",
        "textSlotBottomRightXOffset",
        "textSlotBottomRightYOffset",
        "textSlotBottomRightStrata",
        "textSlotTopLeftSize",
        "textSlotTopLeftXOffset",
        "textSlotTopLeftYOffset",
        "textSlotTopLeftStrata",
        "textSlotTopRightSize",
        "textSlotTopRightXOffset",
        "textSlotTopRightYOffset",
        "textSlotTopRightStrata",
        "textSlotTopColor",
        "textSlotRightColor",
        "textSlotLeftColor",
        "textSlotCenterColor",
        "textSlotBottomLeftColor",
        "textSlotBottomRightColor",
        "textSlotTopLeftColor",
        "textSlotTopRightColor",
        "threatColorHealth",
        "threatColorBorder",
        "threatColorName",
        "textSlotTopClassColor",
        "textSlotRightClassColor",
        "textSlotLeftClassColor",
        "textSlotCenterClassColor",
        "textSlotBottomLeftClassColor",
        "textSlotBottomRightClassColor",
        "textSlotTopLeftClassColor",
        "textSlotTopRightClassColor",
        "textSlotTopColorMode",
        "textSlotTopNameColorOn",
        "textSlotTopNameColor",
        "textSlotTopLevelColorOn",
        "textSlotTopLevelColor",
        "textSlotTopLevelDiffOn",
        "textSlotRightColorMode",
        "textSlotRightNameColorOn",
        "textSlotRightNameColor",
        "textSlotRightLevelColorOn",
        "textSlotRightLevelColor",
        "textSlotRightLevelDiffOn",
        "textSlotLeftColorMode",
        "textSlotLeftNameColorOn",
        "textSlotLeftNameColor",
        "textSlotLeftLevelColorOn",
        "textSlotLeftLevelColor",
        "textSlotLeftLevelDiffOn",
        "textSlotCenterColorMode",
        "textSlotCenterNameColorOn",
        "textSlotCenterNameColor",
        "textSlotCenterLevelColorOn",
        "textSlotCenterLevelColor",
        "textSlotCenterLevelDiffOn",
        "textSlotBottomLeftColorMode",
        "textSlotBottomLeftNameColorOn",
        "textSlotBottomLeftNameColor",
        "textSlotBottomLeftLevelColorOn",
        "textSlotBottomLeftLevelColor",
        "textSlotBottomLeftLevelDiffOn",
        "textSlotBottomRightColorMode",
        "textSlotBottomRightNameColorOn",
        "textSlotBottomRightNameColor",
        "textSlotBottomRightLevelColorOn",
        "textSlotBottomRightLevelColor",
        "textSlotBottomRightLevelDiffOn",
        "textSlotTopLeftColorMode",
        "textSlotTopLeftNameColorOn",
        "textSlotTopLeftNameColor",
        "textSlotTopLeftLevelColorOn",
        "textSlotTopLeftLevelColor",
        "textSlotTopLeftLevelDiffOn",
        "textSlotTopRightColorMode",
        "textSlotTopRightNameColorOn",
        "textSlotTopRightNameColor",
        "textSlotTopRightLevelColorOn",
        "textSlotTopRightLevelColor",
        "textSlotTopRightLevelDiffOn",
        "tankHasAggroEnabled",
        "tankHasAggro",
        "classicTankAggro",
        "tankHasAggroOverrideMobType",
        "tankHasAggroOverrideBoss",
        "dpsHasAggro",
        "dpsNearAggro",
        "offTankAggroEnabled",
        "offTankAggro",
        "dpsNoAggroEnabled",
        "dpsNoAggro",
        "dpsNoAggroOverrideMiniBoss",
        "dpsNoAggroOverrideCaster",
        "dpsNoAggroOverrideBoss",
        "targetArrowDouble",
        "targetArrowStyle",
        "targetArrowColor",
        "targetArrowClassColor",
        "auraStackTextSize",
        "auraStackTextColor",
        "auraStackTextPosition",
        "auraStackTextX",
        "auraStackTextY",
        "auraDurationTextX",
        "auraDurationTextY",
        "debuffDurationTextSize",
        "debuffDurationTextX",
        "debuffDurationTextY",
        "debuffDurationTextColor",
        "buffDurationTextSize",
        "buffDurationTextX",
        "buffDurationTextY",
        "buffDurationTextColor",
        "ccDurationTextSize",
        "ccDurationTextX",
        "ccDurationTextY",
        "ccDurationTextColor",
        "buffTextSize",
        "buffTextColor",
        "ccTextSize",
        "ccTextColor",
        "raidMarkerPos",
        "classificationSlot",
        "classificationShowInInstances",
        "factionSlot",
        "classificationIncludeFaction",
        "classificationHideRare",
        "classificationHideQuest",
        -- Core Positions elements (no defaults: unset reads the views in Layout.lua).
        "debuffCoreSize",
        "buffCoreSize",
        "ccCoreSize",
        "raidMarkerCoreSize",
        "rareCoreSize",
        "questCoreSize",
        "factionCoreSize",
        "questTextSlot",
        "rareShowInInstances",
        "questShowInInstances",
        "questTextShowInInstances",
        "castNameSize",
        "castNameColor",
        "castCombineNameTarget",
        "castTargetSize",
        "castTargetClassColor",
        "castTargetColor",
        "showCastTimer",
        "castTimerSize",
        "castTimerColor",
        "targetScale",
        "minorEnemyScale",
        "nonEliteEnemyScale",
        "castNameSide",
        "castTargetSide",
        "castTimerSide",
        "castNameWidthPct",
        "castNameWrap",
        "castCombinedWidthPct",
        "castTargetWidthPct",
        "castTargetWrap",
        "enemyNameWidthPct",
        "enemyNameWrap",
        "wrapBorderCastbar",
        "wrapBorderSeam",
        "debuffSlot",
        "buffSlot",
        "ccSlot",
        "debuffYOffset",
        "sideAuraXOffset",
        "auraSpacing",
        "debuffSpacing",
        "buffSpacing",
        "ccSpacing",
        "debuffTimerPosition",
        "buffTimerPosition",
        "ccTimerPosition",
        "auraDurationTextSize",
        "auraDurationTextColor",
        "debuffCropIcons",
        "buffCropIcons",
        "ccCropIcons",
        "debuffCropPercent",
        "buffCropPercent",
        "ccCropPercent",
        "hideCastIconBorder",
        "hideDebuffIconBorder",
        "hideBuffIconBorder",
        "hideCCIconBorder",
        "showCastLockoutAsCrowdControl",
        "castIconOffsetX",
        "castIconOffsetY",
        "targetGlowCludesUI",
        "targetGlowBorderColor",
        "targetGlowHighlight",
        "targetBorderColor",
        "targetGlowBorderSize",
        "targetBorderSizeValue",
    }) do
        t[#t + 1] = k
    end
end

local defaultSet = {
    -- CUI_DEBUFF_COLORS: optional player-debuff tinting (Colors page). The
    -- per-class lists ("debuffColors" .. class token) have no defaults: unset
    -- is an empty list (CludesUINameplates_DebuffColors.lua).
    debuffColorsEnabled = false,
    debuffColorsPlayerOnly = true,
    -- Debuff Coloring "Color Border": the color goes on the plate's border
    -- instead of its health bar, plus whole pixels added to a Basic or Custom
    -- Solid border while it shows.
    debuffColorsBorder = false,
    debuffColorsBorderExtra = 0,
    -- debuffColorsMode ("texture" = Texture Nameplate, "name" = Color Name) and
    -- debuffColorsTexture have no defaults: unset reads debuffColorsBorder's
    -- choice and the health bar's own texture.
    -- Blizzard Style (Global Settings > Style): the stock nameplate's bar,
    -- background, selection and cast bar art on our plates with every feature
    -- intact. Default OFF; reload-gated.
    useBlizzardStyle = false,
    -- Classic WoW UI (Global Settings > Style): the flat vanilla plate -- the
    -- user's fill inside a 1px black edge, square icons -- with every feature
    -- intact. Default OFF; reload-gated. Set together with useBlizzardStyle
    -- it wins.
    useClassicStyle = false,
    absorbStyle = "blizzard",
    absorbCleanAlpha = 30,
    absorbColor = { r = 1, g = 1, b = 1 },
    -- Shield placement, the unit frames' set: overlay / overlayReverse / right / left.
    absorbEdgeMode = "overlay",
    hostile = { r = 0.39, g = 0.11, b = 0.09 },
    neutral = { r = 0.81, g = 0.72, b = 0.19 },
    tapped = { r = 0.50, g = 0.50, b = 0.50 },
    focus = { r = 0.051, g = 0.820, b = 0.620 },
    focusColorEnabled = true,
    focusOverlayTexture = "striped-v2",
    focusOverlayAlpha = 1.0,
    focusOverlayColor = { r = 1.0, g = 1.0, b = 1.0 },
    focusOverlayFullBgAlpha = false, -- on: empty bar shows focus texture at full opacity (vs dimmed 30% default)
    focusOverlayNoTint = false, -- on: overlay tints with the bar's health color instead of focusOverlayColor
    focusLetterEnabled = false,
    focusLetterAnchor = "CENTER",
    focusLetterX = 0,
    focusLetterY = 0,
    focusLetterSize = 18,
    target = { r = 0.459, g = 0.890, b = 0.580 },
    targetColorEnabled = false,
    targetOverlayTexture = "none",
    targetOverlayAlpha = 1.0,
    targetOverlayColor = { r = 1.0, g = 1.0, b = 1.0 },
    targetOverlayFullBgAlpha = false, -- on: empty bar shows target texture at full opacity instead of dimmed 30%
    targetOverlayNoTint = false, -- mirrors focusOverlayNoTint, for the target overlay
    hoverOverlayTexture = "none",
    caster = { r = 0.231, g = 0.510, b = 0.965 },
    miniboss = { r = 0.518, g = 0.243, b = 0.984 },
    boss = { r = 0.518, g = 0.243, b = 0.984 },
    enemyInCombat = { r = 0.800, g = 0.137, b = 0.137 },
    -- "Mini Enemies" (non-elite trash) has no static default: unset views enemyInCombat, so it
    -- starts identical to "Enemies" (see GetReactionColor).
    miniColoringMPlusOnly = false, -- on = Mini Enemies color only in 5-mans; off = everywhere
    -- Simple Coloring When Not In M+ (inline cog on Enemy Types): outside 5-mans, mob-type colors (Mini
    -- Enemies/Casters/Mini-Bosses/Bosses) collapse to owBasicColor; Neutral keeps its own color out of
    -- combat and takes owBasicColor in combat.
    owBasicColoring = false,
    owBasicColor = { r = 0.800, g = 0.137, b = 0.137 },
    -- Color Casting Enemies: a mob without a mana pool takes the Interruptible color once it
    -- casts something interruptible, else the Uninterruptible color once it casts something
    -- that is not; each color applies to the mob types ticked for it.
    castingEnemyColors = false,
    -- Enemy Players Use Enemy Color: enemy players take the Enemies color, not their class color.
    enemyPlayerEnemyColor = false,
    castingIntColor = { r = 0.310, g = 0.702, b = 1.000 },
    castingUnintColor = { r = 0.953, g = 0.573, b = 0.000 },
    castingIntNormal = true,
    castingIntElite = true,
    castingIntMiniBoss = true,
    castingIntBoss = true,
    castingUnintNormal = true,
    castingUnintElite = true,
    castingUnintMiniBoss = false,
    castingUnintBoss = false,
    darkenEnemiesOOC = true,
    darkenOOCRecolor = false, -- Modify Out of Combat "Change Color": recolor OOC enemies rather than dimming
    darkenOOCColor = { r = 0.5, g = 0.5, b = 0.5 },
    -- Threat Colors channel multi-check: which surfaces carry the threat color.
    -- Health Bar is the historical single channel (on by default, so existing profiles
    -- keep their exact colors); Border and Text are opt-in SECOND channels that carry
    -- threat independently of the bar, so the bar can keep showing the mob type
    -- (Caster/Mini-Boss/Boss) while the border/name shows aggro -- the two-signal
    -- layout. With Health Bar off, GetReactionColor skips the whole threat arm and
    -- clears isThreatUnit, so the low-priority has-aggro/no-aggro steps stop firing on
    -- the bar as well and it is purely mob-type/reaction colored.
    threatColorHealth = true,
    threatColorBorder = false,
    threatColorName = false,
    -- Show Threat Colors: where the threat colors apply -- "never", "instances" (party/raid
    -- instances and delves) or "always". Per client: WoW Forever defaults to "always".
    threatColorMode = (CludesUI.IS_FOREVER == true) and "always" or "instances",
    tankHasAggro = { r = 0.30, g = 0.79, b = 0.94 },
    tankHasAggroEnabled = false,
    tankHasAggroOverrideMobType = false, -- on: overrides Mini-Boss/Caster (above priority step 7); off = stays low
    tankHasAggroOverrideBoss = true, -- on (default): overrides Boss color; off = held just below Boss
    classicTankAggro = false,
    tankLosingAggro = { r = 0.81, g = 0.72, b = 0.19 },
    tankNoAggro = { r = 1.00, g = 0.22, b = 0.17 },
    dpsNearAggro = { r = 0.81, g = 0.72, b = 0.19 },
    threatNearAggroGlow = false, -- Non-Tank Threat cog: red glow while the Near Aggro color is active
    threatPctEnabled = false, -- Threat % text: WoW Forever only
    threatPctPosition = "CENTER",
    threatPctColorByThreat = true,
    threatPctSize = 10,
    threatPctXOffset = 0,
    threatPctYOffset = 0,
    threatPctMode = "percent", -- "gap": the target's plate shows the Threat Gap
    threatGapAheadColor = { r = 0.30, g = 0.90, b = 0.30 },
    threatGapBehindColor = { r = 0.35, g = 0.60, b = 1.00 },
    dpsHasAggro = { r = 1.00, g = 0.50, b = 0.00 },
    offTankAggro = { r = 0.188, g = 0.761, b = 0.812 },
    offTankAggroEnabled = true,
    dpsNoAggro = { r = 0.35, g = 0.75, b = 0.35 },
    dpsNoAggroEnabled = false,
    dpsNoAggroOverrideMiniBoss = false, -- on: overrides Mini-Boss (above priority step 7); off = stays low
    dpsNoAggroOverrideCaster = false, -- on: overrides Caster (above priority step 8); off = Casters keep own color
    dpsNoAggroOverrideBoss = true, -- on (default, the pre-toggle behaviour): overrides Boss (step 10b); off = Bosses keep own color
    interruptReady = { r = 0.92, g = 0.35, b = 0.20 },
    castBar = { r = 0.70, g = 0.40, b = 0.90 },
    interruptMidCastEnabled = false,
    interruptMidCastColor = { r = 0.318, g = 0.820, b = 0.357 },
    castBarUninterruptible = { r = 0.45, g = 0.45, b = 0.45 },
    castBarImportant = { r = 1, g = 0.2, b = 0.2 },
    importantCastColorEnabled = false,
    importantCastKickReadyAsInterruptible = false,
    castBarShieldEnabled = true,
    interruptedFlashEnabled = true,
    interruptedFlashColor = { r = 0.8, g = 0.0, b = 0.0 },
    showCastLockoutAsCrowdControl = false,
    healthBarHeight = 17,
    friendlyNameOnly = true,
    friendlyNameOnlyYOffset = -20,
    friendlyNameSize = 15,
    friendlyPlateYOffset = 0,
    friendlyHealthBarHeight = 17,
    friendlyHealthBarWidth = 150,
    showFriendlyNPCs = false,
    showNPCTitles = true,
    showNPCRaidMarker = true,
    showFriendlyPlayers = true,
    friendlyClickThrough = false,
    friendlyShowDefaultNames = false,
    classColorFriendly = true,
    friendlyNameClassColor = false,
    -- Target Border Effects (Friendly Nameplate Settings cog): the target Border Color
    -- and Border Size effects on friendly plates too.
    friendlyTargetBorderFx = false,
    friendlyBarColor = { r = 0.314, g = 0.800, b = 0.408 },
    friendlyNPCColor = { r = 0, g = 1, b = 0 },
    friendlyNPCNameColor = { r = 0, g = 1, b = 0 },
    friendlyNPCTitleColor = { r = 0, g = 1, b = 0, a = 0.7 },
    friendlyNPCNameSize = 13,
    friendlyNPCTitleSize = 10,
    friendlyNameTextSize = 12,
    friendlyBelowName = "none",
    friendlyBelowNameSize = 12,
    friendlyBelowNameColor = { r = 0.8, g = 0.8, b = 0.8 },
    friendlyBelowNameClassColor = false,
    friendlyBelowNameGuildBrackets = true,
    friendlyShowLevel = false,
    friendlyLevelDiffColor = false,
    showEnemyPets = false,
    font = "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF",
    textSlotTop = "enemyName",
    textSlotRight = "healthPercent",
    -- WoW Forever shows the level by default (retail leaves the slot empty).
    textSlotLeft = (CludesUI.IS_FOREVER == true) and "level" or "none",
    textSlotCenter = "none",
    textSlotBottomLeft = "none",
    textSlotBottomRight = "none",
    textSlotTopLeft = "none",
    textSlotTopRight = "none",
    showTargetArrows = false,
    targetArrowDouble = false,
    targetArrowScale = 1.0,
    targetArrowColor = { r = 1, g = 1, b = 1 },
    targetArrowClassColor = false,
    showClassPower = false,
    classPowerPos = "bottom",
    classPowerYOffset = 1,
    classPowerXOffset = 0,
    -- The 8x3 base pip is reported as too small to read on Forever, where this is
    -- the target-side display rather than a second one. The Size slider (0.5 to
    -- 4.0) still overrides it.
    classPowerScale = (CludesUI.IS_FOREVER == true) and 1.8 or 1.0,
    classPowerClassColors = true,
    classPowerCustomColor = { r = 1.00, g = 0.84, b = 0.30 },
    classPowerBgColor = { r = 0.082, g = 0.082, b = 0.082, a = 1.0 },
    classPowerEmptyColor = { r = 0.2, g = 0.2, b = 0.2, a = 1.0 },
    classPowerGap = 2,
    classPowerShape = "rectangle", -- rectangle | square | circle | diamond | hexagon | shield
    classPowerBorder = false,
    classPowerBorderColor = { r = 0, g = 0, b = 0, a = 1.0 },
    classPowerBorderSize = 1,
    healthBarWidth = 6,
    stackSpacingScale = 100,
    stackingEnabled = true,
    stackingFriendly = false,
    hitboxScaleX = 100,
    hitboxScaleY = 100,
    nameplateYOffset = 0,
    enemyNameTextSize = 11,
    enemyNameTextReactionColor = false,
    debuffTimerColor = { r = 1, g = 1, b = 1 },
    auraTextPosition = "topleft",
    debuffTimerPosition = "topleft",
    buffTimerPosition = "topleft",
    ccTimerPosition = "topleft",
    auraDurationTextSize = 11,
    auraDurationTextX = 0,
    auraDurationTextY = 0,
    auraDurationTextColor = { r = 1, g = 1, b = 1 },
    auraStackTextSize = 11,
    auraStackTextColor = { r = 1, g = 1, b = 1 },
    auraStackTextPosition = "bottomright",
    auraStackTextX = 0,
    auraStackTextY = 0,
    debuffSlot = "top",
    buffSlot = "left",
    ccSlot = "right",
    debuffYOffset = 2,
    sideAuraXOffset = 2,
    nameYOffset = 0,
    auraSpacing = 2,
    debuffSpacing = 2, -- per-element icon gap; all default to the global auraSpacing value
    buffSpacing = 2,
    ccSpacing = 2,
    debuffCropIcons = false, -- cropped icons: trim top/bottom to rectangular (80% of width), mirrors Unit Frames
    buffCropIcons = false,
    ccCropIcons = false,
    debuffCropPercent = 10, -- per-side trim % for cropped mode (5-25); 10 == the fixed 80%-of-width crop
    buffCropPercent = 10,
    ccCropPercent = 10,
    hideDebuffIconBorder = false,
    hideBuffIconBorder = false,
    hideCCIconBorder = false,
    debuffIconSize = 26,
    buffIconSize = 24,
    buffTextSize = 12,
    buffTextColor = { r = 1, g = 1, b = 1 },
    ccIconSize = 24,
    ccTextSize = 12,
    ccTextColor = { r = 1, g = 1, b = 1 },
    targetGlowStyle = "cludesui",
    -- Target "Border Color" tint for the custom border when Border Color toggle is on.
    -- targetGlowCludesUI/targetGlowBorderColor/targetGlowHighlight deliberately have NO
    -- default: they stay nil so getters can live-convert from the targetGlowStyle string.
    targetBorderColor = { r = 1, g = 1, b = 1 },
    targetGlowColor = { r = 0.4117, g = 0.6667, b = 1.0 }, -- "Glow Color" for the CUI background glow (signature blue)
    targetGlowAlpha = 1.0,
    targetHighlightColor = { r = 1, g = 1, b = 1 }, -- Target Highlight wash color/opacity
    targetHighlightAlpha = 0.20,
    nameRaidMarkerEnabled = false,
    nameRaidMarkerSize = 14,
    raidMarkerPos = "topright",
    raidMarkerSize = 24,
    classificationSlot = "topleft",
    -- The fallback of the Elite/Rare, Quest and Quest Objective Text Show In Instances
    -- keys (rareShowInInstances / questShowInInstances / questTextShowInInstances, no
    -- defaults: ns.NP_ShowInInstances). WoW Forever: on.
    classificationShowInInstances = (CludesUI.IS_FOREVER == true) and true or false,
    -- Faction badge (Horde/Alliance), a Core Positions slot element; rules in ns.NP_FactionBadge.
    factionSlot = "none",
    factionStyle = "pvp", -- Icon Style: a key of CludesUI.FACTION_ART
    classificationIncludeFaction = false, -- "Rare/Quest + Faction": the badge shares the classification slot
    -- The classification element's two halves, each switchable in Core Positions:
    -- the Elite/Rare Indicator (elite and rare marks) and the Quest Indicator.
    classificationHideRare = false,
    classificationHideQuest = false,
    factionOppositeOnly = false,
    factionPlayersOnly = false,
    factionPvP = "dim", -- "dim" greys unflagged units, "only" hides them, "ignore" draws both alike
    rareEliteIconSize = 20,
    castBarHeight = 17,
    castBarOffsetY = 0,
    castBarSparkEnabled = true,
    castOverlayEnabled = false,
    hideEnemyNameWhileCasting = false,
    castNameSize = 10,
    castNameColor = { r = 1, g = 1, b = 1 },
    castNameOffsetX = 0,
    castNameOffsetY = 0,
    castNameSide = "left", -- cast bar text line side for spell name: left|right|center|none
    -- Spell name truncation: width as a % of cast bar width; wrap off = single line + ellipsis.
    castNameWidthPct = 42,
    castNameWrap = false,
    castCombineNameTarget = false,
    castCombinedWidthPct = 80, -- combined "Spell - Target" width, % of cast bar
    castTargetSize = 10,
    castTargetClassColor = true,
    castTargetColor = { r = 1, g = 1, b = 1 },
    castTargetOffsetX = 0,
    castTargetOffsetY = 0,
    castTargetSide = "right", -- side the spell target occupies: left|right|center|none
    -- Spell target truncation: % of cast bar width + wrap toggle.
    castTargetWidthPct = 42,
    castTargetWrap = false,
    showCastTimer = true,
    castTimerSide = "right", -- side when shown; visibility governed by showCastTimer
    castTimerSize = 10,
    castTimerColor = { r = 1, g = 1, b = 1 },
    castTimerOffsetX = 0,
    castTimerOffsetY = 0,
    -- Enemy name truncation: % of the name's computed (bar-derived) width (100 = full width
    -- minus raid-marker/classification reserves). Wrap off = single line + ellipsis, on = 2 lines.
    enemyNameWidthPct = 100,
    enemyNameWrap = false,
    targetScale = 100,
    minorEnemyScale = 100, -- minor/trivial mob plates; 100 = off
    nonEliteEnemyScale = 100, -- normal (non-elite, non-minor) mob plates in dungeons; 100 = off
    nonTargetKeepFocus = true,
    nonTargetCastFull = false, -- casting plates ignore Non-Target Opacity
    nonTargetCastImportantOnly = false, -- ...only for casts the game flags important
    outOfRangeAlpha = 50,
    outOfRangeMode = "disabled",
    showAllDebuffs = false,
    rangeTextEnabled = false, -- Distance to Target Text (range bucket on the target's nameplate)
    rangeTextSize = 11,
    rangeTextOffsetX = 0,
    rangeTextOffsetY = 0,
    rangeTextColor = { r = 0.816, g = 0.357, b = 0.220 }, -- #D05B38
    maxDebuffs = 5,
    showAuraTooltips = false, -- Buff / Debuff icons show their tooltip on hover
    showBorder = true,
    borderSize = 1,
    borderColor = { r = 0.067, g = 0.067, b = 0.067 },
    -- "Wrap Border Around Castbar": health border extends down to enclose the cast bar while casting,
    -- forming one unified border. Fully additive: no wrap machinery runs unless enabled.
    wrapBorderCastbar = false,
    -- "Show Seam Line" (Castbar Border cog, Custom border only): a divider along the cast
    -- bar's top edge while the custom border wraps the cast bar. Read only by that wrap.
    wrapBorderSeam = false,
    -- Classic WoW UI: the level and the boss icon seated in the health
    -- border's plate. A size of 0 follows the bar's own height; read only
    -- while that style renders.
    classicLevelSize = 0,
    classicLevelX = 0,
    classicLevelY = 0,
    classicSkullSize = 0,
    classicSkullX = 0,
    classicSkullY = 0,
    -- Custom border (opt-in): shared CludesUI border engine (same as Unit Frames, full
    -- SharedMedia). When false, NONE of these keys are read; the simple border above renders instead.
    customBorderEnabled = false,
    customBorderTexture = "solid",
    customBorderSize = 1,
    customBorderColor = { r = 0.067, g = 0.067, b = 0.067 },
    customBorderAlpha = 1,
    customBorderBehind = false,
    pandemicGlow = false,
    -- The aura glow styles' saved keys from before 9.6, read as a view
    -- (CUI_Nameplates_Layout.lua): this old default and nil mean Blizzard
    -- Pandemic Border; a style picked from 9.6 on is pandemicGlowPick /
    -- dispelGlowPick (no defaults: nil = no pick).
    pandemicGlowStyle = 1,
    pandemicGlowColor = { r = 1.0, g = 0.800, b = 0.329 },
    pandemicGlowLines = 8,
    pandemicGlowThickness = 1,
    pandemicGlowSpeed = 4,
    pandemicGlowBackground = false,
    pandemicGlowBackgroundColor = { r = 0, g = 0, b = 0 },
    lowHpGlow = false, -- Execute Pulse Glow (Extras): red glow around plates below 30% health
    hideBloodPlagueCopies = true, -- Extras (Blood DK only): collapse the Blood Plague copies to one debuff icon
    showSunderArmor = false, -- Extras (Forever warriors only): Sunder Armor from any warrior on enemy plates
    dispelGlow = false,
    dispelGlowStyle = 2,
    -- Swatch display only: the getter returns nil while the user has never
    -- customized the color, and the engines render their own default (this
    -- same gold on the ABG halo). Keep the two in step.
    dispelGlowColor = { r = 1.0, g = 0.788, b = 0.137 },
    dispelGlowUseTypeColor = false,
    -- Enemy Buff Filter ("important" | "dispellable" | "showall"): unset reads
    -- as Important; WoW Forever shows every enemy buff by default.
    npEnemyBuffFilter = (CludesUI.IS_FOREVER == true) and "showall" or nil,
    castScale = 100,
    focusCastHeight = 100,
    questMobColorEnabled = false,
    questMobColor = { r = 0.157, g = 0.855, b = 0.475 },
    -- Read only by the Quest Objective Text view (ns.NP_LegacyQuestText) while questTextSlot
    -- is unset: on, the text takes the Quest Indicator's slot. Its WoW Forever default is
    -- what shows the text on a fresh Forever profile. No UI writes it.
    replaceQuestIconWithObjective = (CludesUI.IS_FOREVER == true) and true or false,
    questObjectiveTextSize = 14, -- the Quest Objective Text element's Text Size
    showQuestObjectiveTypeIcon = false,
    questObjectiveTypeIconScale = 100,
    showCastIcon = true,
    castIconScale = 1,
    castIconOffsetX = 0,
    castIconOffsetY = 0,
    castbarIconInWidth = false,
    castIconOnRight = false,
    castIconFullSize = false,
    castIconTargetBorder = false,
    hideCastIconBorder = false,
    -- Icon Borders cog (Border = Custom only): the cast spell icon and the aura icons
    -- (debuffs, buffs, crowd control) wear the plate's custom border instead of their
    -- 1px edge. Read only while Border is Custom.
    castIconCustomBorder = false,
    castIconSeparator = false,
    auraIconCustomBorder = false,
    bgAlpha = 1.0,
    bgColor = { r = 0.12, g = 0.12, b = 0.12 },
    hoverColor = { r = 1, g = 1, b = 1 },
    hoverAlpha = 0.3,
    hoverOverlayFullBgAlpha = false, -- on: empty bar shows hover texture at full opacity instead of dimmed 30%
    castBgAlpha = 0.9,
    castBgColor = { r = 0.1, g = 0.1, b = 0.1 },
    castBorderSize = 0,
    castBorderColor = { r = 0, g = 0, b = 0 },
    hashLineEnabled = false,
    hashLinePercent = 30,
    hashLineColor = { r = 1, g = 1, b = 1 },
    kickTickEnabled = true,
    kickTickColor = { r = 1, g = 1, b = 1 },
    importantCastGlow = true,
    importantCastGlowStyle = 1,
    importantCastGlowColor = { r = 1, g = 0.2, b = 0.2 },
    importantCastGlowLines = 8,
    importantCastGlowThickness = 2,
    importantCastGlowSpeed = 4,
    importantCastGlowBackground = false,
    importantCastGlowBackgroundColor = { r = 0, g = 0, b = 0 },
    castTargetGlow = false, -- glow the cast bar while the cast targets the player
    castTargetGlowStyle = 1,
    castTargetGlowColor = { r = 1, g = 1, b = 1 },
    castTargetGlowLines = 8,
    castTargetGlowThickness = 2,
    castTargetGlowSpeed = 4,
    castTargetGlowBackground = false,
    castTargetGlowBackgroundColor = { r = 0, g = 0, b = 0 },
    -- Core Positions: per-slot XY offsets. <pos>SlotSize is the fallback of each element's
    -- own size key (debuffCoreSize, raidMarkerCoreSize, ..., no defaults: ns.NP_ElementSize).
    topSlotSize = 26,
    topSlotXOffset = 0,
    topSlotYOffset = 0,
    topSlotRaiseStrata = false,
    rightSlotSize = 24,
    rightSlotXOffset = 0,
    rightSlotYOffset = 0,
    rightSlotRaiseStrata = false,
    leftSlotSize = 24,
    leftSlotXOffset = 0,
    leftSlotYOffset = 0,
    leftSlotRaiseStrata = false,
    toprightSlotSize = 24,
    toprightSlotXOffset = 0,
    toprightSlotYOffset = 0,
    toprightSlotGrowth = "right",
    toprightSlotRaiseStrata = false,
    topleftSlotSize = 24,
    topleftSlotXOffset = 0,
    topleftSlotYOffset = 0,
    topleftSlotGrowth = "left",
    topleftSlotRaiseStrata = false,
    bottomSlotSize = 26,
    bottomSlotXOffset = 0,
    bottomSlotYOffset = 0,
    bottomSlotRaiseStrata = false,
    -- Core Text Positions: slot-based size + XY offsets (WoW Forever: a larger
    -- top text, raised 3px; retail keeps 10 / 0)
    textSlotTopSize = (CludesUI.IS_FOREVER == true) and 12 or 10,
    textSlotTopXOffset = 0,
    textSlotTopYOffset = (CludesUI.IS_FOREVER == true) and 3 or 0,
    textSlotRightSize = 10,
    textSlotRightXOffset = 0,
    textSlotRightYOffset = 0,
    textSlotLeftSize = 10,
    textSlotLeftXOffset = 0,
    textSlotLeftYOffset = 0,
    textSlotCenterSize = 10,
    textSlotCenterXOffset = 0,
    textSlotCenterYOffset = 0,
    textSlotBottomLeftSize = 10,
    textSlotBottomLeftXOffset = 0,
    textSlotBottomLeftYOffset = 0,
    textSlotBottomRightSize = 10,
    textSlotBottomRightXOffset = 0,
    textSlotBottomRightYOffset = 0,
    textSlotTopLeftSize = 10,
    textSlotTopLeftXOffset = 0,
    textSlotTopLeftYOffset = 0,
    textSlotTopRightSize = 10,
    textSlotTopRightXOffset = 0,
    textSlotTopRightYOffset = 0,
    -- Core Text Positions: slot-based strata (MEDIUM = the shared text tier)
    textSlotTopStrata = "MEDIUM",
    textSlotRightStrata = "MEDIUM",
    textSlotLeftStrata = "MEDIUM",
    textSlotCenterStrata = "MEDIUM",
    textSlotBottomLeftStrata = "MEDIUM",
    textSlotBottomRightStrata = "MEDIUM",
    textSlotTopLeftStrata = "MEDIUM",
    textSlotTopRightStrata = "MEDIUM",
    -- Core Text Positions: slot-based colors
    textSlotTopColor = { r = 1, g = 1, b = 1 },
    textSlotRightColor = { r = 1, g = 1, b = 1 },
    textSlotLeftColor = { r = 1, g = 1, b = 1 },
    textSlotCenterColor = { r = 1, g = 1, b = 1 },
    textSlotBottomLeftColor = { r = 1, g = 1, b = 1 },
    textSlotBottomRightColor = { r = 1, g = 1, b = 1 },
    textSlotTopLeftColor = { r = 1, g = 1, b = 1 },
    textSlotTopRightColor = { r = 1, g = 1, b = 1 },
    -- Core Text Positions: per-slot class colour flag, read only by ns.NP_SlotColorMode
    -- while the slot's Text Coloring mode (<slot>ColorMode, no default) is unset.
    textSlotTopClassColor = false,
    textSlotRightClassColor = false,
    textSlotLeftClassColor = false,
    textSlotCenterClassColor = false,
    textSlotBottomLeftClassColor = false,
    textSlotBottomRightClassColor = false,
    textSlotTopLeftClassColor = false,
    textSlotTopRightClassColor = false,
    healthBarTexture = "none", -- bar texture overlay
    castBarTexture = "none",
    healthTextureBg = false, -- Textured Background (Bar Texture cog)
    castTextureBg = false, -- Textured Background (Cast Bar Texture cog)
}
local BAR_W = 150
mod.defaults = defaultSet
mod.BAR_W = BAR_W
local CAST_H = 17

-- Custom nameplate border (opt-in) -----------------------------------------
-- Per-style/size offset defaults for the shared border engine (mirrors Unit Frames). do/end
-- keeps these locals from leaking (file is near Lua 5.1's main-chunk local cap).
do
    if CludesUI and CludesUI.RegisterBorderDefaults then
        local function AllSizes(ox, oy, sx, sy)
            local t = {}
            for k = 0, 4 do
                t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy }
            end
            return t
        end
        CludesUI.RegisterBorderDefaults("nameplates", {
            ["glow"] = { defaultSize = 1, sizes = AllSizes(0, 0, 0, 0) },
            ["blizz"] = {
                defaultSize = 4,
                sizes = {
                    [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                    [1] = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                    [2] = { offsetX = 3, offsetY = 1, shiftX = 1, shiftY = 0 },
                    [3] = { offsetX = 4, offsetY = 2, shiftX = 2, shiftY = 0 },
                    [4] = { offsetX = 5, offsetY = 3, shiftX = 2, shiftY = 0 },
                },
            },
            ["dialog"] = {
                defaultSize = 2,
                sizes = {
                    [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                    [1] = { offsetX = 2, offsetY = 2, shiftX = 0, shiftY = 0 },
                    [2] = { offsetX = 2, offsetY = 2, shiftX = 0, shiftY = 0 },
                    [3] = { offsetX = 4, offsetY = 4, shiftX = 0, shiftY = 0 },
                    [4] = { offsetX = 8, offsetY = 8, shiftX = 0, shiftY = 0 },
                },
            },
            ["sm:Blizzard Achievement Wood"] = { defaultSize = 1, sizes = AllSizes(1, 1, 0, 0) },
        })
    end
end

-- Custom border apply helpers. Read the enemy profile `p` (friendly plates mirror it 1:1) and
-- route through the shared border engine. Lives on plate._customBorder (a child frame we own)
-- so it never collides with the simple PP.CreateBorder on plate.health. ns fields, not new
-- file-scope locals (local cap).
function mod.IsCustomBorderEnabled()
    -- Stock styles: the Blizzard background art, or the classic plate's plain
    -- 1px edge, stands in for the custom border.
    if mod.NP_Blizz() then
        return false
    end
    local val = p and p.customBorderEnabled
    if val == nil then
        return defaultSet.customBorderEnabled
    end
    return val
end
-- szOverride: optional size for the "Border Size" target effect (rebuilds at that size).
function mod.ApplyCustomBorderStyle(backing, szOverride)
    if not backing or not backing.health then
        return
    end
    if not (CludesUI and CludesUI.ApplyBorderStyle) then
        return
    end
    local texture = (p and p.customBorderTexture) or defaultSet.customBorderTexture
    local sz = szOverride or (p and p.customBorderSize) or defaultSet.customBorderSize
    -- Exact pixel size (customBorderSizePx) counts only for the plate's own size; a
    -- target/hover effect size is a substitute and keeps the legacy path.
    local px
    if not szOverride then
        px = CludesUI.BorderPx(p and p.customBorderSizePx, sz, texture)
    end
    local colour = (p and p.customBorderColor) or defaultSet.customBorderColor
    local a = (p and p.customBorderAlpha) or defaultSet.customBorderAlpha or 1
    local behind = p and p.customBorderBehind
    if behind == nil then
        behind = defaultSet.customBorderBehind
    end
    local bf = backing._customBorder
    if not bf then
        bf = CreateFrame("Frame", nil, backing.health)
        bf:SetAllPoints(backing.health)
        backing._customBorder = bf
        -- Plates move by sub-pixels: the Pixels styles need their edge fill.
        CludesUI.SetBorderEdgeFill(bf, true)
    end
    -- Health bars flatten render layers: a BORDER-layer backdrop would be clipped by the
    -- ARTWORK health fill, so lift it onto MEDIUM strata (same escape the plate uses for
    -- text/aura layers). Set before ApplyBorderStyle so any backdrop child it creates inherits it.
    bf:SetFrameStrata("MEDIUM")
    bf:SetFrameLevel(
        behind and math.max(1, backing.health:GetFrameLevel() - 1) or (backing.health:GetFrameLevel() + 1)
    )
    CludesUI.ApplyBorderStyle(
        bf,
        sz,
        colour.r,
        colour.g,
        colour.b,
        a,
        texture,
        p and p.customBorderOffset,
        p and p.customBorderOffsetY,
        p and p.customBorderShiftX,
        p and p.customBorderShiftY,
        "nameplates",
        sz,
        nil,
        px
    )
    -- Solid strips need the scaleGuard the Basic border has, or Scale Target/Casting
    -- Nameplate leaves them sub-pixel and their sides vanish as the plate moves.
    if Pix.GetBorders(bf) then
        Pix.CreateBorder(bf, nil, nil, nil, nil, nil, nil, nil, true)
    end
    -- The size it is drawn at (a target/hover effect size included): the cast bar
    -- wrap's lower piece and seam copy it (ns.NP_UpdateCustomBorderWrap).
    bf._cbTex, bf._cbSz, bf._cbPx = texture, sz, px
    -- A target/hover effect size redraws a rounded glow at that size (ApplyBorder
    -- rounds after its own call).
    if szOverride and backing._npRounded then
        mod.NP_ApplyRounding(backing, "health")
    end
end
function mod.ApplyCustomBorderColor(backing)
    if not backing or not backing._customBorder then
        return
    end
    if not (CludesUI and CludesUI.SetBorderStyleColor) then
        return
    end
    local colour = (p and p.customBorderColor) or defaultSet.customBorderColor
    local a = (p and p.customBorderAlpha) or defaultSet.customBorderAlpha or 1
    CludesUI.SetBorderStyleColor(backing._customBorder, colour.r, colour.g, colour.b, a)
end
function mod.HideCustomBorder(backing)
    local bf = backing and backing._customBorder
    if bf and CludesUI and CludesUI.ApplyBorderStyle then
        -- A border wrapping the cast bar gets its anchors back first.
        if backing._cbWrapActive then
            mod.NP_UnwrapCustomBorder(backing)
        end
        CludesUI.ApplyBorderStyle(bf, 0)
        bf:Hide()
    end
end

-- Wrap Around Castbar, custom border (called from plate:UpdateBorderWrap, which also
-- runs the Basic wrap). The custom border is one frame lifted to MEDIUM strata above
-- the plate's flattened layer, so while the cast bar sits in the plate that frame
-- itself spans the health bar's top to the cast bar's bottom. Casts In Front of
-- Nameplates moves the cast bar out of the plate: the border then stays on the health
-- bar and a lower piece (a child of the cast bar, drawn with the border's style, size
-- and live colour) spans the health bar's bottom to the cast bar's bottom. The two
-- pieces drop the edges where they touch (solid: the strips; textured: the backdrop
-- pieces, ns.NP_SetWrapJoin), so both modes draw the same single outline and the seam
-- follows Show Seam Line alone. While wrapped, the cast bar's 1px icon separator is
-- hidden (the Basic wrap's rule). Unwrapping only re-anchors the frame or drops the
-- lower piece, so a border a target or hover effect resized keeps that size. Own flag:
-- plate._cbWrapActive. ns fields (local cap).
function mod.NP_UpdateCustomBorderWrap(backing)
    local bf, cast = backing._customBorder, backing.cast
    if
        not (
            bf
            and bf._cbSz
            and cast
            and mod.GetWrapBorderCastbar()
            and cast:IsShown()
            and mod.IsCustomBorderEnabled()
        )
    then
        if backing._cbWrapActive then
            mod.NP_UnwrapCustomBorder(backing)
        end
        return
    end
    local CUI = CludesUI
    local texture, sz, px = bf._cbTex, bf._cbSz, bf._cbPx
    local solid = not texture or texture == "" or texture == "solid"
    -- The colour the border shows right now (base, hover or target), read back from it.
    local uc = Pix.GetBorders(bf)
    local red, green, blue, a
    local edge = not solid and CUI._bdBorderData[bf]
    if edge then
        red, green, blue, a = edge:GetBackdropBorderColor()
    elseif uc and uc._bdColor then
        local c = uc._bdColor
        red, green, blue, a = c[1], c[2], c[3], c[4] or 1
    end
    if not red then
        local c = (p and p.customBorderColor) or defaultSet.customBorderColor
        red, green, blue, a = c.r, c.g, c.b, (p and p.customBorderAlpha) or defaultSet.customBorderAlpha or 1
    end
    if backing._castOverlayLifted then
        if backing._cbWrapMode == "single" then
            bf:ClearAllPoints()
            bf:SetAllPoints(backing.health)
            mod.NP_SetWrapSeam(bf, nil, false)
        end
        backing._cbWrapMode = "split"
        local lower = backing._cbWrapLower
        if not lower then
            lower = CreateFrame("Frame", nil, cast)
            lower:SetPoint("TOPLEFT", backing.health, "BOTTOMLEFT", 0, 0)
            lower:SetPoint("TOPRIGHT", backing.health, "BOTTOMRIGHT", 0, 0)
            lower:SetPoint("BOTTOM", cast, "BOTTOM", 0, 0)
            backing._cbWrapLower = lower
            CUI.SetBorderEdgeFill(lower, true)
        end
        -- Above the cast spell icon, re-set every pass (a strata change on the lifted
        -- cast bar resets its children's levels).
        local lvl = (backing.castIconFrame and backing.castIconFrame:GetFrameLevel() or cast:GetFrameLevel())
            + 2
        local offX, offY = p and p.customBorderOffset, p and p.customBorderOffsetY
        local shX, shY = p and p.customBorderShiftX, p and p.customBorderShiftY
        -- Full restyle only when a style input moved, the level was reset or the piece
        -- is down; a colour change alone is a tint.
        if
            not lower:IsShown()
            or lower:GetFrameLevel() ~= lvl
            or lower._sTex ~= texture
            or lower._sSz ~= sz
            or lower._sPx ~= px
            or lower._sOX ~= offX
            or lower._sOY ~= offY
            or lower._sSX ~= shX
            or lower._sSY ~= shY
        then
            lower:SetFrameLevel(lvl)
            CUI.ApplyBorderStyle(
                lower,
                sz,
                red,
                green,
                blue,
                a,
                texture,
                offX,
                offY,
                shX,
                shY,
                "nameplates",
                sz,
                nil,
                px
            )
            if Pix.GetBorders(lower) then
                Pix.CreateBorder(lower, nil, nil, nil, nil, nil, nil, nil, true)
            end
            lower._sTex, lower._sSz, lower._sPx = texture, sz, px
            lower._sOX, lower._sOY, lower._sSX, lower._sSY = offX, offY, shX, shY
        else
            CUI.SetBorderStyleColor(lower, red, green, blue, a)
        end
        -- Solid strips: hide the two that touch so the pieces read as one outline (the
        -- flags survive every re-snap and are cleared on unwrap).
        local join = solid or nil
        if uc and uc._hideBottom ~= join then
            uc._hideBottom = join
            if uc:IsShown() then
                Pix.SetBorderSize(bf, px or sz)
            end
        end
        local lc = Pix.GetBorders(lower)
        if lc and lc._hideTop ~= join then
            lc._hideTop = join
            if lc:IsShown() then
                Pix.SetBorderSize(lower, px or sz)
            end
        end
        -- Textured: the same join from the backdrop pieces (off for solid).
        mod.NP_SetWrapJoin(backing, not solid, texture, red, green, blue, a)
        mod.NP_SetWrapSeam(
            lower,
            cast,
            (p and p.wrapBorderSeam) == true,
            texture,
            sz,
            px,
            red,
            green,
            blue,
            a,
            backing.health
        )
    else
        if backing._cbWrapMode == "split" then
            mod.NP_DropCustomWrapLower(backing)
        end
        if backing._cbWrapMode ~= "single" then
            bf:ClearAllPoints()
            bf:SetPoint("TOPLEFT", backing.health, "TOPLEFT", 0, 0)
            bf:SetPoint("TOPRIGHT", backing.health, "TOPRIGHT", 0, 0)
            bf:SetPoint("BOTTOM", cast, "BOTTOM", 0, 0)
            backing._cbWrapMode = "single"
        end
        mod.NP_SetWrapSeam(
            bf,
            cast,
            (p and p.wrapBorderSeam) == true,
            texture,
            sz,
            px,
            red,
            green,
            blue,
            a,
            backing.health
        )
    end
    backing._cbWrapActive = true
    -- The 1px icon separator would show inside the outline (NP_UnwrapCustomBorder
    -- gives it back).
    if backing.castLeftBorder then
        backing.castLeftBorder:Hide()
    end
    -- Tint the full-size cast icon's border like the wrapped bar (the Basic wrap's rule).
    local iconTex = backing.castIconFrame
    if iconTex and Pix.GetBorders(iconTex) then
        if
            p
            and p.castIconTargetBorder
            and mod.GetShowCastIcon()
            and mod.GetCastIconFullSize()
            and backing.unit
            and UnitIsUnit(backing.unit, "target")
            and mod.GetTargetGlowBorderColor()
        then
            Pix.SetBorderColor(iconTex, red, green, blue, a)
        else
            Pix.SetBorderColor(iconTex, 0, 0, 0, 1)
        end
    end
end
-- Textured split wrap: a backdrop cannot drop one strip the way the solid pieces do,
-- so the touching art is hidden piece by piece on the two backdrop frames (ours): the
-- upper piece's bottom edge and bottom corners, the lower piece's top edge and top
-- corners. Two fillers on the lower piece, drawn with the style's own side-edge art,
-- run each side line from where the upper piece's stops (its hidden bottom corner's
-- top) to where the lower piece's starts (its hidden top corner's bottom), so the two
-- pieces draw the single-frame outline. A backdrop re-layout (restyle, UI scale)
-- re-anchors its pieces but never shows them, and the fillers ride the corners'
-- anchors. on = false gives the upper piece its bottom back and drops the fillers;
-- the lower piece is only ever the lower piece, so its top stays down.
function mod.NP_SetWrapJoin(backing, enabled, texture, red, green, blue, a)
    local bf, lower = backing._customBorder, backing._cbWrapLower
    local bdData = CludesUI._bdBorderData
    local ubd = enabled and bf and bdData[bf]
    local lbd = enabled and lower and bdData[lower]
    -- Off, or the two backdrops not both drawn and laid out: give the upper piece its
    -- bottom back and drop the fillers. A joined lower piece keeps its top down, which
    -- only matters while it draws, and every setting that stops one backdrop drawing
    -- (size 0, a missing border file) stops both.
    if
        not (ubd and lbd and ubd:IsShown() and lbd:IsShown() and ubd.BottomLeftCorner and lbd.TopLeftCorner)
    then
        local joined = bf and bf._cbJoinBd
        if joined then
            joined.BottomEdge:Show()
            joined.BottomLeftCorner:Show()
            joined.BottomRightCorner:Show()
            bf._cbJoinBd = nil
            CludesUI.SyncBorderEdgeFill(bf)
        end
        if lower and lower._cbFillL then
            lower._cbFillL:Hide()
            lower._cbFillR:Hide()
        end
        return
    end
    ubd.BottomEdge:Hide()
    ubd.BottomLeftCorner:Hide()
    ubd.BottomRightCorner:Hide()
    bf._cbJoinBd = ubd
    lbd.TopEdge:Hide()
    lbd.TopLeftCorner:Hide()
    lbd.TopRightCorner:Hide()
    CludesUI.SyncBorderEdgeFill(bf)
    CludesUI.SyncBorderEdgeFill(lower)
    local fl, fr = lower._cbFillL, lower._cbFillR
    if not fl then
        fl = lower:CreateTexture(nil, "BORDER")
        fr = lower:CreateTexture(nil, "BORDER")
        fl:SetPoint("TOPLEFT", ubd.BottomLeftCorner, "TOPLEFT", 0, 0)
        fl:SetPoint("BOTTOMRIGHT", lbd.TopLeftCorner, "BOTTOMRIGHT", 0, 0)
        fr:SetPoint("TOPRIGHT", ubd.BottomRightCorner, "TOPRIGHT", 0, 0)
        fr:SetPoint("BOTTOMLEFT", lbd.TopRightCorner, "BOTTOMLEFT", 0, 0)
        lower._cbFillL, lower._cbFillR = fl, fr
    end
    if lower._cbFillTex ~= texture then
        local filePath = CludesUI.ResolveBorderTexture(texture)
        fl:SetTexture(filePath)
        fr:SetTexture(filePath)
        -- The left and right edge cells of the edge file, trimmed as the backdrop
        -- trims every cell (texels 2-30 of 32).
        fl:SetTexCoord(0.0078125, 0.1171875, 0.0625, 0.9375)
        fr:SetTexCoord(0.1328125, 0.2421875, 0.0625, 0.9375)
        lower._cbFillTex = texture
    end
    fl:SetVertexColor(red, green, blue, a)
    fr:SetVertexColor(red, green, blue, a)
    fl:Show()
    fr:Show()
end
-- Takes the Casts In Front lower piece and its seam down, and gives the border back
-- its bottom (solid strip or textured pieces). Turned off through
-- ApplyBorderStyle(lower, 0) so the UI scale re-apply cannot bring it back.
function mod.NP_DropCustomWrapLower(backing)
    mod.NP_SetWrapJoin(backing, false)
    local lower = backing._cbWrapLower
    if lower then
        mod.NP_SetWrapSeam(lower, nil, false)
        local lc = Pix.GetBorders(lower)
        if lc then
            lc._hideTop = nil
        end
        CludesUI.ApplyBorderStyle(lower, 0)
        lower:Hide()
        lower._sTex = nil
    end
    local bf = backing._customBorder
    local uc = bf and Pix.GetBorders(bf)
    if uc and uc._hideBottom then
        uc._hideBottom = nil
        if uc:IsShown() then
            Pix.SetBorderSize(bf, bf._cbPx or bf._cbSz or 1)
        end
    end
end
function mod.NP_UnwrapCustomBorder(backing)
    local mode = backing._cbWrapMode
    backing._cbWrapActive, backing._cbWrapMode = nil, nil
    if mode == "split" then
        mod.NP_DropCustomWrapLower(backing)
    else
        local bf = backing._customBorder
        if bf then
            bf:ClearAllPoints()
            bf:SetAllPoints(backing.health)
            mod.NP_SetWrapSeam(bf, nil, false)
        end
    end
    -- The icon separator comes back unless the Basic wrap (this same pass) owns it now.
    if backing.castLeftBorder and not backing._wrapActive then
        backing.castLeftBorder:Show()
    end
    if backing.castIconFrame and Pix.GetBorders(backing.castIconFrame) then
        Pix.SetBorderColor(backing.castIconFrame, 0, 0, 0, 1)
    end
end

-- "Show Seam Line": only a border style with separator art draws one (the Pixels styles).
function mod.NP_CanShowWrapSeam(texture)
    return CludesUI.GetBorderCompanion(texture, "sepH") ~= nil
end
-- A divider along anchor's top edge (the cast bar's), spanning the health bar's
-- width even when the cast bar reserves space for its icon. A lazy child of owner
-- (a border frame we own) above its border art, tinted like the live border.
-- tex / step / px = the texture key, size step and exact px the border is drawn at.
-- Shared by the live plates and the options preview.
function mod.NP_SetWrapSeam(ownerFrame, anchor, show, texture, step, px, red, green, blue, a, health)
    local owner = ownerFrame and ownerFrame._cbSeamHost
    if not show or not mod.NP_CanShowWrapSeam(texture) then
        if owner and owner:IsShown() then
            owner:Hide()
            CludesUI.RegisterPxReapply(owner, nil)
        end
        return
    end
    if not owner then
        owner = Pool.CreateFrame("Frame", nil, ownerFrame)
        owner:SetAllPoints(ownerFrame)
        owner._seam = owner:CreateTexture(nil, "OVERLAY", nil, 7)
        ownerFrame._cbSeamHost = owner
    end
    -- Above the border's backdrop (owner level) and its pixel strips (owner level + 1).
    owner:SetFrameLevel(ownerFrame:GetFrameLevel() + 2)
    owner._seamAnchor, owner._seamTex, owner._seamStep, owner._seamPx = anchor, texture, step, px
    owner._seamHealth = health
    owner._seam:SetVertexColor(red, green, blue, a)
    owner:Show()
    mod.NP_LayoutWrapSeam(owner)
    -- An exact size is pixels at UIParent scale: re-lay the seam when the pixel grid moves.
    CludesUI.RegisterPxReapply(owner, px and mod.NP_LayoutWrapSeam or nil)
end
function mod.NP_LayoutWrapSeam(owner)
    local t, anchor, health = owner._seam, owner._seamAnchor, owner._seamHealth
    if not (t and anchor and health) then
        return
    end
    local CUI = CludesUI
    local texture, step, px = owner._seamTex, owner._seamStep, owner._seamPx
    local es = owner:GetEffectiveScale()
    if not (es and es > 0.01) then
        es = UIParent:GetEffectiveScale()
    end
    local filePath = CUI.GetBorderCompanion(texture, "sepH")
    local thick = filePath and CUI.BorderCompanionThickness(texture, step, px, es)
    if not thick or thick <= 0 then
        t:Hide()
        return
    end
    -- The strip's line sits near its top edge: raising it 3/16 of its thickness
    -- puts the line on the join, where the border's own line runs.
    local raise = Pix.SnapForES(thick * 3 / 16, es)
    if owner._seamPath ~= filePath then
        t:SetTexture(filePath)
        owner._seamPath = filePath
    end
    if
        owner._lThick ~= thick
        or owner._lRaise ~= raise
        or owner._lAnchor ~= anchor
        or owner._lHealth ~= health
    then
        t:ClearAllPoints()
        t:SetPoint("TOP", anchor, "TOP", 0, raise)
        t:SetPoint("LEFT", health, "LEFT", 0, 0)
        t:SetPoint("RIGHT", health, "RIGHT", 0, 0)
        t:SetHeight(thick)
        owner._lThick, owner._lRaise, owner._lAnchor = thick, raise, anchor
        owner._lHealth = health
    end
    t:Show()
end

-- Main-chunk locals the CUI_Nameplates_*.lua files re-import by name.
-- profileSetters: every file keeps its own copy of the profile alias p and
-- adds a setter here; the places that re-read the profile write through
-- SetProfile, which runs them all.
-- broken: true while an CUI_Nameplates_*.lua file loads; a file that fails
-- leaves it set, and the files behind it return at their first lines.
CludesUI.NewInternals(mod, "_npInternals", {
    _npYOffsetState = _npYOffsetState,
    BAR_W = BAR_W,
    CAST_H = CAST_H,
    defaults = defaultSet,
    ENP = ENP,
    GetFont = GetFont,
    GetNPOutline = GetNPOutline,
    HP_BAR_SLOTS = HP_BAR_SLOTS,
    SetFSFont = SetFSFont,
    profileSetters = {
        function(val)
            p = val
        end,
    },
    classPowerTypeSetters = {},
}, { SetProfile = "profileSetters", SetClassPowerType = "classPowerTypeSetters" })
