if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI.lua  -  Custom Options Panel, shared across the whole CUI suite.
--  Scaffold: background, sidebar, header, content area, controls.
-------------------------------------------------------------------------------
-- CUI_NS is this addon's private namespace (the TOC vararg): shared by the core
-- files, unreachable from any other addon. Navigation state that must not be
-- writable by third-party code (module registry, sidebar model, page cache)
-- lives here instead of on the global CludesUI table.
local CUI_HOST_ADDON, CUI_NS = ...
-- Build renames "CludesUI" -> "CUICoreStandalone<Module>" but never the word
-- "Standalone", so host name contains it iff standalone; false in the suite (branches inert).
local IS_STANDALONE = type(CUI_HOST_ADDON) == "string" and CUI_HOST_ADDON:find("Standalone") ~= nil
-- A standalone build is ONE addon: its module files share this vararg table
-- and publish it through _ModuleNS. So there the core's private state lives in
-- a table of its own, handed to the later core files through __cuiCoreNS until
-- the first module publish removes that slot (see _ModuleNS).
if IS_STANDALONE then
    local sharedMedia = CUI_NS
    CUI_NS = {}
    sharedMedia.__cuiCoreNS = CUI_NS
end
-------------------------------------------------------------------------------
--  Constants & Colours
-------------------------------------------------------------------------------
--  Visual Settings  (edit these to adjust the look -- values only, no tables)
-------------------------------------------------------------------------------
-- Accent colour -- canonical default: #4CC9F0 teal. The Forever client opens
-- on #DCA77F (soft bronze) instead; a chosen accent always wins over this.
local DEFAULT_ACCENT_R, DEFAULT_ACCENT_G, DEFAULT_ACCENT_B = 76 / 255, 201 / 255, 240 / 255
if CUI_CLIENT_FOREVER == true then
    DEFAULT_ACCENT_R, DEFAULT_ACCENT_G, DEFAULT_ACCENT_B = 220 / 255, 167 / 255, 127 / 255
end

-- Theme presets: { accentR, accentG, accentB, bgFile }
-- bgFile is relative to MEDIA_PATH (resolved later after MEDIA_PATH is defined)
local THEME_PRESETS = {
    ["CludesUI"] = { r = 76 / 255, g = 201 / 255, b = 240 / 255 }, -- #4CC9F0
    ["CludesUI Original"] = { r = 76 / 255, g = 201 / 255, b = 240 / 255 }, -- #4CC9F0 (not listed; kept for saved settings)
    ["CludesUI Forever"] = { r = 220 / 255, g = 167 / 255, b = 127 / 255 }, -- #DCA77F soft bronze
    ["Horde"] = { r = 255 / 255, g = 90 / 255, b = 31 / 255 }, -- #FF5A1F
    ["Alliance"] = { r = 63 / 255, g = 167 / 255, b = 255 / 255 }, -- #3FA7FF
    ["Faction (Auto)"] = nil, -- resolved at runtime to Horde or Alliance
    ["Midnight"] = { r = 120 / 255, g = 65 / 255, b = 200 / 255 }, -- #7841C8  deep purple void
    ["Dark"] = { r = 1, g = 1, b = 1 }, -- white accent
    ["Pixels"] = { r = 1, g = 1, b = 1 }, -- white accent
    ["Ember"] = { r = 255 / 255, g = 122 / 255, b = 26 / 255 }, -- #FF7A1A warm orange
    ["Blood"] = { r = 215 / 255, g = 38 / 255, b = 61 / 255 }, -- #D7263D crimson
    ["Frost"] = { r = 76 / 255, g = 201 / 255, b = 240 / 255 }, -- #4CC9F0 ice blue (now the house colour; not listed, kept for saved settings)
    ["Arcane"] = { r = 155 / 255, g = 107 / 255, b = 255 / 255 }, -- #9B6BFF bright violet
    ["Gold"] = { r = 230 / 255, g = 180 / 255, b = 80 / 255 }, -- #E6B450 muted gold
    ["Toxic"] = { r = 166 / 255, g = 226 / 255, b = 46 / 255 }, -- #A6E22E lime green
    ["Class Colored"] = nil, -- resolved at runtime from player class
    ["Custom Color"] = nil, -- user-chosen via color picker
}
local THEME_ORDER = {
    "CludesUI",
    "CludesUI Forever",
    "Horde",
    "Alliance",
    "Faction (Auto)",
    "Midnight",
    "Dark",
    "Pixels",
    "Ember",
    "Blood",
    "Arcane",
    "Gold",
    "Toxic",
    "Class Colored",
    "Custom Color",
}
-- "CludesUI Forever" is the WoW Forever look: only that client lists it.
if CUI_CLIENT_FOREVER ~= true then
    table.remove(THEME_ORDER, 2)
end
-- The theme in force when none was chosen: the Forever client opens on its own
-- backdrop, every other client on the blue CludesUI theme. A chosen theme always wins.
CludesUI.DEFAULT_THEME = (CUI_CLIENT_FOREVER == true) and "CludesUI Forever" or "CludesUI"
-- Background file paths per theme (relative to MEDIA_PATH, in backgrounds/ subfolder)
local THEME_BG_FILES = {
    ["CludesUI"] = "backgrounds\\cui-bg-new.png",
    ["CludesUI Original"] = "backgrounds\\cui-bg-new.png",
    ["CludesUI Forever"] = "backgrounds\\cui-bg-forever-compressed.png",
    ["Horde"] = "backgrounds\\cui-bg-new.png",
    ["Alliance"] = "backgrounds\\cui-bg-new.png",
    ["Midnight"] = "backgrounds\\cui-bg-new.png",
    ["Dark"] = "backgrounds\\cui-bg-new.png",
    ["Pixels"] = "backgrounds\\cui-bg-new.png",
    -- The six colour schemes share the tintable art: the panel desaturates it
    -- and tints it to the scheme's accent, as it does for Class Colored.
    ["Ember"] = "backgrounds\\cui-bg-new.png",
    ["Blood"] = "backgrounds\\cui-bg-new.png",
    ["Frost"] = "backgrounds\\cui-bg-new.png",
    ["Arcane"] = "backgrounds\\cui-bg-new.png",
    ["Gold"] = "backgrounds\\cui-bg-new.png",
    ["Toxic"] = "backgrounds\\cui-bg-new.png",
    ["Class Colored"] = "backgrounds\\cui-bg-new.png",
    ["Custom Color"] = "backgrounds\\cui-bg-new.png",
}
-- Theme art is not loaded at file load: each file is a 1500x1154 canvas, and
-- holding every theme in VRAM costs tens of MB for a panel most sessions never
-- open. A theme loads on its first pick (the crossfade starts the new layer at
-- alpha 0, so nothing flashes), or at PLAYER_LOGIN for the player whose saved
-- theme it is (CludesUI._PreloadLazyThemeBG).
-- Accent overlay per theme: its accent-coloured pieces (logo mark, rules, close X)
-- as white art, cropped to their band of the 1500x1154 canvas (x, y = top-left
-- offset; w, h = size, all in canvas units). Drawn above the theme art and tinted
-- with the live UI accent; built on the theme's first apply (CreateMainFrame).
CludesUI.THEME_ACCENT_OVERLAYS = {}
-- The close box painted into each theme art file, in canvas units: x, y, w, h =
-- tight rect around its border; bx, by, bw, bh = outer rect of the border line
-- itself and bd = its depth (the hover glow lights only that ring); gx, gy =
-- centre of its X; gs = glyph size drawn over a copy (16 when absent); r, g, b =
-- the X colour; sh = alpha of the dark rim under a glyph; acc = alpha of a
-- live-accent glyph stacked on top (art whose X comes from its accent overlay);
-- ex, ey = top-left of the 76 unit square around the painted logo emblem; rr, rg,
-- rb = the logo badge ring colour. The collapse button and the collapsed mini
-- window rebuild their boxes and badge from these rects of the art on screen.
CludesUI.THEME_CLOSE_BOX = {
    ["backgrounds\\cui-bg-new.png"] = {
        x = 1345,
        y = 115,
        w = 44,
        h = 43,
        gx = 1367,
        gy = 136,
        bx = 1346,
        by = 116,
        bw = 42,
        bh = 41,
        bd = 2,
        r = 0.686,
        g = 0.718,
        b = 0.714,
        sh = 0.5,
        ex = 118,
        ey = 110,
        rr = 0.324,
        rg = 0.345,
        rb = 0.363,
    },
    ["backgrounds\\cui-bg-forever-compressed.png"] = {
        x = 1346,
        y = 114,
        w = 43,
        h = 41,
        gx = 1368,
        gy = 134,
        bx = 1348,
        by = 116,
        bw = 40,
        bh = 38,
        bd = 3,
        r = 0.894,
        g = 0.788,
        b = 0.617,
        sh = 0.5,
        ex = 122,
        ey = 109,
        rr = 0.417,
        rg = 0.311,
        rb = 0.231,
    },
}

--- Resolve "Faction (Auto)" to Horde/Alliance by player faction; other themes unchanged.
local function ResolveFactionTheme(skinName)
    if skinName == "Faction (Auto)" then
        local faction = UnitFactionGroup("player")
        return (faction == "Horde") and "Horde" or "Alliance"
    end
    return skinName
end

-- Hidden 1x1 frame preloads the saved theme into VRAM: no 1-frame bg flash on first open.
do
    local mp = "Interface\\AddOns\\CludesUI\\media\\"
    local preloadFn = CreateFrame("Frame")
    preloadFn:SetSize(1, 1)
    preloadFn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
    preloadFn:Show()
    local baseTex = preloadFn:CreateTexture()
    baseTex:SetTexture(mp .. "backgrounds\\cui-bg.png")
    baseTex:SetAllPoints()
    -- The saved theme is known only once SavedVariables load, so the PLAYER_LOGIN
    -- theme block calls this (once): the player then opens the panel with
    -- their theme's art, and its accent overlay, already resident.
    function CludesUI._PreloadLazyThemeBG(skinName)
        skinName = ResolveFactionTheme(skinName)
        local file = THEME_BG_FILES[skinName] or THEME_BG_FILES["CludesUI"]
        local texture = preloadFn:CreateTexture()
        texture:SetTexture(mp .. file)
        texture:SetAllPoints()
        local shade = CludesUI.THEME_ACCENT_OVERLAYS[skinName]
        if shade then
            local ovTex = preloadFn:CreateTexture()
            ovTex:SetTexture(mp .. shade.file)
            ovTex:SetAllPoints()
        end
    end
end

-- CludesUIDB arrives from SavedVariables at ADDON_LOADED. Do NOT create it here --
-- that overwrites saved data. (Stale child SV copy guard lives in CludesUI_Lite.lua.)

-- Widget style constants, one table instead of ~75 file-scope locals, which
-- would push this main chunk past Lua 5.1's 200-active-locals limit. Read them
-- as STYLE.X here; other files get them through the CludesUI.X exports below.
local STYLE = {
    -- The dark surfaces below (and the options' popups) share one faint cool
    -- slate tint, matching the panel art, each at its own lightness.

    -- Panel background
    PANEL_BG_R = 0.069,
    PANEL_BG_G = 0.058,
    PANEL_BG_B = 0.047,

    -- Global border  (white + alpha -- adapts to any background tint)
    BORDER_R = 1,
    BORDER_G = 1,
    BORDER_B = 1,
    BORDER_A = 0.05,

    -- Text  (white + alpha -- adapts to any background tint)
    TEXT_WHITE_R = 1,
    TEXT_WHITE_G = 1,
    TEXT_WHITE_B = 1,
    TEXT_DIM_R = 1,
    TEXT_DIM_G = 1,
    TEXT_DIM_B = 1,
    TEXT_DIM_A = 0.53,
    TEXT_SECTION_R = 1,
    TEXT_SECTION_G = 1,
    TEXT_SECTION_B = 1,
    TEXT_SECTION_A = 0.41,

    -- Row alternating background alpha  (black overlay on option rows)
    ROW_BG_ODD = 0.1,
    ROW_BG_EVEN = 0.2,

    -- Slider  (white + alpha for track -- adapts to any background tint)
    SL_TRACK_R = 1,
    SL_TRACK_G = 1,
    SL_TRACK_B = 1, -- track bg (white + alpha)
    SL_TRACK_A = 0.16, -- track bg alpha
    SL_FILL_A = 0.75, -- filled portion alpha (colour = accent)
    SL_INPUT_R = 0.030,
    SL_INPUT_G = 0.023,
    SL_INPUT_B = 0.018, -- input box background (darker than bg, stays as-is)
    SL_INPUT_A = 0.25, -- input box alpha (all sliders)
    SL_INPUT_BRD_A = 0.12, -- input box border alpha (white; a visible outline, dimmer than a dropdown's)

    -- Multi-widget slider overrides  (applied additively in BuildSliderCore)
    MW_INPUT_ALPHA_BOOST = 0.15, -- additive alpha boost for multi-widget input fields
    MW_TRACK_ALPHA_BOOST = 0.06, -- additive alpha boost for multi-widget slider track

    -- Toggle  (white + alpha for off states -- adapts to any background tint)
    TG_OFF_R = 0.267,
    TG_OFF_G = 0.267,
    TG_OFF_B = 0.267, -- track when OFF (#444)
    TG_OFF_A = 0.65, -- track OFF alpha
    TG_ON_A = 0.75, -- track alpha at full ON (colour = accent)
    TG_KNOB_OFF_R = 1,
    TG_KNOB_OFF_G = 1,
    TG_KNOB_OFF_B = 1, -- knob when OFF (white + alpha)
    TG_KNOB_OFF_A = 0.5, -- knob OFF alpha
    TG_KNOB_ON_R = 1,
    TG_KNOB_ON_G = 1,
    TG_KNOB_ON_B = 1, -- knob when ON
    TG_KNOB_ON_A = 1, -- knob ON alpha

    -- Checkbox
    CB_BOX_R = 0.112,
    CB_BOX_G = 0.105,
    CB_BOX_B = 0.098, -- box background
    CB_BRD_A = 0.05,
    CB_ACT_BRD_A = 0.15, -- box border alpha / checked border alpha

    -- Button / WideButton
    BTN_BG_R = 0.089,
    BTN_BG_G = 0.080,
    BTN_BG_B = 0.072, -- background
    BTN_BG_A = 0.6,
    BTN_BG_HA = 0.65, -- background alpha hovered
    BTN_BRD_A = 0.3, -- border alpha (colour = white)
    BTN_BRD_HA = 0.45, -- border alpha hovered
    BTN_TXT_A = 0.55, -- text alpha (colour = white)
    BTN_TXT_HA = 0.70, -- text alpha hovered

    -- Dropdown
    DD_BG_R = 0.103,
    DD_BG_G = 0.095,
    DD_BG_B = 0.088, -- background
    DD_BG_A = 0.9,
    DD_BG_HA = 0.98, -- background alpha hovered
    DD_BRD_A = 0.20, -- border alpha (colour = white)
    DD_BRD_HA = 0.30, -- border alpha hovered
    DD_TXT_A = 0.50, -- selected value text alpha (colour = white)
    DD_TXT_HA = 0.60, -- selected value text alpha hovered
    DD_ITEM_HL_A = 0.12, -- menu item highlight alpha (hover)
    DD_ITEM_SEL_A = 0.08, -- menu item highlight alpha (active selection)

    -- Multi-widget layout  (dual = 2-up, triple = 3-up -- shared by all widget types)
    DUAL_ITEM_W = 350, -- width of each item in a 2-up row
    DUAL_GAP = 42, -- gap between 2-up items
    TRIPLE_ITEM_W = 180, -- width of each item in a 3-up row
    TRIPLE_GAP = 50, -- gap between 3-up items
}

-- Color swatch border (packed into table)
local CS = {
    BRD_THICK = 1,
    SAT_THRESH = 0.25,
    CHROMA_MIN = 0.15,
    SOLID_R = 1,
    SOLID_G = 1,
    SOLID_B = 1,
    SOLID_A = 1,
}

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  Derived / Internal  (built from visual settings -- no need to edit below)
-------------------------------------------------------------------------------
local CLUDES_GREEN
do
    -- CLASS_COLOR_MAP is defined below: parse time resolves presets only; Class/Custom resolve at PLAYER_LOGIN.
    local saved = CludesUIDB or {}
    local skinName = ResolveFactionTheme(saved.activeTheme or CludesUI.DEFAULT_THEME)
    local red, green, blue
    if skinName == "Custom Color" then
        local sa = saved.accentColor
        red, green, blue =
            sa and sa.r or DEFAULT_ACCENT_R, sa and sa.g or DEFAULT_ACCENT_G, sa and sa.b or DEFAULT_ACCENT_B
    else
        local presetRec = THEME_PRESETS[skinName]
        if presetRec then
            red, green, blue = presetRec.r, presetRec.g, presetRec.b
        else
            red, green, blue = DEFAULT_ACCENT_R, DEFAULT_ACCENT_G, DEFAULT_ACCENT_B
        end
    end
    CLUDES_GREEN = { r = red, g = green, b = blue, _themeEnabled = true }
end

-- Registry of accent-colored elements (sidebar indicators, glows, tab underlines,
-- footer buttons, popup confirm). Entry = { type="solid"|"gradient"|"font"|"callback", obj=... }
local _accentElements = { _idx = {} } -- _idx: obj -> index, prevents duplicates
local function RegAccent(record)
    local entryKey = record.obj or record.fn
    if entryKey and _accentElements._idx[entryKey] then
        _accentElements[_accentElements._idx[entryKey]] = record
    else
        _accentElements[#_accentElements + 1] = record
        if entryKey then
            _accentElements._idx[entryKey] = #_accentElements
        end
    end
end
local DARK_BG = { r = STYLE.PANEL_BG_R, g = STYLE.PANEL_BG_G, b = STYLE.PANEL_BG_B }
local BORDER_COLOR = { r = STYLE.BORDER_R, g = STYLE.BORDER_G, b = STYLE.BORDER_B, a = STYLE.BORDER_A }
local TEXT_WHITE = { r = STYLE.TEXT_WHITE_R, g = STYLE.TEXT_WHITE_G, b = STYLE.TEXT_WHITE_B }
local TEXT_DIM = { r = STYLE.TEXT_DIM_R, g = STYLE.TEXT_DIM_G, b = STYLE.TEXT_DIM_B, a = STYLE.TEXT_DIM_A }
local TEXT_SECTION =
    { r = STYLE.TEXT_SECTION_R, g = STYLE.TEXT_SECTION_G, b = STYLE.TEXT_SECTION_B, a = STYLE.TEXT_SECTION_A }

-- Dropdown widget colours: widgets reference DD_BG_*, DD_BRD_*, DD_TXT_* directly

local CONTENT_PAD = 45
local CONTENT_HEADER_TOP_PAD = 10 -- extra top padding on scroll content when header is present

-- Paths  (media lives in CludesUI/media inside the parent addon folder)
local ADDON_PATH = "Interface\\AddOns\\" .. CUI_HOST_ADDON .. "\\"
local MEDIA_PATH = "Interface\\AddOns\\CludesUI\\media\\"
local _, playerClass = UnitClass("player")

local CLASS_ART_MAP = {
    DEATHKNIGHT = "dk.png",
    DEMONHUNTER = "dh.png",
    DRUID = "druid.png",
    EVOKER = "evoker.png",
    HUNTER = "hunter.png",
    MAGE = "mage.png",
    MONK = "monk.png",
    PALADIN = "paladin.png",
    PRIEST = "priest.png",
    ROGUE = "rogue.png",
    SHAMAN = "shaman.png",
    WARLOCK = "warlock.png",
    WARRIOR = "warrior.png",
}

-- Official WoW class colors (from RAID_CLASS_COLORS)
local CLASS_COLOR_MAP = {
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 }, -- #C41E3A
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 }, -- #A330C9
    DRUID = { r = 1.00, g = 0.49, b = 0.04 }, -- #FF7C0A
    EVOKER = { r = 0.20, g = 0.58, b = 0.50 }, -- #33937F
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, -- #AAD372
    MAGE = { r = 0.25, g = 0.78, b = 0.92 }, -- #3FC7EB
    MONK = { r = 0.00, g = 1.00, b = 0.60 }, -- #00FF98
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, -- #F48CBA
    PRIEST = { r = 1.00, g = 1.00, b = 1.00 }, -- #FFFFFF
    ROGUE = { r = 1.00, g = 0.96, b = 0.41 }, -- #FFF468
    SHAMAN = { r = 0.00, g = 0.44, b = 0.87 }, -- #0070DD
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 }, -- #8788EE
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, -- #C69B6D
}

-- Class icon sprite-sheet UV grid (4-column sheet; left/right/top/bottom). Shared by
-- every module's class-icon rendering; TEXTURE path stays per consumer. Read-only.
CludesUI.CLASS_ICON_SPRITE_COORDS = {
    WARRIOR = { 0, 0.125, 0, 0.125 },
    MAGE = { 0.125, 0.25, 0, 0.125 },
    ROGUE = { 0.25, 0.375, 0, 0.125 },
    DRUID = { 0.375, 0.5, 0, 0.125 },
    EVOKER = { 0.5, 0.625, 0, 0.125 },
    HUNTER = { 0, 0.125, 0.125, 0.25 },
    SHAMAN = { 0.125, 0.25, 0.125, 0.25 },
    PRIEST = { 0.25, 0.375, 0.125, 0.25 },
    WARLOCK = { 0.375, 0.5, 0.125, 0.25 },
    PALADIN = { 0, 0.125, 0.25, 0.375 },
    DEATHKNIGHT = { 0.125, 0.25, 0.25, 0.375 },
    MONK = { 0.25, 0.375, 0.25, 0.375 },
    DEMONHUNTER = { 0.375, 0.5, 0.25, 0.375 },
}

-- CUI LEGENDS event roster (PERMANENT): the event winners + team members who
-- earned a spot in the suite's previews, with class-balancing filler names. The
-- Raid & Party Frames preview fills its slots 2-20 with these in this order (Name,
-- class and role travel together through its role sort; hpal = a holy paladin),
-- and Group Finder's settings preview names its sample members and applicants
-- from it, a member's own class first. Read-only.
-- Names that belong to other addons: the keys their nickname features look
-- this suite up by. Kept in one place; the unit and raid frame name code
-- reads them through ns.EXT_NICK.
CludesUI.EXT_NICK = {
    addon = "Elles" .. "mereUI", -- TimelineReminders
    nsKey = "E" .. "UI", -- NSAPI.GetName
    nsToggle = "E" .. "UI_NICKNAME_TOGGLE", -- NSAPI callback
    liquidFn = "GetNicknameFor" .. "Elles" .. "mereUI", -- LiquidAPI
    rgaModule = "elles" .. "mereui", -- RakGaming Aliases
}

CludesUI.PREVIEW_ROSTER = {
    { name = "Brannoc", class = "MONK", role = "TANK" },
    { name = "Grimjaw", class = "WARRIOR", role = "TANK" },
    { name = "Aldermere", class = "PALADIN", role = "HEALER", hpal = true },
    { name = "Wenlai", class = "MONK", role = "HEALER" },
    { name = "Thessaly", class = "PALADIN", role = "HEALER", hpal = true },
    { name = "Oakhollow", class = "DRUID", role = "HEALER" },
    { name = "Seraphine", class = "PALADIN", role = "HEALER", hpal = true },
    { name = "Halvard", class = "PALADIN", role = "HEALER", hpal = true },
    { name = "Velisande", class = "PRIEST", role = "DAMAGER" },
    { name = "Tidecaller", class = "SHAMAN", role = "DAMAGER" },
    { name = "Harrowind", class = "HUNTER", role = "DAMAGER" },
    { name = "Morgath", class = "DEATHKNIGHT", role = "DAMAGER" },
    { name = "Drakmoor", class = "DEMONHUNTER", role = "DAMAGER" },
    { name = "Embertide", class = "EVOKER", role = "DAMAGER" },
    { name = "Elyndra", class = "MAGE", role = "DAMAGER" },
    { name = "Fenwick", class = "ROGUE", role = "DAMAGER" },
    { name = "Zulkhar", class = "WARLOCK", role = "DAMAGER" },
    { name = "Luneth", class = "DRUID", role = "DAMAGER" },
    { name = "Stormhelm", class = "SHAMAN", role = "DAMAGER" },
}

-- Font (Expressway lives in CludesUI/media)
local EXPRESSWAY = MEDIA_PATH .. "fonts\\Expressway.ttf"

-- Locale system-font fallback for glyphs our fonts lack (CJK, Cyrillic). Resolved by
-- CludesUI_Locale.lua from the EFFECTIVE locale (client or override); nil = Expressway.
local LOCALE_FONT_FALLBACK = _G.CludesUI and _G.CludesUI._localeFont or nil
-------------------------------------------------------------------------------
--  Addon Roster  --  per-addon display name + search alias from CludesUI/media
-------------------------------------------------------------------------------
local ICONS_PATH = MEDIA_PATH .. "icons\\"

-------------------------------------------------------------------------------
--  Season M+ Portals -- single source of truth for every portal/teleport list in
--  the suite (Chat flyout, Minimap flyout, QoL /keys resolver, DataBars tooltip).
--  SEASON UPDATE: one entry per dungeon of the new Mythic+ pool, updated ONCE
--  here. Order = flyout grid order (top-left to bottom-right).
--    spellID     - primary teleport spell id
--    short       - abbreviated label used by the flyout buttons
--    dungeonID   - LFG dungeonID (GetLFGDungeonInfo name lookup)
--    names       - lowercase dungeon names + localized aliases (name -> spell)
--    altSpellIDs - optional variant teleport spell ids
-------------------------------------------------------------------------------
CludesUI.SEASON_PORTALS = {
    {
        spellID = 1286801,
        short = "BV",
        dungeonID = 3102,
        names = { "the blinding vale", "blinding vale", "слепящая долина" },
    },
    {
        spellID = 1286804,
        short = "VA",
        dungeonID = 3106,
        names = { "voidscar arena", "арена шрама бездны" },
    },
    {
        spellID = 1286807,
        short = "DoN",
        dungeonID = 3051,
        names = { "den of nalorakk", "den of nalorak", "берлога налоракка" },
    },
    {
        spellID = 1286809,
        short = "MR",
        dungeonID = 3090,
        names = { "murder row", "закоулок душегубов" },
    },
    {
        spellID = 1286812,
        short = "AoF",
        dungeonID = 3191,
        names = { "altar of fangs", "алтарь клыков" },
    },
    {
        spellID = 393256,
        short = "RLP",
        dungeonID = 2361,
        names = { "ruby life pools", "рубиновые омуты жизни" },
    },
    {
        spellID = 1286828,
        short = "ToS",
        dungeonID = 1694,
        names = { "temple of sethraliss", "храм сетралисс" },
    },
    {
        spellID = 1286831,
        short = "KR",
        dungeonID = 1785,
        names = { "kings' rest", "king's rest", "гробница королей" },
    },
}

-- Great Vault shortcut (Minimap button, Data Bars block, character sheet
-- season panel): loads Blizzard's vault on first use and toggles it directly,
-- so opening it closes no other panel (the UIPanel fit check would close the
-- character sheet). Escape still closes it (RegisterEscapeClose, notOwned).
function CludesUI.ToggleGreatVault()
    if not C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards") then
        C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
    end
    local vault = _G.WeeklyRewardsFrame
    if vault then
        vault:SetShown(not vault:IsShown())
    end
end

-- Portal flyout (Chat sidebar and Minimap): SEASON_PORTALS spell buttons plus a
-- hearthstone column, all secure. Build lazily, never in combat; the caller
-- caches the frame and owns anchoring. opts: name (frame name prefix), bg
-- ({r,g,b}), labelFont, labelFlags, clamp (clamp to screen), unitEvents
-- (register the cast events for "player" only). Out of combat a left click
-- anywhere else closes it; the caller names the button that toggles it before
-- each Show (flyout._toggle = button), whose own click then closes it.
function CludesUI.CreatePortalFlyout(options)
    if InCombatLockdown() then
        return nil
    end
    local floor = math.floor
    local Pix = CludesUI.PP

    local BTN_SIZE = 32
    local SPACING = 1
    local PADDING = 2
    local COLS = 4
    local ROWS = math.ceil(#CludesUI.SEASON_PORTALS / COLS)

    local flyH = PADDING * 2 + BTN_SIZE * ROWS + SPACING * (ROWS - 1)
    local HS_COUNT = 3
    local HS_H = floor((flyH - PADDING * 2 - SPACING * (HS_COUNT - 1)) / HS_COUNT)
    local hsX = PADDING + COLS * BTN_SIZE + (COLS - 1) * SPACING + SPACING
    local flyW = hsX + HS_H + PADDING

    local portalMenu = CreateFrame("Frame", options.name .. "PortalFlyout", UIParent)
    portalMenu:SetSize(flyW, flyH)
    portalMenu:SetFrameStrata("DIALOG")
    portalMenu:SetFrameLevel(100)
    if options.clamp then
        portalMenu:SetClampedToScreen(true)
    end
    portalMenu:Hide()

    local backdrop = portalMenu:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(options.bg[1], options.bg[2], options.bg[3], 0.95)

    if Pix and Pix.CreateBorder then
        Pix.CreateBorder(portalMenu, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
    end

    -- Close in combat
    local guard = CreateFrame("Frame")
    guard:RegisterEvent("PLAYER_REGEN_DISABLED")
    guard:SetScript("OnEvent", function()
        portalMenu:Hide()
    end)

    local function NewButton(label, px)
        local button = CreateFrame("Button", label, portalMenu, "SecureActionButtonTemplate")
        button:SetSize(px, px)
        local glyph = button:CreateTexture(nil, "ARTWORK")
        glyph:SetAllPoints()
        glyph:SetTexCoord(6 / 64, 58 / 64, 6 / 64, 58 / 64)
        button.icon = glyph
        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(button, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetAllPoints()
        cooldown:SetHideCountdownNumbers(true)
        cooldown:SetDrawSwipe(true)
        cooldown:SetDrawBling(false)
        cooldown:SetDrawEdge(false)
        button.cooldown = cooldown
        return button, cooldown
    end

    local function AddHighlights(button)
        local hover = button:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.20)
        -- Casting highlight overlay
        local castHL = button:CreateTexture(nil, "OVERLAY", nil, 1)
        castHL:SetAllPoints()
        castHL:SetColorTexture(1, 1, 1, 0.4)
        castHL:Hide()
        button._castHL = castHL
    end

    local portalBtns = {}
    for i, entry in ipairs(CludesUI.SEASON_PORTALS) do
        local spellId = entry.spellID
        local col = (i - 1) % COLS
        local row = floor((i - 1) / COLS)
        local button, cooldown = NewButton(options.name .. "Portal" .. i, BTN_SIZE)
        button:SetPoint(
            "TOPLEFT",
            portalMenu,
            "TOPLEFT",
            PADDING + col * (BTN_SIZE + SPACING),
            -(PADDING + row * (BTN_SIZE + SPACING))
        )
        button.spellID = spellId
        local spellInfo = C_Spell.GetSpellInfo(spellId)
        if spellInfo then
            button.icon:SetTexture(spellInfo.iconID)
        end

        local short = entry.short
        if short then
            local labelFrame = CreateFrame("Frame", nil, button)
            labelFrame:SetAllPoints()
            labelFrame:SetFrameLevel(cooldown:GetFrameLevel() + 2)
            local labelText = labelFrame:CreateFontString(nil, "OVERLAY", nil)
            if CludesUI.PrimeFontShadow then
                CludesUI.PrimeFontShadow(labelText, true)
            end
            labelText:SetFont(options.labelFont, 8, options.labelFlags)
            labelText:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
            labelText:SetTextColor(1, 1, 1, 0.9)
            labelText:SetText((CludesUI.L(short)) or short)
        end

        AddHighlights(button)
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", spellId)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        portalBtns[i] = button
    end

    -- Hearthstone column: 3 icons stacked vertically as a 5th column
    local hearthBtns = {}
    for i = 1, HS_COUNT do
        local button = NewButton(options.name .. "Hearth" .. i, HS_H)
        button:SetPoint("TOPLEFT", portalMenu, "TOPLEFT", hsX, -(PADDING + (i - 1) * (HS_H + SPACING)))
        AddHighlights(button)
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self._hsType == "spell" then
                GameTooltip:SetSpellByID(self._hsID)
            elseif self._hsType == "item" then
                if self._hsID ~= 6948 and PlayerHasToy and PlayerHasToy(self._hsID) then
                    GameTooltip:SetToyByItemID(self._hsID)
                else
                    GameTooltip:SetItemByID(self._hsID)
                end
            elseif self._hsType == "housing" then
                GameTooltip:AddLine(CludesUI.L("Housing Dashboard"))
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        button:HookScript("PostClick", function(self)
            if self._hsType == "housing" then
                if HousingFramesUtil and HousingFramesUtil.ToggleHousingDashboard then
                    HousingFramesUtil.ToggleHousingDashboard()
                end
                portalMenu:Hide()
            else
                self._castHL:Show()
            end
        end)
        hearthBtns[i] = button
    end

    local function RefreshPortalButtons()
        for _, button in ipairs(portalBtns) do
            local spellId = button.spellID
            local known = IsPlayerSpell(spellId)
            if button._lastKnown ~= known then
                button._lastKnown = known
                button.icon:SetDesaturated(not known)
                button.icon:SetAlpha(known and 1 or 0.4)
            end
            if known then
                local cooldown = C_Spell.GetSpellCooldown(spellId)
                if cooldown and cooldown.startTime and cooldown.duration and cooldown.duration > 0 then
                    button.cooldown:SetCooldown(cooldown.startTime, cooldown.duration)
                else
                    button.cooldown:Clear()
                end
            else
                button.cooldown:Clear()
            end
        end
    end

    -- Swipe-only refresh (SPELL_UPDATE_COOLDOWN); never re-resolves toys.
    local function RefreshHearthCooldowns()
        for _, button in ipairs(hearthBtns) do
            local auraType, ident = button._hsType, button._hsID
            if auraType == "spell" and C_Spell and C_Spell.GetSpellCooldown then
                local cooldown = C_Spell.GetSpellCooldown(ident)
                if cooldown and cooldown.startTime and cooldown.duration and cooldown.duration > 0 then
                    button.cooldown:SetCooldown(cooldown.startTime, cooldown.duration)
                else
                    button.cooldown:Clear()
                end
            -- The namespaced call (as IsHearthOnCD uses): the global only exists
            -- behind Blizzard's deprecation fallbacks, and never on Forever.
            elseif auraType == "item" and C_Container and C_Container.GetItemCooldown then
                local success, start, dur = pcall(C_Container.GetItemCooldown, ident)
                if success and start and dur and dur > 0 then
                    button.cooldown:SetCooldown(start, dur)
                else
                    button.cooldown:Clear()
                end
            else
                button.cooldown:Clear()
            end
        end
    end

    -- Full resolve (random toy, icon/macro/attributes). Show only, never on
    -- cooldown events; attribute writes are combat-illegal, hence the gate.
    local function ResolveHearthButtons()
        if InCombatLockdown() then
            return
        end
        local resolvers = {
            CludesUI.ResolveHearthSlot,
            CludesUI.ResolveDalaranSlot,
            CludesUI.ResolveHousingSlot,
        }
        for i, button in ipairs(hearthBtns) do
            local auraType, ident, iconTex = resolvers[i]()
            button._hsType = auraType
            button._hsID = ident
            button.icon:SetTexture(iconTex)
            button.icon:SetTexCoord(
                auraType == "housing" and 0 or 6 / 64,
                auraType == "housing" and 1 or 58 / 64,
                auraType == "housing" and 0 or 6 / 64,
                auraType == "housing" and 1 or 58 / 64
            )
            if auraType == "housing" then
                button:SetAttribute("type", nil)
                button:SetAttribute("macrotext", nil)
            elseif auraType == "spell" then
                button:SetAttribute("type", "macro")
                local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(ident)
                local label = details and details.name or ""
                button:SetAttribute("macrotext", "/cast " .. label)
            else
                button:SetAttribute("type", "macro")
                if ident == 6948 then
                    button:SetAttribute("macrotext", "/use item:" .. ident)
                else
                    local toyName
                    if C_ToyBox and C_ToyBox.GetToyInfo then
                        local _, tn = C_ToyBox.GetToyInfo(ident)
                        toyName = tn
                    end
                    button:SetAttribute("macrotext", toyName and ("/use " .. toyName) or ("/use item:" .. ident))
                end
            end
        end
        RefreshHearthCooldowns()
    end

    -- Events live only while shown: cooldown + cast highlight refresh, and the
    -- mouse press that closes it.
    local CAST_EVENTS = {
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED",
    }
    portalMenu:SetScript("OnShow", function(self)
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        for _, ev in ipairs(CAST_EVENTS) do
            if options.unitEvents then
                self:RegisterUnitEvent(ev, "player")
            else
                self:RegisterEvent(ev)
            end
        end
        RefreshPortalButtons()
        ResolveHearthButtons()
        -- Controller cursor: a window the player opened brings the gamepad pointer up.
        if CludesUI.PadNative() then
            CludesUI.RaiseGamePadCursor()
        end
    end)
    portalMenu:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        for _, button in ipairs(portalBtns) do
            if button._castHL then
                button._castHL:Hide()
            end
        end
        for _, button in ipairs(hearthBtns) do
            if button._castHL then
                button._castHL:Hide()
            end
        end
    end)
    portalMenu:SetScript("OnEvent", function(self, evt, unitToken, castGUID, spellId)
        if evt == "SPELL_UPDATE_COOLDOWN" then
            RefreshPortalButtons()
            RefreshHearthCooldowns()
        elseif evt == "GLOBAL_MOUSE_DOWN" then
            -- A left click anywhere else closes it (unit is the mouse button here).
            -- A press on its toggle is left alone: that button's click closes it.
            local toggle = self._toggle
            if
                unitToken == "LeftButton"
                and not InCombatLockdown()
                and not self:IsMouseOver()
                and not (toggle and toggle:IsVisible() and toggle:IsMouseOver())
            then
                self:Hide()
            end
        elseif unitToken == "player" then
            local casting = (evt == "UNIT_SPELLCAST_START") and spellId or nil
            for _, button in ipairs(portalBtns) do
                if button._castHL then
                    button._castHL:SetShown(casting and casting == button.spellID)
                end
            end
            -- Cast end clears hearthstone highlights
            if not casting then
                for _, button in ipairs(hearthBtns) do
                    if button._castHL then
                        button._castHL:Hide()
                    end
                end
            end
        end
    end)

    -- Escape to close
    CludesUI.RegisterEscapeClose(portalMenu)
    return portalMenu
end

local ADDON_ROSTER = {
    {
        folder = "CludesUIActionBars",
        display = "Action Bars",
        search_name = "CludesUI Action Bars",
    },
    {
        folder = "CludesUINameplates",
        display = "Nameplates",
        search_name = "CludesUI Nameplates",
    },
    {
        folder = "CludesUIUnitFrames",
        display = "Unit Frames",
        search_name = "CludesUI Unit Frames",
    },
    {
        folder = "CludesUIRaidFrames",
        display = "Raid & Party Frames",
        search_name = "CludesUI Raid & Party Frames",
    },
    {
        folder = "CludesUICooldownManager",
        display = "Cooldown Manager",
        search_name = "CludesUI Cooldown Manager",
    },
    {
        folder = "CludesUIResourceBars",
        display = "Resource & Cast Bars",
        search_name = "CludesUI Resource Bars Cast Bars",
    },
    {
        folder = "CludesUITank",
        display = "Tank Kit",
        search_name = "CludesUI Tank Kit Co-Tank Taunt",
    },
    {
        folder = "CludesUIRaidLead",
        display = "Raid Lead",
        search_name = "CludesUI Raid Lead Setup Sort Split",
    },
    {
        folder = "CludesUITitleLine",
        display = "Title Line",
        search_name = "CludesUI Title Line Mythic+ Rating Cutoff",
    },
    {
        folder = "CludesUIAuraBuffReminders",
        display = "Buff Reminders",
        search_name = "CludesUI Buff Reminders",
    },
    {
        folder = "CludesUIQoL",
        display = "Utilities",
        search_name = "CludesUI Utilities",
    },
    {
        folder = "CludesUIForeverEssentials",
        display = "Forever Tools",
        search_name = "CludesUI Forever Tools",
    },
    {
        folder = "CludesUIBlizzardSkin",
        display = "Window Skins",
        search_name = "CludesUI Window Skins",
        syncFolder = "CludesUIDragonRiding",
        syncDisplay = "Dragon Riding",
    },
    {
        folder = "CludesUIFriends",
        display = "Friends List",
        search_name = "CludesUI Friends List",
    },
    {
        folder = "CludesUIMythicTimer",
        display = "Mythic+ Tools",
        search_name = "CludesUI Mythic+ Tools Timer",
    },
    {
        folder = "CludesUIQuestTracker",
        display = "Quest Tracker",
        search_name = "CludesUI Quest Tracker",
    },
    {
        folder = "CludesUIMinimap",
        display = "Minimap",
        search_name = "CludesUI Minimap",
    },
    {
        folder = "CludesUIChat",
        display = "Chat",
        search_name = "CludesUI Chat",
    },
    {
        folder = "CludesUIDamageMeters",
        display = "Damage Meters",
        search_name = "CludesUI Damage Meters",
    },
    {
        folder = "CludesUIBags",
        display = "Bags",
        search_name = "CludesUI Bags",
    },
    {
        folder = "CludesUIDataBars",
        display = "Info Bar",
        search_name = "CludesUI Info Bar",
    },
    {
        folder = "CludesUIQuickdraw",
        display = "Action Wheel",
        search_name = "CludesUI Action Wheel",
    },
    {
        folder = "CludesUILoadoutManager",
        display = "Loadout Manager",
        search_name = "CludesUI Loadout Manager",
    },
    {
        folder = "CludesUIGroupFinder",
        display = "Group Finder",
        search_name = "CludesUI Group Finder Premade Groups",
    },
    {
        folder = "CludesUISimpleLootCouncil",
        display = "Simple Loot Council",
        search_name = "CludesUI Simple Loot Council Loot Council",
    },
}

-------------------------------------------------------------------------------
--  Addon Groups -- ordered sidebar categories, by what the player is doing
--  (Combat, Raid & Dungeon, Interface, Tools). Group = header the player can
--  collapse; members = child rows, order authoritative, coming-soon last). Keys
--  stay stable when a label changes: other addons look groups up by key. On
--  CludesUI, not a file local, to stay under the 200-local / CreateMainFrame
--  60-upvalue caps.
-------------------------------------------------------------------------------
CludesUI.ADDON_GROUPS = {
    {
        key = "combat",
        label = "Combat",
        members = {
            "CludesUIActionBars",
            "CludesUIUnitFrames",
            "CludesUINameplates",
            "CludesUIRaidFrames",
            "CludesUICooldownManager",
            "CludesUIResourceBars",
            "CludesUIAuraBuffReminders",
            "CludesUIDamageMeters",
        },
    },
    {
        key = "group",
        label = "Raid & Dungeon",
        members = {
            "CludesUIMythicTimer",
            "CludesUIRaidLead",
            "CludesUITank",
            "CludesUITitleLine",
            "CludesUIGroupFinder",
            "CludesUILoadoutManager",
            "CludesUISimpleLootCouncil",
        },
    },
    {
        key = "interface",
        label = "Interface",
        members = {
            "CludesUIBlizzardSkin",
            "CludesUIMinimap",
            "CludesUIChat",
            "CludesUIBags",
            "CludesUIQuestTracker",
            "CludesUIFriends",
            "CludesUIDataBars",
        },
    },
    {
        key = "tools",
        label = "Tools",
        members = {
            "CludesUIQoL",
            "CludesUIForeverEssentials",
            "CludesUIQuickdraw",
        },
    },
}

-- STANDALONE: the bundled module is the only roster entry containing "Standalone"
-- (rename yields "CUICoreStandalone<X>" refs; installed folder is "CUIStandalone<X>").
-- Keep the full sidebar, prepend a "Standalone" category with this module, and remove
-- it from its normal category so it is not listed twice. Inert in the suite.
if IS_STANDALONE then
    local selfFolder
    for _, details in ipairs(ADDON_ROSTER) do
        -- Exclude "Core": the renamed core token is "CUICoreStandalone<X>".
        if details.folder:find("Standalone") and not details.folder:find("Core") then
            selfFolder = details.folder
            break
        end
    end
    if selfFolder then
        for _, set in ipairs(CludesUI.ADDON_GROUPS) do
            for mi = #set.members, 1, -1 do
                if set.members[mi] == selfFolder then
                    table.remove(set.members, mi)
                end
            end
        end
        table.insert(CludesUI.ADDON_GROUPS, 1, {
            key = "standalone",
            label = "Standalone",
            members = { selfFolder },
        })
    end
end

-- WoW Forever: addons switched off for the whole client (TOC
-- "## AllowLoadGameType: standard") leave every list built from the roster
-- and the groups -- sidebar, install picker, font and texture cards -- rather
-- than sit in them disabled. Extend the set whenever a TOC gets that line.
CludesUI.FOREVER_HIDDEN_ADDONS = {
    CludesUIMythicTimer = true,
    CludesUIFriends = true,
    CludesUITitleLine = true,
    CludesUITank = true,
    CludesUIRaidLead = true,
    CludesUILoadoutManager = true,
    CludesUIGroupFinder = true,
    -- Not an addon: the Dragon Riding profile pseudo-folder (its file returns at
    -- load on Forever), listed so the profile import/export checklists drop it.
    CludesUIDragonRiding = true,
}
-- The mirror: addons that load on WoW Forever alone (TOC
-- "## AllowLoadGameType: camelot") leave the same lists on every other client.
CludesUI.FOREVER_ONLY_ADDONS = {
    CludesUIForeverEssentials = true,
}
-- Modules held back from the current release on every client: they leave the
-- same lists and the packager does not ship their folder (.pkgmeta ignore);
-- the tester zip ships every folder as the tree stands, held back or not
-- (owner 2026-10-20). The Loadout Manager never loads (its TOC is LoadOnDemand
-- and nothing loads it); a Group Finder listed here would stop at the top of
-- each runtime file. To ship one, drop it here, drop its TOC's LoadOnDemand
-- hold line and restore its .pkgmeta move-folders line. Simple Loot Council
-- is held back too (listed here, with the hold line in both its TOCs, and
-- .pkgmeta ignoring it); to switch it on locally for the guild's raid tests,
-- drop it here and drop the hold line from both TOCs.
CludesUI.HELD_BACK_ADDONS = {
    CludesUILoadoutManager = true,
    CludesUISimpleLootCouncil = true,
}
-- The set the running client leaves out.
do
    local hiddenSet = {}
    for folder in
        pairs((CUI_CLIENT_FOREVER == true) and CludesUI.FOREVER_HIDDEN_ADDONS or CludesUI.FOREVER_ONLY_ADDONS)
    do
        hiddenSet[folder] = true
    end
    for folder in pairs(CludesUI.HELD_BACK_ADDONS) do
        hiddenSet[folder] = true
    end
    CludesUI._CLIENT_HIDDEN_ADDONS = hiddenSet
end
-- The profile import/export checklists read the profile data map, which stays
-- complete (it drives the data itself); they list through this view instead.
function CludesUI.VisibleProfileAddons(map)
    if type(map) ~= "table" then
        return map
    end
    local hiddenSet = CludesUI._CLIENT_HIDDEN_ADDONS
    local result = {}
    for _, record in ipairs(map) do
        if not hiddenSet[record.folder] then
            result[#result + 1] = record
        end
    end
    return result
end
do
    local hiddenSet = CludesUI._CLIENT_HIDDEN_ADDONS
    for i = #ADDON_ROSTER, 1, -1 do
        if hiddenSet[ADDON_ROSTER[i].folder] then
            table.remove(ADDON_ROSTER, i)
        end
    end
    for _, set in ipairs(CludesUI.ADDON_GROUPS) do
        for mi = #set.members, 1, -1 do
            if hiddenSet[set.members[mi]] then
                table.remove(set.members, mi)
            end
        end
    end
end

-- Icon file ids the Forever client does not ship (its art set predates them),
-- each with the vanilla-era icon that stands in for it there. Resolved where
-- an icon is painted (a stored custom icon gets the same treatment), never in
-- the default tables; every other client gets the id back as it is. Extend
-- the map whenever a tester reports a green square.
CludesUI._FOREVER_ICON = {
    [7548911] = 133975, -- Bags "Consumables" default: an apple
    [7549094] = 136249, -- Bags "Gear Enhancements": classic enchantment icon
    [7548925] = 134332, -- Bags "Professions": classic trade-skill icon
}
function CludesUI.ClientIcon(glyph)
    if CUI_CLIENT_FOREVER ~= true then
        return glyph
    end
    return CludesUI._FOREVER_ICON[glyph] or glyph
end

-- The trash can on a delete button: Blizzard's atlas where the client has it,
-- else the bundled glyph (the Forever client has no common-icon-delete).
function CludesUI.SetDeleteIcon(texture)
    local success = CludesUI._deleteAtlasOK
    if success == nil then
        success = C_Texture.GetAtlasInfo("common-icon-delete") ~= nil
        CludesUI._deleteAtlasOK = success
    end
    if success then
        texture:SetAtlas("common-icon-delete")
    else
        texture:SetTexture(CludesUI.ICONS_PATH .. "common-icon-delete.png")
    end
end

-- Flat folder -> roster-info lookup for the grouped sidebar builder. On CludesUI
-- (not a local): CreateMainFrame is up against the Lua 5.1 60-upvalue limit.
CludesUI._addonInfoByFolder = {}
for _, details in ipairs(ADDON_ROSTER) do
    CludesUI._addonInfoByFolder[details.folder] = details
end

-------------------------------------------------------------------------------
--  Private navigation model
--  The sidebar is built ONLY from these copies, taken once the roster and groups
--  above are final. ADDON_ROSTER / ADDON_GROUPS / _addonInfoByFolder stay public
--  as read-only data for other files, but writes to them no longer reach the
--  sidebar: third-party code cannot add rows to the suite's sections, reorder
--  them, or relabel them. Plugin sections (see the Plugin API section) are held
--  in separate lists and can only sit above or below the whole suite block.
-------------------------------------------------------------------------------
do
    local navInfo = {}
    for _, details in ipairs(ADDON_ROSTER) do
        local copy = {}
        for k, v in pairs(details) do
            copy[k] = v
        end
        navInfo[details.folder] = copy
    end
    -- A group the running client left with no addons (Raid & Dungeon on WoW
    -- Forever, where every member is switched off) gets no sidebar header:
    -- an empty section only looks broken.
    local coreGroups = {}
    for _, set in ipairs(CludesUI.ADDON_GROUPS) do
        local memberList = {}
        for i, folder in ipairs(set.members) do
            memberList[i] = folder
        end
        if #memberList > 0 then
            coreGroups[#coreGroups + 1] = { key = set.key, label = set.label, members = memberList }
        end
    end
    CUI_NS.navInfo = navInfo
    CUI_NS.coreGroups = coreGroups
    CUI_NS.pluginGroupsTop = {}
    CUI_NS.pluginGroupsBottom = {}
    CUI_NS.navGroups = {}
    -- Sidebar group header frames, keyed by group key.
    CUI_NS.sidebarGroupButtons = {}

    -- Final sidebar order: top plugin sections, the suite's own groups as one
    -- contiguous block, then bottom plugin sections.
    function CUI_NS.RebuildNavGroups()
        local result = CUI_NS.navGroups
        for i = #result, 1, -1 do
            result[i] = nil
        end
        for _, group in ipairs(CUI_NS.pluginGroupsTop) do
            result[#result + 1] = group
        end
        for _, group in ipairs(coreGroups) do
            result[#result + 1] = group
        end
        for _, group in ipairs(CUI_NS.pluginGroupsBottom) do
            result[#result + 1] = group
        end
    end
    CUI_NS.RebuildNavGroups()

    -- Module keys starting with this prefix belong to the plugin registry.
    local PLUGIN_PREFIX = "plugin:"
    CUI_NS.PLUGIN_PREFIX = PLUGIN_PREFIX
    function CUI_NS.IsPluginKey(entryKey)
        return type(entryKey) == "string" and entryKey:sub(1, #PLUGIN_PREFIX) == PLUGIN_PREFIX
    end

    -- Suite registration window (see RegisterModule). Open while the options
    -- addon loads (whoever loads it: its files register as they run), while the
    -- core drains its deferred inits, and from a pre-login load of the options
    -- addon until just after PLAYER_LOGIN (its files register from their
    -- PLAYER_LOGIN handlers in that case).
    local registryDepth, loginWindow = 0, false
    local IsAddOnLoaded = C_AddOns.IsAddOnLoaded
    function CUI_NS.CoreRegistrationOpen()
        if registryDepth > 0 or loginWindow then
            return true
        end
        local loadedOrLoading, isLoaded = IsAddOnLoaded("CludesUIOptions")
        return loadedOrLoading and not isLoaded
    end
    -- The suite's pages always register through the real RegisterModule. An
    -- addon that replaced or hooked the public one (to slip pages into the
    -- suite's modules) is taken out of the path first, so it can never stop
    -- them registering, and is named in the panel's update notice.
    local rawget, rawset = rawget, rawset
    local function ReclaimRegisterModule()
        local real = CUI_NS.CoreRegisterModule
        if not real or rawget(CludesUI, "RegisterModule") == real then
            return
        end
        local by = CUI_NS.WriterOf(CludesUI, "RegisterModule")
        rawset(CludesUI, "RegisterModule", real)
        if by then
            CUI_NS.RecordLegacyOffender(by)
        end
    end
    -- Errors are reported through the error handler (keeping their traceback)
    -- rather than rethrown, so a failing callee can never leave the window open.
    local function ReportError(err)
        return geterrorhandler()(err)
    end
    CUI_NS.ReportError = ReportError -- shared with the plugin registry (CludesUI_Panel.lua)
    function CUI_NS.RunCoreRegistration(func, ...)
        ReclaimRegisterModule()
        registryDepth = registryDepth + 1
        local success, a, b = xpcall(func, ReportError, ...)
        registryDepth = registryDepth - 1
        if success then
            return a, b
        end
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self, evt, label)
        if evt == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            -- Before the options files' own PLAYER_LOGIN registrations (a
            -- pre-login options load, standalone builds).
            ReclaimRegisterModule()
            if loginWindow then
                C_Timer.After(0, function()
                    loginWindow = false
                end)
            end
        elseif label == "CludesUIOptions" then
            self:UnregisterEvent("ADDON_LOADED")
            -- Loaded before login: its files register from their PLAYER_LOGIN handlers.
            if not IsLoggedIn() then
                loginWindow = true
            end
        end
    end)
end

local IsAddonLoaded = C_AddOns.IsAddOnLoaded

-------------------------------------------------------------------------------
--  Forward declarations
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI or {}
_G.CludesUI = CludesUI
CludesUI.GLOBAL_KEY = "_CUIGlobal"
CludesUI.ADDON_ROSTER = ADDON_ROSTER
CludesUI.LOCALE_FONT_FALLBACK = LOCALE_FONT_FALLBACK
-- Script the fallback stands in for: "cyrillic" | "cjk" | nil. Table field, not a
-- file-scope local: this file sits on the Lua 5.1 200-local cap.
CludesUI.LOCALE_SCRIPT = CludesUI._localeScript
CludesUI.EXPRESSWAY = LOCALE_FONT_FALLBACK or EXPRESSWAY

-- Re-sync once the override-aware effective locale is known (the values above
-- are captured before CludesUIDB's displayLocale override is readable).
function CludesUI.RefreshLocaleFontFallback()
    LOCALE_FONT_FALLBACK = CludesUI._localeFont
    CludesUI.LOCALE_FONT_FALLBACK = LOCALE_FONT_FALLBACK
    CludesUI.LOCALE_SCRIPT = CludesUI._localeScript
    CludesUI.EXPRESSWAY = LOCALE_FONT_FALLBACK or EXPRESSWAY
    CludesUI.InvalidateFontCache()
end

-- Taint-safe print: AddMessage, never global print() (its C-side handler taints the chat
-- frame). Drops silently in protected instances (raid combat, active M+) to avoid tainting FCF_OpenTemporaryWindow's whisper chain.
function CludesUI.Print(...)
    local f = DEFAULT_CHAT_FRAME
    if not f then
        return
    end
    local _, instanceType = IsInInstance()
    if instanceType == "raid" and InCombatLockdown() then
        return
    end
    if
        instanceType == "party"
        and C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    then
        return
    end
    if (instanceType == "pvp" or instanceType == "arena") and InCombatLockdown() then
        return
    end
    f:AddMessage(strjoin(" ", tostringall(...)))
end

-- Budgeted step runner -- the 12.1 script-watchdog defense for any pass whose
-- cost scales with data size (frames x settings x profile keys). Runs `steps`
-- (an array of functions) strictly in order, spending at most `msBudget`
-- (default 8) milliseconds of CPU per execution; when the budget is spent the
-- remainder re-queues via C_Timer.After(0), so every continuation gets a
-- fresh watchdog budget. By construction no single execution here can
-- approach the watchdog limit, on any machine, at any step count.
--
-- NOTHING runs in the caller's execution: the first slice is deferred too,
-- so a caller that already spent real budget (a profile apply, an options
-- click) never gets this work stacked on top. Timers do not fire during
-- loading screens, so from a login-window caller the first slice lands on
-- the first frame after the screen drops.
--
-- Each step runs under pcall with errors routed to the standard error
-- handler and the chain CONTINUING: an async chain that died mid-way would
-- silently strand `onDone` (completion/cleanup) and every later step, which
-- is worse than one step's failure. Steps must tolerate a failed
-- predecessor; a sequence that cannot should stay synchronous instead.
-- `onDone` (optional) runs after the last step, in that final execution.
-- No file-scope locals here on purpose: this file sits on the 200-local cap.
function CludesUI.RunBudgeted(steps, msBudget, onDone)
    local slotIndex, n = 1, #steps
    local budget = msBudget or 8
    local function drain()
        local deadline = debugprofilestop() + budget
        while slotIndex <= n do
            local success, err = pcall(steps[slotIndex])
            slotIndex = slotIndex + 1
            if not success and err then
                geterrorhandler()(err)
            end
            if slotIndex <= n and debugprofilestop() > deadline then
                C_Timer.After(0, drain)
                return
            end
        end
        if onDone then
            onDone()
        end
    end
    C_Timer.After(0, drain)
end

local modules = {}
-- Private alias so other core files (the panel, global search) can reach the
-- registered modules. Never published on CludesUI: a reference to a
-- module's config table would let any addon rewrite that module's pages.
CUI_NS.modules = modules

-- Widget refresh registry: a Refresh callback per widget so RefreshPage updates values in-place without rebuilding frames.
local _widgetRefreshList = {}
local function RegisterWidgetRefresh(func)
    _widgetRefreshList[#_widgetRefreshList + 1] = func
end
CludesUI.RegisterWidgetRefresh = RegisterWidgetRefresh

-- Collapse callbacks -- fn(true) when the panel folds to its mini window, fn(false)
-- when it unfolds back on screen. The options session stays open across both, so
-- neither the OnShow nor the OnHide callbacks run; a close from the mini window
-- runs the OnHide callbacks instead of fn(false). For panel-owned surfaces that
-- live outside the panel body (UIParent-parented popouts) or panel-only work.
CludesUI._onCollapseCallbacks = {}
function CludesUI:RegisterOnCollapse(func)
    local entries = self._onCollapseCallbacks
    entries[#entries + 1] = func
end

-------------------------------------------------------------------------------
--  Utilities
-------------------------------------------------------------------------------
local function MakeFont(hostFrame, px, flags, red, green, blue, a)
    local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
    fontStr:SetFont(LOCALE_FONT_FALLBACK or EXPRESSWAY, px, flags or "")
    if red then
        fontStr:SetTextColor(red, green, blue, a or 1)
    end
    return fontStr
end

local function SolidTex(hostFrame, layer, red, green, blue, a)
    local texture = hostFrame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetColorTexture(red, green, blue, a or 1)
    return texture
end

-- PP and PanelPP come from CludesUI_PixelPerfect.lua, which loads before this file
local Pix = CludesUI.PP

-- Disable WoW pixel snapping on a texture/frame so 1px elements never round to 0.
local function DisablePixelSnap(object)
    if object.SetSnapToPixelGrid then
        object:SetSnapToPixelGrid(false)
        object:SetTexelSnappingBias(0)
    end
end

-- Dropdown arrow: square canvas, arrow centered, two-point anchored so it inherits the parent's pixel-aligned bounds.
local function MakeDropdownArrow(hostFrame, xPad, ppOverride)
    local pp = ppOverride or Pix
    local arrow = hostFrame:CreateTexture(nil, "ARTWORK")
    pp.DisablePixelSnap(arrow)
    arrow:SetTexture(ICONS_PATH .. "cui-arrow.png")
    local pad = (xPad or 12) + 5
    local sz = 26
    pp.Point(arrow, "TOPRIGHT", hostFrame, "RIGHT", -(pad - sz / 2), sz / 2)
    pp.Point(arrow, "BOTTOMLEFT", hostFrame, "RIGHT", -(pad + sz / 2), -sz / 2)
    return arrow
end

-- Page reuse (CludesUIOptions/CludesUI_FramePool.lua): ONE switch for the
-- whole suite. On: a page built again gets its earlier frames back reset to
-- fresh instead of building new ones. Off: every page takes the old
-- build-and-drop path (the one-line rollback).
CludesUI._reusePages = true
-- The frame pool's table (CludesUI_PixelPerfect.lua makes it): for the
-- resident helpers that build options frames (MakeBorder, AttachSmoothScrollbar)
-- a plain CreateFrame until the options addon loads the pool, which fills this
-- same table in place. Read through this local, never the public slot.
local POOL = CludesUI._Pool
if type(POOL) ~= "table" then
    POOL = {
        CreateFrame = function(...)
            return CreateFrame(...)
        end,
    }
    CludesUI._Pool = POOL
end

local function MakeBorder(hostFrame, red, green, blue, a, ppOverride)
    -- PP.CreateBorder wrapper returning the MakeBorder API. ppOverride: PanelPP for panel context, else real PP (game context).
    local pp = ppOverride or Pix
    local alpha = a or 1
    red = red or 0
    green = green or 0
    blue = blue or 0
    -- On a page-pool host the border frame is pooled with it (PP.CreateBorder
    -- dresses its kept strips again); anywhere else a plain new frame.
    local bf = POOL.CreateFrame("Frame", nil, hostFrame)
    bf:SetAllPoints(hostFrame)
    bf:SetFrameLevel(hostFrame:GetFrameLevel() + 1)
    bf:EnableMouse(false)

    -- PP.CreateBorder's four strips. A border inside the options panel re-snaps with
    -- the rest of it in SetPanelScale's settle pass, never through a hook of its own.
    local brd = Pix.CreateBorder(bf, red, green, blue, alpha, 1, "BORDER", 7)

    return {
        _frame = bf,
        edges = brd,
        SetColor = function(self, cr, cg, cb, ca)
            Pix.SetBorderColor(bf, cr, cg, cb, ca or 1)
        end,
    }
end

-- Alternating row backgrounds, counted per parent so each section resets independently. In
-- a split column (parent._splitParent) the bg lives on splitParent so it spans full width, anchored to the widget frame's top/bottom edges.
local rowCounters = {}
local function RowBg(widget, hostFrame)
    if not rowCounters[hostFrame] then
        rowCounters[hostFrame] = 0
    end
    rowCounters[hostFrame] = rowCounters[hostFrame] + 1
    local alpha = (rowCounters[hostFrame] % 2 == 0) and STYLE.ROW_BG_EVEN or STYLE.ROW_BG_ODD
    local splitParent = hostFrame._splitParent
    local bgParent = splitParent or widget
    local backdrop = bgParent:CreateTexture(nil, "BACKGROUND")
    backdrop:SetColorTexture(0, 0, 0, alpha)
    -- Always panel context: PanelPP (CludesUI_PixelPerfect.lua, loaded before this file)
    local ppp = CludesUI.PanelPP or Pix
    ppp.DisablePixelSnap(backdrop)
    backdrop:SetIgnoreParentAlpha(true)
    if splitParent then
        backdrop:SetPoint("LEFT", splitParent, "LEFT", 0, 0)
        backdrop:SetPoint("RIGHT", splitParent, "RIGHT", 0, 0)
        backdrop:SetPoint("TOP", widget, "TOP", 0, 0)
        backdrop:SetPoint("BOTTOM", widget, "BOTTOM", 0, 0)
    else
        backdrop:SetAllPoints()
    end
    -- Center divider (1px vertical at row midpoint); only when parent._showRowDivider is set
    if hostFrame._showRowDivider and not widget._skipRowDivider then
        local div = widget:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1, 1, 1, 0.06)
        if div.SetSnapToPixelGrid then
            div:SetSnapToPixelGrid(false)
            div:SetTexelSnappingBias(0)
        end
        div:SetWidth(1)
        ppp.Point(div, "TOP", widget, "TOP", 0, 0)
        ppp.Point(div, "BOTTOM", widget, "BOTTOM", 0, 0)
    end
end
-- Reset row counter (call from ClearContent so each rebuild starts fresh)
local function ResetRowCounters()
    wipe(rowCounters)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Shared /played: every module asks here, so modules share one request and its
-- reply, and the game prints its two chat lines as rarely as possible. Returns
-- total and this-level seconds when a reply for this level is known. Otherwise
-- returns nothing and requests; the caller's own TIME_PLAYED_MSG gets the reply.
do
    local PENDING_SECONDS = 10 -- after this a reply counts as lost; a call asks again
    local widget, pendingAt, sum, level, at, charLevel

    function CludesUI.RequestTimePlayed()
        local nowTime = GetTime()
        if sum and charLevel == UnitLevel("player") then
            return sum + (nowTime - at), level + (nowTime - at)
        end
        if not RequestTimePlayed or (pendingAt and nowTime - pendingAt < PENDING_SECONDS) then
            return
        end
        if not widget then
            widget = CreateFrame("Frame")
            widget:SetScript("OnEvent", function(self, _, totalTime, levelTime)
                if type(totalTime) ~= "number" or type(levelTime) ~= "number" then
                    return
                end
                sum, level, at, charLevel = totalTime, levelTime, GetTime(), UnitLevel("player")
                pendingAt = nil
                self:UnregisterEvent("TIME_PLAYED_MSG")
            end)
        end
        pendingAt = nowTime
        widget:RegisterEvent("TIME_PLAYED_MSG")
        RequestTimePlayed()
    end
end

-- A duration in whole minutes: 3d 4h, 1h 24m, 22m (a negative one reads 0m).
function CludesUI.FormatDuration(secondary)
    local m = math.floor((secondary > 0 and secondary or 0) / 60)
    local hgt = math.floor(m / 60)
    if hgt >= 24 then
        local d = math.floor(hgt / 24)
        return string.format(CludesUI.L("%dd %dh"), d, hgt - d * 24)
    elseif hgt > 0 then
        return string.format(CludesUI.L("%dh %dm"), hgt, m - hgt * 60)
    end
    return string.format(CludesUI.L("%dm"), m)
end

-- Realm a character roster groups by. Forever is realmless: the ruleset name.
function CludesUI.RealmGroupName()
    if not CludesUI.IS_FOREVER then
        return GetRealmName()
    end
    local R = Enum.GameRule
    local function On(rule)
        return rule and C_GameRules.IsGameRuleActive(rule)
    end
    if On(R.HardcoreRuleset) then
        return GUILD_PLAYSTYLE_HARDCORE
    end
    local pvp, rp = On(R.PvPRuleset), On(R.RPRuleset)
    if pvp and rp then
        return GDAPI_REALMTYPE_PVP_RP
    end
    if pvp then
        return GDAPI_REALMTYPE_PVP
    end
    if rp then
        return GDAPI_REALMTYPE_RP
    end
    return GDAPI_REALMTYPE_NORMAL
end

-- Moves store[old] to store[key] unless key already holds an entry; old goes
-- either way.
local function AdoptCharEntry(storage, old, entryKey)
    if storage[old] ~= nil then
        if storage[entryKey] == nil then
            storage[entryKey] = storage[old]
        end
        storage[old] = nil
    end
end

-- Per-character key. Retail: "Name<sep>Realm". WoW Forever: the character's
-- GUID (nil while it cannot be read), since a first name is not unique there
-- and a GUID survives a rename. Each store passed in takes over what older
-- builds filed under "Name<sep>Ruleset" or "Name<sep>Realm"; nothing files
-- those keys any more, so an entry two characters shared goes to the first
-- of them to log in.
function CludesUI.CharKey(sep, ...)
    local label, set = UnitName("player"), CludesUI.RealmGroupName()
    if not label or not set then
        return nil
    end
    if not CludesUI.IS_FOREVER then
        return label .. sep .. set
    end
    local unitGuid = UnitGUID("player")
    if not unitGuid or issecretvalue(unitGuid) then
        return nil
    end
    local byGroup, byRealm
    for i = 1, select("#", ...) do
        local storage = select(i, ...)
        if type(storage) == "table" then
            if not byGroup then
                byGroup, byRealm = label .. sep .. set, label .. sep .. (GetRealmName() or "")
            end
            AdoptCharEntry(storage, byGroup, unitGuid)
            AdoptCharEntry(storage, byRealm, unitGuid)
        end
    end
    return unitGuid
end

-- "Name-Realm" whisper/invite target. With realmName it builds (realm wins,
-- spaces stripped); with a finished name alone it only collapses a stacked realm.
function CludesUI.BuildFullName(charName, realm)
    -- type()/issecretvalue() before any comparison: `== ""` on a secret throws.
    if type(charName) ~= "string" then
        return nil
    end
    if issecretvalue and issecretvalue(charName) then
        return charName
    end
    if charName == "" then
        return nil
    end

    -- Character names hold no hyphen, so the first one splits name from realm.
    local base, tail = charName:match("^([^%-]+)%-(.+)$")
    base = base or charName

    if type(realm) == "string" and not (issecretvalue and issecretvalue(realm)) then
        local realm = (realm:gsub("%s+", ""))
        if realm ~= "" then
            return base .. "-" .. realm
        end
    end
    if not tail then
        return base
    end

    -- Collapse proven repetition only -- a realm may hold a hyphen ("Azjol-Nerub").
    local segs = {}
    for seg in tail:gmatch("[^%-]+") do
        if segs[#segs] ~= seg then
            segs[#segs + 1] = seg
        end
    end
    tail = table.concat(segs, "-")
    -- A doubled multi-word realm has no adjacent repeats; a half-split catches it.
    local half = (#tail - 1) / 2
    if
        half > 0
        and half == math.floor(half)
        and tail:sub(half + 1, half + 1) == "-"
        and tail:sub(1, half) == tail:sub(half + 2)
    then
        tail = tail:sub(1, half)
    end
    return base .. "-" .. tail
end

-- A friend or guild note for display. Older Friends builds wrote a "||<tag>:Group||" tag
-- into friend notes that was never removed: the text before it is kept, trailing
-- space trimmed. nil for a non-string, secret or empty note.
function CludesUI.StripFriendNoteTag(noteText)
    if type(noteText) ~= "string" or issecretvalue(noteText) or noteText == "" then
        return nil
    end
    local s = noteText:find("||E" .. "UI:", 1, true)
    if s and noteText:find("||", s + 6, true) then
        noteText = noteText:sub(1, s - 1):match("^(.-)%s*$")
        if noteText == "" then
            return nil
        end
    end
    return noteText
end

-------------------------------------------------------------------------------
--  Exports  (shared locals CludesUI table for split files)
-------------------------------------------------------------------------------
-- Visual constants (tables)
CludesUI.CLUDES_GREEN = CLUDES_GREEN
CludesUI.DARK_BG = DARK_BG
CludesUI.BORDER_COLOR = BORDER_COLOR
CludesUI.TEXT_WHITE = TEXT_WHITE
CludesUI.TEXT_DIM = TEXT_DIM
CludesUI.TEXT_SECTION = TEXT_SECTION
CludesUI.CS = CS

-- Shared icon paths
-- The settings cog (the inline cog's default, owner 2026-11-05); Unlock Mode's
-- mover cog keeps the cogwheel art.
CludesUI.COGS_ICON = MEDIA_PATH .. "icons\\settings.png"
CludesUI.UNDO_ICON = MEDIA_PATH .. "icons\\undo.png"
CludesUI.RESIZE_ICON = MEDIA_PATH .. "icons\\cui-resize-5.png"
CludesUI.DIRECTIONS_ICON = MEDIA_PATH .. "icons\\cui-directions.png"
CludesUI.SYNC_ICON = MEDIA_PATH .. "icons\\sync.png"
CludesUI.EYE_VISIBLE_ICON = MEDIA_PATH .. "icons\\cui-visible.png"
CludesUI.EYE_INVISIBLE_ICON = MEDIA_PATH .. "icons\\cui-invisible.png"
CludesUI.UNLOCK_ICON = MEDIA_PATH .. "icons\\unlockmode.png"

-- Shared chat/tooltip colour escapes. Leave codes inside L()/Lf() literals alone:
-- that text is the translation key.
CludesUI.COLOR_CODES = {
    WHITE = "|cffffffff",
    DIM = "|cff888888",
    BAD = "|cffff5959",
    ERROR = "|cffff6060",
    BRAND = "|cff4cc9f0", -- ADDON_COLORS["CludesUI"]
}

-- 0-1 r, g, b -> "|cffRRGGBB" (each channel rounded).
function CludesUI.HexColor(red, green, blue)
    return string.format(
        "|cff%02x%02x%02x",
        math.floor(red * 255 + 0.5),
        math.floor(green * 255 + 0.5),
        math.floor(blue * 255 + 0.5)
    )
end

-- Red "[CludesUI]" chat line through Print (same combat/instance muting).
function CludesUI.PrintError(message)
    CludesUI.Print(CludesUI.COLOR_CODES.ERROR .. "[CludesUI]|r " .. message)
end

-- Shared options-dropdown data, read-only. The menu renders ONLY the keys its order array
-- lists, so a subset-order site may share the full labels dict. Never mutate these or feed
-- them to the SharedMedia appenders (which mutate args in place); sites with a different sequence (none-first, bottomright-first, "same"-prefixed) keep local orders.
CludesUI.POSITION_GRID_VALUES = {
    ["topleft"] = "Top Left",
    ["top"] = "Top",
    ["topright"] = "Top Right",
    ["left"] = "Left",
    ["center"] = "Center",
    ["right"] = "Right",
    ["bottomleft"] = "Bottom Left",
    ["bottom"] = "Bottom",
    ["bottomright"] = "Bottom Right",
}
CludesUI.POSITION_GRID_VALUES_NONE = {
    ["topleft"] = "Top Left",
    ["top"] = "Top",
    ["topright"] = "Top Right",
    ["left"] = "Left",
    ["center"] = "Center",
    ["right"] = "Right",
    ["bottomleft"] = "Bottom Left",
    ["bottom"] = "Bottom",
    ["bottomright"] = "Bottom Right",
    ["none"] = "None",
}
CludesUI.POSITION_GRID_ORDER =
    { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
CludesUI.FRAME_STRATA_LABELS = {
    BACKGROUND = "Background",
    LOW = "Low",
    MEDIUM = "Medium",
    HIGH = "High",
    DIALOG = "Dialog",
    FULLSCREEN = "Fullscreen",
    FULLSCREEN_DIALOG = "Fullscreen Dialog",
    TOOLTIP = "Tooltip",
}
CludesUI.FRAME_STRATA_ORDER_BASE = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }
CludesUI.FRAME_STRATA_ORDER_FULL =
    { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
CludesUI.GROW_DIR_VALUES_FULL =
    { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down", CENTER = "Center" }
CludesUI.GROW_DIR_ORDER_FULL = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER" }
CludesUI.GROW_DIR_VALUES_BASE = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
CludesUI.GROW_DIR_ORDER_BASE = { "RIGHT", "LEFT", "UP", "DOWN" }

-- Alert sound catalogue: shared LITERAL data only. Every consumer takes its OWN tables from
-- BuildAlertSoundTables() -- SM appenders mutate in place and cache by table identity, so a shared table collapses two dropdowns into one and loses SM entries.
CludesUI.ALERT_SOUND_FILES = {
    airhorn = "AirHorn.ogg",
    banana = "BananaPeelSlip.ogg",
    bikehorn = "BikeHorn.ogg",
    bite = "Bite.ogg",
    boxing = "BoxingArenaSound.ogg",
    catmeow = "CatMeow.ogg",
    catmeow2 = "CatMeow2.ogg",
    gunshot = "FrontalsGunshot.wav",
    glass = "Glass.mp3",
    kaching = "Kaching.ogg",
    phone = "Phone.ogg",
    robotblip = "RobotBlip.ogg",
    sonar = "Sonar.ogg",
    siren = "WarningSiren.ogg",
    water = "WaterDrop.ogg",
    wilhelm = "Wilhelm.ogg",
}
CludesUI.ALERT_SOUND_NAMES = {
    none = "None",
    airhorn = "Air Horn",
    banana = "Banana Peel Slip",
    bikehorn = "Bike Horn",
    bite = "Bite",
    boxing = "Boxing Arena",
    catmeow = "Cat Meow",
    catmeow2 = "Cat Meow 2",
    gunshot = "Frontals Gunshot",
    glass = "Glass",
    kaching = "Kaching",
    phone = "Phone",
    robotblip = "Robot Blip",
    sonar = "Sonar",
    siren = "Warning Siren",
    water = "Water Drop",
    wilhelm = "Wilhelm",
}
CludesUI.ALERT_SOUND_ORDER = {
    "none",
    "airhorn",
    "banana",
    "bikehorn",
    "bite",
    "boxing",
    "catmeow",
    "catmeow2",
    "gunshot",
    "glass",
    "kaching",
    "phone",
    "robotblip",
    "sonar",
    "siren",
    "water",
    "wilhelm",
}
-- FRESH paths/names/order tables from the catalogue ("none" = name-only, no path). Safe for the SM appenders.
function CludesUI.BuildAlertSoundTables()
    local dir = MEDIA_PATH .. "sounds\\"
    local paths, nameList, sequence = {}, {}, {}
    for i, k in ipairs(CludesUI.ALERT_SOUND_ORDER) do
        sequence[i] = k
        nameList[k] = CludesUI.ALERT_SOUND_NAMES[k]
        local f = CludesUI.ALERT_SOUND_FILES[k]
        if f then
            paths[k] = dir .. f
        end
    end
    return paths, nameList, sequence
end

-- Plays one catalogue path: a file path, a SoundKit id (1 = silent), or a
-- FileDataID when isFile is set (a number the catalogue cannot tell apart).
function CludesUI.PlaySoundPath(filePath, isFile)
    if type(filePath) == "number" then
        if isFile then
            PlaySoundFile(filePath, "Master")
        elseif filePath ~= 1 then
            PlaySound(filePath, "Master")
        end
    elseif filePath then
        PlaySoundFile(filePath, "Master")
    end
end

-- Statusbar texture catalogue: same contract as the sound catalogue above.
CludesUI.BAR_TEXTURE_FILES = {
    melli = "melli.tga",
    beautiful = "beautiful.tga",
    plating = "plating.tga",
    atrocity = "atrocity.tga",
    divide = "divide.tga",
    glass = "glass.tga",
    ["fade-right"] = "fade-right.tga",
    ["thin-line-top"] = "thin-line-top.tga",
    ["thin-line-bottom"] = "thin-line-bottom.tga",
    fade = "fade.tga",
    ["gradient-lr"] = "gradient-lr.tga",
    ["gradient-rl"] = "gradient-rl.tga",
    ["gradient-bt"] = "gradient-bt.tga",
    ["gradient-tb"] = "gradient-tb.tga",
    matte = "matte.tga",
    sheer = "sheer.tga",
    ["pixels-fill"] = "pixels-fill.tga",
    ["pixels-dark"] = "pixels-dark.tga",
    ["pixels-bg"] = "pixels-bg.tga",
    ["blinkii-diamonds"] = "blinkii-diamonds.tga",
    ["kringel-window"] = "kringel-window.tga",
}
CludesUI.BAR_TEXTURE_NAMES = {
    none = "None",
    melli = "Melli (ElvUI)",
    beautiful = "Beautiful",
    plating = "Plating",
    atrocity = "Atrocity",
    divide = "Divide",
    glass = "Glass",
    ["fade-right"] = "Fade Right",
    ["thin-line-top"] = "Thin Line Top",
    ["thin-line-bottom"] = "Thin Line Bottom",
    fade = "Fade",
    ["gradient-lr"] = "Gradient Right",
    ["gradient-rl"] = "Gradient Left",
    ["gradient-bt"] = "Gradient Up",
    ["gradient-tb"] = "Gradient Down",
    matte = "Matte",
    sheer = "Sheer",
    ["pixels-fill"] = "Pixels Fill",
    ["pixels-dark"] = "Pixels Dark",
    ["pixels-bg"] = "Pixels Background",
    ["blinkii-diamonds"] = "Blinkii Diamonds",
    ["kringel-window"] = "Kringel Window",
}
CludesUI.BAR_TEXTURE_ORDER = {
    "none",
    "melli",
    "atrocity",
    "fade",
    "fade-right",
    "thin-line-top",
    "thin-line-bottom",
    "beautiful",
    "plating",
    "divide",
    "glass",
    "gradient-lr",
    "gradient-rl",
    "gradient-bt",
    "gradient-tb",
    "matte",
    "sheer",
    "pixels-fill",
    "pixels-dark",
    "pixels-bg",
    "blinkii-diamonds",
    "kringel-window",
}
-- FRESH textures/names/order tables. includeExtras=true = full 22-key set; else core set
-- without the pattern textures (blinkii-diamonds, kringel-window). "none" is name-only.
function CludesUI.BuildBarTextureTables(includeExtras)
    local dir = MEDIA_PATH .. "textures\\"
    local texture, nameList, sequence = {}, {}, {}
    for _, k in ipairs(CludesUI.BAR_TEXTURE_ORDER) do
        if includeExtras or (k ~= "blinkii-diamonds" and k ~= "kringel-window") then
            sequence[#sequence + 1] = k
            nameList[k] = CludesUI.BAR_TEXTURE_NAMES[k]
            local f = CludesUI.BAR_TEXTURE_FILES[k]
            if f then
                texture[k] = dir .. f
            end
        end
    end
    return texture, nameList, sequence
end

-- Absorb bar style catalogue (Unit Frames absorbs, the Resource Bars health bar
-- overlays): key -> file, the styles drawn as repeating tiles (every other style
-- stretches; striped3 is a stretch texture, never add "striped"), the dropdown
-- names and the shield / heal absorb orders. Readers copy the names and orders
-- before appending the SharedMedia tail; never mutate these.
CludesUI.ABSORB_STYLE_TEX = {
    striped = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped3.tga",
    stripedReversed = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped-5-reversed.png",
    stripedThick = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped-thick.png",
    stripedThickR = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped-thick-r.png",
    clean = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\blizzard.tga",
    largeOutlinedStripes = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-habsorb-left.png",
    largeOutlinedStripesR = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-habsorb-right.png",
    largeStripes = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-absorb-left.png",
    largeStripesR = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-absorb-right.png",
    pixelsShield = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\pixels-shield.tga",
    pixelsShieldEdge = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\pixels-shield-edge.tga",
    pixelsShieldFill = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\pixels-shield-fill.tga",
}
CludesUI.ABSORB_TILED_STYLES = {
    stripedReversed = true,
    stripedThick = true,
    stripedThickR = true,
    largeStripes = true,
    largeStripesR = true,
    largeOutlinedStripes = true,
    largeOutlinedStripesR = true,
    pixelsShieldFill = true,
}
CludesUI.ABSORB_STYLE_NAMES = {
    none = "None",
    striped = "Striped",
    stripedReversed = "Striped Reversed",
    stripedThick = "Striped Thick",
    stripedThickR = "Striped Thick Reversed",
    clean = "Clean (Flat)",
    blizzard = "Blizzard",
    largeOutlinedStripes = "Large Outlined Stripes", -- heal absorb only
    largeOutlinedStripesR = "Large Outlined Stripes R", -- heal absorb only
    largeStripes = "Large Stripes",
    largeStripesR = "Large Stripes R",
    pixelsShield = "Pixels Shield",
    pixelsShieldEdge = "Pixels Shield Edge", -- shield only
    pixelsShieldFill = "Pixels Shield Fill", -- shield only
}
CludesUI.ABSORB_STYLE_ORDER = {
    "none",
    "striped",
    "stripedReversed",
    "stripedThick",
    "stripedThickR",
    "clean",
    "blizzard",
    "largeStripes",
    "largeStripesR",
    "pixelsShield",
    "pixelsShieldEdge",
    "pixelsShieldFill",
}
CludesUI.HEAL_ABSORB_STYLE_ORDER = {
    "none",
    "striped",
    "stripedReversed",
    "stripedThick",
    "stripedThickR",
    "clean",
    "blizzard",
    "largeOutlinedStripes",
    "largeOutlinedStripesR",
    "largeStripes",
    "largeStripesR",
    "pixelsShield",
}

-- Max Health Style: the temporary max health loss overlay of the Raid & Party
-- Frames and the Unit Frames. Its own stripes, or any style the calling module's
-- resolver knows (resolveTex(style, fallback): its built-ins and SharedMedia).
-- Plain Striped tiles here, unlike on the absorbs; the pre-colored heal absorb
-- styles draw untinted. Sets the fill's texture, tint, opacity and layer and
-- returns it; the caller owns the fill rotation, any mask and the backing.
CludesUI.MAX_HEALTH_STRIPES_TEX = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped-maxhp.png"
CludesUI.MAX_HEALTH_COLOR = { r = 0.7, g = 0.1, b = 0.1 }
do
    local UNTINTED = { healBlizzModern = true, largeOutlinedStripes = true, largeOutlinedStripesR = true }
    local WHITE = { r = 1, g = 1, b = 1 }
    function CludesUI.ApplyMaxHealthStyle(bar, look, prefs, resolveTex)
        local texture, tiled
        if look == "maxHealthStripes" then
            texture, tiled = CludesUI.MAX_HEALTH_STRIPES_TEX, true
        else
            texture = resolveTex(look, "Interface\\Buttons\\WHITE8X8")
            tiled = look == "striped" or CludesUI.ABSORB_TILED_STYLES[look] == true
        end
        local mc = UNTINTED[look] and WHITE or (prefs and prefs.maxHealthColor) or CludesUI.MAX_HEALTH_COLOR
        bar:SetStatusBarTexture(texture)
        bar:SetStatusBarColor(
            mc.r or 0.7,
            mc.g or 0.1,
            mc.b or 0.1,
            prefs and (prefs.maxHealthOpacity or 100) / 100 or 1
        )
        local fillTex = bar:GetStatusBarTexture()
        if fillTex then
            fillTex:SetDrawLayer("ARTWORK", 3)
            fillTex:SetHorizTile(tiled)
            fillTex:SetVertTile(tiled)
        end
        return fillTex
    end
end

-- Numeric constants
CludesUI.TEXT_WHITE_R = STYLE.TEXT_WHITE_R
CludesUI.TEXT_WHITE_G = STYLE.TEXT_WHITE_G
CludesUI.TEXT_WHITE_B = STYLE.TEXT_WHITE_B
CludesUI.TEXT_DIM_R = STYLE.TEXT_DIM_R
CludesUI.TEXT_DIM_G = STYLE.TEXT_DIM_G
CludesUI.TEXT_DIM_B = STYLE.TEXT_DIM_B
CludesUI.TEXT_DIM_A = STYLE.TEXT_DIM_A
CludesUI.TEXT_SECTION_R = STYLE.TEXT_SECTION_R
CludesUI.TEXT_SECTION_G = STYLE.TEXT_SECTION_G
CludesUI.TEXT_SECTION_B = STYLE.TEXT_SECTION_B
CludesUI.TEXT_SECTION_A = STYLE.TEXT_SECTION_A
CludesUI.ROW_BG_ODD = STYLE.ROW_BG_ODD
CludesUI.ROW_BG_EVEN = STYLE.ROW_BG_EVEN
CludesUI.BORDER_R = STYLE.BORDER_R
CludesUI.BORDER_G = STYLE.BORDER_G
CludesUI.BORDER_B = STYLE.BORDER_B
CludesUI.CONTENT_PAD = CONTENT_PAD
-- Slider
CludesUI.SL_TRACK_R = STYLE.SL_TRACK_R
CludesUI.SL_TRACK_G = STYLE.SL_TRACK_G
CludesUI.SL_TRACK_B = STYLE.SL_TRACK_B
CludesUI.SL_TRACK_A = STYLE.SL_TRACK_A
CludesUI.SL_FILL_A = STYLE.SL_FILL_A
CludesUI.SL_INPUT_R = STYLE.SL_INPUT_R
CludesUI.SL_INPUT_G = STYLE.SL_INPUT_G
CludesUI.SL_INPUT_B = STYLE.SL_INPUT_B
CludesUI.SL_INPUT_A = STYLE.SL_INPUT_A
CludesUI.SL_INPUT_BRD_A = STYLE.SL_INPUT_BRD_A
CludesUI.MW_INPUT_ALPHA_BOOST = STYLE.MW_INPUT_ALPHA_BOOST
CludesUI.MW_TRACK_ALPHA_BOOST = STYLE.MW_TRACK_ALPHA_BOOST
-- Toggle
CludesUI.TG_OFF_R = STYLE.TG_OFF_R
CludesUI.TG_OFF_G = STYLE.TG_OFF_G
CludesUI.TG_OFF_B = STYLE.TG_OFF_B
CludesUI.TG_OFF_A = STYLE.TG_OFF_A
CludesUI.TG_ON_A = STYLE.TG_ON_A
CludesUI.TG_KNOB_OFF_R = STYLE.TG_KNOB_OFF_R
CludesUI.TG_KNOB_OFF_G = STYLE.TG_KNOB_OFF_G
CludesUI.TG_KNOB_OFF_B = STYLE.TG_KNOB_OFF_B
CludesUI.TG_KNOB_OFF_A = STYLE.TG_KNOB_OFF_A
CludesUI.TG_KNOB_ON_R = STYLE.TG_KNOB_ON_R
CludesUI.TG_KNOB_ON_G = STYLE.TG_KNOB_ON_G
CludesUI.TG_KNOB_ON_B = STYLE.TG_KNOB_ON_B
CludesUI.TG_KNOB_ON_A = STYLE.TG_KNOB_ON_A
-- Checkbox
CludesUI.CB_BOX_R = STYLE.CB_BOX_R
CludesUI.CB_BOX_G = STYLE.CB_BOX_G
CludesUI.CB_BOX_B = STYLE.CB_BOX_B
CludesUI.CB_BRD_A = STYLE.CB_BRD_A
CludesUI.CB_ACT_BRD_A = STYLE.CB_ACT_BRD_A
-- Button
CludesUI.BTN_BG_R = STYLE.BTN_BG_R
CludesUI.BTN_BG_G = STYLE.BTN_BG_G
CludesUI.BTN_BG_B = STYLE.BTN_BG_B
CludesUI.BTN_BG_A = STYLE.BTN_BG_A
CludesUI.BTN_BG_HA = STYLE.BTN_BG_HA
CludesUI.BTN_BRD_A = STYLE.BTN_BRD_A
CludesUI.BTN_BRD_HA = STYLE.BTN_BRD_HA
CludesUI.BTN_TXT_A = STYLE.BTN_TXT_A
CludesUI.BTN_TXT_HA = STYLE.BTN_TXT_HA
-- Dropdown
CludesUI.DD_BG_R = STYLE.DD_BG_R
CludesUI.DD_BG_G = STYLE.DD_BG_G
CludesUI.DD_BG_B = STYLE.DD_BG_B
CludesUI.DD_BG_A = STYLE.DD_BG_A
CludesUI.DD_BG_HA = STYLE.DD_BG_HA
CludesUI.DD_BRD_A = STYLE.DD_BRD_A
CludesUI.DD_BRD_HA = STYLE.DD_BRD_HA
CludesUI.DD_TXT_A = STYLE.DD_TXT_A
CludesUI.DD_TXT_HA = STYLE.DD_TXT_HA
CludesUI.DD_ITEM_HL_A = STYLE.DD_ITEM_HL_A
CludesUI.DD_ITEM_SEL_A = STYLE.DD_ITEM_SEL_A
-- Blizzard reskin colors (tooltips, context menus, popups)
CludesUI.RESKIN = {
    BG_R = 0.067,
    BG_G = 0.067,
    BG_B = 0.067,
    TT_ALPHA = 0.92, -- tooltip background alpha
    CTX_ALPHA = 0.95, -- blizzard context menu background alpha
    QT_ALPHA = 0.97, -- quest tracker right-click menu alpha
    BRD_ALPHA = 0.18, -- border alpha (white)
}

-- LFG queue accept countdown defaults (shared by the skin and its options)
CludesUI.QUEUE_TIMER = {
    TEXT_R = 1,
    TEXT_G = 0.831,
    TEXT_B = 0, -- #ffd400
    TEXT_SIZE = 9,
    BAR_HEIGHT = 11,
    TEXT_OFFSET_Y = 0,
}

-- Unified tooltip background for BOTH the Blizzard tooltip reskin and CUI widget tooltips.
-- Customizable via Blizz UI Enhanced > Blizzard Tooltip (tooltipBgColor/tooltipBgOpacity in
-- CludesUIDB); unset = RESKIN palette. Returns r,g,b,a (0 is valid: Lua 0 is truthy, so `or` fallback fires on nil only).
function CludesUI.GetTooltipBg()
    local saved = CludesUIDB
    local color = saved and saved.tooltipBgColor
    local R = CludesUI.RESKIN
    local r = (color and color.r) or R.BG_R
    local g = (color and color.g) or R.BG_G
    local b = (color and color.b) or R.BG_B
    local a = (saved and saved.tooltipBgOpacity) or R.TT_ALPHA
    return r, g, b, a
end
-- Tooltip border for the Blizzard tooltip reskin (Blizz UI Enhanced > Blizzard Tooltip >
-- Border); unset = white @ BRD_ALPHA, 1px. Returns r,g,b,a,size (0 is valid).
function CludesUI.GetTooltipBorder()
    local saved = CludesUIDB
    local color = saved and saved.tooltipBorderColor
    local r = (color and color.r) or 1
    local g = (color and color.g) or 1
    local b = (color and color.b) or 1
    local a = (saved and saved.tooltipBorderOpacity) or CludesUI.RESKIN.BRD_ALPHA
    local px = (saved and saved.tooltipBorderSize) or 1
    return r, g, b, a, px
end
-- Layout
CludesUI.DUAL_ITEM_W = STYLE.DUAL_ITEM_W
CludesUI.DUAL_GAP = STYLE.DUAL_GAP
CludesUI.TRIPLE_ITEM_W = STYLE.TRIPLE_ITEM_W
CludesUI.TRIPLE_GAP = STYLE.TRIPLE_GAP

-- Table constants
CludesUI.CLASS_COLOR_MAP = CLASS_COLOR_MAP
CludesUI.CLASS_ART_MAP = CLASS_ART_MAP

-- Upgrade track identification (locale-agnostic). Deliberately NOT feature-gated: the QoL
-- upgrade calculator needs it with skin/bag modules disabled. Tiny table, built once.
do
    -- Localized C_Item.GetItemUpgradeInfo().trackString -> canonical English key (the upgrade calculator's season tables key on these).
    local KEYS = {
        -- Explorer / Delve
        Explorer = "Explorer",
        Expedicionario = "Explorer",
        Forscher = "Explorer",
        Explorateur = "Explorer",
        Esploratore = "Explorer",
        Explorador = "Explorer",
        Delve = "Explorer",
        -- Adventurer
        Adventurer = "Adventurer",
        Aventurero = "Adventurer",
        Abenteurer = "Adventurer",
        Aventurier = "Adventurer",
        Avventuriero = "Adventurer",
        Aventureiro = "Adventurer",
        -- Veteran
        Veteran = "Veteran",
        Veterano = "Veteran",
        ["V\195\169t\195\169ran"] = "Veteran",
        -- Champion
        Champion = "Champion",
        ["Campe\195\179n"] = "Champion",
        Campione = "Champion",
        ["Campe\195\163o"] = "Champion",
        -- Hero
        Hero = "Hero",
        ["H\195\169roe"] = "Hero",
        Held = "Hero",
        ["H\195\169ros"] = "Hero",
        Eroe = "Hero",
        ["Hero\195\173"] = "Hero",
        -- Myth
        Myth = "Myth",
        Mito = "Myth",
        Mythos = "Myth",
        Mythe = "Myth",
        -- ruRU
        ["\208\152\209\129\209\129\208\187\208\181\208\180\208\190\208\178\208\176\209\130\208\181\208\187\209\140"] = "Explorer",
        ["\208\152\209\129\208\186\208\176\209\130\208\181\208\187\209\140 \208\191\209\128\208\184\208\186\208\187\209\142\209\135\208\181\208\189\208\184\208\185"] = "Adventurer",
        ["\208\146\208\181\209\130\208\181\209\128\208\176\208\189"] = "Veteran",
        ["\208\151\208\176\209\137\208\184\209\130\208\189\208\184\208\186"] = "Champion",
        ["\208\147\208\181\209\128\208\190\208\185"] = "Hero",
        ["\208\155\208\181\208\179\208\181\208\189\208\180\208\176"] = "Myth",
        -- koKR
        ["\237\131\144\237\151\152\234\176\128"] = "Explorer",
        ["\235\170\168\237\151\152\234\176\128"] = "Adventurer",
        ["\235\133\184\235\160\168\234\176\128"] = "Veteran",
        ["\236\177\148\237\148\188\236\150\184"] = "Champion",
        ["\236\152\129\236\155\133"] = "Hero",
        ["\236\139\160\237\153\148"] = "Myth",
        -- zhCN
        ["\230\142\162\231\180\162\232\128\133"] = "Explorer",
        ["\229\134\146\233\153\169\232\128\133"] = "Adventurer",
        ["\232\128\129\229\133\181"] = "Veteran",
        ["\229\139\135\229\163\171"] = "Champion",
        ["\232\139\177\233\155\132"] = "Hero",
        ["\231\165\158\232\175\157"] = "Myth",
        -- zhTW
        ["\230\142\162\233\154\170\232\128\133"] = "Explorer",
        ["\229\134\146\233\154\170\232\128\133"] = "Adventurer",
        ["\231\178\190\229\133\181"] = "Veteran",
        ["\231\165\158\232\169\177"] = "Myth",
    }

    CludesUI.UPGRADE_TRACK_KEYS = KEYS

    -- Returns trackKey (canonical English) | nil, currentLevel, maxLevel; nil trackKey means
    -- a no-track item (crafted, older) or an untranslated trackString.
    function CludesUI.GetUpgradeTrackKey(itemLinkStr)
        if not itemLinkStr or not (C_Item and C_Item.GetItemUpgradeInfo) then
            return nil
        end
        local details = C_Item.GetItemUpgradeInfo(itemLinkStr)
        if not details then
            return nil
        end
        return KEYS[details.trackString or ""], details.currentLevel, details.maxLevel
    end
end

-- Upgrade track color data (shared by BlizzardSkin character/inspect sheets + Bags); only
-- initialized when a consumer feature is enabled.
do
    local en = C_AddOns and C_AddOns.GetAddOnEnableState
    local need = en
        and (
            (en("CludesUIBags") or 0) > 0
            or (
                (en("CludesUIBlizzardSkin") or 0) > 0
                and (
                    not CludesUIDB
                    or CludesUIDB.themedCharacterSheet ~= false
                    or CludesUIDB.themedInspectSheet ~= false
                )
            )
        )
    if need then
        local W = { r = 1.00, g = 1.00, b = 1.00 }
        local CH = { r = 0.00, g = 0.44, b = 0.87 }
        local MY = { r = 1.00, g = 0.50, b = 0.00 }
        local HE = { r = 1.00, g = 0.30, b = 1.00 }
        local VE = { r = 0.12, g = 1.00, b = 0.00 }
        local GR = { r = 0.62, g = 0.62, b = 0.62 }

        CludesUI._TRACK_WHITE = W
        CludesUI._TRACK_RANK = { [GR] = 1, [W] = 2, [VE] = 3, [CH] = 4, [HE] = 5, [MY] = 6 }

        -- Canonical track key -> hue (localized translation lives ONLY in UPGRADE_TRACK_KEYS).
        local map = {
            Explorer = GR,
            Adventurer = W,
            Veteran = VE,
            Champion = CH,
            Hero = HE,
            Myth = MY,
        }

        function CludesUI.GetUpgradeTrack(itemLinkStr)
            local entryKey, cur, maxL = CludesUI.GetUpgradeTrackKey(itemLinkStr)
            local textValue = (cur and maxL and maxL > 0) and (cur .. "/" .. maxL) or ""
            return textValue, map[entryKey or ""] or W
        end

        -- Crest bonuses identify the crafting tier independently of quality and
        -- overlapping item levels. Midnight S2 Hero/Myth: 13835/13836.
        -- Source: https://www.raidbots.com/static/data/live/bonuses.json
        local craftedColors = { [13835] = HE, [13836] = MY }
        local function ParseCraftedTrackColor(itemLinkStr)
            local payload = itemLinkStr:match("item:([^|]+)")
            if not payload then
                return nil
            end
            local slotIndex, lastBonus = 0, 13
            for field in (payload .. ":"):gmatch("([^:]*):") do
                slotIndex = slotIndex + 1
                if slotIndex == 13 then
                    lastBonus = 13 + (tonumber(field) or 0)
                elseif slotIndex > 13 then
                    if slotIndex > lastBonus then
                        break
                    end
                    local color = craftedColors[tonumber(field)]
                    if color then
                        return color
                    end
                end
            end
            return nil
        end
        -- Memoized per link: the Bags inventory/bank refresh asks for every
        -- untracked gear item on every pass (bag-update bursts), and the parse
        -- above concatenates and splits the link each time. Links are
        -- per-instance, so the memo is bounded and wiped like Bags' sort cache;
        -- `false` records a miss so the parse never repeats for one link.
        local craftedCache, craftedCacheN = {}, 0
        function CludesUI.GetCraftedTrackColor(itemLinkStr)
            if type(itemLinkStr) ~= "string" then
                return nil
            end
            local hit = craftedCache[itemLinkStr]
            if hit ~= nil then
                return hit or nil
            end
            local color = ParseCraftedTrackColor(itemLinkStr)
            if craftedCacheN >= 4000 then
                wipe(craftedCache)
                craftedCacheN = 0
            end
            craftedCache[itemLinkStr] = color or false
            craftedCacheN = craftedCacheN + 1
            return color
        end

        -- Item-level text color: custom override > upgrade-track hue > crafted-crest hue >
        -- item rarity > white. Shared by character sheet, inspect sheet, equipment flyout and
        -- merchant. upgradeText/upgradeColor: a GetUpgradeTrack result the caller already has.
        function CludesUI.GetItemLevelColor(itemLinkStr, itemQuality, upgradeText, upgradeColor)
            if
                CludesUIDB
                and CludesUIDB.charSheetItemLevelUseColor
                and CludesUIDB.charSheetItemLevelColor
            then
                return CludesUIDB.charSheetItemLevelColor
            end
            if upgradeText == nil then
                upgradeText, upgradeColor = CludesUI.GetUpgradeTrack(itemLinkStr)
            end
            if upgradeText and upgradeText ~= "" and upgradeColor then
                return upgradeColor
            end
            local crafted = CludesUI.GetCraftedTrackColor(itemLinkStr)
            if crafted then
                return crafted
            end
            if (not CludesUIDB or CludesUIDB.charSheetColorItemLevel ~= false) and itemQuality then
                local red, green, blue = C_Item.GetItemQualityColor(itemQuality)
                return { r = red, g = green, b = blue }
            end
            return { r = 1, g = 1, b = 1 }
        end
    end
end

-- Stat letters for an item: its secondaries by amount, largest first ("MH"),
-- and its tertiaries the same way ("L"), returned apart so callers can show
-- the tertiaries smaller. Ties keep the list order. The letters stay English
-- in every locale (the usual shorthand). Shared by the equipment flyout, the
-- character sheet slots and the socket panel. Memoized per link (the link
-- carries the bonus IDs, so catalyst variants of one item differ); an item
-- whose stats have not loaded yet is not recorded, and its third return
-- (pending) is true while the client has not cached the item at all.
do
    local SECONDARY = {
        { "ITEM_MOD_CRIT_RATING_SHORT", "C" },
        { "ITEM_MOD_HASTE_RATING_SHORT", "H" },
        { "ITEM_MOD_MASTERY_RATING_SHORT", "M" },
        { "ITEM_MOD_VERSATILITY", "V" },
    }
    local TERTIARY = {
        { "ITEM_MOD_CR_LIFESTEAL_SHORT", "L" },
        { "ITEM_MOD_CR_AVOIDANCE_SHORT", "A" },
        { "ITEM_MOD_CR_SPEED_SHORT", "S" },
    }

    local function Letters(statList, entries)
        local picked = {}
        for i = 1, #entries do
            local v = statList[entries[i][1]]
            if type(v) == "number" and v > 0 then
                picked[#picked + 1] = i
            end
        end
        table.sort(picked, function(lhs, rhs)
            local va, vb = statList[entries[lhs][1]], statList[entries[rhs][1]]
            if va ~= vb then
                return va > vb
            end
            return lhs < rhs
        end)
        local result = ""
        for n = 1, #picked do
            result = result .. entries[picked[n]][2]
        end
        return result
    end

    -- Stat amounts read off the item's tooltip data, for items whose stats
    -- C_Item.GetItemStats leaves empty (gems: "+16 Versatility & +7 Critical
    -- Strike"). Each listed stat's localized name (_G[key]) is found in a line,
    -- in any letter case (some locales lower-case a stat mid-line), and paired
    -- with the last number before it; a stat takes the first line that gives
    -- it one. C_TooltipInfo only: never a scanning tooltip frame. The second
    -- return is false when there was no tooltip data to read.
    local LISTS = { SECONDARY, TERTIARY }
    -- Each listed stat's key and lower-cased name, built on the first read
    -- (the names are constant for the session).
    local NAMES
    local function StatNames()
        if not NAMES then
            NAMES = {}
            for _, entries in ipairs(LISTS) do
                for i = 1, #entries do
                    local label = _G[entries[i][1]]
                    if type(label) == "string" and label ~= "" then
                        NAMES[#NAMES + 1] = { entries[i][1], label:lower() }
                    end
                end
            end
        end
        return NAMES
    end
    local function TooltipStats(itemLinkStr)
        if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
            return nil, false
        end
        local info = C_TooltipInfo.GetHyperlink(itemLinkStr)
        local lines = info and info.lines
        if not lines then
            return nil, false
        end
        local nameList = StatNames()
        local statList
        for _, line in ipairs(lines) do
            local textValue = line.leftText
            if type(textValue) == "string" and textValue ~= "" then
                local low = textValue:lower()
                for jdx = 1, #nameList do
                    local entryKey = nameList[jdx][1]
                    if not (statList and statList[entryKey]) then
                        local place = low:find(nameList[jdx][2], 1, true)
                        if place then
                            local num = textValue:sub(1, place - 1):match("(%d[%d%.,]*)%D*$")
                            local v = num and tonumber((num:gsub("%D", "")))
                            if v and v > 0 then
                                statList = statList or {}
                                statList[entryKey] = v
                            end
                        end
                    end
                end
            end
        end
        return statList, true
    end

    local secCache, terCache, cacheN = {}, {}, 0
    function CludesUI.GetItemStatLetters(itemLinkStr)
        if type(itemLinkStr) ~= "string" then
            return "", "", false
        end
        local secondary = secCache[itemLinkStr]
        if secondary then
            return secondary, terCache[itemLinkStr], false
        end
        local statList = C_Item.GetItemStats and C_Item.GetItemStats(itemLinkStr)
        local read = true
        if not statList or next(statList) == nil then
            statList, read = TooltipStats(itemLinkStr)
        end
        local tertiary = ""
        secondary = ""
        if statList then
            secondary, tertiary = Letters(statList, SECONDARY), Letters(statList, TERTIARY)
        end
        -- A read made before the item's data loads can come back short: one
        -- that found no letters is recorded only once the client has the item
        -- and its tooltip was read (an item with no such stats then stops
        -- reading its tooltip).
        if secondary == "" and tertiary == "" then
            local loading = C_Item.GetItemInfo(itemLinkStr) == nil
            if loading or not read then
                return secondary, tertiary, loading
            end
        end
        if cacheN >= 2000 then
            wipe(secCache)
            wipe(terCache)
            cacheN = 0
        end
        secCache[itemLinkStr], terCache[itemLinkStr] = secondary, tertiary
        cacheN = cacheN + 1
        return secondary, tertiary, false
    end

    -- An item's letters for a main label and a smaller one: the secondaries,
    -- then the tertiaries (when withTertiary). An item with only tertiaries
    -- gives them for the main label; a nil link gives two empty strings.
    local function StatLetterPair(link, withTertiary)
        local secondary, tertiary, loading = "", "", false
        if link then
            secondary, tertiary, loading = CludesUI.GetItemStatLetters(link)
        end
        if not withTertiary then
            tertiary = ""
        end
        if secondary == "" then
            secondary, tertiary = tertiary, ""
        end
        return secondary, tertiary, loading
    end

    -- Paints an item's letters into `main`, with its tertiaries in `small`,
    -- the smaller label the caller hung off main's right; the pair is centred
    -- along `anchor`'s bottom edge. Returns GetItemStatLetters' pending flag.
    function CludesUI.PaintStatLetters(main, small, link, withTertiary, anchor)
        local secondary, tertiary, loading = StatLetterPair(link, withTertiary)
        main:SetText(secondary)
        small:SetText(tertiary)
        local wid = main:GetStringWidth() + (tertiary ~= "" and small:GetStringWidth() + 1 or 0)
        main:ClearAllPoints()
        main:SetPoint("BOTTOMLEFT", anchor, "BOTTOM", -wid / 2, 2)
        return loading
    end

    -- At most two letters: three or more read as the first and "+" ("CHM"
    -- shows "C+").
    local function TwoLetters(s)
        if #s > 2 then
            return s:sub(1, 1) .. "+"
        end
        return s
    end

    -- Paints an item's letters as two rows the caller placed: the secondaries
    -- in `main`, the tertiaries in `small`, each at most two letters. Returns
    -- GetItemStatLetters' pending flag.
    function CludesUI.PaintStatLetterRows(main, small, link, withTertiary)
        local secondary, tertiary, loading = StatLetterPair(link, withTertiary)
        main:SetText(TwoLetters(secondary))
        small:SetText(TwoLetters(tertiary))
        return loading
    end
end

-- File-level PanelPP reference for panel layout code below
local PanelPP = CludesUI.PanelPP

-- Critical Strike and Haste as Blizzard's character pane shows them. WoW Forever
-- keeps melee, ranged and spell crit and haste apart and shows the highest with
-- its matching rating. Retail crit makes the same pick between the lowest spell
-- crit across the magic schools (2 = Holy up to MAX_SPELL_SCHOOLS), ranged and
-- melee; retail haste is one figure. The getters go secret while unit stats are
-- restricted, so the source picked on the last readable update is reused until
-- the next one; before any readable update retail gets spell (Blizzard's tie
-- winner), and on Forever casters get spell, hunters ranged (haste only once a
-- ranged total has been read) and everyone else melee.
do
    local FOREVER_CASTER = { MAGE = true, PRIEST = true, WARLOCK = true }
    local statPick = {}
    local foreverRangedHaste

    local function ForeverFallbackPick(kind)
        if statPick[kind] then
            return statPick[kind]
        end
        local _, classTok = UnitClass("player")
        if not issecretvalue(classTok) then
            if FOREVER_CASTER[classTok] then
                return "spell"
            end
            if classTok == "HUNTER" and (kind == "crit" or foreverRangedHaste) then
                return "ranged"
            end
        end
        return "melee"
    end

    local function HighestPick(spell, rangedPick, meleePick)
        if spell >= rangedPick and spell >= meleePick then
            return "spell"
        end
        if rangedPick >= meleePick then
            return "ranged"
        end
        return "melee"
    end

    function CludesUI.ForeverCritChance()
        local spell, rangedPick, meleePick = GetSpellCritChance(), GetRangedCritChance(), GetCritChance()
        local choice
        if issecretvalue(spell) or issecretvalue(rangedPick) or issecretvalue(meleePick) then
            choice = ForeverFallbackPick("crit")
        else
            choice = HighestPick(spell, rangedPick, meleePick)
            statPick.crit = choice
        end
        if choice == "spell" then
            return spell, CR_CRIT_SPELL
        end
        if choice == "ranged" then
            return rangedPick, CR_CRIT_RANGED
        end
        return meleePick, CR_CRIT_MELEE
    end

    function CludesUI.ForeverHaste()
        local spell, meleePick = UnitSpellHaste("player"), GetMeleeHaste()
        local rangedBase, quiver = GetRangedHaste()
        local rangedPick, choice
        if
            issecretvalue(spell)
            or issecretvalue(meleePick)
            or issecretvalue(rangedBase)
            or issecretvalue(quiver)
        then
            choice = ForeverFallbackPick("haste")
            -- The quiver bonus cannot be added to a secret; ranged shows the last readable total.
            rangedPick = foreverRangedHaste
        else
            rangedPick = rangedBase + (quiver or 0)
            foreverRangedHaste = rangedPick
            choice = HighestPick(spell, rangedPick, meleePick)
            statPick.haste = choice
        end
        if choice == "spell" then
            return spell, CR_HASTE_SPELL
        end
        if choice == "ranged" then
            return rangedPick, CR_HASTE_RANGED
        end
        return meleePick, CR_HASTE_MELEE
    end

    -- Crit for the running client: the Forever pick there, the retail rule here.
    -- Returns percent, rating index.
    function CludesUI.PlayerCritChance()
        if CludesUI.IS_FOREVER then
            return CludesUI.ForeverCritChance()
        end
        local rangedPick, meleePick = GetRangedCritChance(), GetCritChance()
        local spell, school = GetSpellCritChance(2), 2
        local secret = issecretvalue(rangedPick) or issecretvalue(meleePick) or issecretvalue(spell)
        if not secret then
            for i = 3, MAX_SPELL_SCHOOLS or 7 do
                local s = GetSpellCritChance(i)
                if issecretvalue(s) then
                    secret = true
                    break
                end
                if s < spell then
                    spell, school = s, i
                end
            end
        end
        local choice
        if secret then
            choice = statPick.crit or "spell"
            if choice == "spell" then
                spell = GetSpellCritChance(statPick.critSchool or 2)
            end
        else
            choice = HighestPick(spell, rangedPick, meleePick)
            statPick.crit, statPick.critSchool = choice, school
        end
        if choice == "spell" then
            return spell, CR_CRIT_SPELL
        end
        if choice == "ranged" then
            return rangedPick, CR_CRIT_RANGED
        end
        return meleePick, CR_CRIT_MELEE
    end
end

-- Group role with the local player's spec as the authority. The role picked
-- when listing a premade group sticks server-side through spec swaps (list a
-- key as tank, swap to dps: UnitGroupRolesAssigned still answers TANK for the
-- life of the group, surviving /reload and a manual role set), so for the
-- player the spec-derived role wins whenever spec data is readable. Other
-- units have no readable spec, so they keep the assigned role. The client
-- makes that role secret for a unit whose identity it restricts, and the
-- player test secret where unit comparisons are restricted: a secret role
-- returns nil plus true, so every caller can compare what it gets (the role
-- icon paints a secret one through Blizzard's own painter).
function CludesUI.UnitEffectiveRole(unitToken)
    local isPlayer = UnitIsUnit(unitToken, "player")
    if not issecretvalue(isPlayer) and isPlayer then
        local specInfo = GetSpecialization and GetSpecialization()
        local roleName = specInfo and GetSpecializationRole and GetSpecializationRole(specInfo)
        if roleName then
            return roleName
        end
    end
    local roleName = UnitGroupRolesAssigned(unitToken)
    if issecretvalue(roleName) then
        return nil, true
    end
    return roleName
end

-- WoW Forever has no specs, so the effective role above is only the group's
-- assigned one there: a tank's shape or stance tells the rest (Bear Form,
-- Dire Bear Form or Defensive Stance, by shapeshift form ID). Callers on the
-- Forever client add this to the role, but only while nobody in the group has
-- the tank role assigned (CludesUI.GroupHasTankRole): then the role decides.
function CludesUI.ForeverTankForm()
    local formIndex = GetShapeshiftFormID()
    return formIndex == 5 or formIndex == 8 or formIndex == 18
end

-- Whether anyone in the group, the player included, has the tank role assigned.
-- The second return is true when a restricted (secret) role read leaves a "no"
-- unsure; a tank found is always sure.
do
    local raidTok, partyTok = {}, {}
    for i = 1, 40 do
        raidTok[i] = "raid" .. i
    end
    for i = 1, 4 do
        partyTok[i] = "party" .. i
    end
    function CludesUI.GroupHasTankRole()
        local unsure = false
        local roleName = UnitGroupRolesAssigned("player")
        if issecretvalue(roleName) then
            unsure = true
        elseif roleName == "TANK" then
            return true, false
        end
        local unitKey, count = nil, 0
        if IsInRaid() then
            unitKey, count = raidTok, GetNumGroupMembers()
        elseif IsInGroup() then
            unitKey, count = partyTok, GetNumGroupMembers() - 1
        end
        for i = 1, unitKey and math.min(count, #unitKey) or 0 do
            roleName = UnitGroupRolesAssigned(unitKey[i])
            if issecretvalue(roleName) then
                unsure = true
            elseif roleName == "TANK" then
                return true, false
            end
        end
        return false, unsure
    end
end

-------------------------------------------------------------------------------
--  Resource trackers (secret-value safe)
--  Maelstrom Weapon (344179), Tip of the Spear (260286) and Devourer soul
--  fragment auras (1225789, 1227702) are Blizzard-whitelisted and stay readable.
-------------------------------------------------------------------------------

-- Tip of the Spear stacks (Survival Hunter). Buff 260286 is WHITELISTED, safe to read
-- in combat. Max 3 stacks.
function CludesUI.GetTipOfTheSpear()
    local buff = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(260286)
    return (buff and buff.applications or 0), 3
end

-- DH Soul Fragment count (current, max). Vengeance: C_Spell.GetSpellCastCount(228477)
-- returns a SECRET value the caller must handle (StatusBar or similar). Devourer (hero
-- spec 1480): auras 1225789/1227702 are WHITELISTED, safe to read.
-- Cached spec ID: GetSoulFragments is polled EVERY FRAME and GetSpecialization +
-- GetSpecializationInfo allocate fresh strings per call (~1.9 kb garbage/call, the
-- dominant memory churn). Spec changes only on swap: cache it, refresh on spec events.
CludesUI._RefreshSpecID = function()
    local specInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    CludesUI._specID = (specInfo and C_SpecializationInfo.GetSpecializationInfo(specInfo)) or 0
end
CludesUI._specWatcher = CludesUI._specWatcher or CreateFrame("Frame")
CludesUI._specWatcher:RegisterEvent("PLAYER_LOGIN")
CludesUI._specWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
CludesUI._specWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
CludesUI._specWatcher:SetScript("OnEvent", CludesUI._RefreshSpecID)

function CludesUI.GetSoulFragments()
    local specId = CludesUI._specID
    if not specId then -- pre-login / not resolved yet: resolve once
        CludesUI._RefreshSpecID()
        specId = CludesUI._specID
    end
    if specId == 581 then -- Vengeance
        local cur = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
        return cur, 6
    elseif specId == 1480 then -- Devourer (hero spec)
        -- In Void Metamorphosis (1217607): stacks from Silence the Whispers (1227702),
        -- max 40. Outside: Dark Heart (1225789), max 50 (35 with Soul Glutton 1247534).
        -- Surrender to the Void (PvP talent 1261423) adds 50 to whichever value applies.
        local inMeta = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(1217607)
        local buff, max
        if inMeta then
            buff = C_UnitAuras.GetPlayerAuraBySpellID(1227702)
            max = 40
        else
            buff = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(1225789)
            max = (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(1247534)) and 35
                or 50
            if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(1261423) then
                max = max + 50
            end
        end
        return (buff and buff.applications or 0), max
    end
    -- Havoc or unknown spec: no soul fragments
    return 0, 0
end

-- Enhancement Shaman Maelstrom Weapon stacks (current, max). Buff 344179 is WHITELISTED,
-- safe to read in combat. Base max 5 (10 with Raging Maelstrom talent 384143).
function CludesUI.GetMaelstromWeapon()
    local buff = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(344179)
    local max = 5
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(384143) then
        max = 10
    end
    return (buff and buff.applications or 0), max
end

CludesUI.RESOURCE_BAR_ANCHOR_KEYS = {
    none = true,
    mouse = true,
    partyframe = true,
    playerframe = true,
    erb_classresource = true,
    erb_powerbar = true,
    erb_health = true,
    erb_castbar = true,
    erb_cdm = true,
}

do
    local PARTY_FRAME_SOURCES = {
        { addon = "ElvUI", prefix = "ElvUF_PartyGroup1UnitButton", count = 5 },
        { addon = "Cell", prefix = "CellPartyFrameMember", count = 5 },
        { addon = nil, prefix = "CompactPartyFrameMember", count = 5 },
        { addon = nil, prefix = "CompactRaidFrame", count = 40 },
    }

    local PLAYER_FRAME_SOURCES = {
        { addon = "CludesUIUnitFrames", global = "CludesUIUnitFrames_Player" },
        { addon = "ElvUI", global = "ElvUF_Player" },
    }

    local _cachedPartyFrame = nil
    local _cachedPlayerFrame = nil
    local _cachedRosterToken = -1

    local function RosterToken()
        return GetNumGroupMembers()
    end

    local function CacheValid()
        return _cachedRosterToken == RosterToken()
    end

    -- Invalidate both caches. Called by CDM and ResourceBars on GROUP_ROSTER_UPDATE
    -- and PLAYER_SPECIALIZATION_CHANGED so the next lookup rescans.
    function CludesUI.InvalidateFrameCache()
        _cachedPartyFrame = nil
        _cachedPlayerFrame = nil
        _cachedRosterToken = -1
    end

    function CludesUI.FindPlayerPartyFrame()
        if _cachedPartyFrame and CacheValid() and _cachedPartyFrame:IsVisible() then
            return _cachedPartyFrame
        end
        _cachedPartyFrame = nil
        _cachedRosterToken = RosterToken()

        for _, source in ipairs(PARTY_FRAME_SOURCES) do
            if not source.addon or C_AddOns.IsAddOnLoaded(source.addon) then
                for i = 1, source.count do
                    local widget = _G[source.prefix .. i]
                    if
                        widget
                        and widget.GetAttribute
                        and widget:GetAttribute("unit") == "player"
                        and widget.IsVisible
                        and widget:IsVisible()
                    then
                        _cachedPartyFrame = widget
                        return widget
                    end
                end
            end
        end

        if C_AddOns.IsAddOnLoaded("DandersFrames") then
            local boxHolder = _G["DandersPartyContainer"]
            if boxHolder and boxHolder.IsVisible and boxHolder:IsVisible() then
                _cachedPartyFrame = boxHolder
                return boxHolder
            end
        end

        return nil
    end

    function CludesUI.FindPlayerUnitFrame()
        if _cachedPlayerFrame and CacheValid() and _cachedPlayerFrame:IsVisible() then
            local u = _cachedPlayerFrame.GetAttribute and _cachedPlayerFrame:GetAttribute("unit")
            if not u or UnitIsUnit(u, "player") then
                return _cachedPlayerFrame
            end
        end
        _cachedPlayerFrame = nil
        _cachedRosterToken = RosterToken()

        for _, source in ipairs(PLAYER_FRAME_SOURCES) do
            if C_AddOns.IsAddOnLoaded(source.addon) then
                local widget = _G[source.global]
                if widget and widget.IsVisible and widget:IsVisible() then
                    _cachedPlayerFrame = widget
                    return widget
                end
            end
        end

        if C_AddOns.IsAddOnLoaded("DandersFrames") then
            local headerText = _G["DandersPartyHeader"]
            if headerText then
                for i = 1, 5 do
                    local childFrame = headerText:GetAttribute("child" .. i)
                    if
                        childFrame
                        and childFrame.GetAttribute
                        and childFrame:GetAttribute("unit") == "player"
                        and childFrame.IsVisible
                        and childFrame:IsVisible()
                    then
                        _cachedPlayerFrame = childFrame
                        return childFrame
                    end
                end
            end
        end

        local stockFrame = _G["PlayerFrame"]
        if stockFrame and stockFrame.IsVisible and stockFrame:IsVisible() then
            _cachedPlayerFrame = stockFrame
            return stockFrame
        end

        return nil
    end
end

-- Tip of the Spear / Whirlwind Stacks: tracked manually above via UNIT_SPELLCAST_SUCCEEDED.

CludesUI.THEME_PRESETS = THEME_PRESETS
CludesUI.THEME_ORDER = THEME_ORDER

-- Path strings Keep the locale glyph-font fallback: plain EXPRESSWAY here would drop it
-- and render CJK/Cyrillic clients as boxes for every later consumer.
CludesUI.EXPRESSWAY = LOCALE_FONT_FALLBACK or EXPRESSWAY
CludesUI.MEDIA_PATH = MEDIA_PATH
CludesUI.ICONS_PATH = ICONS_PATH

-------------------------------------------------------------------------------
--  Portal flyout hearthstone row: shared resolution logic.
--  Called lazily from chat + minimap portal flyouts on Show only.
-------------------------------------------------------------------------------
do
    local HEARTH_TOYS = {
        54452, -- Ethereal Portal
        64488, -- The Innkeeper's Daughter
        93672, -- Dark Portal
        28585, -- Ruby Slippers
        142542, -- Tome of Town Portal
        163045, -- Headless Horseman's Hearthstone
        162973, -- Greatfather Winter's Hearthstone
        165669, -- Lunar Elder's Hearthstone
        165670, -- Peddlefeet's Lovely Hearthstone
        165802, -- Noble Gardener's Hearthstone
        166746, -- Fire Eater's Hearthstone
        166747, -- Brewfest Reveler's Hearthstone
        168907, -- Holographic Digitalization Hearthstone
        172179, -- Eternal Traveler's Hearthstone
        184353, -- Kyrian Hearthstone
        180290, -- Night Fae Hearthstone
        182773, -- Necrolord Hearthstone
        183716, -- Venthyr Sinstone
        188952, -- Dominated Hearthstone
        190237, -- Broker Translocation Matrix
        190196, -- Enlightened Hearthstone
        193588, -- Timewalker's Hearthstone
        200630, -- Ohn'ir Windsage's Hearthstone
        206195, -- Path of the Naaru
        209035, -- Hearthstone of the Flame
        210455, -- Draenic Hologem
        208704, -- Deepdweller's Earthen Hearthstone
        212337, -- Stone of the Hearth
        228940, -- Notorious Thread's Hearthstone
        235016, -- Redeployment Module
        236687, -- Explosive Hearthstone
        245970, -- P.O.S.T. Master's Express Hearthstone
        246565, -- Cosmic Hearthstone
        250411, -- Timerunner's Hearthstone
        257736, -- Lightcalled Hearthstone
        263489, -- Naaru's Enfold
        263933, -- Preyseeker's Hearthstone
        265100, -- Corewarden's Hearthstone
        142298, -- Astonishingly Scarlet Slippers
        264367, -- Mushroom
    }
    local SHAMAN_ASTRAL_RECALL = 556
    local DALARAN_HS = 253629
    local DALARAN_HS_FALLBACK = 140192
    local HOUSING_ICON = MEDIA_PATH .. "icons\\housing-teleport.png"

    -- Get the correct icon for a toy (not the base "learn" item icon)
    local function ToyIcon(ident)
        if C_ToyBox and C_ToyBox.GetToyInfo then
            local _, _, glyph = C_ToyBox.GetToyInfo(ident)
            if glyph then
                return glyph
            end
        end
        return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(ident) or 134414
    end

    -- M+/raid/PvP instance check -- guards against tainted execution.
    -- Dev mode counts as protected: /cuidev forces the addon*RestrictionsForced
    -- CVars, which create the same restricted/secret-value environment anywhere.
    local function InProtectedInstance()
        if CludesUI.IsDevModeActive and CludesUI.IsDevModeActive() then
            return true
        end
        local _, instanceType = IsInInstance()
        if instanceType == "raid" and InCombatLockdown() then
            return true
        end
        if
            instanceType == "party"
            and C_ChallengeMode
            and C_ChallengeMode.IsChallengeModeActive
            and C_ChallengeMode.IsChallengeModeActive()
        then
            return true
        end
        if (instanceType == "pvp" or instanceType == "arena") and InCombatLockdown() then
            return true
        end
        return false
    end
    CludesUI.InProtectedInstance = InProtectedInstance

    -- Check if a toy/item hearthstone is on cooldown.
    -- Skips in M+/raid combat to avoid secret value errors.
    local function IsHearthOnCD(ident)
        if InProtectedInstance() then
            return true
        end
        if C_Container and C_Container.GetItemCooldown then
            local success, start, dur = pcall(C_Container.GetItemCooldown, ident)
            if success and start and dur and dur > 1.5 then
                return true
            end
        end
        return false
    end

    -- Hearthstone toys are account-wide, but the Draenic Hologem works only for
    -- draenei and lightforged draenei: owning it is not enough on other races.
    local function CanUseHearthToy(ident)
        if ident ~= 210455 then
            return true
        end
        local _, race = UnitRace("player")
        if issecretvalue(race) then
            return false
        end
        return race == "Draenei" or race == "LightforgedDraenei"
    end
    CludesUI.CanUseHearthToy = CanUseHearthToy

    -- Resolve slot 1: For Shamans with Astral Recall known:
    --   In M+/raid combat -> always Astral Recall (no CD checks, no secret values)
    --   If any owned toy is on CD -> Astral Recall (shorter CD)
    --   Otherwise -> random owned toy (variety)
    -- For non-Shamans: random owned toy HS, fallback to item 6948
    -- noAstralRecall: resolve as a non-Shaman (Quickdraw's Random Hearthstone).
    function CludesUI.ResolveHearthSlot(noAstralRecall)
        local _, classTok = UnitClass("player")
        local isShaman = not noAstralRecall and classTok == "SHAMAN" and IsPlayerSpell(SHAMAN_ASTRAL_RECALL)

        if isShaman and InProtectedInstance() then
            local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(SHAMAN_ASTRAL_RECALL)
            return "spell", SHAMAN_ASTRAL_RECALL, details and details.iconID or 136010
        end

        -- Collect owned hearthstone toys (6948 is always in bags, not a toy)
        local owned = {}
        for _, ident in ipairs(HEARTH_TOYS) do
            local hasToy = PlayerHasToy and PlayerHasToy(ident)
            if hasToy and CanUseHearthToy(ident) then
                owned[#owned + 1] = ident
            end
        end

        if isShaman and #owned > 0 then
            local anyOnCD = false
            for _, ident in ipairs(owned) do
                if IsHearthOnCD(ident) then
                    anyOnCD = true
                    break
                end
            end
            if anyOnCD then
                local details = C_Spell
                    and C_Spell.GetSpellInfo
                    and C_Spell.GetSpellInfo(SHAMAN_ASTRAL_RECALL)
                return "spell", SHAMAN_ASTRAL_RECALL, details and details.iconID or 136010
            end
        end

        if #owned == 0 then
            local glyph = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(6948) or 134414
            return "item", 6948, glyph
        end
        local choice = owned[math.random(#owned)]
        return "item", choice, ToyIcon(choice)
    end

    -- Resolve slot 2: Dalaran HS 253629 > fallback 140192
    function CludesUI.ResolveDalaranSlot()
        local hasPrimary = PlayerHasToy and PlayerHasToy(DALARAN_HS)
        local ident = hasPrimary and DALARAN_HS or DALARAN_HS_FALLBACK
        return "item", ident, ToyIcon(ident)
    end

    -- Resolve slot 3: Housing dashboard (click handler, not a spell)
    function CludesUI.ResolveHousingSlot()
        return "housing", 0, HOUSING_ICON
    end
end

-- Safe scroll range helper (avoids tainted secret number values)
function CludesUI.SafeScrollRange(scrollFrame)
    local success, val = pcall(scrollFrame.GetVerticalScrollRange, scrollFrame)
    if success and val then
        local secondOk, n = pcall(tonumber, val)
        if secondOk and n then
            local ok3, gt = pcall(function()
                return n > 0
            end)
            if ok3 and gt then
                return n
            end
        end
    end
    return 0
end

-- Smooth wheel scroll + thin draggable scrollbar (shown only on overflow) for a ScrollFrame.
-- opts: step (45), thumbMin (30), width (4), rightInset (2), topInset (4), bottomInset (topInset),
-- trackParent (sf), level (2, above trackParent), trackAlpha (0.02), thumbAlpha (0.27),
-- child (range = child height - sf height, else SafeScrollRange), onScroll(v), thumb (false = wheel only),
-- panelWheel (true: a surface inside the options panel, where Shift + wheel scales the panel instead),
-- passWheel (true: while there is nothing to scroll, the wheel goes on to the options page; a surface inside a page).
-- Returns UpdateThumb, ScrollTo(v) (immediate: stops the lerp, clamps, syncs the thumb).
-- While a controller is in use the bar also carries step arrows and a page strip.
-- On a page-pool host (CludesUI_FramePool.lua) its parts are pooled with the
-- scroll frame, so a call on a reset scroll frame dresses the same bar again.
function CludesUI.AttachSmoothScrollbar(scrollFrame, options)
    options = options or {}
    local step, childFrame, onScroll = options.step or 45, options.child, options.onScroll
    local Pool = POOL
    local function MaxScroll()
        if childFrame then
            return math.max(0, childFrame:GetHeight() - scrollFrame:GetHeight())
        end
        return CludesUI.SafeScrollRange(scrollFrame)
    end
    local UpdateThumb = function() end
    local rail, knob
    if options.thumb ~= false then
        local wid, thumbMin, tp =
            options.width or 4, options.thumbMin or 30, options.trackParent or scrollFrame
        local topY = options.topInset or 4
        rail = Pool.CreateFrame("Frame", nil, tp)
        rail:SetWidth(wid)
        rail:SetPoint("TOPRIGHT", tp, "TOPRIGHT", -(options.rightInset or 2), -topY)
        rail:SetPoint(
            "BOTTOMRIGHT",
            tp,
            "BOTTOMRIGHT",
            -(options.rightInset or 2),
            options.bottomInset or topY
        )
        rail:SetFrameLevel(tp:GetFrameLevel() + (options.level or 2))
        rail:Hide()
        SolidTex(rail, "BACKGROUND", 1, 1, 1, options.trackAlpha or 0.02):SetAllPoints()
        knob = Pool.CreateFrame("Button", nil, rail)
        knob:SetWidth(wid)
        knob:SetFrameLevel(rail:GetFrameLevel() + 1)
        knob:EnableMouse(true)
        knob:RegisterForDrag("LeftButton")
        knob:SetScript("OnDragStart", function() end)
        knob:SetScript("OnDragStop", function() end)
        SolidTex(knob, "ARTWORK", 1, 1, 1, options.thumbAlpha or 0.27):SetAllPoints()
        -- Controller cursor: a drag-only control, never a stop.
        CludesUI.PadHint(knob, "nodeignore")
        UpdateThumb = function()
            local scrollMax = MaxScroll()
            if scrollMax <= 0 then
                rail:Hide()
                return
            end
            rail:Show()
            local trackH = rail:GetHeight()
            local visH = scrollFrame:GetHeight()
            local thumbH = math.max(thumbMin, trackH * (visH / (visH + scrollMax)))
            knob:SetHeight(thumbH)
            -- Guarded read: the preview scroll frames can return a secret value.
            local cur = 0
            local success, val = pcall(scrollFrame.GetVerticalScroll, scrollFrame)
            if success and val then
                local secondOk, n = pcall(tonumber, val)
                if secondOk and n then
                    cur = n
                end
            end
            knob:ClearAllPoints()
            knob:SetPoint("TOP", rail, "TOP", 0, -(cur / scrollMax * (trackH - thumbH)))
        end
    end

    local goal, smoothing = 0, false
    -- The smoothing frame is owned by the scroll frame on a pool host (shown only
    -- while it lerps, as always).
    local smoother
    if Pool.Gen and Pool.Gen(scrollFrame) then
        smoother = Pool.Owned(scrollFrame, "smooth", "Frame", scrollFrame)
    else
        smoother = CreateFrame("Frame", nil, scrollFrame)
    end
    smoother:Hide()
    local function Stop()
        smoothing = false
        smoother:Hide()
    end
    local function Set(v)
        scrollFrame:SetVerticalScroll(v)
        UpdateThumb()
        if onScroll then
            onScroll(v)
        end
    end
    smoother:SetScript("OnUpdate", function(_, elapsed)
        local cur = scrollFrame:GetVerticalScroll()
        local scrollMax = MaxScroll()
        goal = math.max(0, math.min(scrollMax, goal))
        local diff = goal - cur
        if math.abs(diff) < 0.3 then
            Stop()
            Set(goal)
            return
        end
        Set(math.max(0, math.min(scrollMax, cur + diff * math.min(1, 12 * elapsed))))
    end)
    scrollFrame:EnableMouseWheel(true)
    local panelWheel, passWheel = options.panelWheel, options.passWheel
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        if panelWheel and CludesUI._ShiftWheelScale(delta) then
            return
        end
        local scrollMax = MaxScroll()
        if scrollMax <= 0 then
            local page = passWheel and CludesUI._scrollFrame
            local func = page and page:GetScript("OnMouseWheel")
            if func then
                func(page, delta)
            end
            return
        end
        local base = smoothing and goal or self:GetVerticalScroll()
        goal = math.max(0, math.min(scrollMax, base - delta * step))
        if not smoothing then
            smoothing = true
            smoother:Show()
        end
    end)

    local function ScrollTo(v)
        Stop()
        goal = math.max(0, math.min(MaxScroll(), v))
        Set(goal)
    end
    if not knob then
        return UpdateThumb, ScrollTo
    end
    scrollFrame:SetScript("OnScrollRangeChanged", function()
        UpdateThumb()
    end)

    -- Controller cursor: it scrolls the frame itself to reach a control, so the
    -- thumb follows (the lerp and a thumb drag already paint their own frames).
    if CludesUI.PadCP() then
        scrollFrame:HookScript("OnVerticalScroll", function()
            if not smoothing and not knob:GetScript("OnUpdate") then
                UpdateThumb()
            end
        end)
    end

    -- Controller (no mouse wheel): step arrows and a page strip on the bar, built
    -- and shown only when a controller is in use as the bar appears.
    local padSequence
    local function PadScrollBy(delta)
        local scrollMax = MaxScroll()
        if scrollMax <= 0 then
            return
        end
        local base = smoothing and goal or scrollFrame:GetVerticalScroll()
        goal = math.max(0, math.min(scrollMax, base + delta))
        if not smoothing then
            smoothing = true
            smoother:Show()
        end
    end
    local function PadArrow(anchorPoint, glyph, delta)
        local b = Pool.CreateFrame("Button", nil, padSequence)
        b:SetSize(rail:GetWidth() + 10, 14)
        b:SetPoint(anchorPoint, rail, anchorPoint, 0, 0)
        b:SetFrameLevel(rail:GetFrameLevel() + 1)
        SolidTex(b, "BACKGROUND", 0, 0, 0, 0.6):SetAllPoints()
        local texture = b:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(ICONS_PATH .. glyph)
        texture:SetSize(14, 14)
        texture:SetPoint("CENTER")
        texture:SetAlpha(0.6)
        b:SetScript("OnEnter", function()
            texture:SetAlpha(1)
        end)
        b:SetScript("OnLeave", function()
            texture:SetAlpha(0.6)
        end)
        b:SetScript("OnClick", function()
            PadScrollBy(delta)
        end)
    end
    rail:HookScript("OnShow", function()
        if not CludesUI.PadInUse() then
            if padSequence then
                padSequence:Hide()
            end
            return
        end
        if not padSequence then
            padSequence = Pool.CreateFrame("Frame", nil, rail)
            padSequence:SetAllPoints(rail)
            padSequence:SetFrameLevel(rail:GetFrameLevel())
            -- Page strip under the thumb: a click pages toward the pointer.
            local strip = Pool.CreateFrame("Button", nil, padSequence)
            strip:SetPoint("TOPLEFT", rail, "TOPLEFT", -5, 0)
            strip:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 5, 0)
            strip:SetFrameLevel(rail:GetFrameLevel())
            strip:SetScript("OnClick", function()
                local _, ty = knob:GetCenter()
                if not ty then
                    return
                end
                local _, curY = GetCursorPosition()
                local amount = scrollFrame:GetHeight() * 0.9
                PadScrollBy((curY / knob:GetEffectiveScale() > ty) and -amount or amount)
            end)
            -- The controller cursor cannot aim a page click: its stops are the arrows.
            CludesUI.PadHint(strip, "nodeignore")
            PadArrow("TOP", "cui-arrow-up3.png", -step)
            PadArrow("BOTTOM", "cui-arrow-down3.png", step)
            -- The thumb stays grabbable over the arrows; at either end it only
            -- covers the arrow that cannot scroll further.
            knob:SetFrameLevel(rail:GetFrameLevel() + 2)
        end
        padSequence:Show()
    end)

    knob:SetScript("OnMouseDown", function(self, btnFrame)
        if btnFrame ~= "LeftButton" then
            return
        end
        Stop()
        local _, curY = GetCursorPosition()
        local startY = curY / self:GetEffectiveScale()
        local startScroll = scrollFrame:GetVerticalScroll()
        self:SetScript("OnUpdate", function(self2)
            if not IsMouseButtonDown("LeftButton") then
                self2:SetScript("OnUpdate", nil)
                return
            end
            Stop()
            local _, cy2 = GetCursorPosition()
            local maxTravel = rail:GetHeight() - self2:GetHeight()
            if maxTravel <= 0 then
                return
            end
            local scrollMax = MaxScroll()
            goal = math.max(
                0,
                math.min(
                    scrollMax,
                    startScroll + ((startY - cy2 / self2:GetEffectiveScale()) / maxTravel) * scrollMax
                )
            )
            Set(goal)
        end)
    end)
    knob:SetScript("OnMouseUp", function(self, btnFrame)
        if btnFrame == "LeftButton" then
            self:SetScript("OnUpdate", nil)
        end
    end)
    return UpdateThumb, ScrollTo
end

-- Utility functions
CludesUI.SolidTex = SolidTex
CludesUI.MakeFont = MakeFont
CludesUI.MakeBorder = MakeBorder
CludesUI.DisablePixelSnap = DisablePixelSnap
CludesUI.RowBg = RowBg
CludesUI.ResetRowCounters = ResetRowCounters
CludesUI.lerp = lerp
CludesUI.MakeDropdownArrow = MakeDropdownArrow
CludesUI.RegAccent = RegAccent

-- Internal references (needed by Widget Factory accent system)
CludesUI.DEFAULT_ACCENT_R = DEFAULT_ACCENT_R
CludesUI.DEFAULT_ACCENT_G = DEFAULT_ACCENT_G
CludesUI.DEFAULT_ACCENT_B = DEFAULT_ACCENT_B
CludesUI._ResolveFactionTheme = ResolveFactionTheme
CludesUI._playerClass = playerClass
CludesUI._accentElements = _accentElements
CludesUI._widgetRefreshList = _widgetRefreshList
CludesUI._rowCounters = rowCounters
CludesUI._STYLE = STYLE
CludesUI._THEME_BG_FILES = THEME_BG_FILES
CludesUI._IS_STANDALONE = IS_STANDALONE

-------------------------------------------------------------------------------
--  MakeUnlockElement  --  shared factory for unlock mode element tables.
--  Required fields in opts:
--    key        (string)   unique element key, e.g. "MainBar", "ERB_Health"
--    label      (string)   human-readable name shown on the mover
--    group      (string)   grouping label in menus, e.g. "Action Bars"
--    order      (number)   sort order (lower = earlier)
--    getFrame   (function) -> frame  returns the movable frame
--    getSize    (function) -> w, h   returns authoritative width, height
--    savePos    (function(key, point, relPoint, x, y))  persist + apply
--    loadPos    (function(key)) -> { point, relPoint, x, y } or nil
--    clearPos   (function(key))  remove saved position
--    applyPos   (function(key))  apply saved position to the live frame
--
--  Optional fields:
--    setWidth   (function(key, w))  set element width and rebuild
--    setHeight  (function(key, h))  set element height and rebuild
--    isHidden   (function(key)) -> bool  true if element is disabled/hidden
--    isAnchored (function(key)) -> bool  true if anchored to another element
--    onLiveMove (function(key))  called after every mover-driven placement of
--               the frame: drag start, each drag frame, drag stop, arrow/cog
--               nudge. Runs before the anchor chain reads the frame's rect.
--    ownsPosition (boolean) the module alone places the frame from its saved
--               position (main chat, whose spot Blizzard's Edit Mode also
--               applies): anchor links never move it and it offers no link,
--               so no link becomes a third owner of the frame (one stored on
--               it is deleted when Unlock Mode opens). Mover drags and nudges
--               still move it and save through savePos
--    getScreenPoint / setScreenPoint (function(key) -> point,
--               function(key, point))  an ownsPosition element that keeps its
--               own screen relation: the cog's Relative to Screen menu reads
--               and picks one of UIParent's nine points through these (CENTER
--               = centered) instead of a screen-edge link. Without them an
--               ownsPosition element offers no Relative to Screen
--    isPositionHeld (function(key)) -> bool  true while something else places
--               the frame (the quest tracker inside Blizzard's managed frame
--               container): outside an unlock session, saved positions and
--               anchor links leave it where it is
--    noSpecLayout (boolean) spec override unlock layouts neither bank nor
--               restore the element: one spot for every spec (the quest
--               tracker, whose spot lives in the shared Edit Mode layout and
--               takes a reload to change)
--    linkedKeys (table)  list of element keys that move with this one
--    noResize   (boolean) true for Blizzard elements that cannot be resized
--    sizeFixedByLook (boolean) the current look fixes the element's size
--               (Blizzard Style unit frames): getSize reports that look's size,
--               not the element's own setting. Stored width/height matches to
--               and from it are kept, and spec layouts never bank that size
--    getSettingSize (function(key) -> w, h)  the size the element's own
--               settings give, whatever the look (read with sizeFixedByLook)
--    getBottomExtra (function(key) -> height)  extra height, in the frame's
--               units, the mover extends BELOW the frame (a boss cast bar,
--               the Blizzard Style cast bar text box)
--    getInsets  (function(key) -> l, r, t, b)  visual insets from the frame's
--               box to the rect the mover outlines (Blizzard Style unit frames;
--               negative reaches outside it: the minimap's square frame)
--    detachedMover (boolean) the frame refuses dependents (it carries a
--               forbidden layout aspect), so the mover takes its screen spot by
--               absolute anchor instead of anchoring to it
--    loadRawPos (function(key)) -> the STORED position table, for an element
--               whose stored form is not the one loadPos reports
--    saveRawPos (function(key, p))  store a table loadRawPos returned. Spec
--               override unlock layers bank and restore positions through this
--               pair when an element gives both (loadPos/savePos otherwise)
--  This table is a WHITELIST: a field left out here never reaches the unlock
--  module, silently.
-------------------------------------------------------------------------------
function CludesUI.MakeUnlockElement(options)
    return {
        key = options.key,
        label = options.label,
        group = options.group,
        order = options.order,
        getFrame = options.getFrame,
        getSize = options.getSize,
        savePosition = options.savePos,
        loadPosition = options.loadPos,
        clearPosition = options.clearPos,
        applyPosition = options.applyPos,
        setWidth = options.setWidth,
        setHeight = options.setHeight,
        isHidden = options.isHidden,
        isAnchored = options.isAnchored,
        onLiveMove = options.onLiveMove,
        ownsPosition = options.ownsPosition,
        getScreenPoint = options.getScreenPoint,
        setScreenPoint = options.setScreenPoint,
        isPositionHeld = options.isPositionHeld,
        noSpecLayout = options.noSpecLayout,
        linkedKeys = options.linkedKeys,
        noResize = options.noResize,
        linkedDimensions = options.linkedDimensions,
        -- noInitHook: self-positioning element; ApplySavedPositions /
        -- NotifyElementResized (CUI_UnlockMode) must not re-apply its stored position.
        noInitHook = options.noInitHook,
        loadRawPosition = options.loadRawPos,
        saveRawPosition = options.saveRawPos,
        noAnchorTarget = options.noAnchorTarget,
        noAnchorTo = options.noAnchorTo,
        -- allowMatchSource: show the width/height MATCH buttons even when resize is
        -- disabled (noResize), so the element can size-match TO another element.
        -- noSizeMatchTarget: other elements may NOT size-match TO this one.
        allowMatchSource = options.allowMatchSource,
        noSizeMatchTarget = options.noSizeMatchTarget,
        sizeFixedByLook = options.sizeFixedByLook,
        getSettingSize = options.getSettingSize,
        -- matchUnavailable: function(key) -> reason string when a NEW width/height match
        -- is impossible (action bars in Blizzard Style, where CUI does not control
        -- sizing). Clearing an existing match stays allowed.
        matchUnavailable = options.matchUnavailable,
        -- keepMoverWhenAnchored: isAnchored() reflecting a module option (ERB "Anchor
        -- To") still gets a mover -- position-locked (no drag/nudge/anchor link), but
        -- resize and width/height matching stay available.
        keepMoverWhenAnchored = options.keepMoverWhenAnchored,
        -- moverBg: optional {r,g,b} tint for the mover background (default: dark overlay).
        -- moverTooltip: optional hover tooltip (string or function) on the mover
        -- (first use: CDM's Additional Bar Offset marker).
        -- subtitle: optional dimmed helper line under the mover label.
        moverBg = options.moverBg,
        moverTooltip = options.moverTooltip,
        subtitle = options.subtitle,
        getBottomExtra = options.getBottomExtra,
        getInsets = options.getInsets,
        -- getMatchPad: function(key) -> padW, padH the element draws OUTSIDE its
        -- own rect (chrome such as a classic resource bar's frame); width/height
        -- matching adds it on the target side and takes it off the source side so
        -- matches line up with what is on screen. nil = nothing outside the rect.
        getMatchPad = options.getMatchPad,
        detachedMover = options.detachedMover,
    }
end

-------------------------------------------------------------------------------
--  Lazy-load stub: ResolveThemeColor -- minimal version for PLAYER_LOGIN, before the
--  Widgets file initializes and replaces it with the full (animated) version.
-------------------------------------------------------------------------------
if not CludesUI.ResolveThemeColor then
    CludesUI.ResolveThemeColor = function(skinName)
        skinName = ResolveFactionTheme(skinName)
        if skinName == "Class Colored" then
            local clr = (CludesUI.GetRawClassColor and CludesUI.GetRawClassColor(playerClass))
                or CLASS_COLOR_MAP[playerClass]
            if clr then
                return clr.r, clr.g, clr.b
            end
            return DEFAULT_ACCENT_R, DEFAULT_ACCENT_G, DEFAULT_ACCENT_B
        elseif skinName == "Custom Color" then
            local sa = CludesUIDB and CludesUIDB.accentColor
            return sa and sa.r or DEFAULT_ACCENT_R,
                sa and sa.g or DEFAULT_ACCENT_G,
                sa and sa.b or DEFAULT_ACCENT_B
        else
            local presetRec = THEME_PRESETS[skinName]
            if presetRec then
                return presetRec.r, presetRec.g, presetRec.b
            end
            return DEFAULT_ACCENT_R, DEFAULT_ACCENT_G, DEFAULT_ACCENT_B
        end
    end
end

-------------------------------------------------------------------------------
--  Load-order stub: GetActiveTheme -- the real one lives in CludesUI_UICore.lua
--  (loads right after this file); covers callers in the rest of THIS file's scope. Identical body, harmlessly replaced.
-------------------------------------------------------------------------------
if not CludesUI.GetActiveTheme then
    CludesUI.GetActiveTheme = function()
        return CludesUIDB and CludesUIDB.activeTheme or CludesUI.DEFAULT_THEME
    end
end

-------------------------------------------------------------------------------
--  Load-order stub: ResolveActiveAccent -- the real one (and its ResolveProfileAccent /
--  GetActiveProfileData helpers) lives in CludesUI_UICore.lua, which loads right after
--  this file; mirrors ResolveProfileAccent's resolution order so the accent matches.
-------------------------------------------------------------------------------
if not CludesUI.ResolveActiveAccent then
    CludesUI.ResolveActiveAccent = function()
        local skinName = (CludesUIDB and CludesUIDB.activeTheme) or CludesUI.DEFAULT_THEME
        local themeR, themeG, themeB = CludesUI.ResolveThemeColor(skinName)
        local saved = CludesUIDB
        local p = saved and saved.profiles and saved.profiles[saved.activeProfile or "Default"]
        local accent = p and p.cuiAccent
        -- 1) per-profile cuiAccent
        if accent and accent.useClass then
            local color = (CludesUI.GetRawClassColor and CludesUI.GetRawClassColor(playerClass))
                or CLASS_COLOR_MAP[playerClass]
            if color then
                return color.r, color.g, color.b
            end
        end
        if accent and accent.custom then
            local ca = accent.custom
            return ca.r or themeR, ca.g or themeG, ca.b or themeB
        end
        -- 2) frozen global root (only when no explicit per-profile cuiAccent)
        if (not accent) and saved and saved.useClassAccentColor then
            local color = (CludesUI.GetRawClassColor and CludesUI.GetRawClassColor(playerClass))
                or CLASS_COLOR_MAP[playerClass]
            if color then
                return color.r, color.g, color.b
            end
        end
        local gca = saved and saved.customAccentColor
        if gca then
            return gca.r or themeR, gca.g or themeG, gca.b or themeB
        end
        -- 3) theme color
        return themeR, themeG, themeB
    end
end

-------------------------------------------------------------------------------
--  SharedMedia helpers
-------------------------------------------------------------------------------

-- Resolve a texture key to a file path; "sm:" keys fall back to LSM:Fetch when missing
-- from the local table (covers a SharedMedia addon loading after our init).
--   texTable  - the addon's local texture lookup (e.g. TBB_TEXTURES)
--   key       - the saved texture key ("sm:Some Pack" or "beautiful")
--   fallback  - path to use if nothing resolves (optional)
function CludesUI.ResolveTexturePath(texTable, entryKey, fallbackValue)
    if not entryKey then
        return fallbackValue
    end
    local filePath = texTable and texTable[entryKey]
    if filePath then
        return filePath
    end
    -- A non-string key is legacy data, not a lookup miss: some settings were boolean toggles
    -- before becoming style dropdowns (showPlayerAbsorb). Callers gate on truthiness, so a
    -- stored `true` reaches the :match below and raises inside unit frame init, aborting the
    -- whole build (white player frame, unopenable tab); treat it as unset. Deliberately AFTER
    -- the direct lookup: the raise is in the :match, so this stays a pure crash fix and can never turn a table hit into a fallback.
    if type(entryKey) ~= "string" then
        return fallbackValue
    end
    local smName = entryKey:match("^sm:(.+)")
    if smName then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local fetched = LSM:Fetch("statusbar", smName)
            if fetched then
                -- Cache it back into the table so future lookups are instant
                if texTable then
                    texTable[entryKey] = fetched
                end
                return fetched
            end
        end
    end
    return fallbackValue
end

-------------------------------------------------------------------------------
--  Append LibSharedMedia-3.0 statusbar textures into a runtime texture table.
--  Signature: AppendSharedMediaTextures(names, order, castBarNames, textures)
--    names        - key -> display-name string table
--    order        - ordered array of keys (receives "---" + SM keys appended)
--    castBarNames - optional secondary names table (may be nil)
--    textures     - key -> texture-path table
--  Safe to call repeatedly; duplicate keys are skipped via the textures guard. Registered
--  tables stay current for the session: one LibSharedMedia_Registered callback appends
--  LATE-registered textures (addons register at varying times) into every consumer's tables, so dropdowns always list ALL SharedMedia.
-------------------------------------------------------------------------------
-- Consumers keyed by their `textures` table identity (dedups repeat calls).
-- On CludesUI (not new file-scope locals): this file is at the local/upvalue cap.
CludesUI._smTexConsumers = CludesUI._smTexConsumers or {}

function CludesUI.AppendSharedMediaTextures(nameList, sequence, castBarNames, textures)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        return
    end

    -- Icon textures some SM packs wrongly register as statusbar (cached once).
    local blockedSet = CludesUI._smTexBlacklist
    if not blockedSet then
        blockedSet = { play_icon = true, stop_icon = true, user_icon = true, users_icon = true }
        CludesUI._smTexBlacklist = blockedSet
    end

    -- Append one SM texture (by LSM name) into a consumer's tables if absent; the "---"
    -- separator is added once, lazily, before the first SM key. Defined here (not file scope) and captured as an upvalue by the once-installed registration callback.
    local function AppendOne(c, label, filePath)
        if not filePath then
            return
        end
        local entryKey = "sm:" .. label
        if c.textures[entryKey] or blockedSet[label] then
            return
        end
        -- Drop only an exact duplicate: a native entry with the SAME display
        -- name AND the same file would otherwise list that texture twice,
        -- once in the module's own section and once in the SharedMedia tail.
        local nativePath = c.nativeNames and c.nativeNames[string.lower(label)]
        if nativePath and nativePath == filePath then
            return
        end
        if not c.sepAdded then
            c.order[#c.order + 1] = "---"
            c.sepAdded = true
        end
        c.textures[entryKey] = filePath
        c.names[entryKey] = label
        c.order[#c.order + 1] = entryKey
        if c.castBarNames then
            c.castBarNames[entryKey] = label
        end
    end

    -- Register this consumer (dedup by textures-table identity); sepAdded stays false so the first SM key adds exactly one "---" (the dedup guard prevents a second).
    local c = CludesUI._smTexConsumers[textures]
    if not c then
        -- The consumer's own display-name -> file pairs at registration (its
        -- module-side list is complete by then; SM keys are not in it yet),
        -- for the exact-duplicate test above. Keyed by NAME, not by file
        -- alone: several modules point an entry of their own at a file the
        -- library also ships under a different name -- Raid Frames calls the
        -- blank texture "None" where the library calls it "Solid" -- and
        -- matching on the file alone would swallow the library's entry and
        -- leave the user unable to find that texture by name.
        local native = {}
        for k, filePath in pairs(textures) do
            local nm = nameList and nameList[k]
            if nm then
                native[string.lower(nm)] = filePath
            end
        end
        c = {
            names = nameList,
            order = sequence,
            castBarNames = castBarNames,
            textures = textures,
            nativeNames = native,
        }
        CludesUI._smTexConsumers[textures] = c
    end

    -- Sync all currently-registered SM textures (sorted alphabetically; late ones arriving via the callback append after, in registration order).
    local smTextures = LSM:HashTable("statusbar")
    if smTextures then
        local ordered = {}
        for label in pairs(smTextures) do
            local entryKey = "sm:" .. label
            if not textures[entryKey] and not blockedSet[label] then
                ordered[#ordered + 1] = label
            end
        end
        if #ordered > 0 then
            table.sort(ordered)
            for _, label in ipairs(ordered) do
                AppendOne(c, label, smTextures[label])
            end
        end
    end

    -- Install the late-registration callback once, with a DEDICATED owner: same owner + event would replace the font LibSharedMedia_Registered callback in CallbackHandler.
    if not CludesUI._smTexCallbackInstalled then
        CludesUI._smTexCallbackInstalled = true
        CludesUI._smTexCBOwner = CludesUI._smTexCBOwner or {}
        LSM.RegisterCallback(CludesUI._smTexCBOwner, "LibSharedMedia_Registered", function(_, mediatype, entryKey)
            if mediatype ~= "statusbar" then
                return
            end
            local filePath = LSM:Fetch("statusbar", entryKey)
            if not filePath then
                return
            end
            for _, cc in pairs(CludesUI._smTexConsumers) do
                AppendOne(cc, entryKey, filePath)
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Append LibSharedMedia-3.0 sounds into a runtime sound dropdown table.
--  Signature: AppendSharedMediaSounds(paths, names, order)
--    paths   - key -> sound file path table
--    names   - key -> display name string table
--    order   - ordered array of keys (receives "---" + SM keys appended)
--  Safe to call repeatedly; duplicate keys are skipped via the paths guard.
-------------------------------------------------------------------------------
function CludesUI.AppendSharedMediaSounds(paths, nameList, sequence)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        return
    end
    local smSounds = LSM:HashTable("sound")
    if not smSounds then
        return
    end

    local ordered = {}
    for label in pairs(smSounds) do
        local entryKey = "sm:" .. label
        if not paths[entryKey] then
            ordered[#ordered + 1] = label
        end
    end
    if #ordered == 0 then
        return
    end
    table.sort(ordered)

    sequence[#sequence + 1] = "---"
    for _, label in ipairs(ordered) do
        local entryKey = "sm:" .. label
        paths[entryKey] = smSounds[label]
        nameList[entryKey] = label
        sequence[#sequence + 1] = entryKey
    end
end

-------------------------------------------------------------------------------
--  Append LibSharedMedia-3.0 fonts into a runtime font dropdown table.
--  Signature: AppendSharedMediaFonts(values, order, opts)
--    values  - key -> { text, font } table (or key -> path when keyByName=true)
--    order   - ordered array of keys
--    opts    - optional { keyByName = true } -- use display name as key
--  Safe to call multiple times; duplicate keys are skipped.
-------------------------------------------------------------------------------
function CludesUI.AppendSharedMediaFonts(values, sequence, options)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        return
    end
    local mediaFonts = LSM:HashTable("font")
    if not mediaFonts then
        return
    end

    -- Build the SM font path lookup so ResolveFontName can find SM fonts
    if not CludesUI._smFontPaths then
        CludesUI._smFontPaths = {}
    end
    for label, filePath in pairs(mediaFonts) do
        CludesUI._smFontPaths[label] = filePath
    end

    local keyByName = options and options.keyByName
    local ordered = {}
    for label in pairs(mediaFonts) do
        local entryKey = keyByName and label or ("smf:" .. label)
        if not values[entryKey] then
            ordered[#ordered + 1] = label
        end
    end
    if #ordered == 0 then
        return
    end
    table.sort(ordered)

    sequence[#sequence + 1] = "---"
    for _, label in ipairs(ordered) do
        local entryKey = keyByName and label or ("smf:" .. label)
        values[entryKey] = { text = label, font = mediaFonts[label] }
        sequence[#sequence + 1] = entryKey
    end
end

-- Append only EXTERNAL SharedMedia fonts (not bundled with CludesUI) to a dropdown
-- values/order pair, for glyph-restricted locales where bundled Latin fonts cannot render the
-- script: only user-installed SM fonts are offered, alongside System Default (bundled names are skipped -- LSM-registered too, but they would just show boxes).
function CludesUI.AppendExternalSharedMediaFonts(values, sequence)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        return
    end
    local mediaFonts = LSM:HashTable("font")
    if not mediaFonts then
        return
    end
    if not CludesUI._smFontPaths then
        CludesUI._smFontPaths = {}
    end
    local ordered = {}
    for label, filePath in pairs(mediaFonts) do
        CludesUI._smFontPaths[label] = filePath
        if not CludesUI.FONT_FILES[label] and not CludesUI.FONT_BLIZZARD[label] and not values[label] then
            ordered[#ordered + 1] = label
        end
    end
    if #ordered == 0 then
        return
    end
    table.sort(ordered)
    sequence[#sequence + 1] = "---"
    for _, label in ipairs(ordered) do
        values[label] = { text = label, font = mediaFonts[label] }
        sequence[#sequence + 1] = label
    end
end

-------------------------------------------------------------------------------
--  Deferred file initialization -- Heavy UI files (Widgets, UnlockMode, Options)
--  register init functions here at load but do not execute until the panel opens.
--  The options surface itself (Widgets + every *_Options.lua) lives in the
--  LoadOnDemand CludesUIOptions addon: nothing of it is even PARSED until
--  EnsureLoaded loads the addon on first panel open.
-------------------------------------------------------------------------------
CludesUI._deferredInits = {}
CludesUI._deferredLoaded = false

-- Module-namespace registry: every child addon publishes its private ns here at
-- load. The LOD options files (which get CludesUIOptions' own useless vararg
-- ns) resolve their module's real ns from this table, and early-return when the
-- module is absent/disabled -- reproducing the old "disabled child = no options
-- page" behavior exactly.
CludesUI._ModuleNS = {}
if IS_STANDALONE then
    -- Every core file has loaded by the first module publish: remove the
    -- hand-off slot before the shared table is published (see the top).
    local sharedMedia = select(2, ...)
    setmetatable(CludesUI._ModuleNS, {
        __newindex = function(t, key, v)
            sharedMedia.__cuiCoreNS = nil
            setmetatable(t, nil)
            rawset(t, key, v)
        end,
    })
end

-- Login-critical deferred body: UnlockMode's position/anchor engine
-- (_applySavedPositions, width/height matches, anchor propagation). It must run
-- at PLAYER_LOGIN / CDM setup WITHOUT loading the options addon, or the
-- LoadOnDemand split's login win evaporates -- so it lives in its own slot, not
-- _deferredInits. One-shot; EnsureLoaded also drains it (panel paths need it too).
CludesUI._unlockCoreInit = nil

function CludesUI:EnsureUnlockCore()
    local func = self._unlockCoreInit
    if func then
        self._unlockCoreInit = nil
        func()
    end
end

-- Loads the LoadOnDemand options surface. False (with a user-facing message)
-- only when the CludesUIOptions addon is missing or disabled in the AddOn List.
function CludesUI.EnsureOptionsLoaded()
    -- Standalone builds bundle the options files FLAT into the one addon --
    -- they are resident from startup, and the LoadOnDemand addon named below
    -- does not exist there under any name (the rename would point this at a
    -- nonexistent "<coreToken>Options", printing MISSING and dead-ending every
    -- options open). Loaded is simply true; EnsureLoaded's deferred-init drain
    -- does the rest, exactly like the pre-split resident options.
    if IS_STANDALONE then
        return true
    end
    if C_AddOns.IsAddOnLoaded("CludesUIOptions") then
        return true
    end
    -- Inside the suite registration window: the options files register the
    -- suite's module pages while they load (see RegisterModule).
    local success, reason = CUI_NS.RunCoreRegistration(C_AddOns.LoadAddOn, "CludesUIOptions")
    if not success then
        CludesUI.PrintError(
            "Options could not load ("
                .. tostring(reason)
                .. '). Enable the "CludesUI Options" addon in the AddOn List.'
        )
    end
    return success and true or false
end

-- The options LOD split moved the child modules' slash registrations into
-- CludesUIOptions, where they cannot exist until the panel first loads.
-- Register a self-replacing bootstrap for each at login: it refuses in
-- combat (matching the real handlers, and keeping LoadAddOn out of combat),
-- loads the options addon -- whose re-fired init installs the REAL handler
-- over this one -- then re-dispatches, so subcommands like "/crf reset"
-- behave exactly as before the split. A real handler that never installs
-- (child module disabled) leaves the command a silent no-op, matching the
-- pre-split not-loaded behavior.
do
    local LOD_SLASH = {
        { key = "EABR", "/cabr", "/cbr" },
        { key = "EBSK", "/cbsk" },
        { key = "ECMEOPT", "/ccmeopt" },
        { key = "EFR", "/cfr" },
        { key = "EMM", "/cmm" },
        { key = "CLUDESNAMEPLATES", "/cnp" },
        { key = "EQOL", "/qol" },
        { key = "EQTOPTS", "/cqtopts" },
        { key = "CUIQUICKDRAW", "/cqd", "/quickdraw" },
        { key = "CLUDESRAIDFRAMES", "/crf" },
        { key = "ERBOPT", "/crbopt" },
        { key = "CLUDESUNITFRAMES", "/cuf" },
        { key = "CLUDESDATABARS", "/cdb" },
    }
    for _, entry in ipairs(LOD_SLASH) do
        local entryKey = entry.key
        for i = 1, #entry do
            _G["SLASH_" .. entryKey .. i] = entry[i]
        end
        local function bootstrap(message)
            if InCombatLockdown() then
                print("Cannot open options in combat")
                return
            end
            -- Deferred one tick: slash dispatch runs inside the chat edit
            -- box's script execution, and first-open work (options addon
            -- load + full panel build) can exceed that execution's watchdog
            -- budget ("script ran too long"). A fresh timer execution owns
            -- its own budget.
            C_Timer.After(0, function()
                if InCombatLockdown() then
                    return
                end
                if not CludesUI.EnsureOptionsLoaded() then
                    return
                end
                local real = SlashCmdList[entryKey]
                if real and real ~= bootstrap then
                    real(message)
                end
            end)
        end
        SlashCmdList[entryKey] = bootstrap
    end
end

function CludesUI:EnsureLoaded()
    if self._deferredLoaded then
        return
    end
    -- Unlock core first (position/anchor engine), matching the pre-split order
    -- where UnlockMode's deferred body ran before Widgets'.
    self:EnsureUnlockCore()
    -- Load the options addon: its files append their deferred inits, which the
    -- loop below then runs. On failure keep _deferredLoaded false so a later
    -- open retries after the user re-enables the addon.
    if not CludesUI.EnsureOptionsLoaded() then
        return
    end
    self._deferredLoaded = true
    -- The page pool came with the options addon (CludesUI_FramePool.lua), which
    -- filled the core's own pool table: the panel's page path calls these captured
    -- functions, never the public slot.
    local Pool = POOL
    if Pool.Kept then
        CUI_NS.PoolKept, CUI_NS.PoolCreateFrame = Pool.Kept, Pool.CreateFrame
        CUI_NS.PoolIsIdle, CUI_NS.PoolGen, CUI_NS.PoolDevEndPass = Pool.IsIdle, Pool.Gen, Pool._DevEndPass
        CUI_NS.PoolManaged, CUI_NS.PoolPin = Pool.Managed, Pool.Pin
    end
    -- Deferred inits run inside the suite registration window: some options
    -- files register their module page from here (e.g. Party Mode).
    for i, func in ipairs(self._deferredInits) do
        CUI_NS.RunCoreRegistration(func)
        self._deferredInits[i] = nil
    end
end

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
CludesUI.VERSION = "1.1.3"

-- Register this addon's version into a shared global table (taint-free at load time)
if not _G._CUI_AddonVersions then
    _G._CUI_AddonVersions = {}
end
_G._CUI_AddonVersions[CUI_HOST_ADDON] = CludesUI.VERSION

-- Version-increase detection: stamp the account's last-seen version at login
-- and raise the Patch Notes reminder dot when it changed. The dot clears
-- when the Patch Notes row is clicked and stays cleared until the NEXT
-- version change. First-ever login (no prior stamp) never raises it.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if not CludesUIDB then
            CludesUIDB = {}
        end
        local prev = CludesUIDB.lastLoginVersion
        if prev and prev ~= CludesUI.VERSION then
            CludesUIDB.patchDotPending = true
        end
        CludesUIDB.lastLoginVersion = CludesUI.VERSION
        if CludesUI._UpdatePatchDot then
            CludesUI._UpdatePatchDot()
        end
    end)
end

-- Version mismatch check (shared across all Cludes addons)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if _G._CUI_VersionChecked then
            return
        end
        _G._CUI_VersionChecked = true
        C_Timer.After(2, function()
            local versions = _G._CUI_AddonVersions
            if not versions then
                return
            end
            local isLoaded = {}
            for label, ver in pairs(versions) do
                isLoaded[#isLoaded + 1] = { name = label, version = ver }
            end
            if #isLoaded < 2 then
                return
            end
            local newest = isLoaded[1].version
            for i = 2, #isLoaded do
                if isLoaded[i].version > newest then
                    newest = isLoaded[i].version
                end
            end
            local outdated = {}
            for _, details in ipairs(isLoaded) do
                if details.version ~= newest then
                    outdated[#outdated + 1] = details.name
                end
            end
            if #outdated == 0 then
                return
            end
            local message = "The following CludesUI addons are out of date. "
                .. "Please update so all addons are the same version:\n\n"
                .. table.concat(outdated, ", ")
            CludesUI:ShowConfirmPopup({
                title = "Out of Date",
                message = message,
                confirmText = "OK",
            })
        end)
    end)
end

--------------------------------------------------------------------------------
--  Global Incompatible Addon Detection -- runs once per session. Non-ElvUI conflicts always
--  show. ElvUI is a one-off warning: once dismissed while it is the ONLY conflict, it is
--  suppressed forever; if other conflicts are also present, ElvUI shows too and the one-off flag is not consumed.
--------------------------------------------------------------------------------
-- Conflict check is wrapped in a function so the first-install popup (CludesUI_FirstInstall.lua)
-- can defer it until after the user picks their initial addon list. The inline scheduler at the
-- bottom of this block only runs it automatically if the first-install popup has already been shown in a prior session.
CludesUI._RunConflictCheck = function()
    if _G._CUI_ConflictCheckRan then
        return
    end
    _G._CUI_ConflictCheckRan = true
    do
        local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        if not IsLoaded then
            return
        end

        -- conflict list: { addon, label, targets, message, moduleCheck }
        --   targets = "all" or a table of Cludes folder names
        --   message = optional custom popup message override
        --   moduleCheck = optional function returning true while the conflict applies: an
        --     CludesUI sub-feature is on (HoverCast, the Mythic+ Timer, the Character Sheet
        --     skin), or a clashing option is on in the other addon
        -- Blizzard UI Enhanced has sub-features stored as flags on CludesUIDB; conflicts against a specific sub-feature only fire when that feature is actually enabled.
        local function BlizzardSkinSubEnabled(entryKey)
            if not CludesUIDB then
                return true
            end
            return CludesUIDB[entryKey] ~= false
        end
        -- Another Mythic+ timer addon only clashes with the Mythic+ Timer window,
        -- so it is named only while that window is on, and the message points at
        -- its switch (the rest of Mythic+ Tools keeps running beside it).
        local function MPlusTimerOn()
            return _G._CUMT_IsTimerEnabled and _G._CUMT_IsTimerEnabled()
        end
        local function MPlusTimerMsg(labelText)
            return CludesUI.Lf(
                "%1$s conflicts with CludesUI's Mythic+ Timer. Turn off Enable Mythic+ Timer on the Mythic+ Timer tab of Mythic+ Tools, or disable %1$s.",
                labelText
            )
        end
        -- Leatrix Plus only clashes through these options (LeaPlusDB holds "On"/"Off"),
        -- so it is named only while one is on for a loaded module, and the popup lists them.
        local function LeatrixOptionsOn()
            local saved = _G.LeaPlusDB
            if type(saved) ~= "table" then
                return nil
            end
            local enabled = {}
            for _, o in ipairs({
                { "CludesUIChat", "UseEasyChatResizing", "Use easy resizing" },
                { "CludesUIChat", "NoCombatLogTab", "Hide the combat log" },
                { "CludesUIChat", "NoChatButtons", "Hide chat buttons" },
                { "CludesUIChat", "UnclampChat", "Unclamp chat frame" },
                { "CludesUIChat", "MoveChatEditBoxToTop", "Move editbox to top" },
                { "CludesUIChat", "NoStickyChat", "Disable sticky chat" },
                { "CludesUIChat", "UseArrowKeysInChat", "Use arrow keys in chat" },
                { "CludesUIChat", "NoChatFade", "Disable chat fade" },
                { "CludesUIChat", "RecentChatWindow", "Recent chat window" },
                { "CludesUIChat", "RestoreChatMessages", "Restore chat messages" },
                { "CludesUIMinimap", "MinimapModder", "Enhance minimap" },
            }) do
                if saved[o[2]] == "On" and IsLoaded(o[1]) then
                    enabled[#enabled + 1] = o[3]
                end
            end
            return #enabled > 0 and table.concat(enabled, ", ") or nil
        end
        local leatrixOn = LeatrixOptionsOn()
        local conflicts = {
            {
                addon = "ElvUI",
                label = "ElvUI",
                targets = "all",
                message = "Many of ElvUI's modules are incompatible with CludesUI. Make sure to disable any conflicting modules.",
            },
            {
                addon = "DandersFrames",
                label = "Danders Frames",
                targets = { "CludesUIRaidFrames" },
            },
            {
                addon = "HarreksAdvancedRaidFrames",
                label = "Harreks Advanced Raid Frames",
                targets = { "CludesUIRaidFrames" },
            },
            {
                addon = "Grid2",
                label = "Grid2",
                targets = { "CludesUIRaidFrames" },
            },
            -- Clique is special: it only conflicts when Raid Frames is enabled AND
            -- HoverCast (click-casting) is turned on -- with HoverCast off, Clique
            -- coexists fine (it owns the frames). targets handles the RF-enabled
            -- check; moduleCheck adds the HoverCast-enabled check.
            {
                addon = "Clique",
                label = "Clique",
                targets = { "CludesUIRaidFrames" },
                moduleCheck = function()
                    return _G._CURF_IsHoverCastEnabled and _G._CURF_IsHoverCastEnabled()
                end,
                message = "Clique controls click-casting on the same Raid & Party Frames as CludesUI's Frame Bindings, so they conflict. Disable the Clique addon to use Frame Bindings.",
            },
            {
                addon = "TellMeWhen",
                label = "TellMeWhen",
                targets = "all",
                message = "TellMeWhen overlaps with CludesUI's core positional architecture. If you ONLY use for sound alerts it should be okay but may still cause issues.",
            },
            {
                addon = "Bartender4",
                label = "Bartender4",
                targets = { "CludesUIActionBars" },
            },
            {
                addon = "Dominos",
                label = "Dominos",
                targets = { "CludesUIActionBars" },
            },
            {
                addon = "ImprovedTalentLoadouts",
                label = "Improved Talent Loadouts",
                targets = { "CludesUIActionBars" },
            },
            {
                addon = "UnhaltedUnitFrames",
                label = "Unhalted Unit Frames",
                targets = { "CludesUIUnitFrames" },
            },
            {
                addon = "Platynator",
                label = "Platynator",
                targets = { "CludesUINameplates" },
            },
            {
                addon = "Plater",
                label = "Plater Nameplates",
                targets = { "CludesUINameplates" },
            },
            {
                addon = "Kui_Nameplates",
                label = "KUI Nameplates",
                targets = { "CludesUINameplates" },
            },
            {
                addon = "TidyPlates",
                label = "TidyPlates",
                targets = { "CludesUINameplates" },
            },
            {
                addon = "TidyPlates_ThreatPlates",
                label = "TidyPlates ThreatPlates",
                targets = { "CludesUINameplates" },
            },
            {
                addon = "Healers-Have-To-Die",
                label = "Healers Have To Die",
                targets = { "CludesUINameplates" },
            },
            {
                addon = "Aloft",
                label = "Aloft",
                targets = { "CludesUINameplates" },
            },
            {
                addon = "SenseiClassResourceBar",
                label = "Sensei Class Resource Bar",
                targets = { "CludesUIResourceBars" },
            },
            {
                addon = "EditModeExpanded",
                label = "Edit Mode Expanded",
                targets = { "CludesUIQuestTracker", "CludesUIChat" },
            },
            {
                addon = "SexyMap",
                label = "SexyMap",
                targets = { "CludesUIMinimap" },
            },
            {
                addon = "MinimapButtonButton",
                label = "MinimapButtonButton",
                targets = { "CludesUIMinimap" },
            },
            {
                addon = "Leatrix_Plus",
                label = "Leatrix",
                targets = { "CludesUIChat", "CludesUIMinimap" },
                moduleCheck = function()
                    return leatrixOn ~= nil
                end,
                message = CludesUI.L(
                    "Leatrix Plus has chat and minimap features that conflict with CludesUI. Disable any chat or minimap related options within Leatrix Plus to stay compatible."
                )
                    .. "\n"
                    .. CludesUI.L("Leatrix Plus options that are on:")
                    .. " "
                    .. (leatrixOn or ""),
            },
            {
                addon = "Prat-3.0",
                label = "Prat",
                targets = { "CludesUIChat" },
            },
            {
                addon = "Chatter",
                label = "Chatter",
                targets = { "CludesUIChat" },
            },
            {
                addon = "Chattynator",
                label = "Chattynator",
                targets = { "CludesUIChat" },
            },
            {
                addon = "Glass",
                label = "Glass",
                targets = { "CludesUIChat" },
            },
            {
                addon = "AdiBags",
                label = "AdiBags",
                targets = { "CludesUIBags" },
            },
            {
                addon = "ArkInventory",
                label = "ArkInventory",
                targets = { "CludesUIBags" },
            },
            {
                addon = "Baganator",
                label = "Baganator",
                targets = { "CludesUIBags" },
            },
            {
                addon = "Bagnon",
                label = "Bagnon",
                targets = { "CludesUIBags" },
            },
            {
                addon = "BetterBags",
                label = "BetterBags",
                targets = { "CludesUIBags" },
            },
            {
                addon = "Sorted",
                label = "Sorted",
                targets = { "CludesUIBags" },
            },
            {
                addon = "UltimateMouseCursor",
                label = "Ultimate Mouse Cursor",
                targets = { "CludesUIQoL" },
            },
            {
                addon = "BetterCooldownManager",
                label = "Better Cooldown Manager",
                targets = { "CludesUICooldownManager", "CludesUIResourceBars" },
            },
            {
                addon = "CooldownManagerCentered",
                label = "Cooldown Manager Centered",
                targets = { "CludesUICooldownManager" },
            },
            {
                addon = "SkironCooldownManager",
                label = "Skiron Cooldown Manager",
                targets = { "CludesUICooldownManager" },
            },
            {
                addon = "ArcUI",
                label = "ArcUI",
                targets = { "CludesUICooldownManager" },
            },
            {
                addon = "Ayije_CDM",
                label = "Ayije CDM",
                targets = { "CludesUICooldownManager", "CludesUIResourceBars" },
            },
            {
                addon = "MythicPlusTimer",
                label = "Mythic Plus Timer",
                targets = { "CludesUIMythicTimer" },
                moduleCheck = MPlusTimerOn,
                message = MPlusTimerMsg("Mythic Plus Timer"),
            },
            {
                addon = "WarpDeplete",
                label = "WarpDeplete",
                targets = { "CludesUIMythicTimer" },
                moduleCheck = MPlusTimerOn,
                message = MPlusTimerMsg("WarpDeplete"),
            },
            {
                addon = "MPlusTimer",
                label = "MPlusTimer",
                targets = { "CludesUIMythicTimer" },
                moduleCheck = MPlusTimerOn,
                message = MPlusTimerMsg("MPlusTimer"),
            },
            {
                addon = "ChonkyCharacterSheet",
                label = "Chonky Character Sheet",
                targets = { "CludesUIBlizzardSkin" },
                moduleCheck = function()
                    return BlizzardSkinSubEnabled("themedCharacterSheet")
                end,
                message = "Chonky Character Sheet conflicts with the CludesUI's Character Sheet. Disable either Chonky or the Character Sheet skin in Blizzard UI Enhanced settings.",
            },
            {
                addon = "DejaCharacterStats",
                label = "Deja Character Stats",
                targets = { "CludesUIBlizzardSkin" },
                moduleCheck = function()
                    return BlizzardSkinSubEnabled("themedCharacterSheet")
                end,
                message = "Deja Character Stats conflicts with the CludesUI's Character Sheet. Disable either Deja or the Character Sheet skin in Blizzard UI Enhanced settings.",
            },
            {
                addon = "BetterCharacterPanel",
                label = "Better Character Panel",
                targets = { "CludesUIBlizzardSkin" },
                moduleCheck = function()
                    return BlizzardSkinSubEnabled("themedCharacterSheet")
                end,
                message = "Better Character Panel conflicts with the CludesUI's Character Sheet. Disable either Better Character Panel or the Character Sheet skin in Blizzard UI Enhanced settings.",
            },
            {
                addon = "idTip",
                label = "idTip",
                targets = "all",
                message = "idTip conflicts with CludesUI's tooltip systems. Disable the idTip addon to stay compatible.",
            },
            -- The suite this one shares its frames with: both running at once
            -- fight over the same parts of the interface.
            {
                addon = "Elles" .. "mereUI",
                label = "Elles" .. "mereUI",
                targets = "all",
                message = ("Elles" .. "mereUI")
                    .. " and CludesUI change the same parts of the interface and cannot run together. Disable one of them in the AddOn list, then reload.",
            },
            -- The same author's older single-purpose addons, and the old name of
            -- the DataBars addon: each still draws what one of our modules draws.
            {
                addon = "Elles" .. "mereUIWonderBar",
                label = "Elles" .. "mereUI WonderBar",
                targets = { "CludesUIDataBars" },
            },
            {
                addon = "Elles" .. "mereBarGlows",
                label = "Elles" .. "mere's CDM Bar Glows",
                targets = "all",
            },
            {
                addon = "Elles" .. "mereNameplates",
                label = "Elles" .. "mere's Nameplates",
                targets = "all",
            },
            {
                addon = "Elles" .. "mereActionBars",
                label = "Elles" .. "mere's Action Bars",
                targets = "all",
            },
            {
                addon = "Elles" .. "mereUnitFrames",
                label = "Elles" .. "mere's Unit Frames",
                targets = "all",
            },
        }

        local exempt = { CludesUIPartyMode = true }

        if not CludesUIDB then
            CludesUIDB = {}
        end
        if not CludesUIDB.dismissedConflicts then
            CludesUIDB.dismissedConflicts = {}
        end
        local dismissed = CludesUIDB.dismissedConflicts

        -- Collect all active conflicts. ElvUI is filtered out if it has been permanently dismissed AND it would be the only conflict showing (i.e. no other conflicts exist).
        local loading = {}
        for _, record in ipairs(conflicts) do
            local moduleActive = not record.moduleCheck or record.moduleCheck()
            if record.addon ~= CUI_HOST_ADDON and IsLoaded(record.addon) and moduleActive then
                local touched = {}
                if record.targets == "all" then
                    local allTargets = {
                        "CludesUIActionBars",
                        "CludesUIUnitFrames",
                        "CludesUINameplates",
                        "CludesUIResourceBars",
                        "CludesUIAuraBuffReminders",
                        "CludesUICooldownManager",
                        "CludesUIRaidFrames",
                    }
                    for _, label in ipairs(allTargets) do
                        if not exempt[label] and IsLoaded(label) then
                            touched[#touched + 1] = label
                        end
                    end
                else
                    for _, t in ipairs(record.targets) do
                        if IsLoaded(t) then
                            touched[#touched + 1] = t
                        end
                    end
                end
                if #touched > 0 then
                    loading[#loading + 1] = { entry = record, affected = touched }
                end
            end
        end

        -- If ElvUI is the ONLY conflict and it has been dismissed, suppress it.
        if #loading == 1 and loading[1].entry.addon == "ElvUI" and dismissed["ElvUI"] then
            return
        end

        -- Show one popup at a time.
        -- "Okay"             -> dismiss this session only; re-shows next login.
        -- "Don't show again" -> permanently dismiss this specific addon.
        local pendingIndex = 0
        local function ShowNextConflict()
            pendingIndex = pendingIndex + 1
            local item = loading[pendingIndex]
            if not item then
                return
            end
            local record, touched = item.entry, item.affected
            -- Skip any conflict the user permanently dismissed previously.
            if dismissed[record.addon] then
                ShowNextConflict()
                return
            end
            local nameList = {}
            for _, a in ipairs(touched) do
                -- Prefer the module's registered display title; fall back to stripping the CludesUI prefix from the folder name.
                local displayName = (modules[a] and modules[a].title) or a:gsub("^CludesUI", "")
                nameList[#nameList + 1] = displayName
            end
            local message = record.message
                or (
                    record.label
                    .. " is not compatible with CludesUI's "
                    .. table.concat(nameList, ", ")
                    .. ". Running both at the same time may cause errors or unexpected behavior."
                    .. "\n\nPlease disable one of them."
                )
            if CludesUI.ShowConfirmPopup then
                CludesUI:ShowConfirmPopup({
                    title = "Incompatible Addon Detected",
                    message = message,
                    confirmText = "Okay",
                    cancelText = "Don't show again",
                    onConfirm = function()
                        ShowNextConflict()
                    end,
                    onCancel = function()
                        dismissed[record.addon] = true
                        ShowNextConflict()
                    end,
                    modal = true,
                })
            else
                CludesUI.PrintError(message:gsub("\n", " "))
                ShowNextConflict()
            end
        end
        ShowNextConflict()
    end
end

-- Auto-run the conflict check only if first-install has already been shown. On first install,
-- the first-install popup will call RunConflictCheck when the user closes it (no reload needed).
C_Timer.After(2, function()
    if CludesUIDB and CludesUIDB.firstInstallPopupShown then
        -- Defer while the style choice popup is still pending/open; it runs the
        -- conflict check itself when dismissed.
        if CludesUI._styleChoicePending then
            return
        end
        CludesUI._RunConflictCheck()
    end
end)

-- /cuiperf: every loaded CludesUI addon's CPU time from Blizzard's addon
-- profiler, heaviest first, for finding what is slow when the game feels
-- laggy. Recent = the last few seconds, Peak = its worst single frame this
-- session. Printed to chat, so it works in combat.
SLASH_CUIPERF1 = "/cuiperf"
SlashCmdList.CUIPERF = function()
    local P, M = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if not (P and P.GetAddOnMetric and M) or (P.IsEnabled and not P.IsEnabled()) then
        CludesUI.PrintError("The addon profiler is not available on this client.")
        return
    end
    local rowList, totalRecent = {}, 0
    for i = 1, C_AddOns.GetNumAddOns() do
        local label = C_AddOns.GetAddOnInfo(i)
        if type(label) == "string" and label:find("^CludesUI") and C_AddOns.IsAddOnLoaded(label) then
            local recent = P.GetAddOnMetric(label, M.RecentAverageTime) or 0
            rowList[#rowList + 1] = {
                name = label,
                recent = recent,
                peak = P.GetAddOnMetric(label, M.PeakTime) or 0,
                session = P.GetAddOnMetric(label, M.SessionAverageTime) or 0,
            }
            totalRecent = totalRecent + recent
        end
    end
    table.sort(rowList, function(posX, posY)
        return posX.recent > posY.recent
    end)
    local fps = GetFramerate() or 0
    CludesUI.Print(
        ("CPU per frame, %d addons, %.3f ms recent total (a frame at %d fps is %.1f ms):"):format(
            #rowList,
            totalRecent,
            fps,
            fps > 0 and 1000 / fps or 0
        )
    )
    for i = 1, math.min(10, #rowList) do
        local r = rowList[i]
        local labelText = r.name:gsub("^CludesUI", "")
        if labelText == "" then
            labelText = "Core"
        end
        print(
            ("  %s: recent %.3f ms, session %.3f ms, peak %.1f ms"):format(
                labelText,
                r.recent,
                r.session,
                r.peak
            )
        )
    end
end

SLASH_CUIOPTIONS1 = "/cui"
SLASH_CUIOPTIONS2 = "/cludes"
SLASH_CUIOPTIONS3 = "/cludesui"
-- Deferred one frame: keeps the panel build out of the chat edit box's
-- execution (its watchdog budget). Blizzard's own Enter handling still runs
-- tainted after any addon slash command; on a whisper to a secret-named
-- target its header math then errors (ChatFrameEditBox UpdateHeader), which
-- no handler-side change can prevent.
SlashCmdList.CUIOPTIONS = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            CludesUI.PrintError("Cannot open options during combat.")
            return
        end
        CludesUI:Toggle()
    end)
end

-- Quick-access: /ce opens global settings
SLASH_CUIQUICK1 = "/ce"
SlashCmdList.CUIQUICK = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            CludesUI.PrintError("Cannot open options during combat.")
            return
        end
        CludesUI:Toggle()
    end)
end

-- Quick-access: /unlock opens Unlock Mode directly
SLASH_CUIUNLOCK1 = "/unlock"
SlashCmdList.CUIUNLOCK = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            CludesUI.PrintError("Cannot open options during combat.")
            return
        end
        CludesUI:EnsureUnlockCore()
        if CludesUI._openUnlockMode then
            CludesUI._openUnlockMode()
        else
            CludesUI.PrintError("Layout Mode is not available.")
        end
    end)
end

-- Support: reset all one-time hint flags so they show again
SLASH_CUIRESETHINT1 = "/cuiresethint"
SlashCmdList.CUIRESETHINT = function()
    C_Timer.After(0, function()
        if CludesUIDB then
            CludesUIDB.previewHintDismissed = nil
            CludesUIDB.unlockTipSeen = nil
            CludesUIDB.sidebarUnlockTipSeen = nil
            CludesUIDB.rfEyeHintSeen = nil
            CludesUIDB.bmIconHintDismissed = nil
            CludesUIDB.cdmButtonTipSeen = nil
            CludesUIDB.bagCategoryTipSeen = nil
            CludesUIDB.inlineCogTipSeen = nil
            CludesUIDB.cogSeen = nil
        end
        CludesUI.Print(CludesUI.L("|cff00ff00[CludesUI]|r All hints reset. /reload to see them again."))
    end)
end

-- Support: wipe saved UI scale so next reload re-snapshots from Blizzard default
SLASH_CUIRESETSCALE1 = "/cuiresetscale"
SlashCmdList.CUIRESETSCALE = function()
    C_Timer.After(0, function()
        if CludesUIDB then
            CludesUIDB.ppUIScale = nil
            CludesUIDB.ppUIScaleAuto = nil
        end
        CludesUI.Print(
            CludesUI.L(
                "|cff00ff00[CludesUI]|r UI scale reset. /reload to re-snapshot from your Blizzard scale."
            )
        )
    end)
end

SLASH_CUIDEV1 = "/cuidev"
SlashCmdList.CUIDEV = function()
    local cvars = {
        "addonChallengeModeRestrictionsForced",
        "addonChatRestrictionsForced",
        "addonCombatRestrictionsForced",
        "addonEncounterRestrictionsForced",
        "addonMapRestrictionsForced",
        "addonPvPMatchRestrictionsForced",
    }
    local current = GetCVar(cvars[1])
    local newVal = (current == "1") and "0" or "1"
    for _, cv in ipairs(cvars) do
        CludesUI.SetCVar(cv, newVal)
    end
    local status = newVal == "1" and "ON" or "OFF"
    CludesUI.Print("|cff00ff00[CludesUI]|r Dev mode: all addon restriction CVars " .. status .. ".")
    if CludesUI.UpdateDevModeIndicator then
        CludesUI.UpdateDevModeIndicator()
    end
end

-------------------------------------------------------------------------------
--  Status badge: a small dark tag with a faint accent wash, a 1px accent border, a
--  pulsing accent dot and an accent label (the /cuidev DEV MODE ACTIVE badge, Simple
--  Loot Council's SLC ACTIVE). Made hidden through the page pool's CreateFrame, so a
--  kept options page hands it back; the caller places it and shows it while its
--  state holds. The dot pulses only while the badge shows. The accent is read when
--  the badge is made.
--  opts (optional): dot = false leaves the dot out (a plain text tag, nothing
--  animated). onClick makes the badge a button: the wash brightens on hover and
--  tooltip (a string, or a function returning one or nil) shows beside it; the
--  caller turns the mouse off (EnableMouse) while a click would do nothing.
-------------------------------------------------------------------------------
function CludesUI.BuildStatusBadge(hostFrame, textValue, label, options)
    local accentColor = CLUDES_GREEN
    local dotted = not (options and options.dot == false)
    local onClick = options and options.onClick
    local f = POOL.CreateFrame(onClick and "Button" or "Frame", label, hostFrame)
    f:SetHeight(26)
    f:EnableMouse(onClick and true or false)
    f:Hide()

    -- Dark base + faint accent wash for an on-brand tint
    local backdrop = f:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.02, 0.02, 0.03, 0.62)
    local wash = f:CreateTexture(nil, "BORDER")
    wash:SetAllPoints()
    wash:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.06)

    Pix.CreateBorder(f, accentColor.r, accentColor.g, accentColor.b, 0.9, 1, "OVERLAY", 7)

    local labelText = f:CreateFontString(nil, "OVERLAY")
    labelText:SetFont(CludesUI.EXPRESSWAY, 11, (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE")
    labelText:SetText(textValue)
    labelText:SetTextColor(accentColor.r, accentColor.g, accentColor.b, 1)

    if dotted then
        -- Pulsing accent "LED" dot (recording-indicator vibe)
        local dotTex = f:CreateTexture(nil, "ARTWORK")
        dotTex:SetTexture("Interface\\Buttons\\WHITE8x8")
        dotTex:SetVertexColor(accentColor.r, accentColor.g, accentColor.b, 1)
        dotTex:SetSize(7, 7)
        dotTex:SetPoint("LEFT", f, "LEFT", 9, 0)
        DisablePixelSnap(dotTex)
        local ag = dotTex:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local pulse = ag:CreateAnimation("Alpha")
        pulse:SetFromAlpha(1)
        pulse:SetToAlpha(0.1)
        pulse:SetDuration(0.7)
        pulse:SetSmoothing("IN_OUT")
        f:SetScript("OnShow", function()
            ag:Play()
        end)
        f:SetScript("OnHide", function()
            ag:Stop()
        end)
        labelText:SetPoint("LEFT", dotTex, "RIGHT", 8, 0)
        -- Size to content: dotPad(9) + dot(7) + gap(8) + text + rightPad(12)
        f:SetWidth(9 + 7 + 8 + labelText:GetStringWidth() + 12)
    else
        labelText:SetPoint("CENTER", f, "CENTER", 0, 0)
        f:SetWidth(12 + labelText:GetStringWidth() + 12)
    end

    if onClick then
        local tipText = options.tooltip
        f:SetScript("OnEnter", function(self)
            wash:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.16)
            local tipText = tipText
            if type(tipText) == "function" then
                tipText = tipText()
            end
            if tipText then
                CludesUI.ShowWidgetTooltip(self, tipText)
            end
        end)
        f:SetScript("OnLeave", function()
            wash:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.06)
            CludesUI.HideWidgetTooltip()
        end)
        f:SetScript("OnClick", function(self)
            wash:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.06)
            CludesUI.HideWidgetTooltip()
            onClick(self)
        end)
    end
    return f
end

-------------------------------------------------------------------------------
--  Dev Mode badge: a small top-left indicator shown while /cuidev is active (the addon-
--  restriction-forced CVars are on, forcing the restricted / secret-value environment for
--  testing). Toggled by /cuidev and re-checked on login, since the CVars persist across sessions.
-------------------------------------------------------------------------------
do
    local DEV_CVAR = "addonChallengeModeRestrictionsForced"

    function CludesUI.IsDevModeActive()
        return GetCVar(DEV_CVAR) == "1"
    end

    local badgeTex

    function CludesUI.UpdateDevModeIndicator()
        if not CludesUI.IsDevModeActive() then
            if badgeTex then
                badgeTex:Hide()
            end
            return
        end
        if not badgeTex then
            badgeTex = CludesUI.BuildStatusBadge(UIParent, "DEV MODE ACTIVE", "CludesUIDevModeBadge")
            badgeTex:SetFrameStrata("HIGH")
            badgeTex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -41)
        end
        badgeTex:Show()
    end

    -- CVars persist across sessions: check on login (deferred so the theme accent is fully resolved). PLAYER_LOGIN re-fires on /reload, so this covers both.
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(2, function()
            CludesUI.UpdateDevModeIndicator()
        end)
    end)
end

-------------------------------------------------------------------------------
--  Minimap Button: a LibDBIcon button (LibDBIcon10_CludesUI), so minimap
--  button bins and the addon compartment handle it like any other addon's.
--  CludesUIDB.showMinimapButton stays the on/off switch the options read;
--  CludesUIDB.minimapIcon is LibDBIcon's own record (position, hidden).
-------------------------------------------------------------------------------
do
    local NAME = "CludesUI"
    local ICON_PATH = "Interface\\AddOns\\CludesUI\\media\\HappyBufo"
    local LDBIcon

    local function IconDB()
        if not CludesUIDB then
            CludesUIDB = {}
        end
        local saved = CludesUIDB.minimapIcon
        if type(saved) ~= "table" then
            -- First run on LibDBIcon: carry over the old button's angle.
            saved = { minimapPos = CludesUIDB.minimapButtonAngle or 220 }
            CludesUIDB.minimapIcon = saved
        end
        saved.hide = CludesUIDB.showMinimapButton == false or nil
        return saved
    end

    function CludesUI.CreateMinimapButton()
        if LDBIcon then
            return LDBIcon:GetMinimapButton(NAME)
        end
        local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
        LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
        if not (LDB and LDBIcon) then
            return
        end

        local launcher = LDB:NewDataObject(NAME, {
            type = "launcher",
            text = NAME,
            icon = ICON_PATH,
            OnClick = function(_, btnFrame)
                if InCombatLockdown() then
                    return
                end
                if btnFrame == "LeftButton" then
                    CludesUI:Toggle()
                elseif btnFrame == "RightButton" then
                    CludesUI:EnsureUnlockCore()
                    if CludesUI._openUnlockMode then
                        CludesUI._openUnlockMode()
                    end
                elseif btnFrame == "MiddleButton" then
                    CludesUIDB.showMinimapButton = false
                    CludesUI.HideMinimapButton()
                    -- an open page re-reads its rows (a closed panel catches up when it next shows)
                    local refreshList = CludesUI._widgetRefreshList
                    if refreshList and #refreshList > 0 then
                        CludesUI:RefreshPage()
                    end
                end
            end,
            OnTooltipShow = function(tt)
                tt:AddLine("|cff4cc9f0CludesUI|r")
                tt:AddLine(CludesUI.L("|cff4cc9f0Left-click:|r |cffE0E0E0Toggle CludesUI|r"))
                tt:AddLine(CludesUI.L("|cff4cc9f0Right-click:|r |cffE0E0E0Enter Layout Mode|r"))
                tt:AddLine(CludesUI.L("|cff4cc9f0Middle-click:|r |cffE0E0E0Hide Minimap Button|r"))
            end,
        })
        LDBIcon:Register(NAME, launcher, IconDB())
        return LDBIcon:GetMinimapButton(NAME)
    end

    function CludesUI.ShowMinimapButton()
        if not LDBIcon then
            CludesUI.CreateMinimapButton()
        end
        if LDBIcon then
            IconDB()
            LDBIcon:Show(NAME)
        end
    end

    function CludesUI.HideMinimapButton()
        if LDBIcon then
            IconDB()
            LDBIcon:Hide(NAME)
        end
    end
end

-- Spell ID on Tooltip (Blizzard Skins+ > Tooltips & Menus, Global Settings >
-- Developer): on unless turned off. Accounts from before that default keep it
-- off through the spellid_default_on_v1 migration (CludesUI_Migration.lua).
function CludesUI.SpellIDOn()
    local saved = CludesUIDB
    return saved ~= nil and saved.showSpellID ~= false
end

-------------------------------------------------------------------------------
--  Init  +  Demo Modules  (temporary placeholder content)
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
initFrame:SetScript("OnEvent", function(self, evt)
    if evt == "PLAYER_REGEN_DISABLED" then
        if CludesUI._mainFrame and CludesUI._mainFrame:IsShown() then
            CludesUI:Hide()
            CludesUI.PrintError("Options closed -- entering combat.")
        end
        return
    end

    -- PLAYER_LOGIN: register demo modules (UI is built lazily on first open)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Apply the global font to Blizzard's default game text (opt-in, reload-gated).
    -- Done here at login, out of combat, so it runs once before the UI renders.
    CludesUI.ApplyGlobalFontToGameText()
    -- Always-on failsafe: swap the shared font objects behind Chat, the Quest Tracker, and
    -- Blizzard-UI-Enhanced tooltips to each module's font, so the sub-elements our per-frame
    -- styling misses pick up the right face. Runs after the global pass so the per-module face wins in those three areas.
    CludesUI.ApplyModuleFontFailsafe()

    ---------------------------------------------------------------------------
    --  Escape proxy: single UISpecialFrames entry for all CUI frames.
    --  Child addons call CludesUI.RegisterEscapeClose(frame[, opts]) to opt
    --  in (defined here, at PLAYER_LOGIN). Every opt is optional; a frame
    --  registered without opts closes one per Escape press, newest registration
    --  first, exactly as before:
    --    cursor    raise the gamepad pointer on each show (user-opened windows)
    --    onEscape  fn(frame) runs instead of frame:Hide() when Escape/Back closes it
    --    modal     true or fn(frame): never closed by Escape/Back, never keeps the
    --              proxy shown by itself, and while shown swallows Escape/Back for
    --              the windows under it (as a modal popup's own key handler does)
    --    notOwned  no controller-cursor registration: a frame we do not own, or
    --              one that must never be a controller-cursor root (Unlock Mode)
    --    padOnly   counts only when a controller was in use at its show (popups,
    --              dimmers, Unlock Mode); otherwise it never touches the proxy
    --  Controller Back while the gamepad pointer is in control closes every open
    --  window in one pass: Blizzard turns the pointer off after that press.
    ---------------------------------------------------------------------------
    do
        local escapeFrames = {}
        local escOpts = {} -- [frame] = its opts (a shared empty table when none)
        local escModal = {} -- registered non-padOnly frames with a modal opt
        local padShown = {} -- padOnly frames that count, in show order
        local closeList = {} -- reused by the controller close-all pass
        local closing = false
        local NO_OPTS = {}
        local PadNative, PadInUse = CludesUI.PadNative, CludesUI.PadInUse
        local proxy = CreateFrame("Frame", "CludesUI_EscapeProxy", UIParent)
        proxy:Hide()
        tinsert(UISpecialFrames, "CludesUI_EscapeProxy")

        local function IsModal(f)
            local m = escOpts[f].modal
            if not m then
                return false
            end
            if m == true then
                return true
            end
            return m(f) and true or false
        end

        local function AnyOpen()
            for i = 1, #escapeFrames do
                local f = escapeFrames[i]
                if f:IsShown() and not IsModal(f) then
                    return true
                end
            end
            for i = 1, #padShown do
                local f = padShown[i]
                if f:IsShown() and not IsModal(f) then
                    return true
                end
            end
            return false
        end

        local function ModalOpen()
            for i = 1, #escModal do
                local f = escModal[i]
                if f:IsShown() and IsModal(f) then
                    return true
                end
            end
            for i = 1, #padShown do
                local f = padShown[i]
                if f:IsShown() and IsModal(f) then
                    return true
                end
            end
            return false
        end

        local function RefreshProxy()
            if closing then
                return
            end
            if AnyOpen() then
                proxy:Show()
            else
                proxy:Hide()
            end
        end

        local function CloseOne(f)
            local onEscape = escOpts[f].onEscape
            if onEscape then
                onEscape(f)
            else
                f:Hide()
            end
        end

        -- Controller close-all pass over the snapshot in closeList.
        local function CloseListed(n)
            for i = 1, n do
                local f = closeList[i]
                if f:IsShown() then
                    CloseOne(f)
                end
            end
        end

        proxy:SetScript("OnHide", function(self)
            if closing then
                return
            end
            if ModalOpen() then
                RefreshProxy()
                return
            end
            -- Controller Back (a real Hide, the gamepad pointer in control):
            -- close everything now, newest controller-counted window first.
            if not self:IsShown() and PadNative() and CanAutoSetGamePadCursorControl(false) then
                local n = 0
                for i = #padShown, 1, -1 do
                    local f = padShown[i]
                    if f:IsShown() and not IsModal(f) then
                        n = n + 1
                        closeList[n] = f
                    end
                end
                for i = #escapeFrames, 1, -1 do
                    local f = escapeFrames[i]
                    if f:IsShown() and not IsModal(f) then
                        n = n + 1
                        closeList[n] = f
                    end
                end
                -- A failing onEscape must not leave the proxy stuck in `closing`.
                closing = true
                local success, err = pcall(CloseListed, n)
                closing = false
                wipe(closeList)
                RefreshProxy()
                if not success then
                    geterrorhandler()(err)
                end
                return
            end
            -- One window per press: a controller-counted window first (only
            -- ever present while a controller is in use), then the registry.
            for i = #padShown, 1, -1 do
                local f = padShown[i]
                if f:IsShown() and not IsModal(f) then
                    CloseOne(f)
                    if AnyOpen() then
                        self:Show()
                    end
                    return
                end
            end
            for i = #escapeFrames, 1, -1 do
                local f = escapeFrames[i]
                if f:IsShown() and not IsModal(f) then
                    CloseOne(f)
                    if AnyOpen() then
                        self:Show()
                    end
                    return
                end
            end
        end)

        -- padOnly: one controller check at the show edge; the hide edge only
        -- walks the counted list, which stays empty for mouse/keyboard players.
        local function PadOnlyShown(f)
            if not PadInUse() then
                return
            end
            for i = #padShown, 1, -1 do
                if padShown[i] == f then
                    table.remove(padShown, i)
                end
            end
            padShown[#padShown + 1] = f
            RefreshProxy()
        end

        local function PadOnlyHidden(f)
            for i = #padShown, 1, -1 do
                if padShown[i] == f then
                    table.remove(padShown, i)
                    RefreshProxy()
                    return
                end
            end
        end

        function CludesUI.RegisterEscapeClose(widget, options)
            if escOpts[widget] then
                return
            end
            options = options or NO_OPTS
            escOpts[widget] = options
            if not options.notOwned then
                CludesUI.RegisterPadFrame(widget)
            end
            if options.cursor then
                widget:HookScript("OnShow", CludesUI.RaiseGamePadCursor)
            end
            if options.padOnly then
                widget:HookScript("OnShow", PadOnlyShown)
                widget:HookScript("OnHide", PadOnlyHidden)
                return
            end
            if options.modal then
                escModal[#escModal + 1] = widget
            end
            escapeFrames[#escapeFrames + 1] = widget
            widget:HookScript("OnShow", RefreshProxy)
            widget:HookScript("OnHide", RefreshProxy)
        end

        -- The options page pool (CludesUI_FramePool.lua) resets a frame it hands
        -- out again to the state of a new frame, which drops the hooks above: the
        -- registration goes with them, so the code that dresses the frame again
        -- registers it again, exactly as it registered the new frame.
        function CludesUI._ForgetEscapeClose(widget)
            if not escOpts[widget] then
                return
            end
            escOpts[widget] = nil
            for i = #escapeFrames, 1, -1 do
                if escapeFrames[i] == widget then
                    table.remove(escapeFrames, i)
                end
            end
            for i = #escModal, 1, -1 do
                if escModal[i] == widget then
                    table.remove(escModal, i)
                end
            end
            for i = #padShown, 1, -1 do
                if padShown[i] == widget then
                    table.remove(padShown, i)
                end
            end
            RefreshProxy()
        end

        -- Register the Vault once, regardless of which shortcut opens it.
        -- Blizzard's frame: never handed to the controller cursor.
        local function RegisterVaultEscapeClose()
            if not WeeklyRewardsFrame then
                return false
            end
            CludesUI.RegisterEscapeClose(WeeklyRewardsFrame, { notOwned = true })
            RefreshProxy()
            return true
        end

        if not RegisterVaultEscapeClose() then
            local vaultLoader = CreateFrame("Frame")
            vaultLoader:RegisterEvent("ADDON_LOADED")
            vaultLoader:SetScript("OnEvent", function(self, evt, addonName)
                if addonName == "Blizzard_WeeklyRewards" and RegisterVaultEscapeClose() then
                    self:UnregisterEvent("ADDON_LOADED")
                end
            end)
        end
    end

    -- Create native minimap button
    CludesUI.CreateMinimapButton()

    -- Add CludesUI + Unlock Mode buttons to the Game Menu (pause menu); both share a single Layout hook to avoid double-push conflicts.
    if GameMenuFrame and not CludesUI._GetFFD(GameMenuFrame).cuiBtn then
        -- Game menu frame+button skinning lives in CludesUIBlizzardSkin (CUI_BlizzardSkin_Dialogs.lua) so it only
        -- applies when that addon is enabled; detect whether the skin is active so CUI's own buttons match the skinned menu style.
        local _blizzSkinLoaded = C_AddOns
            and C_AddOns.IsAddOnLoaded
            and C_AddOns.IsAddOnLoaded("CludesUIBlizzardSkin")
        -- "Reskin Pause Menu" is an independent toggle (default on); the migration blizzskin_reskin_master_split_v1 seeds reskinGameMenu for existing users.
        local _reskinMenu = _blizzSkinLoaded and (not CludesUIDB or CludesUIDB.reskinGameMenu ~= false)

        local button =
            CreateFrame("Button", "CludesUI_GameMenuButton", GameMenuFrame, "MainMenuFrameButtonTemplate")
        button:SetSize(200, 35)
        button:SetScript("OnClick", function()
            if InCombatLockdown() then
                CludesUI.PrintError("Cannot open options during combat.")
                return
            end
            HideUIPanel(GameMenuFrame)
            CludesUI:Toggle()
            -- Controller cursor: the pause menu turned the gamepad pointer off as it
            -- hid; unfolding the mini window fires no OnShow, so raise it here too.
            if CludesUI.PadNative() and CludesUI:IsShown() then
                CludesUI.RaiseGamePadCursor()
            end
        end)
        CludesUI._GetFFD(GameMenuFrame).cuiBtn = button

        local unlockButton =
            CreateFrame("Button", "CludesUI_UnlockMenuButton", GameMenuFrame, "MainMenuFrameButtonTemplate")
        unlockButton:SetSize(200, 35)
        unlockButton:SetScript("OnClick", function()
            if InCombatLockdown() then
                CludesUI.PrintError("Cannot toggle Layout Mode during combat.")
                return
            end
            HideUIPanel(GameMenuFrame)
            if CludesUI.ToggleUnlockMode then
                CludesUI:ToggleUnlockMode()
            end
            -- Controller cursor: the pause menu turned the gamepad pointer off as it hid.
            if CludesUI.PadNative() and CludesUI._unlockActive then
                CludesUI.RaiseGamePadCursor()
            end
        end)
        CludesUI._GetFFD(GameMenuFrame).unlockBtn = unlockButton

        -- Skin our custom buttons the same way as pooled Blizzard buttons
        if _reskinMenu then
            for _, customButton in ipairs({ button, unlockButton }) do
                local regions = { customButton:GetRegions() }
                for jdx = 1, #regions do
                    local r = regions[jdx]
                    if r and r:IsObjectType("Texture") and r ~= customButton:GetFontString() then
                        r:SetAlpha(0)
                    end
                end
                if customButton.Left then
                    customButton.Left:SetAlpha(0)
                end
                if customButton.Middle then
                    customButton.Middle:SetAlpha(0)
                end
                if customButton.Right then
                    customButton.Right:SetAlpha(0)
                end
                for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                    local texture = customButton[texKey]
                    if texture and texture.SetAlpha then
                        hooksecurefunc(texture, "SetAlpha", function(self, a)
                            if a > 0 then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end
                local insetPx = CreateFrame("Frame", nil, customButton)
                insetPx:SetPoint("TOPLEFT", 2, -2)
                insetPx:SetPoint("BOTTOMRIGHT", -2, 2)
                insetPx:SetFrameLevel(customButton:GetFrameLevel())
                local cBg = insetPx:CreateTexture(nil, "BACKGROUND", nil, -6)
                cBg:SetAllPoints()
                local color = CludesUIDB and CludesUIDB.popupMenuButtonBackgroundColor
                    or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
                cBg:SetColorTexture(color.r, color.g, color.b, color.a == nil and 0.8 or color.a)
                CludesUI._GetFFD(customButton).gameMenuInset = insetPx
                CludesUI._GetFFD(customButton).gameMenuButtonBg = cBg
                if CludesUI._applyBlizzardConfiguredBorder then
                    CludesUI._applyBlizzardConfiguredBorder(insetPx, "popupMenuButton", 1)
                end
                local highlight = customButton:CreateTexture(nil, "HIGHLIGHT")
                highlight:SetAllPoints(insetPx)
                highlight:SetColorTexture(1, 1, 1, 0.1)
                local cfs = customButton:GetFontString()
                if cfs then
                    local cuiFont = CludesUI.GetFontPath() or nil
                    local _, px, flags = cfs:GetFont()
                    cfs:SetFont(cuiFont or "Fonts\\FRIZQT__.TTF", (px or 14) - 2, flags or "")
                    -- Native mode keeps the branded inline-code labels set by
                    -- the Layout hook; only explicit modes flat-recolor.
                    if
                        CludesUI._getPopupMenuElementMode
                        and CludesUI._getPopupMenuElementMode() ~= "native"
                        and CludesUI._getPopupMenuButtonTextColor
                    then
                        local red, green, blue = CludesUI._getPopupMenuButtonTextColor()
                        cfs:SetTextColor(red, green, blue, 1)
                    end
                end
            end
        end

        local _gameMenuBaseHeight = nil
        hooksecurefunc(GameMenuFrame, "Layout", function()
            if InCombatLockdown() then
                button:Hide()
                unlockButton:Hide()
                return
            end

            -- Re-apply accent color to header text on every open (only when skinned)
            if _reskinMenu then
                local headerText = GameMenuFrame.Header
                if headerText then
                    local headerText = headerText.Text
                    if headerText and headerText.SetTextColor then
                        if CludesUI._getPopupMenuButtonTextColor then
                            local red, green, blue = CludesUI._getPopupMenuButtonTextColor()
                            headerText:SetTextColor(red, green, blue, 1)
                        end
                    end
                end
            end

            -- Determine which buttons are visible
            local showCUI = not (CludesUIDB and CludesUIDB.hideGameMenuButton)
            local showUnlock = CludesUIDB and CludesUIDB.hideUnlockMenuButton == false

            if not showCUI then
                button:Hide()
            end
            if not showUnlock then
                unlockButton:Hide()
            end
            if not showCUI and not showUnlock then
                return
            end

            -- Find the Shop button to anchor below (fall back to Options)
            local anchorButton
            for menuBtn in GameMenuFrame.buttonPool:EnumerateActive() do
                local textValue = menuBtn:GetText()
                if textValue == BLIZZARD_STORE then
                    anchorButton = menuBtn
                    break
                elseif textValue == GAMEMENU_OPTIONS then
                    anchorButton = menuBtn
                end
            end
            if not anchorButton then
                return
            end

            -- Match our buttons to the Blizzard button size
            local anchorW, anchorH = anchorButton:GetWidth(), anchorButton:GetHeight()
            if anchorW and anchorW > 0 then
                button:SetSize(anchorW, anchorH or 35)
                unlockButton:SetSize(anchorW, anchorH or 35)
            end

            -- Position our buttons in a chain below the anchor
            local extraHeight = 0
            local lastBtn = anchorButton
            local cuiFont = CludesUI.GetFontPath() or "Fonts\\FRIZQT__.TTF"
            local btnFontSize = 13
            -- Branded two-tone labels are the default (native mode, or when BlizzardSkin is not
            -- loaded) -- applied via inline color codes in SetText, which works with the
            -- pause-menu reskin off too. Only an explicitly chosen Element & Text Color mode switches to a plain label + whole-string recolor (inline codes would override SetTextColor otherwise).
            local elemMode = CludesUI._getPopupMenuElementMode and CludesUI._getPopupMenuElementMode()
                or "native"
            local brandHex
            if elemMode == "native" then
                local ACC = CludesUI.CLUDES_GREEN or { r = 0.27, g = 0.86, b = 0.49 }
                brandHex = CludesUI.HexColor(ACC.r, ACC.g, ACC.b)
            end

            if showCUI then
                button:Show()
                if brandHex then
                    button:SetText(brandHex .. "Cludes|r|cffffffffUI|r")
                else
                    button:SetText("CludesUI")
                end
                if _reskinMenu then
                    local fontStr = button:GetFontString()
                    if fontStr then
                        fontStr:SetFont(cuiFont, btnFontSize, "")
                        if not brandHex and CludesUI._getPopupMenuButtonTextColor then
                            local red, green, blue = CludesUI._getPopupMenuButtonTextColor()
                            fontStr:SetTextColor(red, green, blue, 1)
                        end
                    end
                end
                button:ClearAllPoints()
                button:SetPoint("TOP", lastBtn, "BOTTOM", 0, -12)
                lastBtn = button
                extraHeight = extraHeight + 40
            end
            if showUnlock then
                unlockButton:Show()
                if brandHex then
                    unlockButton:SetText(brandHex .. "CUI|r |cffffffffLayout Mode|r")
                else
                    unlockButton:SetText("CUI Layout Mode")
                end
                if _reskinMenu then
                    local fs2 = unlockButton:GetFontString()
                    if fs2 then
                        fs2:SetFont(cuiFont, btnFontSize, "")
                        if not brandHex and CludesUI._getPopupMenuButtonTextColor then
                            local red, green, blue = CludesUI._getPopupMenuButtonTextColor()
                            fs2:SetTextColor(red, green, blue, 1)
                        end
                    end
                end
                unlockButton:ClearAllPoints()
                unlockButton:SetPoint("TOP", lastBtn, "BOTTOM", 0, showCUI and -4 or -12)
                extraHeight = extraHeight + (showCUI and 40 or 40)
            end

            -- Push all Blizzard buttons below the anchor down
            local anchorBottom = anchorButton:GetBottom()
            if anchorBottom then
                for menuBtn in GameMenuFrame.buttonPool:EnumerateActive() do
                    local topY = menuBtn:GetTop()
                    if topY and topY < anchorBottom + 2 then
                        local p, rel, rp, posX, posY = menuBtn:GetPoint(1)
                        if p then
                            menuBtn:ClearAllPoints()
                            menuBtn:SetPoint(p, rel, rp, posX, (posY or 0) - extraHeight)
                        end
                    end
                end
            end

            if not _gameMenuBaseHeight then
                _gameMenuBaseHeight = GameMenuFrame:GetHeight()
            end
            GameMenuFrame:SetHeight(_gameMenuBaseHeight + extraHeight)
        end)
    end

    -- Apply theme settings from SavedVariables
    if CludesUIDB then
        local skinName = CludesUIDB.activeTheme or CludesUI.DEFAULT_THEME
        CLUDES_GREEN._themeEnabled = true
        local themeR, themeG, themeB = CludesUI.ResolveThemeColor(skinName)
        -- Apply theme color to the window background only. The CUI Options Theme
        -- is a SEPARATE, global control from the UI accent color (per-profile).
        if CludesUI._applyBgTint then
            CludesUI._applyBgTint(themeR, themeG, themeB)
        end
        -- Art left out of the file-load preload is preloaded for its own player only.
        CludesUI._PreloadLazyThemeBG(skinName)
        -- UI accent: authoritative login resolution for the active profile
        -- (per-profile cuiAccent -> frozen global root -> theme color). When a
        -- profile has no per-profile accent this reproduces the legacy behavior
        -- exactly, so existing users see zero change.
        --
        -- Routed through the live-apply path rather than assigning the three
        -- fields directly: Lite is TOC-ordered ahead of this file, so its
        -- PLAYER_LOGIN fires first and every module's OnEnable has already
        -- painted against the parse-time fallback. Notifying repaints them.
        local accentR, accentG, accentB = CludesUI.ResolveActiveAccent()
        if CludesUI.ApplyAccentColorLive then
            CludesUI.ApplyAccentColorLive(accentR, accentG, accentB)
        else
            CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b = accentR, accentG, accentB
        end
    end

    -- Spell ID / Item ID + Icon ID / Max Item Stack on Tooltip (developer option)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        -- Register per-type callbacks instead of AllTypes to avoid firing on every unit/currency tooltip in the game (major CPU savings).
        local _isSecret = issecretvalue -- cache global once

        -- The spell/item/icon ID lines can be gated behind a held modifier (the "Use Modifier"
        -- cog: none | shift | control | alt, default none). "none" shows them whenever Show
        -- Spell ID is on (the original behavior); the others only surface the lines while that key is held.
        local function IsSpellIDModifierHeld()
            local mod = (CludesUIDB and CludesUIDB.spellIDModifier) or "none"
            if mod == "none" then
                return true
            end
            if mod == "control" then
                return IsControlKeyDown()
            end
            if mod == "alt" then
                return IsAltKeyDown()
            end
            return IsShiftKeyDown()
        end

        -- The Max Item Stack lines can be gated behind a held modifier (the "Use Modifier" cog:
        -- none | shift | control | alt, default none). "none" shows them whenever Show Max Stack
        -- for items is on (the original behavior); the others only surface the lines while that key is held.
        local function IsItemStackModifierHeld()
            local mod = (CludesUIDB and CludesUIDB.itemStackModifier) or "none"
            if mod == "none" then
                return true
            end
            if mod == "control" then
                return IsControlKeyDown()
            end
            if mod == "alt" then
                return IsAltKeyDown()
            end
            return IsShiftKeyDown()
        end

        -- Shared dedup check: only scan last 5 lines (we add at most 3)
        local function hasDupLine(tipText, label, tag)
            local n = tipText:NumLines()
            local start = n - 4
            if start < 1 then
                start = 1
            end
            for i = n, start, -1 do
                local fontStr = _G[label .. "TextLeft" .. i]
                if fontStr then
                    local txt = fontStr:GetText()
                    if txt then
                        if _isSecret and _isSecret(txt) then
                            return true
                        end
                        if txt:find(tag) then
                            return true
                        end
                    end
                end
            end
            return false
        end

        -- 12.1 ONLY: aura spell IDs during combat. The Lua hooks below can never render them
        -- there -- under aura restrictions the tooltip's id is a SECRET value -- but the
        -- engine-side tooltipShowAuraSpellIDs CVar (68824+) formats the ID itself and works under
        -- full secrecy, including the forbidden container tooltips. The CVar is session-only, so
        -- it re-asserts every login and on toggle edits. Modifier-gated configs skip it: the engine renders always-on, which would override the user's hold-a-modifier preference (their combat aura IDs stay unavailable -- inherent trade).
        function CludesUI.SyncAuraSpellIDCVar()
            local saved = CludesUIDB
            local enabled = CludesUI.SpellIDOn() and (saved.spellIDModifier or "none") == "none"
            pcall(CludesUI.SetCVar, "tooltipShowAuraSpellIDs", enabled and "1" or "0")
        end
        do
            -- PLAYER_ENTERING_WORLD, not PLAYER_LOGIN: the engine settles its
            -- session CVars after login and clobbered the early write -- aura
            -- IDs stayed off until the user re-toggled the option (field-
            -- reported). Kept registered: a re-assert per zone-in is one
            -- pcall'd SetCVar and survives any later engine reset.
            local cvarBoot = CreateFrame("Frame")
            cvarBoot:RegisterEvent("PLAYER_ENTERING_WORLD")
            -- Instance zone-ins also remind once per session about the two
            -- debug CVars that quietly tax combat performance (taintLog is
            -- often left on after a bug-report capture; scriptProfile adds
            -- per-call overhead to every addon and only changes effect on
            -- reload). Ignore or Esc keeps it quiet until the next reload;
            -- the flag is set on SHOW, so nothing re-fires on later zones.
            local perfPromptShown = false
            cvarBoot:SetScript("OnEvent", function()
                CludesUI.SyncAuraSpellIDCVar()
                if perfPromptShown or not IsInInstance() then
                    return
                end
                local taintOn = (tonumber(GetCVar("taintLog") or 0) or 0) > 0
                local profOn = (tonumber(GetCVar("scriptProfile") or 0) or 0) > 0
                if not (taintOn or profOn) then
                    return
                end
                perfPromptShown = true
                local which
                if taintOn and profOn then
                    which = CludesUI.L("The taintLog and scriptProfile CVars are enabled.")
                elseif taintOn then
                    which = CludesUI.L("The taintLog CVar is enabled.")
                else
                    which = CludesUI.L("The scriptProfile CVar is enabled.")
                end
                CludesUI:ShowConfirmPopup({
                    title = CludesUI.L("Performance Reminder"),
                    message = which
                        .. " "
                        .. CludesUI.L(
                            "It reduces performance and should be off unless you are capturing a bug report."
                        ),
                    confirmText = CludesUI.L("Disable and Reload"),
                    cancelText = CludesUI.L("Ignore"),
                    reload = true,
                    onConfirm = function()
                        -- The player's own fix, which Uninstall CUI must not
                        -- undo: plain SetCVar, not CludesUI.SetCVar.
                        pcall(C_CVar.SetCVar, "taintLog", "0")
                        pcall(C_CVar.SetCVar, "scriptProfile", "0")
                    end,
                })
            end)
        end

        local function SpellIDTooltipHook(tipText, info)
            if not CludesUI.SpellIDOn() then
                return
            end
            if not IsSpellIDModifierHeld() then
                return
            end
            if not info or not info.id then
                return
            end
            if _isSecret and _isSecret(info.id) then
                return
            end
            -- 12.1 no-modifier configs render aura IDs engine-side via the tooltipShowAuraSpellIDs
            -- CVar (see SyncAuraSpellIDCVar); adding the Lua line too would show the ID twice on aura tooltips.
            if
                Enum.TooltipDataType
                and info.type == Enum.TooltipDataType.UnitAura
                and (CludesUIDB.spellIDModifier or "none") == "none"
            then
                return
            end
            if not tipText or not tipText.GetName then
                return
            end
            local success, label = pcall(tipText.GetName, tipText)
            if not success or not label then
                return
            end
            if hasDupLine(tipText, label, "SpellID") then
                return
            end
            tipText:AddDoubleLine("SpellID", tostring(info.id), 1, 1, 1, 1, 1, 1)
            if CludesUIDB.showIconID ~= false then
                local iconID = C_Spell.GetSpellTexture(info.id)
                if iconID then
                    tipText:AddDoubleLine("IconID", tostring(iconID), 1, 1, 1, 1, 1, 1)
                end
            end
            tipText:Show()
        end

        local function ItemIDTooltipHook(tipText, info)
            if not CludesUI.SpellIDOn() then
                return
            end
            if not IsSpellIDModifierHeld() then
                return
            end
            if not info or not info.id then
                return
            end
            if _isSecret and _isSecret(info.id) then
                return
            end
            if not tipText or not tipText.GetName then
                return
            end
            local success, label = pcall(tipText.GetName, tipText)
            if not success or not label then
                return
            end
            -- The gem-socketing window's item text is a tooltip-data frame; ID lines do not belong inside that window.
            if label == "ItemSocketingDescription" then
                return
            end
            if hasDupLine(tipText, label, "ItemID") then
                return
            end
            local showItem = CludesUIDB.showItemID ~= false
            local showIcon = CludesUIDB.showIconID ~= false
            if not showItem and not showIcon then
                return
            end
            if showItem then
                tipText:AddDoubleLine("ItemID", tostring(info.id), 1, 1, 1, 1, 1, 1)
            end
            if showIcon then
                local iconID = C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.id)
                    or (GetItemIcon and GetItemIcon(info.id))
                if iconID then
                    tipText:AddDoubleLine("IconID", tostring(iconID), 1, 1, 1, 1, 1, 1)
                end
            end
            tipText:Show()
        end

        local function ItemIdMaxStackHook(tipText, info)
            if not (CludesUIDB and CludesUIDB.showItemMaxStacks) then
                return
            end
            if not IsItemStackModifierHeld() then
                return
            end
            if not info or not info.id then
                return
            end
            if _isSecret and _isSecret(info.id) then
                return
            end
            if not tipText or not tipText.GetName then
                return
            end
            local success, label = pcall(tipText.GetName, tipText)
            if not success or not label then
                return
            end
            if label == "ItemSocketingDescription" then
                return
            end
            if hasDupLine(tipText, label, "Max Stack") then
                return
            end

            -- 8th return of GetItemInfo is the native max stack size; nil while the item is uncached (the line then appears on the next hover).
            local _, _, _, _, _, _, _, maxStack = C_Item.GetItemInfo(info.id)
            if maxStack and maxStack > 1 then
                tipText:AddDoubleLine("Max Stack", tostring(maxStack), 1, 1, 1, 1, 1, 1)
                tipText:Show()
            end
        end

        -- Macros surface as their own tooltip type, so the Spell hook above never fires for
        -- them (GetSpell() also returns nil on a macro tooltip). The spell #showtooltip resolved
        -- to (honoring conditionals) is exposed as the FIRST tooltip line's tooltipID, read from the tooltip data.
        local function MacroSpellIDTooltipHook(tipText, _data)
            if not CludesUI.SpellIDOn() then
                return
            end
            if not IsSpellIDModifierHeld() then
                return
            end
            if not tipText or not tipText.GetName or not tipText.GetTooltipData then
                return
            end
            local success, details = pcall(tipText.GetTooltipData, tipText)
            if not success or type(details) ~= "table" or not details.lines then
                return
            end
            local line = details.lines[1]
            local spellId = line and line.tooltipID
            if not spellId then
                return
            end -- item-only macro / nothing castable
            if _isSecret and _isSecret(spellId) then
                return
            end
            local okN, label = pcall(tipText.GetName, tipText)
            if not okN or not label then
                return
            end
            if hasDupLine(tipText, label, "SpellID") then
                return
            end
            tipText:AddDoubleLine("SpellID", tostring(spellId), 1, 1, 1, 1, 1, 1)
            if CludesUIDB.showIconID ~= false then
                local iconID = C_Spell.GetSpellTexture(spellId)
                if iconID then
                    tipText:AddDoubleLine("IconID", tostring(iconID), 1, 1, 1, 1, 1, 1)
                end
            end
            tipText:Show()
        end

        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, SpellIDTooltipHook)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, SpellIDTooltipHook)
        if Enum.TooltipDataType.PetAction then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.PetAction, SpellIDTooltipHook)
        end
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ItemIDTooltipHook)
        if Enum.TooltipDataType.Macro then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, MacroSpellIDTooltipHook)
        end
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ItemIdMaxStackHook)

        -- Live toggle: when a selected modifier is pressed/released while a tooltip is hovered,
        -- re-process the shown GameTooltip so the ID and Max Stack lines appear/disappear without
        -- re-hovering. RefreshData re-runs the post-calls above (which then add or skip their
        -- lines per their own modifier checks). Only fires when a feature is on and its chosen modifier actually changed.
        local function KeyMatchesModifier(entryKey, mod)
            return (mod == "shift" and (entryKey == "LSHIFT" or entryKey == "RSHIFT"))
                or (mod == "control" and (entryKey == "LCTRL" or entryKey == "RCTRL"))
                or (mod == "alt" and (entryKey == "LALT" or entryKey == "RALT"))
        end
        local modWatcher = CreateFrame("Frame")
        modWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
        modWatcher:SetScript("OnEvent", function(_, entryKey)
            local saved = CludesUIDB
            if not saved then
                return
            end
            local relevant = (
                CludesUI.SpellIDOn() and KeyMatchesModifier(entryKey, saved.spellIDModifier or "none")
            )
                or (saved.showItemMaxStacks and KeyMatchesModifier(entryKey, saved.itemStackModifier or "none"))
            if not relevant then
                return
            end
            if GameTooltip and GameTooltip:IsShown() and GameTooltip.RefreshData then
                GameTooltip:RefreshData()
            end
        end)
    end

    -- Consolidated Blizzard AddOns > Options panel (single entry for all Cludes addons)
    local panelFrame = CreateFrame("Frame")
    panelFrame.name = "CludesUI"
    local button = CreateFrame("Button", nil, panelFrame, "UIPanelButtonTemplate")
    button:SetSize(200, 30)
    button:SetPoint("CENTER", panelFrame, "CENTER", 0, 0)
    button:SetText("Open CludesUI")
    button:SetScript("OnClick", function()
        if InCombatLockdown() then
            CludesUI.PrintError("Cannot open options during combat.")
            return
        end
        -- Close Blizzard settings first, then open ours on next frame to avoid taint
        if SettingsPanel and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end
        C_Timer.After(0, function()
            if CludesUI then
                CludesUI:Show()
            end
        end)
    end)
    local category = Settings.RegisterCanvasLayoutCategory(panelFrame, "CludesUI")
    Settings.RegisterAddOnCategory(category)

    local dT, dS, dD = {}, {}, {}
    local demoConfigs = {
        -- Only list addons that do NOT have their own CUI_*_Options.lua yet. Addons with real
        -- options files register via PLAYER_LOGIN and must NOT appear here -- the demo would race and win due to page caching.
        {
            folder = "CludesBeaconReminder",
            title = "Beacon Reminders",
            desc = "Configure alerts for missing Beacon of Light or Faith.",
            pages = { "General", "Alerts" },
        },
        {
            folder = "CludesConsumablesTracker",
            title = "Consumables",
            desc = "Track consumables and raid buffs for instanced content.",
            pages = { "General", "Tracking" },
        },
    }

    for _, conf in ipairs(demoConfigs) do
        if IsAddonLoaded(conf.folder) and not modules[conf.folder] then
            local k = conf.folder
            dT[k] = {
                opt1 = true,
                opt2 = false,
                opt3 = true,
                opt4 = false,
                opt5 = true,
                opt6 = false,
                opt7 = true,
            }
            dS[k] = { size = 36, font = 14, opacity = 80, spacing = 4, scale = 100, thickness = 2 }
            dD[k] = { effect = "pulse", position = "center", style = "modern" }
            local dC = {
                showInRaid = true,
                showInDungeon = true,
                showInArena = false,
                showInBG = false,
                showInWorld = true,
                showWhileMounted = false,
            }

            CUI_NS.RegisterCoreModule(conf.folder, {
                title = conf.title,
                description = conf.desc,
                pages = conf.pages,
                buildPage = function(pageName, hostFrame, yOffset)
                    local W = CludesUI.Widgets
                    local posY = yOffset
                    local _, hgt

                    _, hgt = W:SectionHeader(hostFrame, "APPEARANCE", posY)
                    posY = posY - hgt
                    _, hgt = W:Toggle(hostFrame, "Enable Modern Styling", posY, function()
                        return dT[k].opt1
                    end, function(v)
                        dT[k].opt1 = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Slider(hostFrame, "Icon Size", posY, 16, 64, 1, function()
                        return dS[k].size
                    end, function(v)
                        dS[k].size = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Dropdown(
                        hostFrame,
                        "Proc Glow Effect",
                        posY,
                        { pulse = "Pulse", flash = "Flash", none = "None" },
                        function()
                            return dD[k].effect
                        end,
                        function(v)
                            dD[k].effect = v
                        end
                    )
                    posY = posY - hgt
                    _, hgt = W:Toggle(hostFrame, "Show Border", posY, function()
                        return dT[k].opt3
                    end, function(v)
                        dT[k].opt3 = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Slider(hostFrame, "Border Opacity", posY, 0, 100, 5, function()
                        return dS[k].opacity
                    end, function(v)
                        dS[k].opacity = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Spacer(hostFrame, posY, 20)
                    posY = posY - hgt

                    _, hgt = W:SectionHeader(hostFrame, "KEY BINDING TEXT", posY)
                    posY = posY - hgt
                    _, hgt = W:Toggle(hostFrame, "Show Keybind Text", posY, function()
                        return dT[k].opt2
                    end, function(v)
                        dT[k].opt2 = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Slider(hostFrame, "Font Size", posY, 8, 24, 1, function()
                        return dS[k].font
                    end, function(v)
                        dS[k].font = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Dropdown(hostFrame, "Text Position", posY, {
                        center = "Center",
                        topleft = "Top Left",
                        topright = "Top Right",
                        bottomright = "Bottom Right",
                    }, function()
                        return dD[k].position
                    end, function(v)
                        dD[k].position = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Toggle(hostFrame, "Abbreviate Text", posY, function()
                        return dT[k].opt4
                    end, function(v)
                        dT[k].opt4 = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Spacer(hostFrame, posY, 20)
                    posY = posY - hgt

                    _, hgt = W:SectionHeader(hostFrame, "LAYOUT", posY)
                    posY = posY - hgt
                    _, hgt = W:Slider(hostFrame, "Button Spacing", posY, 0, 12, 1, function()
                        return dS[k].spacing
                    end, function(v)
                        dS[k].spacing = v
                    end, nil, true)
                    posY = posY - hgt
                    _, hgt = W:Slider(hostFrame, "Global Scale", posY, 50, 200, 5, function()
                        return dS[k].scale
                    end, function(v)
                        dS[k].scale = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Toggle(hostFrame, "Lock Position", posY, function()
                        return dT[k].opt5
                    end, function(v)
                        dT[k].opt5 = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Dropdown(
                        hostFrame,
                        "Frame Style",
                        posY,
                        { modern = "Modern", classic = "Classic", minimal = "Minimal" },
                        function()
                            return dD[k].style
                        end,
                        function(v)
                            dD[k].style = v
                        end
                    )
                    posY = posY - hgt
                    _, hgt = W:Toggle(hostFrame, "Show in Combat", posY, function()
                        return dT[k].opt6
                    end, function(v)
                        dT[k].opt6 = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Spacer(hostFrame, posY, 20)
                    posY = posY - hgt

                    _, hgt = W:SectionHeader(hostFrame, "ADVANCED", posY)
                    posY = posY - hgt
                    _, hgt = W:Toggle(hostFrame, "Enable Mouseover Mode", posY, function()
                        return dT[k].opt7
                    end, function(v)
                        dT[k].opt7 = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Slider(hostFrame, "Border Thickness", posY, 1, 6, 1, function()
                        return dS[k].thickness
                    end, function(v)
                        dS[k].thickness = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Spacer(hostFrame, posY, 20)
                    posY = posY - hgt

                    _, hgt = W:SectionHeader(hostFrame, "VISIBILITY", posY)
                    posY = posY - hgt
                    _, hgt = W:Checkbox(hostFrame, "Show in Raids", posY, function()
                        return dC.showInRaid
                    end, function(v)
                        dC.showInRaid = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Checkbox(hostFrame, "Show in Dungeons", posY, function()
                        return dC.showInDungeon
                    end, function(v)
                        dC.showInDungeon = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Checkbox(hostFrame, "Show in Arena", posY, function()
                        return dC.showInArena
                    end, function(v)
                        dC.showInArena = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Checkbox(hostFrame, "Show in Battlegrounds", posY, function()
                        return dC.showInBG
                    end, function(v)
                        dC.showInBG = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Checkbox(hostFrame, "Show in Open World", posY, function()
                        return dC.showInWorld
                    end, function(v)
                        dC.showInWorld = v
                    end)
                    posY = posY - hgt
                    _, hgt = W:Checkbox(hostFrame, "Show While Mounted", posY, function()
                        return dC.showWhileMounted
                    end, function(v)
                        dC.showWhileMounted = v
                    end)
                    posY = posY - hgt

                    return math.abs(posY)
                end,
                onReset = function()
                    dT[k] = {
                        opt1 = true,
                        opt2 = false,
                        opt3 = true,
                        opt4 = false,
                        opt5 = true,
                        opt6 = false,
                        opt7 = true,
                    }
                    dS[k] = { size = 36, font = 14, opacity = 80, spacing = 4, scale = 100, thickness = 2 }
                    dD[k] = { effect = "pulse", position = "center", style = "modern" }
                    CludesUI:SelectPage(CludesUI:GetActivePage())
                end,
            }, false)
        end
    end
end)
