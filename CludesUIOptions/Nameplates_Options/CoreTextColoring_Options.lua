if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\CoreTextColoring_Options.lua
--  Nameplates options: the Core Text Coloring section of the Display page,
--  one Text Coloring half per assigned text in position order. Called by
--  BuildDisplayLayout (DisplayLayout_Options.lua) right after the Core Text
--  Positions section; returns y. Shared helpers come from ns._NPO_OptEnv, the
--  text slots from ns.NPO_TEXT_SLOTS and ns.NPO_TextSlotShown.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUINameplates"]
if not mod then
    return
end -- module disabled: no options page

local function BuildCoreTextColoring(hostFrame, cursorY, W)
    local environ = mod._NPO_OptEnv
    local DB, DBVal, defaultSet = environ.DB, environ.DBVal, environ.defaults
    local Pix, UpdatePreview, RefreshAllPlates = environ.PP, environ.UpdatePreview, environ.RefreshAllPlates

    -- The assigned texts in position order. While none is assigned the section
    -- is not built at all (no header, no spacer).
    local isShown = {}
    local slots = mod.NPO_TEXT_SLOTS
    for idx = 1, #slots do
        if mod.NPO_TextSlotShown(slots[idx].key) then
            isShown[#isShown + 1] = slots[idx]
        end
    end
    if #isShown == 0 then
        return cursorY
    end

    local _, height = W:SectionHeader(hostFrame, "CORE TEXT COLORING", cursorY)
    cursorY = cursorY - height

    hostFrame._showRowDivider = true

    -- Text Coloring halves: one per assigned text, in their own section. The
    -- dropdown picks the slot's colour mode; ns.NP_SlotColorMode reads the saved
    -- mode, or derives it from the older colour keys until one is picked, so the
    -- page and the plates always agree.
    -- Custom paints the slot colour; Hostility / Class paints enemy players by
    -- class and NPCs by the Tapped / Neutral / Hostile name colours every slot
    -- shares (Target of Target: the target's class, else the slot colour); Level
    -- Difficulty paints the unit's level difficulty colour (every text but Target
    -- of Target, which names another unit).
    local COLOR_MODE_ORDER = { "custom", "class" }
    local COLOR_MODE_ORDER_LEVEL = { "custom", "class", "level" }
    local function TextColoringCfg(slotKey, labelText)
        local el = DBVal(slotKey)
        if el == "none" then
            return CludesUI.BlankRowCfg()
        end
        local values, sequence
        if el == "targetOfTarget" then
            values, sequence = { custom = "Custom", class = "Class" }, COLOR_MODE_ORDER
        else
            values = { custom = "Custom", class = "Hostility / Class", level = "Level Difficulty" }
            sequence = COLOR_MODE_ORDER_LEVEL
        end
        return {
            type = "dropdown",
            text = labelText,
            values = values,
            order = sequence,
            getValue = function()
                return mod.NP_SlotColorMode(slotKey, DB())
            end,
            -- The mode is saved only when the pick differs from what the slot derives
            -- with none saved, so picking the derived value pins nothing. Rebuild: the
            -- shared NPC swatches exist only on a Hostility / Class half.
            setValue = function(val)
                local saved = DB()
                saved[slotKey .. "ColorMode"] = nil
                if mod.NP_SlotColorMode(slotKey, saved) ~= val then
                    saved[slotKey .. "ColorMode"] = val
                end
                mod.RefreshAllSettings()
                UpdatePreview()
                CludesUI:RefreshPage(true)
            end,
        }
    end

    -- A Text Coloring half's inline controls. The swatches sit beside the
    -- dropdown, shown by the mode from the page refresh: Custom the slot colour,
    -- Hostility / Class the three shared NPC colours (Target of Target: the slot
    -- colour, used for an NPC target), Level Difficulty none. Level | Name and
    -- Name | Level add a cog beside the dropdown, the shown swatches left of it,
    -- with the name and level part colours (inline escapes on that part
    -- only; the rest of the text keeps the mode's colour). The NPC swatches are
    -- built only on a Hostility / Class half, so no other half traces the shared
    -- keys for Spec Overrides. Every write goes through the dropdown, a cog row or
    -- a swatch, which the Spec Overrides capture follows on its own.
    local npcSwatchUpdates = {} -- the shared NPC swatches of every row, repainted together
    local function MakeTextColoringInline(row, regionKey, slotKey, title)
        local el = DBVal(slotKey)
        if el == "none" then
            return
        end
        local region = row[regionKey]
        local colorKey = slotKey .. "Color"
        local isToT = el == "targetOfTarget"
        local function Mode()
            return mod.NP_SlotColorMode(slotKey, DB())
        end
        local function Apply()
            mod.RefreshAllSettings()
            UpdatePreview()
        end

        -- Level | Name and Name | Level: the part colours on a cog beside the
        -- dropdown, built first so the swatches chain left of it.
        local cog
        if el == "levelName" or el == "nameLevel" then
            local nameOnKey, nameColorKey = slotKey .. "NameColorOn", slotKey .. "NameColor"
            local lvlOnKey, lvlColorKey = slotKey .. "LevelColorOn", slotKey .. "LevelColor"
            local diffKey = slotKey .. "LevelDiffOn"
            -- A part colour not picked yet starts from the slot colour.
            local function PartColor(key)
                local saved = DB()
                local c = (saved and (saved[key] or saved[colorKey])) or defaultSet[colorKey]
                return c.r, c.g, c.b
            end
            cog = CludesUI.BuildInlineCog(region, {
                title = title,
                captureRegion = region,
                rows = {
                    {
                        type = "toggle",
                        label = "Custom Name Color",
                        get = function()
                            return DBVal(nameOnKey) == true
                        end,
                        set = function(val)
                            DB()[nameOnKey] = val
                            Apply()
                        end,
                    },
                    {
                        type = "colorpicker",
                        label = "Name Color",
                        hidden = function()
                            return DBVal(nameOnKey) ~= true
                        end,
                        get = function()
                            return PartColor(nameColorKey)
                        end,
                        set = function(red, green, blue)
                            DB()[nameColorKey] = { r = red, g = green, b = blue }
                            Apply()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Custom Level Color",
                        get = function()
                            return DBVal(lvlOnKey) == true
                        end,
                        set = function(val)
                            DB()[lvlOnKey] = val
                            if val then
                                DB()[diffKey] = false
                            end
                            Apply()
                        end,
                    },
                    {
                        type = "colorpicker",
                        label = "Level Color",
                        hidden = function()
                            return DBVal(lvlOnKey) ~= true
                        end,
                        get = function()
                            return PartColor(lvlColorKey)
                        end,
                        set = function(red, green, blue)
                            DB()[lvlColorKey] = { r = red, g = green, b = blue }
                            Apply()
                        end,
                    },
                    -- The whole text already takes the difficulty colour in Level
                    -- Difficulty mode.
                    {
                        type = "toggle",
                        label = "Level Difficulty Color",
                        hidden = function()
                            return Mode() == "level"
                        end,
                        get = function()
                            return mod.NP_SlotLevelDiff(slotKey, DB())
                        end,
                        set = function(val)
                            DB()[diffKey] = val
                            if val then
                                DB()[lvlOnKey] = false
                            end
                            Apply()
                        end,
                    },
                },
            })
        end

        -- The custom swatch and the first NPC swatch (never shown together) both
        -- sit beside the cog, or beside the dropdown on a half without one.
        local anchor = region._lastInline or region._control
        local gap = region._lastInline and -8 or -12
        local custom, updateCustom = CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
            local c = (DB() and DB()[colorKey]) or defaultSet[colorKey]
            return c.r, c.g, c.b
        end, function(red, green, blue)
            DB()[colorKey] = { r = red, g = green, b = blue }
            Apply()
        end, nil, 20)
        Pix.Point(custom, "RIGHT", anchor, "LEFT", gap, 0)
        custom:SetScript("OnEnter", function()
            if isToT and Mode() == "class" then
                CludesUI.ShowWidgetTooltip(custom, CludesUI.L("NPC Target Color"))
            else
                CludesUI.ShowWidgetTooltip(custom, CludesUI.L("Custom Color"))
            end
        end)
        custom:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)

        -- Hostility / Class: Tapped / Neutral / Hostile left to right, Hostile in
        -- the custom swatch's place.
        local npc, npcUpd
        if not isToT and Mode() == "class" then
            npc, npcUpd = {}, {}
            local prev, prevGap = anchor, gap
            local function NPCSwatch(key, fallbackKey, tipText)
                local sw, upd = CludesUI.BuildColorSwatch(
                    region,
                    region:GetFrameLevel() + 5,
                    function()
                        local c = (DB() and DB()[key]) or defaultSet[fallbackKey]
                        return c.r, c.g, c.b
                    end,
                    -- Read live by the per-unit painter, so a health colour pass repaints.
                    function(red, green, blue)
                        DB()[key] = { r = red, g = green, b = blue }
                        RefreshAllPlates()
                        UpdatePreview()
                        for idx = 1, #npcSwatchUpdates do
                            npcSwatchUpdates[idx]()
                        end
                    end,
                    nil,
                    20
                )
                Pix.Point(sw, "RIGHT", prev, "LEFT", prevGap, 0)
                prev, prevGap = sw, -8
                sw:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(sw, tipText)
                end)
                sw:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                npc[#npc + 1] = sw
                npcUpd[#npcUpd + 1] = upd
                npcSwatchUpdates[#npcSwatchUpdates + 1] = upd
                return sw
            end
            NPCSwatch("enemyNameHostileColor", "hostile", CludesUI.L("Hostile Color"))
            NPCSwatch("enemyNameNeutralColor", "neutral", CludesUI.L("Neutral Color"))
            NPCSwatch("enemyNameTappedColor", "tapped", CludesUI.L("Tapped Color"))
        end

        local function ShowForMode()
            local m = Mode()
            local showCustom = m == "custom" or (isToT and m == "class")
            custom:SetShown(showCustom)
            updateCustom()
            local npcOn = npc and m == "class"
            if npc then
                for idx = 1, #npc do
                    npc[idx]:SetShown(npcOn)
                    npcUpd[idx]()
                end
            end
            -- The label clamp's bound (read a frame after the build): the
            -- leftmost item this mode shows, the cog when no swatch shows, the
            -- dropdown itself on a half with neither.
            region._lastInline = (npcOn and npc[#npc]) or (showCustom and custom) or cog
        end
        CludesUI.RegisterWidgetRefresh(ShowForMode)
        ShowForMode()
    end

    -- Two halves per row in position order; an odd last half sits beside a
    -- blank one.
    for keyName = 1, #isShown, 2 do
        local l, r = isShown[keyName], isShown[keyName + 1]
        local row, rowH = W:DualRow(
            hostFrame,
            cursorY,
            TextColoringCfg(l.key, l.coloring),
            r and TextColoringCfg(r.key, r.coloring) or CludesUI.BlankRowCfg()
        )
        if not CludesUI._prebuilding then
            MakeTextColoringInline(row, "_leftRegion", l.key, l.coloring)
            if r then
                MakeTextColoringInline(row, "_rightRegion", r.key, r.coloring)
            end
        end
        cursorY = cursorY - rowH
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    return cursorY
end

-- Used by DisplayLayout_Options.lua
mod.NPO_BuildCoreTextColoring = BuildCoreTextColoring
