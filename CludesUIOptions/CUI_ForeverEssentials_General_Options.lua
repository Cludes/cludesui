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
    --  SIMPLIFIED STATS (item tooltips)
    ---------------------------------------------------------------------------
    local SS = CUI._SimplifiedStats
    if SS then
        local function Set(keyName, val)
            SS.Cfg()[keyName] = val
            CUI:RefreshPage() -- update the dependent rows' disabled state
        end
        local function shortenOff() return not SS.Get("shorten") end
        local function colorsOff() return not SS.Get("colors") end

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "SIMPLIFIED STATS", cursorY)
        cursorY = cursorY - height

        -- Shorten Equip Lines | Color Stats
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Shorten Equip Lines",
            tooltip = "Shortens Equip: and Set: stat lines on item tooltips to +X Stat.",
            getValue = function() return SS.Get("shorten") end,
            setValue = function(val) Set("shorten", val) end,
        }, {
            type = "toggle",
            text = "Color Stats",
            tooltip = "Colors each stat name on item tooltips, enchants included, and its number per Number Color.",
            getValue = function() return SS.Get("colors") end,
            setValue = function(val) Set("colors", val) end,
        })
        cursorY = cursorY - height

        -- Merge Equal Spell Power | Number Color
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Merge Equal Spell Power",
            tooltip = "Shows equal spell damage and healing as one Spell Power line.",
            disabled = shortenOff,
            disabledTooltip = "Shorten Equip Lines",
            getValue = function() return SS.Get("merge") end,
            setValue = function(val) Set("merge", val) end,
        }, {
            type = "dropdown",
            text = "Number Color",
            disabled = colorsOff,
            disabledTooltip = "Color Stats",
            values = { signed = "Green / Red", stat = "Stat Color", line = "Line Color" },
            order = { "signed", "stat", "line" },
            getValue = function() return SS.Get("numColor") end,
            setValue = function(val) SS.Cfg().numColor = (val ~= "signed") and val or nil end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  ACTIVE STANCE, FORM, ASPECT & AURA
    ---------------------------------------------------------------------------
    local AF = CUI._ActiveForm
    if AF then
        local function afOff() return not AF.Get("enabled") end
        local function AFSet(key, val)
            AF.Cfg()[key] = val
            AF.Apply()
        end
        local _, class = UnitClass("player")
        local labelText = class == "WARRIOR" and "Show Current Stance"
            or class == "DRUID" and "Show Current Form"
            or class == "PALADIN" and "Show Current Aura"
            or class == "HUNTER" and "Show Current Aspect"
            or "Show Current Stance / Form"

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "ACTIVE STANCE, FORM, ASPECT & AURA", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_ActiveForm", disabled = afOff, disabledTooltip = labelText }
        )

        _, height = CUI.BuildVisibilityRow(W, hostFrame, cursorY, {
            leftCfg = {
                type = "toggle",
                text = labelText,
                tooltip = "Shows an icon for your active stance, form, aura or aspect. Hidden while none is active.",
                getValue = function() return not afOff() end,
                setValue = CUI.SectionToggleSetValue(function(val) AFSet("enabled", val) end),
            },
            -- The table exists once it was turned on, and the row is greyed out
            -- while it is off, so viewing the page saves nothing.
            getStore = function() return afOff() and AF.Read() or AF.Cfg() end,
            caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
            disabledFn = afOff,
            disabledTooltip = labelText,
            onChanged = CUI.RequestVisibilityUpdate,
            onOptionChanged = CUI.RequestVisibilityUpdate,
        })
        cursorY = cursorY - height

        if not afOff() then
            -- Icon Size | Icon Zoom
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Icon Size",
                min = 16,
                max = 96,
                step = 1,
                isPercent = false,
                getValue = function() return AF.Get("iconSize") end,
                setValue = function(val) AFSet("iconSize", val) end,
            }, {
                type = "slider",
                text = "Icon Zoom",
                tooltip = "Crops the icon's edges.",
                min = 0,
                max = 25,
                step = 1,
                isPercent = false,
                getValue = function() return AF.Get("zoom") end,
                setValue = function(val) AFSet("zoom", val) end,
            })
            cursorY = cursorY - height

            -- Border Style | Border Size (+ color swatch)
            local texValues, texOrder = CUI.GetBorderTextureDropdown()
            local borderRow
            borderRow, height = W:DualRow(
                hostFrame,
                cursorY,
                {
                    type = "dropdown",
                    text = "Border Style",
                    values = texValues,
                    order = texOrder,
                    getValue = function() return AF.Get("borderTexture") end,
                    setValue = function(val)
                        local c = AF.Cfg()
                        c.borderTexture = val
                        c.borderTextureOffset, c.borderTextureOffsetY = nil, nil
                        local color = CUI.GetBorderStyleSelectDefaults(val)
                        c.borderR, c.borderG, c.borderB, c.borderA = color.r, color.g, color.b, 1
                        local defaultSize = CUI.GetBorderDefaultSize(nil, val)
                        if defaultSize then c.borderSize = defaultSize end
                        if c.borderSizePx then c.borderSizePx = false end
                        AF.Apply()
                        -- Rebuild: the offset row follows the Solid / textured pick.
                        CUI:RefreshPage(true)
                    end,
                },
                CUI.BorderPxSliderCfg({
                    text = "Border Size",
                    getStep = function() return AF.Get("borderSize") end,
                    setStep = function(val) AF.Cfg().borderSize = val end,
                    getTex = function() return AF.Get("borderTexture") end,
                    getPx = function() return AF.Read().borderSizePx end,
                    setPx = function(val) AF.Cfg().borderSizePx = val end,
                    apply = AF.Apply,
                })
            )
            cursorY = cursorY - height

            if not CUI._prebuilding then
                local region = borderRow._rightRegion
                local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
                    region,
                    region:GetFrameLevel() + 5,
                    function()
                        return AF.Get("borderR"), AF.Get("borderG"), AF.Get("borderB"), AF.Get("borderA")
                    end,
                    function(red, green, blue, a)
                        local c = AF.Cfg()
                        c.borderR, c.borderG, c.borderB, c.borderA = red, green, blue, a or 1
                        AF.Apply()
                    end,
                    true,
                    20
                )
                colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -12, 0)
                region._lastInline = colorSwatch
                CUI.RegisterWidgetRefresh(updateSwatch)
            end

            -- Width | Height Offset: only while a textured style is selected.
            local texKey = AF.Get("borderTexture")
            if texKey ~= "" and texKey ~= "solid" then
                local offL, offR = CUI.BorderOffsetRowCfgs({
                    getTex = function() return AF.Get("borderTexture") end,
                    getStep = function() return AF.Get("borderSize") end,
                    getSizeKey = function() return AF.Get("borderSize") end,
                    getPx = function() return AF.Read().borderSizePx end,
                    getX = function() return AF.Read().borderTextureOffset end,
                    setX = function(val) AF.Cfg().borderTextureOffset = val end,
                    getY = function() return AF.Read().borderTextureOffsetY end,
                    setY = function(val) AF.Cfg().borderTextureOffsetY = val end,
                    apply = AF.Apply,
                })
                _, height = W:DualRow(hostFrame, cursorY, offL, offR)
                cursorY = cursorY - height
            end
        end
    end

    ---------------------------------------------------------------------------
    --  TRACKING REMINDER
    ---------------------------------------------------------------------------
    local TR = CUI._TrackingReminder
    if TR then
        local function trOff() return not TR.Get("enabled") end
        local function TRSet(key, val)
            TR.Cfg()[key] = val
            TR.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "TRACKING REMINDER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_TrackingReminder", disabled = trOff, disabledTooltip = "Tracking Reminder" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Tracking Reminder",
            tooltip = "A row of icons for the tracking you know but have not turned on: Find Treasure, hunter tracks, Track Humanoids in Cat Form, Sense Undead, Sense Demons. Click one to turn it on. Hidden in combat.",
            getValue = function() return not trOff() end,
            setValue = function(val) TRSet("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Include Find Herbs and Minerals",
            disabled = trOff,
            getValue = function() return TR.Get("gathering") end,
            setValue = function(val) TRSet("gathering", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Icon Size",
            min = 16,
            max = 64,
            step = 1,
            isPercent = false,
            disabled = trOff,
            getValue = function() return TR.Get("iconSize") end,
            setValue = function(val) TRSet("iconSize", math.floor(val + 0.5)) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  SWING TIMER
    ---------------------------------------------------------------------------
    local STm = CUI._SwingTimer
    if STm then
        local function stOff() return not STm.Get("enabled") end
        local function STSet(key, val)
            STm.Cfg()[key] = val
            STm.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "SWING TIMER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_SwingTimer", disabled = stOff, disabledTooltip = "Swing Timer" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Swing Timer",
            tooltip = "A bar per weapon that fills to your next auto attack. The game sends each swing's real length, so haste and parry haste are already counted.",
            getValue = function() return not stOff() end,
            setValue = function(val) STSet("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Hide When Idle",
            disabled = stOff,
            tooltip = "Hide a bar when that weapon has not swung for a moment.",
            getValue = function() return STm.Get("hideIdle") end,
            setValue = function(val) STSet("hideIdle", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Off Hand Bar",
            disabled = stOff,
            getValue = function() return STm.Get("offHand") end,
            setValue = function(val) STSet("offHand", val and true or false) end,
        }, {
            type = "toggle",
            text = "Ranged Bar",
            disabled = stOff,
            getValue = function() return STm.Get("ranged") end,
            setValue = function(val) STSet("ranged", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Width",
            min = 80,
            max = 400,
            step = 1,
            isPercent = false,
            disabled = stOff,
            getValue = function() return STm.Get("width") end,
            setValue = function(val) STSet("width", math.floor(val + 0.5)) end,
        }, {
            type = "slider",
            text = "Height",
            min = 6,
            max = 30,
            step = 1,
            isPercent = false,
            disabled = stOff,
            getValue = function() return STm.Get("height") end,
            setValue = function(val) STSet("height", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  MANA BAR AND FIVE-SECOND RULE
    ---------------------------------------------------------------------------
    local DM = CUI._DruidMana
    if DM then
        local function dmOff() return not DM.Get("enabled") end
        local function DMSet(key, val)
            DM.Cfg()[key] = val
            DM.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "MANA BAR", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_ManaBar", disabled = dmOff, disabledTooltip = "Mana Bar" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Mana Bar",
            tooltip = "Shows a druid's mana while in Bear, Cat or another form that hides it.",
            getValue = function() return not dmOff() end,
            setValue = function(val) DMSet("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Five-Second Rule",
            disabled = dmOff,
            tooltip = "A line under the bar counts down five seconds after you spend mana, while spirit regen is paused.",
            getValue = function() return DM.Get("fiveSecond") end,
            setValue = function(val) DMSet("fiveSecond", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Always Show",
            disabled = dmOff,
            tooltip = "Show the bar all the time, for any class with mana, not only a druid in a form.",
            getValue = function() return DM.Get("always") end,
            setValue = function(val) DMSet("always", val and true or false) end,
        }, {
            type = "slider",
            text = "Width",
            min = 80,
            max = 400,
            step = 1,
            isPercent = false,
            disabled = dmOff,
            getValue = function() return DM.Get("width") end,
            setValue = function(val) DMSet("width", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  CONSUMABLE BAR
    ---------------------------------------------------------------------------
    local CB = CUI._ConsumableBar
    if CB then
        local function cbOff() return not CB.Get("enabled") end
        local function CBSet(key, val)
            CB.Cfg()[key] = val
            CB.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "CONSUMABLE BAR", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_ConsumableBar", disabled = cbOff, disabledTooltip = "Consumable Bar" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Consumable Bar",
            tooltip = "The consumables in your bags on a bar you can click, with how many you carry and their cooldowns. It works in combat; an item you run out of in a fight keeps its icon until the fight ends.",
            getValue = function() return not cbOff() end,
            setValue = function(val) CBSet("enabled", val and true or false) end,
        }, {
            type = "slider",
            text = "Icon Size",
            min = 16,
            max = 64,
            step = 1,
            isPercent = false,
            disabled = cbOff,
            getValue = function() return CB.Get("iconSize") end,
            setValue = function(val) CBSet("iconSize", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
        local cats = CB.Categories
        for idx = 1, #cats, 2 do
            local function Toggle(cfg)
                if not cfg then return { type = "label", text = "" } end
                return {
                    type = "toggle",
                    text = cfg.label,
                    disabled = cbOff,
                    getValue = function() return CB.Get(cfg.key) end,
                    setValue = function(val) CBSet(cfg.key, val and true or false) end,
                }
            end
            _, height = W:DualRow(hostFrame, cursorY, Toggle(cats[idx]), Toggle(cats[idx + 1]))
            cursorY = cursorY - height
        end
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Most Icons",
            min = 1,
            max = 30,
            step = 1,
            isPercent = false,
            disabled = cbOff,
            getValue = function() return CB.Get("maxIcons") end,
            setValue = function(val) CBSet("maxIcons", math.floor(val + 0.5)) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  RAID DEBUFFS
    ---------------------------------------------------------------------------
    local RD = CUI._RaidDebuffs
    if RD then
        local function rdOff() return not RD.Get("enabled") end
        local function RDSet(key, val)
            RD.Cfg()[key] = val
            RD.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "RAID DEBUFFS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_RaidDebuffs", disabled = rdOff, disabledTooltip = "Raid Debuffs" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Raid Debuffs",
            tooltip = "Icons on your enemy target for the raid debuffs you pick: bright while up with their time, dim while missing. Changes to the picks apply out of combat.",
            getValue = function() return not rdOff() end,
            setValue = function(val) RDSet("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Only in a Group",
            disabled = rdOff,
            getValue = function() return RD.Get("groupOnly") end,
            setValue = function(val) RDSet("groupOnly", val and true or false) end,
        })
        cursorY = cursorY - height
        local entries = RD.Debuffs
        for idx = 1, #entries, 2 do
            local function Toggle(d)
                if not d then return { type = "label", text = "" } end
                return {
                    type = "toggle",
                    text = d.label,
                    disabled = rdOff,
                    getValue = function() return RD.Get("pick_" .. d.key) end,
                    setValue = function(val) RDSet("pick_" .. d.key, val and true or false) end,
                }
            end
            _, height = W:DualRow(hostFrame, cursorY, Toggle(entries[idx]), Toggle(entries[idx + 1]))
            cursorY = cursorY - height
        end
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Icon Size",
            min = 16,
            max = 64,
            step = 1,
            isPercent = false,
            disabled = rdOff,
            getValue = function() return RD.Get("iconSize") end,
            setValue = function(val) RDSet("iconSize", math.floor(val + 0.5)) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  GEAR SETS
    ---------------------------------------------------------------------------
    local GS = CUI._GearSets
    if GS then
        local function gsOff() return not GS.Get("enabled") end
        local function GSSet(key, val)
            GS.Cfg()[key] = val
            GS.Apply()
        end
        local function SetChoices()
            local values, sequence = { [""] = "None" }, { "" }
            for _, s in ipairs(GS.List()) do
                values[s.name] = s.name
                sequence[#sequence + 1] = s.name
            end
            return values, sequence
        end
        local values, sequence = SetChoices()
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "GEAR SETS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_GearSets", disabled = gsOff, disabledTooltip = "Gear Sets" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Gear Sets Bar",
            tooltip = "Your equipment sets on a bar; click one to wear it. The set you are wearing is lit. Armour cannot change in combat, so a click in combat waits for the fight to end.",
            getValue = function() return not gsOff() end,
            setValue = function(val) GSSet("enabled", val and true or false) end,
        }, {
            type = "input",
            text = "Save What You Wear",
            inputWidth = 140,
            inputStyle = "popup",
            placeholder = "Set name",
            tooltip = "Type a name to save the gear you have on as a set. Using an existing name saves over it.",
            getValue = function() return "" end,
            setValue = function(textValue)
                GS.Save(textValue)
                C_Timer.After(0.5, function() CUI:RefreshPage(true) end)
            end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "While Mounted",
            values = values,
            order = sequence,
            disabled = gsOff,
            tooltip = "Wear this set while mounted, and put your gear back when you dismount.",
            getValue = function() return GS.Get("mountedSet") end,
            setValue = function(val) GSSet("mountedSet", val) end,
        }, {
            type = "dropdown",
            text = "While Resting",
            values = values,
            order = sequence,
            disabled = gsOff,
            tooltip = "Wear this set in an inn or a city, and put your gear back when you leave.",
            getValue = function() return GS.Get("restingSet") end,
            setValue = function(val) GSSet("restingSet", val) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  INSTANCE TRACKER
    ---------------------------------------------------------------------------
    local IT = CUI._InstanceTracker
    if IT then
        local function itOff() return not IT.Get("enabled") end
        local function ITSet(key, val)
            IT.Cfg()[key] = val
            IT.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "INSTANCE TRACKER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_InstanceTracker", disabled = itOff, disabledTooltip = "Instance Tracker" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Instance Tracker",
            tooltip = "Counts the new dungeons and raids your account enters in a rolling hour against the cap, times your runs, and prints a summary when you leave. Re-entering the same copy does not count again.",
            getValue = function() return not itOff() end,
            setValue = function(val) ITSet("enabled", val and true or false) end,
        }, {
            type = "slider",
            text = "Hourly Cap",
            min = 1,
            max = 30,
            step = 1,
            isPercent = false,
            disabled = itOff,
            tooltip = "WoW Forever allows 10 new instances an hour per account. Change this only if the game does.",
            getValue = function() return IT.Get("cap") end,
            setValue = function(val) ITSet("cap", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show the Counter",
            disabled = itOff,
            getValue = function() return IT.Get("hud") end,
            setValue = function(val) ITSet("hud", val and true or false) end,
        }, {
            type = "toggle",
            text = "Summary When You Leave",
            disabled = itOff,
            getValue = function() return IT.Get("summary") end,
            setValue = function(val) ITSet("summary", val and true or false) end,
        })
        cursorY = cursorY - height
        if not itOff() then
            local runs = IT.Runs()
            for idx = 1, math.min(#runs, 6), 2 do
                local function Run(r)
                    if not r then return { type = "label", text = "" } end
                    return {
                        type = "label",
                        text = ("%s  |cff9aa6b2%d:%02d, %d deaths, %d items|r"):format(
                            r.name or "?",
                            math.floor(r.seconds / 60),
                            r.seconds % 60,
                            r.deaths or 0,
                            r.items or 0
                        ),
                    }
                end
                _, height = W:DualRow(hostFrame, cursorY, Run(runs[idx]), Run(runs[idx + 1]))
                cursorY = cursorY - height
            end
        end
    end

    ---------------------------------------------------------------------------
    --  GROUP INSPECT
    ---------------------------------------------------------------------------
    if CUI._GroupInspect then
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "GROUP INSPECT", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Group Inspect",
            buttonText = "Open",
            width = 90,
            tooltip = "Everyone in your group with their level, item level and unenchanted slots. Click a name to open the game's inspect window on them. /cinspect opens it too.",
            onClick = function() CUI._GroupInspect.Show() end,
        }, { type = "label", text = "Players out of range answer when they come closer." })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  GEAR SCORE
    ---------------------------------------------------------------------------
    local GSC = CUI._GearScore
    if GSC then
        local function gOff() return not GSC.Get("enabled") end
        local function Set(key, val)
            GSC.Cfg()[key] = val
            GSC.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "GEAR SCORE", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Gear Score",
            tooltip = "One number for a character's gear on the item level scale: 26.4 is worth a full set of level 26 epics. Colored by how close it is to dungeon blues five levels over their level. Shown under your level on the character sheet, under item level on the inspect sheet, and in Group Inspect.",
            getValue = function() return not gOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "On Player Tooltips",
            disabled = gOff,
            tooltip = "Player tooltips show their Gear Score: yours from your gear, others' once they have been inspected.",
            getValue = function() return GSC.Get("tooltip") end,
            setValue = function(val) Set("tooltip", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Inspect Players You Hover",
            disabled = gOff,
            tooltip = "The player you hover is inspected in the background (one at a time, in range, out of combat), so their tooltip gets a score. Never while your own Inspect window is open.",
            getValue = function() return GSC.Get("hoverInspect") end,
            setValue = function(val) Set("hoverInspect", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  TALENT BUILDS
    ---------------------------------------------------------------------------
    local TB = CUI._TalentBuilds
    if TB then
        local function tOff() return not TB.Get("enabled") end
        local function Set(key, val)
            TB.Cfg()[key] = val
            TB.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "TALENT BUILDS", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Talent Builds",
            tooltip = "/cbuilds: talent builds as the order you spend points, per class on this account. Save your talents now, import and export them as a line, follow one: its next talent lights up in CludesUI's talent window, and Learn spends your unspent points along it.",
            getValue = function() return not tOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "labeledButton",
            text = "Builds Window",
            buttonText = "Open",
            width = 90,
            disabled = tOff,
            tooltip = "Opens the Talent Builds window. Also /cbuilds.",
            onClick = function() TB.Builds.Toggle() end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Next Talent on Level-Up",
            disabled = tOff,
            tooltip = "Each level-up, a chat line names the next talent of the build you follow.",
            getValue = function() return TB.Get("levelUpLine") end,
            setValue = function(val) Set("levelUpLine", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  COMBAT EXTRAS
    ---------------------------------------------------------------------------
    local CE = CUI._CombatExtras
    if CE then
        local function Set(f, key, val)
            f.Cfg()[key] = val
            f.Apply()
        end
        local function Off(f)
            return function() return not f.Get("enabled") end
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "COMBAT EXTRAS", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Combat Timer",
            tooltip = "How long the current fight has run, held for a few seconds after it ends. Move it in Edit Layout.",
            getValue = function() return CE.timer.Get("enabled") end,
            setValue = function(val) Set(CE.timer, "enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Fight Length in Chat",
            disabled = Off(CE.timer),
            getValue = function() return CE.timer.Get("chat") end,
            setValue = function(val) Set(CE.timer, "chat", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Combat Alert",
            tooltip = "+ Combat and - Combat fade in the middle of the screen as you enter and leave combat.",
            getValue = function() return CE.alert.Get("enabled") end,
            setValue = function(val) Set(CE.alert, "enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Alert Sound",
            tooltip = "The sound the alert plays.",
            disabled = Off(CE.alert),
            getValue = function() return CE.alert.Get("sound") end,
            setValue = function(val) Set(CE.alert, "sound", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Stealth Reminder",
            tooltip = "For rogues, and druids in Cat Form: Not stealthed shows while you are out of combat and out of stealth. Never in an inn or a city, or while mounted.",
            getValue = function() return CE.stealth.Get("enabled") end,
            setValue = function(val) Set(CE.stealth, "enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Only in a Group",
            disabled = Off(CE.stealth),
            getValue = function() return CE.stealth.Get("groupOnly") end,
            setValue = function(val) Set(CE.stealth, "groupOnly", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  BAG SPACE
    ---------------------------------------------------------------------------
    local BS = CUI._BagSpace
    if BS then
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "BAG SPACE", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(heading, {
            key = "CUI_BagSpace",
            disabled = function() return not BS.Get("enabled") end,
            disabledTooltip = "Bag Space",
        })
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Bag Space",
            tooltip = "Free bag slots on screen, amber when nearly full and red when full. Hover it for the cheapest items you carry; click it to open your bags.",
            getValue = function() return BS.Get("enabled") end,
            setValue = function(val)
                BS.Cfg().enabled = val and true or false
                BS.Apply()
            end,
        }, {
            type = "toggle",
            text = "Warn When Nearly Full",
            disabled = function() return not BS.Get("enabled") end,
            getValue = function() return BS.Get("warn") end,
            setValue = function(val)
                BS.Cfg().warn = val and true or false
                BS.Apply()
            end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  QUEST AUTOMATION
    ---------------------------------------------------------------------------
    local QA = CUI._QuestAutomation
    if QA then
        local function qaOff() return not QA.Get("enabled") end
        local function QASet(key, val)
            QA.Cfg()[key] = val and true or false
            QA.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "QUEST AUTOMATION", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Quest Automation",
            tooltip = "Accepts and turns in quests for you. Hold Shift while talking to an NPC to do it yourself. With a choice of rewards it always stops for you to pick.",
            getValue = function() return not qaOff() end,
            setValue = function(val) QASet("enabled", val) end,
        }, {
            type = "toggle",
            text = "Skip Gray Quests",
            disabled = qaOff,
            tooltip = "Leave quests far below your level alone.",
            getValue = function() return QA.Get("skipGrey") end,
            setValue = function(val) QASet("skipGrey", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Auto Accept",
            disabled = qaOff,
            getValue = function() return QA.Get("accept") end,
            setValue = function(val) QASet("accept", val) end,
        }, {
            type = "toggle",
            text = "Auto Turn In",
            disabled = qaOff,
            getValue = function() return QA.Get("turnIn") end,
            setValue = function(val) QASet("turnIn", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Progress to Party",
            disabled = qaOff,
            tooltip = "Says your quest objective progress (Kobold Vermin slain: 4/10) in party chat. Never in a raid.",
            getValue = function() return QA.Get("progress") end,
            setValue = function(val) QASet("progress", val) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
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
    --  BEST IN SLOT
    ---------------------------------------------------------------------------
    local BI = CUI._BiS
    if BI then
        local function BSet(key, val) BI.Cfg()[key] = val and true or false end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "BEST IN SLOT", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Your BiS List",
            buttonText = "Open",
            width = 90,
            tooltip = "Your pick for every gear slot and whether you have it. Alt+Shift-click any item to add or remove it. Shared by your characters of this class. /cbis opens it too.",
            onClick = function() BI.Show() end,
        }, {
            type = "toggle",
            text = "Alt+Shift-Click to Add",
            getValue = function() return BI.Get("enabled") end,
            setValue = function(val) BSet("enabled", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Mark BiS on Tooltips",
            getValue = function() return BI.Get("tooltip") end,
            setValue = function(val) BSet("tooltip", val) end,
        }, {
            type = "toggle",
            text = "Drop Alert",
            tooltip = "A warning, a sound and a chat line when a BiS item you do not have drops: in the loot window, or looted by anyone near you.",
            getValue = function() return BI.Get("alert") end,
            setValue = function(val) BSet("alert", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Export",
            inputWidth = 160,
            inputStyle = "popup",
            tooltip = "Copy this line to share your list.",
            getValue = function() return BI.Export() end,
            setValue = function() end,
        }, {
            type = "input",
            text = "Import",
            inputWidth = 160,
            inputStyle = "popup",
            placeholder = "CUIBIS1:...",
            tooltip = "Paste a CludesUI BiS line for your class. It replaces your list.",
            getValue = function() return "" end,
            setValue = function(textValue) BI.Import(textValue) end,
        })
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
    --  BOAT AND ZEPPELIN TIMERS
    ---------------------------------------------------------------------------
    local TR2 = CUI._Transport
    if TR2 then
        local function tOff() return not TR2.Get("enabled") end
        local function Set(key, val)
            TR2.Cfg()[key] = val
            TR2.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "BOAT AND ZEPPELIN TIMERS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_ShipTimer", disabled = tOff, disabledTooltip = "Boat and Zeppelin Timer" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Boat and Zeppelin Timers",
            tooltip = "When each ship leaves and arrives, on minimap pins at its docks. A ship is timed when you ride it, when you click its pin as it arrives (left) or leaves (right), or from players who share timings.",
            getValue = function() return not tOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Zone Timer",
            disabled = tOff,
            tooltip = "A list of the boats and zeppelins in your zone with their times. Move it in Edit Layout.",
            getValue = function() return TR2.Get("zone") end,
            setValue = function(val) Set("zone", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Share Timings",
            disabled = tOff,
            tooltip = "Sends the ships you time to your group and guild, and takes theirs, and the timings of ForeverTransport and NauticusClassic users.",
            getValue = function() return TR2.Get("share") end,
            setValue = function(val) Set("share", val and true or false) end,
        }, {
            type = "slider",
            text = "Text Size",
            min = 10,
            max = 24,
            step = 1,
            isPercent = false,
            disabled = tOff,
            getValue = function() return TR2.Get("size") end,
            setValue = function(val) Set("size", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  TOWN MAP
    ---------------------------------------------------------------------------
    local TWN = CUI._TownMap
    if TWN then
        local function nOff() return not TWN.Get("enabled") end
        local function Tog(key, textValue, tipText, dis)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = dis or nOff,
                getValue = function() return TWN.Get(key) end,
                setValue = function(val)
                    TWN.Cfg()[key] = val and true or false
                    TWN.Apply()
                end,
            }
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "TOWN MAP", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "enabled",
                "Town Map",
                "Service NPCs for your faction, mailboxes and spirit healers on the world map. Hover a pin for its name.",
                function() return false end
            ),
            Tog(
                "capitalsOnly",
                "Vendors and Trainers Only in Cities",
                "Keeps vendors, trainers and the bank off questing maps. Flight masters, innkeepers and stable masters still show everywhere."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("minimapMail", "Mailboxes on Minimap", "Pins the mailboxes near you on the minimap."),
            Tog(
                "minimapSpirit",
                "Spirit Healers on Minimap",
                "Pins the spirit healers near you on the minimap."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("mail", "Mailboxes", "Every mailbox, in towns and out in the world."),
            Tog("spirit", "Spirit Healers", "Every graveyard's spirit healer, in towns and out in the world.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("class", "Class Trainers", "Your own class's trainers only."),
            Tog("profession", "Profession Trainers")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("flight", "Flight Masters", "Left to Map Markers when its Flight Points pins are on."),
            Tog("inn", "Innkeepers")
        )
        cursorY = cursorY - height
        _, height =
            W:DualRow(hostFrame, cursorY, Tog("bank", "Bank and Auction House"), Tog("repair", "Repairs"))
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("supplies", "Reagents, Ammo and Food"),
            Tog("stable", "Stable Masters", "Hunters only.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("vendors", "Other Vendors", "Trade goods and every other merchant."),
            {
                type = "slider",
                text = "Pin Size",
                min = 10,
                max = 32,
                step = 1,
                isPercent = false,
                disabled = nOff,
                getValue = function() return TWN.Get("size") end,
                setValue = function(val)
                    TWN.Cfg().size = math.floor(val + 0.5)
                    TWN.Apply()
                end,
            }
        )
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  PALADIN BLESSINGS
    ---------------------------------------------------------------------------
    local BL = CUI._Blessings
    if BL then
        local function bOff() return not BL.Get("enabled") end
        local function Set(key, val)
            BL.Cfg()[key] = val
            BL.Apply()
        end
        local function Tog(key, textValue, tipText)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = bOff,
                getValue = function() return BL.Get(key) end,
                setValue = function(val) Set(key, val and true or false) end,
            }
        end
        local function Slider(key, textValue, lo, hi, tipText)
            return {
                type = "slider",
                text = textValue,
                tooltip = tipText,
                min = lo,
                max = hi,
                step = 1,
                isPercent = false,
                disabled = bOff,
                getValue = function() return BL.Get(key) end,
                setValue = function(val) Set(key, math.floor(val + 0.5)) end,
            }
        end
        local ROLE_VALUES = {
            none = "None",
            might = "Blessing of Might",
            wisdom = "Blessing of Wisdom",
            kings = "Blessing of Kings",
        }
        local ROLE_ORDER = { "none", "might", "wisdom", "kings" }
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "PALADIN BLESSINGS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_BlessingBar", disabled = bOff, disabledTooltip = "Blessing Bar" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Blessing Bar",
            tooltip = "For paladins: your aura and a button per class in the group. Left-click a class to bless the next member who needs it, missing first; in combat each click steps to the next. Right-click a class for its blessing, its player list or the assignments. Plans are shared with the group's other paladins, and PallyPower users' plans are read too.",
            getValue = function() return not bOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "labeledButton",
            text = "Assignments",
            buttonText = "Open",
            width = 90,
            disabled = bOff,
            tooltip = "Every paladin's blessing for each class and their aura, with Auto-Assign, a saved preset and a report to chat. Also /cbless.",
            onClick = function() BL.Open() end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("showAura", "Aura Button", "Casts your aura. Right-click it to choose which, wheel to cycle."),
            Tog(
                "showFury",
                "Righteous Fury Button",
                "Casts Righteous Fury on yourself. A red ! means it is not up."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("showSeal", "Seal Button", "Casts your seal. Right-click it to choose which, wheel to cycle."),
            Tog(
                "showAuto",
                "Auto Buff Button",
                "Left-click blesses the next player in need, right-click the next Greater Blessing."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "autoGreater",
                "Auto Buff Greater First",
                "Swaps the Auto Buff button: left-click casts a Greater Blessing, right-click a single one."
            ),
            Tog("showClasses", "Class Buttons", "Off leaves only the Auto Buff button and the key bindings.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "playerList",
                "Player List",
                "Right-click a class to list its players: bless one, or give one their own blessing."
            ),
            Tog("tooltips", "Show Tooltips", "A tooltip on each bar button.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "labels",
                "Class Labels",
                "Each class's name under its button, or beside it when the bar is vertical."
            ),
            Tog(
                "timers",
                "Minutes Left",
                "Minutes left on each class's shortest blessing, and on each player's."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "smart",
                "Smart Blessings",
                "No Wisdom for warriors and rogues, no Might for priests, mages and warlocks in the menus."
            ),
            Tog(
                "respect",
                "Respect Blessing Time",
                "Only bless players who are missing a blessing or running out."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("wait", "Wait for Players", "Cast a Greater Blessing only when the whole class is in range."),
            Tog(
                "bench",
                "Hide the Bench",
                "In a raid dungeon, leave out the players outside its usual groups."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("inParty", "Use in Party", "Show the bar in a party. It always shows in a raid."),
            Tog("solo", "Use When Solo", "Show the bar when you are not in a group.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Main Tank Blessing",
            values = ROLE_VALUES,
            order = ROLE_ORDER,
            disabled = bOff,
            tooltip = "A warrior, druid or paladin marked as tank or main tank gets this instead of their class blessing.",
            getValue = function() return BL.Get("tank") end,
            setValue = function(val) Set("tank", val) end,
        }, {
            type = "dropdown",
            text = "Main Assist Blessing",
            values = ROLE_VALUES,
            order = ROLE_ORDER,
            disabled = bOff,
            tooltip = "A warrior, druid or paladin marked as main assist gets this instead of their class blessing.",
            getValue = function() return BL.Get("assist") end,
            setValue = function(val) Set("assist", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "vertical",
                "Vertical Bar",
                "The bar grows down instead of right, with the class names beside the buttons."
            ),
            {
                type = "dropdown",
                text = "Button Border",
                disabled = bOff,
                values = { black = "Black", status = "Status Color", none = "None" },
                order = { "black", "status", "none" },
                tooltip = "With Status Color the class buttons show their state on their edge instead of tinting the icon: red missing, yellow running out, blue only players with their own.",
                getValue = function() return BL.Get("border") end,
                setValue = function(val) Set("border", val) end,
            }
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider("size", "Button Size", 20, 60),
            Slider("spacing", "Button Spacing", 0, 30)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider(
                "groupGap",
                "Aura / Class Gap",
                0,
                40,
                "The extra gap between your own buttons and the class buttons."
            ),
            Slider("perRow", "Class Buttons per Row", 1, 9)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, Slider("timerSize", "Timer Text Size", 8, 20), {
            type = "label",
            text = "Key bindings: Next Blessing and Next Greater Blessing, under CludesUI in the game's Key Bindings.",
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  DISCOVERY
    ---------------------------------------------------------------------------
    local DC = CUI._Discovery
    if DC then
        local function dOff() return not DC.Get("enabled") end
        local function Set(key, val)
            DC.Cfg()[key] = val
            DC.Apply()
        end
        local function Tog(key, textValue, tipText)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = dOff,
                getValue = function() return DC.Get(key) end,
                setValue = function(val) Set(key, val and true or false) end,
            }
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "DISCOVERY", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_DiscoveryTracker", disabled = dOff, disabledTooltip = "Discovery Tracker" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Discovery",
            tooltip = "A window (/cdiscovery) of the library books, the Cozy Sleeping Bag's hidden chain, the Field Journal, and every quest and rare by zone, with trackers and map pins.",
            getValue = function() return not dOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "labeledButton",
            text = "Discovery Window",
            buttonText = "Open",
            width = 90,
            disabled = dOff,
            tooltip = "Opens the Discovery window. Also /cdiscovery.",
            onClick = function() DC.Open() end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "tracker",
                "Library Books Tracker",
                "Lists the books still to find in your zone, and the ones you carry. Its X closes it until you enter another zone. Move it in Edit Layout."
            ),
            Tog(
                "bagTracker",
                "Sleeping Bag Tracker",
                "From level 14 until you have the bag, the chain's next step on the same tracker."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("mapPins", "Library Book Pins", "A pin on the world map for each book you still need."),
            Tog(
                "mapTurnIn",
                "Librarian Pin",
                "While you carry books, a pin at the librarian or mage trainer who takes them."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("bagMapPins", "Sleeping Bag Pins", "A pin on the world map at the chain's next step."),
            Tog(
                "fieldJournal",
                "Count the Field Journal",
                "Counts the fish you catch, the herbs you pick from their nodes and the dishes you cook, for this character."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "nearby",
                "Nearby Book Alert",
                "A ping and a chat line when you come within range of a book you still need."
            ),
            {
                type = "slider",
                text = "Alert Range (yards)",
                min = 10,
                max = 100,
                step = 5,
                isPercent = false,
                disabled = dOff,
                getValue = function() return DC.Get("nearbyRange") end,
                setValue = function(val) Set("nearbyRange", math.floor(val + 0.5)) end,
            }
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("nearbyPing", "Alert Sound", "The map ping sound with the alert."),
            Tog("nearbyChat", "Alert Chat Line", "A chat line with the book's name and how far it is.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Map Pin Size",
            min = 12,
            max = 36,
            step = 1,
            isPercent = false,
            disabled = dOff,
            getValue = function() return DC.Get("pinSize") end,
            setValue = function(val) Set("pinSize", math.floor(val + 0.5)) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  QUEST LIST AND RARES (Discovery's last two tabs)
    ---------------------------------------------------------------------------
    local QL = CUI._QuestList
    if QL and DC then
        local function qOff() return not DC.Get("enabled") end
        local function Set(key, val)
            QL.Cfg()[key] = val
            QL.Apply()
        end
        local function Tog(key, textValue, tipText)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = qOff,
                getValue = function() return QL.Get(key) end,
                setValue = function(val) Set(key, val and true or false) end,
            }
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "QUEST LIST AND RARES", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(heading, {
            key = "CUI_RareAlert",
            disabled = function() return qOff() or not QL.Get("rareAlert") end,
            disabledTooltip = "Rare Alert",
        })
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "questPins",
                "Quest Giver Pins",
                "A ! on the world map at each quest giver with a quest you can take now. Green for dungeon quests, blue for repeatable ones."
            ),
            Tog("pinGrey", "Low Level Quests", "Pins givers whose quests are gray to you too.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("chainsOnly", "Chains Only", "Pins only quests that are part of a chain, and dungeon quests."),
            Tog("rarePins", "Rare Pins", "A star on the world map where each rare spawns.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "rarePinsKilled",
                "Pins for Killed Rares",
                "Keeps the stars of rares you have killed, greyed."
            ),
            {
                type = "slider",
                text = "Quest and Rare Pin Size",
                min = 12,
                max = 36,
                step = 1,
                isPercent = false,
                disabled = qOff,
                getValue = function() return QL.Get("pinSize") end,
                setValue = function(val) Set("pinSize", math.floor(val + 0.5)) end,
            }
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "rareAlert",
                "Rare Alerts",
                "A card and a sound when a rare's nameplate, your target, your mouseover or the minimap shows one. Left-click the card to target it, right-click to close it. Move it in Edit Layout."
            ),
            Tog("rareAlertKilled", "Alert for Killed Rares", "Also alerts for rares you have killed before.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("rareSound", "Alert Sound", "The Gruntling Horn with each alert."),
            Tog(
                "rareAlertSkull",
                "Skull on Click",
                "Clicking the card also puts a skull on the rare. Your whole group sees the mark."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Alert Time (seconds)",
            min = 5,
            max = 60,
            step = 1,
            isPercent = false,
            disabled = qOff,
            getValue = function() return QL.Get("rareAlertTime") end,
            setValue = function(val) Set("rareAlertTime", math.floor(val + 0.5)) end,
        }, {
            type = "labeledButton",
            text = "Test the Alert",
            buttonText = "Test",
            width = 90,
            disabled = qOff,
            tooltip = "Shows the card for your target, or a sample rare.",
            onClick = function() QL.TestAlert() end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  PROFESSIONS
    ---------------------------------------------------------------------------
    local PF = CUI._Professions
    if PF then
        local function pOff() return not PF.Get("enabled") end
        local function Set(key, val)
            PF.Cfg()[key] = val
            PF.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "PROFESSIONS", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Professions",
            tooltip = "A window (/cprof) for each of your professions: the next rank and where to get it, the recipes you know that still give skill, and every recipe you have not learned with where it comes from. Open your profession window once so it knows what you have learned.",
            getValue = function() return not pOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "labeledButton",
            text = "Professions Window",
            buttonText = "Open",
            width = 90,
            disabled = pOff,
            tooltip = "Opens the Professions window. Also /cprof.",
            onClick = function() PF.Open() end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Next Rank Alert",
            disabled = pOff,
            tooltip = "A chat line once when a profession is ready for its next rank, with where to train it. /cprof rank checks now.",
            getValue = function() return PF.Get("rankAlert") end,
            setValue = function(val) Set("rankAlert", val and true or false) end,
        }, {
            type = "toggle",
            text = "List Recipes for Later",
            disabled = pOff,
            tooltip = "The Recipe Finder also lists the recipes your skill is not high enough for yet.",
            getValue = function() return PF.Get("showLater") end,
            setValue = function(val) Set("showLater", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Recipe Window",
            disabled = pOff,
            tooltip = "Opening a profession shows CludesUI's recipe window in place of the game's: your recipes by category with how many you can make, favourites, a filter, reagents with what is in your bags and bank, and the recipes you have not learned yet with where to learn them.",
            getValue = function() return PF.Get("craftWindow") end,
            setValue = function(val) Set("craftWindow", val and true or false) end,
        }, {
            type = "toggle",
            text = "Skill-up Chances",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "The recipe window shows each recipe's chance to raise your skill, where it is not certain either way.",
            getValue = function() return PF.Get("skillUpChances") end,
            setValue = function(val) Set("skillUpChances", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Skill-up Levels",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "The picked recipe shows the skill where it turns yellow, green and gray, and your chance now.",
            getValue = function() return PF.Get("skillThresholds") end,
            setValue = function(val) Set("skillThresholds", val and true or false) end,
        }, {
            type = "toggle",
            text = "Alts' Professions",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "An Alts button on the recipe window opens your other characters' professions on this realm. Each one shows once that character has opened it.",
            getValue = function() return PF.Get("altProfessions") end,
            setValue = function(val) Set("altProfessions", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Craft Orders",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "On someone else's profession (from a trade link), an order column: pick recipes, how many, the materials you bring and a tip, then ask them in party chat or by whisper.",
            getValue = function() return PF.Get("craftOrders") end,
            setValue = function(val) Set("craftOrders", val and true or false) end,
        }, {
            type = "toggle",
            text = "Skill-up Plan",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "A Skill-up Plan button on the recipe window: the fewest crafts from your skill to your cap, with the trainer recipes to learn on the way.",
            getValue = function() return PF.Get("skillUpPlan") end,
            setValue = function(val) Set("skillUpPlan", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Craft Profit",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "Under a recipe's reagents: what one craft sells for after the auction cut, its materials and the profit. Needs auction prices (The Market's Auction Prices, or Auctionator).",
            getValue = function() return PF.Get("craftProfit") end,
            setValue = function(val) Set("craftProfit", val and true or false) end,
        }, {
            type = "toggle",
            text = "Disenchant Window",
            disabled = pOff,
            tooltip = "/cde, or the Disenchant button on the recipe window while Enchanting is open: everything in your bags Disenchant can take. Right-click keeps one, Shift-right-click every copy; Disenchant All does one per click.",
            getValue = function() return PF.Get("disenchant") end,
            setValue = function(val) Set("disenchant", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Disenchant on Tooltips",
            disabled = function() return pOff() or not PF.Get("disenchant") end,
            tooltip = "Green, blue and purple gear says about what it disenchants into is worth at your auction prices, and the Enchanting skill it needs (red when yours is lower).",
            getValue = function() return PF.Get("disenchantTooltip") end,
            setValue = function(val) Set("disenchantTooltip", val and true or false) end,
        }, {
            type = "toggle",
            text = "Trade Enchants",
            disabled = pOff,
            tooltip = "While you trade with Enchanting open: beside the trade window, your enchants that go on the item in the \"Will not be traded\" slot, the ones they linked to you first. Enchant casts it in one click.",
            getValue = function() return PF.Get("tradeEnchants") end,
            setValue = function(val) Set("tradeEnchants", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  THE MARKET
    ---------------------------------------------------------------------------
    local MK = CUI._Market
    if MK then
        local function mOff() return not MK.Get("enabled") end
        local function Set(key, val)
            MK.Cfg()[key] = val
            MK.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "THE MARKET", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Auction Prices",
            tooltip = function()
                return "A Scan Prices button on the auction house: it reads every listing and keeps each item's lowest buyout for this realm and faction (the game allows one full scan every 15 minutes). Your own searches keep prices fresh too. Loot Feed, Junk Items and the recipe window use these prices when Auctionator is not installed.\n\n"
                    .. MK.Market.Summary()
            end,
            getValue = function() return not mOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Prices on Tooltips",
            disabled = mOff,
            tooltip = "Item tooltips show the lowest buyout and how old it is. Off while Auctionator is installed, which shows its own.",
            getValue = function() return MK.Get("tooltip") end,
            setValue = function(val) Set("tooltip", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Scan on Opening",
            disabled = mOff,
            tooltip = "Scans by itself when you open the auction house and your last scan is over 30 minutes old.",
            getValue = function() return MK.Get("autoScan") end,
            setValue = function(val) Set("autoScan", val and true or false) end,
        }, {
            type = "toggle",
            text = "Keep Other Addons' Scans",
            disabled = mOff,
            tooltip = "Also keeps the prices from full scans that other addons start.",
            getValue = function() return MK.Get("capture") end,
            setValue = function(val) Set("capture", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Market Panel",
            disabled = mOff,
            tooltip = "A panel beside the auction house. Sell: your bags most valuable first, each priced one step under the cheapest listing that is not yours, with quantity, duration and Post. My Auctions: your auctions checked against the listings, undercut ones first, with Cancel.",
            getValue = function() return MK.Get("panel") end,
            setValue = function(val) Set("panel", val and true or false) end,
        }, {
            type = "toggle",
            text = "Undercut Alert",
            disabled = function() return mOff() or not MK.Get("panel") end,
            tooltip = "A chat line at the auction house when someone lists for less than your auctions.",
            getValue = function() return MK.Get("undercutAlert") end,
            setValue = function(val) Set("undercutAlert", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Shopping Tab",
            disabled = function() return mOff() or not MK.Get("panel") end,
            tooltip = "A Shopping tab on the Market panel: the items your current RestedXP steps tell you to buy and the items your quests still need, with how many you have. Click one to search for it.",
            getValue = function() return MK.Get("shopping") end,
            setValue = function(val) Set("shopping", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  MAIL AND ALTS
    ---------------------------------------------------------------------------
    local MA = CUI._MailAlts
    if MA then
        local function Tog(key, textValue, tipText)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                getValue = function() return MA.Get(key) end,
                setValue = function(val)
                    MA.Cfg()[key] = val and true or false
                    MA.Apply()
                end,
            }
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "MAIL AND ALTS", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "altCounts",
                "Alt Item Counts",
                "Item tooltips show how many your characters on this realm and faction hold in their bags, bank and mailbox. Each is counted once you log in on it, its bank once you open it."
            ),
            Tog(
                "mailAlts",
                "Alts Button on Mail",
                "An Alts button beside the mailbox's Send tab lists your characters with level and gold; pick one to fill the To box."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "quickAttach",
                "Quick Attach",
                "An Attach button beside the Send tab: attach every trade good, one type of trade good, or your unbound gear in one click."
            ),
            Tog(
                "expiry",
                "Mail Expiry Warning",
                "At login, names any of your characters with mail expiring within three days."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Forget a Character",
            buttonText = "Forget",
            width = 90,
            tooltip = "Removes a deleted or moved character from the counts and the Alts list.",
            onClick = function(self) MA.Forget(self) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  LAYERS
    ---------------------------------------------------------------------------
    local LY = CUI._Layers
    if LY then
        local lt, ls = LY.tracker, LY.swap
        local function lOff() return not lt.Get("enabled") end
        local function Set(key, val)
            lt.Cfg()[key] = val
            lt.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "LAYERS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_LayerTracker", disabled = lOff, disabledTooltip = "Layer Tracker" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Layer Tracker",
            tooltip = "Which layer of the zone you are on, read from the NPCs around you. Hover it for the layers seen in this zone.",
            getValue = function() return not lOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Auto-Accept Layer Swap",
            tooltip = "Confirms the game's layer swap prompt when you join a group.",
            getValue = function() return ls.Get("enabled") end,
            setValue = function(val) ls.Cfg().enabled = val and true or false end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Countdown to a Layer Change",
            disabled = lOff,
            getValue = function() return lt.Get("countdown") end,
            setValue = function(val) Set("countdown", val and true or false) end,
        }, {
            type = "toggle",
            text = "Say When You Move",
            disabled = lOff,
            getValue = function() return lt.Get("chat") end,
            setValue = function(val) Set("chat", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  XP PER HOUR AND GROUP XP
    ---------------------------------------------------------------------------
    local XP = CUI._XP
    if XP then
        local xt, gx = XP.ticker, XP.group
        local function Set(f, key, val)
            f.Cfg()[key] = val
            f.Apply()
        end
        local function Tog(f, key, textValue, tipText, off)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = off,
                getValue = function() return f.Get(key) end,
                setValue = function(val) Set(f, key, val and true or false) end,
            }
        end
        local function Num(f, key, textValue, min, max, step, off)
            return {
                type = "slider",
                text = textValue,
                min = min,
                max = max,
                step = step,
                isPercent = false,
                disabled = off,
                getValue = function() return f.Get(key) end,
                setValue = function(val) Set(f, key, math.floor(val + 0.5)) end,
            }
        end
        local function xOff() return not xt.Get("enabled") end
        local function gOff() return not gx.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "XP PER HOUR", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_XPTicker", disabled = xOff, disabledTooltip = "XP per Hour" }
        )
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                xt,
                "enabled",
                "XP per Hour",
                "This session's XP per hour, the time to your next level, the session's time and how long your last levels took. Pause and reset on the card, or /cxp start, pause, reset."
            ),
            Tog(xt, "hideResting", "Hide While Resting", nil, xOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(xt, "splits", "Show Level Times", nil, xOff),
            Num(xt, "history", "Levels Shown", 1, 10, 1, xOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(xt, "size", "Text Size", 10, 28, 1, xOff),
            { type = "label", text = "" }
        )
        cursorY = cursorY - height

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "GROUP XP", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_GroupXP", disabled = gOff, disabledTooltip = "Group XP" }
        )
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                gx,
                "enabled",
                "Group XP",
                "A bar per group member with their level and XP. They need CludesUI (or another addon that shares group XP)."
            ),
            Tog(gx, "showSelf", "Show Yourself", nil, gOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(gx, "raid", "Also in Raids", nil, gOff),
            Num(gx, "width", "Width", 160, 500, 10, gOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(gx, "size", "Text Size", 8, 20, 1, gOff),
            { type = "label", text = "" }
        )
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  RESTOCK AND REMINDERS
    ---------------------------------------------------------------------------
    local RM = CUI._Reminders
    if RM then
        local rs, lk, gr, tp = RM.restock, RM.lock, RM.gear, RM.talents
        local function Set(f, key, val)
            f.Cfg()[key] = val
            if f.Apply then f.Apply() end
        end
        local function Tog(f, key, textValue, tipText, off)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = off,
                getValue = function() return f.Get(key) end,
                setValue = function(val) Set(f, key, val and true or false) end,
            }
        end
        local function Num(f, key, textValue, min, max, step, off)
            return {
                type = "slider",
                text = textValue,
                min = min,
                max = max,
                step = step,
                isPercent = false,
                disabled = off,
                getValue = function() return f.Get(key) end,
                setValue = function(val) Set(f, key, math.floor(val + 0.5)) end,
            }
        end
        local function rsOff() return not rs.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "RESTOCK REMINDER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_Restock", disabled = rsOff, disabledTooltip = "Restock Reminder" }
        )
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                rs,
                "enabled",
                "Restock Reminder",
                "When you reach a city or inn, a flashing list of what you are short on. It stays up until you have what you need or leave."
            ),
            Tog(
                rs,
                "buy",
                "Buy at Vendors",
                "At a vendor who sells them, tops your class reagents and ammo up to what you carry, and prints what it spent. Off by default: it spends gold for you.",
                rsOff
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(rs, "reagents", "Class Reagents", nil, rsOff),
            Tog(rs, "ammo", "Ammo (thrown, arrows, shot)", nil, rsOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(rs, "ammoTarget", "Ammo to Carry", 50, 4000, 50, rsOff),
            Tog(rs, "food", "Food & Drink", "Warriors and rogues do not need drink.", rsOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(rs, "foodBelow", "Food & Drink Below", 1, 40, 1, rsOff),
            Tog(rs, "vendor", "Junk & Full Bags", nil, rsOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(rs, "foodMinLevel", "Food Minimum Level", 0, 60, 1, rsOff),
            Num(rs, "foodMaxLevel", "Food Maximum Level", 0, 60, 1, rsOff)
        )
        cursorY = cursorY - height
        if rs.Class == "HUNTER" then
            _, height = W:DualRow(
                hostFrame,
                cursorY,
                Tog(
                    rs,
                    "hunterAmmo",
                    "Hunter Ammo Reminder",
                    "Reminds about your equipped ammo at its own amount.",
                    rsOff
                ),
                Num(rs, "hunterAmmoBelow", "Remind When Ammo Falls To", 50, 4000, 50, rsOff)
            )
            cursorY = cursorY - height
        end
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(rs, "bagsBelow", "Free Slots Below", 1, 20, 1, rsOff),
            Num(rs, "size", "Text Size", 10, 32, 1, rsOff)
        )
        cursorY = cursorY - height
        local reagents = rs.Reagents()
        for idx = 1, #reagents, 2 do
            local function Carry(r)
                if not r then return { type = "label", text = "" } end
                return {
                    type = "slider",
                    text = r.name .. " to Carry",
                    min = 0,
                    max = 200,
                    step = 1,
                    isPercent = false,
                    disabled = rsOff,
                    tooltip = "How many to carry. 0 stops reminding you about it.",
                    getValue = function() return rs.Target(r.item) end,
                    setValue = function(val)
                        local c = rs.Cfg()
                        c.targets = c.targets or {}
                        c.targets[r.item] = math.floor(val + 0.5)
                        rs.Apply()
                    end,
                }
            end
            _, height = W:DualRow(hostFrame, cursorY, Carry(reagents[idx]), Carry(reagents[idx + 1]))
            cursorY = cursorY - height
        end

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "OTHER REMINDERS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(heading, {
            key = "CUI_GearReminders",
            disabled = function() return not (gr.Get("worn") or gr.Get("pole")) end,
            disabledTooltip = "Gear Reminders",
        })
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                lk,
                "enabled",
                "Lockpicking Skill",
                "Lockbox tooltips show the Lockpicking needed to open them, colored by yours."
            ),
            Tog(
                tp,
                "enabled",
                "Unspent Talent Points",
                "Text on screen while you have talent points to spend. Hidden in combat."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                gr,
                "worn",
                "Worn Gear Reminder",
                "An icon while you wear Cloak of Hermitic Bliss in Wailing Caverns, so you remember to swap it."
            ),
            Tog(gr, "pole", "Fishing Pole Reminder", "An icon while you have a fishing pole equipped.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Fishing Pole Shows In",
            values = { always = "Everywhere", instance = "Dungeons & Raids" },
            order = { "always", "instance" },
            disabled = function() return not gr.Get("pole") end,
            getValue = function() return gr.Get("poleWhere") end,
            setValue = function(val) Set(gr, "poleWhere", val) end,
        }, Num(gr, "size", "Gear Icon Size", 20, 96, 1))
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  MANA EFFICIENCY
    ---------------------------------------------------------------------------
    local SE = CUI._SpellEfficiency
    if SE then
        local function seOff() return not SE.Get("enabled") end
        local function SESet(key, val) SE.Cfg()[key] = val end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "MANA EFFICIENCY", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Mana Efficiency",
            tooltip = "A line on a mana spell's tooltip (and a macro that casts one) with its healing or damage per mana and per second, with your spell power and talents counted.",
            getValue = function() return not seOff() end,
            setValue = function(val) SESet("enabled", val and true or false) end,
        }, {
            type = "dropdown",
            text = "Show",
            disabled = seOff,
            values = { all = "Healing and Damage", heal = "Healing Only", damage = "Damage Only" },
            order = { "all", "heal", "damage" },
            getValue = function() return SE.Get("show") end,
            setValue = function(val) SESet("show", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Per Mana",
            disabled = seOff,
            getValue = function() return SE.Get("perMana") end,
            setValue = function(val) SESet("perMana", val and true or false) end,
        }, {
            type = "toggle",
            text = "Per Second",
            disabled = seOff,
            getValue = function() return SE.Get("perSecond") end,
            setValue = function(val) SESet("perSecond", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Per Mana per Second",
            disabled = seOff,
            getValue = function() return SE.Get("perManaSecond") end,
            setValue = function(val) SESet("perManaSecond", val and true or false) end,
        }, {
            type = "dropdown",
            text = "Style",
            disabled = seOff,
            values = { long = "Words (healing per mana)", short = "Short (HPM, HPS)" },
            order = { "long", "short" },
            getValue = function() return SE.Get("style") end,
            setValue = function(val) SESet("style", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Count Spell Power",
            disabled = seOff,
            getValue = function() return SE.Get("bonus") end,
            setValue = function(val) SESet("bonus", val and true or false) end,
        }, {
            type = "toggle",
            text = "Count Talents",
            disabled = seOff,
            getValue = function() return SE.Get("talents") end,
            setValue = function(val) SESet("talents", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Decimals",
            min = 0,
            max = 2,
            step = 1,
            isPercent = false,
            disabled = seOff,
            getValue = function() return SE.Get("decimals") end,
            setValue = function(val) SESet("decimals", math.floor(val + 0.5)) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  HEALER MANA AND PET TRACKER
    ---------------------------------------------------------------------------
    local GW = CUI._GroupWatch
    if GW then
        local hm, pt = GW.healer, GW.pet
        local function Set(f, key, val)
            f.Cfg()[key] = val
            f.Apply()
        end
        local function hmOff() return not hm.Get("enabled") end
        local function ptOff() return not pt.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "HEALER MANA", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_HealerMana", disabled = hmOff, disabledTooltip = "Healer Mana" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Healer Mana",
            tooltip = "Your group's healers and their mana, lowest first, with a cup beside anyone drinking. Move it in Edit Layout.",
            getValue = function() return not hmOff() end,
            setValue = function(val) Set(hm, "enabled", val and true or false) end,
        }, {
            type = "dropdown",
            text = "Show In",
            disabled = hmOff,
            values = { instance = "Dungeons & Raids", group = "Any Group" },
            order = { "instance", "group" },
            getValue = function() return hm.Get("where") end,
            setValue = function(val) Set(hm, "where", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Yourself",
            disabled = hmOff,
            getValue = function() return hm.Get("showSelf") end,
            setValue = function(val) Set(hm, "showSelf", val and true or false) end,
        }, {
            type = "toggle",
            text = "Mark Drinking",
            disabled = hmOff,
            getValue = function() return hm.Get("drinking") end,
            setValue = function(val) Set(hm, "drinking", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Width",
            min = 100,
            max = 300,
            step = 5,
            isPercent = false,
            disabled = hmOff,
            getValue = function() return hm.Get("width") end,
            setValue = function(val) Set(hm, "width", math.floor(val + 0.5)) end,
        }, {
            type = "slider",
            text = "Text Size",
            min = 8,
            max = 20,
            step = 1,
            isPercent = false,
            disabled = hmOff,
            getValue = function() return hm.Get("size") end,
            setValue = function(val) Set(hm, "size", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "PET TRACKER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_PetTracker", disabled = ptOff, disabledTooltip = "Pet Tracker" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Pet Tracker",
            tooltip = "A warning while a hunter or warlock has no pet out. A warlock who sacrificed their demon, and a hunter with Lone Wolf, are left alone.",
            getValue = function() return not ptOff() end,
            setValue = function(val) Set(pt, "enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Warn While Passive",
            disabled = ptOff,
            getValue = function() return pt.Get("passive") end,
            setValue = function(val) Set(pt, "passive", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Warn on Low Pet Health",
            disabled = ptOff,
            getValue = function() return pt.Get("lowHealth") end,
            setValue = function(val) Set(pt, "lowHealth", val and true or false) end,
        }, {
            type = "slider",
            text = "Low Health Below",
            min = 5,
            max = 90,
            step = 1,
            isPercent = false,
            disabled = ptOff,
            getValue = function() return pt.Get("lowBelow") end,
            setValue = function(val) Set(pt, "lowBelow", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Only In Combat",
            disabled = ptOff,
            getValue = function() return pt.Get("combatOnly") end,
            setValue = function(val) Set(pt, "combatOnly", val and true or false) end,
        }, {
            type = "toggle",
            text = "Only In Dungeons & Raids",
            disabled = ptOff,
            getValue = function() return pt.Get("instanceOnly") end,
            setValue = function(val) Set(pt, "instanceOnly", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Hide While Mounted",
            disabled = ptOff,
            getValue = function() return pt.Get("hideMounted") end,
            setValue = function(val) Set(pt, "hideMounted", val and true or false) end,
        }, {
            type = "toggle",
            text = "Show Icon",
            disabled = ptOff,
            getValue = function() return pt.Get("showIcon") end,
            setValue = function(val) Set(pt, "showIcon", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  DUNGEON JOURNAL
    ---------------------------------------------------------------------------
    if CUI._Journal then
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "DUNGEON JOURNAL", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Dungeon Journal",
            buttonText = "Open",
            width = 90,
            tooltip = "Every dungeon and raid: bosses in kill order, their loot and drop chances, a tip per boss, and the quests. Alt+Shift-click an item to add it to your BiS list. /cjournal opens it too.",
            onClick = function() CUI._Journal.Show() end,
        }, { type = "label", text = "Opens on the dungeon you are in." })
        cursorY = cursorY - height
        local DM = CUI._DungeonMap
        if DM then
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Dungeon Map",
                tooltip = "Inside a dungeon, a small map with the route: bosses numbered in kill order and joined by a line, the next one ringed, killed ones dimmed. It turns to the next boss's floor and moves on with each kill. /cdmap shows or hides it; move it in Edit Layout.",
                getValue = function() return DM.Get("enabled") end,
                setValue = function(val)
                    DM.Cfg().enabled = val and true or false
                    DM.Apply()
                    CUI:RefreshPage()
                end,
            }, {
                type = "toggle",
                text = "Open on Entering",
                tooltip = "Opens the Dungeon Map when you enter a dungeon, and closes it when you leave.",
                disabled = function() return not DM.Get("enabled") end,
                disabledTooltip = "Dungeon Map",
                getValue = function() return DM.Get("autoShow") end,
                setValue = function(val)
                    DM.Cfg().autoShow = val and true or false
                    DM.Apply()
                end,
            })
            cursorY = cursorY - height
        end
    end

    ---------------------------------------------------------------------------
    --  STAT WEIGHTS
    ---------------------------------------------------------------------------
    local SWt = CUI._StatWeights
    if SWt then
        local rowConf = SWt.Cfg()
        local function Rebuild()
            C_Timer.After(0.05, function() CUI:RefreshPage(true) end)
        end
        local values, sequence = { [""] = "Automatic (talents)" }, { "" }
        for _, spec in ipairs(SWt.Specs()) do
            values[spec.key] = spec.name
            sequence[#sequence + 1] = spec.key
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "STAT WEIGHTS", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Upgrades on Tooltips",
            tooltip = "Gear that is an upgrade for your spec says so on its tooltip, as a percent over what you wear. The BiS window shows each pick's gain too. An estimate from these weights.",
            getValue = function() return SWt.Get("enabled") end,
            setValue = function(val)
                rowConf.enabled = val and true or false
                Rebuild()
            end,
        }, {
            type = "dropdown",
            text = "Spec",
            values = values,
            order = sequence,
            tooltip = "Automatic weighs by the talent tree you spent most points in.",
            getValue = function() return rowConf.spec or "" end,
            setValue = function(val)
                rowConf.spec = val
                Rebuild()
            end,
        })
        cursorY = cursorY - height
        if SWt.Get("enabled") then
            local key = SWt.ActiveSpec()
            local weights = SWt.For(key) or {}
            local entries = {}
            for _, st in ipairs(SWt.Stats) do
                if (weights[st[1]] or 0) ~= 0 then entries[#entries + 1] = st end
            end
            local function Slider(st)
                if not st then return { type = "label", text = "" } end
                local max = st[3]
                local step = max >= 20 and 0.5 or (max >= 5 and 0.1 or (max >= 1 and 0.05 or 0.005))
                return {
                    type = "slider",
                    text = st[2],
                    min = 0,
                    max = max,
                    step = step,
                    isPercent = false,
                    getValue = function() return (SWt.For(key) or {})[st[1]] or 0 end,
                    setValue = function(val) SWt.Set(key, st[1], val) end,
                }
            end
            for idx = 1, #entries, 2 do
                _, height = W:DualRow(hostFrame, cursorY, Slider(entries[idx]), Slider(entries[idx + 1]))
                cursorY = cursorY - height
            end
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "labeledButton",
                text = "Weights for " .. (SWt.Spec(key) and SWt.Spec(key).name or "?"),
                buttonText = "Reset",
                width = 90,
                tooltip = "Put this spec's weights back to the defaults.",
                onClick = function()
                    SWt.Reset(key)
                    Rebuild()
                end,
            }, { type = "label", text = "Main stat, Spell Damage, Healing or Stamina is 1." })
            cursorY = cursorY - height
        end
    end

    ---------------------------------------------------------------------------
    --  JUNK ITEMS (the rows after the toggle are built while the window is
    --  on; the toggle rebuilds the page)
    ---------------------------------------------------------------------------
    local JI = CUI._JunkItems
    local function junkOff() return not JI.Get("enabled") end
    -- Every write re-applies the window.
    local function JunkSet(key, val)
        JI.Cfg()[key] = val
        JI.Apply()
    end
    local function ClearJunkExclusions()
        CUI:ShowConfirmPopup({
            title = CUI.L("Clear Excluded Items"),
            message = CUI.L(
                "Every item you middle-clicked away can show in the Junk Items window again."
            ),
            confirmText = CUI.L("Clear"),
            cancelText = CANCEL,
            onConfirm = JI.ClearExclusions,
        })
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height
    heading, height = W:SectionHeader(hostFrame, "JUNK ITEMS", cursorY)
    cursorY = cursorY - height
    CUI.BuildSectionUnlockJump(
        heading,
        { key = "CUI_JunkList", disabled = junkOff, disabledTooltip = "Junk Items Window" }
    )

    _, height = CUI.BuildVisibilityRow(W, hostFrame, cursorY, {
        leftCfg = {
            type = "toggle",
            text = "Enable Junk Items Window",
            tooltip = "Shows your cheapest junk in a small window.",
            getValue = function() return not junkOff() end,
            setValue = CUI.SectionToggleSetValue(function(val) JunkSet("enabled", val) end),
        },
        -- The window's table exists once it was turned on, and the row is
        -- greyed out while it is off, so viewing the page saves nothing.
        getStore = function() return junkOff() and JI.Read() or JI.Cfg() end,
        legacyKey = "visibility",
        caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
        disabledFn = junkOff,
        disabledTooltip = "Junk Items Window",
        onChanged = CUI.RequestVisibilityUpdate,
        onOptionChanged = CUI.RequestVisibilityUpdate,
    })
    cursorY = cursorY - height

    if not junkOff() then
        -- Rare and better are never junk by quality (and need DELETE typed), so
        -- both lists stop at Uncommon.
        local qualityValues, qualityOrder = _G._CUI_ItemQualityValues(Enum.ItemQuality.Uncommon)

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Items Shown",
            min = 1,
            max = 6,
            step = 1,
            isPercent = false,
            tooltip = "How many junk stacks the window lists.",
            getValue = function() return JI.Get("itemCount") end,
            setValue = function(val) JunkSet("itemCount", val) end,
        }, {
            type = "dropdown",
            text = "Maximum Quality",
            values = qualityValues,
            order = qualityOrder,
            tooltip = "Items above this quality are not shown, unless marked as junk in Bags.",
            getValue = function() return tostring(JI.Get("maxQuality")) end,
            setValue = function(val) JunkSet("maxQuality", tonumber(val)) end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Delete Without Confirming",
            values = qualityValues,
            order = qualityOrder,
            tooltip = "Items of this quality and below delete on the first Ctrl + Left Click. Higher-quality items need a second click, and Rare and above also need DELETE typed.",
            getValue = function() return tostring(JI.Get("oneClickQuality")) end,
            setValue = function(val) JunkSet("oneClickQuality", tonumber(val)) end,
        }, {
            type = "labeledButton",
            text = "Excluded Items",
            buttonText = "Clear",
            width = 90,
            tooltip = "Brings back items you middle-clicked away.",
            onClick = ClearJunkExclusions,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Icon Size",
            min = 16,
            max = 64,
            step = 1,
            isPercent = false,
            getValue = function() return JI.Get("iconSize") end,
            setValue = function(val) JunkSet("iconSize", val) end,
        }, {
            type = "slider",
            text = "Icon Spacing",
            tooltip = "Prices that don't fit show only their largest coin.",
            min = 0,
            max = 30,
            step = 1,
            isPercent = false,
            getValue = function() return JI.Get("iconSpacing") end,
            setValue = function(val) JunkSet("iconSpacing", val) end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Price Position",
            values = { bottom = "Below Icon", top = "Above Icon" },
            order = { "bottom", "top" },
            getValue = function() return JI.Get("priceSide") end,
            setValue = function(val) JunkSet("priceSide", val) end,
        }, {
            type = "toggle",
            text = "Show Empty Bag Slots",
            tooltip = "Shows free and total bag slots as the title.",
            getValue = function() return JI.Get("showFreeSlots") == true end,
            setValue = function(val) JunkSet("showFreeSlots", val) end,
        })
        cursorY = cursorY - height

        -- Only Show When Bag Space Is Low (its threshold in the cog) | Use Auctionator Prices
        local lowRow
        lowRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Only Show When Bag Space Is Low",
            tooltip = "Shows the window only while few bag slots are free. Use the cog to set how few.",
            getValue = function() return JI.Get("onlyLowBagSpace") == true end,
            setValue = function(val)
                JunkSet("onlyLowBagSpace", val)
                CUI:RefreshPage() -- the cog's disabled state
            end,
        }, {
            type = "toggle",
            text = "Use Auctionator Prices",
            tooltip = "Prices items from Auctionator scans.",
            disabled = function() return CUI._ModuleNS["CludesUIForeverEssentials"].AuctionAPI() == nil end,
            disabledTooltip = "This option requires Auctionator to be loaded.",
            getValue = function() return JI.Get("auctionPrices") == true end,
            setValue = function(val) JunkSet("auctionPrices", val) end,
        })
        cursorY = cursorY - height
        if not CUI._prebuilding then
            CUI.BuildInlineCog(lowRow._leftRegion, {
                title = "Only Show When Bag Space Is Low",
                disabled = function() return JI.Get("onlyLowBagSpace") ~= true end,
                disabledTooltip = "Only Show When Bag Space Is Low",
                rows = {
                    {
                        type = "slider",
                        label = "Free-Slot Threshold",
                        min = 1,
                        max = 100,
                        step = 1,
                        tooltip = "Shows the window while fewer regular bag slots than this are free.",
                        get = function() return JI.Get("freeSlotThreshold") end,
                        set = function(val) JunkSet("freeSlotThreshold", val) end,
                    },
                },
            })
        end
    end

    ---------------------------------------------------------------------------
    --  FISHING (CludesUIForeverEssentials_Fishing.lua)
    ---------------------------------------------------------------------------
    local FI = CUI._Fishing
    local function SetFish(key, val)
        FI.Cfg()[key] = val
        FI.Apply()
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height
    heading, height = W:SectionHeader(hostFrame, "FISHING", cursorY)
    cursorY = cursorY - height
    -- The Bobber Indicator's mover exists only while the indicator can show:
    -- the Fishing Key bound with Reel In and Bobber Indicator on (the cog's
    -- rows), so the button names whichever of the three is missing.
    CUI.BuildSectionUnlockJump(heading, {
        key = "CUI_FishingBobber",
        disabled = function() return FI.Get("key") == nil or not FI.Get("reel") or not FI.Get("indicator") end,
        disabledTooltip = function()
            if FI.Get("key") == nil then return "Fishing Key" end
            if not FI.Get("reel") then return "Reel In With the Key" end
            return "Bobber Indicator"
        end,
    })

    -- Fishing Key (keybind, its options in the cog) | Double-Click to Cast
    local fishKeyRow
    fishKeyRow, height = W:DualRow(hostFrame, cursorY, {
        type = "label",
        text = "Fishing Key",
        tooltip = "One key casts your line, equipping your best fishing pole first. Use the cog for reeling in, the bobber indicator and lures.",
    }, {
        type = "toggle",
        text = "Double-Click to Cast",
        tooltip = "With a fishing pole in hand, double right-click the world to cast.",
        disabled = function() return CUI.PadGamepadUI() end,
        disabledTooltip = "This option does not work with the Gamepad interface style.",
        getValue = function() return FI.Get("doubleClick") end,
        setValue = function(val)
            SetFish("doubleClick", val)
            CUI:RefreshPage() -- the cog's disabled state
        end,
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        local region = fishKeyRow._leftRegion
        local kbBtn, refresh = CUI.BuildKeybindButton(region, {
            w = 140,
            h = 30,
            font = 13,
            get = function() return FI.Get("key") end,
            set = function(val)
                SetFish("key", val)
                CUI:RefreshPage() -- the cog's disabled state
            end,
            tooltip = "Left-click to set a keybind.\nRight-click to unbind.",
        })
        CUI.PanelPP.Point(kbBtn, "RIGHT", region, "RIGHT", -20, 0)
        CUI.RegisterWidgetRefresh(refresh)

        local function fishRow(labelText, tooltip, key)
            return {
                type = "toggle",
                label = labelText,
                tooltip = tooltip,
                get = function() return FI.Get(key) end,
                set = function(val) SetFish(key, val) end,
            }
        end
        -- A label half has no control: the cog sits left of the keybind
        -- button, which also bounds the label.
        CUI.BuildInlineCog(region, {
            title = "Fishing Key",
            rows = {
                fishRow(
                    "Reel In With the Key",
                    "Once the bobber bites and is on screen, the Fishing Key reels it in.",
                    "reel"
                ),
                fishRow(
                    "Bobber Indicator",
                    "Shows whether the key will reel in. Place it in Edit Layout.",
                    "indicator"
                ),
                fishRow(
                    "Apply Lure",
                    "With no lure on your pole, the key applies your best lure first.",
                    "lure"
                ),
            },
            anchorTo = kbBtn,
            disabled = function() return FI.Get("key") == nil end,
            disabledTooltip = "Fishing Key",
        })
        CUI.BuildInlineCog(fishKeyRow._rightRegion, {
            title = "Double-Click to Cast",
            rows = {
                fishRow(
                    "Apply Lure",
                    "With no lure on your pole, a double-click applies your best lure first.",
                    "clickLure"
                ),
            },
            disabled = function() return CUI.PadGamepadUI() or not FI.Get("doubleClick") end,
            disabledTooltip = function()
                if CUI.PadGamepadUI() then
                    return "This option does not work with the Gamepad interface style."
                end
                return "Double-Click to Cast"
            end,
        })
    end

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Fishing Sounds",
        tooltip = "While you fish: music and ambience down, effects up, sound on in the background.",
        getValue = function() return FI.Get("sound") end,
        setValue = function(val) SetFish("sound", val) end,
    }, {
        type = "toggle",
        text = "Auto Loot While Fishing",
        tooltip = "While you fish, the catch loots itself; your own auto loot setting comes back when you stop.",
        getValue = function() return FI.Get("autoLoot") end,
        setValue = function(val) SetFish("autoLoot", val) end,
    })
    cursorY = cursorY - height

    -- GLIMMER (CludesUIForeverEssentials_Glimmer.lua).
    local GL = CUI._Glimmer
    if GL then
        local function glOff() return not GL.Get("enabled") end
        local function GLSet(key, val, refresh)
            GL.Cfg()[key] = val
            GL.Apply()
            if refresh then CUI:RefreshPage() end
        end
        local function Tog(key, textValue, tipText, off, refresh)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = off,
                getValue = function() return GL.Get(key) == true end,
                setValue = function(val) GLSet(key, val and true or false, refresh) end,
            }
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "GLIMMER", cursorY)
        cursorY = cursorY - height
        local lookRow
        lookRow, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "enabled",
                "Object Highlights",
                "Herbs, ore, chests, quest objects and quest givers light up as you walk up to them, herbs and ore in the color of your chance to raise your skill, with a line under them. It turns the game's soft interact targeting on while it is on, and puts your settings back when you turn it off. Rests in combat.",
                nil,
                true
            ),
            {
                type = "dropdown",
                text = "Effect",
                disabled = glOff,
                values = { glow = "Glow", sparkles = "Sparkles", ring = "Ring", beam = "Beam", brackets = "Brackets" },
                order = { "glow", "sparkles", "ring", "beam", "brackets" },
                getValue = function() return GL.Get("style") end,
                setValue = function(val) GLSet("style", val) end,
            }
        )
        cursorY = cursorY - height
        if not CUI._prebuilding then
            CUI.BuildInlineCog(lookRow._rightRegion, {
                disabled = glOff,
                disabledTooltip = "Object Highlights",
                title = "Glimmer Look",
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 60,
                        max = 160,
                        step = 5,
                        get = function() return math.floor(GL.Get("size") * 100 + 0.5) end,
                        set = function(val) GLSet("size", val / 100) end,
                    },
                    {
                        type = "slider",
                        label = "Brightness",
                        min = 30,
                        max = 150,
                        step = 5,
                        get = function() return math.floor(GL.Get("brightness") * 100 + 0.5) end,
                        set = function(val) GLSet("brightness", val / 100) end,
                    },
                    {
                        type = "slider",
                        label = "Reach (yards)",
                        min = 5,
                        max = 15,
                        step = 1,
                        get = function() return GL.Get("range") end,
                        set = function(val) GLSet("range", math.floor(val + 0.5)) end,
                    },
                    {
                        type = "toggle",
                        label = "Skill-up Colors",
                        get = function() return GL.Get("skillColors") == true end,
                        set = function(val) GLSet("skillColors", val) end,
                    },
                    {
                        type = "toggle",
                        label = "Line Under It",
                        tooltip = "Skill-up chance, the skill needed, or the quest objective.",
                        get = function() return GL.Get("showLine") == true end,
                        set = function(val) GLSet("showLine", val) end,
                    },
                    {
                        type = "toggle",
                        label = "Hide in Dungeons",
                        get = function() return GL.Get("hideInstance") == true end,
                        set = function(val) GLSet("hideInstance", val) end,
                    },
                    {
                        type = "toggle",
                        label = "Hide What You Cannot Gather",
                        get = function() return GL.Get("hideLocked") == true end,
                        set = function(val) GLSet("hideLocked", val) end,
                    },
                },
            })
        end
        local NAMES = {
            ore = "Ore",
            herb = "Herbs",
            quest = "Quest Objects",
            giver = "Quest Givers",
            chest = "Chests",
            bobber = "Fishing Bobber",
            corpse = "Lootable Corpses",
        }
        local cats = GL.Categories
        for idx = 1, #cats, 2 do
            local function Cat(key)
                if not key then return { type = "label", text = "" } end
                return Tog(key, NAMES[key], nil, glOff)
            end
            local catRow
            catRow, height = W:DualRow(hostFrame, cursorY, Cat(cats[idx]), Cat(cats[idx + 1]))
            cursorY = cursorY - height
            if not CUI._prebuilding then
                for side, key in pairs({ _leftRegion = cats[idx], _rightRegion = cats[idx + 1] }) do
                    CUI.BuildInlineSwatches(catRow[side], {
                        {
                            tooltip = NAMES[key] .. " Color",
                            getValue = function() return GL.Get(key .. "R"), GL.Get(key .. "G"), GL.Get(key .. "B"), 1 end,
                            setValue = function(red, green, blue)
                                local c = GL.Cfg()
                                c[key .. "R"], c[key .. "G"], c[key .. "B"] = red, green, blue
                                GL.Apply()
                            end,
                        },
                    }, { disabled = glOff, disabledTooltip = "Object Highlights" })
                end
            end
        end
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "minimapIcons",
                "Herb and Ore Spots on the Minimap",
                "Every spot herbs and ore grow near you, on the minimap, ringed in your skill-up color. With Find Herbs or Find Minerals on, the game's own dot shows inside the ring when the node is up.",
                glOff
            ),
            Tog(
                "gatheredPins",
                "Gathered on the World Map",
                "Each herb and vein you gather goes on the world map, with how many times you have gathered it.",
                glOff
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("myProfessions", "Only My Gathering Skills", "Minimap spots only for Herbalism or Mining you have.", glOff),
            {
                type = "slider",
                text = "Minimap Spot Size",
                min = 10,
                max = 24,
                step = 1,
                isPercent = false,
                disabled = glOff,
                getValue = function() return GL.Get("minimapSize") end,
                setValue = function(val) GLSet("minimapSize", math.floor(val + 0.5)) end,
            }
        )
        cursorY = cursorY - height
    end

    -- GUIDE WINDOW (CludesUIForeverEssentials_GuideWindow.lua).
    local GUIDE = CUI._GuideWindow
    if GUIDE then
        local function gwOff() return not GUIDE.Get("enabled") end
        local function GWSet(key, val, refresh)
            GUIDE.Cfg()[key] = val
            GUIDE.Apply()
            if refresh then CUI:RefreshPage() end
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        local gwHeading
        gwHeading, height = W:SectionHeader(hostFrame, "GUIDE WINDOW", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(gwHeading, { key = "CUI_GuideWindow", disabled = gwOff, disabledTooltip = "Guide Window" })
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "RestedXP Guide Window",
            tooltip = "Shows your RestedXP levelling guide in a CludesUI window in place of RestedXP's own: the guide and its progress, the active steps with their objectives, and the next steps. Shift-click a step to skip it or go to it; right-click for RestedXP's menu. Needs RestedXP with its V2 interface turned on.",
            getValue = function() return GUIDE.Get("enabled") end,
            setValue = function(val) GWSet("enabled", val and true or false, true) end,
        }, {
            type = "dropdown",
            text = "Skipping Steps",
            disabled = gwOff,
            values = { shift = "Shift-click", click = "Click", off = "Off" },
            order = { "shift", "click", "off" },
            getValue = function() return GUIDE.Get("skip") end,
            setValue = function(val) GWSet("skip", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Width",
            min = 260,
            max = 640,
            step = 10,
            isPercent = false,
            disabled = gwOff,
            getValue = function() return GUIDE.Get("width") end,
            setValue = function(val) GWSet("width", math.floor(val + 0.5)) end,
        }, {
            type = "slider",
            text = "Next Steps Shown",
            min = 0,
            max = 12,
            step = 1,
            isPercent = false,
            disabled = gwOff,
            getValue = function() return GUIDE.Get("steps") end,
            setValue = function(val) GWSet("steps", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Lock Window",
            disabled = gwOff,
            getValue = function() return GUIDE.Get("lock") == true end,
            setValue = function(val) GWSet("lock", val and true or false) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    return math.abs(cursorY)
end
