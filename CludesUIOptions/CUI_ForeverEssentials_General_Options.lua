if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_General_Options.lua
--  Builds the "General" page inside the Forever Essentials module: its
--  general quality of life features, one section each.
-------------------------------------------------------------------------------
if not CUI._ModuleNS["CludesUIForeverEssentials"] then return end -- module disabled: no options page

-------------------------------------------------------------------------------
--  NAME FORMAT: one place for every Name Format in the suite, as two checkbox
--  dropdowns over the same module rows: a box shows that part of the name, so
--  First Name alone = first names, Last Name alone = last names, both = Full
--  Name. A name always shows, so a row's last checked box stays checked.
--  Each row is a WRITE-THROUGH MIRROR, as on Global Settings > Textures: it
--  reads and writes the module's OWN keys and calls the module's own apply, so
--  nothing is stored here and each module's page shows the same setting. A row
--  over several keys (every unit frame text; raid and party) reads checked in
--  neither while they differ, as does a module set to Abbreviated or a
--  Character Count (its own page sets those), and a click sets them all. A
--  module that is off has no row.
-------------------------------------------------------------------------------
-- A saved Name Format as a row value ("full" = Full Name), and back (nil).
local function ModeOf(val) return (val == nil or val == "full") and "full" or val end
local function Stored(val) return (val ~= "full") and val or nil end
-- One value while every input agrees, "mixed" once two differ (nil: none yet).
local function Merge(acc, m)
    if acc == nil or acc == m then return m end
    return "mixed"
end

-- The rows in page order: { text, tooltip, get, set [, disabled, disabledTooltip] }.
local function NameFormatSources()
    local entries, MNS = {}, CUI.ModuleNS

    -- Unit Frames: every text slot (the list the Unit Frames options publish).
    -- The slots that show a name on a frame of ours that is shown (its frame
    -- source, as the Unit Frames pages test it) decide what it reads; a pick
    -- sets every slot, so a text switched to a name later follows it.
    local uf = MNS("CludesUIUnitFrames")
    local slots = uf and uf.db and uf.UF_NAME_FORMAT_SLOTS
    if slots then
        entries[#entries + 1] = {
            text = "Unit Frames",
            tooltip = "Player names in every unit frame text that shows a name.",
            get = function()
                local p, isShown, all = uf.db.profile, nil, nil
                for idx = 1, #slots do
                    local e = slots[idx]
                    local cfg = p[e.unit]
                    if cfg and uf.GetUnitFrameSource(e.unit) == "cui" then
                        local m = ModeOf(cfg[e.format])
                        -- A power text without Custom never names, so it does
                        -- not count toward the fallback either.
                        if not e.power or cfg[e.content] == "custom" then all = Merge(all, m) end
                        -- A power text shows while its position is set and, under a
                        -- stock style, Hide Power Bar leaves it (ApplyPowerPercentText).
                        local powerShown = not e.power
                            or (
                                (cfg[e.power] or "none") ~= "none"
                                and not (
                                    uf.UF_Blizz()
                                    and uf.UF_IsMainSettings(cfg)
                                    and uf.UF_StockHidesPower(cfg)
                                )
                            )
                        if
                            uf.UF_ContentShowsName(cfg[e.content], cfg[e.custom])
                            and (not e.btb or cfg.bottomTextBar)
                            and powerShown
                        then
                            isShown = Merge(isShown, m)
                        end
                    end
                end
                return isShown or all or "full"
            end,
            set = function(val)
                local p, mode = uf.db.profile, Stored(val)
                for idx = 1, #slots do
                    local cfg = p[slots[idx].unit]
                    if cfg then cfg[slots[idx].format] = mode end
                end
                uf.ReloadFrames()
            end,
        }
    end

    -- Raid Frames: the raid key, and the party's while its Text Display is
    -- unsynced (Raid Frames saves "full"; an unset party key reads the raid's).
    local rf = MNS("CludesUIRaidFrames")
    if rf and rf.db then
        local function partyOwn() return rf._IsPartySectionCustom("textDisplay") end
        entries[#entries + 1] = {
            text = "Raid & Party Frames",
            tooltip = "Player names on raid and party frames.",
            get = function()
                local p = rf.db.profile
                local m = ModeOf(p.nameFormat)
                if partyOwn() and p.party_nameFormat ~= nil then m = Merge(m, ModeOf(p.party_nameFormat)) end
                return m
            end,
            set = function(val)
                local p = rf.db.profile
                p.nameFormat = val
                -- A party key left from an unsync is set too, or a later unsync
                -- would bring the old value back.
                if partyOwn() or p.party_nameFormat ~= nil then p.party_nameFormat = val end
                rf._BumpAbsorbGen()
                rf.ReloadFrames()
                rf.ReloadPartyFrames()
            end,
        }
    end

    -- Nameplates: the enemy name, Target of Target and Custom slots showing a name
    -- or a target (a pick sets every slot's key, so a text moved later keeps it),
    -- then the friendly players.
    local np = MNS("CludesUINameplates")
    if np and np.db then
        local slotKeys, formatKey = np.textSlotKeys, {}
        for _, slot in ipairs(slotKeys) do
            formatKey[slot] = slot .. "NameFormat"
        end
        entries[#entries + 1] = {
            text = "Enemy Player Nameplates",
            tooltip = "Enemy player names on nameplates, and their targets when they are players.",
            get = function()
                local p, m = np.db.profile, nil
                local nameSlot, totSlot = np.FindNameSlot(), np._npToTSlot
                if nameSlot then m = ModeOf(p[formatKey[nameSlot]]) end
                if totSlot then m = Merge(m, ModeOf(p[formatKey[totSlot]])) end
                for idx = 1, #slotKeys do
                    local slot = slotKeys[idx]
                    local parsed = p[slot] == "custom" and np.NP_CustomParse(slot)
                    if parsed and (parsed.has.name or parsed.has.target) then
                        m = Merge(m, ModeOf(p[formatKey[slot]]))
                    end
                end
                if not m then
                    for idx = 1, #slotKeys do
                        m = Merge(m, ModeOf(p[formatKey[slotKeys[idx]]]))
                    end
                end
                return m or "full"
            end,
            set = function(val)
                local p, mode = np.db.profile, Stored(val)
                for idx = 1, #slotKeys do
                    p[formatKey[slotKeys[idx]]] = mode
                end
                np.RefreshAllSettings()
            end,
        }
        entries[#entries + 1] = {
            text = "Friendly Player Nameplates",
            tooltip = "Friendly player names on nameplates, in both modes.",
            disabled = function() return np.db.profile.showFriendlyPlayers == false end,
            disabledTooltip = "Show CludesUI Friendly Player Nameplates",
            get = function() return ModeOf(np.db.profile.friendlyNameFormat) end,
            set = function(val)
                np.db.profile.friendlyNameFormat = Stored(val)
                np.NP_SyncFriendlyNameFormat()
            end,
        }
    end

    -- Damage Meters: one key for every window.
    local dm = MNS("CludesUIDamageMeters")
    if dm and _G._CUDM_DB then
        local DMCfg = dm.EDM.DB
        entries[#entries + 1] = {
            text = "Damage Meters",
            tooltip = "Player names on the meter bars.",
            get = function() return ModeOf(DMCfg().nameFormat) end,
            set = function(val)
                DMCfg().nameFormat = Stored(val)
                dm.RefreshNames()
            end,
        }
    end

    -- The threat meter (this module; account-wide like its other settings).
    local TM = CUI._ThreatMeter
    entries[#entries + 1] = {
        text = "Threat Meter",
        tooltip = "Player names on the threat meter, for all your characters.",
        disabled = function() return not TM.Get("enabled") end,
        disabledTooltip = "Threat Meter",
        get = function() return ModeOf(TM.Get("nameFormat")) end,
        set = function(val)
            TM.Cfg().nameFormat = Stored(val)
            TM.ApplyStyle()
        end,
    }
    return entries
end

_G._CUI_BuildForeverGeneralPage = function(page, hostFrame, yOffset)
    local W = CUI.Widgets
    local SU, CS, CT = CUI._SpellUprank, CUI._ClassicSpellbook, CUI._ClassicTalents
    local MT = CUI._MapTravel
    local cursorY = yOffset
    local _, height, heading
    hostFrame._showRowDivider = true

    ---------------------------------------------------------------------------
    --  GENERAL: Auto Uprank Spells on Bars | Classic Windows (the vanilla
    --  spellbook and talent window as one checkbox dropdown), then Most
    --  Valuable Quest Reward (CludesUIForeverEssentials_QuestRewards.lua) |
    --  Gathering Skill in Tooltips (CludesUIForeverEssentials_GatherSkill.lua,
    --  its Minimap row in the cog), then Auto Summon Pet | Favorites per
    --  Character. Every control reads and writes its feature's own key and
    --  runs that feature's own apply.
    ---------------------------------------------------------------------------
    local QR, GS = CUI._QuestRewards, CUI._GatherSkill
    _, height = W:SectionHeader(hostFrame, "GENERAL", cursorY)
    cursorY = cursorY - height

    local CW_LABEL = "Classic Windows"
    local cwItems = {
        {
            key = "spellbook",
            label = "Classic Spellbook",
            tooltip = "Your spellbook key and the micro menu's Spellbook button open the vanilla spellbook.",
            read = function() return CS.Get("enabled") end,
            write = function(val)
                CS.Cfg().enabled = val
                CS.Apply()
            end,
        },
        {
            key = "talents",
            label = "Classic Talents",
            tooltip = "Your talents key and the micro menu's Talents button open the vanilla talent window.",
            read = function() return CT.Get("enabled") end,
            write = function(val)
                CT.Cfg().enabled = val
                CT.Apply()
            end,
        },
    }
    -- Global search sees row labels and tooltips only, so this row's entry,
    -- registered before the row (the index keeps the first one), carries the
    -- dropdown's names as search text; it is never shown.
    if CUI._RegisterSearchEntry then
        local words = {}
        for idx = 1, #cwItems do
            local s = cwItems[idx].label
            words[#words + 1] = s
            local loc = CUI.L(s)
            if loc ~= s then words[#words + 1] = loc end
        end
        local labelLoc = CUI.L(CW_LABEL)
        CUI._RegisterSearchEntry(
            CW_LABEL,
            labelLoc ~= CW_LABEL and labelLoc or nil,
            table.concat(words, " "),
            CUI._buildingModule,
            CUI._buildingPage,
            hostFrame._currentSection and hostFrame._currentSection._sectionName
        )
    end

    local generalRow
    generalRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Auto Uprank Spells on Bars",
        tooltip = "Swaps new spell ranks, yours and your pet's, onto your action bars.",
        getValue = function() return SU.Get("enabled") end,
        setValue = function(val)
            SU.Cfg().enabled = val
            SU.Apply()
        end,
    }, {
        type = "label",
        text = CW_LABEL,
        tooltip = "Choose which windows open in their classic version.",
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        local region = generalRow._rightRegion
        local byKey = {}
        for idx = 1, #cwItems do
            byKey[cwItems[idx].key] = cwItems[idx]
        end
        local cwDD, cwRefresh = CUI.BuildVisOptsCBDropdown(
            region,
            210,
            region:GetFrameLevel() + 2,
            cwItems,
            function(key) return byKey[key].read() end,
            function(key, val) byKey[key].write(val) end
        )
        CUI.PanelPP.Point(cwDD, "RIGHT", region, "RIGHT", -20, 0)
        region._control = cwDD
        region._lastInline = nil
        CUI.RegisterWidgetRefresh(cwRefresh)
    end

    local rewardRow
    rewardRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Most Valuable Quest Reward",
        tooltip = "Among a quest's reward choices, a money bag marks the one that sells for most, its count included.",
        getValue = function() return QR.Get("enabled") end,
        setValue = function(val)
            QR.Cfg().enabled = val
            QR.Apply()
        end,
    }, {
        type = "toggle",
        text = "Gathering Skill in Tooltips",
        tooltip = "Adds the skill a herb or ore node needs to its tooltip, colored by your chance to raise your skill there.",
        getValue = function() return GS.Get("enabled") end,
        setValue = function(val)
            GS.Cfg().enabled = val
            GS.Apply()
            CUI:RefreshPage() -- the cog's disabled state
        end,
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        CUI.BuildInlineCog(rewardRow._rightRegion, {
            title = "Gathering Skill in Tooltips",
            rows = {
                {
                    type = "toggle",
                    label = "Minimap",
                    tooltip = "Also adds the required skill to herb and ore names on the minimap.",
                    get = function() return GS.Get("minimap") end,
                    set = function(val)
                        GS.Cfg().minimap = val
                        GS.Apply()
                    end,
                },
            },
            disabled = function() return not GS.Get("enabled") end,
            disabledTooltip = "Gathering Skill in Tooltips",
        })
    end

    -- Auto Summon Pet | Favorites per Character
    -- (CludesUIForeverEssentials_PetSummon.lua), while the Pet Journal exists.
    local PS = CUI._PetSummon
    if PS and C_PetJournal then
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Auto Summon Pet",
            tooltip = "Brings a random favorite pet back after loading screens, flights and deaths; a pet you dismiss stays away.",
            getValue = function() return PS.Get("enabled") end,
            setValue = function(val)
                PS.Cfg().enabled = val
                PS.Apply(val) -- turning it on also ends an earlier dismissal
                CUI:RefreshPage() -- Favorites per Character's disabled state
            end,
        }, {
            type = "toggle",
            text = "Favorites per Character",
            tooltip = "Pick this character's favorites from a pet's right-click menu in the Pet Journal.",
            disabled = function() return not PS.Get("enabled") end,
            disabledTooltip = "Auto Summon Pet",
            -- This character's own setting, read without creating its table.
            getValue = function()
                local chars, unitGuid = PS.Get("chars"), UnitGUID("player")
                return chars ~= nil
                    and unitGuid ~= nil
                    and chars[unitGuid] ~= nil
                    and chars[unitGuid].own == true
            end,
            setValue = function(val)
                local unitGuid = UnitGUID("player")
                if not unitGuid then return end
                local rowConf = PS.Cfg()
                rowConf.chars = rowConf.chars or {}
                rowConf.chars[unitGuid] = rowConf.chars[unitGuid] or {}
                rowConf.chars[unitGuid].own = val or nil
                PS.RefreshJournal()
            end,
        })
        cursorY = cursorY - height
    end

    -- Known Levels: a player's level the game hides as ?? (10+ levels above
    -- you), from when it could last be read (CludesUIForeverEssentials_PvP.lua
    -- keeps it, PvP on or off).
    local pvp = CUI._PvP
    if pvp then
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Known Levels Instead of ??",
            tooltip = "Unit frames, nameplates and tooltips show ?? for anything 10 or more levels above you. This shows the real level instead: the one the game still gives addons, or for a player whose level is hidden, the level they had when you last saw it (or a groupmate's PvP sharing sent it).",
            getValue = function() return pvp.Get("knownLevels") end,
            setValue = function(val) pvp.Cfg().knownLevels = val end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  NAME FORMAT (while a module with a Name Format is on)
    ---------------------------------------------------------------------------
    local sources = NameFormatSources()
    if #sources > 0 then
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "NAME FORMAT", cursorY)
        cursorY = cursorY - height
        -- Placeholder dropdowns keep the labels, tooltips and search entries; the
        -- checkbox dropdowns replace them (DualRow only builds plain widgets).
        local function Slot(textValue, tooltip)
            return {
                type = "dropdown",
                text = textValue,
                tooltip = tooltip,
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function() return "__placeholder" end,
                setValue = function() end,
            }
        end
        local row
        row, height = W:DualRow(
            hostFrame,
            cursorY,
            Slot(
                "First Name",
                "Checked modules show players' first names. A module checked in both lists shows the full name."
            ),
            Slot(
                "Last Name",
                "Checked modules show players' last names. A module checked in both lists shows the full name."
            )
        )
        cursorY = cursorY - height
        if not CUI._prebuilding then
            local Pix = CUI.PanelPP
            -- A module that is switched off stays greyed out and out of "All".
            local itemList = {}
            for idx = 1, #sources do
                local source = sources[idx]
                itemList[idx] = {
                    key = idx,
                    label = source.text,
                    tooltip = source.tooltip,
                    lockedFn = source.disabled,
                    excludeFromSummaryFn = source.disabled,
                    lockedTooltip = source.disabled and function()
                        return CUI.DisabledTooltip(source.disabledTooltip)
                    end or nil,
                }
            end
            -- Whether a row value shows that part of the name ("mixed" shows neither box).
            local function Has(m, part) return m == part or m == "full" end
            local function List(region, part)
                local other = (part == "first") and "last" or "first"
                if region._control then region._control:Hide() end
                -- 260 wide: room for the longest row label (Friendly Player
                -- Nameplates and its translations); longer ones end in "...".
                local dropdown, refresh = CUI.BuildVisOptsCBDropdown(
                    region,
                    260,
                    region:GetFrameLevel() + 2,
                    itemList,
                    function(idx) return Has(sources[idx].get(), part) end,
                    function(idx, on)
                        local theirs = Has(sources[idx].get(), other)
                        -- A name always shows: unchecking the last box keeps it.
                        if not (on or theirs) then return end
                        sources[idx].set((on and theirs) and "full" or (on and part or other))
                        -- The other list reads the new value too.
                        CUI:RefreshPage()
                    end
                )
                Pix.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
                region._control = dropdown
                region._lastInline = nil
                CUI.RegisterWidgetRefresh(refresh)
            end
            List(row._leftRegion, "first")
            List(row._rightRegion, "last")
        end
    end

    ---------------------------------------------------------------------------
    --  WORLD MAP (Fade Map While Moving | Show the Game Behind the Map, then
    --  Reveal Unexplored Areas with its color in the cog | Show Zone Levels,
    --  then Show Map Markers with its sets in the cog:
    --  CludesUIForeverEssentials_MapTravel.lua | Show Fishing Skill:
    --  CludesUIForeverEssentials_ZoneLevels.lua)
    ---------------------------------------------------------------------------
    local MR = CUI._MapReveal
    local ZL = CUI._ZoneLevels
    local function revealOff() return not MR.Get("enabled") end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height
    _, height = W:SectionHeader(hostFrame, "WORLD MAP", cursorY)
    cursorY = cursorY - height

    -- Fade Map While Moving | Show the Game Behind the Map. Runtime in
    -- CludesUIForeverEssentials_MapFade.lua.
    local MF = CUI._MapFade
    local function SetFade(key, val)
        MF.Cfg()[key] = val
        MF.Apply()
    end

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Fade Map While Moving",
        tooltip = "The world map fades while you move and comes back when you stop or hover it.",
        getValue = function() return MF.Get("enabled") end,
        setValue = function(val) SetFade("enabled", val) end,
    }, {
        type = "toggle",
        text = "Show the Game Behind the Map",
        tooltip = "Lightens the black behind the maximized world map.",
        getValue = function() return MF.Get("dim") end,
        setValue = function(val) SetFade("dim", val) end,
    })
    cursorY = cursorY - height

    local revealRow
    revealRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Reveal Unexplored Areas",
        tooltip = "Shows the parts of the world map you have not explored yet. Use the cog to pick their color.",
        getValue = function() return MR.Get("enabled") end,
        setValue = function(val)
            MR.Cfg().enabled = val
            MR.Apply()
            CUI:RefreshPage() -- the cog's disabled state
        end,
    }, {
        type = "toggle",
        text = "Show Zone Levels",
        tooltip = "Shows the level range of the zone you hover on a continent of the world map, under its name, colored by difficulty.",
        getValue = function() return ZL.Get("enabled") end,
        setValue = function(val)
            ZL.Cfg().enabled = val
            ZL.Apply()
        end,
    })
    cursorY = cursorY - height

    local markersRow
    markersRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Map Markers",
        tooltip = "Shows boats, zeppelins, dungeon entrances, flight points and zone exits on the world map; click one to link it in chat.",
        getValue = function() return MT.Get("enabled") end,
        setValue = function(val)
            MT.Cfg().enabled = val
            MT.Apply()
            CUI:RefreshPage() -- the cog's disabled state
        end,
    }, {
        type = "toggle",
        text = "Show Fishing Skill",
        tooltip = "Shows the fishing skill a zone needs under its name on the world map: red, too low; yellow, fish still get away; green, none do.",
        getValue = function() return ZL.Get("fishing") end,
        setValue = function(val)
            ZL.Cfg().fishing = val
            ZL.Apply()
        end,
    })
    cursorY = cursorY - height

    -- Quest Area Tint (CludesUIForeverEssentials_QuestAreaTint.lua) | Zone Info
    -- (CludesUIForeverEssentials_ZoneInfo.lua).
    local QT = CUI._QuestAreaTint
    local ZI = CUI._ZoneInfo
    if QT then
        local zoneCfg = CUI.BlankRowCfg()
        if ZI then
            zoneCfg = {
                type = "toggle",
                text = "Zone Info",
                tooltip = "A panel beside the world map for the zone it shows: its levels against yours, its dungeons, the fishing skill it needs, its flight masters, boats and roads, and the herbs and ore that grow there.",
                getValue = function() return ZI.Get("enabled") end,
                setValue = function(val)
                    ZI.Cfg().enabled = val and true or false
                    ZI.Apply()
                    CUI:RefreshPage()
                end,
            }
        end
        local tintRow
        tintRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Quest Area Tint",
            tooltip = "Colors the quest objective areas on the world map, with a glowing edge. The colors need a full game restart the first time.",
            getValue = function() return QT.Get("enabled") end,
            setValue = function(val)
                QT.Cfg().enabled = val and true or false
                QT.Apply()
                CUI:RefreshPage()
            end,
        }, zoneCfg)
        cursorY = cursorY - height
        if ZI and not CUI._prebuilding then
            local function ZTog(key, label)
                return {
                    type = "toggle",
                    label = label,
                    get = function() return ZI.Get(key) == true end,
                    set = function(val)
                        ZI.Cfg()[key] = val
                        ZI.Apply()
                    end,
                }
            end
            CUI.BuildInlineCog(tintRow._rightRegion, {
                disabled = function() return not ZI.Get("enabled") end,
                disabledTooltip = "Zone Info",
                title = "Zone Info",
                rows = {
                    ZTog("dungeons", "Dungeons & Raids"),
                    ZTog("fishing", "Fishing"),
                    ZTog("travel", "Travel"),
                    ZTog("gathering", "Herbs & Mining"),
                    ZTog("onlyMyProfessions", "Only My Gathering Skills"),
                },
            })
        end
        if not CUI._prebuilding then
            CUI.BuildInlineCog(tintRow._leftRegion, {
                disabled = function() return not QT.Get("enabled") end,
                disabledTooltip = "Quest Area Tint",
                title = "Quest Area Tint",
                rows = {
                    {
                        type = "dropdown",
                        label = "Quest Area Color",
                        values = { blue = "Blue", violet = "Violet", green = "Green", gold = "Gold", red = "Red" },
                        order = { "blue", "violet", "green", "gold", "red" },
                        get = function() return QT.Get("color") end,
                        set = function(val)
                            QT.Cfg().color = val
                            QT.Apply()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Quest Area Opacity",
                        min = 10,
                        max = 90,
                        step = 5,
                        get = function() return math.floor(QT.Get("fill") * 100 + 0.5) end,
                        set = function(val)
                            QT.Cfg().fill = val / 100
                            QT.Apply()
                        end,
                    },
                },
            })
        end
    end
    if not CUI._prebuilding then
        CUI.BuildInlineCog(revealRow._leftRegion, {
            title = "Reveal Unexplored Areas Settings",
            rows = {
                {
                    type = "colorpicker",
                    label = "Unexplored Color",
                    hasAlpha = true,
                    tooltip = "Tints the areas you have not explored yet. White shows them as they are.",
                    get = function()
                        local color = MR.Get("color")
                        return color.r, color.g, color.b, color.a
                    end,
                    set = function(red, green, blue, a)
                        MR.Cfg().color = { r = red, g = green, b = blue, a = a or 1 }
                        MR.Apply()
                    end,
                },
            },
            disabled = revealOff,
            disabledTooltip = "Reveal Unexplored Areas",
        })
    end

    -- Map Markers: one toggle; the cog picks the sets, all shown until turned
    -- off.
    if not CUI._prebuilding then
        local function setRow(labelText, tooltip, key)
            return {
                type = "toggle",
                label = labelText,
                tooltip = tooltip,
                get = function() return MT.Get(key) end,
                set = function(val)
                    MT.Cfg()[key] = val
                    MT.Apply()
                end,
            }
        end
        local rowList = {
            setRow(
                "Transports",
                "Boats, zeppelins and the tram, from the world map down, with where each one goes when you hover it.",
                "transports"
            ),
            setRow(
                "Zone Exits",
                "On zone maps, an arrow on each road out of the zone, pointing to the zone it leads to.",
                "exits"
            ),
            setRow(
                "Instance Entrances",
                "Dungeon and raid entrances, on continent and zone maps; hover one for its name.",
                "instances"
            ),
            setRow(
                "Flight Points",
                "On zone maps, the flight masters, those you have not found yet included.",
                "flights"
            ),
        }
        CUI.BuildInlineCog(markersRow._leftRegion, {
            title = "Map Markers",
            rows = rowList,
            disabled = function() return not MT.Get("enabled") end,
            disabledTooltip = "Show Map Markers",
        })
    end

    ---------------------------------------------------------------------------
    --  ACTION BAR PROFILES
    ---------------------------------------------------------------------------
    local AP = CUI._ActionBarProfiles
    if AP then
        local rowConf = AP.Cfg()
        local nameList = AP.Names()
        local values, sequence = {}, {}
        for _, num in ipairs(nameList) do
            values[num] = num
            sequence[#sequence + 1] = num
        end
        if #nameList == 0 then
            values[""] = "None saved"
            sequence[1] = ""
        end
        if not values[rowConf.selected or ""] then rowConf.selected = nameList[1] or "" end
        local function Rebuild()
            C_Timer.After(0.1, function() CUI:RefreshPage(true) end)
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "ACTION BAR PROFILES", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Save Your Bars",
            inputWidth = 140,
            inputStyle = "popup",
            placeholder = "Profile name",
            tooltip = "Saves every action bar slot under this name, for any character of your class on this account. /cbars save <name> does the same.",
            getValue = function() return "" end,
            setValue = function(textValue)
                AP.Save(textValue)
                rowConf.selected = (textValue or ""):match("^%s*(.-)%s*$")
                Rebuild()
            end,
        }, {
            type = "toggle",
            text = "Include Keybinds",
            tooltip = "Also save and load your keybinds with the bars.",
            getValue = function() return AP.Get("bindings") end,
            setValue = function(val) rowConf.bindings = val and true or false end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Profile",
            values = values,
            order = sequence,
            getValue = function() return rowConf.selected or "" end,
            setValue = function(val) rowConf.selected = val end,
        }, {
            type = "labeledButton",
            text = "Load It",
            buttonText = "Load",
            width = 90,
            tooltip = "Puts the profile on your bars. Spells you have not learned and items you do not carry are skipped. Out of combat only.",
            onClick = function()
                if rowConf.selected and rowConf.selected ~= "" then AP.Load(rowConf.selected) end
            end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Delete It",
            buttonText = "Delete",
            width = 90,
            onClick = function()
                if rowConf.selected and rowConf.selected ~= "" then
                    AP.Delete(rowConf.selected)
                    rowConf.selected = nil
                    Rebuild()
                end
            end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  LOOT SPARKLES
    ---------------------------------------------------------------------------
    local LS = CUI._LootSparkles
    if LS then
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "LOOT SPARKLES", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Quest Item Sparkles",
            tooltip = "Keeps the game's sparkle on lootable quest items, even after a graphics preset turns it off. Your outline mode is left as you set it. Switching this off takes effect after restarting the game.",
            getValue = function() return LS.Get("enabled") end,
            setValue = function(val) LS.SetEnabled(val) end,
        }, { type = "label", text = "Turning it off needs a game restart." })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  PLAYER HISTORY
    ---------------------------------------------------------------------------
    local PH = CUI._PlayerHistory
    if PH then
        local function Set(key, val)
            PH.Cfg()[key] = val
            PH.Apply()
        end
        local function pOff() return not PH.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "PLAYER HISTORY", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Player History",
            tooltip = "Remembers the players you group with on this computer: how often, the dungeons and raids together, and your last sessions. /chistory lists them. Right-click a player for Player Note to tag them and write a note.",
            getValue = function() return not pOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Record Chats",
            disabled = pOff,
            tooltip = "Also keeps your last whispers and group chat lines with each player.",
            getValue = function() return PH.Get("chats") end,
            setValue = function(val) Set("chats", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Forget After (days)",
            min = 7,
            max = 365,
            step = 1,
            isPercent = false,
            disabled = pOff,
            getValue = function() return PH.Get("days") end,
            setValue = function(val) PH.Cfg().days = math.floor(val + 0.5) end,
        }, {
            type = "toggle",
            text = "Notes on Tooltips",
            getValue = function() return PH.Get("tooltip") end,
            setValue = function(val) PH.Cfg().tooltip = val and true or false end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Player History",
            buttonText = "Open",
            width = 90,
            onClick = function() PH.Show() end,
        }, {
            type = "labeledButton",
            text = "Clear History (keeps notes)",
            buttonText = "Clear",
            width = 90,
            onClick = function() PH.Clear("history") end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  CREATURE SCOUT
    ---------------------------------------------------------------------------
    local SC = CUI._Scout
    if SC then
        local function Set(key, val)
            SC.Cfg()[key] = val
            SC.Apply()
        end
        local function sOff() return not SC.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "CREATURE SCOUT", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Creature Scout",
            tooltip = "Adds what a creature can do to its tooltip: the spells it uses, its armor and how much of your physical damage that takes, and what it is immune to or resists.",
            getValue = function() return not sOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Creature Abilities",
            disabled = sOff,
            tooltip = "The spells a creature is known to use, with their range and cast time.",
            getValue = function() return SC.Get("abilities") end,
            setValue = function(val) Set("abilities", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Armor and Damage Taken",
            disabled = sOff,
            tooltip = "Its armor (estimated from its level when not known) and how much of your physical damage it stops.",
            getValue = function() return SC.Get("armor") end,
            setValue = function(val) Set("armor", val and true or false) end,
        }, {
            type = "toggle",
            text = "Immunities and Resistances",
            disabled = sOff,
            tooltip = "The effects and spell schools it is immune to, and the schools it resists.",
            getValue = function() return SC.Get("immunities") end,
            setValue = function(val) Set("immunities", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Details Key",
            disabled = sOff,
            tooltip = "Hold it over a creature to read what each of its abilities does.",
            values = { ctrl = "Ctrl", alt = "Alt", shift = "Shift" },
            order = { "ctrl", "alt", "shift" },
            getValue = function() return SC.Get("key") end,
            setValue = function(val) Set("key", val) end,
        }, {
            type = "toggle",
            text = "Key Hint",
            disabled = sOff,
            tooltip = "A line on the tooltip saying which key shows the details.",
            getValue = function() return SC.Get("hint") end,
            setValue = function(val) Set("hint", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Pet Family",
            disabled = sOff,
            tooltip = "Hunters see a beast's pet family, its attack speed and whether they can tame it yet.",
            getValue = function() return SC.Get("family") end,
            setValue = function(val) Set("family", val and true or false) end,
        }, {
            type = "toggle",
            text = "Also in Dungeons",
            disabled = sOff,
            tooltip = "Shows it inside dungeons and raids too.",
            getValue = function() return SC.Get("instances") end,
            setValue = function(val) Set("instances", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  CHAT ZONES
    ---------------------------------------------------------------------------
    local CZ = CUI._ChatZones
    if CZ then
        local function Set(key, val)
            CZ.Cfg()[key] = val
            CZ.Apply()
        end
        local function zOff() return not CZ.Get("enabled") end
        local function chatOff() return zOff() or not CZ.Get("chat") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "CHAT ZONES", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Chat Zones",
            tooltip = "Shows where other players are: in front of their chat messages, and on Group Finder listings. The game never says where a stranger is, so a player shows once they turn up in the Group Finder, your guild, your friends, your group or a /who.",
            getValue = function() return not zOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Zones in Chat",
            disabled = zOff,
            tooltip = "The speaker's zone in front of their message in chat channels, guild chat and whispers.",
            getValue = function() return CZ.Get("chat") end,
            setValue = function(val) Set("chat", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Level",
            disabled = chatOff,
            tooltip = "Adds their level after the zone.",
            getValue = function() return CZ.Get("level") end,
            setValue = function(val) Set("level", val and true or false) end,
        }, {
            type = "toggle",
            text = "Class Color",
            disabled = chatOff,
            tooltip = "The zone in the speaker's class color. Off, it is grey.",
            getValue = function() return CZ.Get("classColor") end,
            setValue = function(val) Set("classColor", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Where? on Whispers",
            disabled = chatOff,
            tooltip = "A [Where?] link after a whisper from someone whose zone is not known. Click it to look them up with /who; their next messages show their zone.",
            getValue = function() return CZ.Get("where") end,
            setValue = function(val) Set("where", val and true or false) end,
        }, {
            type = "toggle",
            text = "Zones in Group Finder",
            disabled = zOff,
            tooltip = "The leader's zone on each Group Finder listing, and every member's zone when you hover one.",
            getValue = function() return CZ.Get("finder") end,
            setValue = function(val) Set("finder", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Forget After (minutes)",
            min = 1,
            max = 60,
            step = 1,
            isPercent = false,
            disabled = zOff,
            tooltip = "A zone older than this is no longer shown, since the player has likely moved on.",
            getValue = function() return CZ.Get("maxAge") end,
            setValue = function(val) CZ.Cfg().maxAge = math.floor(val + 0.5) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    return math.abs(cursorY)
end
