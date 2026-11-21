if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI and CludesUI.IS_FOREVER then return end -- WoW Forever: talent reminders are retail-only (its options page is not built there)
-------------------------------------------------------------------------------
--  CludesUIABR_TalentReminders.lua
--  Standalone talent reminder system. Zero dependency on ABR aura/buff logic.
--  Reads reminder configs from the ABR DB (db.profile.talentReminders) but
--  manages its own icons, events, and refresh cycle.
-------------------------------------------------------------------------------
local floor = math.floor
local ICON_SIZE = 40

-------------------------------------------------------------------------------
--  Helpers (self-contained, no ABR imports)
-------------------------------------------------------------------------------
local function Known(ident) return ident and (IsPlayerSpell(ident) or IsSpellKnown(ident)) end

local texCache = {}
local function Tex(ident)
    local c = texCache[ident]
    if c then return c end
    local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ident)
    if t then texCache[ident] = t end
    return t
end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

local function InRealInstancedContent()
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then return false end
    if C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then return false end
    local _, iType = GetInstanceInfo()
    return iType == "party" or iType == "raid" or iType == "scenario" or iType == "arena" or iType == "pvp"
end

local function InMythicPlusKey()
    return C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
end

-------------------------------------------------------------------------------
--  Zone data
-------------------------------------------------------------------------------
-- SEASON UPDATE: the season raid + the Mythic+ pool (12.1 Season 2). Rotated-
-- out zones are removed from this picker list, but stored reminders for
-- them are kept (hidden in options) and still name-match at runtime --
-- re-adding a zone here revives its reminders in the options list too.
-- instanceID = GetInstanceInfo() 8th return, locale-proof.
local TALENT_REMINDER_ZONES = {
    { name = "The Venomous Abyss", type = "raid", instanceID = 3004 },

    { name = "Murder Row", type = "dungeon", instanceID = 2813 },
    { name = "Den of Nalorakk", type = "dungeon", instanceID = 2825 },
    { name = "The Blinding Vale", type = "dungeon", instanceID = 2859 },
    { name = "Voidscar Arena", type = "dungeon", instanceID = 2923 },
    { name = "Altar of Fangs", type = "dungeon", instanceID = 2993 },
    { name = "Ruby Life Pools", type = "dungeon", instanceID = 2521 },
    { name = "Temple of Sethraliss", type = "dungeon", instanceID = 1877 },
    { name = "Kings' Rest", type = "dungeon", instanceID = 1762 },

    { name = "Nagrand Arena", type = "pvp" },
    { name = "Blade's Edge Arena", type = "pvp" },
    { name = "Ruins of Lordaeron", type = "pvp" },
    { name = "Dalaran Sewers", type = "pvp" },
    { name = "The Ring of Valor", type = "pvp" },
    { name = "Tol'viron Arena", type = "pvp" },
    { name = "Tiger's Peak", type = "pvp" },
    { name = "Black Rook Hold Arena", type = "pvp" },
    { name = "Ashamane's Fall", type = "pvp" },
    { name = "Mugambala", type = "pvp" },
    { name = "Hook Point", type = "pvp" },
    { name = "Empyrean Domain", type = "pvp" },
    { name = "Warsong Gulch", type = "pvp" },
    { name = "Arathi Basin", type = "pvp" },
    { name = "Eye of the Storm", type = "pvp" },
    { name = "Strand of the Ancients", type = "pvp" },
    { name = "Isle of Conquest", type = "pvp" },
    { name = "Twin Peaks", type = "pvp" },
    { name = "Silvershard Mines", type = "pvp" },
    { name = "Battle for Gilneas", type = "pvp" },
    { name = "Temple of Kotmogu", type = "pvp" },
    { name = "Deepwind Gorge", type = "pvp" },
    { name = "Ashran", type = "pvp" },
    { name = "Seething Shore", type = "pvp" },
    { name = "Wintergrasp", type = "pvp" },
    { name = "Slayer's Rise", type = "pvp" },
}

local ZONE_BY_MAPID = {}
local ZONE_BY_INSTANCEID = {}
local ZONE_BY_NAME = {}
for _, z in ipairs(TALENT_REMINDER_ZONES) do
    if z.mapID then ZONE_BY_MAPID[z.mapID] = z end
    if z.instanceID then ZONE_BY_INSTANCEID[z.instanceID] = z end
    ZONE_BY_NAME[z.name] = z
end

-- How far a reminder's 'Not Needed' reminder reaches: "never", "season" (only in a
-- zone of the picker list above, this season's instances) or "all" (any instance).
-- Reminders saved before the choice existed hold only the old checkbox: on reads
-- as "season" and off as "never" (read here, never written back).
local function NotNeededMode(reminder)
    local m = reminder.notNeededMode
    if m == "never" or m == "season" or m == "all" then return m end
    return reminder.showNotNeeded and "season" or "never"
end
_G._CUABR_TR_NotNeededMode = NotNeededMode

-- Expose for options page
_G._CUABR_TALENT_REMINDER_ZONES = TALENT_REMINDER_ZONES

-------------------------------------------------------------------------------
--  DB access (reads from ABR SavedVariables, set up after PLAYER_LOGIN)
-------------------------------------------------------------------------------
local saved -- set during Init

local function GetReminders() return saved and saved.profile and saved.profile.talentReminders end

-------------------------------------------------------------------------------
--  Icon pool & display
-------------------------------------------------------------------------------
local talentIconAnchor
local talentIconPool = {}
local talentActiveIcons = {}

local function GetOrCreateIcon(index)
    if talentIconPool[index] then return talentIconPool[index] end
    local button =
        CreateFrame("Button", "EABR_TalentIcon" .. index, talentIconAnchor, "SecureActionButtonTemplate")
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    securecallfunction(button.SetPassThroughButtons, button, "RightButton", "MiddleButton")
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(100)
    button:Hide()
    local iconTex = button:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button._icon = iconTex
    local Pix = CludesUI and CludesUI.PP
    if Pix then Pix.CreateBorder(button, 0, 0, 0, 1, 1, "OVERLAY", 7) end
    local textValue = button:CreateFontString(nil, "OVERLAY")
    textValue:SetPoint("TOP", button, "BOTTOM", 0, -2)
    CludesUI.ApplyModuleFont(textValue, nil, 11, "auraBuff")
    textValue:SetTextColor(1, 1, 1, 1)
    button._text = textValue
    talentIconPool[index] = button
    return button
end

local function SetupIcon(button, record)
    if not InCombat() then
        button:SetAttribute("type", nil)
        button:SetAttribute("spell", nil)
        button:SetAttribute("item", nil)
        button:SetAttribute("macrotext", nil)
    end
    button._icon:SetTexture(record.texture or 134400)
    button._text:SetText(record.label or "")
    button._icon:SetDesaturated(false)
end

local function ShowIcon(iconIdx, record)
    local button = GetOrCreateIcon(iconIdx)
    SetupIcon(button, record)
    CludesUI.ApplyModuleFont(button._text, nil, 11, "auraBuff")
    button._text:SetTextColor(1, 1, 1, 1)
    button._text:Show()
    button:Show()
    talentActiveIcons[#talentActiveIcons + 1] = button
end

local function LayoutIcons()
    local total = #talentActiveIcons
    if total == 0 then return end
    local spacing = 40
    local sz = ICON_SIZE
    local totalW = (total * sz) + ((total - 1) * spacing)
    local startX = -totalW / 2
    for index, button in ipairs(talentActiveIcons) do
        button:SetSize(sz, sz)
        button:SetAlpha(1)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", talentIconAnchor, "TOP", startX + (index - 1) * (sz + spacing), 0)
    end
end

local function HideIcons()
    if InCombat() then return end
    for index = 1, #talentActiveIcons do
        local button = talentActiveIcons[index]
        if button then
            button._text:SetText("")
            button:Hide()
        end
    end
    wipe(talentActiveIcons)
    if talentIconAnchor then CludesUI.SetElementVisibility(talentIconAnchor, false) end
end

-------------------------------------------------------------------------------
--  Migration state
-------------------------------------------------------------------------------
local _migNeeded = false
local _migPending = false
local _migStamped = false

-------------------------------------------------------------------------------
--  Collection
-------------------------------------------------------------------------------
local _missing = {}

local function Collect()
    wipe(_missing)

    local inInstance = InRealInstancedContent()
    local inKeystone = InMythicPlusKey()
    if inKeystone or InCombat() or not inInstance then return end

    local reminders = GetReminders()
    if not reminders or #reminders == 0 then return end

    local currentInstance, _, _, _, _, _, _, currentInstanceID = GetInstanceInfo()
    local currentMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local _, playerClass = UnitClass("player")
    local playerSpecID = GetSpecializationInfo(GetSpecialization() or 1)
    if not currentInstance then return end
    -- The picker zone of this instance, by its ID or map first (locale-proof),
    -- names the zone the reminders match below. Any picker zone is the reach of
    -- "Current Season Instances", the instance's own name counting too.
    local idZone = currentInstanceID and ZONE_BY_INSTANCEID[currentInstanceID]
    local mapZone = currentMapID and ZONE_BY_MAPID[currentMapID]
    local idName = idZone and idZone.name
    local mapName = mapZone and mapZone.name
    local inSeasonZone = idZone or mapZone or ZONE_BY_NAME[currentInstance]

    for _, reminder in ipairs(reminders) do
        -- One-time migration: stamp class/spec on old reminders
        if
            _migPending
            and not reminder.class
            and (IsPlayerSpell(reminder.spellID) or IsSpellKnown(reminder.spellID))
        then
            _migStamped = true
            reminder.class = playerClass
            if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
                local cfgID = C_ClassTalents.GetActiveConfigID()
                if cfgID and C_Traits and C_Traits.GetConfigInfo then
                    local cfgInfo = C_Traits.GetConfigInfo(cfgID)
                    if cfgInfo and cfgInfo.treeIDs then
                        for _, treeID in ipairs(cfgInfo.treeIDs) do
                            local nodes = C_Traits.GetTreeNodes(treeID)
                            if nodes then
                                for _, nodeID in ipairs(nodes) do
                                    local ni = C_Traits.GetNodeInfo(cfgID, nodeID)
                                    if ni and ni.entryIDs then
                                        for _, eID in ipairs(ni.entryIDs) do
                                            local ei = C_Traits.GetEntryInfo(cfgID, eID)
                                            if ei and ei.definitionID then
                                                local di = C_Traits.GetDefinitionInfo(ei.definitionID)
                                                if di and di.spellID == reminder.spellID then
                                                    if ni.isClassNode then
                                                        reminder.talentSource = "class"
                                                    else
                                                        reminder.talentSource = "spec"
                                                        reminder.specID = playerSpecID
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Skip reminders for a different class
        if reminder.class and reminder.class ~= playerClass then
            -- not this class
        elseif reminder.talentSource == "spec" and reminder.specID and reminder.specID ~= playerSpecID then
            -- not this spec
        else
            -- The reminder's zones as saved, read on every pass so an edit on the
            -- options page applies at once. One saved with the single zone of an
            -- older version holds it in zoneName while it has no list.
            local zoneMatch = false
            local zns = reminder.zoneNames
            if zns and #zns > 0 then
                for index = 1, #zns do
                    local zn = zns[index]
                    if zn == idName or zn == mapName or zn == currentInstance then
                        zoneMatch = true
                        break
                    end
                end
            else
                local zn = reminder.zoneName
                zoneMatch = zn ~= nil and (zn == idName or zn == mapName or zn == currentInstance)
            end

            local hasTalent = IsPlayerSpell(reminder.spellID) or IsSpellKnown(reminder.spellID)

            if zoneMatch and not hasTalent then
                _missing[#_missing + 1] = {
                    texture = Tex(reminder.spellID) or 134400,
                    spellID = reminder.spellID,
                    label = reminder.spellName or "Unknown",
                }
            elseif not zoneMatch and hasTalent then
                local mode = NotNeededMode(reminder)
                if mode == "all" or (mode == "season" and inSeasonZone) then
                    _missing[#_missing + 1] = {
                        texture = Tex(reminder.spellID) or 134400,
                        spellID = reminder.spellID,
                        label = (reminder.spellName or "Unknown") .. " (N/N)",
                    }
                end
            end
        end
    end

    _migPending = false
    if _migStamped then
        _migStamped = false
        local stillNeeded = false
        for _, region in ipairs(reminders) do
            if not region.class then
                stillNeeded = true
                break
            end
        end
        if not stillNeeded then _migNeeded = false end
    end
end

-------------------------------------------------------------------------------
--  Refresh
-------------------------------------------------------------------------------
local _refreshQueued = false
local _lastRefresh = 0

local function Refresh()
    _refreshQueued = false
    _lastRefresh = GetTime()

    if not saved then return end

    -- Suppress while dead, mounted+flying, or in vehicle
    if
        UnitIsDeadOrGhost("player")
        or IsResting()
        or (IsMounted() and IsFlying())
        or UnitInVehicle("player")
    then
        HideIcons()
        return
    end

    HideIcons()
    Collect()

    if #_missing > 0 and talentIconAnchor then
        for index, m in ipairs(_missing) do
            ShowIcon(index, m)
        end
        LayoutIcons()
        CludesUI.SetElementVisibility(talentIconAnchor, true)
    end
end

local function QueueRefresh()
    if _refreshQueued then return end
    _refreshQueued = true
    local elapsed = GetTime() - _lastRefresh
    if elapsed >= 0.5 then
        C_Timer.After(0, function()
            _refreshQueued = false
            Refresh()
        end)
    else
        C_Timer.After(0.5 - elapsed, function()
            _refreshQueued = false
            Refresh()
        end)
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, evt, ...)
    if evt == "PLAYER_LOGIN" then
        -- Get DB reference from ABR
        saved = _G._CUABR_AceDB
        if not saved then return end

        -- Check if migration needed
        local reminders = GetReminders()
        if reminders then
            for _, region in ipairs(reminders) do
                if not region.class then
                    _migNeeded = true
                    break
                end
            end
        end

        -- Create anchor
        talentIconAnchor = CreateFrame("Frame", "EABR_TalentAnchor", UIParent)
        talentIconAnchor:SetSize(1, 1)
        talentIconAnchor:SetFrameStrata("MEDIUM")
        talentIconAnchor:SetFrameLevel(100)
        talentIconAnchor:EnableMouse(false)
        talentIconAnchor:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        talentIconAnchor:Show()
        CludesUI.SetElementVisibility(talentIconAnchor, false)

        -- Register ongoing events
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
        eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:RegisterEvent("SPELLS_CHANGED")
        eventFrame:RegisterEvent("PLAYER_DEAD")
        eventFrame:RegisterEvent("PLAYER_ALIVE")

        C_Timer.After(1, QueueRefresh)
        return
    end

    if evt == "PLAYER_ENTERING_WORLD" then
        QueueRefresh()
        C_Timer.After(0.5, QueueRefresh)
        return
    end

    if evt == "PLAYER_REGEN_DISABLED" then
        HideIcons()
        return
    end

    if evt == "PLAYER_REGEN_ENABLED" then
        QueueRefresh()
        return
    end

    if evt == "PLAYER_DEAD" or evt == "PLAYER_ALIVE" then
        QueueRefresh()
        return
    end

    -- Talent/zone change events
    if _migNeeded then
        if
            evt == "ZONE_CHANGED_NEW_AREA"
            or evt == "TRAIT_CONFIG_UPDATED"
            or evt == "PLAYER_TALENT_UPDATE"
            or evt == "PLAYER_SPECIALIZATION_CHANGED"
            or evt == "SPELLS_CHANGED"
        then
            _migPending = true
        end
    end

    QueueRefresh()
end)

-------------------------------------------------------------------------------
--  Public API (for options and unlock mode)
-------------------------------------------------------------------------------
_G._CUABR_TR_RequestRefresh = QueueRefresh
_G._CUABR_TR_HideIcons = HideIcons
