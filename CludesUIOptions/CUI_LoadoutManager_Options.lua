if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_LoadoutManager_Options.lua  --  Settings page for the Loadout Manager
--
--  The module owns the saved variables, the edit scope and the swap
--  machinery; this page drives it through the ns API. Status lines, summaries
--  and pickers are live widgets re-read on every page refresh. Picking another
--  edit scope rebuilds the page, since its tooltips and the copy cog name it.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUILoadoutManager"
local mod = CludesUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page

local PAGE_DISPLAY = "Loadout Manager"

CludesUI.AtOptionsLogin(function()

    local function DB()
        return mod.DB()
    end

    local function ApplyLoadouts(force)
        CludesUI:RefreshPage(force and true or nil)
    end

    -- The module calls this when its state changes.
    mod.OnStateChanged = function()
        if CludesUI:GetActiveModule() ~= ADDON_NAME then
            return
        end
        ApplyLoadouts()
    end

    local function NotEnabled()
        return not DB().enabled
    end

    -- Why a control is locked, shown as written (rawTooltip).
    local PICK_FIRST = "Pick a gear set or talent loadout first."
    local NOT_IN_INSTANCE = "Enter a dungeon, raid or other instance first."
    local TALENT_SCOPE = "Set Assign For to All Specs or your spec."

    ---------------------------------------------------------------------------
    --  Text helpers. Widget labels and tooltips are translated where the
    --  widgets draw them; the lines this page writes itself go through L/Lf.
    ---------------------------------------------------------------------------
    local DIM = CludesUI.COLOR_CODES.DIM
    local function Grey(textValue)
        return DIM .. tostring(textValue) .. "|r"
    end

    -- Assigned names in the suite accent, read on every call so a theme change
    -- lands with the next refresh.
    local function Accent(textValue)
        local color = CludesUI.CLUDES_GREEN
        return CludesUI.HexColor(color.r, color.g, color.b) .. tostring(textValue) .. "|r"
    end

    local ALL_SPECS_TEXT = CludesUI.L("All Specs")
    local TXT_NOT_SET = Grey(CludesUI.L("not set"))
    local TXT_NO_GEAR = Grey(CludesUI.L("no gear"))
    local TXT_NO_TALENTS = Grey(CludesUI.L("no talents"))
    local TXT_SLASH = Grey(" / ")
    local TXT_NOTHING_HERE = Grey(CludesUI.L("nothing assigned here"))
    local TXT_OUTSIDE = Grey(CludesUI.L("not in an instance"))
    local TXT_OPEN_WORLD = Grey(CludesUI.L("open world"))
    local TXT_UNKNOWN = Grey(CludesUI.L("unknown"))
    local TXT_PICK_SAVED = Grey(CludesUI.L("pick a saved instance"))

    -- One assignment slot as "gear / talents", or "not set".
    local function PairSummary(gearName, talentStored)
        local talentName = mod.TalentDisplayName(talentStored)
        if not gearName and not talentName then
            return TXT_NOT_SET
        end
        return (gearName and Accent(gearName) or TXT_NO_GEAR)
            .. TXT_SLASH
            .. (talentName and Accent(talentName) or TXT_NO_TALENTS)
    end

    ---------------------------------------------------------------------------
    --  Content types, each specific type next to the one it outranks and Open
    --  World last (it applies on the way out)
    ---------------------------------------------------------------------------
    local TYPE_INFO = {}
    for _, details in ipairs(mod.INSTANCE_TYPE_ORDER) do
        TYPE_INFO[details.key] = details
    end

    local TYPE_LAYOUT =
        { "party", "mplus", "raid", "timewalking", "scenario", "delve", "arena", "pvp", "world" }

    -- Tooltips for the types whose label alone does not say where they
    -- apply; the others have none.
    local TYPE_TIPS = {
        world = "Applies when you leave an instance.",
        mplus = "Mythic and Mythic+ dungeons.",
        timewalking = "Timewalking dungeons and raids.",
    }

    local INSTANCE_KIND = {
        party = CludesUI.L("Dungeon"),
        raid = CludesUI.L("Raid"),
        scenario = CludesUI.L("Scenario"),
        arena = CludesUI.L("Arena"),
        pvp = CludesUI.L("Battleground"),
    }
    local INSTANCE_KIND_OTHER = CludesUI.L("Instance")

    ---------------------------------------------------------------------------
    --  Edit scope: "All Specs" plus one entry per specialization, set only by
    --  the Assign For pick
    ---------------------------------------------------------------------------
    local ALL_SPECS = "all"

    local function ScopeValues()
        -- Spec names come from the game already translated.
        local values, sequence = { _noLoc = true, [ALL_SPECS] = ALL_SPECS_TEXT }, { ALL_SPECS }
        for _, specInfo in ipairs(mod.GetSpecList()) do
            values[tostring(specInfo.id)] = specInfo.name
            sequence[#sequence + 1] = tostring(specInfo.id)
        end
        return values, sequence
    end

    local function GetScopeKey()
        local scope = mod.GetScope()
        return scope and tostring(scope) or ALL_SPECS
    end

    local function SetScopeKey(key)
        mod.SetScope(key ~= ALL_SPECS and tonumber(key) or nil)
        ApplyLoadouts(true) -- the page's tooltips and the copy cog name the scope
    end

    local function ScopeLabel()
        local scope = mod.GetScope()
        return scope and tostring(mod.SpecName(scope)) or ALL_SPECS_TEXT
    end

    ---------------------------------------------------------------------------
    --  Pickers. Their value tables are refilled in place when the game's list
    --  changes and the cached menu is invalidated, so no rebuild is needed.
    ---------------------------------------------------------------------------
    local NONE = "__none__"
    local function Noop() end

    local gearIcons = {}

    local function GearEntries()
        local entries, sig = {}, {}
        for keyName in pairs(gearIcons) do
            gearIcons[keyName] = nil
        end
        for _, set in ipairs(mod.ListEquipmentSets()) do
            entries[#entries + 1] = { key = set.name, text = set.name }
            gearIcons[set.name] = set.icon
            sig[#sig + 1] = tostring(set.name) .. "=" .. tostring(set.icon)
        end
        return entries, table.concat(sig, "\n")
    end

    local function TalentEntries()
        local entries, sig = {}, {}
        for _, loadout in ipairs(mod.ListTalentLoadouts()) do
            local key = tostring(loadout.configID)
            entries[#entries + 1] = { key = key, text = loadout.name }
            sig[#sig + 1] = key .. "=" .. tostring(loadout.name)
        end
        return entries, table.concat(sig, "\n")
    end

    -- Menu options (_menuOpts) and the no-localize flag (_noLoc) ride along
    -- in the values table and survive a refill; everything else is replaced.
    local function FillValues(values, sequence, noneText, entries)
        for keyName in pairs(values) do
            if keyName ~= "_menuOpts" and keyName ~= "_noLoc" then
                values[keyName] = nil
            end
        end
        for idx = #sequence, 1, -1 do
            sequence[idx] = nil
        end
        values[NONE] = noneText
        sequence[1] = NONE
        for _, entry in ipairs(entries) do
            values[entry.key] = entry.text
            sequence[#sequence + 1] = entry.key
        end
    end

    -- Returns the tables for a picker plus Update (register as a widget
    -- refresh) and Attach (hand it the dropdown button once it exists).
    -- noneText is already translated.
    local function LivePicker(noneText, entriesFn, menuOpts)
        -- Set, loadout and instance names are the game's or the player's own:
        -- never run them through L().
        local values, sequence = { _noLoc = true }, {}
        if menuOpts then
            values._menuOpts = menuOpts
        end
        -- The search prebuild indexes the row, never its list.
        if CludesUI._prebuilding then
            return values, sequence, Noop, Noop
        end
        local entries, sig = entriesFn()
        FillValues(values, sequence, noneText, entries)
        local dropdownBtn
        local function Update()
            local e, s = entriesFn()
            if s == sig then
                return
            end
            sig = s
            FillValues(values, sequence, noneText, e)
            if dropdownBtn and dropdownBtn._invalidateMenu then
                dropdownBtn._invalidateMenu()
            end
        end
        local function Attach(button)
            dropdownBtn = button
        end
        return values, sequence, Update, Attach
    end

    local function SetSelectedTalentKey(key)
        if key == NONE then
            mod.SetSelectedTalent(nil)
        else
            for _, loadout in ipairs(mod.ListTalentLoadouts()) do
                if tostring(loadout.configID) == key then
                    mod.SetSelectedTalent(mod.StoreTalentLoadout(loadout))
                    break
                end
            end
        end
        ApplyLoadouts()
    end

    ---------------------------------------------------------------------------
    --  Readers for the live labels
    ---------------------------------------------------------------------------
    local function LocationText()
        local context = mod.GetContext()
        if not context.inInstance then
            local zone = GetRealZoneText()
            if not zone or zone == "" then
                zone = context.name
            end
            return tostring(zone) .. "  " .. TXT_OPEN_WORLD
        end
        local kind = INSTANCE_KIND[context.instanceType] or INSTANCE_KIND_OTHER
        if context.difficultyName and context.difficultyName ~= "" then
            kind = kind .. ", " .. context.difficultyName
        end
        return tostring(context.name) .. "  " .. Grey(kind)
    end

    -- The difficulty a per-difficulty assignment here covers. A running key
    -- reads as Mythic, the difficulty you enter at (the module stores it so).
    local function DifficultyName()
        return mod.DifficultyName(mod.GetContext())
    end

    -- Where a resolved assignment comes from, e.g. "(Raid default, Holy)".
    local function SourceText(level, key, scope)
        local layer = scope and tostring(mod.SpecName(scope)) or ALL_SPECS_TEXT
        if level == "difficulty" then
            return Grey(CludesUI.Lf("(this instance, %1$s only, %2$s)", DifficultyName(), layer))
        elseif level == "instance" then
            return Grey(CludesUI.Lf("(this instance, %1$s)", layer))
        elseif level == "type" then
            local details = TYPE_INFO[key]
            local typeName = details and CludesUI.L(details.label) or tostring(key)
            return Grey(CludesUI.Lf("(%1$s default, %2$s)", typeName, layer))
        end
        return ""
    end

    -- This instance's assignment slot in the scope being edited, under the
    -- key the module writes for it. Returns inside, gear, talent.
    local function InstanceSlot(perDifficulty)
        local context = mod.GetContext()
        if not context.inInstance or not context.instanceID then
            return false
        end
        local key = mod.AssignmentKey(context, perDifficulty)
        if not key then
            return true
        end
        local R = mod.ReadTables()
        if perDifficulty then
            return true, R.difficultySets[key], R.talentDifficultySets[key]
        end
        return true, R.instanceSets[key], R.talentInstanceSets[key]
    end

    -- Saved Instances list: every instance assignment in the scope being
    -- edited, wherever you are. The pick is the page's own state; savedByKey
    -- holds the entries the latest list read returned, by picker key.
    local pickedSaved -- tostring(key) of the picked entry, or nil
    local savedByKey = {}

    local function SavedEntries()
        local entries, sig = {}, {}
        wipe(savedByKey)
        for _, entry in ipairs(mod.ListInstanceAssignments()) do
            local key = tostring(entry.key)
            entries[#entries + 1] = { key = key, text = entry.label }
            sig[#sig + 1] = key .. "=" .. entry.label
            savedByKey[key] = entry
        end
        return entries, table.concat(sig, "\n")
    end

    local function PickedSavedEntry()
        return pickedSaved and savedByKey[pickedSaved] or nil
    end

    local function TypeSlot(key)
        local R = mod.ReadTables()
        return R.typeDefaults[key], R.talentTypeDefaults[key]
    end

    ---------------------------------------------------------------------------
    --  Widget helpers
    ---------------------------------------------------------------------------
    -- Show a live value after a half-row's own text (prefix, translated),
    -- re-read on every page refresh. The label is bounded left of the half's
    -- inline controls so a long line ellipsizes, and a half with no tooltip
    -- of its own shows the whole line on hover while it is cut. Call after
    -- those controls are built.
    local function LiveLabel(regionFrame, prefixText, valueFn)
        if CludesUI._prebuilding then
            return
        end
        local labelText = regionFrame and regionFrame._label
        if not labelText then
            return
        end
        local bound = regionFrame._lastInline or regionFrame._control
        if bound then
            labelText:SetPoint("RIGHT", bound, "LEFT", -12, 0)
        else
            labelText:SetPoint("RIGHT", regionFrame, "RIGHT", -20, 0)
        end
        local function Update()
            labelText:SetText(prefixText .. "  " .. valueFn())
            regionFrame._labelTruncated = labelText:IsTruncated()
        end
        Update()
        CludesUI.RegisterWidgetRefresh(Update)
        if not regionFrame._labelHasHit then
            local hit = CreateFrame("Frame", nil, regionFrame)
            hit:SetPoint("TOPLEFT", labelText, "TOPLEFT", -5, 5)
            hit:SetPoint("BOTTOMRIGHT", labelText, "BOTTOMRIGHT", 5, -5)
            hit:SetMouseClickEnabled(false)
            hit:SetScript("OnEnter", function()
                if labelText:IsTruncated() then
                    CludesUI.ShowWidgetTooltip(labelText, labelText:GetText())
                end
            end)
            hit:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            regionFrame._labelRevealHit = hit
        end
    end

    -- Compact button on a half-row. Inline controls chain right to left, so
    -- the first one built sits rightmost. tip shows while enabled, disabledTip
    -- (a sentence, or a function returning one) while disabled.
    local function InlineButton(regionFrame, textValue, onClick, tipText, disabledFn, disabledTip)
        CludesUI.BuildInlineButton(regionFrame, textValue, onClick, {
            width = 58,
            tip = tipText,
            disabled = disabledFn,
            disabledTooltip = disabledTip,
            rawTooltip = true,
        })
    end

    -- One frame, moved into each build of the page: its show and hide are the
    -- page's, so the module registers the events behind the live rows only
    -- while the page is on screen.
    local pageWatch
    local function WatchPage(hostFrame)
        if CludesUI._prebuilding then
            return
        end
        if not pageWatch then
            pageWatch = CreateFrame("Frame")
            pageWatch._searchIgnore = true -- the inline search never hides it
            pageWatch:SetScript("OnShow", function()
                mod.SetPageShown(true)
            end)
            pageWatch:SetScript("OnHide", function()
                mod.SetPageShown(false)
            end)
        end
        pageWatch:Hide()
        pageWatch:SetParent(hostFrame)
        pageWatch:Show()
    end

    ---------------------------------------------------------------------------
    --  Page
    ---------------------------------------------------------------------------
    local function BuildPage(page, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local Pix = CludesUI.PanelPP
        local cursorY = yOffset
        local _, height

        hostFrame._showRowDivider = true
        CludesUI:ClearContentHeader()
        WatchPage(hostFrame)

        local scopeName = ScopeLabel()

        -----------------------------------------------------------------------
        --  General: the master switch, what swaps on its own (timing on the
        --  cog), and the two ways a swap is announced
        -----------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "GENERAL", cursorY)
        cursorY = cursorY - height

        local swapRow
        swapRow, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "toggle",
                text = "Enable Loadout Manager",
                tooltip = "Swaps gear and talents as you change content.",
                getValue = function()
                    return DB().enabled
                end,
                setValue = function(val)
                    mod.SetEnabled(val)
                    ApplyLoadouts()
                end,
            },
            -- Placeholder for the checkbox dropdown built below: it gives the
            -- half its label, search entry and disabled label.
            {
                type = "dropdown",
                text = "Auto-Swap",
                tooltip = "Choose what swaps on its own.",
                values = { _placeholder = "..." },
                order = { "_placeholder" },
                getValue = function()
                    return "_placeholder"
                end,
                setValue = function() end,
                disabled = NotEnabled,
                disabledTooltip = "Loadout Manager",
            }
        )
        cursorY = cursorY - height

        if not CludesUI._prebuilding then
            local region = swapRow._rightRegion
            if region._control then
                region._control:Hide()
            end
            local checkDrop, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
                region,
                170,
                region:GetFrameLevel() + 2,
                {
                    { key = "gear", label = "Gear Sets", tooltip = "Equip the assigned gear set." },
                    {
                        key = "talent",
                        label = "Talent Loadouts",
                        tooltip = "Load the assigned talent loadout.",
                    },
                },
                function(keyName)
                    return DB()[keyName == "gear" and "gearEnabled" or "talentEnabled"] and true or false
                end,
                function(keyName, val)
                    mod.SetChannelEnabled(keyName, val)
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                {
                    disabled = NotEnabled,
                    disabledTooltip = "Loadout Manager",
                }
            )
            Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbRefresh)

            CludesUI.BuildInlineCog(region, {
                title = "Auto-Swap",
                rows = {
                    {
                        type = "toggle",
                        label = "Queue In Combat",
                        tooltip = "Apply a swap due in combat once it ends.",
                        get = function()
                            return DB().queueInCombat and true or false
                        end,
                        set = function(val)
                            mod.SetQueueInCombat(val)
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Re-Swap On Spec Change",
                        tooltip = "Swap again on a spec change in an instance.",
                        get = function()
                            return DB().specSwap and true or false
                        end,
                        set = function(val)
                            DB().specSwap = val and true or false
                        end,
                    },
                },
                disabled = NotEnabled,
                disabledTooltip = "Loadout Manager",
            })
        end

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Talent-Change Warning",
            tooltip = "Show DON'T MOVE while talents change.",
            getValue = function()
                return DB().specWarning and true or false
            end,
            setValue = function(val)
                mod.SetSpecWarning(val)
            end,
        }, {
            type = "toggle",
            text = "Announce Swaps In Chat",
            getValue = function()
                return DB().announce and true or false
            end,
            setValue = function(val)
                DB().announce = val and true or false
            end,
        })
        cursorY = cursorY - height

        -----------------------------------------------------------------------
        --  Current location: where you are and what applies here (live)
        -----------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "CURRENT LOCATION", cursorY)
        cursorY = cursorY - height

        local whereRow
        whereRow, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Location",
            buttonText = "Check Now",
            width = 130,
            tooltip = "Check Now applies what is assigned here.",
            onClick = function()
                mod.CheckAndSwap()
                ApplyLoadouts()
            end,
        }, {
            type = "label",
            text = "Specialization",
            tooltip = "Spec assignments win over All Specs.",
        })
        cursorY = cursorY - height
        LiveLabel(whereRow._leftRegion, CludesUI.L("Location"), LocationText)
        LiveLabel(whereRow._rightRegion, CludesUI.L("Specialization"), function()
            local specID = mod.GetCurrentSpecID()
            return specID and Accent(mod.SpecName(specID)) or TXT_UNKNOWN
        end)

        local hereRow
        hereRow, height = W:DualRow(
            hostFrame,
            cursorY,
            { type = "label", text = "Gear Here", tooltip = "The gear set that applies here." },
            { type = "label", text = "Talents Here", tooltip = "The talent loadout that applies here." }
        )
        cursorY = cursorY - height
        LiveLabel(hereRow._leftRegion, CludesUI.L("Gear Here"), function()
            local gear, level, key, scope = mod.ResolveGear(mod.GetContext())
            if not gear then
                return TXT_NOTHING_HERE
            end
            return Accent(gear) .. "  " .. SourceText(level, key, scope)
        end)
        LiveLabel(hereRow._rightRegion, CludesUI.L("Talents Here"), function()
            local talent, level, key, scope = mod.ResolveTalent(mod.GetContext())
            local name = mod.TalentDisplayName(talent)
            if not name then
                return TXT_NOTHING_HERE
            end
            return Accent(name) .. "  " .. SourceText(level, key, scope)
        end)

        -----------------------------------------------------------------------
        --  Selected loadout: what the Save buttons assign, and to which layer
        -----------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "SELECTED LOADOUT", cursorY)
        cursorY = cursorY - height

        local gearValues, gearOrder, gearUpdate, gearAttach =
            LivePicker(DIM .. CludesUI.L("No gear set") .. "|r", GearEntries, {
                icon = function(key)
                    local icon = gearIcons[key]
                    if icon then
                        return icon, 0.08, 0.92, 0.08, 0.92
                    end
                end,
            })
        local talentValues, talentOrder, talentUpdate, talentAttach =
            LivePicker(DIM .. CludesUI.L("No talent loadout") .. "|r", TalentEntries)
        -- Both lists refill before their dropdowns repaint (refreshers run in
        -- registration order).
        CludesUI.RegisterWidgetRefresh(gearUpdate)
        CludesUI.RegisterWidgetRefresh(talentUpdate)

        -- A pick counts only while its list holds it: a renamed or deleted
        -- set, or a loadout of another spec, reads as no pick.
        local function GearPick()
            local name = mod.GetSelectedSet()
            if name ~= nil and gearValues[name] ~= nil then
                return name
            end
        end
        local function TalentPickKey()
            local sel = mod.GetSelectedTalent()
            local key = sel and tostring(sel.configID)
            if key and talentValues[key] ~= nil then
                return key
            end
        end
        -- The module saves talents only into All Specs or the current spec.
        local function TalentScopeOK()
            local scope = mod.GetScope()
            return scope == nil or scope == mod.GetCurrentSpecID()
        end
        local function HasSelection()
            return GearPick() ~= nil or TalentPickKey() ~= nil
        end
        local function CanSave()
            return GearPick() ~= nil or (TalentPickKey() ~= nil and TalentScopeOK())
        end
        local function SaveBlockedTip()
            if TalentPickKey() and not TalentScopeOK() then
                return TALENT_SCOPE
            end
            return PICK_FIRST
        end
        -- Drop a pick its list no longer holds before an action reads the
        -- module's selection.
        local function PrunePicks()
            gearUpdate()
            talentUpdate()
            if mod.GetSelectedSet() ~= nil and not GearPick() then
                mod.SetSelectedSet(nil)
            end
            if mod.GetSelectedTalent() ~= nil and not TalentPickKey() then
                mod.SetSelectedTalent(nil)
            end
        end

        local pickRow
        pickRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Gear Set",
            values = gearValues,
            order = gearOrder,
            tooltip = "The gear set the Save buttons assign.",
            getValue = function()
                return GearPick() or NONE
            end,
            setValue = function(val)
                mod.SetSelectedSet(val ~= NONE and val or nil)
                ApplyLoadouts()
            end,
        }, {
            type = "dropdown",
            text = "Talent Loadout",
            values = talentValues,
            order = talentOrder,
            tooltip = "The talent loadout the Save buttons assign.",
            getValue = function()
                return TalentPickKey() or NONE
            end,
            setValue = SetSelectedTalentKey,
            disabled = function()
                return not TalentScopeOK()
            end,
            disabledTooltip = TALENT_SCOPE,
            rawTooltip = true,
        })
        cursorY = cursorY - height
        gearAttach(pickRow._leftRegion._control)
        talentAttach(pickRow._rightRegion._control)

        CludesUI.BuildInlineCog(pickRow._leftRegion, {
            title = "Gear Sets",
            rows = {
                {
                    type = "button",
                    label = "Verify Assigned Sets",
                    action = function()
                        mod.Verify()
                    end,
                },
            },
        })

        local scopeRow
        do
            local values, sequence = ScopeValues()
            scopeRow, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Assign For",
                values = values,
                order = sequence,
                getValue = GetScopeKey,
                setValue = SetScopeKey,
                tooltip = "Which specs the Save buttons apply to.",
            }, {
                type = "labeledButton",
                text = "Equip Selection",
                buttonText = "Equip Now",
                width = 130,
                tooltip = "Equip the picked gear and talents now.",
                onClick = function()
                    PrunePicks()
                    mod.EquipSelected()
                    ApplyLoadouts()
                end,
                disabled = function()
                    return not HasSelection()
                end,
                disabledTooltip = PICK_FIRST,
                rawTooltip = true,
            })
            cursorY = cursorY - height
        end

        -- Copy cog: one button per other layer. CopyScopeFrom replaces this
        -- layer outright, so the cog closes and a confirmation asks first.
        if not CludesUI._prebuilding then
            local current = mod.GetScope()
            local copyTitle = CludesUI.Lf("Copy Into %1$s", scopeName)
            local rowList, cogShow = {}, nil
            local function AddCopy(sourceID, name)
                rowList[#rowList + 1] = {
                    type = "button",
                    label = CludesUI.Lf("Copy From %1$s", name),
                    action = function()
                        local popFrame = cogShow and cogShow._popupFrame
                        if popFrame and popFrame:IsShown() then
                            popFrame:Hide()
                        end
                        CludesUI:ShowConfirmPopup({
                            title = copyTitle,
                            message = CludesUI.Lf(
                                "Replace every %1$s assignment with a copy of the %2$s assignments?",
                                scopeName,
                                name
                            ),
                            confirmText = "Copy",
                            cancelText = "Cancel",
                            onConfirm = function()
                                mod.CopyScopeFrom(sourceID)
                                ApplyLoadouts()
                            end,
                        })
                    end,
                }
            end
            if current ~= nil then
                AddCopy(nil, ALL_SPECS_TEXT)
            end
            for _, specInfo in ipairs(mod.GetSpecList()) do
                if specInfo.id ~= current then
                    AddCopy(specInfo.id, specInfo.name)
                end
            end
            if #rowList > 0 then
                cogShow = select(
                    2,
                    CludesUI.BuildInlineCog(scopeRow._leftRegion, {
                        title = copyTitle,
                        minWidth = 220,
                        rows = rowList,
                    })
                )
            end
        end

        -----------------------------------------------------------------------
        --  Instances: this instance's two slots, each with Save and Clear,
        --  then every saved instance, which can be cleared from anywhere
        -----------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "INSTANCES", cursorY)
        cursorY = cursorY - height

        -- The Save and Clear tips name the scope the buttons write to.
        local saveTip = CludesUI.Lf("Save the picked loadout here for %1$s.", scopeName)
        local clearTip = CludesUI.Lf("Clear what is saved here for %1$s.", scopeName)
        local nothingTip = CludesUI.Lf("Nothing saved here for %1$s.", scopeName)

        local instRow
        instRow, height = W:DualRow(
            hostFrame,
            cursorY,
            { type = "label", text = "Any Difficulty", tooltip = "This instance on any difficulty." },
            { type = "label", text = "This Difficulty", tooltip = "This instance on this difficulty only." }
        )
        cursorY = cursorY - height

        for _, perDiff in ipairs({ false, true }) do
            local regionFrame = perDiff and instRow._rightRegion or instRow._leftRegion
            local function Inside()
                return (InstanceSlot(perDiff)) and true or false
            end
            local function Saved()
                local inside, g, t = InstanceSlot(perDiff)
                return inside and (g ~= nil or t ~= nil)
            end

            InlineButton(
                regionFrame,
                "Clear",
                function()
                    mod.ClearCurrent(perDiff)
                    ApplyLoadouts()
                end,
                clearTip,
                function()
                    return not Saved()
                end,
                function()
                    return Inside() and nothingTip or NOT_IN_INSTANCE
                end
            )
            InlineButton(
                regionFrame,
                "Save",
                function()
                    PrunePicks()
                    mod.AssignCurrent(perDiff)
                    ApplyLoadouts()
                end,
                saveTip,
                function()
                    return not Inside() or not CanSave()
                end,
                function()
                    return Inside() and SaveBlockedTip() or NOT_IN_INSTANCE
                end
            )
            LiveLabel(
                regionFrame,
                perDiff and CludesUI.L("This Difficulty") or CludesUI.L("Any Difficulty"),
                function()
                    local inside, g, t = InstanceSlot(perDiff)
                    if not inside then
                        return TXT_OUTSIDE
                    end
                    if perDiff then
                        return Grey("(" .. DifficultyName() .. ")") .. "  " .. PairSummary(g, t)
                    end
                    return PairSummary(g, t)
                end
            )
        end

        -- The list refills before the dropdown repaints (refreshers run in
        -- registration order), so a cleared entry never shows as picked.
        local savedValues, savedOrder, savedUpdate, savedAttach =
            LivePicker(DIM .. CludesUI.L("Pick an instance") .. "|r", SavedEntries)
        CludesUI.RegisterWidgetRefresh(savedUpdate)

        local savedRow
        savedRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Saved Instances",
            values = savedValues,
            order = savedOrder,
            tooltip = CludesUI.Lf("Every instance saved for %1$s.", scopeName),
            getValue = function()
                if pickedSaved and savedValues[pickedSaved] then
                    return pickedSaved
                end
                return NONE
            end,
            setValue = function(val)
                pickedSaved = (val ~= NONE) and val or nil
                ApplyLoadouts()
            end,
        }, {
            type = "label",
            text = "Assignment",
            tooltip = "What the picked instance holds.",
        })
        cursorY = cursorY - height
        savedAttach(savedRow._leftRegion._control)

        InlineButton(
            savedRow._rightRegion,
            "Clear",
            function()
                local e = PickedSavedEntry()
                pickedSaved = nil
                if e then
                    mod.ClearInstanceAssignment(e.key)
                end
                ApplyLoadouts()
            end,
            CludesUI.Lf("Clear the picked instance for %1$s.", scopeName),
            function()
                return PickedSavedEntry() == nil
            end,
            "Pick a saved instance first."
        )
        local nothingSaved = Grey(CludesUI.Lf("nothing saved for %1$s", scopeName))
        LiveLabel(savedRow._rightRegion, CludesUI.L("Assignment"), function()
            local e = PickedSavedEntry()
            if e then
                return PairSummary(e.gear, e.talent)
            end
            if #savedOrder <= 1 then
                return nothingSaved
            end
            return TXT_PICK_SAVED
        end)

        -----------------------------------------------------------------------
        --  Content type defaults: two per row, each with Save and Clear
        -----------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "CONTENT TYPE DEFAULTS", cursorY)
        cursorY = cursorY - height

        local function TypeHalf(details)
            if not details then
                return CludesUI.BlankRowCfg()
            end
            return { type = "label", text = details.label, tooltip = TYPE_TIPS[details.key] }
        end

        -- A type's buttons write its default wherever you stand, so their tips
        -- name the type and the scope.
        local function TypeControls(regionFrame, details)
            local key = details.key
            local typeName = CludesUI.L(details.label)
            local function IsSet()
                local g, t = TypeSlot(key)
                return g ~= nil or t ~= nil
            end
            InlineButton(
                regionFrame,
                "Clear",
                function()
                    mod.ClearType(key)
                    ApplyLoadouts()
                end,
                CludesUI.Lf("Clear the %1$s default for %2$s.", typeName, scopeName),
                function()
                    return not IsSet()
                end,
                CludesUI.Lf("No %1$s default saved for %2$s.", typeName, scopeName)
            )
            InlineButton(
                regionFrame,
                "Save",
                function()
                    PrunePicks()
                    mod.AssignType(key)
                    ApplyLoadouts()
                end,
                CludesUI.Lf("Save the picked loadout as the %1$s default for %2$s.", typeName, scopeName),
                function()
                    return not CanSave()
                end,
                SaveBlockedTip
            )
            LiveLabel(regionFrame, typeName, function()
                local g, t = TypeSlot(key)
                return PairSummary(g, t)
            end)
        end

        for idx = 1, #TYPE_LAYOUT, 2 do
            local leftX, right = TYPE_INFO[TYPE_LAYOUT[idx]], TYPE_INFO[TYPE_LAYOUT[idx + 1]]
            local row
            row, height = W:DualRow(hostFrame, cursorY, TypeHalf(leftX), TypeHalf(right))
            cursorY = cursorY - height
            TypeControls(row._leftRegion, leftX)
            if right then
                TypeControls(row._rightRegion, right)
            end
        end

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        hostFrame:SetHeight(math.abs(cursorY - yOffset))
        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    CludesUI:RegisterModule(ADDON_NAME, {
        title = PAGE_DISPLAY,
        description = "Applies gear sets and talent loadouts automatically per instance type and specialization.",
        pages = { PAGE_DISPLAY },
        buildPage = BuildPage,
        resetScope = "character",
        onReset = function()
            mod.ResetAll()
        end,
    })
end)
