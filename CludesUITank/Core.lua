local addonName, mod = ...
if mod.standalone then
    return
end

-- ── Constants (shared with all modules via ns.K) ───────────────────────────
mod.K = {
    BACKDROP_TEXTURE = "Interface\\Buttons\\WHITE8X8",
    DEFAULT_FONT_FACE = "Fonts\\ARIALN.TTF",
    FONT_FACES = {
        { id = "Fonts\\ARIALN.TTF", label = "Arial Narrow" },
        { id = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
        { id = "Fonts\\MORPHEUS.TTF", label = "Morpheus" },
        { id = "Fonts\\SKURRI.TTF", label = "Skurri" },
    },
    FONT_FLAGS = {
        { id = "OUTLINE", label = "Outline", flags = "OUTLINE" },
        { id = "THICKOUTLINE", label = "Thick Outline", flags = "THICKOUTLINE" },
        { id = "MONOCHROME", label = "Monochrome", flags = "MONOCHROME, OUTLINE" },
        { id = "NONE", label = "None", flags = "" },
    },
    FONT_COLOR_DEFAULTS = {
        stackCountColor = { 1.00, 1.00, 1.00 },
        timerTextColor = { 1.00, 0.85, 0.40 },
        nameTextColor = { 1.00, 1.00, 1.00 },
        hpTextColor = { 0.90, 0.90, 0.90 },
        stackHighlightColor = { 1.00, 0.25, 0.20 },
    },
    STACK_NUDGE_MIN = -20,
    STACK_NUDGE_MAX = 20,
    UPDATE_THROTTLE = 0.05,

    -- Frame dimensions
    DEFAULT_WIDTH = 200,
    DEFAULT_HEIGHT = 55,
    MIN_WIDTH = 100,
    MAX_WIDTH = 400,
    MIN_HEIGHT = 30,
    MAX_HEIGHT = 120,
    POWER_BAR_HEIGHT = 5,
    HEALTH_BAR_INTENSITY = 0.7,

    -- Font sizes
    DEFAULT_NAME_FONT_SIZE = 14,
    DEFAULT_HP_FONT_SIZE = 12,
    MIN_FONT_SIZE = 8,
    MAX_FONT_SIZE = 28,

    -- Private auras
    PRIVATE_AURA_CONTAINER_SIZE = 30,
    PRIVATE_AURA_SIZE_DEFAULT = 30,
    PRIVATE_AURA_SIZE_MIN = 16,
    PRIVATE_AURA_SIZE_MAX = 56,
    PRIVATE_AURA_BORDER_SCALE_DEFAULT = 2,
    PRIVATE_AURA_BORDER_SCALE_MIN = 0,
    PRIVATE_AURA_BORDER_SCALE_MAX = 8,
    PRIVATE_AURA_STACK_SCALE_DEFAULT = 1,
    PRIVATE_AURA_STACK_SCALE_MIN = 1,
    PRIVATE_AURA_STACK_SCALE_MAX = 6,
    PRIVATE_AURA_GROW_DIRECTIONS = {
        { id = "LEFT", label = "Left (default)" },
        { id = "RIGHT", label = "Right" },
        { id = "UP", label = "Up" },
        { id = "DOWN", label = "Down" },
    },
    PRIVATE_AURAS_DEFAULT_COUNT = 4,
    PRIVATE_AURAS_MIN_COUNT = 0,
    PRIVATE_AURAS_MAX_COUNT = 10,
    PRIVATE_AURAS_DEFAULT_SCALE_FACTOR = 1.5,

    -- Debuffs
    DEBUFF_ICON_SIZE = 26,
    DEBUFF_SPACING = 4,
    DEBUFF_DEFAULT_COUNT = 5,
    DEBUFF_MIN_COUNT = 0,
    DEBUFF_MAX_COUNT = 10,
    DEBUFF_AURA_FILTER = "HARMFUL",
    -- Which harmful auras the debuff row accepts. `filters` is handed to the
    -- AuraContainer as candidateFilters; the engine applies it, so it works
    -- while auras are secret.
    DEBUFF_FILTER_MODES = {
        { id = "ALL", label = "All debuffs", filters = {} },
        { id = "BOSS_ROLE", label = "Boss and role debuffs", filters = { isBossOrRoleAura = true } },
        { id = "BOSS", label = "Boss debuffs only", filters = { isBossAura = true } },
    },
    -- Stack count at which a debuff icon gets its highlight border (0 = off).
    STACK_HIGHLIGHT_DEFAULT = 0,
    STACK_HIGHLIGHT_MIN = 0,
    STACK_HIGHLIGHT_MAX = 20,
    STACK_HIGHLIGHT_EDGE = 2,

    -- Defensives (0 = hidden by default)
    BIG_DEFENSIVES_DEFAULT_COUNT = 0,
    BIG_DEFENSIVES_MIN_COUNT = 0,
    BIG_DEFENSIVES_MAX_COUNT = 3,
    BIG_DEFENSIVE_AURA_FILTER = "HELPFUL|BIG_DEFENSIVE",

    -- Icon spacing
    ICON_SPACING_MIN = 0,
    ICON_SPACING_MAX = 16,

    -- Icon label settings
    STACK_COUNT_DEFAULT_SIZE = 9,
    STACK_COUNT_MIN_SIZE = 0,
    STACK_COUNT_MAX_SIZE = 18,
    CD_FONT_SCALE_DEFAULT = 5, -- stored 0-10; /10 = actual scale (5 = 0.5)
    CD_FONT_SCALE_MIN = 0,
    CD_FONT_SCALE_MAX = 10,
    TIMER_TEXT_DEFAULT_SIZE = 9,
    TIMER_TEXT_MIN_SIZE = 6,
    TIMER_TEXT_MAX_SIZE = 24,
    STACK_COUNT_POSITIONS = {
        { id = "BR_IN", label = "Inside: Bot-Right", point = "BOTTOMRIGHT", px = 2, py = 1 },
        { id = "BL_IN", label = "Inside: Bot-Left", point = "BOTTOMLEFT", px = -2, py = 1 },
        { id = "TR_IN", label = "Inside: Top-Right", point = "TOPRIGHT", px = 2, py = -2 },
        { id = "TL_IN", label = "Inside: Top-Left", point = "TOPLEFT", px = -2, py = -2 },
        { id = "BR_OUT", label = "Outside: Right", point = "BOTTOMRIGHT", px = 7, py = -2 },
        { id = "BL_OUT", label = "Outside: Left", point = "BOTTOMLEFT", px = -7, py = -2 },
        { id = "TOP_OUT", label = "Above Icon", point = "BOTTOM", rel = "TOP", px = 0, py = 2 },
        { id = "BOT_OUT", label = "Below Icon", point = "TOP", rel = "BOTTOM", px = 0, py = -2 },
    },

    -- Mock preview data
    MOCK_PREVIEW_DEBUFF_ICONS = {
        132290,
        132090,
        135904,
        136125,
        132155,
        136207,
        132104,
        136147,
        135974,
        136015,
        132114,
        136116,
        135978,
    },
    -- Spell IDs whose icons stand in for defensives in the preview:
    -- Shield Wall, Ironbark, Pain Suppression.
    MOCK_PREVIEW_DEFENSIVE_SPELLS = { 871, 102342, 33206 },
    MOCK_NAMES = {
        "Lord Doljonijiarnimorinar",
        "Lorem Ipsum Dolor",
        "M1 Abrams",
        "Iblameheals",
        "TheArtistFormerlyKnownAsTank",
        "LineOfSighted",
    },
}

-- ── Shared addon-level objects ─────────────────────────────────────────────
mod.ADDON_COLOR = CreateColorFromHexString("ff5ab4ff")
mod.isTestMode = false

-- ── Helper functions ───────────────────────────────────────────────────────
-- Settings live in the active CludesUI profile (CludesUIDB.profiles[name]
-- .addons.CludesUITank), so they save, export, import and switch with it.
-- db.profile is re-pointed by the profile system, so always read it here.
local profileDB
function mod.DB()
    if not profileDB then
        profileDB = CludesUI.Lite.NewDB("CludesUITankDB", { profile = {} })
    end
    return profileDB.profile
end

function mod.SettingNumber(key, default)
    local val = mod.DB()[key]
    return tonumber(val) or default
end

function mod.IsInEditMode()
    if C_EditMode and type(C_EditMode.IsEditModeActive) == "function" then
        return C_EditMode.IsEditModeActive()
    end
    return false
end

function mod.CalculateScaleFactor()
    return mod.DB().scaleFactorPrivateAuras or mod.K.PRIVATE_AURAS_DEFAULT_SCALE_FACTOR
end

function mod.FindCoTank()
    if mod.isTestMode then
        return "player"
    end
    local groupType = IsInRaid() and "raid" or (IsInGroup() and "party")
    if not groupType then
        return nil
    end
    local total = GetNumGroupMembers()
    -- Prefer pinned tank if set
    local pinned = mod.DB().pinnedTank
    if pinned then
        for idx = 1, total do
            local unitToken = groupType .. idx
            if UnitExists(unitToken) and UnitName(unitToken) == pinned then
                return unitToken
            end
        end
        -- pinned player not in group; fall through to auto-detect
    end
    for idx = 1, total do
        local unitToken = groupType .. idx
        if UnitExists(unitToken) and not UnitIsUnit(unitToken, "player") then
            if UnitGroupRolesAssigned(unitToken) == "TANK" then
                return unitToken
            end
        end
    end
    return nil
end

function mod.Print(msg)
    print("|cff4cc9f0Tank Kit:|r " .. tostring(msg))
end

-- Points the frame at the co-tank while the player is tanking alongside one,
-- and hides it otherwise. Test mode owns the unit ("player") until it is
-- switched off, so roster, zoning and end-of-combat events leave it alone:
-- testing solo usually means no TANK role, which used to hide the frame the
-- moment the first fight ended.
function mod.AssignCoTank(widget)
    if mod.isTestMode then
        return
    end
    local myRole = UnitGroupRolesAssigned("player")
    local currentTank = mod.FindCoTank()
    if myRole == "TANK" and currentTank then
        widget:SetAttribute("unit", currentTank)
        RegisterUnitWatch(widget)
    else
        UnregisterUnitWatch(widget)
        widget:Hide()
        widget:SetAttribute("unit", nil)
    end
end

-- Turns test mode on or off. Shared by /ctank test and the options panel,
-- which used to do this separately and had drifted: the panel never refreshed
-- the preview icons, so its test mode showed no mock debuffs. Returns false
-- in combat, where changing a secure frame's unit or visibility is blocked.
function mod.SetTestMode(enabled)
    if InCombatLockdown() then
        return false
    end
    mod.isTestMode = enabled and true or false
    local widget = CoTankAuras
    if widget then
        if mod.isTestMode then
            UnregisterUnitWatch(widget)
            widget:SetAttribute("unit", "player")
            widget:Show()
        else
            mod.AssignCoTank(widget)
        end
        -- Test mode swaps the live AuraContainers for the mock icons, and
        -- back again, so both displays have to be told either way.
        widget:RefreshDebuffLayout()
        widget:RefreshDefensiveLayout()
        widget:UpdateVisuals()
    end
    mod.Options:SyncTestButton()
    return true
end

-- ── Position helpers ───────────────────────────────────────────────────────
function mod.SavePosition(widget)
    local anchorPoint, _, relPoint, posX, posY = widget:GetPoint()
    local saved = mod.DB()
    saved.point = anchorPoint
    saved.relPoint = relPoint
    saved.x = posX
    saved.y = posY
end

function mod.ApplyPosition(widget)
    local saved = mod.DB()
    widget:ClearAllPoints()
    widget:SetPoint(saved.point or "CENTER", UIParent, saved.relPoint or "CENTER", saved.x or 0, saved.y or 0)
end

function mod.ResetPosition(widget)
    local saved = mod.DB()
    saved.point = "CENTER"
    saved.relPoint = "CENTER"
    saved.x = 0
    saved.y = 0
    mod.ApplyPosition(widget)
end

-- ── Frame initialization ───────────────────────────────────────────────────
-- Called after all modules have loaded (ADDON_LOADED fires after all TOC files run).
local function InitializeFrame()
    mod.DB()

    if InCombatLockdown() then
        return
    end

    local K = mod.K

    local widget =
        CreateFrame("Button", "CoTankAuras", UIParent, "SecureUnitButtonTemplate, BackdropTemplate")
    widget:SetAttribute("type1", "target") -- left-click targets the co-tank

    Mixin(widget, mod.Mixin) -- ns.Mixin defined in modules/mixin.lua

    local saved = mod.DB()
    widget:SetSize(saved.frameWidth or K.DEFAULT_WIDTH, saved.frameHeight or K.DEFAULT_HEIGHT)
    widget:SetMovable(true)
    widget:SetClampedToScreen(true)

    -- Background
    widget.bg = widget:CreateTexture(nil, "BACKGROUND")
    widget.bg:SetAllPoints()
    widget.bg:SetColorTexture(0.05, 0.07, 0.11, 0.92)
    widget:SetBackdrop({ edgeFile = K.BACKDROP_TEXTURE, edgeSize = 1 })
    widget:SetBackdropBorderColor(0.08, 0.12, 0.20, 1)

    -- Health bar
    widget.health = CreateFrame("StatusBar", nil, widget)
    widget.health:SetPoint("TOPLEFT", 1, -1)
    widget.health:SetPoint("BOTTOMRIGHT", -1, K.POWER_BAR_HEIGHT + 2)
    widget.health.statusBarTextureString = saved.barTexture or K.BACKDROP_TEXTURE
    widget.health:SetStatusBarTexture(widget.health.statusBarTextureString)

    -- Power bar
    widget.power = CreateFrame("StatusBar", nil, widget)
    widget.power:SetHeight(K.POWER_BAR_HEIGHT)
    widget.power:SetPoint("TOPLEFT", widget.health, "BOTTOMLEFT", 0, -1)
    widget.power:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -1, 1)
    widget.power.statusBarTextureString = saved.barTexture or K.BACKDROP_TEXTURE
    widget.power:SetStatusBarTexture(widget.power.statusBarTextureString)
    widget.powerBG = widget.power:CreateTexture(nil, "BACKGROUND")
    widget.powerBG:SetAllPoints()
    widget.powerBG:SetColorTexture(0, 0, 0, 0.5)

    -- Name text
    local face = mod.FontPath()
    local nameSize = saved.nameFontSize or K.DEFAULT_NAME_FONT_SIZE
    local hpSize = saved.hpFontSize or K.DEFAULT_HP_FONT_SIZE
    widget.nameText = widget.health:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    widget.nameText:SetFont(face, nameSize, mod.FontFlags())
    widget.nameText:SetPoint("BOTTOMLEFT", widget.health, "LEFT", 6, 4)
    widget.nameText:SetJustifyH("LEFT")
    widget.nameText:SetIgnoreParentAlpha(false)
    widget.nameText.rawText = ""

    -- HP text
    widget.hpText = widget.health:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    widget.hpText:SetFont(face, hpSize, mod.FontFlags())
    widget.hpText:SetPoint("TOPLEFT", widget.health, "LEFT", 6, -4)
    widget.hpText:SetJustifyH("LEFT")
    widget.hpText:SetTextColor(0.9, 0.9, 0.9)
    widget.hpText:SetIgnoreParentAlpha(false)

    -- Preview icon frames (test mode / edit mode only)
    widget:CreateDebuffContainer()
    widget:CreateDefensiveContainer()
    widget:CreatePrivateAnchorContainers()
    widget:CreateDeadOverlay()

    -- Live aura display. Since 12.1 the engine owns this: AuraContainers can
    -- only be created out of combat, which the guard at the top of this
    -- function already ensures.
    mod.CreateDebuffAuraContainer(widget)
    mod.CreateDefensiveAuraContainer(widget)
    mod.MigratePrivateAuraRow()

    -- Click-through
    if saved.clickThrough then
        widget:EnableMouse(false)
    end

    -- Frame scripts
    widget:SetScript("OnAttributeChanged", widget.OnAttributeChanged)
    widget:SetScript("OnSizeChanged", function(s, wid, hgt)
        s:OnSizeChangedHandler(wid, hgt)
    end)
    widget:SetScript("OnEvent", widget.UpdateVisuals)
    widget:SetScript("OnShow", function(self)
        self:UpdateHealthBarColor()
        self:AttachPrivateAnchors()
    end)
    widget:SetScript("OnHide", function(self)
        self:CleanupPrivateAnchors()
    end)
    widget:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and not InCombatLockdown() then
            mod.Options:Open()
        end
    end)
    -- Placed with CludesUI Layout Mode (modules/externals.lua registers it).

    -- Apply saved position
    mod.ApplyPosition(widget)

    -- Group / role manager - shows/hides the frame as roster changes
    local manager = CreateFrame("Frame")
    manager:RegisterEvent("GROUP_ROSTER_UPDATE")
    manager:RegisterEvent("PLAYER_REGEN_ENABLED")
    manager:RegisterEvent("PLAYER_ENTERING_WORLD")
    local function OnGroupEvent(evt)
        if InCombatLockdown() then
            return
        end
        -- Anything the secrecy rules blocked mid-fight gets replayed here:
        -- aura sound registration, and restyling of AuraButtons that were
        -- forbidden while auras were secret.
        if evt == "PLAYER_REGEN_ENABLED" then
            mod.Alert:FlushPendingAuraSounds()
            mod.FlushPendingRestyle()
        end
        if not widget.anchorFrames then
            widget:CreatePrivateAnchorContainers()
        end
        mod.AssignCoTank(widget)
        -- Retry the AuraContainers in case an earlier attempt could not create them.
        mod.CreateDebuffAuraContainer(widget)
        mod.CreateDefensiveAuraContainer(widget)
        mod.MigratePrivateAuraRow()
        widget:UpdateHealthBarColor()
        widget:UpdateVisuals()
        widget:RefreshAuraLayout()
        widget:RefreshDebuffLayout()
        widget:RefreshDefensiveLayout()
    end
    manager:SetScript("OnEvent", function(_, evt)
        OnGroupEvent(evt)
    end)

    -- Clique support
    _G["ClickCastFrames"] = _G["ClickCastFrames"] or {}
    _G["ClickCastFrames"][widget] = true

    -- Initialise alert and options sub-systems (modules already loaded by TOC order)
    mod.Alert:Initialize()
    mod.Options:Initialize()

    -- Started late because the addon loaded in combat: the login events that
    -- normally assign the co-tank have already fired, so run that pass now.
    if IsLoggedIn() then
        OnGroupEvent("PLAYER_REGEN_ENABLED")
    end
end

-- ── Bootstrap ──────────────────────────────────────────────────────────────
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, evt, name)
    if evt == "ADDON_LOADED" then
        if name ~= addonName then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        -- The frame is secure and AuraContainers cannot be created in combat,
        -- so a reload or reconnect mid-pull waits for combat to end. Before
        -- this, the addon simply stayed blank for the rest of the session.
        if InCombatLockdown() then
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
    else
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    local success, err = pcall(InitializeFrame)
    if not success then
        print("|cffff4040Tank Kit load error:|r " .. tostring(err))
    end
end)

-- ── Slash Commands ─────────────────────────────────────────────────────────
local CMD = "|cffffff00/ctank|r"
local ON = "|cff55ff55ON|r"
local OFF = "|cffff5555OFF|r"

local function handleSlashCommand(msg)
    local cmd = ((msg or ""):match("^%s*(%S*)") or ""):lower()

    if cmd == "" or cmd == "config" or cmd == "options" or cmd == "menu" then
        mod.Options:Open()
        return
    end

    if cmd == "help" then
        mod.Print("|cffaaaaaa--- Commands ---")
        DEFAULT_CHAT_FRAME:AddMessage(
            "  " .. CMD .. " (or |cffffff00/tankkit|r) - open the Tank Kit settings"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "  " .. CMD .. " |cffffff00debuffs|r       - toggle the tank debuff row on/off"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "  " .. CMD .. " |cffffff00sound|r         - check the alert sound is registered"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "  " .. CMD .. " |cffffff00sounds|r [text] - list selectable sound names"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "  " .. CMD .. " |cffffff00sound set|r <name> - use that sound for alerts"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "  " .. CMD .. " |cffffff00test|r          - toggle test mode (watch yourself)"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "  " .. CMD .. " |cffffff00reset|r         - reset frame position to center"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "  " .. CMD .. " |cffffff00move|r          - open Layout Mode to move the frames"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "  " .. CMD .. " |cffffff00pin|r [name]    - pin current (or named) co-tank"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "  " .. CMD .. " |cffffff00unpin|r         - clear pin, auto-detect co-tank"
        )
        DEFAULT_CHAT_FRAME:AddMessage("  " .. CMD .. " |cffffff00help|r          - show this list")
        return
    end

    if cmd == "sounds" then
        local filter = (msg or ""):match("^%s*%S+%s+(.+)")
        mod.Alert:PrintSoundNames(filter)
        return
    end

    if cmd == "sound" then
        local rest = (msg or ""):match("^%s*%S+%s+(.+)")
        local name = rest and rest:match("^set%s+(.+)")
        if name then
            mod.Alert:SetSound(name)
        else
            mod.Alert:ReportAuraSounds()
        end
        return
    end

    if cmd == "debuffs" or cmd == "debuff" then
        local enabled = mod.ToggleDebuffs()
        mod.Print("Tank debuffs: " .. (enabled and ON or OFF))
        return
    end

    if cmd == "test" then
        if mod.SetTestMode(not mod.isTestMode) then
            mod.Print("Test Mode: " .. (mod.isTestMode and ON or OFF))
        else
            mod.Print("|cffff4040Cannot change test mode during combat.|r")
        end
        return
    end

    if cmd == "reset" then
        if InCombatLockdown() then
            mod.Print("|cffff4040Cannot reset during combat.|r")
            return
        end
        if CoTankAuras then
            mod.ResetPosition(CoTankAuras)
        end
        mod.Print("Position reset.")
        return
    end

    if cmd == "lock" or cmd == "unlock" or cmd == "move" then
        -- The frame is placed with CludesUI Layout Mode.
        if InCombatLockdown() then
            mod.Print("Layout Mode cannot open in combat.")
            return
        end
        CludesUI:EnsureUnlockCore()
        if CludesUI._openUnlockMode then
            CludesUI._openUnlockMode()
        end
        return
    end

    if cmd == "pin" then
        local rest = (msg or ""):match("^%s*%S+%s+(.+)") or ""
        rest = rest:match("^%s*(.-)%s*$")
        if rest ~= "" then
            mod.DB().pinnedTank = rest
            mod.Print("Pinned co-tank: |cff5ab4ff" .. rest .. "|r")
        else
            local coTank = mod.FindCoTank()
            local name = coTank and UnitName(coTank)
            if name then
                mod.DB().pinnedTank = name
                mod.Print("Pinned co-tank: |cff5ab4ff" .. name .. "|r")
            else
                mod.Print("|cffff4040No co-tank found. Use /ctank pin PlayerName|r")
            end
        end
        return
    end

    if cmd == "unpin" then
        mod.DB().pinnedTank = nil
        mod.Print("Pin cleared - auto-detecting co-tank.")
        return
    end

    mod.Print("Unknown command - use " .. CMD .. " help")
end

SLASH_COTANKAURAS1 = "/ctank"
SLASH_COTANKAURAS2 = "/tankkit"
SlashCmdList["COTANKAURAS"] = function(msg)
    local success, err = pcall(handleSlashCommand, msg)
    if not success then
        mod.Print("|cffff4040Error: " .. tostring(err) .. "|r")
    end
end
