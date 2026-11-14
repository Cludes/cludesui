if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Friends_Options.lua
--  Registers the Friends List module with CludesUI.
--  All get/set calls go through the global bridge to the addon's DB profile.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIFriends"
local mod = CludesUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page

local PAGE_CHAT = "Chat"
local PAGE_MINIMAP = "Minimap"
local PAGE_FRIENDS = "Friends"
local PAGE_QUEST_TRACKER = "Quest Tracker"
local PAGE_CURSOR = "Cursor"
local PAGE_DMG_METERS = "Damage Meters"

local SECTION_CHAT = "CHAT"
local SECTION_MINIMAP = "DISPLAY"

-- Page reuse: a frame this file builds goes through the options frame pool
-- (CludesUI_FramePool.lua, the options addon's first file), which hands a
-- kept page its previous build's frames back reset to new; on any other
-- parent it is the plain CreateFrame. The page builds only factory widgets.
local CreateFrame = CludesUI._Pool.CreateFrame

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not CludesUI or not CludesUI.RegisterModule then
        return
    end

    ---------------------------------------------------------------------------
    --  DB helpers
    ---------------------------------------------------------------------------
    local saved

    C_Timer.After(0, function()
        saved = _G._CUFR_DB
    end)

    local function DB()
        if not saved then
            saved = _G._CUFR_DB
        end
        return saved and saved.profile
    end

    local function ChatDB()
        local p = DB()
        return p and p.chat
    end

    local function MinimapDB()
        local p = DB()
        return p and p.minimap
    end

    local function FriendsDB()
        local p = DB()
        return p and p.friends
    end

    ---------------------------------------------------------------------------
    --  Refresh helpers
    ---------------------------------------------------------------------------
    local function RefreshChat()
        if _G._CUBS_ApplyChat then
            _G._CUBS_ApplyChat()
        end
    end

    local function RefreshMinimap()
        if _G._CUBS_ApplyMinimap then
            _G._CUBS_ApplyMinimap()
        end
    end

    local function RefreshFriends()
        if _G._CUFR_ApplyFriends then
            _G._CUFR_ApplyFriends()
        end
    end

    local function RefreshAll()
        if _G._CUBS_ApplyAll then
            _G._CUBS_ApplyAll()
        end
    end

    ---------------------------------------------------------------------------
    --  Chat Page
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Minimap Page
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Friends List Page
    ---------------------------------------------------------------------------

    -- Class Icon Theme choices (shared with the WoW Forever Friends List card)
    local ICON_STYLE_VALUES = CludesUI.FriendsKit.ICON_STYLE_VALUES
    local ICON_STYLE_ORDER = CludesUI.FriendsKit.ICON_STYLE_ORDER

    -- Live repaint after a display toggle: the legacy list's row pass, plus a
    -- decoration-only pass over the 12.1 cards (never Blizzard's view:Refresh,
    -- which regenerates the list data from our execution and taints whispers).
    local function RepaintFriendRows()
        if _G._CUFR_ProcessFriendButtons then
            _G._CUFR_ProcessFriendButtons()
        end
        if _G._CUFR_RedecorateTiles then
            _G._CUFR_RedecorateTiles()
        end
    end

    local function BuildFriendsPage(page, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local posY = yOffset
        local _, row, hgt

        CludesUI:ClearContentHeader()

        -- Stock styles (Blizzard Style / Classic WoW UI) keep Blizzard's own
        -- window and rows on either friends window (12.1 Social UI or the
        -- legacy one) and add the class icon, class-coloured name and region
        -- mark to them, so those rows and auto-accept stay. The border and
        -- accent rows drive only the CludesUI skin of the legacy window,
        -- faction banners also the 12.1 tiles; all three hide under stock.
        local BS = CludesUI.BlizzStyle
        local function Gate(conf)
            if BS then
                BS.Gate("friends", conf)
            end
            return conf
        end
        -- Border Size / Border Color drive only this module's own flat look;
        -- the Window Skins "Friends List" card draws the frame otherwise.
        local CHROME_BORDER_TIP =
            "The Friends List window skin draws this border (Window Skins > Window Skins)."

        -- DISPLAY
        _, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
        posY = posY - hgt
        if BS then
            posY = BS.Note(hostFrame, posY, "friends")
        end

        -- Class Icon Theme | Class Color Names
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Class Icon Theme",
            values = ICON_STYLE_VALUES,
            order = ICON_STYLE_ORDER,
            getValue = function()
                local f = FriendsDB()
                return f and f.iconStyle or "modern"
            end,
            setValue = function(val)
                local f = FriendsDB()
                if not f then
                    return
                end
                f.iconStyle = val
                RepaintFriendRows()
            end,
        }, {
            type = "toggle",
            text = "Class Color Names",
            getValue = function()
                local f = FriendsDB()
                return f and f.classColorNames
            end,
            setValue = function(val)
                local f = FriendsDB()
                if not f then
                    return
                end
                f.classColorNames = val
                RepaintFriendRows()
            end,
        })
        posY = posY - hgt

        -- Border Size | Border Color
        _, hgt = W:DualRow(
            hostFrame,
            posY,
            Gate({
                type = "slider",
                text = "Border Size",
                min = 0,
                max = 4,
                step = 1,
                disabled = function()
                    return mod.FR_ChromeShell()
                end,
                disabledTooltip = CHROME_BORDER_TIP,
                rawTooltip = true,
                getValue = function()
                    local f = FriendsDB()
                    return f and f.borderSize or 0
                end,
                setValue = function(val)
                    local f = FriendsDB()
                    if not f then
                        return
                    end
                    f.borderSize = val
                    RefreshFriends()
                    CludesUI:RefreshPage()
                end,
            }),
            Gate({
                type = "multiSwatch",
                text = "Border Color",
                disabled = function()
                    if mod.FR_ChromeShell() then
                        return true
                    end
                    local f = FriendsDB()
                    return not f or (f.borderSize or 0) == 0
                end,
                disabledTooltip = function()
                    return mod.FR_ChromeShell() and CHROME_BORDER_TIP or "Set Border Size above 0"
                end,
                rawTooltip = true,
                swatches = {
                    {
                        tooltip = "Custom Color",
                        hasAlpha = false,
                        getValue = function()
                            local c = FriendsDB()
                            if not c then
                                return 0.05, 0.05, 0.05
                            end
                            return c.borderR, c.borderG, c.borderB
                        end,
                        setValue = function(r, g, b)
                            local c = FriendsDB()
                            if not c then
                                return
                            end
                            c.borderR, c.borderG, c.borderB = r, g, b
                            RefreshFriends()
                        end,
                        onClick = function(self)
                            local c = FriendsDB()
                            if not c then
                                return
                            end
                            if c.useClassColor then
                                c.useClassColor = false
                                RefreshFriends()
                                CludesUI:RefreshPage()
                                return
                            end
                            if self._eabOrigClick then
                                self._eabOrigClick(self)
                            end
                        end,
                        refreshAlpha = function()
                            local c = FriendsDB()
                            if not c or not c.enabled then
                                return 0.15
                            end
                            return c.useClassColor and 0.3 or 1
                        end,
                    },
                    {
                        tooltip = "Accent Colored",
                        hasAlpha = false,
                        getValue = function()
                            local ar, ag, ab = CludesUI.GetAccentColor()
                            return ar, ag, ab
                        end,
                        setValue = function() end,
                        onClick = function()
                            local c = FriendsDB()
                            if not c then
                                return
                            end
                            c.useClassColor = true
                            RefreshFriends()
                            CludesUI:RefreshPage()
                        end,
                        refreshAlpha = function()
                            local c = FriendsDB()
                            if not c or not c.enabled then
                                return 0.15
                            end
                            return c.useClassColor and 1 or 0.3
                        end,
                    },
                },
            })
        )
        posY = posY - hgt

        -- Enable Accent Colors | Enable Faction Banners
        _, hgt = W:DualRow(
            hostFrame,
            posY,
            Gate({
                type = "toggle",
                text = "Enable Accent Colors",
                getValue = function()
                    local f = FriendsDB()
                    return f and (f.accentColors ~= false)
                end,
                setValue = function(val)
                    local f = FriendsDB()
                    if not f then
                        return
                    end
                    f.accentColors = val
                    RefreshFriends()
                end,
            }),
            Gate({
                type = "toggle",
                text = "Enable Faction Banners",
                getValue = function()
                    local f = FriendsDB()
                    return f and (f.factionBanners ~= false)
                end,
                setValue = function(val)
                    local f = FriendsDB()
                    if not f then
                        return
                    end
                    f.factionBanners = val
                    RepaintFriendRows()
                end,
            })
        )
        posY = posY - hgt

        -- Show Region Icons | Auto-Accept Friend Invites
        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Region Icons",
            tooltip = "Shows a map icon of the friend's region if they are not playing within your region",
            getValue = function()
                local f = FriendsDB()
                return f and (f.showRegionIcons ~= false)
            end,
            setValue = function(val)
                local f = FriendsDB()
                if not f then
                    return
                end
                f.showRegionIcons = val
                RepaintFriendRows()
            end,
        }, {
            type = "toggle",
            text = "Auto-Accept Friend Invites",
            tooltip = "Auto-accepts all group invites from people on your friends list",
            getValue = function()
                local f = FriendsDB()
                return f and f.autoAcceptFriendInvites
            end,
            setValue = function(val)
                local f = FriendsDB()
                if not f then
                    return
                end
                f.autoAcceptFriendInvites = val
                if _G._CUFR_SyncAutoAccept then
                    _G._CUFR_SyncAutoAccept()
                end
                CludesUI:RefreshPage() -- update the auto-accept cog disabled state
            end,
        })
        posY = posY - hgt

        -- Guildmate option lives in a cog on Auto-Accept Friend Invites; it
        -- only extends that feature, so the cog blocks while the toggle is off.
        if not CludesUI._prebuilding then
            local region = row._rightRegion
            local function autoAcceptOff()
                local f = FriendsDB()
                return not (f and f.autoAcceptFriendInvites)
            end
            CludesUI.BuildInlineCog(region, {
                title = "Auto Accept Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Accept Invites from Guildmates",
                        get = function()
                            local f = FriendsDB()
                            return f and f.autoAcceptGuildInvites
                        end,
                        set = function(val)
                            local f = FriendsDB()
                            if not f then
                                return
                            end
                            f.autoAcceptGuildInvites = val
                        end,
                    },
                },
                disabled = autoAcceptOff,
                disabledTooltip = "Auto-Accept Friend Invites",
            })
        end

        return math.abs(posY)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    CludesUI:RegisterModule("CludesUIFriends", {
        title = "Friends List",
        description = "Custom friends list with groups, notes, and realm grouping.",
        pages = { "Friends" },
        buildPage = function(page, hostFrame, yOffset)
            if page == "Friends" then
                return BuildFriendsPage(page, hostFrame, yOffset)
            end
        end,
        onReset = function()
            if _G._CUFR_DB and _G._CUFR_DB.ResetProfile then
                _G._CUFR_DB:ResetProfile()
            end
            CludesUI:InvalidatePageCache()
            if _G._CUFR_ApplyFriends then
                _G._CUFR_ApplyFriends()
            end
            if _G._CUFR_SyncAutoAccept then
                _G._CUFR_SyncAutoAccept()
            end
            RepaintFriendRows()
        end,
    })

    SLASH_EFR1 = "/cfr"
    SlashCmdList.EFR = function()
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        CludesUI:ShowModule("CludesUIFriends")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then
    initFrame:GetScript("OnEvent")(initFrame)
end
