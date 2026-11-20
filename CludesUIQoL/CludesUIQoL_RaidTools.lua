if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQoL_RaidTools.lua -- Raid control panels (QoL: Raid Tools page)
--
--  COMPACT BAND is an opt-in layout: one resizable row with eight marker
--  symbols, clear, Ready/Role and pull controls. Target and world actions share
--  each symbol through mouse-button/modifier attributes, so every secure
--  action remains placeable mid-combat without duplicating the row.
--
--  The original Group & Pull and Markers content groups remain available as
--  legacy window modes for existing profiles and low-frequency Convert /
--  Disband access.
--
--  Group & Pull buttons are all created once at build; per-button switches and
--  0-second pull slots decide which ones LayoutGroupContent places (it re-flows
--  the survivors and is the only writer of the group content height).
--
--  SHOW MODE (p.mode) replaces the old shared-visibility system outright:
--
--    "never"  -- the default. NOTHING exists: no frames, no events, no
--                bindings, no unlock rows. True zero cost.
--    "raid"   -- auto-shows in a raid group ([group:raid] state driver).
--    "group"  -- auto-shows in any group ([group] state driver).
--    "always" -- always shown (no driver; the visible attribute just stays
--                true).
--
--  On top of the mode sits ONE unconditional gate: in a raid without leader or
--  assist the whole feature is off the screen, because the server refuses
--  every button on it there. It is raid-only (a party has no assistants) and
--  Lua-side, since no macro conditional can express it -- see AssistSuppressed
--  and RefreshAssistGate.
--
--  The Toggle Raid Tools keybind works in every active mode. Compact Band is
--  already the minimized form, so its key is a plain show/hide. Legacy modes
--  follow Default to Collapsed When Shown: with it ON the key rocks
--  between the collapsed icon and the full windows (the icon is the minimized
--  state, so hiding would be redundant); with it OFF the key is a plain
--  show/hide of the full windows, riding the override on top of the mode's
--  verdict. In the driver modes a TRANSITION reclaims control; in always
--  mode the override holds until the next settings pass.
--
--  COMBAT MODEL -- read this before changing anything here.
--
--  Marker buttons are SecureActionButtonTemplate, built once on first
--  non-never Apply and never re-anchored, re-parented or resized in combat.
--  The window shells are SecureHandlerState frames, which makes THEM
--  protected; that dictates who may change visibility, and when:
--
--    * The STATE DRIVER, the KEYBIND, the collapsed icon's expand click and
--      the collapse buttons all work in combat -- every one is a hardware
--      click or driver transition running the secure "apply" snippet.
--    * LUA does not. Show/Hide AND SetAttribute on a protected frame are
--      blocked in lockdown, so every options-driven change (mode, layout,
--      scale, position) defers behind applyPending and completes on
--      PLAYER_REGEN_ENABLED.
--
--  VISIBILITY STATE -- attributes on each shell and on the collapsed icon,
--  one writer each:
--
--    enabled       -- may this frame ever show. Written by Apply, OOC only.
--    visible       -- the driver's current verdict; false when no driver.
--                     Written by _onstate (and Apply's OOC settle).
--    override      -- "" / "show" / "hide" from the keybind; cleared by
--                     driver transitions and settings passes.
--    expanded      -- windows (true) vs collapsed icon (false). Flipped by
--                     the icon's expand click and the collapse buttons;
--                     re-seeded from startexpanded on driver transitions and
--                     on every keybind "show".
--    startexpanded -- the seed for EVERY show (driver, settings pass,
--                     keybind): NOT Default to Collapsed When Shown. Turning
--                     that toggle off is how the keybind becomes a plain
--                     full-window toggle.
--
--  "apply" folds these into Show/Hide: shells show when visible-and-expanded,
--  the icon shows when visible-and-collapsed. It is the ONLY place any of
--  these frames is shown or hidden.
--
--  SHOW AS (p.showAs) owns the window composition outright -- there are no
--  separate per-panel enable toggles:
--
--    "compact" -- one resizable band in the Group shell. Unlock Mode owns
--                 its position, width and height like any other container.
--    "one"     -- both content groups in the Group & Pull shell,
--                 which grows to fit and retitles to "Raid Tools"; ONE unlock
--                 element positioned by pos.Group. The markers holder
--                 re-parents (OOC) into the shell; holders are plain frames,
--                 so the move is an ordinary SetParent and the secure buttons
--                 never change parents themselves.
--    "two"     -- each content group in its own shell, two unlock elements.
--                 The Markers shell drops its collapse button here: one
--                 collapse control (Group & Pull's) folds the whole feature.
--    "group"   -- only the Group & Pull shell exists on screen.
--    "markers" -- only the Markers shell exists on screen; the collapsed
--                 icon anchors to IT in this mode.
--
--  One Raid Tools Scale (p.scale) covers every form: both shells and the
--  collapsed icon wear the same value, whichever windows the Show as choice
--  puts on screen.
-------------------------------------------------------------------------------
local _, mod = ...

local InCombatLockdown = InCombatLockdown
local UnitIsGroupLeader, UnitIsGroupAssistant = UnitIsGroupLeader, UnitIsGroupAssistant
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local SetRaidTargetIconTexture = SetRaidTargetIconTexture

-- Layout constants. Content geometry is decided once at build; only scale,
-- and which holders a shell carries, are user-facing.
local PANEL_W = 236
local PAD = 10
local TOPBAR_H = 25 -- the Window Skins title band
local CONTENT_TOP = TOPBAR_H + 6
local ROW_H = 22
local ROW_GAP = 4
-- Marker buttons span the full panel width regardless of this size: the row
-- step is derived from it ((PANEL_W - PAD*2 - MARKER_SZ) / 8), so a smaller
-- icon just breathes more between neighbours.
local MARKER_SZ = 23
local MARKER_LBL_H = 10
local ICON_SZ = 30
local COMPACT_H = 40
local COMPACT_W = 400
local COMPACT_MIN_W = 365
local COMPACT_MIN_H = 28
local COMPACT_PAD = 6
local COMPACT_ICON = 28
local COMPACT_GAP = 4
local COMPACT_DIVIDER_OFFSET = 5
local PULL_SLOTS = 3
local PULL_DEFAULTS = { 3, 5, 10 } -- also seeded into DB_DEFAULTS below
mod.PULL_DEFAULTS = PULL_DEFAULTS

-------------------------------------------------------------------------------
--  Window Skins look, replicated
--
--  These panels wear the same dress as the Blizz UI Enhanced window skins:
--  the modern_blizz art cover-fit behind a 0.62 black wash, a 25px black
--  title band, the AdventureMap_TopBorder frame atlas (1px gray fallback),
--  and flat 0.08-gray buttons with a 1px 0.2-gray border and a white 0.1
--  hover. The values are copied from the WSkin engine's Shell/Button recipe
--  ON PURPOSE rather than calling it: WSkin lives in CludesUIBlizzardSkin,
--  a sibling child addon the user may not have enabled, and QoL must not
--  depend on it.
-------------------------------------------------------------------------------
local SKIN_BG_TEX = "Interface\\AddOns\\CludesUI\\media\\modern_blizz.png"
-- Cover-fit crop window into the art (same numbers as the WSkin engine).
local BG_ASPECT = 561 / 433
local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
local BASE_U, BASE_V = BASE_R - BASE_L, BASE_B - BASE_T
local BORDER_ATLAS = "AdventureMap_TopBorder"
-- Theme grays (WSkin.Theme): button fill / border line.
local BTN_R, BTN_G, BTN_B, BTN_A = 0.08, 0.08, 0.08, 0.92
local BRD_R, BRD_G, BRD_B, BRD_A = 0.2, 0.2, 0.2, 1

-- Shell backdrop: art + wash + title band, and a re-crop function the layout
-- pass calls after any height change so the art never stretches.
local function SkinPanelBg(frame)
    local backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    backdrop:SetTexture(SKIN_BG_TEX)
    backdrop:SetAllPoints(frame)
    local overlayFrame = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    overlayFrame:SetColorTexture(0, 0, 0, 0.62)
    overlayFrame:SetAllPoints(frame)
    local topStrip = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    topStrip:SetColorTexture(0, 0, 0, 0.5)
    topStrip:SetPoint("TOPLEFT")
    topStrip:SetPoint("TOPRIGHT")
    topStrip:SetHeight(TOPBAR_H)
    frame._bgArt = backdrop
    frame._bgOverlay = overlayFrame
    frame._titleBar = topStrip
    frame._bgFit = function()
        local fw, fh = frame:GetSize()
        if not fw or fw == 0 or not fh or fh == 0 then
            return
        end
        local fadeAnim = fw / fh
        if fadeAnim > BG_ASPECT then
            local visV = BASE_V * (BG_ASPECT / fadeAnim)
            local trimV = (BASE_V - visV) / 2
            backdrop:SetTexCoord(BASE_L, BASE_R, BASE_T + trimV, BASE_B - trimV)
        else
            local visU = BASE_U * (fadeAnim / BG_ASPECT)
            local trimU = (BASE_U - visU) / 2
            backdrop:SetTexCoord(BASE_L + trimU, BASE_R - trimU, BASE_T, BASE_B)
        end
    end
    frame._bgFit()
end

-- Window frame: the atlas border the skins use, 1px gray line if the atlas
-- ever disappears from the client.
local function SkinPanelBorder(frame)
    local details = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BORDER_ATLAS)
    if not details then
        local fallback = CludesUI.MakeBorder(frame, BRD_R, BRD_G, BRD_B, BRD_A, CludesUI.PP)
        frame._windowBorder = fallback and fallback._frame
        return
    end
    local shade = CreateFrame("Frame", nil, frame)
    shade:SetAllPoints(frame)
    shade:SetFrameLevel(frame:GetFrameLevel() + 6)
    local texture = shade:CreateTexture(nil, "OVERLAY", nil, 7)
    texture:SetAtlas(BORDER_ATLAS)
    texture:SetAllPoints(shade)
    frame._windowBorder = shade
end

-- Button chrome: flat fill, 1px line, white hover on the HIGHLIGHT layer
-- (Buttons show that layer on mouseover natively, so no scripts).
local function SkinButtonChrome(widget)
    local fillTex = widget:CreateTexture(nil, "BACKGROUND")
    fillTex:SetColorTexture(BTN_R, BTN_G, BTN_B, BTN_A)
    fillTex:SetAllPoints(widget)
    CludesUI.MakeBorder(widget, BRD_R, BRD_G, BRD_B, BRD_A, CludesUI.PP)
    local hover = widget:CreateTexture(nil, "HIGHLIGHT")
    hover:SetColorTexture(1, 1, 1, 0.1)
    hover:SetAllPoints(widget)
end

-- The collapsed-state button IS this image: no chrome, no border, no inset.
local COLLAPSED_ICON_TEX = "Interface\\AddOns\\CludesUI\\media\\icons\\raid-tools.png"

-- Canonical section list. Build order, stack order, DB key set, window titles
-- and unlock-mover labels all derive from this one table.
--
-- `label` reaches CludesUI.L as a variable, which the static key extractor
-- cannot see -- the documented arrangement for exactly this case (see the
-- header of .tools/extract-locale-keys.sh); the in-game /cuiloc harvester picks
-- them up, the same way every widget label in the suite is already handled.
local SECTIONS = {
    { key = "Group", label = "Group & Pull" },
    { key = "Markers", label = "Markers" },
}

-- One-window title; reaches L as a variable like the section labels.
local COMBINED_LABEL = "Raid Tools"

-- Prefix for this feature's unlock-mode element keys. Used both to register
-- them and to ask the anchor system about them, so the two cannot drift.
-- These keys persist in saved anchors -- renaming breaks existing links.
local UNLOCK_KEY = "CUI_RaidTools_"
local COMPACT_UNLOCK_KEY = UNLOCK_KEY .. "Compact"

local SECTION_KEYS = {}
local SECTION_LABEL = {}
for _, defaults in ipairs(SECTIONS) do
    SECTION_KEYS[#SECTION_KEYS + 1] = defaults.key
    SECTION_LABEL[defaults.key] = defaults.label
end

local saved
local applyPending -- true when combat blocked an Apply()
local previewOn = false -- Raid Tools settings page is in front (see ApplyVisibility)
local lastSuppressed -- assist gate verdict currently ON SCREEN (see AssistSuppressed)
local toggleBtn -- keybind target; also the out-of-combat path
local runState = {} -- Quick Fire's lazily-created secure state
local sectionList = {} -- key -> shell frame
local shellTitle = {} -- key -> title fontstring
local groupFrame, markersHolder, compactFrame -- plain content holders (see header)
local iconButton -- collapsed-state square
-- Markers are fixed at build; the Group & Pull height follows the settings and
-- is re-computed by LayoutGroupContent on every Apply.
local GROUP_CONTENT_H, MARKERS_CONTENT_H
local Apply -- forward: the event handler closes over it

-- ONE representation of each secure decision, run from both paths.
--
-- The keybind clicks the button, which is the only thing that works during combat. Out
-- of combat the same snippet is run through SecureHandlerExecute instead of being
-- re-implemented in Lua. CUI_RaidFrames_BossFrames.lua does exactly this, for exactly this
-- reason: the driver manager only fires the attribute handlers on value CHANGES, so a
-- reapply with unchanged states would otherwise never run.
local RUN_APPLY = [[ self:RunAttribute("apply") ]]

-- The keybind's job depends on Default to Collapsed When Shown:
--
--   ON  -- the icon IS the minimized state, so hiding would be redundant.
--          The key rocks between the icon and the full windows (collapse /
--          expand); from fully hidden it shows the windows directly, since
--          the press means the tools are wanted NOW.
--   OFF -- a plain show/hide of the full windows.
--
-- The branch is read off the icon's startexpanded (false = collapse mode),
-- so the snippet needs no config attribute of its own.
local TOGGLE_SNIPPET = [[
    local n = self:GetAttribute("count") or 0
    local icon = self:GetFrameRef("icon")
    local anyWin, iconShown = false, false
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f and f:IsShown() then anyWin = true end
    end
    if icon and icon:IsShown() then iconShown = true end

    local collapseMode = icon and not icon:GetAttribute("startexpanded")
    if collapseMode then
        if anyWin then
            -- Windows up: collapse to the icon. Visibility is untouched, so
            -- whatever put the windows up (driver or override) keeps the icon
            -- up in their place.
            for i = 1, n do
                local f = self:GetFrameRef("s" .. i)
                if f then
                    f:SetAttribute("expanded", false)
                    f:RunAttribute("apply")
                end
            end
            icon:SetAttribute("expanded", false)
            icon:RunAttribute("apply")
        else
            -- Icon up, or nothing up: expand to the windows. The override
            -- also covers the fully-hidden case (driver currently saying no).
            for i = 1, n do
                local f = self:GetFrameRef("s" .. i)
                if f then
                    f:SetAttribute("override", "show")
                    f:SetAttribute("expanded", true)
                    f:RunAttribute("apply")
                end
            end
            icon:SetAttribute("override", "show")
            icon:SetAttribute("expanded", true)
            icon:RunAttribute("apply")
        end
        return
    end

    local ov
    if anyWin or iconShown then ov = "hide" else ov = "show" end
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f then
            f:SetAttribute("override", ov)
            if ov == "show" then
                f:SetAttribute("expanded", f:GetAttribute("startexpanded"))
            end
            f:RunAttribute("apply")
        end
    end
    if icon then
        icon:SetAttribute("override", ov)
        if ov == "show" then
            icon:SetAttribute("expanded", icon:GetAttribute("startexpanded"))
        end
        icon:RunAttribute("apply")
    end
]]

-- Expand (the icon's own click) and collapse (the shells' corner buttons):
-- flip `expanded` everywhere and re-apply. Both run in combat as hardware
-- clicks on secure buttons.
local EXPAND_SNIPPET = [[
    local n = self:GetAttribute("count") or 0
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f then
            f:SetAttribute("expanded", true)
            f:RunAttribute("apply")
        end
    end
    self:SetAttribute("expanded", true)
    self:RunAttribute("apply")
]]
local COLLAPSE_SNIPPET = [[
    local n = self:GetAttribute("count") or 0
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f then
            f:SetAttribute("expanded", false)
            f:RunAttribute("apply")
        end
    end
    local icon = self:GetFrameRef("icon")
    if icon then
        icon:SetAttribute("expanded", false)
        icon:RunAttribute("apply")
    end
]]

-- Every fontstring is registered on the OUR-frame that owns it (`_fonts`), and
-- ApplyFonts walks the small fixed owner list -- no module-level registry to keep in
-- sync with frame lifetime. MakeFont (like every options-panel helper) hardcodes the
-- options-panel font; on-screen text has to resolve through GetFontPath instead, or
-- these panels would be the only ones in the suite ignoring the Global Font setting.
local FONT_KEY = "extras" -- QoL's key in CludesUI._addonKeyToFolder
local fontOwners = {} -- filled at build: shells + holders
-- family: a font family string (a text that shows players' names), which takes
-- every font through SetFontFamily, never a plain SetFont
local function TrackFont(markerOwner, fontStr, size, family)
    local t = markerOwner._fonts
    if not t then
        t = {}
        markerOwner._fonts = t
    end
    t[#t + 1] = { fs = fontStr, size = size, family = family }
    return fontStr
end
local function ApplyFonts()
    local filePath = CludesUI.GetFontPath(FONT_KEY)
    if not filePath then
        return
    end
    for _, markerOwner in ipairs(fontOwners) do
        local t = markerOwner._fonts
        if t then
            for _, entry in ipairs(t) do
                if entry.family then
                    CludesUI.SetFontFamily(entry.fs, filePath, entry.size, "", false)
                else
                    local _, _, flags = entry.fs:GetFont()
                    entry.fs:SetFont(filePath, entry.size, flags or "")
                end
            end
        end
    end
end

local groupBtns = {} -- plain buttons, enable-gated on assist
local markerButtons = {} -- secure buttons, dimmed on assist
local pullButtons = {} -- fixed set of 3; only the ones above 0s show
-- Created once at build; the layout pass decides which reach the screen. Ready
-- Check has no switch by design.
local readyButton, roleButton, convertButton, disbandButton, stopButton, buffButton
local compactReady, compactPullButton, compactDivider
local compactMarkers = {}
local ShowCompactTip, HideCompactTip

-- Both marker rows draw Blizzard's own raid target sheet -- the texture the
-- rest of the suite already uses for markers, in nameplates and raid frames.
local MARKER_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- The sheet's SYMBOL order (1 Star, 2 Circle, 3 Diamond, 4 Triangle, 5 Moon, 6 Square,
-- 7 Cross, 8 Skull) is NOT the WORLD marker ID order (1 Blue, 2 Green, 3 Purple, 4 Red,
-- 5 Yellow, 6 Orange, 7 Silver, 8 White). Each flare carries its symbol, so the button
-- shows the symbol and this maps it to the flare that actually wears it -- without it,
-- clicking Star (symbol 1) dropped the BLUE flare (world ID 1).
local SYMBOL_TO_WORLD = { 5, 6, 3, 2, 7, 1, 4, 8 }
local MARKER_NAME = {
    "Star",
    "Circle",
    "Diamond",
    "Triangle",
    "Moon",
    "Square",
    "Cross",
    "Skull",
}
local COMPACT_MARKER_TIP_ROWS = {
    { "Left Click", "Toggle target marker" },
    { "Right Click", "Place world marker" },
    { "Shift + Left Click", "Clear target marker" },
    { "Shift + Right Click", "Clear world marker" },
}
local COMPACT_CLEAR_TIP_ROWS = {
    { "Left Click", "Clear target marker" },
    { "Right Click", "Clear all world markers" },
}
-- One slice of the shared CludesUIQoLDB profile, the same arrangement
-- BattleRes and Bloodlust use: each QoL feature merges its own defaults into
-- the SAME profile table under its own key.
local DB_DEFAULTS = {
    profile = {
        raidTools = {
            -- "never" | "raid" | "group" | "always" (see header). Never = the
            -- feature does not exist at runtime.
            mode = "never",
            -- Toggle Raid Tools key ("SHIFT-R" form). Profile-stored and applied
            -- as an override binding, exactly like Action Bars' toggleVisKey.
            toggleKey = false,
            -- Opt-in world-marker bindings. Empty defaults mean enabling Quick
            -- Fire alone never claims a key.
            quickFire = false,
            quickFirePlaceKey = false,
            quickFireUndoKey = false,
            quickFireClearKey = false,
            -- Default to Collapsed When Shown: EVERY show (driver, settings pass,
            -- keybind) starts as the small icon; click it to expand. Turning this
            -- off makes the keybind a plain full-window toggle.
            collapsedIcon = true,
            -- "compact" | "one" | "two" | "group" | "markers" (see header). The single owner
            -- of window composition; there are no per-panel enable toggles.
            showAs = "one",
            compactWidth = COMPACT_W,
            compactHeight = COMPACT_H,
            -- One scale for the whole feature: whichever windows the Show as
            -- choice puts on screen (and the collapsed icon) all wear it.
            scale = 1,
            -- Three slots is a LAYOUT choice (they fill one row beside Stop), not a
            -- security constraint -- the pull buttons are plain, only the marker buttons
            -- are secure. Growing the count later means growing the panel, nothing more.
            -- 0 = slot hidden; all three at 0 removes the pull row, Stop included.
            pullTimes = { PULL_DEFAULTS[1], PULL_DEFAULTS[2], PULL_DEFAULTS[3] },
            -- Per-button switches (Ready Check has none); hidden buttons close up.
            showRoleCheck = true,
            showConvert = true,
            showDisband = true,
            -- Raid Buff Check (CludesUIQoL_RaidBuffCheck.lua): the feature, its
            -- ready check trigger and window state. Off by default.
            buffCheck = false,
            buffCheckOnReady = true,
            buffCheckOnlyMissing = true,
            buffCheckRuneRequired = true,
            buffCheckVantusRequired = false,
            -- Opt-in Buff Check group button (needs buffCheck).
            showBuffCheck = false,
            -- Per-section: pos[key] = { point, relPoint, x, y }
            pos = {},
        },
    },
}

-- Our slice of the shared QoL profile, re-derived on every read -- the same accessor
-- BattleRes and MovementAlert use. Deliberately NOT cached: a profile switch replaces
-- the whole profile table, and a cached pointer would leave the event handler, the
-- slash command and the unlock callbacks writing into an orphaned table.
--
-- A PURE READ, with no `or {}` seeding. Spec Overrides captures a page by
-- swapping the profile tables for read-tracking proxies: reading a table value
-- hands back a NEW proxy, and writing goes through to the real table. So
-- `t.x = t.x or {}` stores a proxy inside the real table, the next call wraps
-- that proxy in another, and reading through the stack overflows the C stack.
-- DB_DEFAULTS already guarantees the slice exists; the seeding was never
-- needed and is actively harmful here.
local function P()
    return saved and saved.profile and saved.profile.raidTools
end
mod.RaidToolsProfile = P

local function ShowMode()
    local profile = P()
    return (profile and profile.mode) or "never"
end

-- The Show as choice, normalized: any unset/unknown value preserves the
-- original One Window behavior. Compact Band is selected explicitly.
local function ShowAs()
    local profile = P()
    local val = profile and profile.showAs
    if val ~= "compact" and val ~= "one" and val ~= "two" and val ~= "group" and val ~= "markers" then
        val = "one"
    end
    return val
end
mod.ShowAs = ShowAs

local function CompactWidth()
    local profile = P()
    return math.max(COMPACT_MIN_W, (profile and profile.compactWidth) or COMPACT_W)
end

local function CompactHeight()
    local profile = P()
    return math.max(COMPACT_MIN_H, (profile and profile.compactHeight) or COMPACT_H)
end

local function WindowScale()
    local profile = P()
    return (profile and profile.scale) or 1
end

-------------------------------------------------------------------------------
--  Suite-styled widgets
--
--  Window-skin chrome (SkinPanelBg/Border, SkinButtonChrome) plus the suite
--  font pipeline (GetFontPath via TrackFont), so the panels read as skinned
--  Blizzard windows rather than stock Blizzard UI or the options panel.
-------------------------------------------------------------------------------

-- Enable state without touching the button's own scripts: dimming the whole
-- frame and cutting mouse input is both
-- simpler and immune to a hover re-lighting a disabled control.
local function SetButtonEnabled(widget, enabled)
    widget:SetAlpha(enabled and 1 or 0.35)
    widget:EnableMouse(enabled)
end

-- Action button in the Window Skins style: flat fill, 1px line, white hover,
-- white label (WSkin.Button + WhiteButtonLabel, replicated). `needsLeader`
-- narrows the gate from assist to leader.
local function MakeGroupButton(hostFrame, textValue, width, onClick, needsLeader)
    local widget = CreateFrame("Button", nil, hostFrame)
    widget:SetSize(width, ROW_H)
    SkinButtonChrome(widget)
    local labelFS = TrackFont(hostFrame, CludesUI.MakeFont(widget, 11, nil, 1, 1, 1), 11)
    labelFS:SetPoint("CENTER")
    if textValue ~= "" then
        labelFS:SetText(CludesUI.L(textValue))
    end
    widget:SetScript("OnClick", onClick)
    widget._lbl = labelFS
    widget.needsLeader = needsLeader
    groupBtns[#groupBtns + 1] = widget
    return widget
end

-- Secure marker button. Action attributes are set here, at build, and never
-- touched again -- that is what makes them usable in combat.
--
-- The attribute names are SecureActionButtonTemplate's own contract, so two
-- details are dictated rather than chosen:
--   * slash commands are read from the SLASH_* globals. They are localized --
--     writing "/tm" or "/cwm" as a literal breaks every non-English client,
--     including this one.
--   * the worldmarker type takes `marker` as a STRING, and splits placing from
--     clearing across action1 and action2.
local function MakeMarkerButton(hostFrame, index, kindName)
    local widget = CreateFrame("Button", nil, hostFrame, "SecureActionButtonTemplate")
    local isCompact = kindName == "compact" or kindName == "compact-clear"
    local size = isCompact and COMPACT_ICON or MARKER_SZ
    widget:SetSize(size, size)
    -- One phase only: the "!" prefix toggles the marker, so firing on both the
    -- down and the up would set it and immediately clear it again. useOnKeyDown
    -- is pinned because left unset it follows the ActionButtonUseKeyDown CVar,
    -- and at 0 the secure handler acts on the up phase we never register --
    -- every marker button goes dead.
    widget:RegisterForClicks("AnyDown")
    widget:SetAttribute("useOnKeyDown", true)

    local iconTex = widget:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    widget.icon = iconTex

    if kindName == "compact" then
        local worldMarkerId = SYMBOL_TO_WORLD[index]
        -- One symbol, four combat-safe actions. The ordinary clicks perform
        -- the frequent actions; Shift exposes their explicit clear variants.
        widget:SetAttribute("type1", "macro")
        widget:SetAttribute("macrotext1", (SLASH_TARGET_MARKER1 or "/tm") .. " !" .. index)
        widget:SetAttribute("type2", "worldmarker")
        widget:SetAttribute("marker2", tostring(worldMarkerId))
        widget:SetAttribute("action2", "set")
        widget:SetAttribute("shift-type1", "macro")
        widget:SetAttribute("shift-macrotext1", (SLASH_TARGET_MARKER1 or "/tm") .. " 0")
        widget:SetAttribute("shift-type2", "worldmarker")
        widget:SetAttribute("shift-marker2", tostring(worldMarkerId))
        widget:SetAttribute("shift-action2", "clear")
        widget._worldID = worldMarkerId
    elseif kindName == "compact-clear" then
        widget:SetAttribute("type1", "macro")
        widget:SetAttribute("macrotext1", (SLASH_TARGET_MARKER1 or "/tm") .. " 0")
        widget:SetAttribute("type2", "macro")
        widget:SetAttribute("macrotext2", (SLASH_CLEAR_WORLD_MARKER1 or "/cwm") .. " " .. (ALL or "All"))
    elseif kindName == "target" then
        -- Left: toggle this marker on the target. Right: clear it.
        widget:SetAttribute("type", "macro")
        if index == 0 then
            widget:SetAttribute("macrotext", (SLASH_TARGET_MARKER1 or "/tm") .. " 0")
        else
            widget:SetAttribute("macrotext1", (SLASH_TARGET_MARKER1 or "/tm") .. " !" .. index)
            widget:SetAttribute("macrotext2", (SLASH_TARGET_MARKER1 or "/tm") .. " 0")
        end
    elseif index == 0 then
        -- Clear-all is a macro, not a worldmarker action: the attribute form
        -- clears one index at a time.
        widget:SetAttribute("type", "macro")
        widget:SetAttribute("macrotext", (SLASH_CLEAR_WORLD_MARKER1 or "/cwm") .. " " .. (ALL or "All"))
    else
        widget:SetAttribute("type", "worldmarker")
        -- `index` is the SYMBOL the button shows; the attribute wants the
        -- world-marker ID of the flare carrying that symbol (see the map).
        widget:SetAttribute("marker", tostring(SYMBOL_TO_WORLD[index]))
        widget:SetAttribute("action1", "set")
        widget:SetAttribute("action2", "clear")
    end

    if index == 0 then
        iconTex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    else
        iconTex:SetTexture(MARKER_SHEET)
        SetRaidTargetIconTexture(iconTex, index)
    end

    -- No chrome on the marker grid: the symbols read best bare. Hover is an
    -- opacity lift on the icon itself (80% resting, 100% under the cursor),
    -- and the no-assist dim keeps priority -- a 0.4-dimmed button does not
    -- brighten on hover, so the dim never lies. _baseAlpha is ours to write
    -- (our CreateFrame'd button); RefreshPermissions owns its value.
    iconTex:SetAlpha(0.8)
    widget._baseAlpha = 0.8
    if kindName == "compact" then
        -- The "marker is down" underline rides its own child FRAME: its
        -- visibility follows an answer that can be secret (see
        -- RefreshCompactMarkerState), and SetAlphaFromBoolean -- the
        -- secret-safe switch -- renders nothing on a texture. A plain frame
        -- takes no mouse input, so the host never eats the button's clicks.
        local markerOwner = CreateFrame("Frame", nil, widget)
        markerOwner:SetAllPoints(widget)
        markerOwner:SetAlpha(0)
        local isActive = markerOwner:CreateTexture(nil, "OVERLAY")
        isActive:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 2, -2)
        isActive:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -2, -2)
        isActive:SetHeight(2)
        local ar, ag, ab = 0.30, 0.79, 0.94
        if CludesUI.GetAccentColor then
            ar, ag, ab = CludesUI.GetAccentColor()
        end
        isActive:SetColorTexture(ar, ag, ab, 0.95)
        widget._activeHost = markerOwner
    end
    widget:SetScript("OnEnter", function(self)
        if (self._baseAlpha or 0.8) >= 0.8 then
            self.icon:SetAlpha(1)
        end
        if isCompact and ShowCompactTip then
            if kindName == "compact-clear" then
                ShowCompactTip(self, "Clear Markers", COMPACT_CLEAR_TIP_ROWS)
            else
                ShowCompactTip(self, MARKER_NAME[index] or "Raid Marker", COMPACT_MARKER_TIP_ROWS)
            end
        end
    end)
    widget:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(self._baseAlpha or 0.8)
        if isCompact and HideCompactTip then
            HideCompactTip(self)
        end
    end)

    markerButtons[#markerButtons + 1] = widget
    return widget
end

-------------------------------------------------------------------------------
--  Permission gating
-------------------------------------------------------------------------------

-- Ready check, role check, countdown and markers all require lead or assist.
--
-- Solo counts as permitted. You are the only member, so nothing is being taken from
-- anyone, and the game already no-ops whatever does not apply outside a group -- gating
-- it ourselves would only make the panels dead on a target dummy for no reason.
local function HasAssist()
    if not IsInGroup() then
        return true
    end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function IsLeader()
    if not IsInGroup() then
        return true
    end
    return UnitIsGroupLeader("player")
end

-- The Raid Buff Check window (CludesUIQoL_RaidBuffCheck.lua) wears these panels'
-- dress and font. Text: a font string on parent in the QoL font, kept current by
-- ApplyFonts through owner (registered with AddFontOwner).
mod.RT = {
    TOPBAR_H = TOPBAR_H,
    SkinPanelBg = SkinPanelBg,
    SkinPanelBorder = SkinPanelBorder,
    SkinButtonChrome = SkinButtonChrome,
    HasAssist = HasAssist,
    AddFontOwner = function(markerOwner)
        fontOwners[#fontOwners + 1] = markerOwner
    end,
    Text = function(markerOwner, hostFrame, size, red, green, blue)
        local fontStr = TrackFont(markerOwner, CludesUI.MakeFont(hostFrame, size, nil, red, green, blue), size)
        local filePath = CludesUI.GetFontPath(FONT_KEY)
        if filePath then
            local _, _, flags = fontStr:GetFont()
            fontStr:SetFont(filePath, size, flags or "")
        end
        return fontStr
    end,
    -- Text for a player's name: the same font as a font family, which draws the
    -- scripts the font lacks (no outline, no shadow, as Text has)
    NameText = function(markerOwner, hostFrame, size, red, green, blue)
        local fontStr = TrackFont(markerOwner, hostFrame:CreateFontString(nil, "OVERLAY"), size, true)
        CludesUI.SetFontFamily(
            fontStr,
            CludesUI.GetFontPath(FONT_KEY) or CludesUI.EXPRESSWAY,
            size,
            "",
            false
        )
        if red then
            fontStr:SetTextColor(red, green, blue, 1)
        end
        return fontStr
    end,
}

-- In a RAID, every control on the panel needs leader or assist: ready check,
-- role check, the countdown, convert, disband and the marker buttons are all
-- refused by the server without it. So the feature steps off the screen there
-- instead of sitting around fully dimmed.
--
-- Raid only, deliberately. A party has no assistants -- UnitIsGroupAssistant
-- is false for everyone in one -- so the same test would hide the panel from
-- every non-leader in a 5-man, where marking is open to all of them.
--
-- There is no macro conditional for leader/assist, so NO state driver can
-- express this: the gate is Lua's, it lands on the enabled attribute, and a
-- promotion mid-combat is picked up on PLAYER_REGEN_ENABLED like every other
-- Lua-side change (see the combat model in the header).
local function AssistSuppressed()
    if previewOn then
        return false
    end -- configuring the thing beats hiding it
    return IsInRaid() and not HasAssist()
end

-- An optional button's switch, defaulting to shown for an unset profile.
local function ButtonShown(toolKey)
    local profile = P()
    return not profile or profile[toolKey] ~= false
end

-- The Buff Check button needs Raid Buff Check on (and a retail client: the
-- feature file publishes ns.ToggleBuffCheck only there).
local function BuffCheckShown()
    local profile = P()
    return profile and profile.showBuffCheck == true and profile.buffCheck == true and mod.ToggleBuffCheck ~= nil
end

local function ToggleBuffCheck()
    if mod.ToggleBuffCheck then
        mod.ToggleBuffCheck()
    end
end

-- The pull durations worth a button, in slot order. 0 (and anything below it)
-- means the user turned that slot off.
local function VisiblePullTimes()
    local timeList = (P() and P().pullTimes) or {}
    local result = {}
    for index = 1, PULL_SLOTS do
        local seconds = timeList[index]
        if seconds == nil then
            seconds = PULL_DEFAULTS[index]
        end
        if seconds and seconds > 0 then
            result[#result + 1] = seconds
        end
    end
    return result
end

-- GROUP_ROSTER_UPDATE is one of the chattiest events in a raid -- it bursts on
-- every join, leave and zone-in -- while assist/leader/raid status changes a
-- handful of times a night. Memo the three inputs and bail when none moved.
-- `force` is for callers that have just built or rebuilt the buttons.
local lastAssist, lastLeader, lastRaid
local function RefreshPermissions(force)
    local hasAssist, leader, raid = HasAssist(), IsLeader(), IsInRaid()
    if not force and hasAssist == lastAssist and leader == lastLeader and raid == lastRaid then
        return
    end
    lastAssist, lastLeader, lastRaid = hasAssist, leader, raid

    for _, btn in ipairs(groupBtns) do
        local allowed
        if btn.ungated then
            allowed = true
        elseif btn.needsLeader then
            allowed = leader
        else
            allowed = hasAssist
        end
        SetButtonEnabled(btn, allowed)
    end

    -- Secure buttons: cosmetic only, never Enable/Disable (see header).
    -- 0.8 is the grid's resting opacity (hover lifts to 1); 0.4 is the
    -- no-assist dim, which also suppresses the hover lift.
    for _, btn in ipairs(markerButtons) do
        btn._baseAlpha = hasAssist and 0.8 or 0.4
        btn.icon:SetAlpha(btn._baseAlpha)
    end

    if convertButton then
        convertButton._lbl:SetText(raid and CludesUI.L("Convert to Party") or CludesUI.L("Convert to Raid"))
    end
end

-------------------------------------------------------------------------------
--  Pull timer
--
--  A pull has to reach the whole raid, not just this client, so the countdown
--  is handed to whichever boss mod is loaded through its published slash
--  handler -- that is the thing that broadcasts the timer to everyone else --
--  and Blizzard's own countdown runs on top for anyone without one.
--
--  Blizzard's countdown travels through chat, so the client refuses it during
--  combat. The boss mod handoff happens first for that reason: it still works
--  there, and losing the in-game countdown is better than losing both.
-------------------------------------------------------------------------------

local function BossModPullHandler()
    return SlashCmdList.BIGWIGSPULL or SlashCmdList.DEADLYBOSSMODSPULL
end

local function ChatLocked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function StartPull(seconds)
    local handler = BossModPullHandler()
    if handler then
        handler(tostring(seconds))
    end
    if ChatLocked() then
        CludesUI.Print(
            CludesUI.COLOR_CODES.BRAND
                .. "CludesUI:|r "
                .. CludesUI.L(
                    "In-game countdown unavailable in combat; the boss mod pull timer still started."
                )
        )
        return
    end
    C_PartyInfo.DoCountdown(seconds)
end

local function StopPull()
    local handler = BossModPullHandler()
    if handler then
        handler("0")
    end
    if not ChatLocked() then
        C_PartyInfo.DoCountdown(0)
    end
end

-------------------------------------------------------------------------------
--  Group actions
-------------------------------------------------------------------------------

local function DisbandGroup()
    if not IsLeader() then
        return
    end
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            local label = GetRaidRosterInfo(index)
            if label and label ~= UnitName("player") then
                C_PartyInfo.UninviteUnit(label)
            end
        end
    else
        for index = 1, GetNumSubgroupMembers() do
            local label = UnitName("party" .. index)
            if label then
                C_PartyInfo.UninviteUnit(label)
            end
        end
    end
    C_PartyInfo.LeaveParty()
end

-- The suite's own confirm dialog, not StaticPopup: CONTRIBUTING is explicit
-- that confirmations use ShowConfirmPopup, and it is the one that inherits the
-- panel skin and the scale registry.
local function ConfirmDisband()
    CludesUI:ShowConfirmPopup({
        title = "Disband Group",
        message = "Disband the group?",
        confirmText = "Disband",
        cancelText = "Cancel",
        onConfirm = DisbandGroup,
    })
end

-------------------------------------------------------------------------------
--  Frames (built once, on first non-never Apply -- secure children forbid
--  rebuilding)
-------------------------------------------------------------------------------

-- One secure window shell. Returns the frame; content lives in the plain
-- holders, so the shell owns only chrome (bg, border, title, collapse button)
-- and the visibility state machine.
local function MakeShell(toolKey)
    local frame = CreateFrame("Frame", "CludesUIRaidTools" .. toolKey, UIParent, "SecureHandlerStateTemplate")
    frame:SetWidth(PANEL_W)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- The Window Skins dress (see the block above).
    SkinPanelBg(frame)
    SkinPanelBorder(frame)

    -- Visibility state: see the header. "apply" is the ONLY place this frame
    -- is shown or hidden.
    frame:SetAttribute("enabled", true)
    frame:SetAttribute("visible", false)
    frame:SetAttribute("override", "")
    frame:SetAttribute("expanded", true)
    frame:SetAttribute("startexpanded", true)
    frame:SetAttribute(
        "apply",
        [[
        if not self:GetAttribute("enabled") then
            self:Hide()
            return
        end
        local ov = self:GetAttribute("override")
        local vis
        if ov == "show" then
            vis = true
        elseif ov == "hide" then
            vis = false
        else
            vis = self:GetAttribute("visible")
        end
        if vis and self:GetAttribute("expanded") then
            self:Show()
        else
            self:Hide()
        end
    ]]
    )
    -- A driver transition is a context change: it reclaims control from any manual
    -- override and re-seeds the collapsed/expanded form. The icon has no state template
    -- of its own (click templates do not dispatch _onstate), so each shell fans the
    -- verdict out to it -- both shells stamping the same values is idempotent.
    frame:SetAttribute(
        "_onstate-cuirt_vis",
        [[
        local vis = (newstate == "show")
        self:SetAttribute("visible", vis)
        self:SetAttribute("override", "")
        self:SetAttribute("expanded", self:GetAttribute("startexpanded"))
        self:RunAttribute("apply")
        local icon = self:GetFrameRef("icon")
        if icon then
            icon:SetAttribute("visible", vis)
            icon:SetAttribute("override", "")
            icon:SetAttribute("expanded", self:GetAttribute("startexpanded"))
            icon:RunAttribute("apply")
        end
    ]]
    )

    -- White title, vertically centered in the black band (the skins' title
    -- treatment; the accent stays on interactions, not chrome).
    local fontStr = TrackFont(frame, CludesUI.MakeFont(frame, 12, nil, 1, 1, 1), 12)
    fontStr:SetPoint("LEFT", frame, "TOPLEFT", PAD, -TOPBAR_H / 2)
    fontStr:SetText(CludesUI.L(SECTION_LABEL[toolKey]))
    shellTitle[toolKey] = fontStr

    -- Collapse button: small secure corner control riding the title band,
    -- only meaningful (and only shown -- ApplyLayout owns that) while Default
    -- to Collapsed Icon is on. Wears the skins' button chrome.
    local colour = CreateFrame("Button", nil, frame, "SecureHandlerClickTemplate")
    colour:SetSize(14, 14)
    colour:SetPoint("RIGHT", frame, "TOPRIGHT", -6, -TOPBAR_H / 2)
    colour:RegisterForClicks("AnyDown")
    SkinButtonChrome(colour)
    local colFs = TrackFont(frame, CludesUI.MakeFont(colour, 14, nil, 1, 1, 1), 14)
    colFs:SetPoint("CENTER", colour, "CENTER", 0, 1)
    colFs:SetText("-")
    colFs:SetAlpha(0.7)
    colour:SetScript("OnEnter", function()
        colFs:SetAlpha(1)
    end)
    colour:SetScript("OnLeave", function()
        colFs:SetAlpha(0.7)
    end)
    colour:SetAttribute("_onclick", COLLAPSE_SNIPPET)
    frame._collapseBtn = colour

    sectionList[toolKey] = frame
    fontOwners[#fontOwners + 1] = frame
    return frame
end

-- Places the Group & Pull buttons per the settings and is the ONLY writer of
-- GROUP_CONTENT_H. Plain frames only, run from build and Apply (out of combat);
-- must run BEFORE ApplyLayout, which sizes the shells from that height.
local function LayoutGroupContent()
    if not groupFrame then
        return
    end
    local frame = groupFrame

    -- Row plan: two action buttons per row in fixed order; hidden buttons close
    -- the gap, a lone button takes the full width.
    local rowList, pair = {}, {}
    local function Add(b)
        pair[#pair + 1] = b
        if #pair == 2 then
            rowList[#rowList + 1] = pair
            pair = {}
        end
    end
    Add(readyButton)
    if ButtonShown("showRoleCheck") then
        Add(roleButton)
    end
    if BuffCheckShown() then
        Add(buffButton)
    end
    if ButtonShown("showConvert") then
        Add(convertButton)
    end
    if ButtonShown("showDisband") then
        Add(disbandButton)
    end
    if #pair > 0 then
        rowList[#rowList + 1] = pair
    end

    -- Pull row: surviving durations move onto the leading buttons (the click
    -- closure reads b.secs), Stop last; no durations = no row at all.
    local timeList = VisiblePullTimes()
    if #timeList > 0 then
        local pull = {}
        for index, seconds in ipairs(timeList) do
            local b = pullButtons[index]
            b.secs = seconds
            b._lbl:SetText(tostring(seconds))
            pull[index] = b
        end
        pull[#pull + 1] = stopButton
        rowList[#rowList + 1] = pull
    end

    -- Hide all, then show only what the plan placed.
    for _, btn in ipairs(groupBtns) do
        btn:Hide()
    end

    local posY = 0
    for _, line in ipairs(rowList) do
        local num = #line
        local wid = (PANEL_W - PAD * 2 - ROW_GAP * (num - 1)) / num
        for index, b in ipairs(line) do
            b:SetWidth(wid)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (wid + ROW_GAP) * (index - 1), posY)
            b:Show()
        end
        posY = posY - ROW_H - ROW_GAP
    end
    posY = posY + ROW_GAP -- the last row's trailing gap is not content

    GROUP_CONTENT_H = -posY
    frame:SetHeight(GROUP_CONTENT_H)
end

-- Group & Pull content, in its own plain holder so one-window mode can treat
-- it uniformly with the markers holder. Creation only -- the buttons are born
-- unplaced at full-row width, and LayoutGroupContent puts them where the
-- settings say (MakeGroupButton runs labels through L itself).
local function BuildGroupContent()
    groupFrame = CreateFrame("Frame", nil, sectionList.Group)
    groupFrame:SetWidth(PANEL_W)
    fontOwners[#fontOwners + 1] = groupFrame
    local frame = groupFrame
    local full = PANEL_W - PAD * 2

    readyButton = MakeGroupButton(frame, "Ready Check", full, function()
        DoReadyCheck()
    end)
    roleButton = MakeGroupButton(frame, "Role Check", full, function()
        InitiateRolePoll()
    end)
    buffButton = MakeGroupButton(frame, "Buff Check", full, ToggleBuffCheck)
    buffButton.ungated = true -- only reads auras: needs no leader or assist

    convertButton = MakeGroupButton(frame, "Convert to Raid", full, function()
        if IsInRaid() then
            C_PartyInfo.ConvertToParty()
        else
            C_PartyInfo.ConvertToRaid()
        end
    end, true)

    disbandButton = MakeGroupButton(frame, "Disband", full, function()
        ConfirmDisband()
    end, true)

    for index = 1, PULL_SLOTS do
        -- The pull duration lives on the button and changes at runtime, so
        -- the click reads it through the closure.
        local b
        b = MakeGroupButton(frame, "", full, function()
            StartPull(b.secs)
        end)
        pullButtons[index] = b
    end
    stopButton = MakeGroupButton(frame, "Stop", full, StopPull)

    -- A height right away: BuildAll has callers (the slash command, unlock
    -- mode) that reach the shells without going through Apply.
    LayoutGroupContent()
end

-- Row order matches how they are used: unit markers first, ground markers
-- under them. Labels reach L as variables (see the SECTIONS comment).
local MARKER_ROWS = {
    { kind = "target", label = "Target Markers" },
    { kind = "world", label = "World Markers" },
}

local function BuildMarkersContent()
    markersHolder = CreateFrame("Frame", nil, sectionList.Markers)
    markersHolder:SetWidth(PANEL_W)
    fontOwners[#fontOwners + 1] = markersHolder
    local frame = markersHolder
    local posY = 0

    -- 8 markers + a clear button per row, evenly spread across the width.
    local step = (PANEL_W - PAD * 2 - MARKER_SZ) / 8
    for region, line in ipairs(MARKER_ROWS) do
        local labelFS = TrackFont(frame, CludesUI.MakeFont(frame, 9, nil, 1, 1, 1), 9)
        labelFS:SetAlpha(0.55)
        labelFS:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, posY)
        labelFS:SetText(CludesUI.L(line.label))
        posY = posY - MARKER_LBL_H - 2

        for index = 0, 8 do
            local widget = MakeMarkerButton(frame, index == 8 and 0 or (index + 1), line.kind)
            widget:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + step * index, posY)
        end
        posY = posY - MARKER_SZ
        if region < #MARKER_ROWS then
            posY = posY - ROW_GAP * 2
        end
    end

    MARKERS_CONTENT_H = -posY
    frame:SetHeight(MARKERS_CONTENT_H)
end

-- Compact Band uses its own holder so the existing window layouts and secure
-- marker buttons keep their original geometry.
-- Its tooltip copies the established Data Bars grammar locally because that
-- child addon is optional: bracketed title, input left and result right.
do
    local tipText, markerOwner
    local rowList = {}
    local TIP_PAD, TIP_ROW_GAP, TIP_COL_GAP, TIP_FONT_SIZE = 10, 3, 18, 12

    local function SetTipFont(fontStr)
        local filePath = CludesUI.GetFontPath(FONT_KEY)
        local _, _, flags = fontStr:GetFont()
        if not filePath and GameFontNormal then
            local fallbackPath, _, fallbackFlags = GameFontNormal:GetFont()
            filePath, flags = fallbackPath, fallbackFlags
        end
        if filePath then
            fontStr:SetFont(filePath, TIP_FONT_SIZE, flags or "")
        end
    end

    local function EnsureTip()
        if tipText then
            return tipText
        end
        tipText = CreateFrame("Frame", "CludesUIRaidToolsTip", UIParent)
        tipText:SetFrameStrata("TOOLTIP")
        tipText:SetFrameLevel(900)
        tipText:SetClampedToScreen(true)
        tipText:Hide()
        local backdrop = tipText:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.97)
        if CludesUI.PP and CludesUI.PP.CreateBorder then
            CludesUI.PP.CreateBorder(tipText, 0, 0, 0, 0.9, 1, "OVERLAY", 7)
        end
        return tipText
    end

    local function EnsureRow(index)
        local line = rowList[index]
        if not line then
            line = {
                left = tipText:CreateFontString(nil, "OVERLAY"),
                right = tipText:CreateFontString(nil, "OVERLAY"),
            }
            rowList[index] = line
        end
        SetTipFont(line.left)
        SetTipFont(line.right)
        return line
    end

    ShowCompactTip = function(ownerFrame, title, actions)
        EnsureTip()
        markerOwner = ownerFrame
        local total = #actions + 2
        local maxLeft, maxRight, totalH = 0, 0, 0
        for index = 1, total do
            local line = EnsureRow(index)
            line.left:ClearAllPoints()
            line.right:ClearAllPoints()
            line.left:SetWordWrap(false)
            line.right:SetWordWrap(false)
            line.left:SetWidth(0)
            line.right:SetWidth(0)

            if index == 1 then
                line.left:SetText("[" .. CludesUI.L(title) .. "]")
                line.right:SetText("")
                line.right:Hide()
                line._h = line.left:GetStringHeight() or TIP_FONT_SIZE
            elseif index == 2 then
                line.left:SetText("")
                line.right:SetText("")
                line.right:Hide()
                line._h = 4
            else
                local action = actions[index - 2]
                line.left:SetText(CludesUI.L(action[1]))
                line.right:SetText(CludesUI.L(action[2]))
                line.right:Show()
                line._h = math.max(
                    line.left:GetStringHeight() or TIP_FONT_SIZE,
                    line.right:GetStringHeight() or TIP_FONT_SIZE
                )
            end
            line.left:SetTextColor(1, 1, 1, 1)
            line.right:SetTextColor(1, 1, 1, 1)
            line.left:Show()
            maxLeft = math.max(maxLeft, line.left:GetStringWidth() or 0)
            if line.right:IsShown() then
                maxRight = math.max(maxRight, line.right:GetStringWidth() or 0)
            end
            totalH = totalH + line._h + (index > 1 and TIP_ROW_GAP or 0)
        end
        for index = total + 1, #rowList do
            rowList[index].left:Hide()
            rowList[index].right:Hide()
        end

        local innerW = maxLeft + (maxRight > 0 and TIP_COL_GAP + maxRight or 0)
        tipText:SetSize(math.max(60, innerW + TIP_PAD * 2), math.max(24, totalH + TIP_PAD * 2))
        local posY = -TIP_PAD
        for index = 1, total do
            local line = rowList[index]
            line.left:SetPoint("TOPLEFT", tipText, "TOPLEFT", TIP_PAD, posY)
            if line.right:IsShown() then
                line.right:SetPoint("TOPRIGHT", tipText, "TOPRIGHT", -TIP_PAD, posY)
            end
            posY = posY - line._h - TIP_ROW_GAP
        end

        local level = 900
        if GameTooltip and GameTooltip.GetFrameLevel then
            local gameTipLevel = GameTooltip:GetFrameLevel()
            if gameTipLevel then
                level = math.max(level, gameTipLevel + 10)
            end
        end
        if tipText:GetFrameLevel() < level then
            tipText:SetFrameLevel(level)
        end
        tipText:ClearAllPoints()
        local _, cy = ownerFrame:GetCenter()
        if cy and cy < UIParent:GetHeight() / 2 then
            tipText:SetPoint("BOTTOM", ownerFrame, "TOP", 0, 6)
        else
            tipText:SetPoint("TOP", ownerFrame, "BOTTOM", 0, -6)
        end
        tipText:Show()
    end

    HideCompactTip = function(ownerFrame)
        if not tipText or (ownerFrame and markerOwner ~= ownerFrame) then
            return
        end
        markerOwner = nil
        tipText:Hide()
    end
end

local function MakeCompactActionButton(hostFrame, labelText, tipBuilder, onClick)
    local widget = CreateFrame("Button", nil, hostFrame)
    widget:SetSize(COMPACT_ICON, COMPACT_ICON)
    widget:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    widget:SetScript("OnClick", onClick)
    local fontStr = TrackFont(hostFrame, CludesUI.MakeFont(widget, 11, nil, 1, 1, 1), 11)
    fontStr:SetPoint("CENTER")
    fontStr:SetText(labelText)
    fontStr:SetAlpha(0.8)
    widget.label = fontStr
    widget:SetScript("OnEnter", function(self)
        self.label:SetAlpha(1)
        local title, actions = tipBuilder()
        ShowCompactTip(self, title, actions)
    end)
    widget:SetScript("OnLeave", function(self)
        self.label:SetAlpha(0.8)
        HideCompactTip(self)
    end)
    groupBtns[#groupBtns + 1] = widget
    return widget
end

local function CompactPullTime(slot)
    local timeList = (P() and P().pullTimes) or {}
    local value = timeList[slot]
    if value == nil then
        value = PULL_DEFAULTS[slot]
    end
    return value and value > 0 and value or nil
end

-- Fill the complete marker region instead of leaving a dead elastic gap before
-- the utilities. Skull owns the left edge, Clear owns the right edge beside
-- the divider, and the seven symbols between them share the remaining width.
local function LayoutCompactMarkers()
    if not compactFrame or not sectionList.Group or #compactMarkers < 2 then
        return
    end
    local width = sectionList.Group:GetWidth()
    if not width or width < COMPACT_MIN_W then
        return
    end

    local utilityCount = compactPullButton and compactPullButton:IsShown() and 2 or 1
    local utilityWidth = utilityCount * COMPACT_ICON + (utilityCount - 1) * COMPACT_GAP
    local firstLeft = COMPACT_PAD
    local lastLeft = width - COMPACT_PAD - utilityWidth - COMPACT_DIVIDER_OFFSET - COMPACT_GAP - COMPACT_ICON
    local stride = (lastLeft - firstLeft) / (#compactMarkers - 1)

    for index, btnFrame in ipairs(compactMarkers) do
        btnFrame:ClearAllPoints()
        local posX = math.floor(firstLeft + (index - 1) * stride + 0.5)
        btnFrame:SetPoint("LEFT", compactFrame, "LEFT", posX, 0)
    end
end

local function RefreshCompactPullState()
    if not compactPullButton then
        return
    end
    local seconds = CompactPullTime(3) or CompactPullTime(2) or CompactPullTime(1)
    compactPullButton:SetShown(seconds ~= nil)
    if compactReady then
        compactReady:Show()
        compactReady:ClearAllPoints()
        compactReady:SetPoint("RIGHT", compactFrame, "RIGHT", -COMPACT_PAD, 0)
    end
    compactPullButton:ClearAllPoints()
    if seconds and compactReady then
        compactPullButton:SetPoint("RIGHT", compactReady, "LEFT", -COMPACT_GAP, 0)
    end
    if compactDivider and compactReady then
        local firstUtility = seconds and compactPullButton or compactReady
        compactDivider:ClearAllPoints()
        compactDivider:SetPoint("TOP", firstUtility, "TOPLEFT", -COMPACT_DIVIDER_OFFSET, -2)
        compactDivider:SetPoint("BOTTOM", firstUtility, "BOTTOMLEFT", -COMPACT_DIVIDER_OFFSET, 2)
    end
    LayoutCompactMarkers()
end

-- The compact band's marker state: a symbol greys out, and the accent line
-- under it lights, while that world marker is on the ground.
--
-- IsRaidMarkerActive answers a SECRET boolean during chat messaging lockdown:
-- on every dungeon and raid map, in or out of combat, and through boss
-- encounters, keystones and PvP matches. So the answer is never tested here.
-- It goes through C_CurveUtil into the icon's desaturation and into the line
-- host's SetAlphaFromBoolean, both of which take a secret from our code, and
-- the client resolves it; a plain answer takes the same calls. Nothing is
-- kept, so the next RAID_TARGET_UPDATE repaints from scratch.
local function RefreshCompactMarkerState()
    -- Hidden buttons are left alone: switching back to the band runs
    -- ApplyLayout, which ends by calling this.
    if ShowAs() ~= "compact" then
        return
    end
    for _, b in ipairs(compactMarkers) do
        -- The clear button carries no world marker and never greys out.
        local ident = b._worldID
        if ident and IsRaidMarkerActive then
            local isActive = IsRaidMarkerActive(ident)
            b.icon:SetDesaturation(C_CurveUtil.EvaluateColorValueFromBoolean(isActive, 1, 0))
            b._activeHost:SetAlphaFromBoolean(isActive, 1, 0)
        end
    end
end

local function BuildCompactContent()
    compactFrame = CreateFrame("Frame", nil, sectionList.Group)
    compactFrame:SetHeight(COMPACT_H)

    -- Blizzard's marker menus and the supplied references both read
    -- Star -> Skull from left to right, followed by one clear action.
    local markerOrder = { 1, 2, 3, 4, 5, 6, 7, 8 }
    for _, index in ipairs(markerOrder) do
        local b = MakeMarkerButton(compactFrame, index, "compact")
        compactMarkers[#compactMarkers + 1] = b
    end
    local clear = MakeMarkerButton(compactFrame, 0, "compact-clear")
    compactMarkers[#compactMarkers + 1] = clear

    compactReady = MakeCompactActionButton(compactFrame, "RC", function()
        local actions = { { "Left Click", "Ready Check" } }
        if ButtonShown("showRoleCheck") then
            actions[#actions + 1] = { "Right Click", "Role Check" }
        end
        if BuffCheckShown() then
            actions[#actions + 1] = { "Shift + Left Click", "Buff Check" }
        end
        return "Ready Check", actions
    end, function(_, btnFrame)
        if btnFrame == "RightButton" then
            if ButtonShown("showRoleCheck") then
                InitiateRolePoll()
            end
        elseif IsShiftKeyDown() and BuffCheckShown() then
            ToggleBuffCheck()
        else
            DoReadyCheck()
        end
    end)

    compactPullButton = MakeCompactActionButton(compactFrame, "PT", function()
        local a = CompactPullTime(1) or "off"
        local b = CompactPullTime(2) or "off"
        local c = CompactPullTime(3) or "off"
        return "Pull Timer",
            {
                { "Left Click", "Pull " .. c },
                { "Shift + Left Click", "Pull " .. b },
                { "Ctrl + Left Click", "Pull " .. a },
                { "Right Click", "Stop pull timer" },
            }
    end, function(_, btnFrame)
        if btnFrame == "RightButton" then
            StopPull()
            return
        end
        local seconds
        if IsControlKeyDown() then
            seconds = CompactPullTime(1)
        elseif IsShiftKeyDown() then
            seconds = CompactPullTime(2)
        else
            seconds = CompactPullTime(3) or CompactPullTime(2) or CompactPullTime(1)
        end
        if seconds then
            StartPull(seconds)
        end
    end)

    -- Pull is the inner utility beside the marker region; Ready Check owns the
    -- far-right edge, matching the established scan order from raid action to
    -- group confirmation.
    compactReady:SetPoint("RIGHT", compactFrame, "RIGHT", -COMPACT_PAD, 0)
    compactPullButton:SetPoint("RIGHT", compactReady, "LEFT", -COMPACT_GAP, 0)

    compactDivider = compactFrame:CreateTexture(nil, "ARTWORK")
    compactDivider:SetColorTexture(1, 1, 1, 0.10)
    compactDivider:SetWidth(1)
    compactDivider:SetPoint("TOP", compactPullButton, "TOPLEFT", -COMPACT_DIVIDER_OFFSET, -2)
    compactDivider:SetPoint("BOTTOM", compactPullButton, "BOTTOMLEFT", -COMPACT_DIVIDER_OFFSET, 2)

    RefreshCompactPullState()
    RefreshCompactMarkerState()
end

-- The collapsed-state square: bg + border + the icon, expanding on click.
-- A click template (not a state template) -- it cannot dispatch _onstate, so
-- the shells fan the driver verdict to it (see MakeShell).
local function BuildCollapsedIcon()
    iconButton = CreateFrame("Button", "CludesUIRaidToolsIcon", UIParent, "SecureHandlerClickTemplate")
    iconButton:SetSize(ICON_SZ, ICON_SZ)
    iconButton:SetFrameStrata("MEDIUM")
    iconButton:SetClampedToScreen(true)
    iconButton:RegisterForClicks("AnyDown")
    iconButton:Hide()
    -- Rides the Group shell's saved position with no bookkeeping of its own:
    -- anchoring to a hidden frame is fine, the anchor resolves through its points.
    iconButton:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0) -- re-pointed at build

    -- The button IS the art: full-bleed image at full opacity, no chrome and
    -- no tooltip.
    local texture = iconButton:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(iconButton)
    texture:SetTexture(COLLAPSED_ICON_TEX)

    -- Hover whitens the art by 10%: the SAME image additively at 0.1 on the
    -- native HIGHLIGHT layer (auto shown on mouseover, no scripts). Re-using
    -- the image keeps the lift inside its alpha channel -- a plain white ADD
    -- rect would glow the transparent corners too. Vertex color cannot do
    -- this; it only multiplies downward.
    local highlight = iconButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(iconButton)
    highlight:SetTexture(COLLAPSED_ICON_TEX)
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.5)

    iconButton:SetAttribute("enabled", true)
    iconButton:SetAttribute("visible", false)
    iconButton:SetAttribute("override", "")
    iconButton:SetAttribute("expanded", true)
    iconButton:SetAttribute("startexpanded", true)
    iconButton:SetAttribute(
        "apply",
        [[
        if not self:GetAttribute("enabled") then
            self:Hide()
            return
        end
        local ov = self:GetAttribute("override")
        local vis
        if ov == "show" then
            vis = true
        elseif ov == "hide" then
            vis = false
        else
            vis = self:GetAttribute("visible")
        end
        if vis and not self:GetAttribute("expanded") then
            self:Show()
        else
            self:Hide()
        end
    ]]
    )
    iconButton:SetAttribute("_onclick", EXPAND_SNIPPET)
end

local function BuildAll()
    if sectionList.Group then
        return
    end
    MakeShell("Group")
    MakeShell("Markers")
    BuildGroupContent()
    BuildMarkersContent()
    BuildCollapsedIcon()
    iconButton:ClearAllPoints()
    iconButton:SetPoint("TOPLEFT", sectionList.Group, "TOPLEFT", 0, 0)

    -- Keybind target. Shown (a hidden button cannot take a CLICK binding) but
    -- 1px, transparent and parked off-screen. It flips everything together
    -- from one computed value, so the pieces can never drift apart.
    toggleBtn = CreateFrame("Button", "CludesUIRaidToolsToggle", UIParent, "SecureHandlerClickTemplate")
    toggleBtn:SetSize(1, 1)
    toggleBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -100, -100)
    toggleBtn:SetAlpha(0)
    toggleBtn:RegisterForClicks("AnyDown")
    toggleBtn:SetAttribute("count", #SECTION_KEYS)
    toggleBtn:SetAttribute("_onclick", TOGGLE_SNIPPET)

    -- Frame refs: the toggle, the icon and each collapse button all reach the
    -- same set; the shells reach the icon for the _onstate fan-out.
    for index, toolKey in ipairs(SECTION_KEYS) do
        local shell = sectionList[toolKey]
        toggleBtn:SetFrameRef("s" .. index, shell)
        shell:SetFrameRef("icon", iconButton)
        shell._collapseBtn:SetAttribute("count", #SECTION_KEYS)
        for jdx, k2 in ipairs(SECTION_KEYS) do
            shell._collapseBtn:SetFrameRef("s" .. jdx, sectionList[k2])
        end
        shell._collapseBtn:SetFrameRef("icon", iconButton)
        iconButton:SetFrameRef("s" .. index, shell)
    end
    toggleBtn:SetFrameRef("icon", iconButton)
    iconButton:SetAttribute("count", #SECTION_KEYS)
end

-------------------------------------------------------------------------------
--  Layout / position / mode
-------------------------------------------------------------------------------

-- Menu Grow Direction -> which corner of the primary shell the collapsed
-- icon occupies. The icon is the piece the user parks, so the corner it
-- rides decides which way the windows appear to grow from it on expand:
-- icon at TOPLEFT = windows extend down-right (the original behaviour),
-- icon at BOTTOMLEFT = up-right, and so on.
local ICON_CORNER = {
    downright = "TOPLEFT",
    upright = "BOTTOMLEFT",
    downleft = "TOPRIGHT",
    upleft = "BOTTOMRIGHT",
}

local function ApplyShellMaterial(frame, isCompact)
    if frame._bgArt then
        frame._bgArt:SetShown(not isCompact)
    end
    if frame._titleBar then
        frame._titleBar:SetShown(not isCompact)
    end
    if frame._bgOverlay then
        frame._bgOverlay:SetColorTexture(0, 0, 0, 0.62)
    end
    if frame._windowBorder then
        frame._windowBorder:SetShown(not isCompact)
    end
end

-- Show-as arrangement. OOC only (Apply gates); the holders are plain frames,
-- so the re-parent is an ordinary SetParent.
local function ApplyLayout()
    local profile = P()
    local displayAs = ShowAs()
    local windowGroup, windowMarkers = sectionList.Group, sectionList.Markers

    local isCompact = displayAs == "compact"
    local collapseUI = not isCompact and profile and profile.collapsedIcon ~= false
    windowGroup._collapseBtn:SetShown(collapseUI)
    -- Two Windows: only Group & Pull carries the collapse control -- one
    -- button folds the whole feature, and a second on Markers would just be
    -- a duplicate. Markers keeps its own ONLY when it is the lone window.
    windowMarkers._collapseBtn:SetShown(collapseUI and displayAs ~= "two")

    ApplyShellMaterial(windowGroup, isCompact)
    ApplyShellMaterial(windowMarkers, false)
    shellTitle.Group:SetShown(not isCompact)
    shellTitle.Markers:SetShown(true)
    if isCompact and not compactFrame then
        BuildCompactContent()
    end
    if compactFrame then
        compactFrame:SetShown(isCompact)
    end

    if isCompact then
        local width = CompactWidth()
        windowGroup:SetWidth(width)
        compactFrame:SetParent(windowGroup)
        compactFrame:ClearAllPoints()
        compactFrame:SetAllPoints(windowGroup)
        groupFrame:SetShown(false)
        markersHolder:SetShown(false)
        windowGroup:SetHeight(CompactHeight())
    elseif displayAs == "one" then
        windowGroup:SetWidth(PANEL_W)
        windowMarkers:SetWidth(PANEL_W)
        shellTitle.Group:SetText(CludesUI.L(COMBINED_LABEL))
        groupFrame:SetShown(true)
        groupFrame:SetParent(windowGroup)
        groupFrame:ClearAllPoints()
        groupFrame:SetPoint("TOPLEFT", windowGroup, "TOPLEFT", 0, -CONTENT_TOP)
        markersHolder:SetShown(true)
        markersHolder:SetParent(windowGroup)
        markersHolder:ClearAllPoints()
        markersHolder:SetPoint(
            "TOPLEFT",
            windowGroup,
            "TOPLEFT",
            0,
            -CONTENT_TOP - GROUP_CONTENT_H - ROW_GAP * 2
        )
        windowGroup:SetHeight(CONTENT_TOP + GROUP_CONTENT_H + ROW_GAP * 2 + MARKERS_CONTENT_H + PAD)
    else
        windowGroup:SetWidth(PANEL_W)
        windowMarkers:SetWidth(PANEL_W)
        -- Every split mode parents each holder to its own shell; which shells
        -- actually SHOW is ApplyVisibility's call (the enabled attribute).
        shellTitle.Group:SetText(CludesUI.L(SECTION_LABEL.Group))
        groupFrame:SetParent(windowGroup)
        groupFrame:SetShown(true)
        groupFrame:ClearAllPoints()
        groupFrame:SetPoint("TOPLEFT", windowGroup, "TOPLEFT", 0, -CONTENT_TOP)
        windowGroup:SetHeight(CONTENT_TOP + GROUP_CONTENT_H + PAD)

        markersHolder:SetParent(windowMarkers)
        markersHolder:SetShown(true)
        markersHolder:ClearAllPoints()
        markersHolder:SetPoint("TOPLEFT", windowMarkers, "TOPLEFT", 0, -CONTENT_TOP)
        windowMarkers:SetHeight(CONTENT_TOP + MARKERS_CONTENT_H + PAD)
    end

    -- The collapsed icon rides the shell the mode actually shows: Markers-only anchors
    -- (and scales, see Apply) to the Markers shell, everything else to Group & Pull.
    -- Which CORNER it rides is the Menu Grow Direction setting (see ICON_CORNER above).
    local corner = ICON_CORNER[profile and profile.growDir] or "TOPLEFT"
    iconButton:ClearAllPoints()
    iconButton:SetPoint(corner, (displayAs == "markers") and windowMarkers or windowGroup, corner, 0, 0)

    -- Heights just moved: re-crop the backdrop art so it covers instead of
    -- stretches (the skins hook SetHeight for this; our heights only ever
    -- change right here, so a direct call is the whole hook).
    if windowGroup._bgFit then
        windowGroup._bgFit()
    end
    if windowMarkers._bgFit then
        windowMarkers._bgFit()
    end
    RefreshCompactPullState()
    RefreshCompactMarkerState()
end

-- Positions round-trip through unlock mode's CENTER/CENTER convention.
--
-- That pairing is not decoration: for an odd-height frame the stored centre ends in .5,
-- and ApplyCenterPosition subtracts the live half-height so the edges land back on
-- whole pixels. Applying the stored value with a plain SetPoint skips that and leaves
-- the frame a pixel off -- visible only after the snap tool, because a normal drag is
-- converted on the way in and a snapped one is not.
local function DefaultPos(toolKey)
    -- Unpositioned installs park the whole feature in the TOP-LEFT corner of
    -- the screen (a small margin off the edges); two-window mode stacks
    -- Markers under Group & Pull. A saved position always wins over this.
    local MARGIN = 20
    local topY = -MARGIN
    if toolKey == "Markers" then
        topY = topY - (sectionList.Group:GetHeight() * WindowScale() + ROW_GAP)
    end
    -- Screen-space margin converted into the frame's own scaled units.
    local s = WindowScale()
    return { point = "TOPLEFT", relPoint = "TOPLEFT", x = MARGIN / s, y = topY / s }
end

local function ApplySectionPosition(toolKey, unlockKey, posKey)
    local frame = sectionList[toolKey]
    if not frame then
        return
    end
    if InCombatLockdown() then
        applyPending = true
        return
    end

    local profile = P()
    unlockKey = unlockKey or (UNLOCK_KEY .. toolKey)
    posKey = posKey or toolKey
    local position = ((profile and profile.pos) or {})[posKey] or DefaultPos(toolKey)
    if CludesUI.ApplyCenterPosition and position.point == "CENTER" and position.relPoint == "CENTER" then
        -- Skips anchor-linked elements itself, and defers its own combat case for
        -- protected frames. FALSE means it could not resolve a live frame for this key
        -- -- fall through to the plain path, exactly as unlock mode's own caller does.
        if CludesUI.ApplyCenterPosition(unlockKey, position) then
            return
        end
    end

    -- Anything not in that convention is a default or a pre-conversion value.
    if CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(unlockKey) then
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint(position.point, UIParent, position.relPoint or position.point, position.x or 0, position.y or 0)
end

local function ApplyPositions()
    -- While an unlock session is open UNLOCK MODE owns these frames: it moves them live
    -- and only writes the result on Save & Exit. A settings pass landing mid-session
    -- (the options panel hiding/showing flips the preview, and a combat-deferred Apply
    -- completes on PLAYER_REGEN_ENABLED) would drag the window back to the last SAVED
    -- spot -- and because Save & Exit derives the value it stores from the frame's LIVE
    -- bounds, the drag is then written back as the old position and lost for good. Same
    -- guard Action Bars, Aura Reminders and the Cooldown Manager already carry.
    if CludesUI._unlockActive then
        return
    end

    -- Each shell is positioned only when the Show as choice can put it on screen; One
    -- Window and Only Group & Pull ride pos.Group, Only Markers rides pos.Markers.
    local displayAs = ShowAs()
    if displayAs == "compact" then
        ApplySectionPosition("Group", COMPACT_UNLOCK_KEY, "Compact")
    elseif displayAs ~= "markers" then
        ApplySectionPosition("Group")
    end
    if displayAs == "two" or displayAs == "markers" then
        ApplySectionPosition("Markers")
    end
end

-- The whole replacement for the old shared-visibility machinery: two literal
-- driver strings keyed by mode. [group] is any group; [group:raid] raid only.
local MODE_DRIVERS = {
    raid = "[group:raid] show; hide",
    group = "[group] show; hide",
}

-- Reached only from Apply, which has already returned if we are in combat.
local function ApplyVisibility()
    local profile = P()
    local modeName = ShowMode()
    local driver = MODE_DRIVERS[modeName]
    -- The out-of-combat settle for the state a driver will not re-fire
    -- (registering one only fires _onstate on a CHANGE). Always mode has no
    -- driver at all: the settle IS its entire visibility source.
    local visibleNow = false
    if modeName == "raid" then
        visibleNow = IsInRaid()
    elseif modeName == "group" then
        visibleNow = IsInGroup()
    elseif modeName == "always" then
        visibleNow = true
    end

    -- Which SHELLS may show, straight from Show as: the Group shell is the
    -- window everywhere except Markers-only; the Markers shell exists only in
    -- Two Windows and Markers-only.
    --
    -- The assist gate rides on top of that and takes ALL of them, icon
    -- included -- a raid without assist is a raid where nothing here works.
    local displayAs = ShowAs()
    local isCompact = displayAs == "compact"
    local suppressed = AssistSuppressed()
    local shellOn = {
        Group = displayAs ~= "markers" and not suppressed,
        Markers = (displayAs == "two" or displayAs == "markers") and not suppressed,
    }
    -- One seed for every show (see header): Default to Collapsed When Shown.
    -- With the toggle off the seed is "expanded" and the icon never shows.
    -- The strip is already the minimized form. Its keybind is therefore a
    -- direct show/hide, never a second collapse into a mystery icon.
    local startExpanded = isCompact or not (profile and profile.collapsedIcon ~= false)

    -- Settings preview (the TBB-placeholder arrangement): while the Raid
    -- Tools page is in front, the windows are forced shown and FULLY EXPANDED
    -- so every settings change is visible as it lands, and the drivers stay
    -- unregistered so a group transition cannot collapse or hide the thing
    -- being configured mid-edit. Only the LIVE state is forced; the seeds
    -- keep their configured values for when the preview ends.
    local expandedNow = startExpanded
    if previewOn then
        driver = nil
        visibleNow = true
        expandedNow = true
    end

    for _, toolKey in ipairs(SECTION_KEYS) do
        local frame = sectionList[toolKey]
        local enabled = shellOn[toolKey] and true or false

        frame:SetAttribute("enabled", enabled)
        frame:SetAttribute("visible", visibleNow)
        frame:SetAttribute("override", "")
        frame:SetAttribute("startexpanded", startExpanded)
        frame:SetAttribute("expanded", expandedNow)

        UnregisterStateDriver(frame, "cuirt_vis")
        if enabled and driver then
            RegisterStateDriver(frame, "cuirt_vis", driver)
        end
    end

    -- The icon represents the whole feature; every Show as choice shows
    -- something, so it is on while the mode is active and the assist gate is
    -- open. With it shut the keybind and the slash command go quiet too --
    -- both run the secure snippets, and those refuse a disabled frame.
    iconButton:SetAttribute("enabled", not isCompact and not suppressed)
    iconButton:SetAttribute("visible", visibleNow)
    iconButton:SetAttribute("override", "")
    iconButton:SetAttribute("startexpanded", startExpanded)
    iconButton:SetAttribute("expanded", expandedNow)

    -- What is now ON SCREEN, for the roster handler to compare against.
    lastSuppressed = suppressed

    -- Run the snippets rather than re-deciding in Lua: attributes are set
    -- first so "apply" sees them.
    if SecureHandlerExecute then
        for _, toolKey in ipairs(SECTION_KEYS) do
            SecureHandlerExecute(sectionList[toolKey], RUN_APPLY)
        end
        SecureHandlerExecute(iconButton, RUN_APPLY)
    end
end

-- Toggle Raid Tools key: profile-stored, applied as an override binding on
-- the secure toggle button -- the exact arrangement Action Bars uses for
-- Toggle Action Bar. Pressing the bound key is a hardware click,
-- so the toggle itself works IN combat; only (re)binding defers.
local function ApplyToggleKeybind()
    if not toggleBtn then
        return
    end
    ClearOverrideBindings(toggleBtn)
    local profile = P()
    local k = profile and profile.toggleKey
    -- The gate takes the binding with it rather than leaving a key that eats
    -- its own keypress: the snippet would refuse a disabled frame, and an
    -- override binding swallows whatever the key does otherwise.
    if k and k ~= "" and ShowMode() ~= "never" and not AssistSuppressed() then
        SetOverrideBindingClick(toggleBtn, false, k, "CludesUIRaidToolsToggle")
    end
end

-- Build the first-free run from live marker state. Protected attributes cannot
-- be changed during combat, so the secure Place button consumes the last run
-- prepared out of combat and PLAYER_REGEN_ENABLED refreshes it afterward.
--
-- IsRaidMarkerActive answers a SECRET boolean during chat messaging lockdown:
-- on every dungeon and raid map, in or out of combat, and through boss
-- encounters, keystones and PvP matches. A secret cannot choose which
-- attributes to write; no snippet can read marker state, and the one secure
-- action that tests it (the worldmarker toggle) flips a single fixed marker,
-- so it cannot pick the first free one. While the answer is secret the run
-- already prepared is kept, and Place, Undo and Clear carry on by position
-- exactly as they do in combat. A full Star to Skull run starts instead when
-- the instance changed (runtime.qfZonedPending, latched at PLAYER_ENTERING_WORLD
-- so a zone-in during combat still lands here), when no run exists yet, or
-- when the run is used up -- clears are invisible while secret (ours, /cwm,
-- another player's), so an exhausted run starts over rather than going dead.
-- Markers already on the ground are not skipped then. The answers are all
-- read before anything is written, so a secret never leaves a half-built run.
-- An instance change also empties the Undo stack: its markers are gone.
local function PrimeQuickFire(placement)
    if not placement or InCombatLockdown() then
        return
    end
    local zoned = runState.qfZonedPending
    local free = runState.qfFree
    if not free then
        free = {}
        runState.qfFree = free
    end
    for index = 1, 8 do
        local isActive = IsRaidMarkerActive and IsRaidMarkerActive(SYMBOL_TO_WORLD[index])
        if issecretvalue(isActive) then
            local num = tonumber(placement:GetAttribute("qfAvailCount"))
            if zoned or not num or (tonumber(placement:GetAttribute("qfAvailPos")) or 0) >= num then
                for jdx = 1, 8 do
                    placement:SetAttribute("qfAvail" .. jdx, jdx)
                end
                placement:SetAttribute("qfAvailCount", 8)
                placement:SetAttribute("qfAvailPos", 0)
                if zoned or not num then
                    placement:SetAttribute("qfDepth", 0)
                end
                runState.qfZonedPending = nil
            end
            return
        end
        free[index] = not isActive
    end
    local total = 0
    for index = 1, 8 do
        if free[index] then
            total = total + 1
            placement:SetAttribute("qfAvail" .. total, index)
        end
    end
    for index = total + 1, 8 do
        placement:SetAttribute("qfAvail" .. index, nil)
    end
    placement:SetAttribute("qfAvailCount", total)
    placement:SetAttribute("qfAvailPos", 0)
    if zoned then
        placement:SetAttribute("qfDepth", 0)
    end
    runState.qfZonedPending = nil
end

-- The three invisible buttons are created only after Quick Fire is enabled.
-- Their secure click snippets keep Place, Undo and Clear usable in combat;
-- changing the bindings themselves still follows WoW's normal combat lock.
local function BuildQuickFire()
    if runState.qfPlace then
        return
    end

    runState.qfHeader =
        CreateFrame("Frame", "CludesUIRaidToolsQuickFireHeader", UIParent, "SecureHandlerBaseTemplate")

    local placement =
        CreateFrame("Button", "CludesUIRaidToolsQuickFirePlace", UIParent, "SecureActionButtonTemplate")
    placement:RegisterForClicks("AnyDown")
    placement:SetAttribute("useOnKeyDown", true)
    placement:EnableMouse(false)
    placement:SetSize(1, 1)
    placement:SetAlpha(0)
    placement:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -120, -120)
    placement:Show()
    placement:SetAttribute("qfCount", 8)
    placement:SetAttribute("qfDepth", 0)
    for index = 1, 8 do
        placement:SetAttribute("qfMarker" .. index, SYMBOL_TO_WORLD[index])
        placement:SetAttribute(
            "qfPlaceMacro" .. index,
            (SLASH_WORLD_MARKER1 or "/wm") .. " [@cursor] " .. SYMBOL_TO_WORLD[index]
        )
    end
    placement:SetScript("PreClick", function(self)
        PrimeQuickFire(self)
    end)
    SecureHandlerWrapScript(
        placement,
        "OnClick",
        runState.qfHeader,
        [[
        self:SetAttribute("type", nil)
        self:SetAttribute("macrotext", nil)
        local n = tonumber(self:GetAttribute("qfCount")) or 8
        local available = tonumber(self:GetAttribute("qfAvailCount")) or 0
        local nextPos = (tonumber(self:GetAttribute("qfAvailPos")) or 0) + 1
        if nextPos > available then return end
        local pos = tonumber(self:GetAttribute("qfAvail" .. nextPos))
        if not pos then return end
        self:SetAttribute("qfAvailPos", nextPos)

        local depth = tonumber(self:GetAttribute("qfDepth")) or 0
        if depth >= n then
            for i = 1, n - 1 do
                self:SetAttribute("qfStack" .. i,
                    self:GetAttribute("qfStack" .. (i + 1)))
            end
            depth = n - 1
        end
        depth = depth + 1
        self:SetAttribute("qfDepth", depth)
        self:SetAttribute("qfStack" .. depth, pos)
        self:SetAttribute("macrotext", self:GetAttribute("qfPlaceMacro" .. pos))
        self:SetAttribute("type", "macro")
    ]],
        [[
        self:SetAttribute("type", nil)
        self:SetAttribute("macrotext", nil)
    ]]
    )

    local undoStack =
        CreateFrame("Button", "CludesUIRaidToolsQuickFireUndo", UIParent, "SecureActionButtonTemplate")
    undoStack:RegisterForClicks("AnyDown")
    undoStack:SetAttribute("useOnKeyDown", true)
    undoStack:EnableMouse(false)
    undoStack:SetSize(1, 1)
    undoStack:SetAlpha(0)
    undoStack:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -124, -120)
    undoStack:Show()
    SecureHandlerSetFrameRef(undoStack, "place", placement)
    SecureHandlerWrapScript(
        undoStack,
        "OnClick",
        runState.qfHeader,
        [[
        self:SetAttribute("type", nil)
        self:SetAttribute("action", nil)
        self:SetAttribute("marker", nil)
        local place = self:GetFrameRef("place")
        local depth = place and (tonumber(place:GetAttribute("qfDepth")) or 0) or 0
        if depth < 1 then return end
        local pos = tonumber(place:GetAttribute("qfStack" .. depth))
        if not pos then return end
        place:SetAttribute("qfStack" .. depth, nil)
        place:SetAttribute("qfDepth", depth - 1)
        local availablePos = tonumber(place:GetAttribute("qfAvailPos")) or 0
        if availablePos > 0
           and tonumber(place:GetAttribute("qfAvail" .. availablePos)) == pos then
            place:SetAttribute("qfAvailPos", availablePos - 1)
        end
        self:SetAttribute("marker", place:GetAttribute("qfMarker" .. pos))
        self:SetAttribute("action", "clear")
        self:SetAttribute("type", "worldmarker")
    ]],
        [[
        self:SetAttribute("type", nil)
        self:SetAttribute("action", nil)
        self:SetAttribute("marker", nil)
    ]]
    )

    local clear =
        CreateFrame("Button", "CludesUIRaidToolsQuickFireClear", UIParent, "SecureActionButtonTemplate")
    clear:RegisterForClicks("AnyDown")
    clear:SetAttribute("useOnKeyDown", true)
    clear:EnableMouse(false)
    clear:SetSize(1, 1)
    clear:SetAlpha(0)
    clear:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -128, -120)
    clear:Show()
    SecureHandlerSetFrameRef(clear, "place", placement)
    SecureHandlerWrapScript(
        clear,
        "OnClick",
        runState.qfHeader,
        [[
        local place = self:GetFrameRef("place")
        if place then
            local n = tonumber(place:GetAttribute("qfCount")) or 8
            place:SetAttribute("qfDepth", 0)
            place:SetAttribute("qfAvailCount", n)
            place:SetAttribute("qfAvailPos", 0)
            for i = 1, n do
                place:SetAttribute("qfAvail" .. i, i)
                place:SetAttribute("qfStack" .. i, nil)
            end
        end
        self:SetAttribute("macrotext", self:GetAttribute("qfClearMacro"))
        self:SetAttribute("type", "macro")
    ]],
        [[
        self:SetAttribute("type", nil)
        self:SetAttribute("macrotext", nil)
    ]]
    )
    clear:SetAttribute("qfClearMacro", (SLASH_CLEAR_WORLD_MARKER1 or "/cwm") .. " " .. (ALL or "All"))

    runState.qfPlace, runState.qfUndo, runState.qfClear = placement, undoStack, clear
    runState.qfBindingOwner = CreateFrame("Frame")
    PrimeQuickFire(placement)
end

local function ApplyQuickFireBindings()
    local profile = P()
    if runState.qfBindingOwner then
        ClearOverrideBindings(runState.qfBindingOwner)
    end
    if not profile or profile.quickFire ~= true or ShowMode() == "never" or AssistSuppressed() then
        return
    end

    BuildQuickFire()
    PrimeQuickFire(runState.qfPlace)
    local bindings = {
        { profile.quickFirePlaceKey, "CludesUIRaidToolsQuickFirePlace" },
        { profile.quickFireUndoKey, "CludesUIRaidToolsQuickFireUndo" },
        { profile.quickFireClearKey, "CludesUIRaidToolsQuickFireClear" },
    }
    for _, binding in ipairs(bindings) do
        if binding[1] and binding[1] ~= "" then
            SetOverrideBindingClick(runState.qfBindingOwner, false, binding[1], binding[2])
        end
    end
end

-------------------------------------------------------------------------------
--  Lifecycle
--
--  Nothing exists until the mode first leaves "never": no frames, no events,
--  no bindings, no unlock rows. Apply() is the single entry point.
-------------------------------------------------------------------------------

-- The assist gate is Lua's, so a promotion, a demotion or a raid you join
-- without assist has to bring Apply back around -- no state driver will do it
-- for us. Compared against what ApplyVisibility last put on screen, because
-- GROUP_ROSTER_UPDATE bursts and Apply is not free.
--
-- In combat Apply parks itself behind applyPending, which leaves lastSuppressed
-- untouched: the next roster event re-enters here and parks again, and
-- PLAYER_REGEN_ENABLED finishes the job. That is the module's standard
-- deferral, not an omission.
local function RefreshAssistGate()
    if AssistSuppressed() ~= lastSuppressed then
        Apply()
    end
end

-- Events live only while the feature is active (or while a combat-deferred
-- Apply is pending, since PLAYER_REGEN_ENABLED is what completes it). The
-- frame itself is created on first need and reused.
local eventName
local function EnsureEvents()
    if not eventName then
        eventName = CreateFrame("Frame")
        eventName:SetScript("OnEvent", function(_, evt)
            -- Pending work FIRST, before the mode gate: a switch TO "never" deferred by
            -- combat must complete even though the profile already reads never --
            -- swallowing it here is how panels get stranded on screen.
            if evt == "PLAYER_REGEN_ENABLED" and applyPending then
                Apply()
                return
            end
            if ShowMode() == "never" then
                return
            end
            -- A zone change repaints the band too: the markers it showed belong
            -- to the ground just left.
            if (evt == "RAID_TARGET_UPDATE" or evt == "PLAYER_ENTERING_WORLD") and ShowAs() == "compact" then
                RefreshCompactMarkerState()
            end
            -- Both features share these events, but each only does work while
            -- enabled. An old Quick Fire frame can survive being disabled. An
            -- instance change is latched for the next prime out of combat (see
            -- PrimeQuickFire); a loading screen inside the same instance is not one.
            if evt == "PLAYER_ENTERING_WORLD" then
                local zone = select(8, GetInstanceInfo())
                if zone ~= runState.qfZone then
                    runState.qfZone = zone
                    runState.qfZonedPending = true
                end
            end
            if
                evt == "RAID_TARGET_UPDATE"
                or evt == "PLAYER_REGEN_ENABLED"
                or evt == "PLAYER_ENTERING_WORLD"
            then
                local profile = P()
                if profile and profile.quickFire == true and runState.qfPlace then
                    PrimeQuickFire(runState.qfPlace)
                end
            end
            RefreshPermissions()
            RefreshAssistGate()
        end)
    end
    eventName:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventName:RegisterEvent("PARTY_LEADER_CHANGED")
    eventName:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventName:RegisterEvent("PLAYER_REGEN_ENABLED")
    local profile = P()
    if ShowMode() ~= "never" and (ShowAs() == "compact" or (profile and profile.quickFire == true)) then
        eventName:RegisterEvent("RAID_TARGET_UPDATE")
    else
        eventName:UnregisterEvent("RAID_TARGET_UPDATE")
    end
end
local function DropEvents()
    if eventName then
        eventName:UnregisterAllEvents()
    end
end

-- Unlock-mode movers, registered once, on first activation. getFrame
-- returning nil keeps an element out of unlock mode, which is also how
-- one-window mode collapses the feature to a single element: the Markers
-- entry vanishes and the Group entry moves the combined window via pos.Group.
local unlockRegistered
local function RegisterUnlock()
    if unlockRegistered then
        return
    end
    local MK = CludesUI.MakeUnlockElement
    if not MK then
        return
    end
    unlockRegistered = true

    local elementList = {}
    for index, toolKey in ipairs(SECTION_KEYS) do
        local unlockKey = UNLOCK_KEY .. toolKey
        elementList[#elementList + 1] = MK({
            key = unlockKey,
            label = SECTION_LABEL[toolKey],
            group = "Raid Tools",
            order = 540 + index,
            noResize = true,
            getFrame = function()
                if ShowMode() == "never" then
                    return nil
                end
                -- Nothing to move while the assist gate has the whole feature
                -- off the screen -- same opt-out as the modes below.
                if AssistSuppressed() then
                    return nil
                end
                -- Offer exactly the shells the Show as choice puts on screen:
                -- One Window / Only Group & Pull = the Group element alone,
                -- Two Windows = both, Only Markers = the Markers element alone.
                local displayAs = ShowAs()
                if toolKey == "Group" and (displayAs == "compact" or displayAs == "markers") then
                    return nil
                end
                if toolKey == "Markers" and displayAs ~= "two" and displayAs ~= "markers" then
                    return nil
                end
                BuildAll()
                return sectionList[toolKey]
            end,
            getSize = function()
                -- Unlock mode sizes the mover overlay in UIParent units, so
                -- the Window Scale has to be folded in here -- GetWidth is the
                -- frame's own (unscaled) size.
                local s = WindowScale()
                local frame = sectionList[toolKey]
                if frame then
                    return frame:GetWidth() * s, frame:GetHeight() * s
                end
                return PANEL_W * s, 60 * s
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                if not anchorPoint then
                    return
                end
                local profile = P()
                if not profile then
                    return
                end
                -- Unlock mode hands us two conventions: a normal drag arrives
                -- already converted to CENTER/CENTER, a snapped one arrives
                -- raw. Converting here makes both identical --
                -- ConvertToCenterPos passes an already-CENTER value through
                -- untouched, so the drag path is unaffected.
                if CludesUI.ConvertToCenterPos then
                    anchorPoint, relPoint, posX, posY =
                        CludesUI.ConvertToCenterPos(unlockKey, anchorPoint, relPoint, posX, posY)
                end
                -- Direct index, no `p.pos = p.pos or {}` reseed: DB_DEFAULTS
                -- guarantees the table, and under a Spec Overrides capture
                -- proxy the reseed stores a proxy into the real profile (the
                -- hazard the P() comment documents). Writing THROUGH p.pos is
                -- proxy-safe; storing it back is not.
                if not profile.pos then
                    return
                end
                profile.pos[toolKey] = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                if not CludesUI._unlockActive then
                    ApplySectionPosition(toolKey)
                end
            end,
            loadPos = function()
                return ((P() and P().pos) or {})[toolKey]
            end,
            clearPos = function()
                local profile = P()
                if profile and profile.pos then
                    profile.pos[toolKey] = nil
                end
            end,
            applyPos = function()
                -- Compact reuses the Group shell but owns a separate unlock key
                -- and saved position. The global login pass visits every
                -- registered element, including this inactive legacy entry; do
                -- not let its stale Group position overwrite Compact's position.
                if toolKey == "Group" and ShowAs() == "compact" then
                    return
                end
                ApplySectionPosition(toolKey)
            end,
        })
    end

    elementList[#elementList + 1] = MK({
        key = COMPACT_UNLOCK_KEY,
        label = "Compact Band",
        group = "Raid Tools",
        order = 540,
        getFrame = function()
            if ShowMode() == "never" or AssistSuppressed() or ShowAs() ~= "compact" then
                return nil
            end
            BuildAll()
            return sectionList.Group
        end,
        getSize = function()
            local frame = sectionList.Group
            if frame then
                return frame:GetWidth(), frame:GetHeight()
            end
            return CompactWidth(), CompactHeight()
        end,
        setWidth = function(_, newW)
            local profile = P()
            if not (profile and newW) then
                return
            end
            local Pix = CludesUI and CludesUI.PP
            profile.compactWidth = math.max(COMPACT_MIN_W, Pix and Pix.Snap(newW) or math.floor(newW + 0.5))
            if sectionList.Group then
                ApplyLayout()
            end
        end,
        setHeight = function(_, newH)
            local profile = P()
            if not (profile and newH) then
                return
            end
            local Pix = CludesUI and CludesUI.PP
            profile.compactHeight = math.max(COMPACT_MIN_H, Pix and Pix.Snap(newH) or math.floor(newH + 0.5))
            if sectionList.Group then
                ApplyLayout()
            end
        end,
        savePos = function(_, anchorPoint, relPoint, posX, posY)
            if not anchorPoint then
                return
            end
            local profile = P()
            if not (profile and profile.pos) then
                return
            end
            if CludesUI.ConvertToCenterPos then
                anchorPoint, relPoint, posX, posY =
                    CludesUI.ConvertToCenterPos(COMPACT_UNLOCK_KEY, anchorPoint, relPoint, posX, posY)
            end
            profile.pos.Compact = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
            if not CludesUI._unlockActive then
                ApplySectionPosition("Group", COMPACT_UNLOCK_KEY, "Compact")
            end
        end,
        loadPos = function()
            return ((P() and P().pos) or {}).Compact
        end,
        clearPos = function()
            local profile = P()
            if profile and profile.pos then
                profile.pos.Compact = nil
            end
        end,
        applyPos = function()
            if ShowAs() ~= "compact" then
                return
            end
            ApplySectionPosition("Group", COMPACT_UNLOCK_KEY, "Compact")
        end,
    })

    if #elementList > 0 then
        CludesUI:RegisterUnlockElements(elementList, "CludesUIQoL")
    end
end

-- Options-page entry point, and the completion target for combat-deferred work. Every
-- path below writes secure attributes, drivers, bindings or geometry on protected
-- frames -- ALL blocked in lockdown, the switch to "never" included (SetAttribute is as
-- protected as Hide). So in combat the whole request is parked behind applyPending,
-- with the REGEN listener guaranteed alive to finish it.
function Apply()
    -- Raid Buff Check registers plain events only, so it follows the settings
    -- even in combat and with the panels on Never.
    if mod.BuffCheckSync then
        mod.BuffCheckSync()
    end
    if InCombatLockdown() then
        applyPending = true
        EnsureEvents()
        return
    end
    applyPending = false

    -- The settings preview builds and shows even on Never: the page being in
    -- front means the user is configuring the thing, and an invisible subject
    -- makes every control feel dead. Preview off restores the true teardown.
    if ShowMode() == "never" and not previewOn then
        if sectionList.Group then
            for _, toolKey in ipairs(SECTION_KEYS) do
                local frame = sectionList[toolKey]
                UnregisterStateDriver(frame, "cuirt_vis")
                frame:SetAttribute("enabled", false)
                frame:SetAttribute("override", "")
                frame:Hide()
            end
            iconButton:SetAttribute("enabled", false)
            iconButton:Hide()
            ClearOverrideBindings(toggleBtn)
        end
        if runState.qfBindingOwner then
            ClearOverrideBindings(runState.qfBindingOwner)
        end
        -- Fully off and nothing pending: no reason to keep hearing roster
        -- spam. Never-activated sessions never created the frame at all.
        DropEvents()
        return
    end

    EnsureEvents()
    RegisterUnlock()
    BuildAll()
    -- Before ApplyLayout: it sizes the shells from GROUP_CONTENT_H, which the
    -- hidden buttons and the 0-second pull slots move.
    LayoutGroupContent()
    ApplyLayout()
    -- One Window Scale for everything the feature draws.
    local scale = WindowScale()
    sectionList.Group:SetScale(scale)
    sectionList.Markers:SetScale(scale)
    iconButton:SetScale(scale)
    ApplyPositions()
    ApplyVisibility()
    ApplyToggleKeybind()
    ApplyQuickFireBindings()
    ApplyFonts()
    RefreshPermissions(true)
end
_G._CUI_RaidTools_Apply = Apply

-- Settings-page preview switch (see ApplyVisibility). A global rather than an
-- ns export on purpose: the QoL page dispatcher in CUI_QoL_Options.lua has no
-- ns capture, and it is the one that must end the preview when another QoL
-- page builds. Same convention as _CUI_RaidTools_Apply.
_G._CUI_RaidTools_Preview = function(enabled)
    enabled = enabled and true or false
    if previewOn == enabled then
        return
    end
    previewOn = enabled
    Apply()
end

-------------------------------------------------------------------------------
--  Slash command
-------------------------------------------------------------------------------

-- Same snippet as the keybind, entered through SecureHandlerExecute -- which
-- insecure code may only do out of combat, hence the message below. This
-- deliberately does NOT go through toggleButton:Click(): the button is
-- registered for "AnyDown" only, and a bare Click() simulates an up event, so
-- the handler would never fire. The keybind keeps the hardware path because a
-- real click is the only thing that can run the snippet during combat.
local function ToggleOutOfCombat()
    if toggleBtn and SecureHandlerExecute then
        SecureHandlerExecute(toggleBtn, TOGGLE_SNIPPET)
    end
end

SLASH_CUIRAIDTOOLS1 = "/cuiraid"
SlashCmdList["CUIRAIDTOOLS"] = function()
    if ShowMode() == "never" then
        CludesUI.Print(
            CludesUI.COLOR_CODES.BRAND
                .. "CludesUI:|r "
                .. CludesUI.L("Raid Tools is disabled in the CludesUI options.")
        )
        return
    end
    if InCombatLockdown() then
        CludesUI.Print(
            CludesUI.COLOR_CODES.BRAND
                .. "CludesUI:|r "
                .. CludesUI.L("Raid Tools cannot be toggled by slash command in combat -- use the keybind.")
        )
        return
    end
    -- The snippet would refuse anyway (enabled is false while the gate is
    -- shut); saying so beats a slash command that looks broken.
    if AssistSuppressed() then
        CludesUI.Print(
            CludesUI.COLOR_CODES.BRAND
                .. "CludesUI:|r "
                .. CludesUI.L(
                    "Raid Tools is hidden in a raid without leader or assist -- none of its buttons work there."
                )
        )
        return
    end
    BuildAll()
    ToggleOutOfCombat()
end

-------------------------------------------------------------------------------
--  Init -- same shape as the other QoL features: take the shared QoL DB handle
--  on PLAYER_LOGIN, publish it, then start. Apply() is a no-op for anyone on
--  the default "never" mode: no frames, no events, no unlock rows.
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not (CludesUI and CludesUI.Lite and CludesUI.Lite.NewDB) then
        return
    end
    saved = CludesUI.Lite.NewDB("CludesUIQoLDB", DB_DEFAULTS, true)
    _G._CUI_RaidTools_DB = function()
        return saved
    end
    Apply()
end)
