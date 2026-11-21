if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_Friends_Options.lua - the Friends List module's settings page.
--
--  One page (DISPLAY): class icon theme, class-coloured names, the window's
--  border (size and colour), accent colours, faction banners, region icons,
--  and auto-accepting group invites from friends (a cog adds guildmates).
--  Every setting lives in the Friends List module's saved profile
--  (_G._CUFR_DB.profile.friends) and is applied through the module's own
--  hooks. Also /cfr, which opens the page.
--
--  Under a stock style (Blizzard Style / Classic WoW UI) Blizzard's own window
--  stays: the class icon, class colour and region mark still apply to its
--  rows, and the border, accent and banner rows are gated off.
-------------------------------------------------------------------------------
local MODULE = "CludesUIFriends"
local mod = CUI._ModuleNS[MODULE] -- published by the module when it loads
if not mod then
    return -- the module is disabled: no page
end

-- Frames built here go through the options frame pool (a kept page gets its
-- previous build's frames back, reset); anywhere else this is CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

-- The module's settings table, or nil before its saved data exists.
local function Settings()
    local db = _G._CUFR_DB
    return db and db.profile and db.profile.friends
end

-- Calls a hook the Friends List module publishes, if it is there.
local function Call(name)
    local hook = _G[name]
    if hook then hook() end
end

-- A display toggle repaints the rows: the legacy window's row pass and a
-- decoration-only pass over the 12.1 cards (never Blizzard's view:Refresh,
-- which rebuilds the list from our code and taints whispers).
local function RepaintRows()
    Call("_CUFR_ProcessFriendButtons")
    Call("_CUFR_RedecorateTiles")
end

local function Reapply() Call("_CUFR_ApplyFriends") end

-- get/set for one setting: default when unset (or, with onByDefault, "on
-- unless set false"), and after() once it is written.
local function Bind(key, after, default, onByDefault)
    return function()
        local cfg = Settings()
        if not cfg then return default end
        if onByDefault then return cfg[key] ~= false end
        local value = cfg[key]
        if value == nil then return default end
        return value
    end, function(value)
        local cfg = Settings()
        if not cfg then return end
        cfg[key] = value
        if after then after() end
    end
end

local function Toggle(text, key, after, onByDefault, tooltip)
    local get, set = Bind(key, after, nil, onByDefault)
    return { type = "toggle", text = text, tooltip = tooltip, getValue = get, setValue = set }
end

local CHROME_TIP = "The Friends List window skin draws this border (Window Skins > Window Skins)."

local function BuildPage(_, host, yOffset)
    local W = CUI.Widgets
    local y = yOffset
    local h, row

    CUI:ClearContentHeader()

    -- Rows that only drive our own window are gated off under a stock style.
    local BS = CUI.BlizzStyle
    local function Gate(rowConf)
        if BS then BS.Gate("friends", rowConf) end
        return rowConf
    end
    -- The border rows drive this module's flat look only; with the Window
    -- Skins "Friends List" card the skin draws the frame.
    local function Chrome() return mod.FR_ChromeShell() end

    _, h = W:SectionHeader(host, "DISPLAY", y)
    y = y - h
    if BS then y = BS.Note(host, y, "friends") end

    -- Class Icon Theme | Class Color Names
    local iconGet, iconSet = Bind("iconStyle", RepaintRows, "modern")
    _, h = W:DualRow(host, y, {
        type = "dropdown",
        text = "Class Icon Theme",
        values = CUI.FriendsKit.ICON_STYLE_VALUES, -- shared with the WoW Forever Friends card
        order = CUI.FriendsKit.ICON_STYLE_ORDER,
        getValue = iconGet,
        setValue = iconSet,
    }, Toggle("Class Color Names", "classColorNames", RepaintRows))
    y = y - h

    -- Border Size | Border Color (custom, or the accent colour)
    local sizeGet, sizeSet = Bind("borderSize", function()
        Reapply()
        CUI:RefreshPage()
    end, 0)
    local function SwatchAlpha(lit)
        return function()
            local cfg = Settings()
            if not cfg or not cfg.enabled then return 0.15 end
            return lit(cfg) and 1 or 0.3
        end
    end
    _, h = W:DualRow(
        host,
        y,
        Gate({
            type = "slider",
            text = "Border Size",
            min = 0,
            max = 4,
            step = 1,
            disabled = Chrome,
            disabledTooltip = CHROME_TIP,
            rawTooltip = true,
            getValue = sizeGet,
            setValue = sizeSet,
        }),
        Gate({
            type = "multiSwatch",
            text = "Border Color",
            disabled = function()
                if Chrome() then return true end
                local cfg = Settings()
                return not cfg or (cfg.borderSize or 0) == 0
            end,
            disabledTooltip = function() return Chrome() and CHROME_TIP or "Set Border Size above 0" end,
            rawTooltip = true,
            swatches = {
                {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local cfg = Settings()
                        if not cfg then return 0.05, 0.05, 0.05 end
                        return cfg.borderR, cfg.borderG, cfg.borderB
                    end,
                    setValue = function(red, green, blue)
                        local cfg = Settings()
                        if cfg then
                            cfg.borderR, cfg.borderG, cfg.borderB = red, green, blue
                            Reapply()
                        end
                    end,
                    -- While the accent is in use, a click switches back to the
                    -- custom colour instead of opening the picker.
                    onClick = function(self)
                        local cfg = Settings()
                        if not cfg then return end
                        if cfg.useClassColor then
                            cfg.useClassColor = false
                            Reapply()
                            CUI:RefreshPage()
                        elseif self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = SwatchAlpha(function(cfg) return not cfg.useClassColor end),
                },
                {
                    tooltip = "Accent Colored",
                    hasAlpha = false,
                    getValue = function() return CUI.GetAccentColor() end,
                    setValue = function() end,
                    onClick = function()
                        local cfg = Settings()
                        if cfg then
                            cfg.useClassColor = true
                            Reapply()
                            CUI:RefreshPage()
                        end
                    end,
                    refreshAlpha = SwatchAlpha(function(cfg) return cfg.useClassColor end),
                },
            },
        })
    )
    y = y - h

    -- Enable Accent Colors | Enable Faction Banners (both on unless turned off)
    _, h = W:DualRow(
        host,
        y,
        Gate(Toggle("Enable Accent Colors", "accentColors", Reapply, true)),
        Gate(Toggle("Enable Faction Banners", "factionBanners", RepaintRows, true))
    )
    y = y - h

    -- Show Region Icons | Auto-Accept Friend Invites
    row, h = W:DualRow(
        host,
        y,
        Toggle(
            "Show Region Icons",
            "showRegionIcons",
            RepaintRows,
            true,
            "Shows a map icon of the friend's region if they are not playing within your region"
        ),
        Toggle("Auto-Accept Friend Invites", "autoAcceptFriendInvites", function()
            Call("_CUFR_SyncAutoAccept")
            CUI:RefreshPage() -- the cog's disabled state follows the toggle
        end, false, "Auto-accepts all group invites from people on your friends list")
    )
    y = y - h

    -- Guildmates extend the friends auto-accept, so their cog sits on that
    -- toggle and is blocked while it is off.
    if not CUI._prebuilding then
        local guildGet, guildSet = Bind("autoAcceptGuildInvites")
        CUI.BuildInlineCog(row._rightRegion, {
            title = "Auto Accept Settings",
            rows = {
                { type = "toggle", label = "Accept Invites from Guildmates", get = guildGet, set = guildSet },
            },
            disabled = function()
                local cfg = Settings()
                return not (cfg and cfg.autoAcceptFriendInvites)
            end,
            disabledTooltip = "Auto-Accept Friend Invites",
        })
    end

    return math.abs(y)
end

local function Register()
    if not CUI or not CUI.RegisterModule then return end
    CUI:RegisterModule(MODULE, {
        title = "Friends List",
        description = "Custom friends list with groups, notes, and realm grouping.",
        pages = { "Friends" },
        buildPage = function(page, host, yOffset)
            if page == "Friends" then return BuildPage(page, host, yOffset) end
        end,
        onReset = function()
            local db = _G._CUFR_DB
            if db and db.ResetProfile then db:ResetProfile() end
            CUI:InvalidatePageCache()
            Reapply()
            Call("_CUFR_SyncAutoAccept")
            RepaintRows()
        end,
    })

    SLASH_EFR1 = "/cfr"
    SlashCmdList.EFR = function()
        if not (InCombatLockdown and InCombatLockdown()) then CUI:ShowModule(MODULE) end
    end
end

-- The options addon loads on demand, after PLAYER_LOGIN: then register at once.
if IsLoggedIn() then
    Register()
else
    local login = CreateFrame("Frame")
    login:RegisterEvent("PLAYER_LOGIN")
    login:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        Register()
    end)
end
