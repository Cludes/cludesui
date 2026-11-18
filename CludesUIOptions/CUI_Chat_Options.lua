if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Chat_Options.lua
--
--  Options page for CludesUI Chat: visibility, background opacity/color,
--  top accent line.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIChat"] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page
local CHAT = mod.ECHAT

-- Page reuse: the frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua, the options addon's first file), which hands a
-- kept page its previous build's frames back reset to new; on any other
-- parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

CludesUI.AtOptionsLogin(function()
    if not CHAT then
        return
    end

    local function DB()
        local d = _G._CUCHAT_DB
        if d and d.profile and d.profile.chat then
            return d.profile.chat
        end
        return {}
    end
    local function Cfg(keyName)
        return DB()[keyName]
    end
    -- Row getters over Cfg: a key's value (or a default), or whether it is true.
    local function CfgOr(key, default)
        return function()
            return Cfg(key) or default
        end
    end
    local function CfgIs(key)
        return function()
            return Cfg(key) == true
        end
    end
    local function Set(keyName, val)
        DB()[keyName] = val
    end

    local function RefreshAll()
        if CHAT.ApplyBackground then
            CHAT.ApplyBackground()
        end
        if CHAT.ApplyFonts then
            CHAT.ApplyFonts()
        end
        if CHAT.RefreshVisibility then
            CHAT.RefreshVisibility()
        end
    end

    local function BuildPage(pageName, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local Pix = CludesUI.PP
        local cursorY = yOffset
        local _, height

        if CludesUI.ClearContentHeader then
            CludesUI:ClearContentHeader()
        end
        hostFrame._showRowDivider = true

        local isChat = pageName == "Chat"
        local isTabs = pageName == "Tabs"
        local isSidebar = pageName == "Sidebar"

        -- Stock styles (Blizzard Style / Classic WoW UI) reveal Blizzard's own
        -- chat frame art and input box: the panel background, panel border and
        -- input layout rows only apply to the CludesUI look and hide there.
        -- Blizzard Style also shows Blizzard's own tabs (no Tabs page; a deep
        -- link lands on the banner alone); Classic keeps the tab typography.
        local BS = CludesUI.BlizzStyle
        local STOCK = BS and BS.Get("chat")
        -- WoW Forever (Blizzard Style's Forever variant) draws its own panel,
        -- input box and ghost tabs: the panel fill, input height and tab
        -- typography come back; every other stock gate stays.
        local FV = STOCK and BS.Forever("chat")
        if isTabs and STOCK then
            cursorY = BS.Note(hostFrame, cursorY, "chat")
            if BS.Active("chat") == "blizzard" and not FV then
                isTabs = false
            end
        end

        if isChat then
            -- Chat position is an CUI unlock element now; the old Edit Mode
            -- reposition banner and its Force Chat on Screen link are gone.

            -- -- DISPLAY -----------------------------------------------------------
            local heading
            heading, height = W:SectionHeader(hostFrame, "DISPLAY", cursorY)
            cursorY = cursorY - height
            CludesUI.BuildSectionUnlockJump(heading, { key = "ECHAT_MainChat" })
            if BS then
                cursorY = BS.Note(hostFrame, cursorY, "chat")
            end

            -- Row 1: Visibility (one control; no mouseover for chat frames) | Lock Main Chat Size
            _, height = CludesUI.BuildVisibilityRow(W, hostFrame, cursorY, {
                getStore = DB,
                legacyKey = "visibility",
                caps = { partyIncludesRaid = false, noMouseover = true, luaDragonriding = true },
                onChanged = function()
                    if CHAT.ResetIdleTimer then
                        CHAT.ResetIdleTimer()
                    end
                    if CHAT.ApplyIdleFadeHoverMotion then
                        CHAT.ApplyIdleFadeHoverMotion()
                    end
                    RefreshAll()
                end,
                onOptionChanged = RefreshAll,
            }, {
                type = "toggle",
                text = "Lock Main Chat Size",
                tooltip = "Hides the resize handle on the main chat frame, preventing accidental resizing.",
                getValue = CfgOr("lockChatSize", false),
                setValue = function(val)
                    Set("lockChatSize", val)
                    if CHAT.ApplyLockChatSize then
                        CHAT.ApplyLockChatSize()
                    end
                end,
            })
            cursorY = cursorY - height

            -- Row 2: Background Opacity (+ inline color swatch) | Background
            -- Texture (Unit Frames bar texture catalogue incl. SharedMedia, with
            -- per-item texture preview backgrounds). Stock styles: Blizzard's own
            -- background (its tab menu's Background swatch sets it); WoW Forever
            -- fills its framed boxes with these.
            if not STOCK or FV then
                if CHAT.RefreshBgTextureCatalogue then
                    CHAT.RefreshBgTextureCatalogue()
                end
                local btValues, btOrder = {}, {}
                do
                    local texNames = mod.chatBgTextureNames or {}
                    for _, key in ipairs(mod.chatBgTextureOrder or {}) do
                        if key ~= "---" then
                            btValues[key] = texNames[key] or key
                            btOrder[#btOrder + 1] = key
                        end
                    end
                    local texLookup = mod.chatBgTextures or {}
                    btValues._menuOpts = {
                        itemHeight = 28,
                        background = function(key)
                            return texLookup[key]
                        end,
                    }
                end
                local bgRow
                bgRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "slider",
                    text = "Background Opacity",
                    min = 0,
                    max = 1,
                    step = 0.05,
                    getValue = CfgOr("bgAlpha", 0.65),
                    setValue = function(val)
                        Set("bgAlpha", val)
                        RefreshAll()
                    end,
                }, {
                    type = "dropdown",
                    text = "Background Texture",
                    tooltip = "Texture drawn over the chat background color.",
                    values = btValues,
                    order = btOrder,
                    getValue = CfgOr("bgTexture", "none"),
                    setValue = function(val)
                        Set("bgTexture", val)
                        RefreshAll()
                    end,
                })
                if not CludesUI._prebuilding then
                    local region = bgRow._leftRegion
                    local control = region._control
                    local bgSwatch, bgSwatchRefresh = CludesUI.BuildColorSwatch(
                        region,
                        bgRow:GetFrameLevel() + 3,
                        function()
                            return (Cfg("bgR") or 0.03), (Cfg("bgG") or 0.045), (Cfg("bgB") or 0.05)
                        end,
                        function(r, g, b)
                            Set("bgR", r)
                            Set("bgG", g)
                            Set("bgB", b)
                            RefreshAll()
                        end,
                        false,
                        20
                    )
                    Pix.Point(bgSwatch, "RIGHT", control, "LEFT", -8, 0)
                    CludesUI.RegisterWidgetRefresh(function()
                        bgSwatchRefresh()
                    end)
                end
                cursorY = cursorY - height
            end -- not STOCK or FV

            -- Row 3: Font (+ cog: Outline Mode) | Font Size
            do
                local fontValues, fontOrder = CludesUI.BuildFontDropdownData()
                local fontRow
                fontRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "dropdown",
                    text = "Font",
                    values = fontValues,
                    order = fontOrder,
                    getValue = CfgOr("font", "__global"),
                    setValue = function(val)
                        Set("font", val)
                        CludesUI:ShowConfirmPopup({
                            title = "Reload Required",
                            message = "Font changed. A UI reload is needed to apply the new font.",
                            confirmText = "Reload Now",
                            cancelText = "Later",
                            reload = true,
                        })
                    end,
                }, {
                    type = "slider",
                    text = "Font Size",
                    tooltip = "Applies one text size to every chat window, saved with your profile. Individual windows can still be adjusted from their tab's right-click menu until the next login re-applies the profile size.",
                    min = 8,
                    max = 27,
                    step = 1,
                    getValue = function()
                        if Cfg("chatFontSize") then
                            return Cfg("chatFontSize")
                        end
                        local castFrame = _G.ChatFrame1
                        if castFrame and castFrame.GetFont then
                            local _, fh = castFrame:GetFont()
                            if fh and fh > 0 then
                                return math.floor(fh + 0.5)
                            end
                        end
                        return 14
                    end,
                    setValue = function(val)
                        Set("chatFontSize", val)
                        if CHAT.ApplyChatFontSize then
                            CHAT.ApplyChatFontSize(val)
                        end
                    end,
                })
                -- Cog for Outline Mode
                if not CludesUI._prebuilding then
                    local rrgn = fontRow._leftRegion
                    local outlineValues = {
                        ["__global"] = { text = "CUI Global Default" },
                        ["none"] = { text = "Drop Shadow" },
                        ["outline"] = { text = "Outline" },
                        ["thick"] = { text = "Thick Outline" },
                    }
                    local outlineOrder = { "__global", "none", "outline", "thick" }
                    CludesUI.BuildInlineCog(rrgn, {
                        title = "Font Settings",
                        rows = {
                            {
                                type = "dropdown",
                                label = "Outline Mode",
                                values = outlineValues,
                                order = outlineOrder,
                                get = CfgOr("outlineMode", "__global"),
                                set = function(val)
                                    Set("outlineMode", val)
                                    CludesUI:ShowConfirmPopup({
                                        title = "Reload Required",
                                        message = "Outline mode changed. A UI reload is needed to apply.",
                                        confirmText = "Reload Now",
                                        cancelText = "Later",
                                        reload = true,
                                    })
                                end,
                            },
                        },
                    })
                end
            end
            cursorY = cursorY - height

            -- Outer panel border. Without the extended background, visible tabs get
            -- matching individual borders instead of outlining empty tab-strip space.
            -- Stock styles: Blizzard's own frame border.
            if not STOCK then
                local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
                local borderRow
                borderRow, height = W:DualRow(
                    hostFrame,
                    cursorY,
                    {
                        type = "dropdown",
                        text = "Border Style",
                        values = texValues,
                        order = texOrder,
                        getValue = CfgOr("panelBorderTexture", "solid"),
                        setValue = function(val)
                            Set("panelBorderTexture", val)
                            Set("panelBorderOffsetX", nil)
                            Set("panelBorderOffsetY", nil)
                            Set("panelBorderShiftX", nil)
                            Set("panelBorderShiftY", nil)
                            -- A style with a select colour (Pixels grey) seeds the custom
                            -- colour; the colour mode is kept, every other style keeps its colour.
                            local selC = CludesUI.GetBorderSelectColor(val)
                            if selC then
                                Set("panelBorderColor", selC)
                            end
                            -- A style pick lands on the style's default step, so an exact
                            -- pixel size paired with the old step is cleared (false, not
                            -- nil: the clear must travel through mirror sync).
                            if Cfg("panelBorderThicknessPx") then
                                Set("panelBorderThicknessPx", false)
                            end
                            local defSize = CludesUI.GetBorderDefaultSize("chat", val)
                                or CludesUI.GetBorderTextureDefaultThickness(val)
                            -- Unregistered SharedMedia borders default to the NUMBER 1; this key stores labels.
                            if type(defSize) == "number" then
                                defSize = CludesUI.BORDER_LABEL_OF_STEP[defSize] or "thin"
                            end
                            if defSize then
                                Set("panelBorderThickness", defSize)
                            end
                            if CHAT.ApplyExtendedBackground then
                                CHAT.ApplyExtendedBackground()
                            end
                            -- Rebuild: the offset row below exists only for a textured style.
                            CludesUI:RefreshPage(true)
                        end,
                    },
                    CludesUI.BorderPxSliderCfg({
                        text = "Border Size",
                        -- The step the panel renders with: its label as a step, anything unknown = thin.
                        getStep = function()
                            return CludesUI.BORDER_STEP_OF_LABEL[Cfg("panelBorderThickness") or "none"] or 1
                        end,
                        setStep = function(step)
                            Set("panelBorderThickness", CludesUI.BORDER_LABEL_OF_STEP[step])
                        end,
                        getTex = function()
                            return Cfg("panelBorderTexture") or "solid"
                        end,
                        getPx = function()
                            return Cfg("panelBorderThicknessPx")
                        end,
                        setPx = function(val)
                            Set("panelBorderThicknessPx", val)
                        end,
                        apply = function()
                            if CHAT.ApplyExtendedBackground then
                                CHAT.ApplyExtendedBackground()
                            end
                        end,
                    })
                )
                cursorY = cursorY - height

                -- Width Offset | Height Offset: a textured style's outward offsets in their
                -- own row (Solid has none). Same registry row the panel renders with:
                -- "chat" + the thickness label as sizeKey.
                do
                    local pTex = Cfg("panelBorderTexture")
                    if pTex and pTex ~= "" and pTex ~= "solid" then
                        local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                            addonKey = "chat",
                            getTex = function()
                                return Cfg("panelBorderTexture") or "solid"
                            end,
                            getStep = function()
                                return CludesUI.BORDER_STEP_OF_LABEL[Cfg("panelBorderThickness") or "none"]
                                    or 1
                            end,
                            getSizeKey = function()
                                return Cfg("panelBorderThickness") or "none"
                            end,
                            getPx = function()
                                return Cfg("panelBorderThicknessPx")
                            end,
                            getX = function()
                                return Cfg("panelBorderOffsetX")
                            end,
                            setX = function(val)
                                Set("panelBorderOffsetX", val)
                            end,
                            getY = function()
                                return Cfg("panelBorderOffsetY")
                            end,
                            setY = function(val)
                                Set("panelBorderOffsetY", val)
                            end,
                            apply = function()
                                if CHAT.ApplyExtendedBackground then
                                    CHAT.ApplyExtendedBackground()
                                end
                            end,
                        })
                        _, height = W:DualRow(hostFrame, cursorY, ocfgL, ocfgR)
                        cursorY = cursorY - height
                    end
                end

                -- Border options cog on Border Style (Show Behind, shifts).
                do
                    local region = borderRow._leftRegion
                    CludesUI.BuildInlineCog(region, {
                        anchorTo = region._control,
                        title = "Border Options",
                        captureRegion = region,
                        rows = {
                            {
                                type = "toggle",
                                label = "Show Behind",
                                get = CfgOr("panelBorderBehind", false),
                                set = function(val)
                                    Set("panelBorderBehind", val)
                                    if CHAT.ApplyExtendedBackground then
                                        CHAT.ApplyExtendedBackground()
                                    end
                                end,
                            },
                            {
                                type = "slider",
                                label = "Shift X",
                                min = -10,
                                max = 10,
                                step = 1,
                                get = function()
                                    local val = Cfg("panelBorderShiftX")
                                    if val ~= nil then
                                        return val
                                    end
                                    local _, _, value = CludesUI.GetBorderDefaults(
                                        "chat",
                                        Cfg("panelBorderTexture") or "solid",
                                        Cfg("panelBorderThickness") or "none"
                                    )
                                    return value
                                end,
                                set = function(val)
                                    Set("panelBorderShiftX", val == 0 and nil or val)
                                    if CHAT.ApplyExtendedBackground then
                                        CHAT.ApplyExtendedBackground()
                                    end
                                end,
                            },
                            {
                                type = "slider",
                                label = "Shift Y",
                                min = -10,
                                max = 10,
                                step = 1,
                                get = function()
                                    local val = Cfg("panelBorderShiftY")
                                    if val ~= nil then
                                        return val
                                    end
                                    local _, _, _, value = CludesUI.GetBorderDefaults(
                                        "chat",
                                        Cfg("panelBorderTexture") or "solid",
                                        Cfg("panelBorderThickness") or "none"
                                    )
                                    return value
                                end,
                                set = function(val)
                                    Set("panelBorderShiftY", val == 0 and nil or val)
                                    if CHAT.ApplyExtendedBackground then
                                        CHAT.ApplyExtendedBackground()
                                    end
                                end,
                            },
                        },
                    })
                end

                -- Accent, custom, and class-color selectors beside Border Size.
                if not CludesUI._prebuilding then
                    local region = borderRow._rightRegion
                    local control = region._control
                    local function ApplyMode(mode)
                        Set("panelBorderColorMode", mode)
                        if CHAT.ApplyExtendedBackground then
                            CHAT.ApplyExtendedBackground()
                        end
                        CludesUI:RefreshPage()
                    end

                    local classSwatch, refreshClass = CludesUI.BuildColorSwatch(
                        region,
                        borderRow:GetFrameLevel() + 3,
                        function()
                            local _, class = UnitClass("player")
                            local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                            return c and c.r or 1, c and c.g or 1, c and c.b or 1
                        end,
                        function() end,
                        false,
                        20
                    )
                    Pix.Point(classSwatch, "RIGHT", control, "LEFT", -8, 0)
                    classSwatch:SetScript("OnClick", function()
                        ApplyMode("class")
                    end)
                    classSwatch:SetScript("OnEnter", function()
                        CludesUI.ShowWidgetTooltip(classSwatch, "Class Color")
                    end)
                    classSwatch:SetScript("OnLeave", CludesUI.HideWidgetTooltip)

                    local accentSwatch, refreshAccent = CludesUI.BuildColorSwatch(
                        region,
                        borderRow:GetFrameLevel() + 3,
                        function()
                            return CludesUI.GetAccentColor()
                        end,
                        function() end,
                        false,
                        20
                    )
                    Pix.Point(accentSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
                    accentSwatch:SetScript("OnClick", function()
                        ApplyMode("accent")
                    end)
                    accentSwatch:SetScript("OnEnter", function()
                        CludesUI.ShowWidgetTooltip(accentSwatch, "Accent Color")
                    end)
                    accentSwatch:SetScript("OnLeave", CludesUI.HideWidgetTooltip)

                    local customSwatch, refreshCustom = CludesUI.BuildColorSwatch(
                        region,
                        borderRow:GetFrameLevel() + 3,
                        function()
                            local c = Cfg("panelBorderColor") or { r = 1, g = 1, b = 1 }
                            return c.r, c.g, c.b, Cfg("panelBorderOpacity") or 0.18
                        end,
                        function(r, g, b, a)
                            Set("panelBorderColor", { r = r, g = g, b = b })
                            Set("panelBorderOpacity", a)
                            Set("panelBorderColorMode", "custom")
                            if CHAT.ApplyExtendedBackground then
                                CHAT.ApplyExtendedBackground()
                            end
                        end,
                        true,
                        20
                    )
                    Pix.Point(customSwatch, "RIGHT", accentSwatch, "LEFT", -8, 0)
                    local customClick = customSwatch:GetScript("OnClick")
                    customSwatch:SetScript("OnClick", function(self, ...)
                        if (Cfg("panelBorderColorMode") or "custom") ~= "custom" then
                            ApplyMode("custom")
                            return
                        end
                        if customClick then
                            customClick(self, ...)
                        end
                    end)
                    customSwatch:SetScript("OnEnter", function()
                        CludesUI.ShowWidgetTooltip(customSwatch, "Custom Color")
                    end)
                    customSwatch:SetScript("OnLeave", CludesUI.HideWidgetTooltip)

                    local function RefreshBorderSwatches()
                        refreshCustom()
                        refreshAccent()
                        refreshClass()
                        local mode = Cfg("panelBorderColorMode") or "custom"
                        customSwatch:SetAlpha(mode == "custom" and 1 or 0.3)
                        accentSwatch:SetAlpha(mode == "accent" and 1 or 0.3)
                        classSwatch:SetAlpha(mode == "class" and 1 or 0.3)
                    end
                    CludesUI.RegisterWidgetRefresh(RefreshBorderSwatches)
                    RefreshBorderSwatches()
                end
            end -- not STOCK

            -- WoW Forever: the frame its kit draws round the panel, input box,
            -- tabs and sidebar buttons (Slim Textured, Blizzard's live art, is the
            -- default and reads for an unset value; each pick is saved). Latched
            -- with the look, so picking another kind than the latched one asks
            -- for a reload; a kind this client has no art for draws Slim
            -- (CludesUI.ForeverBorderKind). Odd last slot of the section.
            if FV then
                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "dropdown",
                    text = "Border Style",
                    tooltip = "WoW Forever's frame round the chat panel, input box, tabs and sidebar buttons. Slim Textured uses Blizzard's current art; a style whose art this client lacks draws Slim. Applies after a UI reload.",
                    values = { slim = "Slim", textured = "Slim Textured", heavy = "Heavy Bronze" },
                    order = { "slim", "textured", "heavy" },
                    getValue = function()
                        local val = Cfg("foreverBorder")
                        return (val == "slim" or val == "heavy") and val or "textured"
                    end,
                    setValue = function(val)
                        Set("foreverBorder", val)
                        if CludesUI.ForeverBorderKind(val) == mod.ChatFvKind() then
                            return
                        end
                        CludesUI:ShowConfirmPopup({
                            title = "Reload Required",
                            message = "Border Style changed. A UI reload is needed to apply it.",
                            confirmText = "Reload Now",
                            cancelText = "Later",
                            reload = true,
                        })
                    end,
                }, CludesUI.BlankRowCfg())
                cursorY = cursorY - height
            end

            -- -- IDLE FADE ---------------------------------------------------------
            _, height = W:SectionHeader(hostFrame, "IDLE FADE", cursorY)
            cursorY = cursorY - height

            -- Row 1: Enable Idle Fade | Fade Delay
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Enable Idle Fade",
                getValue = function()
                    return Cfg("idleFadeEnabled") ~= false
                end,
                setValue = function(val)
                    Set("idleFadeEnabled", val)
                    if CHAT.ResetIdleTimer then
                        CHAT.ResetIdleTimer()
                    end
                    if CHAT.ApplyIdleFadeHoverMotion then
                        CHAT.ApplyIdleFadeHoverMotion()
                    end
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "slider",
                text = "Fade Delay",
                min = 5,
                max = 30,
                step = 1,
                disabled = function()
                    return Cfg("idleFadeEnabled") == false
                end,
                disabledTooltip = "Enable Idle Fade",
                getValue = CfgOr("idleFadeDelay", 15),
                setValue = function(val)
                    Set("idleFadeDelay", val)
                    if CHAT.ResetIdleTimer then
                        CHAT.ResetIdleTimer()
                    end
                end,
            })
            cursorY = cursorY - height

            -- Row 2 (odd last slot): Fade Strength | (empty)
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Fade Strength",
                min = 0,
                max = 100,
                step = 1,
                disabled = function()
                    return Cfg("idleFadeEnabled") == false
                end,
                disabledTooltip = "Enable Idle Fade",
                getValue = CfgOr("idleFadeStrength", 40),
                setValue = function(val)
                    Set("idleFadeStrength", val)
                    if CHAT.ResetIdleTimer then
                        CHAT.ResetIdleTimer()
                    end
                end,
            }, { type = "label", text = "" })
            cursorY = cursorY - height
        end -- isChat

        -- -- SIDEBAR -----------------------------------------------------------
        if isSidebar then
            _, height = W:SectionHeader(hostFrame, "SIDEBAR", cursorY)
            cursorY = cursorY - height
            if STOCK then
                cursorY = BS.Note(hostFrame, cursorY, "chat")
            end

            -- Row 1: Sidebar Visibility (+ cog) | Sidebar Background
            local sidebarVisValues = {
                always = { text = "Always" },
                mouseover = { text = "Mouseover" },
                never = { text = "Never" },
            }
            local sidebarVisOrder = { "always", "mouseover", "never" }
            local SIDEBAR_ICON_LABELS = {
                showFriends = "Friends",
                showGuild = "Guild",
                showDurability = "Durability",
                showCopy = "Copy Chat",
                showPortals = "M+ Portals",
                showVoice = "Voice/Channels",
                showChatMenu = "Chat Menu",
                showSettings = "Settings",
            }
            -- Chain icons listed in the user's saved order (drag rows to reorder);
            -- Scroll is pinned to the sidebar bottom, so its row is fixed.
            local sidebarIconItems = {}
            local sidebarOrderedKeys = CHAT.ResolveSidebarIconOrder and CHAT.ResolveSidebarIconOrder()
                or {
                    "showFriends",
                    "showGuild",
                    "showDurability",
                    "showCopy",
                    "showPortals",
                    "showVoice",
                    "showSettings",
                }
            for _, keyName in ipairs(sidebarOrderedKeys) do
                sidebarIconItems[#sidebarIconItems + 1] = { key = keyName, label = SIDEBAR_ICON_LABELS[keyName] }
            end
            sidebarIconItems[#sidebarIconItems + 1] =
                { key = "showScroll", label = "Scroll to Bottom", fixed = true }
            local sidebarRow
            sidebarRow, height = W:DualRow(
                hostFrame,
                cursorY,
                {
                    type = "dropdown",
                    text = "Sidebar Visibility",
                    values = sidebarVisValues,
                    order = sidebarVisOrder,
                    getValue = CfgOr("sidebarVisibility", "always"),
                    setValue = function(val)
                        Set("sidebarVisibility", val)
                        if CHAT.ApplySidebarVisibility then
                            CHAT.ApplySidebarVisibility()
                        end
                    end,
                },
                -- Classic WoW UI and WoW Forever draw nothing behind the column;
                -- Blizzard Style's column backdrop follows this toggle.
                (function(rowConf)
                    if STOCK and (BS.Active("chat") == "classic" or FV) then
                        BS.Gate("chat", rowConf)
                    end
                    return rowConf
                end)({
                    type = "toggle",
                    text = "Hide Sidebar Background",
                    getValue = CfgOr("hideSidebarBg", false),
                    setValue = function(val)
                        Set("hideSidebarBg", val)
                        if CHAT.ApplySidebarBackground then
                            CHAT.ApplySidebarBackground()
                        end
                    end,
                })
            )
            -- Cog for Sidebar Visibility
            if not CludesUI._prebuilding then
                local lrgn = sidebarRow._leftRegion
                CludesUI.BuildInlineCog(lrgn, {
                    title = "Sidebar Settings",
                    rows = {
                        {
                            type = "toggle",
                            label = "Show Sidebar on Right",
                            get = CfgOr("sidebarRight", false),
                            set = function(val)
                                Set("sidebarRight", val)
                                if CHAT.ApplySidebarPosition then
                                    CHAT.ApplySidebarPosition()
                                end
                            end,
                        },
                    },
                })
            end
            cursorY = cursorY - height

            local sidebarLayoutRow
            sidebarLayoutRow, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Sidebar Width",
                min = 30,
                max = 100,
                step = 1,
                getValue = function()
                    return Cfg("sidebarWidth")
                        or (CHAT.SidebarWidthDefault and CHAT.SidebarWidthDefault() or 40)
                end,
                setValue = function(val)
                    Set("sidebarWidth", val)
                    if CHAT.ApplySidebarWidth then
                        CHAT.ApplySidebarWidth()
                    end
                end,
            }, {
                type = "toggle",
                text = "Separate Sidebar",
                tooltip = "Separates the sidebar from the chat panel and gives it its own background and border.",
                getValue = CfgOr("sidebarSeparate", false),
                setValue = function(val)
                    Set("sidebarSeparate", val)
                    if CHAT.ApplySidebarPosition then
                        CHAT.ApplySidebarPosition()
                    end
                    if CHAT.ApplyExtendedBackground then
                        CHAT.ApplyExtendedBackground()
                    end
                    CludesUI:RefreshPage()
                end,
            })
            if not CludesUI._prebuilding then
                local lrgn = sidebarLayoutRow._rightRegion
                CludesUI.BuildInlineCog(lrgn, {
                    disabled = function()
                        return not Cfg("sidebarSeparate")
                    end,
                    disabledTooltip = "Separate Sidebar",
                    title = "Separate Sidebar",
                    rows = {
                        {
                            type = "slider",
                            pixel = true,
                            label = "Sidebar Spacing",
                            min = 0,
                            max = 30,
                            step = 1,
                            get = CfgOr("sidebarSeparateSpacing", 8),
                            set = function(val)
                                Set("sidebarSeparateSpacing", val)
                                if CHAT.ApplySidebarPosition then
                                    CHAT.ApplySidebarPosition()
                                end
                                if CHAT.ApplyExtendedBackground then
                                    CHAT.ApplyExtendedBackground()
                                end
                            end,
                        },
                    },
                })
            end
            cursorY = cursorY - height

            _, height = W:SectionHeader(hostFrame, "ICONS", cursorY)
            cursorY = cursorY - height

            -- Row 2: Sidebar Icons Color | (empty)
            local function MakeIconColorSwatches()
                return {
                    {
                        tooltip = "Custom Color",
                        hasAlpha = false,
                        getValue = function()
                            return (Cfg("iconR") or 1), (Cfg("iconG") or 1), (Cfg("iconB") or 1)
                        end,
                        setValue = function(r, g, b)
                            Set("iconR", r)
                            Set("iconG", g)
                            Set("iconB", b)
                            if CHAT.ApplyIconColor then
                                CHAT.ApplyIconColor()
                            end
                        end,
                        onClick = function(self)
                            if Cfg("iconUseAccent") then
                                Set("iconUseAccent", false)
                                if CHAT.ApplyIconColor then
                                    CHAT.ApplyIconColor()
                                end
                                CludesUI:RefreshPage()
                                return
                            end
                            if self._eabOrigClick then
                                self._eabOrigClick(self)
                            end
                        end,
                        refreshAlpha = function()
                            return Cfg("iconUseAccent") and 0.3 or 1
                        end,
                    },
                    {
                        tooltip = "Accent Color",
                        hasAlpha = false,
                        getValue = function()
                            local ar, ag, ab = CludesUI.GetAccentColor()
                            return ar, ag, ab
                        end,
                        setValue = function() end,
                        onClick = function()
                            Set("iconUseAccent", true)
                            if CHAT.ApplyIconColor then
                                CHAT.ApplyIconColor()
                            end
                            CludesUI:RefreshPage()
                        end,
                        refreshAlpha = function()
                            return Cfg("iconUseAccent") and 1 or 0.3
                        end,
                    },
                }
            end
            local iconOptionsRow
            iconOptionsRow, height = W:DualRow(
                hostFrame,
                cursorY,
                -- The stock styles keep the stock column art (no tint).
                CludesUI.BlizzStyle.Gate(
                    "chat",
                    { type = "multiSwatch", text = "Sidebar Icons Color", swatches = MakeIconColorSwatches() }
                ),
                {
                    type = "dropdown",
                    text = "Sidebar Icons",
                    values = { __placeholder = "..." },
                    order = { "__placeholder" },
                    getValue = function()
                        return "__placeholder"
                    end,
                    setValue = function() end,
                }
            )
            if not CludesUI._prebuilding then
                local rightRegion = iconOptionsRow._rightRegion
                if rightRegion._control then
                    rightRegion._control:Hide()
                end
                local pendingIconReload = false
                local checkDrop, cbDDRefresh = CludesUI.BuildReorderCBDropdown(
                    rightRegion,
                    210,
                    rightRegion:GetFrameLevel() + 2,
                    sidebarIconItems,
                    function(keyName)
                        return Cfg(keyName) ~= false
                    end,
                    function(keyName, val)
                        if val and CHAT.SidebarIconExists and not CHAT.SidebarIconExists(keyName) then
                            pendingIconReload = true
                        end
                        Set(keyName, val)
                        if CHAT.ApplySidebarIcons then
                            CHAT.ApplySidebarIcons()
                        end
                    end,
                    {
                        hint2 = "Reload required - close dropdown to reload",
                        setOrder = function(orderedKeys)
                            local map = {}
                            for idx, key in ipairs(orderedKeys) do
                                map[key] = idx
                            end
                            Set("sidebarIconOrder", map)
                        end,
                        onClose = function(orderChanged)
                            if not orderChanged and not pendingIconReload then
                                return
                            end
                            pendingIconReload = false
                            CludesUI:ShowConfirmPopup({
                                title = "Reload Required",
                                message = "A UI reload is needed to apply your sidebar icon changes.",
                                confirmText = "Reload Now",
                                cancelText = "Later",
                                reload = true,
                            })
                        end,
                    }
                )
                CludesUI.PanelPP.Point(checkDrop, "RIGHT", rightRegion, "RIGHT", -20, 0)
                rightRegion._control = checkDrop
                rightRegion._lastInline = nil
                CludesUI.RegisterWidgetRefresh(cbDDRefresh)
            end
            cursorY = cursorY - height

            -- Row 3: Sidebar Icon Size (+ cog: Icon Spacing) | Free Move Icons
            local sizeRow
            sizeRow, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Sidebar Icon Size",
                min = 0.5,
                max = 2.0,
                step = 0.05,
                getValue = CfgOr("sidebarIconScale", 1.0),
                setValue = function(val)
                    Set("sidebarIconScale", val)
                    if CHAT.ApplySidebarIconScale then
                        CHAT.ApplySidebarIconScale()
                    end
                end,
            }, {
                type = "toggle",
                text = "Free Move Icons",
                tooltip = "When enabled, Shift+Click any sidebar icon to drag it to a custom position.",
                getValue = CfgOr("freeMoveIcons", false),
                setValue = function(val)
                    Set("freeMoveIcons", val)
                    if CHAT.ApplySidebarIcons then
                        CHAT.ApplySidebarIcons()
                    end
                    CludesUI:RefreshPage()
                end,
            })
            if not CludesUI._prebuilding then
                local lrgn = sizeRow._leftRegion
                CludesUI.BuildInlineCog(lrgn, {
                    title = "Icon Settings",
                    rows = {
                        -- The stock styles keep their own spacing (the visible
                        -- gap between button art; Blizzard's packing by default).
                        {
                            type = "slider",
                            pixel = true,
                            label = "Icon Spacing",
                            min = 0,
                            max = 30,
                            step = 1,
                            get = function()
                                if STOCK then
                                    return Cfg("stockIconSpacing") or (CHAT.SB_KIT and CHAT.SB_KIT.gap) or 4
                                end
                                return Cfg("sidebarIconSpacing") or 10
                            end,
                            set = function(val)
                                Set(STOCK and "stockIconSpacing" or "sidebarIconSpacing", val)
                                if CHAT.ApplySidebarIcons then
                                    CHAT.ApplySidebarIcons()
                                end
                            end,
                        },
                    },
                })
            end
            -- "Reset" label next to the Free Move Icons toggle (only visible when enabled)
            if not CludesUI._prebuilding then
                local region = sizeRow._rightRegion
                local resetFS = region:CreateFontString(nil, "OVERLAY")
                resetFS:SetFont(CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 12, "")
                resetFS:SetTextColor(1, 1, 1, 0.8)
                resetFS:SetText(CludesUI.L("Reset"))
                resetFS:SetPoint("RIGHT", region._control, "LEFT", -8, 0)
                local hitBtn = CreateFrame("Button", nil, region)
                hitBtn:SetAllPoints(resetFS)
                hitBtn:SetFrameLevel(region:GetFrameLevel() + 5)
                hitBtn:SetScript("OnEnter", function()
                    resetFS:SetTextColor(1, 0.3, 0.3, 1)
                end)
                hitBtn:SetScript("OnLeave", function()
                    resetFS:SetTextColor(1, 1, 1, 0.8)
                end)
                hitBtn:SetScript("OnClick", function()
                    Set("iconPositions", {})
                    if CHAT.ApplySidebarIcons then
                        CHAT.ApplySidebarIcons()
                    end
                end)
                local function UpdateResetVis()
                    local enabled = Cfg("freeMoveIcons")
                    resetFS:SetShown(enabled)
                    hitBtn:SetShown(enabled)
                end
                UpdateResetVis()
                CludesUI.RegisterWidgetRefresh(UpdateResetVis)
            end
            cursorY = cursorY - height

            -- Row 4: Scroll Button on Chat Panel | (empty)
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Scroll Button on Chat Panel",
                tooltip = "Anchors the Scroll to Bottom button to the bottom-right corner of the chat panel instead of the sidebar.",
                getValue = CfgIs("scrollButtonOnChat"),
                setValue = function(val)
                    Set("scrollButtonOnChat", val)
                    if CHAT.ApplySidebarIcons then
                        CHAT.ApplySidebarIcons()
                    end
                    if CHAT.ApplySidebarVisibility then
                        CHAT.ApplySidebarVisibility()
                    end
                end,
            }, { type = "label", text = "" })
            cursorY = cursorY - height
        end -- isSidebar

        if isTabs then
            -- Classic WoW UI (the vanilla tab sheet) and WoW Forever (the
            -- bronze tab) paint at Blizzard's tab geometry: only the
            -- TYPOGRAPHY section applies there.
            if not STOCK then
                _, height = W:SectionHeader(hostFrame, "LAYOUT", cursorY)
                cursorY = cursorY - height

                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Tabs Inside Chat Panel",
                    tooltip = "Places the tabs inside one continuous chat panel background, including the sidebar when visible.",
                    getValue = CfgOr("extendBgBehindTabs", false),
                    setValue = function(val)
                        Set("extendBgBehindTabs", val)
                        if CHAT.ApplyTabPadding then
                            CHAT.ApplyTabPadding()
                        end
                        if CHAT.ApplyTabSpacing then
                            CHAT.ApplyTabSpacing()
                        end
                        CludesUI:RefreshPage()
                    end,
                }, {
                    type = "slider",
                    text = "Tab Spacing",
                    min = 0,
                    max = 10,
                    step = 1,
                    disabled = function()
                        return Cfg("extendBgBehindTabs") == true
                    end,
                    disabledTooltip = "Tabs Inside Chat Panel",
                    requireState = "disabled",
                    getValue = CfgOr("tabSpacing", 1),
                    setValue = function(val)
                        Set("tabSpacing", val)
                        if CHAT.ApplyTabSpacing then
                            CHAT.ApplyTabSpacing()
                        end
                    end,
                })
                cursorY = cursorY - height

                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "slider",
                    text = "Tab Height",
                    min = 18,
                    max = 40,
                    step = 1,
                    getValue = CfgOr("tabHeight", 24),
                    setValue = function(val)
                        Set("tabHeight", val)
                        if CHAT.ApplyTabLayout then
                            CHAT.ApplyTabLayout()
                        end
                    end,
                }, {
                    type = "slider",
                    text = "Inner Padding X",
                    min = 0,
                    max = 30,
                    step = 1,
                    getValue = CfgOr("tabInnerPaddingX", 12),
                    setValue = function(val)
                        Set("tabInnerPaddingX", val)
                        if CHAT.ApplyTabLayout then
                            CHAT.ApplyTabLayout()
                        end
                    end,
                })
                cursorY = cursorY - height
            end -- not STOCK (LAYOUT)

            _, height = W:SectionHeader(hostFrame, "TYPOGRAPHY", cursorY)
            cursorY = cursorY - height
            do
                local fontValues, fontOrder = CludesUI.BuildFontDropdownData()
                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "dropdown",
                    text = "Tab Font",
                    values = fontValues,
                    order = fontOrder,
                    getValue = CfgOr("tabFont", "__global"),
                    setValue = function(val)
                        Set("tabFont", val)
                        if CHAT.ApplyTabAppearance then
                            CHAT.ApplyTabAppearance()
                        end
                        if CHAT.ApplyTabLayout then
                            CHAT.ApplyTabLayout()
                        end
                    end,
                }, {
                    type = "slider",
                    text = "Tab Font Size",
                    min = 8,
                    max = 24,
                    step = 1,
                    getValue = CfgOr("tabFontSize", 11),
                    setValue = function(val)
                        Set("tabFontSize", val)
                        if CHAT.ApplyTabAppearance then
                            CHAT.ApplyTabAppearance()
                        end
                        if CHAT.ApplyTabLayout then
                            CHAT.ApplyTabLayout()
                        end
                    end,
                })
                cursorY = cursorY - height
            end

            -- A tab colour's three swatches: Custom (the colour in key; when the
            -- picker offers no alpha, the stored alpha is kept), Accent and
            -- Class. modeKey records which is in use (unset = Custom); the
            -- unused ones rest dimmed, and clicking one switches to it.
            local function TabModeSwatches(key, modeKey, fallback, withAlpha)
                local function Mode()
                    return Cfg(modeKey) or "custom"
                end
                local function ApplyTabs()
                    if CHAT.ApplyTabAppearance then
                        CHAT.ApplyTabAppearance()
                    end
                end
                local function SetMode(mode)
                    Set(modeKey, mode)
                    ApplyTabs()
                    CludesUI:RefreshPage()
                end
                local function Lit(mode)
                    return function()
                        return Mode() == mode and 1 or 0.3
                    end
                end
                return {
                    {
                        tooltip = "Custom Color",
                        hasAlpha = withAlpha,
                        getValue = function()
                            local c = Cfg(key) or fallback
                            return c.r, c.g, c.b, c.a == nil and fallback.a or c.a
                        end,
                        setValue = function(r, g, b, a)
                            if not withAlpha then
                                local c = Cfg(key) or fallback
                                a = c.a == nil and fallback.a or c.a
                            end
                            Set(key, { r = r, g = g, b = b, a = a })
                            Set(modeKey, "custom")
                            ApplyTabs()
                        end,
                        onClick = function(self)
                            if Mode() ~= "custom" then
                                SetMode("custom")
                                return
                            end
                            if self._eabOrigClick then
                                self._eabOrigClick(self)
                            end
                        end,
                        refreshAlpha = Lit("custom"),
                    },
                    {
                        tooltip = "Accent Color",
                        hasAlpha = false,
                        getValue = function()
                            return CludesUI.GetAccentColor()
                        end,
                        setValue = function() end,
                        onClick = function()
                            SetMode("accent")
                        end,
                        refreshAlpha = Lit("accent"),
                    },
                    {
                        tooltip = "Class Color",
                        hasAlpha = false,
                        getValue = function()
                            local _, class = UnitClass("player")
                            local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                            return c and c.r or 1, c and c.g or 1, c and c.b or 1
                        end,
                        setValue = function() end,
                        onClick = function()
                            SetMode("class")
                        end,
                        refreshAlpha = Lit("class"),
                    },
                }
            end
            local function FontColorSwatch(isActive)
                if isActive then
                    return TabModeSwatches(
                        "tabFontColorActive",
                        "tabFontColorActiveMode",
                        { r = 1, g = 1, b = 1, a = 1 },
                        true
                    )
                end
                return TabModeSwatches(
                    "tabFontColor",
                    "tabFontColorMode",
                    { r = 1, g = 1, b = 1, a = 0.65 },
                    true
                )
            end
            _, height = W:DualRow(
                hostFrame,
                cursorY,
                { type = "multiSwatch", text = "Tab Font Color", swatches = FontColorSwatch(false) },
                { type = "multiSwatch", text = "Tab Font Color Active", swatches = FontColorSwatch(true) }
            )
            cursorY = cursorY - height

            if not STOCK then
                _, height = W:SectionHeader(hostFrame, "APPEARANCE", cursorY)
                cursorY = cursorY - height
                -- The inactive background is a single custom color picker. The
                -- active background uses the common Custom, Accent, Class order;
                -- both reuse the existing color tables without new defaults.
                local TAB_BG_FALLBACK = {
                    [false] = { r = 0.03, g = 0.045, b = 0.05, a = 0.44 },
                    [true] = { r = 0.03, g = 0.045, b = 0.05, a = 0.65 },
                }
                local function InactiveTabBgSwatches()
                    local fallback = TAB_BG_FALLBACK[false]
                    return {
                        {
                            tooltip = "Custom Color",
                            hasAlpha = false,
                            getValue = function()
                                local c = Cfg("tabBackgroundColor") or fallback
                                return c.r, c.g, c.b, c.a == nil and fallback.a or c.a
                            end,
                            setValue = function(r, g, b)
                                local c = Cfg("tabBackgroundColor") or fallback
                                local a = c.a == nil and fallback.a or c.a
                                Set("tabBackgroundColor", { r = r, g = g, b = b, a = a })
                                if CHAT.ApplyTabAppearance then
                                    CHAT.ApplyTabAppearance()
                                end
                            end,
                        },
                    }
                end
                local function ActiveTabBgSwatches()
                    return TabModeSwatches(
                        "tabBackgroundColorActive",
                        "tabBackgroundColorActiveMode",
                        TAB_BG_FALLBACK[true],
                        false
                    )
                end
                local tabBgRow
                tabBgRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "multiSwatch",
                    text = "Tab Background Color",
                    swatches = InactiveTabBgSwatches(),
                }, {
                    type = "multiSwatch",
                    text = "Tab Background Color Active",
                    swatches = ActiveTabBgSwatches(),
                })
                local function AttachTabBgOpacityCog(region, isActive)
                    local key = isActive and "tabBackgroundColorActive" or "tabBackgroundColor"
                    local fallback = TAB_BG_FALLBACK[isActive]
                    CludesUI.BuildInlineCog(region, {
                        title = isActive and "Active Tab Background" or "Tab Background",
                        captureRegion = region,
                        rows = {
                            {
                                type = "slider",
                                label = "Opacity",
                                min = 0,
                                max = 100,
                                step = 1,
                                get = function()
                                    local c = Cfg(key) or fallback
                                    local a = c.a == nil and fallback.a or c.a
                                    return math.floor(a * 100 + 0.5)
                                end,
                                set = function(val)
                                    local c = Cfg(key) or fallback
                                    Set(key, { r = c.r, g = c.g, b = c.b, a = val / 100 })
                                    if CHAT.ApplyTabAppearance then
                                        CHAT.ApplyTabAppearance()
                                    end
                                end,
                            },
                        },
                    })
                end
                if not CludesUI._prebuilding then
                    AttachTabBgOpacityCog(tabBgRow._leftRegion, false)
                    AttachTabBgOpacityCog(tabBgRow._rightRegion, true)
                end
                cursorY = cursorY - height

                local function UnderlineMode()
                    local mode = Cfg("activeUnderlineColorMode") or "accent"
                    -- Legacy "border" profiles render and display as Custom,
                    -- without rewriting the saved profile during initialization.
                    return mode == "border" and "custom" or mode
                end
                local function UnderlineSwatches()
                    return {
                        {
                            tooltip = "Custom Color",
                            hasAlpha = true,
                            getValue = function()
                                local c = Cfg("activeUnderlineColor")
                                    or { r = 0.05, g = 0.82, b = 0.61, a = 1 }
                                return c.r, c.g, c.b, c.a == nil and 1 or c.a
                            end,
                            setValue = function(r, g, b, a)
                                Set("activeUnderlineColor", { r = r, g = g, b = b, a = a })
                                Set("activeUnderlineColorMode", "custom")
                                if CHAT.ApplyTabAppearance then
                                    CHAT.ApplyTabAppearance()
                                end
                            end,
                            onClick = function(self)
                                if UnderlineMode() ~= "custom" then
                                    Set("activeUnderlineColorMode", "custom")
                                    if CHAT.ApplyTabAppearance then
                                        CHAT.ApplyTabAppearance()
                                    end
                                    CludesUI:RefreshPage()
                                    return
                                end
                                if self._eabOrigClick then
                                    self._eabOrigClick(self)
                                end
                            end,
                            refreshAlpha = function()
                                return UnderlineMode() == "custom" and 1 or 0.3
                            end,
                        },
                        {
                            tooltip = "Accent Color",
                            hasAlpha = false,
                            getValue = function()
                                return CludesUI.GetAccentColor()
                            end,
                            setValue = function() end,
                            onClick = function()
                                Set("activeUnderlineColorMode", "accent")
                                if CHAT.ApplyTabAppearance then
                                    CHAT.ApplyTabAppearance()
                                end
                                CludesUI:RefreshPage()
                            end,
                            refreshAlpha = function()
                                return UnderlineMode() == "accent" and 1 or 0.3
                            end,
                        },
                        {
                            tooltip = "Class Color",
                            hasAlpha = false,
                            getValue = function()
                                local _, cl = UnitClass("player")
                                local c = cl and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cl]
                                return c and c.r or 1, c and c.g or 1, c and c.b or 1
                            end,
                            setValue = function() end,
                            onClick = function()
                                Set("activeUnderlineColorMode", "class")
                                if CHAT.ApplyTabAppearance then
                                    CHAT.ApplyTabAppearance()
                                end
                                CludesUI:RefreshPage()
                            end,
                            refreshAlpha = function()
                                return UnderlineMode() == "class" and 1 or 0.3
                            end,
                        },
                    }
                end

                -- Texture belongs to the tab appearance controls, alongside the
                -- combined underline toggle and its inline color choices.
                if CHAT.RefreshBgTextureCatalogue then
                    CHAT.RefreshBgTextureCatalogue()
                end
                local btValues, btOrder = {}, {}
                do
                    local texNames = mod.chatBgTextureNames or {}
                    for _, key in ipairs(mod.chatBgTextureOrder or {}) do
                        if key ~= "---" then
                            btValues[key] = texNames[key] or key
                            btOrder[#btOrder + 1] = key
                        end
                    end
                    local texLookup = mod.chatBgTextures or {}
                    btValues._menuOpts = {
                        itemHeight = 28,
                        background = function(key)
                            return texLookup[key]
                        end,
                    }
                end
                local underlineRow
                underlineRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Active Underline",
                    getValue = function()
                        return Cfg("activeUnderline") ~= false
                    end,
                    setValue = function(val)
                        Set("activeUnderline", val)
                        if CHAT.ApplyTabAppearance then
                            CHAT.ApplyTabAppearance()
                        end
                    end,
                }, {
                    type = "dropdown",
                    text = "Tab Texture",
                    tooltip = "Texture drawn over the tab background colors.",
                    values = btValues,
                    order = btOrder,
                    getValue = CfgOr("tabBackgroundTexture", "none"),
                    setValue = function(val)
                        Set("tabBackgroundTexture", val)
                        if CHAT.ApplyTabAppearance then
                            CHAT.ApplyTabAppearance()
                        end
                    end,
                })
                if not CludesUI._prebuilding then
                    CludesUI.BuildInlineSwatches(underlineRow._leftRegion, UnderlineSwatches())
                end
                cursorY = cursorY - height

                -- (No tab idle-fade section: the per-tab fade layer was removed
                -- 2026-07-20 -- Blizzard's own tab alpha machinery always won and
                -- the setting visibly did nothing. Tabs fade with the chat panel
                -- via the dock; see _ApplyAlpha in CUI_Chat_Visibility.lua.)

                _, height = W:SectionHeader(hostFrame, "BORDER", cursorY)
                cursorY = cursorY - height
                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Sync Border with Chat Panel",
                    tooltip = "For tabs outside the chat panel, uses the chat panel's border style and color instead of separate tab border settings.",
                    disabled = function()
                        return Cfg("extendBgBehindTabs") == true
                    end,
                    disabledTooltip = "Tabs Inside Chat Panel",
                    requireState = "disabled",
                    getValue = function()
                        return Cfg("syncTabBorder") ~= false
                    end,
                    setValue = function(val)
                        Set("syncTabBorder", val)
                        if CHAT.ApplyTabBorders then
                            CHAT.ApplyTabBorders()
                        end
                        CludesUI:RefreshPage()
                    end,
                }, { type = "label", text = "" })
                cursorY = cursorY - height
                local syncTabs = function()
                    return Cfg("syncTabBorder") ~= false
                end
                local tabBordersDisabled = function()
                    return Cfg("extendBgBehindTabs") == true or syncTabs()
                end
                local function TabBorderDisabledTip()
                    if Cfg("extendBgBehindTabs") then
                        return "Tabs Inside Chat Panel"
                    end
                    return "Sync Border with Chat Panel"
                end
                local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
                local borderRow
                borderRow, height = W:DualRow(
                    hostFrame,
                    cursorY,
                    {
                        type = "dropdown",
                        text = "Border Style",
                        disabled = tabBordersDisabled,
                        disabledTooltip = TabBorderDisabledTip,
                        requireState = "disabled",
                        values = texValues,
                        order = texOrder,
                        getValue = CfgOr("tabBorderTexture", "solid"),
                        setValue = function(val)
                            Set("tabBorderTexture", val)
                            Set("tabBorderOffsetX", nil)
                            Set("tabBorderOffsetY", nil)
                            Set("tabBorderShiftX", nil)
                            Set("tabBorderShiftY", nil)
                            -- A style with a select colour (Pixels grey) seeds the custom
                            -- colour; the colour mode is kept, every other style keeps its colour.
                            local selC = CludesUI.GetBorderSelectColor(val)
                            if selC then
                                Set("tabBorderColor", selC)
                            end
                            -- A style pick lands on the style's default step, so an exact
                            -- pixel size paired with the old step is cleared (false, not
                            -- nil: the clear must travel through mirror sync).
                            if Cfg("tabBorderThicknessPx") then
                                Set("tabBorderThicknessPx", false)
                            end
                            local def = CludesUI.GetBorderDefaultSize("chat", val)
                                or CludesUI.GetBorderTextureDefaultThickness(val)
                            -- Unregistered SharedMedia borders default to the NUMBER 1; this key stores labels.
                            if type(def) == "number" then
                                def = CludesUI.BORDER_LABEL_OF_STEP[def] or "thin"
                            end
                            if def then
                                Set("tabBorderThickness", def)
                            end
                            if CHAT.ApplyTabBorders then
                                CHAT.ApplyTabBorders()
                            end
                            -- Rebuild: the offset row below exists only for a textured style.
                            CludesUI:RefreshPage(true)
                        end,
                    },
                    CludesUI.BorderPxSliderCfg({
                        text = "Border Size",
                        disabled = tabBordersDisabled,
                        disabledTooltip = TabBorderDisabledTip,
                        requireState = "disabled",
                        -- The step a tab renders with from its own keys: its label as a step, anything unknown = thin.
                        getStep = function()
                            return CludesUI.BORDER_STEP_OF_LABEL[Cfg("tabBorderThickness") or "none"] or 1
                        end,
                        setStep = function(step)
                            Set("tabBorderThickness", CludesUI.BORDER_LABEL_OF_STEP[step])
                        end,
                        getTex = function()
                            return Cfg("tabBorderTexture") or "solid"
                        end,
                        getPx = function()
                            return Cfg("tabBorderThicknessPx")
                        end,
                        setPx = function(val)
                            Set("tabBorderThicknessPx", val)
                        end,
                        apply = function()
                            if CHAT.ApplyTabBorders then
                                CHAT.ApplyTabBorders()
                            end
                        end,
                    })
                )
                cursorY = cursorY - height

                -- Width Offset | Height Offset: a textured tab style's outward offsets in
                -- their own row (Solid has none). Same registry row a tab renders with
                -- from its own keys: "chat" + the thickness label as sizeKey. Disabled
                -- exactly like the Border Size slot.
                do
                    local tTex = Cfg("tabBorderTexture")
                    if tTex and tTex ~= "" and tTex ~= "solid" then
                        local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                            addonKey = "chat",
                            disabled = tabBordersDisabled,
                            disabledTooltip = TabBorderDisabledTip,
                            requireState = "disabled",
                            getTex = function()
                                return Cfg("tabBorderTexture") or "solid"
                            end,
                            getStep = function()
                                return CludesUI.BORDER_STEP_OF_LABEL[Cfg("tabBorderThickness") or "none"] or 1
                            end,
                            getSizeKey = function()
                                return Cfg("tabBorderThickness") or "none"
                            end,
                            getPx = function()
                                return Cfg("tabBorderThicknessPx")
                            end,
                            getX = function()
                                return Cfg("tabBorderOffsetX")
                            end,
                            setX = function(val)
                                Set("tabBorderOffsetX", val)
                            end,
                            getY = function()
                                return Cfg("tabBorderOffsetY")
                            end,
                            setY = function(val)
                                Set("tabBorderOffsetY", val)
                            end,
                            apply = function()
                                if CHAT.ApplyTabBorders then
                                    CHAT.ApplyTabBorders()
                                end
                            end,
                        })
                        _, height = W:DualRow(hostFrame, cursorY, ocfgL, ocfgR)
                        cursorY = cursorY - height
                    end
                end

                do
                    local region = borderRow._leftRegion
                    CludesUI.BuildInlineCog(region, {
                        chain = false,
                        disabled = tabBordersDisabled,
                        disabledTooltip = TabBorderDisabledTip,
                        title = "Tab Border Options",
                        captureRegion = region,
                        rows = {
                            {
                                type = "slider",
                                label = "Shift X",
                                min = -10,
                                max = 10,
                                step = 1,
                                get = function()
                                    local val = Cfg("tabBorderShiftX")
                                    if val ~= nil then
                                        return val
                                    end
                                    local _, _, d = CludesUI.GetBorderDefaults(
                                        "chat",
                                        Cfg("tabBorderTexture") or "solid",
                                        Cfg("tabBorderThickness") or "none"
                                    )
                                    return d
                                end,
                                set = function(val)
                                    Set("tabBorderShiftX", val == 0 and nil or val)
                                    CHAT.ApplyTabBorders()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Shift Y",
                                min = -10,
                                max = 10,
                                step = 1,
                                get = function()
                                    local val = Cfg("tabBorderShiftY")
                                    if val ~= nil then
                                        return val
                                    end
                                    local _, _, _, d = CludesUI.GetBorderDefaults(
                                        "chat",
                                        Cfg("tabBorderTexture") or "solid",
                                        Cfg("tabBorderThickness") or "none"
                                    )
                                    return d
                                end,
                                set = function(val)
                                    Set("tabBorderShiftY", val == 0 and nil or val)
                                    CHAT.ApplyTabBorders()
                                end,
                            },
                        },
                    })
                end

                if not CludesUI._prebuilding then
                    local region, control = borderRow._rightRegion, borderRow._rightRegion._control
                    local function SetMode(mode)
                        if tabBordersDisabled() then
                            return
                        end
                        Set("tabBorderColorMode", mode)
                        CHAT.ApplyTabBorders()
                        CludesUI:RefreshPage()
                    end
                    local classSw, refreshClass = CludesUI.BuildColorSwatch(
                        region,
                        borderRow:GetFrameLevel() + 3,
                        function()
                            local _, cl = UnitClass("player")
                            local c = cl and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cl]
                            return c and c.r or 1, c and c.g or 1, c and c.b or 1
                        end,
                        function() end,
                        false,
                        20
                    )
                    Pix.Point(classSw, "RIGHT", control, "LEFT", -8, 0)
                    classSw:SetScript("OnClick", function()
                        SetMode("class")
                    end)
                    local accentSw, refreshAccent = CludesUI.BuildColorSwatch(
                        region,
                        borderRow:GetFrameLevel() + 3,
                        function()
                            return CludesUI.GetAccentColor()
                        end,
                        function() end,
                        false,
                        20
                    )
                    Pix.Point(accentSw, "RIGHT", classSw, "LEFT", -8, 0)
                    accentSw:SetScript("OnClick", function()
                        SetMode("accent")
                    end)
                    local customSw, refreshCustom = CludesUI.BuildColorSwatch(
                        region,
                        borderRow:GetFrameLevel() + 3,
                        function()
                            local c = Cfg("tabBorderColor") or { r = 1, g = 1, b = 1 }
                            return c.r, c.g, c.b, Cfg("tabBorderOpacity") or 0.18
                        end,
                        function(r, g, b, a)
                            Set("tabBorderColor", { r = r, g = g, b = b })
                            Set("tabBorderOpacity", a)
                            Set("tabBorderColorMode", "custom")
                            CHAT.ApplyTabBorders()
                        end,
                        true,
                        20
                    )
                    Pix.Point(customSw, "RIGHT", accentSw, "LEFT", -8, 0)
                    local orig = customSw:GetScript("OnClick")
                    customSw:SetScript("OnClick", function(self, ...)
                        if tabBordersDisabled() then
                            return
                        end
                        if (Cfg("tabBorderColorMode") or "custom") ~= "custom" then
                            SetMode("custom")
                        elseif orig then
                            orig(self, ...)
                        end
                    end)
                    local function Refresh()
                        refreshClass()
                        refreshAccent()
                        refreshCustom()
                        local off, mode = tabBordersDisabled(), Cfg("tabBorderColorMode") or "custom"
                        customSw:SetAlpha(off and 0.15 or (mode == "custom" and 1 or 0.3))
                        accentSw:SetAlpha(off and 0.15 or (mode == "accent" and 1 or 0.3))
                        classSw:SetAlpha(off and 0.15 or (mode == "class" and 1 or 0.3))
                    end
                    CludesUI.RegisterWidgetRefresh(Refresh)
                    Refresh()
                end

                -- Row: Active Tab Border (+ inline color swatch)
                local activeBorderRow
                activeBorderRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Active Tab Border",
                    tooltip = "Gives the selected tab its own border color.",
                    disabled = tabBordersDisabled,
                    disabledTooltip = TabBorderDisabledTip,
                    getValue = function()
                        return Cfg("activeTabBorder") ~= false
                    end,
                    setValue = function(val)
                        Set("activeTabBorder", val)
                        if CHAT.ApplyTabBorders then
                            CHAT.ApplyTabBorders()
                        end
                        CludesUI:RefreshPage()
                    end,
                }, { type = "label", text = "" })
                if not CludesUI._prebuilding then
                    local region = activeBorderRow._leftRegion
                    local colorSwatch, refreshSwatch = CludesUI.BuildColorSwatch(
                        region,
                        activeBorderRow:GetFrameLevel() + 3,
                        function()
                            local c = Cfg("tabBorderColorActive") or { r = 1, g = 1, b = 1 }
                            return c.r, c.g, c.b, c.a == nil and 0.18 or c.a
                        end,
                        function(r, g, b, a)
                            Set("tabBorderColorActive", { r = r, g = g, b = b, a = a })
                            if CHAT.ApplyTabBorders then
                                CHAT.ApplyTabBorders()
                            end
                        end,
                        true,
                        20
                    )
                    Pix.Point(colorSwatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                    region._lastInline = colorSwatch
                    colorSwatch:SetScript("OnEnter", function()
                        CludesUI.ShowWidgetTooltip(colorSwatch, "Active Border Color")
                    end)
                    colorSwatch:SetScript("OnLeave", CludesUI.HideWidgetTooltip)
                    local function RefreshActiveSwatch()
                        refreshSwatch()
                        local off = tabBordersDisabled() or Cfg("activeTabBorder") == false
                        colorSwatch:SetAlpha(off and 0.3 or 1)
                    end
                    CludesUI.RegisterWidgetRefresh(RefreshActiveSwatch)
                    RefreshActiveSwatch()
                end
                cursorY = cursorY - height
            end -- not STOCK (APPEARANCE, BORDER)
        end -- isTabs

        if isChat then
            -- -- INPUT FIELD -------------------------------------------------------
            _, height = W:SectionHeader(hostFrame, "INPUT FIELD", cursorY)
            cursorY = cursorY - height

            -- Stock styles keep Blizzard's own input box, its height and place.
            -- WoW Forever's box is ours, always below: its height alone.
            if not STOCK or FV then
                local ebHeightCfg = {
                    type = "slider",
                    text = "Edit Box Height",
                    min = 10,
                    max = 60,
                    step = 1,
                    getValue = CfgOr("editBoxHeight", 23),
                    setValue = function(val)
                        Set("editBoxHeight", val)
                        if CHAT.ApplyInputPosition then
                            CHAT.ApplyInputPosition()
                        end
                    end,
                }
                if FV then
                    _, height = W:DualRow(hostFrame, cursorY, ebHeightCfg, CludesUI.BlankRowCfg())
                else
                    _, height = W:DualRow(hostFrame, cursorY, {
                        type = "toggle",
                        text = "Input on Top",
                        getValue = CfgOr("inputOnTop", false),
                        setValue = function(val)
                            Set("inputOnTop", val)
                            if CHAT.ApplyInputPosition then
                                CHAT.ApplyInputPosition()
                            end
                        end,
                    }, ebHeightCfg)
                end
                cursorY = cursorY - height
            end -- not STOCK or FV

            do
                local fontValues, fontOrder = CludesUI.BuildFontDropdownData()
                fontValues.__chat = "Chat Font"
                table.insert(fontOrder, 1, "__chat")
                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "dropdown",
                    text = "Edit Box Font",
                    values = fontValues,
                    order = fontOrder,
                    getValue = CfgOr("editBoxFont", "__chat"),
                    setValue = function(val)
                        Set("editBoxFont", val)
                        if CHAT.ApplyFonts then
                            CHAT.ApplyFonts()
                        end
                    end,
                }, {
                    type = "slider",
                    text = "Edit Box Font Size",
                    min = 8,
                    max = 24,
                    step = 1,
                    getValue = function()
                        if Cfg("editBoxFontSize") then
                            return Cfg("editBoxFontSize")
                        end
                        local size
                        if FCF_GetChatWindowInfo then
                            size = select(2, FCF_GetChatWindowInfo(1))
                        end
                        return size or 12
                    end,
                    setValue = function(val)
                        Set("editBoxFontSize", val)
                        if CHAT.ApplyFonts then
                            CHAT.ApplyFonts()
                        end
                    end,
                })
                cursorY = cursorY - height
            end

            -- -- EXTRAS ------------------------------------------------------------
            _, height = W:SectionHeader(hostFrame, "EXTRAS", cursorY)
            cursorY = cursorY - height

            -- Row 1: Remember Last Chat Lines (+ cog: Max Lines) | Hide Tooltip on Hover
            local histRow
            histRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Remember Last Chat Lines",
                tooltip = "Saves the most recent lines per chat tab (per character), except Blizzard's combat log window, so they reappear after /reload or relog. Stored separately from layout profiles.",
                getValue = CfgIs("persistChatHistory"),
                setValue = function(val)
                    Set("persistChatHistory", val)
                    if CHAT.OnSessionHistoryToggled then
                        CHAT.OnSessionHistoryToggled(val)
                    elseif CHAT.InitChatSessionHistory then
                        CHAT.InitChatSessionHistory()
                    end
                end,
            }, {
                type = "toggle",
                text = "Hide Tooltip on Hover",
                getValue = CfgOr("hideTooltipOnHover", false),
                setValue = function(val)
                    Set("hideTooltipOnHover", val)
                end,
            })
            if not CludesUI._prebuilding then
                local lrgn = histRow._leftRegion
                CludesUI.BuildInlineCog(lrgn, {
                    title = "Session History",
                    rows = {
                        {
                            type = "slider",
                            label = "Max Lines to Keep",
                            min = 20,
                            max = 300,
                            step = 10,
                            get = CfgOr("persistChatHistoryMaxLines", 100),
                            set = function(val)
                                Set("persistChatHistoryMaxLines", val)
                            end,
                        },
                    },
                })
            end
            cursorY = cursorY - height

            -- Sound dropdown: shallow-copy the runtime tables so _menuOpts
            -- (preview icon) doesn't pollute the shared tables.
            local whisperSoundValues = {}
            local whisperSoundPaths = CHAT.WHISPER_SOUND_PATHS or {}
            local whisperSoundNames = CHAT.WHISPER_SOUND_NAMES or { none = "Blizzard Default", mute = "None" }
            local whisperSoundOrder = CHAT.WHISPER_SOUND_ORDER or { "none", "mute" }
            for keyName, val in pairs(whisperSoundNames) do
                whisperSoundValues[keyName] = val
            end
            whisperSoundValues._menuOpts = {
                itemHeight = 26,
                maxTextWidthPct = 0.8,
                searchable = true,
                iconAtlas = function(key)
                    if key == "none" then
                        return nil
                    end
                    if not whisperSoundPaths[key] then
                        return nil
                    end
                    return CludesUI.SOUND_ICON_ATLAS
                end,
                iconPressedAtlas = function(key)
                    if not whisperSoundPaths[key] then
                        return nil
                    end
                    return CludesUI.SOUND_ICON_PRESSED_ATLAS
                end,
                iconOnClick = function(key)
                    local filePath = whisperSoundPaths[key]
                    if filePath then
                        PlaySoundFile(filePath, "Master")
                    end
                end,
                iconTooltip = function()
                    return "Preview Sound"
                end,
            }

            -- Row 2: Hide Borders (+ inline inner-border swatches) | Whisper Sound
            -- Stock styles draw none of these borders (Blizzard's frame border
            -- is the border), so the toggle and its swatches are blocked there.
            local hideBordersCfg = {
                type = "toggle",
                text = "Hide Borders",
                getValue = CfgOr("hideBorders", false),
                setValue = function(val)
                    Set("hideBorders", val)
                    if CHAT.ApplyBorders then
                        CHAT.ApplyBorders()
                    end
                    CludesUI:RefreshPage()
                end,
            }
            if BS then
                BS.Gate("chat", hideBordersCfg)
            end
            local extrasBorderRow
            extrasBorderRow, height = W:DualRow(hostFrame, cursorY, hideBordersCfg, {
                type = "dropdown",
                text = "Whisper Sound",
                tooltip = "Blizzard Default keeps the game's whisper sound. Any other sound replaces it, and None plays no sound.",
                values = whisperSoundValues,
                order = whisperSoundOrder,
                getValue = CfgOr("whisperSoundKey", "none"),
                setValue = function(val)
                    Set("whisperSoundKey", val)
                    CHAT.ApplyWhisperMute()
                end,
            })
            if not CludesUI._prebuilding then
                local region = extrasBorderRow._leftRegion
                local control = region._control
                local function SetInnerMode(mode)
                    if Cfg("hideBorders") then
                        return
                    end
                    Set("innerBorderColorMode", mode)
                    if CHAT.ApplyBorders then
                        CHAT.ApplyBorders()
                    end
                    if CHAT.ApplyExtendedBackground then
                        CHAT.ApplyExtendedBackground()
                    end
                    if CHAT.ApplyTabSeparators then
                        CHAT.ApplyTabSeparators()
                    end
                    CludesUI:RefreshPage()
                end
                local colorSwatch, refreshSwatch = CludesUI.BuildColorSwatch(
                    region,
                    extrasBorderRow:GetFrameLevel() + 3,
                    function()
                        local c = Cfg("innerBorderColor") or { r = 1, g = 1, b = 1, a = 0.06 }
                        return c.r, c.g, c.b, c.a == nil and 0.06 or c.a
                    end,
                    function(r, g, b, a)
                        Set("innerBorderColor", { r = r, g = g, b = b, a = a })
                        Set("innerBorderColorMode", "custom")
                        if CHAT.ApplyBorders then
                            CHAT.ApplyBorders()
                        end
                        if CHAT.ApplyExtendedBackground then
                            CHAT.ApplyExtendedBackground()
                        end
                        if CHAT.ApplyTabSeparators then
                            CHAT.ApplyTabSeparators()
                        end
                    end,
                    true,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", control, "LEFT", -8, 0)
                -- Accent mode swatch sits left of the custom one (select-mode-
                -- first convention, matching the tab border color trio).
                local accentSw, refreshAccent = CludesUI.BuildColorSwatch(
                    region,
                    extrasBorderRow:GetFrameLevel() + 3,
                    function()
                        return CludesUI.GetAccentColor()
                    end,
                    function() end,
                    false,
                    20
                )
                Pix.Point(accentSw, "RIGHT", colorSwatch, "LEFT", -8, 0)
                accentSw:SetScript("OnClick", function()
                    SetInnerMode("accent")
                end)
                accentSw:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(accentSw, "Accent Inner Border Color")
                end)
                accentSw:SetScript("OnLeave", CludesUI.HideWidgetTooltip)
                local origClick = colorSwatch:GetScript("OnClick")
                colorSwatch:SetScript("OnClick", function(self, ...)
                    if Cfg("hideBorders") then
                        return
                    end
                    if (Cfg("innerBorderColorMode") or "custom") ~= "custom" then
                        SetInnerMode("custom")
                    elseif origClick then
                        origClick(self, ...)
                    end
                end)
                colorSwatch:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(colorSwatch, "Inner Border Color")
                end)
                colorSwatch:SetScript("OnLeave", CludesUI.HideWidgetTooltip)
                local function RefreshInner()
                    refreshSwatch()
                    refreshAccent()
                    local off = Cfg("hideBorders") or STOCK
                    local mode = Cfg("innerBorderColorMode") or "custom"
                    colorSwatch:SetAlpha(off and 0.3 or (mode == "custom" and 1 or 0.3))
                    accentSw:SetAlpha(off and 0.3 or (mode == "accent" and 1 or 0.3))
                end
                CludesUI.RegisterWidgetRefresh(RefreshInner)
                RefreshInner()
                if BS then
                    BS.BlockInline("chat", colorSwatch)
                    BS.BlockInline("chat", accentSw)
                end
            end
            cursorY = cursorY - height

            -- Row 3: Timestamp All Messages | Timestamps
            do
                local tsValues = {
                    ["__blizzard"] = { text = "Use Blizzard Setting" },
                    ["none"] = { text = "None" },
                    ["%I:%M "] = { text = "03:27" },
                    ["%I:%M:%S "] = { text = "03:27:32" },
                    ["%I:%M %p "] = { text = "03:27 PM" },
                    ["%I:%M:%S %p "] = { text = "03:27:32 PM" },
                    ["%H:%M "] = { text = "15:27" },
                    ["%H:%M:%S "] = { text = "15:27:32" },
                }
                local tsOrder = {
                    "__blizzard",
                    "none",
                    "---",
                    "%I:%M ",
                    "%I:%M:%S ",
                    "%I:%M %p ",
                    "%I:%M:%S %p ",
                    "---",
                    "%H:%M ",
                    "%H:%M:%S ",
                }
                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Timestamp All Messages",
                    tooltip = "Adds timestamps to system messages, loot, achievements, and addon messages, not just player chat.",
                    disabled = function()
                        return (Cfg("timestampFormat") or "%I:%M ") == "none"
                    end,
                    disabledTooltip = "Set a Timestamps format first",
                    getValue = CfgIs("timestampAll"),
                    setValue = function(val)
                        Set("timestampAll", val)
                        if CHAT.ApplyTimestampCVar then
                            CHAT.ApplyTimestampCVar()
                        end
                        if CHAT.EngineQueueRebuildAll then
                            CHAT.EngineQueueRebuildAll()
                        end
                    end,
                }, {
                    type = "dropdown",
                    text = "Timestamps",
                    values = tsValues,
                    order = tsOrder,
                    getValue = CfgOr("timestampFormat", "%I:%M "),
                    setValue = function(val)
                        Set("timestampFormat", val)
                        if CHAT.ApplyTimestampCVar then
                            CHAT.ApplyTimestampCVar()
                        end
                        CludesUI:RefreshPage()
                    end,
                })
            end
            cursorY = cursorY - height

            -- Row 4: Shortened Channel Names (+ Use Letters cog) | Class Colored Names
            local abbrevRow
            abbrevRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Shortened Channel Names",
                tooltip = "Abbreviates channel prefixes, like [Party] to [P] and [Guild] to [G]; world channels show their number.",
                getValue = CfgIs("abbreviateChannels"),
                setValue = function(val)
                    Set("abbreviateChannels", val)
                    if CHAT.EngineSetChannelAbbrev then
                        CHAT.EngineSetChannelAbbrev(val)
                    end
                    if CHAT.EngineQueueRebuildAll then
                        CHAT.EngineQueueRebuildAll()
                    end
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "toggle",
                text = "Class Colored Names",
                tooltip = "Colors group and raid member names by their class when they appear in the text of Say, Yell, Party, and Raid messages.",
                getValue = CfgIs("classColorNames"),
                setValue = function(val)
                    Set("classColorNames", val)
                    if CHAT.ApplyClassColorNames then
                        CHAT.ApplyClassColorNames(val)
                    end
                    if CHAT.EngineQueueRebuildAll then
                        CHAT.EngineQueueRebuildAll()
                    end
                end,
            })
            if not CludesUI._prebuilding then
                -- Cog: world channels as letters (the old Ge / T / LD / WD / LFG)
                -- instead of their numbers. Dimmed and inert while the toggle is off.
                local lrgn = abbrevRow._leftRegion
                CludesUI.BuildInlineCog(lrgn, {
                    disabled = function()
                        return Cfg("abbreviateChannels") ~= true
                    end,
                    disabledTooltip = "Shortened Channel Names",
                    title = "Shortened Channel Names",
                    rows = {
                        {
                            type = "toggle",
                            label = "Use Letters",
                            tooltip = "Shows General, Trade, Local Defense, World Defense and LFG as letters instead of their channel numbers.",
                            get = CfgIs("abbreviateChannelLetters"),
                            set = function(val)
                                Set("abbreviateChannelLetters", val)
                                if CHAT.EngineSetChannelAbbrevLetters then
                                    CHAT.EngineSetChannelAbbrevLetters(val)
                                end
                                if CHAT.EngineQueueRebuildAll then
                                    CHAT.EngineQueueRebuildAll()
                                end
                            end,
                        },
                    },
                })
            end
            cursorY = cursorY - height
        end -- isChat

        return math.abs(cursorY)
    end

    _G._CUBS_BuildChatPage = BuildPage

    -- Blizzard Style shows Blizzard's own chat tabs, which take none of the
    -- Tabs page's settings, so the page is not offered there (WoW Forever
    -- paints its own tabs with the Tabs page's typography).
    local blizzTabsStyle = CludesUI.BlizzStyle
        and CludesUI.BlizzStyle.Active("chat") == "blizzard"
        and not CludesUI.BlizzStyle.Forever("chat")
    local chatPages = blizzTabsStyle and { "Chat", "Sidebar" } or { "Chat", "Tabs", "Sidebar" }
    -- Chat Bubbles live in Blizzard Skins+: this tab links straight there, so it
    -- is offered only while that module is loaded.
    if CludesUI._ModuleNS["CludesUIBlizzardSkin"] then
        chatPages[#chatPages + 1] = "Chat Bubbles"
    end

    CludesUI:RegisterModule("CludesUIChat", {
        title = "Chat",
        description = "Chat frame reskin, clickable URLs, copy chat, sidebar icons.",
        pages = chatPages,
        pageLinks = { ["Chat Bubbles"] = { module = "CludesUIBlizzardSkin", page = "Chat Bubbles" } },
        buildPage = function(pageName, p, yOffset)
            return BuildPage(pageName, p, yOffset)
        end,
        searchTerms = "chat tabs border spacing background sidebar friends voice url copy whisper channel abbreviate shortened class color names timestamps timestamp all messages font size",
        onReset = function()
            local d = _G._CUCHAT_DB
            if d and d.ResetProfile then
                d:ResetProfile()
            end
            RefreshAll()
            CludesUI:InvalidatePageCache()
        end,
    })
end)
