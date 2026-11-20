if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  RaidFrames_Options\VisualIndicators_Options.lua
--  Raid Frames options: the Indicators, Dispels, Top Name Bar, Friendly Boss
--  and Extra Frames, Pet Frames and Range & Tooltip sections of the raid and
--  party pages. Called by BuildVisualSections after BuildVisualBars; returns y.
--  Shared helpers come from ns._RFO_OptEnv.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIRaidFrames"]
if not mod then
    return
end -- module disabled: no options page

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host (a kept page wrapper or cog popup and every frame it hands out) are
-- reset and dressed again by the next build instead of made anew; elsewhere
-- this is CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

-- Panel close turns the Healer Mana preview off and resets the eye of each
-- tab's latest build (ns._eye[ctx]): registered once for the session, by the
-- first build that has the eye.
local hmEyeOnHide
local function StopHMPreviewOnHide()
    if not (mod._hmPreview and mod.HM_SetPreview) then
        return
    end
    mod.HM_SetPreview(false)
    local eyes = mod._eye
    if eyes then
        for _, eye in pairs(eyes) do
            if eye.refreshHMEye then
                eye.refreshHMEye()
            end
        end
    end
end

local pgEyeOnHide
local function StopPGPreviewOnHide()
    if not (mod._pgPreview and mod.PG_SetPreview) then
        return
    end
    mod.PG_SetPreview(false)
    local eyes = mod._eye
    if eyes then
        for _, eye in pairs(eyes) do
            if eye.refreshPGEye then
                eye.refreshPGEye()
            end
        end
    end
end

local function BuildVisualIndicators(hostFrame, cursorY, W, onSection, EYE, CustomBorderOff, CustomBorderOffTip)
    local environ = mod._RFO_OptEnv
    local saved, floor, IsPreviewOff, MissingGlowDesc =
        environ.db, environ.floor, environ.IsPreviewOff, environ.MissingGlowDesc
    local optionState, Pix, ReloadAndUpdate, SGet =
        environ.optState, environ.PP, environ.ReloadAndUpdate, environ.SGet
    local SSet, SVal, SWrite = environ.SSet, environ.SVal, environ.SWrite
    -- A row getter over SVal: the key's value, or the default given.
    local function SValRow(key, default)
        return function()
            return SVal(key, default)
        end
    end
    -- Row setters over SSet: the key written with the row's value.
    local function SSetRow(key)
        return function(value)
            SSet(key, value)
        end
    end
    local _, height, heading
    local row
    local _secY = cursorY -- section start tracker
    -------------------------------------------------------------------
    --  INDICATORS
    -------------------------------------------------------------------
    local indicatorHeader
    indicatorHeader, height = W:SectionHeader(hostFrame, "INDICATORS", cursorY)
    cursorY = cursorY - height

    -- Eyeball: toggle indicator visibility on preview (raid + party); none in
    -- the search pre-build (it indexes nothing, and the header is a stand-in there)
    if not CludesUI._prebuilding then
        local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON

        local indLabel
        for _, region in ipairs({ indicatorHeader:GetRegions() }) do
            if region.GetText and CludesUI.EnKey(region:GetText()) == "INDICATORS" then
                indLabel = region
                break
            end
        end
        local eyeButton = CreateFrame("Button", nil, indicatorHeader)
        eyeButton:SetSize(24, 24)
        if indLabel then
            eyeButton:SetPoint("LEFT", indLabel, "RIGHT", 5, 0)
        else
            eyeButton:SetPoint("LEFT", indicatorHeader, "BOTTOMLEFT", 85, 8)
        end
        eyeButton:SetFrameLevel(indicatorHeader:GetFrameLevel() + 5)
        CludesUI.SetGlyphAlpha(eyeButton, 0.4)
        local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()

        -- On ns so the preview can read it.
        if mod._indicatorsVisible == nil then
            mod._indicatorsVisible = false
        end

        local function RefreshIndicatorEye()
            if IsPreviewOff() then
                eyeTex:SetTexture(EYE_VISIBLE)
                CludesUI.SetGlyphAlpha(eyeButton, 0.15)
                return
            end
            eyeTex:SetTexture(mod._indicatorsVisible and EYE_INVISIBLE or EYE_VISIBLE)
            CludesUI.SetGlyphAlpha(eyeButton, 0.4)
        end
        EYE.refreshIndicatorEye = RefreshIndicatorEye
        RefreshIndicatorEye()
        eyeButton:SetScript("OnClick", function()
            if IsPreviewOff() then
                return
            end
            mod._indicatorsVisible = not mod._indicatorsVisible
            -- Indicators are exclusive with health/power/dispel effects.
            if mod._indicatorsVisible then
                if mod._healthAnimActive then
                    if mod._stopHealthAnim then
                        mod._stopHealthAnim()
                    end
                    if EYE.refreshHealthEye then
                        EYE.refreshHealthEye()
                    end
                end
                if mod._powerAnimActive then
                    if mod._stopPowerAnim then
                        mod._stopPowerAnim()
                    end
                    if EYE.refreshPowerEye then
                        EYE.refreshPowerEye()
                    end
                end
                if mod._dispelsVisible then
                    mod._dispelsVisible = false
                    if EYE.refreshDispelEye then
                        EYE.refreshDispelEye()
                    end
                end
            end
            RefreshIndicatorEye()
            if mod.PvRefresh then
                mod.PvRefresh()
            end
        end)
        eyeButton:SetScript("OnEnter", function(self)
            if IsPreviewOff() then
                CludesUI.ShowWidgetTooltip(self, "Enable preview to use")
                return
            end
            CludesUI.SetGlyphAlpha(self, 0.7)
            CludesUI.ShowWidgetTooltip(
                self,
                mod._indicatorsVisible and "Hide indicators on preview" or "Show indicators on preview"
            )
        end)
        eyeButton:SetScript("OnLeave", function(self)
            if not IsPreviewOff() then
                CludesUI.SetGlyphAlpha(self, 0.4)
            end
            CludesUI.HideWidgetTooltip()
        end)
    end -- close do (indicators eyeball)

    -- WoW Forever: Missing Buffs, first in the section (runtime in
    -- CUI_RaidFrames_ForeverMissingBuffs.lua). The raid marker row's
    -- shape: Position (None turns it off) | Size, offsets in the cog.
    if CludesUI.IS_FOREVER then
        local mbPositionValues = {
            none = "None",
            topleft = "Top Left",
            top = "Top",
            topright = "Top Right",
            left = "Left",
            center = "Center",
            right = "Right",
            bottomleft = "Bottom Left",
            bottom = "Bottom",
            bottomright = "Bottom Right",
        }
        local mbPositionOrder = {
            "none",
            "topleft",
            "top",
            "topright",
            "left",
            "center",
            "right",
            "bottomleft",
            "bottom",
            "bottomright",
        }
        local mbRow
        mbRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Missing Buffs",
            values = mbPositionValues,
            order = mbPositionOrder,
            tooltip = "Shows Fortitude, Mark of the Wild, Spirit or Thorns on a member who is missing it, for the buffs you can cast yourself (choose which in the cog).",
            getValue = function()
                if not SVal("showMissingBuffs", true) then
                    return "none"
                end
                return SVal("missingBuffsPosition", "top")
            end,
            setValue = function(val)
                if val == "none" then
                    SSet("showMissingBuffs", false)
                else
                    SWrite("showMissingBuffs", true)
                    SSet("missingBuffsPosition", val)
                end
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Missing Buffs Size",
            min = 8,
            max = 40,
            step = 1,
            disabled = function()
                return not SVal("showMissingBuffs", true)
            end,
            disabledTooltip = "Missing Buffs",
            getValue = SValRow("missingBuffsSize", 22),
            setValue = SSetRow("missingBuffsSize"),
        })
        cursorY = cursorY - height
        do
            local region = mbRow._leftRegion
            -- The role blessings, None first: the client's own spell names minus
            -- the words every blessing starts with ("Blessing of ", in any
            -- language; names sharing no leading word stay whole), English
            -- if the names are not loaded. Reads go through the runtime's
            -- resolver over the page's raw, party-aware reads, so an unset
            -- role shows what it does.
            local blessOrder = { "none", "might", "wisdom", "kings" }
            local blessItems = {}
            local BLESS_ID = { might = 19740, wisdom = 19742, kings = 20217 }
            local BLESS_EN = { might = "Might", wisdom = "Wisdom", kings = "Kings" }
            local blessValues = { none = "None" }
            local full, common = {}, nil
            for idx = 2, #blessOrder do
                local num = C_Spell.GetSpellName(BLESS_ID[blessOrder[idx]])
                if not num then
                    full = nil
                    break
                end
                full[blessOrder[idx]] = num
                local jdx = 0
                if common then
                    while jdx < #common and jdx < #num and common:byte(jdx + 1) == num:byte(jdx + 1) do
                        jdx = jdx + 1
                    end
                end
                common = common and common:sub(1, jdx) or num
            end
            local cut = full and common and common:match("^(.*%s)")
            for idx = 2, #blessOrder do
                local keyName = blessOrder[idx]
                local num = full and full[keyName]
                blessValues[keyName] = (num and cut) and num:sub(#cut + 1) or num or BLESS_EN[keyName]
                blessItems[#blessItems + 1] = { key = keyName, label = blessValues[keyName] }
            end
            local view = setmetatable({}, {
                __index = function(_, keyName)
                    return SGet(keyName)
                end,
            })
            -- A priority list per role: the checked blessings in the order
            -- shown (drag to reorder); the first one the member lacks shows.
            -- Each open lists the checked ones first, in priority order.
            -- A blessing list row: picked() = the list it shows, write(list)
            -- saves a new one, which keeps the order shown.
            local function ListRow(labelText, picked, write)
                local function Save(sequence, key, on)
                    local keep = {}
                    for _, keyName in ipairs(picked()) do
                        keep[keyName] = true
                    end
                    if key then
                        keep[key] = on or nil
                    end
                    local entries = {}
                    for _, keyName in ipairs(sequence) do
                        if keep[keyName] then
                            entries[#entries + 1] = keyName
                        end
                    end
                    write(entries)
                end
                return {
                    type = "reordercheck",
                    label = labelText,
                    ddWidth = 170,
                    grip = true,
                    hint = "Drag to set priority",
                    items = blessItems,
                    get = function(key)
                        for _, keyName in ipairs(picked()) do
                            if keyName == key then
                                return true
                            end
                        end
                        return false
                    end,
                    set = function(key, on, sequence)
                        Save(sequence, key, on)
                    end,
                    setOrder = function(keyList)
                        Save(keyList)
                    end,
                    openOrder = picked,
                }
            end
            -- Class exceptions: the classes that can fill each role, one list
            -- each in a popup beside this one; a class's own list replaces
            -- the role's list for members of that class.
            local ROLE_CLASSES = {
                TANK = { "DRUID", "PALADIN", "WARRIOR" },
                HEALER = { "DRUID", "PALADIN", "PRIEST", "SHAMAN" },
                DAMAGER = {
                    "DRUID",
                    "HUNTER",
                    "MAGE",
                    "PALADIN",
                    "PRIEST",
                    "ROGUE",
                    "SHAMAN",
                    "WARLOCK",
                    "WARRIOR",
                },
            }
            local ROLE_TITLE =
                { TANK = "Tank Exceptions", HEALER = "Healer Exceptions", DAMAGER = "DPS Exceptions" }
            local function BlessRow(labelText, tipText, role)
                local function Picked()
                    return mod.RF_FvBlessingChoice(view, role)
                end
                local exKey = mod.RF_FvBlessingExKey[role]
                local function Own(class)
                    local ex = SGet(exKey)
                    local entries = type(ex) == "table" and ex[class]
                    return type(entries) == "table" and entries or nil
                end
                -- A fresh table on every save: the saved one is also what the
                -- runtime reads.
                local function SetOwn(class, entries)
                    local ex = {}
                    local old = SGet(exKey)
                    if type(old) == "table" then
                        for keyName, val in pairs(old) do
                            ex[keyName] = val
                        end
                    end
                    ex[class] = entries
                    SSet(exKey, next(ex) ~= nil and ex or nil)
                end
                local exShow, exAnchor
                local function OpenExceptions(_, dropdownBtn)
                    if not exShow then
                        local reset = "Use the " .. labelText:gsub(" Blessing", "") .. " List"
                        local rowList = {}
                        for _, token in ipairs(ROLE_CLASSES[role]) do
                            local name = LOCALIZED_CLASS_NAMES_MALE[token] or token
                            local color = CludesUI.GetClassColor(token)
                            local r = ListRow(CludesUI.HexColor(color.r, color.g, color.b) .. name .. "|r", function()
                                return Own(token) or Picked()
                            end, function(entries)
                                SetOwn(token, entries)
                            end)
                            r.tail = { { key = "reset", label = reset } }
                            r.onTail = function()
                                SetOwn(token, nil)
                            end
                            r.tailSelected = function()
                                return Own(token) == nil
                            end
                            rowList[#rowList + 1] = r
                        end
                        local popFrame = dropdownBtn:GetParent()
                        local _, show = CludesUI.BuildCogPopup({
                            title = ROLE_TITLE[role],
                            rows = rowList,
                            noOwnerDim = true,
                        })
                        exShow = show
                        -- Cog popups hang below their anchor: this one sits on
                        -- the cog popup's top edge, so the list opens beside it.
                        exAnchor = CreateFrame("Frame", nil, popFrame)
                        exAnchor:SetSize(1, 1)
                        exAnchor:SetScript("OnHide", function()
                            local frame = exShow._popupFrame
                            if frame and frame:IsShown() then
                                frame:Hide()
                            end
                        end)
                    end
                    exShow(exAnchor)
                    local frame = exShow._popupFrame
                    exAnchor:ClearAllPoints()
                    exAnchor:SetPoint("BOTTOM", exAnchor:GetParent(), "TOPRIGHT", 4 + frame:GetWidth() / 2, 5)
                    dropdownBtn._sidePopup = frame
                end
                local r = ListRow(labelText, Picked, function(entries)
                    SSet(mod.RF_FvBlessingKey[role], entries)
                end)
                r.tooltip = tipText
                r.tail = { { key = "exceptions", label = "Class Exceptions" } }
                r.onTail = OpenExceptions
                return r
            end
            local rowList = {
                -- One switch per buff (all on by default). The list is the
                -- profile's, shared across classes, so every buff is listed;
                -- only the ones this character can cast ever show. The
                -- paladin blessings follow the role rows below instead;
                -- Salvation, which stacks with them, is a switch here and
                -- never shows on a tank.
                {
                    type = "reordercheck",
                    label = "Buffs",
                    ddWidth = 170, -- the Glow dropdown's width
                    hint = "Only buffs you can cast show",
                    items = {
                        { key = "missingBuffsFort", label = "Fortitude", fixed = true },
                        { key = "missingBuffsMark", label = "Mark of the Wild", fixed = true },
                        { key = "missingBuffsIntellect", label = "Arcane Intellect", fixed = true },
                        { key = "missingBuffsSpirit", label = "Spirit", fixed = true },
                        { key = "missingBuffsThorns", label = "Thorns", fixed = true },
                        { key = "missingBuffsSalvation", label = "Salvation", fixed = true },
                    },
                    get = function(key)
                        return SVal(key, true)
                    end,
                    set = function(key, on)
                        SSet(key, on)
                    end,
                },
                -- Stored false, not nil, so a party tab with its own settings
                -- can turn it off over a raid value that is on.
                {
                    type = "toggle",
                    label = "Thorns Only on Tank",
                    tooltip = "Thorns shows on tanks only while the group has one, and on you while solo or without a tank.",
                    disabled = function()
                        return not SVal("missingBuffsThorns", true)
                    end,
                    disabledTooltip = "Thorns",
                    get = SValRow("missingBuffsThornsTank", false),
                    set = function(val)
                        SSet("missingBuffsThornsTank", val and true or false)
                    end,
                },
                BlessRow(
                    "Tank Blessing",
                    "Reminds you of the first checked blessing a tank lacks, top to bottom.",
                    "TANK"
                ),
                BlessRow(
                    "Healer Blessing",
                    "Reminds you of the first checked blessing a healer lacks, top to bottom.",
                    "HEALER"
                ),
                BlessRow(
                    "DPS Blessing",
                    "Reminds you of the first checked blessing a damage dealer lacks, top to bottom. Members with no assigned role use this list too.",
                    "DAMAGER"
                ),
                {
                    type = "slider",
                    label = "Offset X",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValRow("missingBuffsOffsetX", 0),
                    set = SSetRow("missingBuffsOffsetX"),
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValRow("missingBuffsOffsetY", 0),
                    set = SSetRow("missingBuffsOffsetY"),
                },
            }
            -- The icons' glow: the shared glow controls (also listed on
            -- Global Settings > Glows); the Pixel Glow rows show only
            -- while Pixel Glow is picked.
            for _, r in ipairs(CludesUI.GlowOptions.PopupRows(MissingGlowDesc(SVal, SWrite), "Glow", true)) do
                rowList[#rowList + 1] = r
            end
            CludesUI.BuildInlineCog(region, {
                title = "Missing Buffs",
                rows = rowList,
                disabled = function()
                    return not SVal("showMissingBuffs", true)
                end,
                disabledTooltip = "Missing Buffs",
            })
        end
    end

    local RI_STYLES = mod.ROLE_ICON_STYLES
    -- Effective role: the player's spec wins over a stale assigned role
    local playerRole = CludesUI.UnitEffectiveRole("player")
    local roleStyleValues = {
        none = "None",
        modern = "Modern",
        modernCircle = "Modern Circle",
        styled = "Styled",
        classicCircle = "Classic Circle",
        classic = "Classic",
        blizzDefault = "Blizz Default",
        -- Key stays "blizzLight" so saved roleIconStyle values resolve; only the display label reads "Modern Light".
        blizzLight = "Modern Light",
        pixels = "Pixels",
        _menuOpts = {
            icon = function(key)
                local map = RI_STYLES[key]
                if not map or not playerRole or map[playerRole] == nil then
                    return nil
                end
                if map._isTexture then
                    return map[playerRole]
                end
                return nil
            end,
            iconAtlas = function(key)
                local map = RI_STYLES[key]
                if not map or not playerRole or map[playerRole] == nil then
                    return nil
                end
                if not map._isTexture then
                    return map[playerRole]
                end
                return nil
            end,
        },
    }
    local roleStyleOrder = {
        "none",
        "modern",
        "blizzLight",
        "pixels",
        "modernCircle",
        "styled",
        "classicCircle",
        "classic",
        "blizzDefault",
    }
    row, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Role Icons",
        values = roleStyleValues,
        order = roleStyleOrder,
        disabled = function()
            return SVal("roleText", false)
        end,
        disabledTooltip = "Role Text",
        requireState = "disabled",
        getValue = SValRow("roleIconStyle", "modern"),
        setValue = function(val)
            SSet("roleIconStyle", val)
            CludesUI:RefreshPage()
        end,
    }, {
        type = "dropdown",
        text = "Show Role",
        disabled = function()
            return not SVal("roleText", false) and SVal("roleIconStyle", "modern") == "none"
        end,
        disabledTooltip = "Role Icons",
        values = { __placeholder = "All Roles" },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
    })
    cursorY = cursorY - height
    -- Right side placeholder dropdown is swapped for a checkbox dropdown.
    if not CludesUI._prebuilding then
        local rightRegion = row._rightRegion
        if rightRegion._control then
            rightRegion._control:Hide()
        end
        local function ShowRoleItems()
            local itemList = {
                { key = "tank", label = "Tank" },
                { key = "healer", label = "Healer" },
                { key = "dps", label = "DPS" },
            }
            if SVal("roleText", false) then
                for _, entry in ipairs(itemList) do
                    local colorKey = "roleText" .. entry.label .. "Color"
                    entry.swatch = {
                        get = function()
                            local color = SGet(colorKey) or mod._internals.defaults.profile[colorKey]
                            return color.r, color.g, color.b
                        end,
                        set = function(red, green, blue)
                            SSet(colorKey, { r = red, g = green, b = blue })
                            if mod._UpdateRoleIcons then
                                mod._UpdateRoleIcons()
                            end
                        end,
                    }
                end
            end
            return itemList
        end
        local roleKeyMap = { tank = "showRoleForTank", healer = "showRoleForHealer", dps = "showRoleForDPS" }
        local checkDrop = CludesUI.BuildVisOptsCBDropdown(
            rightRegion,
            170,
            rightRegion:GetFrameLevel() + 2,
            ShowRoleItems,
            function(keyName)
                return SVal(roleKeyMap[keyName], true)
            end,
            function(keyName, val)
                SSet(roleKeyMap[keyName], val)
            end
        )
        Pix.Point(checkDrop, "RIGHT", rightRegion, "RIGHT", -20, 0)
        rightRegion._control = checkDrop
        rightRegion._lastInline = nil
    end
    do
        local region = row._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Role Icons",
            rows = {
                {
                    type = "toggle",
                    label = "Role Text",
                    tooltip = "Show Healer, Tank, or DPS text instead of the role icon, using the same size, position, and Show Role settings.",
                    get = SValRow("roleText", false),
                    set = function(val)
                        SSet("roleText", val)
                        if mod._UpdateRoleIcons then
                            mod._UpdateRoleIcons()
                        end
                        CludesUI:RefreshPage()
                    end,
                },
                {
                    type = "toggle",
                    label = "Hide In Combat",
                    tooltip = "Hide role icons while you are in combat.",
                    get = SValRow("roleIconHideInCombat", false),
                    set = function(val)
                        SSet("roleIconHideInCombat", val)
                        if mod._UpdateRoleIcons then
                            mod._UpdateRoleIcons()
                        end
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Behind Border",
                    tooltip = "Draw role icons behind the frame border, including the hover and target highlight.",
                    get = SValRow("roleIconBehindBorder", false),
                    set = SSetRow("roleIconBehindBorder"),
                },
            },
        })
    end
    local rolePositionValues = {
        topleft = "Top Left",
        top = "Top",
        topright = "Top Right",
        left = "Left",
        center = "Center",
        right = "Right",
        bottomleft = "Bottom Left",
        bottom = "Bottom",
        bottomright = "Bottom Right",
    }
    local rolePositionOrder = CludesUI.POSITION_GRID_ORDER
    -- Attach Role Icons (Top Name Bar section) takes over the role icon's placement
    local function RoleAttached()
        return SVal("roleIconOnNameBar", false) and SVal("topNameBarEnabled", false)
    end
    local roleRow2
    -- Party Frames kit: role, ready check and leader take the stock spots
    -- (their offset cogs stay live).
    roleRow2, height = W:DualRow(
        hostFrame,
        cursorY,
        mod.RF_PartyKitGate({
            type = "dropdown",
            text = "Role Position",
            values = rolePositionValues,
            order = rolePositionOrder,
            disabled = function()
                return RoleAttached()
                    or (not SVal("roleText", false) and SVal("roleIconStyle", "modern") == "none")
            end,
            disabledTooltip = function()
                return RoleAttached() and "Attach Role Icons" or "Role Icons"
            end,
            requireState = function()
                return RoleAttached() and "disabled" or nil
            end,
            getValue = SValRow("roleIconPosition", "bottomleft"),
            setValue = SSetRow("roleIconPosition"),
        }),
        {
            type = "slider",
            text = "Role Icon Size",
            min = 8,
            max = 30,
            step = 1,
            disabled = function()
                return not SVal("roleText", false) and SVal("roleIconStyle", "modern") == "none"
            end,
            disabledTooltip = "Role Icons",
            getValue = SValRow("roleIconSize", 14),
            setValue = SSetRow("roleIconSize"),
        }
    )
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        local region = roleRow2._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Role Icon Offset",
            disabled = RoleAttached,
            disabledTooltip = "Attach Role Icons",
            requireState = "disabled",
            rows = {
                {
                    type = "slider",
                    label = "Offset X",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValRow("roleIconOffsetX", 0),
                    set = SSetRow("roleIconOffsetX"),
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValRow("roleIconOffsetY", 0),
                    set = SSetRow("roleIconOffsetY"),
                },
            },
        })
    end

    local markerPositionValues = {
        none = "None",
        topleft = "Top Left",
        top = "Top",
        topright = "Top Right",
        left = "Left",
        center = "Center",
        right = "Right",
        bottomleft = "Bottom Left",
        bottom = "Bottom",
        bottomright = "Bottom Right",
    }
    local markerPositionOrder = {
        "none",
        "topleft",
        "top",
        "topright",
        "left",
        "center",
        "right",
        "bottomleft",
        "bottom",
        "bottomright",
    }
    row, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Marker Position",
        values = markerPositionValues,
        order = markerPositionOrder,
        getValue = function()
            if not SVal("showRaidMarker", true) then
                return "none"
            end
            return SVal("raidMarkerPosition", "center")
        end,
        setValue = function(val)
            if val == "none" then
                SSet("showRaidMarker", false)
            else
                SWrite("showRaidMarker", true)
                SSet("raidMarkerPosition", val)
            end
            CludesUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Marker Size",
        min = 8,
        max = 40,
        step = 1,
        disabled = function()
            return not SVal("showRaidMarker", true)
        end,
        disabledTooltip = "Marker Position",
        getValue = SValRow("raidMarkerSize", 16),
        setValue = SSetRow("raidMarkerSize"),
    })
    cursorY = cursorY - height

    do
        local region = row._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Marker Offset",
            rows = {
                {
                    type = "slider",
                    label = "Offset X",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValRow("raidMarkerOffsetX", 0),
                    set = SSetRow("raidMarkerOffsetX"),
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValRow("raidMarkerOffsetY", 0),
                    set = SSetRow("raidMarkerOffsetY"),
                },
            },
        })
    end

    -- Rows below Marker Position are the less-common indicators. The RAID tab collapses them behind the shared session expander (BuildLessCommonExpander in CludesUI_Widgets_RowAddons.lua); the party tab always shows them.
    local lessCommonOpen = true
    if not optionState._partyCtx then
        lessCommonOpen, cursorY = CludesUI.BuildLessCommonExpander(
            hostFrame,
            cursorY,
            "rfIndicators",
            "Show Less Common Indicator Options"
        )
    end
    if lessCommonOpen then
        -- The three indicators share a single texture, so one position + size control set drives all of them.
        local readyCheckPositionValues = {
            topleft = "Top Left",
            top = "Top",
            topright = "Top Right",
            left = "Left",
            center = "Center",
            right = "Right",
            bottomleft = "Bottom Left",
            bottom = "Bottom",
            bottomright = "Bottom Right",
        }
        local readyCheckPositionOrder = CludesUI.POSITION_GRID_ORDER
        local rcRow
        rcRow, height = W:DualRow(
            hostFrame,
            cursorY,
            mod.RF_PartyKitGate({
                type = "dropdown",
                text = "Ready Check / Summon / Rez",
                values = readyCheckPositionValues,
                order = readyCheckPositionOrder,
                getValue = SValRow("readyCheckPosition", "center"),
                setValue = SSetRow("readyCheckPosition"),
            }),
            {
                type = "slider",
                text = "Icon Size",
                min = 8,
                max = 40,
                step = 1,
                getValue = SValRow("readyCheckSize", 20),
                setValue = SSetRow("readyCheckSize"),
            }
        )
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            local region = rcRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Ready Check / Summon / Rez",
                rows = {
                    {
                        type = "toggle",
                        label = "Show Ready Check",
                        get = SValRow("showReadyCheck", true),
                        set = SSetRow("showReadyCheck"),
                    },
                    {
                        type = "toggle",
                        label = "Show Incoming Summon",
                        get = SValRow("showSummonPending", true),
                        set = SSetRow("showSummonPending"),
                    },
                    {
                        type = "toggle",
                        label = "Show Incoming Resurrection",
                        get = SValRow("showIncomingRez", true),
                        set = SSetRow("showIncomingRez"),
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValRow("readyCheckOffsetX", 0),
                        set = SSetRow("readyCheckOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValRow("readyCheckOffsetY", 0),
                        set = SSetRow("readyCheckOffsetY"),
                    },
                },
            })
        end

        local statusTextPositionValues = {
            none = "None",
            topleft = "Top Left",
            top = "Top",
            topright = "Top Right",
            left = "Left",
            center = "Center",
            right = "Right",
            bottomleft = "Bottom Left",
            bottom = "Bottom",
            bottomright = "Bottom Right",
        }
        local statusTextPositionOrder = {
            "none",
            "topleft",
            "top",
            "topright",
            "left",
            "center",
            "right",
            "bottomleft",
            "bottom",
            "bottomright",
        }
        local stRow
        stRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Status Text",
            values = statusTextPositionValues,
            order = statusTextPositionOrder,
            getValue = SValRow("statusTextPosition", "center"),
            setValue = SSetRow("statusTextPosition"),
        }, {
            type = "slider",
            text = "Text Size",
            min = 6,
            max = 30,
            step = 1,
            getValue = SValRow("statusTextSize", 14),
            setValue = SSetRow("statusTextSize"),
        })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            local region = stRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Status Text",
                rows = {
                    {
                        type = "toggle",
                        label = "Show AFK",
                        get = SValRow("statusShowAFK", false),
                        set = function(val)
                            SSet("statusShowAFK", val)
                            ReloadAndUpdate()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValRow("statusTextOffsetX", 0),
                        set = SSetRow("statusTextOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValRow("statusTextOffsetY", 0),
                        set = SSetRow("statusTextOffsetY"),
                    },
                },
            })
        end
        if not CludesUI._prebuilding then
            local region = stRow._rightRegion
            local colorSwatch = CludesUI.BuildColorSwatch(region, stRow:GetFrameLevel() + 3, function()
                local color = SGet("statusTextColor")
                if color then
                    return color.r, color.g, color.b, 1
                end
                return 1, 1, 1, 1
            end, function(red, green, blue)
                SWrite("statusTextColor", { r = red, g = green, b = blue })
                ReloadAndUpdate()
            end, false, 20)
            colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
        end

        local leaderPositionValues = {
            none = "None",
            topleft = "Top Left",
            top = "Top",
            topright = "Top Right",
            left = "Left",
            center = "Center",
            right = "Right",
            bottomleft = "Bottom Left",
            bottom = "Bottom",
            bottomright = "Bottom Right",
        }
        local leaderPositionOrder = {
            "none",
            "topleft",
            "top",
            "topright",
            "left",
            "center",
            "right",
            "bottomleft",
            "bottom",
            "bottomright",
        }
        -- (The dropdown is also the leader icon's on/off switch, so under the
        -- kit it keeps that job: shown at the stock spot, or None.)
        row, height = W:DualRow(hostFrame, cursorY, mod.RF_OptPartyKit() and {
            type = "segmented",
            text = "Leader Icon",
            values = { kit = "Party Frame", none = "None" },
            order = { "kit", "none" },
            getValue = function()
                return SVal("showLeaderIcon", false) and "kit" or "none"
            end,
            setValue = function(val)
                SSet("showLeaderIcon", val ~= "none")
                CludesUI:RefreshPage()
            end,
        } or {
            type = "dropdown",
            text = "Leader Icon",
            values = leaderPositionValues,
            order = leaderPositionOrder,
            getValue = function()
                if not SVal("showLeaderIcon", false) then
                    return "none"
                end
                return SVal("leaderIconPosition", "top")
            end,
            setValue = function(val)
                if val == "none" then
                    SSet("showLeaderIcon", false)
                else
                    SWrite("showLeaderIcon", true)
                    SSet("leaderIconPosition", val)
                end
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Leader Icon Size",
            min = 8,
            max = 30,
            step = 1,
            disabled = function()
                return not SVal("showLeaderIcon", false)
            end,
            disabledTooltip = "Leader Icon",
            getValue = SValRow("leaderIconSize", 14),
            setValue = SSetRow("leaderIconSize"),
        })
        cursorY = cursorY - height
        do
            local region = row._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Leader Icon",
                rows = {
                    {
                        type = "toggle",
                        label = "Show In Combat",
                        tooltip = "Show the leader/assistant icon while you are in combat. Disable to hide it during combat.",
                        get = SValRow("showLeaderIconInCombat", true),
                        set = function(val)
                            SSet("showLeaderIconInCombat", val)
                            if mod._UpdateLeaderIcons then
                                mod._UpdateLeaderIcons()
                            end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValRow("leaderIconOffsetX", 0),
                        set = SSetRow("leaderIconOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValRow("leaderIconOffsetY", 0),
                        set = SSetRow("leaderIconOffsetY"),
                    },
                },
            })
        end

        -- Combat Icon Position ("None" disables) | Combat Icon Size; shows on members currently in combat. Style/color/offset live in the inline cog.
        local combatPositionValues = {
            none = "None",
            topleft = "Top Left",
            top = "Top",
            topright = "Top Right",
            left = "Left",
            center = "Center",
            right = "Right",
            bottomleft = "Bottom Left",
            bottom = "Bottom",
            bottomright = "Bottom Right",
        }
        local combatPositionOrder = {
            "none",
            "topleft",
            "top",
            "topright",
            "left",
            "center",
            "right",
            "bottomleft",
            "bottom",
            "bottomright",
        }
        local combatStyleValues = {
            standard = "Standard",
            class = "Class Theme",
            combat0 = "Arcade",
            combat1 = "Dungeoneer",
            combat2 = "Classic",
            combat3 = "Cross",
            combat4 = "Circle",
            combat5 = "Square",
        }
        local combatStyleOrder =
            { "standard", "class", "combat0", "combat1", "combat2", "combat3", "combat4", "combat5" }
        local ciRow
        ciRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Combat Icon",
            values = combatPositionValues,
            order = combatPositionOrder,
            getValue = function()
                if not SVal("showCombatIndicator", false) then
                    return "none"
                end
                return SVal("combatIndicatorPosition", "right")
            end,
            setValue = function(val)
                if val == "none" then
                    SSet("showCombatIndicator", false)
                else
                    SWrite("showCombatIndicator", true)
                    SSet("combatIndicatorPosition", val)
                end
                if mod._UpdateCombatIcons then
                    mod._UpdateCombatIcons()
                end
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Combat Icon Size",
            min = 8,
            max = 40,
            step = 1,
            disabled = function()
                return not SVal("showCombatIndicator", false)
            end,
            disabledTooltip = "Combat Icon",
            getValue = SValRow("combatIndicatorSize", 16),
            setValue = SSetRow("combatIndicatorSize"),
        })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            local region = ciRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Combat Icon",
                rows = {
                    {
                        type = "dropdown",
                        label = "Style",
                        values = combatStyleValues,
                        order = combatStyleOrder,
                        get = SValRow("combatIndicatorStyle", "standard"),
                        set = function(val)
                            SSet("combatIndicatorStyle", val)
                            if mod._UpdateCombatIcons then
                                mod._UpdateCombatIcons()
                            end
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Class Colored",
                        tooltip = "Tint the combat icon by the member's class color. Not available for the Arcade/Dungeoneer/Classic/Cross/Circle/Square styles.",
                        disabled = function()
                            local st = SVal("combatIndicatorStyle", "standard")
                            return st:find("^combat%d") and true or false
                        end,
                        disabledTooltip = "Not available for this combat icon style.",
                        rawTooltip = true,
                        get = function()
                            return SVal("combatIndicatorColor", "custom") == "classcolor"
                        end,
                        set = function(val)
                            SSet("combatIndicatorColor", val and "classcolor" or "custom")
                            if mod._UpdateCombatIcons then
                                mod._UpdateCombatIcons()
                            end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValRow("combatIndicatorOffsetX", 0),
                        set = SSetRow("combatIndicatorOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValRow("combatIndicatorOffsetY", 0),
                        set = SSetRow("combatIndicatorOffsetY"),
                    },
                },
            })
        end
        if not CludesUI._prebuilding then
            local region = ciRow._rightRegion
            local colorSwatch = CludesUI.BuildColorSwatch(region, ciRow:GetFrameLevel() + 3, function()
                local color = SGet("combatIndicatorCustomColor")
                if color then
                    return color.r, color.g, color.b, 1
                end
                return 1, 0.2, 0.2, 1
            end, function(red, green, blue)
                SWrite("combatIndicatorCustomColor", { r = red, g = green, b = blue })
                if mod._UpdateCombatIcons then
                    mod._UpdateCombatIcons()
                end
            end, false, 20)
            colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
        end

        -- Show Group Numbers | Number Size (+ alpha swatch). Raid only: party has no groups. Size + color also drive the always-on preview group labels; the toggle gates only the real frames.
        if not optionState._partyCtx then
            local gnRow
            gnRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Show Group Numbers",
                getValue = SValRow("showGroupNumbers", false),
                setValue = SSetRow("showGroupNumbers"),
            }, {
                type = "slider",
                text = "Number Size",
                min = 6,
                max = 30,
                step = 1,
                getValue = SValRow("groupNumberSize", 10),
                setValue = SSetRow("groupNumberSize"),
            })
            cursorY = cursorY - height
            if not CludesUI._prebuilding then
                local region = gnRow._rightRegion
                local colorSwatch = CludesUI.BuildColorSwatch(region, gnRow:GetFrameLevel() + 3, function()
                    local color = SGet("groupNumberColor")
                    if color then
                        return color.r, color.g, color.b, color.a or 0.75
                    end
                    return 1, 1, 1, 0.75
                end, function(red, green, blue, a)
                    SWrite("groupNumberColor", { r = red, g = green, b = blue, a = a })
                    ReloadAndUpdate()
                end, true, 20)
                colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                region._lastInline = colorSwatch
            end
            if not CludesUI._prebuilding then
                local region = gnRow._leftRegion
                CludesUI.BuildInlineCog(region, {
                    title = "Group Number Offset",
                    rows = {
                        {
                            type = "slider",
                            label = "Offset X",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = SValRow("groupNumberOffsetX", 0),
                            set = SSetRow("groupNumberOffsetX"),
                        },
                        {
                            type = "slider",
                            label = "Offset Y",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = SValRow("groupNumberOffsetY", 0),
                            set = SSetRow("groupNumberOffsetY"),
                        },
                    },
                })
            end
        end

        -- Ping Marker | Ping Marker Size (+ offset cog). The mark a group member's ping
        -- puts on the pinged unit's frame, Blizzard's own art. Also needs Blizzard's
        -- "Show Pings on Raid Frames" setting on (same gate as the default frames).
        local pingPositionValues = {
            none = "None",
            topleft = "Top Left",
            top = "Top",
            topright = "Top Right",
            left = "Left",
            center = "Center",
            right = "Right",
            bottomleft = "Bottom Left",
            bottom = "Bottom",
            bottomright = "Bottom Right",
        }
        local pingPositionOrder = {
            "none",
            "topleft",
            "top",
            "topright",
            "left",
            "center",
            "right",
            "bottomleft",
            "bottom",
            "bottomright",
        }
        local pingRow
        pingRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Ping Marker",
            values = pingPositionValues,
            order = pingPositionOrder,
            tooltip = "Shows the ping mark on a member's frame when someone pings them (needs Blizzard's Show Pings on Raid Frames setting on).",
            getValue = function()
                if not SVal("showPingMarker", true) then
                    return "none"
                end
                return SVal("pingMarkerPosition", "center")
            end,
            setValue = function(val)
                if val == "none" then
                    SSet("showPingMarker", false)
                else
                    SWrite("showPingMarker", true)
                    SSet("pingMarkerPosition", val)
                end
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Ping Marker Size",
            min = 10,
            max = 60,
            step = 1,
            disabled = function()
                return not SVal("showPingMarker", true)
            end,
            disabledTooltip = "Ping Marker",
            getValue = SValRow("pingMarkerSize", 30),
            setValue = SSetRow("pingMarkerSize"),
        })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            local region = pingRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Ping Marker Offset",
                rows = {
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValRow("pingMarkerOffsetX", 0),
                        set = SSetRow("pingMarkerOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValRow("pingMarkerOffsetY", 0),
                        set = SSetRow("pingMarkerOffsetY"),
                    },
                },
            })
        end
    end -- close the less-common-indicators collapse wrapper
    -- While expanded the shared link re-renders here in its "Hide ..." form; no-op while collapsed or in party ctx.
    if not optionState._partyCtx then
        cursorY = CludesUI.FinishLessCommonExpander(
            hostFrame,
            cursorY,
            "rfIndicators",
            "Show Less Common Indicator Options"
        )
    end

    -------------------------------------------------------------------
    --  DISPELS
    -------------------------------------------------------------------
    local dispelHeader
    if onSection then
        onSection("indicators", _secY, cursorY)
    end
    _secY = cursorY
    dispelHeader, height = W:SectionHeader(hostFrame, "DISPELS", cursorY)
    cursorY = cursorY - height

    -- Eyeball: toggle dispel visibility on preview (raid + party); none in
    -- the search pre-build (it indexes nothing, and the header is a stand-in there)
    if not CludesUI._prebuilding then
        local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON

        local dispLabel
        for _, region in ipairs({ dispelHeader:GetRegions() }) do
            if region.GetText and CludesUI.EnKey(region:GetText()) == "DISPELS" then
                dispLabel = region
                break
            end
        end
        local eyeButton = CreateFrame("Button", nil, dispelHeader)
        eyeButton:SetSize(24, 24)
        if dispLabel then
            eyeButton:SetPoint("LEFT", dispLabel, "RIGHT", 5, 0)
        else
            eyeButton:SetPoint("LEFT", dispelHeader, "BOTTOMLEFT", 85, 8)
        end
        eyeButton:SetFrameLevel(dispelHeader:GetFrameLevel() + 5)
        CludesUI.SetGlyphAlpha(eyeButton, 0.4)
        local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()

        if mod._dispelsVisible == nil then
            mod._dispelsVisible = false
        end

        local function RefreshDispelEye()
            if IsPreviewOff() then
                eyeTex:SetTexture(EYE_VISIBLE)
                CludesUI.SetGlyphAlpha(eyeButton, 0.15)
                return
            end
            eyeTex:SetTexture(mod._dispelsVisible and EYE_INVISIBLE or EYE_VISIBLE)
            CludesUI.SetGlyphAlpha(eyeButton, 0.4)
        end
        EYE.refreshDispelEye = RefreshDispelEye
        RefreshDispelEye()
        eyeButton:SetScript("OnClick", function()
            if IsPreviewOff() then
                return
            end
            mod._dispelsVisible = not mod._dispelsVisible
            -- Dispels and indicators are mutually exclusive.
            if mod._dispelsVisible then
                if mod._indicatorsVisible then
                    mod._indicatorsVisible = false
                    if EYE.refreshIndicatorEye then
                        EYE.refreshIndicatorEye()
                    end
                end
            end
            RefreshDispelEye()
            if mod.PvRefresh then
                mod.PvRefresh()
            end
        end)
        eyeButton:SetScript("OnEnter", function(self)
            if IsPreviewOff() then
                CludesUI.ShowWidgetTooltip(self, "Enable preview to use")
                return
            end
            CludesUI.SetGlyphAlpha(self, 0.7)
            CludesUI.ShowWidgetTooltip(
                self,
                mod._dispelsVisible and "Hide dispels on preview" or "Show dispels on preview"
            )
        end)
        eyeButton:SetScript("OnLeave", function(self)
            if not IsPreviewOff() then
                CludesUI.SetGlyphAlpha(self, 0.4)
            end
            CludesUI.HideWidgetTooltip()
        end)
    end -- close do (dispels eyeball)

    local dispelOverlayValues = {
        none = "None",
        fill = "Fill Overlay",
        full = "Full Overlay",
        gradient = "Gradient Overlay",
        gradient_sharp = "Gradient Sharp",
        gradient_reverse = "Gradient Sharp Reverse",
    }
    local dispelOverlayOrder = { "none", "fill", "full", "gradient", "gradient_sharp", "gradient_reverse" }

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Dispel Overlay",
        values = dispelOverlayValues,
        order = dispelOverlayOrder,
        getValue = SValRow("dispelOverlay", "fill"),
        setValue = function(val)
            SSet("dispelOverlay", val)
            CludesUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Overlay Opacity",
        min = 5,
        max = 100,
        step = 1,
        disabled = function()
            return SVal("dispelOverlay", "fill") == "none"
        end,
        disabledTooltip = "Dispel Overlay",
        getValue = SValRow("dispelOverlayOpacity", 100),
        setValue = SSetRow("dispelOverlayOpacity"),
    })
    cursorY = cursorY - height

    local dispelIconPositionValues = {
        none = "None",
        topleft = "Top Left",
        top = "Top",
        topright = "Top Right",
        left = "Left",
        center = "Center",
        right = "Right",
        bottomleft = "Bottom Left",
        bottom = "Bottom",
        bottomright = "Bottom Right",
    }
    local dispelIconPositionOrder = {
        "none",
        "topleft",
        "top",
        "topright",
        "left",
        "center",
        "right",
        "bottomleft",
        "bottom",
        "bottomright",
    }
    row, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Frame Border",
        min = 0,
        max = 4,
        step = 1,
        getValue = SValRow("dispelBorderSize", 2),
        setValue = SSetRow("dispelBorderSize"),
    }, {
        type = "dropdown",
        text = "Type Icon Position",
        values = dispelIconPositionValues,
        order = dispelIconPositionOrder,
        getValue = function()
            if not SVal("showDispelIcons", false) then
                return "none"
            end
            return SVal("dispelIconPosition", "center")
        end,
        setValue = function(val)
            if val == "none" then
                SSet("showDispelIcons", false)
            else
                SSet("showDispelIcons", true)
                SSet("dispelIconPosition", val)
            end
            CludesUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height
    do
        local region = row._rightRegion
        CludesUI.BuildInlineCog(region, {
            disabled = function()
                return not SVal("showDispelIcons", false)
            end,
            disabledTooltip = "This option requires a Type Icon Position other than None",
            title = "Dispel Icon",
            rows = {
                {
                    type = "slider",
                    label = "Icon Size",
                    min = 8,
                    max = 48,
                    step = 1,
                    get = SValRow("dispelIconSize", 16),
                    set = SSetRow("dispelIconSize"),
                },
                {
                    type = "slider",
                    label = "Offset X",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValRow("dispelIconOffsetX", 0),
                    set = SSetRow("dispelIconOffsetX"),
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValRow("dispelIconOffsetY", 0),
                    set = SSetRow("dispelIconOffsetY"),
                },
            },
        })
    end
    -- Cog on the Dispel Border slider: thickness in physical pixels of the engine-tinted dispel ring on dispellable debuff ICONS,
    -- and Color Custom Borders (the frame's own border copied in the dispel type color).
    if not CludesUI._prebuilding then
        local region = row._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Dispel Border",
            rows = {
                {
                    type = "slider",
                    label = "Debuff Icon Border",
                    min = -1,
                    max = 4,
                    step = 1,
                    tooltip = "Thickness in physical pixels. -1 follows the Debuff Manager's Border setting, 0 hides the dispel color border.",
                    get = SValRow("dispelIconBorderSize", 2),
                    set = SSetRow("dispelIconBorderSize"),
                },
                {
                    type = "toggle",
                    label = "Color Custom Borders",
                    tooltip = "Recolors the frame border in the dispel type color while a debuff of that type is shown.",
                    -- Copies the frame's own border: only over a custom border (CustomBorderOff).
                    disabled = CustomBorderOff,
                    disabledTooltip = CustomBorderOffTip,
                    requireState = "disabled",
                    get = function()
                        return not mod.RF_CompactOnTab(optionState._partyCtx)
                            and SVal("dispelCustomBorder", false)
                    end,
                    set = function(val)
                        if val and CustomBorderOff() then
                            return
                        end
                        SSet("dispelCustomBorder", val)
                    end,
                },
            },
        })
    end

    -- Dispel Colors: five always-active swatches, one per type. Unlike Name Color (a mode picker) each is independently editable, so no onClick/refreshAlpha -- the default click opens the picker.
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "multiSwatch",
        text = "Dispel Colors",
        -- Per-type alpha 0 hides that type's border/overlay entirely.
        swatches = {
            {
                tooltip = "Magic",
                hasAlpha = true,
                getValue = function()
                    local color = SGet("dispelColorMagic")
                    if color then
                        return color.r, color.g, color.b, color.a or 1
                    end
                    return 0.354, 0.396, 0.74, 1
                end,
                setValue = function(red, green, blue, a)
                    SWrite("dispelColorMagic", { r = red, g = green, b = blue, a = a or 1 })
                    ReloadAndUpdate()
                end,
            },
            {
                tooltip = "Curse",
                hasAlpha = true,
                getValue = function()
                    local color = SGet("dispelColorCurse")
                    if color then
                        return color.r, color.g, color.b, color.a or 1
                    end
                    return 0.636, 0.0, 0.64, 1
                end,
                setValue = function(red, green, blue, a)
                    SWrite("dispelColorCurse", { r = red, g = green, b = blue, a = a or 1 })
                    ReloadAndUpdate()
                end,
            },
            {
                tooltip = "Disease",
                hasAlpha = true,
                getValue = function()
                    local color = SGet("dispelColorDisease")
                    if color then
                        return color.r, color.g, color.b, color.a or 1
                    end
                    return 0.71, 0.379, 0.0, 1
                end,
                setValue = function(red, green, blue, a)
                    SWrite("dispelColorDisease", { r = red, g = green, b = blue, a = a or 1 })
                    ReloadAndUpdate()
                end,
            },
            {
                tooltip = "Poison",
                hasAlpha = true,
                getValue = function()
                    local color = SGet("dispelColorPoison")
                    if color then
                        return color.r, color.g, color.b, color.a or 1
                    end
                    return 0.052, 0.586, 0.62, 1
                end,
                setValue = function(red, green, blue, a)
                    SWrite("dispelColorPoison", { r = red, g = green, b = blue, a = a or 1 })
                    ReloadAndUpdate()
                end,
            },
            {
                tooltip = "Bleed",
                hasAlpha = true,
                getValue = function()
                    local color = SGet("dispelColorBleed")
                    if color then
                        return color.r, color.g, color.b, color.a or 1
                    end
                    return 0.75, 0.15, 0.15, 1
                end,
                setValue = function(red, green, blue, a)
                    SWrite("dispelColorBleed", { r = red, g = green, b = blue, a = a or 1 })
                    ReloadAndUpdate()
                end,
            },
        },
    }, {
        type = "toggle",
        text = "Only Show Dispellable",
        -- Inverse of dispelShowAll: ON = only-mine (dispelShowAll=false).
        getValue = function()
            return not SVal("dispelShowAll", true)
        end,
        setValue = function(val)
            SSet("dispelShowAll", not val)
        end,
    })
    cursorY = cursorY - height

    if onSection then
        onSection("dispels", _secY, cursorY)
    end
    _secY = cursorY

    -- Party Frames kit: the stock frame has no Top Name Bar (the whole
    -- section, its sync overlay included, is skipped on the Party page).
    if not mod.RF_OptPartyKit() then
        -------------------------------------------------------------------
        --  TOP NAME BAR
        -------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "TOP NAME BAR", cursorY)
        cursorY = cursorY - height

        local function TNBOff()
            return not SVal("topNameBarEnabled", false)
        end

        -- Enable Top Name Bar | Height. The master toggle HIDES the dependent rows while off; SectionToggleSetValue forces that rebuild.
        row, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Enable Top Name Bar",
            getValue = SValRow("topNameBarEnabled", false),
            setValue = CludesUI.SectionToggleSetValue(function(val)
                SSet("topNameBarEnabled", val)
            end),
        }, TNBOff() and { type = "label", text = "" } or {
            type = "slider",
            text = "Height",
            min = 8,
            max = 40,
            step = 1,
            getValue = SValRow("topNameBarHeight", 20),
            setValue = SSetRow("topNameBarHeight"),
        })
        cursorY = cursorY - height

        if not TNBOff() and not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(row._rightRegion, {
                disabled = function()
                    local key = SGet("borderTexture")
                    return TNBOff()
                        or CludesUI.BlizzStyle.Get("raidframes")
                        or not CludesUI._pixelArtBorders[key]
                end,
                disabledTooltip = function()
                    return TNBOff() and "Enable Top Name Bar" or "Pixels or Pixels Textured Border Style"
                end,
                title = "Top Name Bar Options",
                rows = {
                    {
                        type = "toggle",
                        label = "Divider",
                        tooltip = "Separates the name bar from the health bar.",
                        get = SValRow("topNameBarDivider", false),
                        set = SSetRow("topNameBarDivider"),
                    },
                    {
                        type = "toggle",
                        label = "Match Highlight Colors",
                        tooltip = "The divider follows hover and target colors.",
                        disabled = function()
                            return not SVal("topNameBarDivider", false)
                        end,
                        disabledTooltip = "Requires Divider.",
                        rawTooltip = true,
                        get = SValRow("topNameBarDividerMatchColor", false),
                        set = SSetRow("topNameBarDividerMatchColor"),
                    },
                },
            })
        end

        if not TNBOff() then
            local tnbRow2
            tnbRow2, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Background",
                min = 0,
                max = 100,
                step = 1,
                getValue = SValRow("topNameBarBgOpacity", 80),
                setValue = SSetRow("topNameBarBgOpacity"),
            }, {
                type = "slider",
                text = "Text Size",
                min = 6,
                max = 30,
                step = 1,
                getValue = SValRow("topNameBarTextSize", 11),
                setValue = SSetRow("topNameBarTextSize"),
            })
            cursorY = cursorY - height
            if not CludesUI._prebuilding then
                local region = tnbRow2._leftRegion
                local bgSwatch = CludesUI.BuildColorSwatch(region, tnbRow2:GetFrameLevel() + 3, function()
                    local color = SGet("topNameBarBgColor")
                    if color then
                        return color.r, color.g, color.b, 1
                    end
                    return 17 / 255, 17 / 255, 17 / 255, 1
                end, function(red, green, blue)
                    SWrite("topNameBarBgColor", { r = red, g = green, b = blue })
                    ReloadAndUpdate()
                end, false, 20)
                bgSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                region._lastInline = bgSwatch
            end
            do
                local region = tnbRow2._rightRegion
                CludesUI.BuildInlineCog(region, {
                    title = "Text Offset",
                    rows = {
                        {
                            type = "slider",
                            label = "Offset X",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = SValRow("topNameBarTextOffsetX", 0),
                            set = SSetRow("topNameBarTextOffsetX"),
                        },
                        {
                            type = "slider",
                            label = "Offset Y",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = SValRow("topNameBarTextOffsetY", 0),
                            set = SSetRow("topNameBarTextOffsetY"),
                        },
                    },
                })
            end

            -- Align dropdown plus a custom/class swatch pair that doubles as the color-mode selector (as with Health Text). Defaults to class.
            local tnbRow3
            tnbRow3, height = W:DualRow(hostFrame, cursorY, {
                type = "segmented",
                text = "Alignment & Color",
                values = { center = "Center", left = "Left", right = "Right" },
                order = { "center", "left", "right" },
                getValue = SValRow("topNameBarTextAlign", "center"),
                setValue = SSetRow("topNameBarTextAlign"),
            }, {
                type = "toggle",
                text = "Show on Bottom",
                tooltip = "Places the bar at the bottom of the frame instead of the top.",
                getValue = SValRow("topNameBarBottom", false),
                setValue = SSetRow("topNameBarBottom"),
            })
            cursorY = cursorY - height
            -- Custom rightmost (opens picker), class leftmost. Clicking switches topNameBarTextColorMode; the inactive one dims. Custom is added FIRST so it sits next to the dropdown.
            if not CludesUI._prebuilding then
                local region = tnbRow3._leftRegion
                local function AddTNBSwatch(getColor, setColor, mode, opensPicker, tooltip)
                    local sw = CludesUI.BuildColorSwatch(
                        region,
                        tnbRow3:GetFrameLevel() + 3,
                        getColor,
                        setColor,
                        false,
                        20
                    )
                    sw:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                    region._lastInline = sw
                    sw._eabOrigClick = sw:GetScript("OnClick")
                    sw:SetScript("OnClick", function(self)
                        if SVal("topNameBarTextColorMode", "class") ~= mode then
                            SSet("topNameBarTextColorMode", mode)
                            CludesUI:RefreshPage()
                            return
                        end
                        if opensPicker and self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end)
                    if tooltip then
                        sw:HookScript("OnEnter", function()
                            CludesUI.ShowWidgetTooltip(sw, tooltip)
                        end)
                        sw:HookScript("OnLeave", function()
                            CludesUI.HideWidgetTooltip()
                        end)
                    end
                    local function vis()
                        sw:SetAlpha(SVal("topNameBarTextColorMode", "class") == mode and 1 or 0.3)
                    end
                    CludesUI.RegisterWidgetRefresh(vis)
                    vis()
                end
                -- Custom (rightmost): editable, opens the picker when active.
                AddTNBSwatch(function()
                    local color = SGet("topNameBarTextColor")
                    if color then
                        return color.r, color.g, color.b, 1
                    end
                    return 1, 1, 1, 1
                end, function(red, green, blue)
                    SWrite("topNameBarTextColor", { r = red, g = green, b = blue })
                    ReloadAndUpdate()
                end, "custom", true, "Custom Color")
                AddTNBSwatch(function()
                    local _, classTok = UnitClass("player")
                    if classTok and RAID_CLASS_COLORS[classTok] then
                        local classColor = RAID_CLASS_COLORS[classTok]
                        return classColor.r, classColor.g, classColor.b, 1
                    end
                    return 1, 1, 1, 1
                end, function() end, "class", false, "Class Color")
            end

            -- Attach Role Icons: the role icon sits on this bar, placed by the arrow cog
            local tnbRow4
            tnbRow4, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Attach Role Icons",
                tooltip = "Places role icons on the Top Name Bar, in the same spot on every frame whether or not it shows a power bar.",
                getValue = SValRow("roleIconOnNameBar", false),
                setValue = function(val)
                    SSet("roleIconOnNameBar", val)
                    CludesUI:RefreshPage()
                end,
            }, CludesUI.BlankRowCfg())
            cursorY = cursorY - height
            if not CludesUI._prebuilding then
                CludesUI.BuildInlineCog(tnbRow4._leftRegion, {
                    title = "Role Icon Position",
                    disabled = function()
                        return not SVal("roleIconOnNameBar", false)
                    end,
                    disabledTooltip = "Attach Role Icons",
                    rows = {
                        {
                            type = "dropdown",
                            label = "Position",
                            values = CludesUI.POSITION_GRID_VALUES,
                            order = CludesUI.POSITION_GRID_ORDER,
                            get = SValRow("roleNameBarPosition", "left"),
                            set = SSetRow("roleNameBarPosition"),
                        },
                        {
                            type = "slider",
                            label = "Offset X",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = SValRow("roleNameBarOffsetX", 0),
                            set = SSetRow("roleNameBarOffsetX"),
                        },
                        {
                            type = "slider",
                            label = "Offset Y",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = SValRow("roleNameBarOffsetY", 0),
                            set = SSetRow("roleNameBarOffsetY"),
                        },
                    },
                })
            end
        end -- close Top Name Bar hidden-while-disabled gate

        if onSection then
            onSection("topNameBar", _secY, cursorY)
        end
    end -- not Party Frames kit
    _secY = cursorY

    -------------------------------------------------------------------
    --  FRIENDLY BOSS FRAMES (raid tab only)
    -------------------------------------------------------------------
    if not optionState._partyCtx then
        _, height = W:SectionHeader(hostFrame, "FRIENDLY BOSS FRAMES", cursorY)
        cursorY = cursorY - height

        local function FBSet()
            local profile = saved.profile
            if not profile.friendlyBoss then
                profile.friendlyBoss = { display = "never", position = "right" }
            end
            return profile.friendlyBoss
        end
        -- Everything below the display dropdown is inert while "Never".
        local function FBEnabled()
            return (FBSet().display or "never") ~= "never"
        end
        local FB_DISABLED_TIP = "This option requires Add Friendly Boss Group to be set to Healers or Always."

        row, height = W:DualRow(hostFrame, cursorY, {
            type = "segmented",
            text = "Add Friendly Boss Group",
            values = { never = "Never", healers = "Healers", always = "Always" },
            order = { "never", "healers", "always" },
            getValue = function()
                return FBSet().display or "never"
            end,
            -- Rows below are HIDDEN while Never; only the Never <-> enabled flip forces the full rebuild.
            setValue = CludesUI.DependentSetValue(FBEnabled, function(val)
                FBSet().display = val
                mod.FB_Apply()
                CludesUI:RefreshPage()
            end),
        }, (not FBEnabled()) and { type = "label", text = "" } or {
            type = "dropdown",
            text = "Position",
            values = { left = "Before First Group", right = "After Last Group", free = "Free Move" },
            order = { "left", "right", "free" },
            getValue = function()
                return FBSet().position or "right"
            end,
            setValue = function(val)
                FBSet().position = val
                if val ~= "free" then
                    mod.FB_SetMoverShown(false)
                end
                mod.FB_Apply()
                CludesUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height
        -- Inline cog on the display dropdown: Show in Dungeons (opt-in;
        -- the group gate is raid-only without it). Dimmed while Never,
        -- like every row below the dropdown.
        if not CludesUI._prebuilding then
            local region = row._leftRegion
            CludesUI.BuildInlineCog(region, {
                disabled = function()
                    return not FBEnabled()
                end,
                disabledTooltip = FB_DISABLED_TIP,
                title = "Friendly Boss Group",
                rows = {
                    {
                        type = "toggle",
                        label = "Show in Dungeons",
                        get = function()
                            return FBSet().showInDungeons == true
                        end,
                        set = function(val)
                            -- Absent = off (additive key); FB_Apply re-registers
                            -- the secure group driver, so the flip is live.
                            FBSet().showInDungeons = val and true or nil
                            mod.FB_Apply()
                        end,
                    },
                },
            })
        end
        if FBEnabled() then
            -- Free Move Position: label left, Move Frames button right (Free Move only). Right slot: Boss Health Color.
            row, height = W:DualRow(
                hostFrame,
                cursorY,
                { type = "label", text = "Free Move Position" },
                { type = "label", text = "Boss Health Color" }
            )
            cursorY = cursorY - height
            do
                local button = mod.RF_OptMoveFramesButton(row, row._leftRegion, {
                    isShown = mod.FB_IsMoverShown,
                    setShown = mod.FB_SetMoverShown,
                    allowed = function()
                        return FBEnabled() and (FBSet().position == "free") and not InCombatLockdown()
                    end,
                    enabled = FBEnabled,
                    enabledTip = FB_DISABLED_TIP,
                })
                CludesUI.BuildInlineCog(row, {
                    anchorTo = button,
                    chain = false,
                    disabled = function()
                        return not (FBEnabled() and FBSet().position == "free")
                    end,
                    disabledTooltip = "This option requires Position to be set to Free Move",
                    title = "Free Move Options",
                    rows = {
                        {
                            type = "toggle",
                            label = "Horizontal Frames",
                            get = function()
                                return FBSet().freeHorizontal == true
                            end,
                            set = function(val)
                                FBSet().freeHorizontal = val
                                mod.FB_Apply()
                                -- Resize/reposition the drag overlay if it is up.
                                if mod.FB_IsMoverShown() then
                                    mod.FB_SetMoverShown(true)
                                end
                            end,
                        },
                    },
                })
            end
            if not CludesUI._prebuilding then
                local region = row._rightRegion
                local colorSwatch = CludesUI.BuildColorSwatch(region, row:GetFrameLevel() + 3, function()
                    local color = FBSet().healthColor
                    if color then
                        return color.r, color.g, color.b, 1
                    end
                    return 23 / 255, 172 / 255, 49 / 255, 1
                end, function(red, green, blue)
                    FBSet().healthColor = { r = red, g = green, b = blue }
                    mod.FB_Apply()
                end, false, 20)
                colorSwatch:SetPoint("RIGHT", region, "RIGHT", -20, 0)
                region._lastInline = colorSwatch
                -- Dimming alone leaves the swatch clickable; this blocks it.
                local swatchBlock = CludesUI.NewSwatchBlocker(colorSwatch)
                swatchBlock:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(colorSwatch, FB_DISABLED_TIP)
                end)
                swatchBlock:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local function UpdateFBSwatch()
                    local on = FBEnabled()
                    colorSwatch:SetAlpha(on and 1 or 0.3)
                    swatchBlock:SetShown(not on)
                    if region._label then
                        region._label:SetAlpha(on and 1 or 0.3)
                    end
                end
                CludesUI.RegisterWidgetRefresh(UpdateFBSwatch)
                UpdateFBSwatch()
            end

            -- Row 3: size offset on top of the shared raid frame size
            row, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Extra Width",
                min = -50,
                max = 100,
                step = 1,
                tooltip = "Widens or narrows the boss frames relative to the raid frame size.",
                getValue = function()
                    return FBSet().extraWidth or 0
                end,
                setValue = function(val)
                    FBSet().extraWidth = val
                    mod.FB_Apply()
                    if mod.FB_IsMoverShown() then
                        mod.FB_SetMoverShown(true)
                    end
                end,
            }, {
                type = "slider",
                text = "Extra Height",
                min = -50,
                max = 100,
                step = 1,
                tooltip = "Makes the boss frames taller or shorter relative to the raid frame size.",
                getValue = function()
                    return FBSet().extraHeight or 0
                end,
                setValue = function(val)
                    FBSet().extraHeight = val
                    mod.FB_Apply()
                    if mod.FB_IsMoverShown() then
                        mod.FB_SetMoverShown(true)
                    end
                end,
            })
            cursorY = cursorY - height
        end -- close Friendly Boss Frames hidden-while-disabled gate

        if onSection then
            onSection("friendlyBossFrames", _secY, cursorY)
        end
        _secY = cursorY

        -------------------------------------------------------------------
        --  EXTRA FRAMES (raid tab only)
        -------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "EXTRA FRAMES", cursorY)
        cursorY = cursorY - height

        local function ExtraFramesCfg()
            local profile = saved.profile
            if not profile.extraFrames then
                profile.extraFrames = { showTanks = false, position = "right", players = {} }
            end
            return profile.extraFrames
        end
        -- Position settings only matter once something can feed the group: the tanks toggle or a bound hotkey.
        local function XFConfigured()
            return ExtraFramesCfg().showTanks == true or (CludesUIDB and CludesUIDB.extraFramesKey) ~= nil
        end
        -- Row 1: Add to Extra Group Hotkey (capture) | Show Tanks toggle
        row, height = W:DualRow(hostFrame, cursorY, { type = "label", text = "Add to Extra Group Hotkey" }, {
            type = "toggle",
            text = "Show Tanks in Extra Group",
            tooltip = "Automatically duplicates the raid's tanks into the Extra Frames group. Shares the frame cap with hotkey picks.",
            getValue = function()
                return ExtraFramesCfg().showTanks == true
            end,
            -- Rows below are HIDDEN while unconfigured (no tanks toggle AND no hotkey); only a configured-state flip forces the rebuild.
            setValue = CludesUI.DependentSetValue(XFConfigured, function(val)
                ExtraFramesCfg().showTanks = val
                mod.XF_Apply()
                -- Feature may have just gone dark; the mover can't stay up.
                if not XFConfigured() then
                    mod.XF_SetMoverShown(false)
                end
                CludesUI:RefreshPage()
            end),
        })
        cursorY = cursorY - height
        -- Inline cog on Show Tanks: tank auto-include options.
        if not CludesUI._prebuilding then
            local region = row._rightRegion
            CludesUI.BuildInlineCog(region, {
                title = "Show Tanks Options",
                rows = {
                    {
                        type = "toggle",
                        label = "Exclude Myself",
                        tooltip = "Skips your own frame when Show Tanks duplicates the raid's tanks. Hotkey picks can still add you.",
                        get = function()
                            return ExtraFramesCfg().excludeSelfTank == true
                        end,
                        set = function(val)
                            ExtraFramesCfg().excludeSelfTank = val or nil
                            mod.XF_Apply()
                        end,
                    },
                },
            })
        end
        if not CludesUI._prebuilding then
            local region = row._leftRegion
            local kbBtn, refresh = CludesUI.BuildKeybindButton(row, {
                w = 140,
                h = 26,
                font = 13,
                level = 5,
                tooltip = "Left-click to set a keybind. Right-click to unbind.\nPress the key while hovering a raid frame to add or remove that player from the Extra Frames group.",
                get = function()
                    return CludesUIDB and CludesUIDB.extraFramesKey
                end,
                set = function(key)
                    if not CludesUIDB then
                        CludesUIDB = {}
                    end
                    local bindBtn = _G["ERFExtraFramesBindBtn"]
                    if bindBtn then
                        -- Override bindings cannot change in combat: keep the old key.
                        if InCombatLockdown() then
                            return
                        end
                        if key or CludesUIDB.extraFramesKey then
                            ClearOverrideBindings(bindBtn)
                        end
                        if key then
                            SetOverrideBindingClick(bindBtn, true, key, "ERFExtraFramesBindBtn")
                        end
                    end
                    local wasConfigured = XFConfigured()
                    CludesUIDB.extraFramesKey = key
                    -- The mover can't stay up once the feature goes dark.
                    if not XFConfigured() then
                        mod.XF_SetMoverShown(false)
                    end
                    -- Hidden rows below: a configured-state flip needs the full rebuild, not the fast refresh.
                    if XFConfigured() ~= wasConfigured then
                        CludesUI:RefreshPage(true)
                    else
                        CludesUI:RefreshPage()
                    end
                end,
            })
            CludesUI.PanelPP.Point(kbBtn, "RIGHT", region, "RIGHT", -20, 0)
            CludesUI.RegisterWidgetRefresh(refresh)
        end

        -- Rows 2-4 are HIDDEN while unconfigured (no tanks toggle AND no hotkey); the triggers above rebuild when that state flips.
        if XFConfigured() then
            -- Row 2: Position | Free Move Position (Move Frames)
            row, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Position",
                values = { left = "Before First Group", right = "After Last Group", free = "Free Move" },
                order = { "left", "right", "free" },
                getValue = function()
                    return ExtraFramesCfg().position or "right"
                end,
                setValue = function(val)
                    ExtraFramesCfg().position = val
                    if val ~= "free" then
                        mod.XF_SetMoverShown(false)
                    end
                    mod.XF_Apply()
                    -- Full rebuild: the Grow/Wrap Direction row only exists while the position is Free Move.
                    CludesUI:RefreshPage(true)
                end,
            }, { type = "label", text = "Free Move Position" })
            cursorY = cursorY - height
            mod.RF_OptMoveFramesButton(row, row._rightRegion, {
                isShown = mod.XF_IsMoverShown,
                setShown = mod.XF_SetMoverShown,
                allowed = function()
                    return XFConfigured() and (ExtraFramesCfg().position == "free") and not InCombatLockdown()
                end,
            })

            -- Free Move ONLY (hidden otherwise; Position's setValue forces a rebuild): growth axes of the free-floating grid, with Wrap After in an inline cog on Wrap Direction.
            -- Attached positions need none of this -- they stack group-sized runs of 5 along the raid's own growth settings, like extra raid groups.
            -- Grow Direction defaults from the legacy freeHorizontal key, so existing layouts read back unchanged.
            if ExtraFramesCfg().position == "free" then
                local function ExtraGrowDir()
                    local set = ExtraFramesCfg()
                    return set.growDirection or (set.freeHorizontal and "RIGHT" or "DOWN")
                end
                local function XFReapply()
                    mod.XF_Apply()
                    if mod.XF_IsMoverShown() then
                        mod.XF_SetMoverShown(true)
                    end
                end

                -- The wrap dropdown only offers the two directions perpendicular to the primary run, so a grow change forces a full rebuild to swap its value set.
                local xfHoriz = (ExtraGrowDir() == "RIGHT" or ExtraGrowDir() == "LEFT")
                row, height = W:DualRow(hostFrame, cursorY, {
                    type = "dropdown",
                    text = "Grow Direction",
                    tooltip = "Direction the frames are laid out.",
                    values = { DOWN = "Down", UP = "Up", RIGHT = "Right", LEFT = "Left" },
                    order = { "DOWN", "UP", "RIGHT", "LEFT" },
                    getValue = ExtraGrowDir,
                    setValue = function(val)
                        local set = ExtraFramesCfg()
                        set.growDirection = val
                        -- Keep the legacy key coherent for exports/older reads.
                        set.freeHorizontal = (val == "RIGHT" or val == "LEFT")
                        XFReapply()
                        CludesUI:RefreshPage(true)
                    end,
                }, {
                    type = "dropdown",
                    text = "Wrap Direction",
                    tooltip = "Direction each new row or column stacks. Set Wrap After in the cog to enable wrapping.",
                    values = xfHoriz and { DOWN = "Down", UP = "Up" } or { RIGHT = "Right", LEFT = "Left" },
                    order = xfHoriz and { "DOWN", "UP" } or { "RIGHT", "LEFT" },
                    getValue = function()
                        local wd = ExtraFramesCfg().wrapDirection
                        if ExtraGrowDir() == "RIGHT" or ExtraGrowDir() == "LEFT" then
                            return (wd == "UP" or wd == "DOWN") and wd or "DOWN"
                        end
                        return (wd == "LEFT" or wd == "RIGHT") and wd or "RIGHT"
                    end,
                    setValue = function(val)
                        ExtraFramesCfg().wrapDirection = val
                        XFReapply()
                    end,
                })
                cursorY = cursorY - height
                do
                    local region = row._rightRegion
                    CludesUI.BuildInlineCog(region, {
                        title = "Row Wrapping",
                        rows = {
                            {
                                type = "slider",
                                label = "Wrap After",
                                min = 0,
                                max = 20,
                                step = 1,
                                get = function()
                                    return ExtraFramesCfg().wrapAfter or 0
                                end,
                                set = function(val)
                                    ExtraFramesCfg().wrapAfter = val
                                    XFReapply()
                                end,
                            },
                        },
                    })
                end
            end -- Free Move only row

            -- Row 4: size offset on top of the shared raid frame size
            row, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Extra Width",
                min = -50,
                max = 100,
                step = 1,
                tooltip = "Widens or narrows the extra frames relative to the raid frame size.",
                getValue = function()
                    return ExtraFramesCfg().extraWidth or 0
                end,
                setValue = function(val)
                    ExtraFramesCfg().extraWidth = val
                    mod.XF_Apply()
                    if mod.XF_IsMoverShown() then
                        mod.XF_SetMoverShown(true)
                    end
                end,
            }, {
                type = "slider",
                text = "Extra Height",
                min = -50,
                max = 100,
                step = 1,
                tooltip = "Makes the extra frames taller or shorter relative to the raid frame size.",
                getValue = function()
                    return ExtraFramesCfg().extraHeight or 0
                end,
                setValue = function(val)
                    ExtraFramesCfg().extraHeight = val
                    mod.XF_Apply()
                    if mod.XF_IsMoverShown() then
                        mod.XF_SetMoverShown(true)
                    end
                end,
            })
            cursorY = cursorY - height
            -- Inline cog on Extra Width: Auto Resize Indicators (default on;
            -- off keeps indicators/auras at the real frames' base scale
            -- regardless of the extra frames' custom size).
            do
                local region = row._leftRegion
                CludesUI.BuildInlineCog(region, {
                    title = "Extra Frame Size",
                    rows = {
                        {
                            type = "toggle",
                            label = "Auto Resize Indicators",
                            get = function()
                                return ExtraFramesCfg().autoResizeIndicators ~= false
                            end,
                            set = function(val)
                                -- nil = on (additive key, zero migration); false = off.
                                if val then
                                    ExtraFramesCfg().autoResizeIndicators = nil
                                else
                                    ExtraFramesCfg().autoResizeIndicators = false
                                end
                                mod.XF_Apply()
                            end,
                        },
                    },
                })
            end
        end -- close Extra Frames hidden-while-unconfigured gate

        if onSection then
            onSection("extraFrames", _secY, cursorY)
        end
        _secY = cursorY
    end

    -------------------------------------------------------------------
    --  PET FRAMES (party and raid tabs, each with its own switch)
    -------------------------------------------------------------------
    -- Not a synced section: no onSection call, so the party tab never overlays it.
    do
        _, height = W:SectionHeader(hostFrame, "PET FRAMES", cursorY)
        cursorY = cursorY - height

        local function PFSet()
            local profile = saved.profile
            if not profile.petFrames then
                profile.petFrames = { position = "right" }
            end
            return profile.petFrames
        end
        local tabKey = optionState._partyCtx and "party" or "raid"
        local onParty = tabKey == "party"
        -- This tab's Position, Extra Width/Height and Free Move spot (it reads the shared ones
        -- until it sets its own).
        local function PFTab()
            PFSet()
            return mod.PF_View(tabKey)
        end
        local function PFEnabled()
            return PFSet()[tabKey] == true
        end
        -- Only a preview already on screen: starting one here would show the raid preview on the
        -- party tab, or a preview with Preview Mode set to None.
        local function RedrawPetPreview()
            if mod.previewActive() then
                mod.ShowPreview()
            end
            if mod.partyPvActive() then
                mod.ShowPartyPreview()
            end
        end
        -- The last row holds what the chosen position needs: the Move Frames button (Free Move)
        -- or Pet Side (Beside Owner). The other positions have none.
        local function PFPlacement()
            local p = PFTab().position
            if p == "free" or (p == "owner" and onParty) then
                return p
            end
        end
        local BLANK = CludesUI.BlankRowCfg

        row, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Pets",
            tooltip = "Adds your group's pets beside these frames, with their health, name, range and click-casting.",
            getValue = function()
                return PFEnabled()
            end,
            -- Rows below are HIDDEN while off; only the on/off flip forces the rebuild.
            setValue = CludesUI.DependentSetValue(PFEnabled, function(val)
                PFSet()[tabKey] = val and true or false
                mod.PF_Apply()
                -- The Move Frames button goes with the page rebuild; the overlay can't stay up.
                if not val and mod.PF_IsMoverShown(tabKey) then
                    mod.PF_SetMoverShown(false)
                end
                RedrawPetPreview()
                CludesUI:RefreshPage()
            end),
        }, (not PFEnabled()) and BLANK() or {
            type = "dropdown",
            text = "Position",
            -- Beside Owner (a pet beside each party frame) is party only.
            values = onParty and {
                left = "Before First Group",
                right = "After Last Group",
                free = "Free Move",
                owner = "Beside Owner",
            } or { left = "Before First Group", right = "After Last Group", free = "Free Move" },
            order = onParty and { "left", "right", "free", "owner" } or { "left", "right", "free" },
            getValue = function()
                return PFTab().position or "right"
            end,
            setValue = function(val)
                local before = PFPlacement()
                PFTab().position = val
                if val ~= "free" and mod.PF_IsMoverShown(tabKey) then
                    mod.PF_SetMoverShown(false)
                end
                mod.PF_Apply()
                RedrawPetPreview()
                -- A new last row needs the full rebuild.
                CludesUI:RefreshPage(PFPlacement() ~= before)
            end,
        })
        cursorY = cursorY - height

        if PFEnabled() then
            row, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Extra Width",
                min = -50,
                max = 100,
                step = 1,
                tooltip = "Widens or narrows the pet frames relative to the frame size.",
                getValue = function()
                    return PFTab().extraWidth or 0
                end,
                setValue = function(val)
                    PFTab().extraWidth = val
                    mod.PF_Apply()
                    mod.PF_PlaceMover(tabKey)
                    RedrawPetPreview()
                end,
            }, {
                type = "slider",
                text = "Extra Height",
                min = -50,
                max = 100,
                step = 1,
                tooltip = "Makes the pet frames taller or shorter relative to the frame size.",
                getValue = function()
                    return PFTab().extraHeight or 0
                end,
                setValue = function(val)
                    PFTab().extraHeight = val
                    mod.PF_Apply()
                    mod.PF_PlaceMover(tabKey)
                    RedrawPetPreview()
                end,
            })
            cursorY = cursorY - height

            local placement = PFPlacement()
            if placement == "free" then
                row, height = W:DualRow(hostFrame, cursorY, { type = "label", text = "Free Move Position" }, {
                    type = "dropdown",
                    text = "Growth Direction",
                    tooltip = "Match Frames grows the pets the same way as the frames.",
                    values = {
                        frames = "Match Frames",
                        DOWN = "Down",
                        UP = "Up",
                        RIGHT = "Right",
                        LEFT = "Left",
                    },
                    order = { "frames", "DOWN", "UP", "RIGHT", "LEFT" },
                    getValue = function()
                        return PFTab().freeGrowth or "frames"
                    end,
                    setValue = function(val)
                        PFTab().freeGrowth = (val ~= "frames") and val or nil
                        mod.PF_Apply()
                        mod.PF_PlaceMover(tabKey)
                    end,
                })
                cursorY = cursorY - height
                mod.RF_OptMoveFramesButton(row, row._leftRegion, {
                    isShown = function()
                        return mod.PF_IsMoverShown(tabKey)
                    end,
                    setShown = function(show)
                        mod.PF_SetMoverShown(show, tabKey)
                    end,
                    allowed = function()
                        return PFTab().position == "free" and not InCombatLockdown()
                    end,
                })
            elseif placement == "owner" then
                -- Across the party frames' stack only: beside stacked frames, above or below
                -- horizontal ones (the other sides hold the next frame).
                row, height = W:DualRow(hostFrame, cursorY, {
                    type = "dropdown",
                    text = "Pet Side",
                    values = { right = "Right", left = "Left", above = "Above", below = "Below" },
                    order = { "right", "left", "above", "below" },
                    itemDisabled = function(val)
                        local across = (val == "above" or val == "below")
                        return across ~= (saved.profile.partyHorizontal and true or false)
                    end,
                    itemDisabledTooltip = function(val)
                        if val == "above" or val == "below" then
                            return "Horizontal Frames"
                        end
                        return "This option requires Horizontal Frames to be disabled"
                    end,
                    getValue = function()
                        return mod.PF_OwnerSide()
                    end,
                    setValue = function(val)
                        PFSet().ownerSide = val
                        mod.PF_Apply()
                        RedrawPetPreview()
                    end,
                }, BLANK())
                cursorY = cursorY - height
            end
        end
        _secY = cursorY
    end

    -------------------------------------------------------------------
    --  RANGE & TOOLTIP
    -------------------------------------------------------------------
    heading, height = W:SectionHeader(hostFrame, "EXTRAS", cursorY)
    cursorY = cursorY - height
    -- The Healer Mana Display's Move in Unlock Mode button, on the raid tab
    -- only: both tabs build this section and the display's settings are
    -- shared. Greyed while the mode is None, when the display has no mover.
    if not optionState._partyCtx then
        CludesUI.BuildSectionUnlockJump(heading, {
            key = "RF_HealerMana",
            disabled = function()
                local hm = saved.profile.healerMana
                return not hm or (hm.mode or "none") == "none"
            end,
            disabledTooltip = "Healer Mana Display",
        })
    end

    -- OOR Alpha | Show Raid Frames Tooltip (dropdown + cog). The dropdown is a pure VIEW over the legacy keys: with tooltipMode unset it derives the shown option from the showTooltip toggle plus the global "show in combat" flag, so behavior only changes once the user picks.
    -- Same derive as the runtime ns._ResolveTooltipMode.
    local function CurTooltipMode()
        local m = SVal("tooltipMode", nil)
        if m ~= nil then
            return m
        end
        if SVal("showTooltip", true) == false then
            return "never"
        end
        if CludesUIDB and CludesUIDB.showUnitTooltipsInCombat then
            return "always"
        end
        return "outOfCombat"
    end
    row, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Out of Range Alpha",
        min = 10,
        max = 100,
        step = 1,
        getValue = function()
            return floor((SVal("oorAlpha", 0.4)) * 100)
        end,
        setValue = function(val)
            SSet("oorAlpha", val / 100)
            -- SetAlphaFromBoolean bakes the value in at call time, so already-OOR units keep the old alpha until a range re-eval.
            -- Seed all buttons so the slider takes effect now.
            if mod._RangeSeedAll then
                mod._RangeSeedAll()
            end
        end,
    }, {
        type = "dropdown",
        text = "Show Raid & Party Frames Tooltip",
        tooltip = "Controls when the tooltip appears as you hover a raid or party frame",
        values = {
            always = "Always",
            outOfCombat = "Out of Combat",
            outOfBossCombat = "Out of Boss Combat",
            never = "Never",
        },
        order = { "always", "outOfCombat", "outOfBossCombat", "never" },
        getValue = function()
            return CurTooltipMode()
        end,
        setValue = SSetRow("tooltipMode"),
    })
    cursorY = cursorY - height
    -- Cog: buff/HoT aura-icon tooltips (Buff Manager), hidden by default and opt-in here. This is the ONLY gate on the aura tip: the dropdown's tooltip mode governs the UNIT tooltip and must NOT veto an aura tip enabled here (see ns.RaidFrameTooltipAllowed).
    if not CludesUI._prebuilding then
        local region = row._rightRegion
        local tipRows
        -- 4-state on the same key: true/nil=hidden, false=shown, "cursor"=shown at cursor, "combat"=hidden during combat.
        tipRows = {
            {
                type = "dropdown",
                label = "Buff Tooltips",
                tooltip = "Tooltip behavior when hovering a buff/HoT icon on a raid or party frame.",
                values = {
                    hidden = "Hidden",
                    shown = "Shown",
                    cursor = "Shown At Cursor",
                    combat = "Hidden In Combat",
                },
                order = { "hidden", "shown", "cursor", "combat" },
                get = function()
                    local val = SVal("buffHideTooltips", true)
                    if val == false then
                        return "shown"
                    end
                    if val == "cursor" or val == "combat" then
                        return val
                    end
                    return "hidden"
                end,
                set = function(keyName)
                    local val = keyName
                    if keyName == "shown" then
                        val = false
                    elseif keyName == "hidden" then
                        val = true
                    end
                    SSet("buffHideTooltips", val)
                    if mod.ReloadFrames then
                        mod.ReloadFrames()
                    end
                end,
            },
        }
        CludesUI.BuildInlineCog(region, {
            title = "Tooltip Settings",
            rows = tipRows,
        })
    end

    -- Healer Mana Display: one mana-percent text row per group healer,
    -- riding the existing power-event plumbing (see ns.HM_Rebuild).
    local function HealerManaCfg()
        local profile = saved.profile
        if not profile.healerMana then
            profile.healerMana = { mode = "none" }
        end
        return profile.healerMana
    end
    local function RebuildHealthMarkers()
        if mod.HM_Rebuild then
            mod.HM_Rebuild()
        end
    end
    local hmRow
    hmRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Healer Mana Display",
        tooltip = "Shows a mana percentage row for every healer in your group as its own movable text display. Position it in Layout Mode.",
        values = { none = "None", party = "In Party", raid = "In Raid", both = "In Party & Raid" },
        order = { "none", "party", "raid", "both" },
        getValue = function()
            local m = HealerManaCfg().mode
            return (m == "party" or m == "raid" or m == "both") and m or "none"
        end,
        setValue = function(val)
            HealerManaCfg().mode = val
            -- Re-syncs healer power-event registrations and rebuilds.
            if mod.UpdatePowerEventRegistration then
                mod.UpdatePowerEventRegistration()
            end
            -- Re-register unlock elements: the mover's isHidden verdict
            -- just changed, and re-registration applies it live to an
            -- open unlock session (both directions).
            if mod._RFRegisterUnlock then
                mod._RFRegisterUnlock()
            end
        end,
    }, {
        type = "multiSwatch",
        text = "Healer Mana Text Color",
        swatches = {
            {
                tooltip = "Custom Colored",
                getValue = function()
                    local color = HealerManaCfg().color
                    return (color and color.r) or 1, (color and color.g) or 1, (color and color.b) or 1, 1
                end,
                setValue = function(red, green, blue)
                    local hm = HealerManaCfg()
                    hm.color = { r = red, g = green, b = blue }
                    hm.colorMode = "custom"
                    RebuildHealthMarkers()
                end,
                onClick = function(self)
                    local hm = HealerManaCfg()
                    if hm.colorMode == "power" then
                        hm.colorMode = "custom"
                        RebuildHealthMarkers()
                        CludesUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then
                        self._eabOrigClick(self)
                    end
                end,
                refreshAlpha = function()
                    return (HealerManaCfg().colorMode == "power") and 0.3 or 1
                end,
            },
            {
                tooltip = "Power Colored",
                getValue = function()
                    -- Same resolver chain as the runtime rows: the global
                    -- custom power color first, stock mana color after.
                    local details = CludesUI.GetPowerColor("MANA")
                    if details then
                        return details.r, details.g, details.b, 1
                    end
                    local mc = PowerBarColor and PowerBarColor.MANA
                    if mc then
                        return mc.r, mc.g, mc.b, 1
                    end
                    return 0.3, 0.5, 0.85, 1
                end,
                setValue = function() end,
                onClick = function()
                    local hm = HealerManaCfg()
                    hm.colorMode = "power"
                    RebuildHealthMarkers()
                    CludesUI:RefreshPage()
                end,
                refreshAlpha = function()
                    return (HealerManaCfg().colorMode == "power") and 1 or 0.3
                end,
            },
        },
    })
    cursorY = cursorY - height
    -- Inline cog (text settings) + preview eyeball on the toggle
    if not CludesUI._prebuilding then
        local region = hmRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Healer Mana Display",
            rows = {
                {
                    type = "slider",
                    label = "Text Size",
                    min = 8,
                    max = 24,
                    step = 1,
                    get = function()
                        return HealerManaCfg().textSize or 12
                    end,
                    set = function(val)
                        HealerManaCfg().textSize = val
                        RebuildHealthMarkers()
                    end,
                },
                {
                    type = "slider",
                    label = "Spacing",
                    min = 0,
                    max = 12,
                    step = 1,
                    tooltip = "Vertical space between rows.",
                    get = function()
                        return HealerManaCfg().spacing or 2
                    end,
                    set = function(val)
                        HealerManaCfg().spacing = val
                        RebuildHealthMarkers()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Text Align",
                    values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                    order = { "LEFT", "CENTER", "RIGHT" },
                    get = function()
                        local a = HealerManaCfg().align
                        return (a == "RIGHT" or a == "CENTER") and a or "LEFT"
                    end,
                    set = function(keyName)
                        HealerManaCfg().align = keyName
                        RebuildHealthMarkers()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Text Growth",
                    tooltip = "Which way the rows stack as healers are added.",
                    values = { DOWN = "Down", UP = "Up" },
                    order = { "DOWN", "UP" },
                    get = function()
                        return HealerManaCfg().growth == "UP" and "UP" or "DOWN"
                    end,
                    set = function(keyName)
                        HealerManaCfg().growth = keyName
                        RebuildHealthMarkers()
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Names in Raid",
                    tooltip = "Shows each healer's name before the number while in a raid. In a party the display always shows numbers only.",
                    get = function()
                        return HealerManaCfg().showNames ~= false
                    end,
                    -- if/else, NOT `v and nil or false`: that expression is
                    -- ALWAYS false (the nil arm falls through the or).
                    set = function(val)
                        if val then
                            HealerManaCfg().showNames = nil
                        else
                            HealerManaCfg().showNames = false
                        end
                        RebuildHealthMarkers()
                    end,
                },
                {
                    type = "toggle",
                    label = "Class Colored Names",
                    get = function()
                        return HealerManaCfg().classNames ~= false
                    end,
                    set = function(val)
                        if val then
                            HealerManaCfg().classNames = nil
                        else
                            HealerManaCfg().classNames = false
                        end
                        RebuildHealthMarkers()
                    end,
                },
            },
        })

        local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON
        local eyeButton = CreateFrame("Button", nil, region)
        eyeButton:SetSize(26, 26)
        eyeButton:SetPoint("RIGHT", region._lastInline, "LEFT", -4, 0)
        region._lastInline = eyeButton
        eyeButton:SetFrameLevel(region:GetFrameLevel() + 5)
        CludesUI.SetGlyphAlpha(eyeButton, 0.4)
        local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        eyeTex:SetTexture(EYE_VISIBLE)
        local function RefreshHMEye()
            eyeTex:SetTexture(mod._hmPreview and EYE_INVISIBLE or EYE_VISIBLE)
        end
        EYE.refreshHMEye = RefreshHMEye
        eyeButton:SetScript("OnClick", function()
            if mod.HM_SetPreview then
                mod.HM_SetPreview(not mod._hmPreview)
            end
            RefreshHMEye()
        end)
        eyeButton:SetScript("OnEnter", function(s)
            CludesUI.SetGlyphAlpha(s, 0.7)
            CludesUI.ShowWidgetTooltip(
                s,
                mod._hmPreview and "Hide the preview" or "Preview the display at its position"
            )
        end)
        eyeButton:SetScript("OnLeave", function(s)
            CludesUI.SetGlyphAlpha(s, 0.4)
            CludesUI.HideWidgetTooltip()
        end)
        if not hmEyeOnHide then
            hmEyeOnHide = true
            CludesUI:RegisterOnHide(StopHMPreviewOnHide)
        end
    end

    -- Player Group Label: raid tab only, party has no groups.
    if not optionState._partyCtx then
        local function PGS()
            local profile = saved.profile
            if not profile.playerGroup then
                profile.playerGroup = {}
            end
            return profile.playerGroup
        end
        local function ApplyPowerGlow()
            if mod.PG_Apply then
                mod.PG_Apply()
            end
        end
        local function PGOff()
            return not PGS().enabled
        end
        local function PGModeSwatches(modeKey, colorKey)
            local function Mode()
                return PGS()[modeKey] or "accent"
            end
            local function Pick(m)
                return function()
                    PGS()[modeKey] = m
                    ApplyPowerGlow()
                    CludesUI:RefreshPage()
                end
            end
            local function Alpha(m)
                return function()
                    return (Mode() == m) and 1 or 0.3
                end
            end
            return {
                {
                    tooltip = "Custom Color",
                    hasAlpha = true,
                    refreshAlpha = Alpha("custom"),
                    getValue = function()
                        local color = mod._PGCustomColor(colorKey)
                        return color.r, color.g, color.b, color.a or 1
                    end,
                    setValue = function(red, green, blue, a)
                        PGS()[colorKey] = { r = red, g = green, b = blue, a = a }
                        ApplyPowerGlow()
                    end,
                    onClick = function(self)
                        if Mode() ~= "custom" then
                            Pick("custom")()
                        elseif self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                },
                {
                    tooltip = "Class Colored",
                    hasAlpha = false,
                    refreshAlpha = Alpha("class"),
                    getValue = function()
                        local color = CludesUI.GetClassColor(CludesUI._playerClass)
                        if color then
                            return color.r, color.g, color.b, 1
                        end
                        return 1, 1, 1, 1
                    end,
                    setValue = function() end,
                    onClick = Pick("class"),
                },
                {
                    tooltip = "Accent Colored",
                    hasAlpha = false,
                    refreshAlpha = Alpha("accent"),
                    getValue = function()
                        local red, green, b = CludesUI.ResolveActiveAccent()
                        return red or 1, green or 1, b or 1, 1
                    end,
                    setValue = function() end,
                    onClick = Pick("accent"),
                },
            }
        end
        local pgRow
        pgRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Player Group Label",
            tooltip = "Shows your raid group number in its own movable frame. Position it in Layout Mode.",
            getValue = function()
                return PGS().enabled and true or false
            end,
            setValue = function(val)
                PGS().enabled = val
                if not val then
                    mod._pgPreview = nil
                end
                ApplyPowerGlow()
                -- The mover's isHidden verdict changed: re-register.
                if mod._RFRegisterUnlock then
                    mod._RFRegisterUnlock()
                end
                CludesUI:RefreshPage()
            end,
        }, {
            type = "multiSwatch",
            text = "Group Label Text Color",
            disabled = PGOff,
            disabledTooltip = "Player Group Label",
            swatches = PGModeSwatches("textColorMode", "textColor"),
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "multiSwatch",
            text = "Group Label Background",
            disabled = PGOff,
            disabledTooltip = "Player Group Label",
            swatches = {
                {
                    tooltip = "Background",
                    hasAlpha = true,
                    getValue = function()
                        local color = select(3, mod._PGStyle())
                        return color.r, color.g, color.b, color.a or 1
                    end,
                    setValue = function(red, green, blue, a)
                        PGS().bgColor = { r = red, g = green, b = blue, a = a }
                        ApplyPowerGlow()
                    end,
                },
            },
        }, {
            type = "multiSwatch",
            text = "Group Label Border Color",
            disabled = PGOff,
            disabledTooltip = "Player Group Label",
            swatches = PGModeSwatches("borderColorMode", "borderColor"),
        })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            local region = pgRow._leftRegion
            local function SizeRow(labelText, key)
                return {
                    type = "slider",
                    label = labelText,
                    min = 0,
                    max = 200,
                    step = 1,
                    tooltip = "0 sizes the frame to the text plus padding.",
                    get = function()
                        return PGS()[key] or 0
                    end,
                    set = function(val)
                        PGS()[key] = (val > 0) and val or nil
                        ApplyPowerGlow()
                    end,
                }
            end
            CludesUI.BuildInlineCog(region, {
                title = "Player Group Label",
                disabled = PGOff,
                disabledTooltip = "Player Group Label",
                rows = {
                    {
                        type = "dropdown",
                        label = "Text Format",
                        values = { number = "3", full = GROUP_NUMBER:format(3) },
                        order = { "number", "full" },
                        get = function()
                            return PGS().format == "full" and "full" or "number"
                        end,
                        set = function(keyName)
                            PGS().format = keyName
                            ApplyPowerGlow()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 40,
                        step = 1,
                        get = function()
                            return (mod._PGStyle())
                        end,
                        set = function(val)
                            PGS().textSize = val
                            ApplyPowerGlow()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Padding",
                        min = 0,
                        max = 20,
                        step = 1,
                        get = function()
                            return PGS().padding or 4
                        end,
                        set = function(val)
                            PGS().padding = val
                            ApplyPowerGlow()
                        end,
                    },
                    SizeRow("Width", "width"),
                    SizeRow("Height", "height"),
                    {
                        type = "slider",
                        label = "Border Size",
                        min = 0,
                        max = 4,
                        step = 1,
                        get = function()
                            return (select(4, mod._PGStyle()))
                        end,
                        set = function(val)
                            PGS().borderSize = val
                            ApplyPowerGlow()
                        end,
                    },
                },
            })

            local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
            local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON
            local eyeButton = CreateFrame("Button", nil, region)
            eyeButton:SetSize(26, 26)
            eyeButton:SetPoint("RIGHT", region._lastInline, "LEFT", -4, 0)
            region._lastInline = eyeButton
            eyeButton:SetFrameLevel(region:GetFrameLevel() + 5)
            CludesUI.SetGlyphAlpha(eyeButton, 0.4)
            local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            eyeTex:SetTexture(EYE_VISIBLE)
            local function PaintPowerGlowEye()
                eyeTex:SetTexture(mod._pgPreview and EYE_INVISIBLE or EYE_VISIBLE)
                eyeButton:SetEnabled(not PGOff())
                CludesUI.SetGlyphAlpha(eyeButton, PGOff() and 0.15 or 0.4)
            end
            EYE.refreshPGEye = PaintPowerGlowEye
            CludesUI.RegisterWidgetRefresh(PaintPowerGlowEye)
            PaintPowerGlowEye()
            eyeButton:SetScript("OnClick", function()
                if mod.PG_SetPreview then
                    mod.PG_SetPreview(not mod._pgPreview)
                end
                PaintPowerGlowEye()
            end)
            eyeButton:SetScript("OnEnter", function(s)
                CludesUI.SetGlyphAlpha(s, 0.7)
                CludesUI.ShowWidgetTooltip(
                    s,
                    mod._pgPreview and "Hide the preview" or "Preview the label at its position"
                )
            end)
            eyeButton:SetScript("OnLeave", function(s)
                CludesUI.SetGlyphAlpha(s, 0.4)
                CludesUI.HideWidgetTooltip()
            end)
            if not pgEyeOnHide then
                pgEyeOnHide = true
                CludesUI:RegisterOnHide(StopPGPreviewOnHide)
            end
        end
    end

    -- Hide Blizzard Party Panel shares the exact global setting and apply function as Quality of Life's Hide Blizzard Elements > Party Panel (CludesUIDB.hideBlizzardPartyFrame -> CludesUI._applyHideBlizzardPartyFrame): one setting, changeable on either page. Off when unset.
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Hide Blizzard Party Panel",
        tooltip = "Hides the collapsed Blizzard party/raid sidebar panel on the side of the screen.",
        getValue = function()
            return CludesUIDB and CludesUIDB.hideBlizzardPartyFrame or false
        end,
        setValue = function(val)
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.hideBlizzardPartyFrame = val
            CludesUI._applyHideBlizzardPartyFrame()
        end,
    }, {
        type = "multiSwatch",
        text = "Status Colors",
        swatches = {
            {
                tooltip = "Offline",
                hasAlpha = false,
                getValue = function()
                    local color = SGet("statusColorOffline")
                    if color then
                        return color.r, color.g, color.b
                    end
                    return 0x66 / 255, 0x66 / 255, 0x66 / 255
                end,
                setValue = function(red, green, blue)
                    SWrite("statusColorOffline", { r = red, g = green, b = blue })
                    ReloadAndUpdate()
                end,
            },
            {
                tooltip = "Dead",
                hasAlpha = false,
                getValue = function()
                    local color = SGet("statusColorDead")
                    if color then
                        return color.r, color.g, color.b
                    end
                    return 0x24 / 255, 0x17 / 255, 0x17 / 255
                end,
                setValue = function(red, green, blue)
                    SWrite("statusColorDead", { r = red, g = green, b = blue })
                    ReloadAndUpdate()
                end,
            },
        },
    })
    cursorY = cursorY - height

    -- Right-click + drag over a raid/party frame turns the camera (mouselook).
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Right Mouse Camera Unlock",
        tooltip = "Allows free camera movement while holding and dragging right mouse button over raid and party frames. Right-click tap still opens the unit menu.",
        getValue = SValRow("freeRightClickCamera", false),
        setValue = function(val)
            SSet("freeRightClickCamera", val)
            if mod.FRCM_Refresh then
                mod.FRCM_Refresh()
            end
        end,
    }, {
        type = "dropdown",
        text = "Frame Strata",
        tooltip = "Controls the display order of raid and party frames. Set higher to show above other elements.",
        values = CludesUI.FRAME_STRATA_LABELS,
        order = CludesUI.FRAME_STRATA_ORDER_BASE,
        getValue = SValRow("frameStrata", "LOW"),
        setValue = function(val)
            -- Reload after changing strata to restore child frame levels.
            SWrite("frameStrata", val)
            if mod.ApplyFrameStrata then
                mod.ApplyFrameStrata()
            end
            ReloadAndUpdate()
        end,
    })
    cursorY = cursorY - height

    if onSection then
        onSection("rangeTooltip", _secY, cursorY)
    end
    return cursorY
end

-- Used by CUI_RaidFrames_Options.lua
mod.RFO_BuildVisualIndicators = BuildVisualIndicators
