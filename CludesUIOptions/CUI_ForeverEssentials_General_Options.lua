if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_General_Options.lua
--  Builds the "General" page inside the Forever Essentials module: its
--  general quality of life features, one section each.
-------------------------------------------------------------------------------
if not CludesUI._ModuleNS["CludesUIForeverEssentials"] then return end  -- module disabled: no options page

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
local function ModeOf(v) return (v == nil or v == "full") and "full" or v end
local function Stored(v) return (v ~= "full") and v or nil end
-- One value while every input agrees, "mixed" once two differ (nil: none yet).
local function Merge(acc, m)
    if acc == nil or acc == m then return m end
    return "mixed"
end

-- The rows in page order: { text, tooltip, get, set [, disabled, disabledTooltip] }.
local function NameFormatSources()
    local list, MNS = {}, CludesUI.ModuleNS

    -- Unit Frames: every text slot (the list the Unit Frames options publish).
    -- The slots that show a name on a frame of ours that is shown (its frame
    -- source, as the Unit Frames pages test it) decide what it reads; a pick
    -- sets every slot, so a text switched to a name later follows it.
    local uf = MNS("CludesUIUnitFrames")
    local slots = uf and uf.db and uf.UF_NAME_FORMAT_SLOTS
    if slots then
        list[#list + 1] = { text = "Unit Frames", tooltip = "Player names in every unit frame text that shows a name.",
            get = function()
                local p, shown, all = uf.db.profile, nil, nil
                for i = 1, #slots do
                    local e = slots[i]
                    local s = p[e.unit]
                    if s and uf.GetUnitFrameSource(e.unit) == "cui" then
                        local m = ModeOf(s[e.format])
                        -- A power text without Custom never names, so it does
                        -- not count toward the fallback either.
                        if not e.power or s[e.content] == "custom" then all = Merge(all, m) end
                        -- A power text shows while its position is set and, under a
                        -- stock style, Hide Power Bar leaves it (ApplyPowerPercentText).
                        local powerShown = not e.power or ((s[e.power] or "none") ~= "none"
                            and not (uf.UF_Blizz() and uf.UF_IsMainSettings(s) and uf.UF_StockHidesPower(s)))
                        if uf.UF_ContentShowsName(s[e.content], s[e.custom]) and (not e.btb or s.bottomTextBar)
                           and powerShown then
                            shown = Merge(shown, m)
                        end
                    end
                end
                return shown or all or "full"
            end,
            set = function(v)
                local p, mode = uf.db.profile, Stored(v)
                for i = 1, #slots do
                    local s = p[slots[i].unit]
                    if s then s[slots[i].format] = mode end
                end
                uf.ReloadFrames()
            end }
    end

    -- Raid Frames: the raid key, and the party's while its Text Display is
    -- unsynced (Raid Frames saves "full"; an unset party key reads the raid's).
    local rf = MNS("CludesUIRaidFrames")
    if rf and rf.db then
        local function partyOwn() return rf._IsPartySectionCustom("textDisplay") end
        list[#list + 1] = { text = "Raid & Party Frames", tooltip = "Player names on raid and party frames.",
            get = function()
                local p = rf.db.profile
                local m = ModeOf(p.nameFormat)
                if partyOwn() and p.party_nameFormat ~= nil then m = Merge(m, ModeOf(p.party_nameFormat)) end
                return m
            end,
            set = function(v)
                local p = rf.db.profile
                p.nameFormat = v
                -- A party key left from an unsync is set too, or a later unsync
                -- would bring the old value back.
                if partyOwn() or p.party_nameFormat ~= nil then p.party_nameFormat = v end
                rf._BumpAbsorbGen()
                rf.ReloadFrames()
                rf.ReloadPartyFrames()
            end }
    end

    -- Nameplates: the enemy name, Target of Target and Custom slots showing a name
    -- or a target (a pick sets every slot's key, so a text moved later keeps it),
    -- then the friendly players.
    local np = MNS("CludesUINameplates")
    if np and np.db then
        local slotKeys, formatKey = np.textSlotKeys, {}
        for _, slot in ipairs(slotKeys) do formatKey[slot] = slot .. "NameFormat" end
        list[#list + 1] = { text = "Enemy Player Nameplates",
            tooltip = "Enemy player names on nameplates, and their targets when they are players.",
            get = function()
                local p, m = np.db.profile, nil
                local nameSlot, totSlot = np.FindNameSlot(), np._npToTSlot
                if nameSlot then m = ModeOf(p[formatKey[nameSlot]]) end
                if totSlot then m = Merge(m, ModeOf(p[formatKey[totSlot]])) end
                for i = 1, #slotKeys do
                    local slot = slotKeys[i]
                    local parsed = p[slot] == "custom" and np.NP_CustomParse(slot)
                    if parsed and (parsed.has.name or parsed.has.target) then
                        m = Merge(m, ModeOf(p[formatKey[slot]]))
                    end
                end
                if not m then
                    for i = 1, #slotKeys do m = Merge(m, ModeOf(p[formatKey[slotKeys[i]]])) end
                end
                return m or "full"
            end,
            set = function(v)
                local p, mode = np.db.profile, Stored(v)
                for i = 1, #slotKeys do p[formatKey[slotKeys[i]]] = mode end
                np.RefreshAllSettings()
            end }
        list[#list + 1] = { text = "Friendly Player Nameplates",
            tooltip = "Friendly player names on nameplates, in both modes.",
            disabled = function() return np.db.profile.showFriendlyPlayers == false end,
            disabledTooltip = "Show CUI Friendly Player Nameplates",
            get = function() return ModeOf(np.db.profile.friendlyNameFormat) end,
            set = function(v)
                np.db.profile.friendlyNameFormat = Stored(v)
                np.NP_SyncFriendlyNameFormat()
            end }
    end

    -- Damage Meters: one key for every window.
    local dm = MNS("CludesUIDamageMeters")
    if dm and _G._EDM_DB then
        local DMCfg = dm.EDM.DB
        list[#list + 1] = { text = "Damage Meters",
            tooltip = "Player names on the meter bars.",
            get = function() return ModeOf(DMCfg().nameFormat) end,
            set = function(v)
                DMCfg().nameFormat = Stored(v)
                dm.RefreshNames()
            end }
    end

    -- The threat meter (this module; account-wide like its other settings).
    local TM = CludesUI._ThreatMeter
    list[#list + 1] = { text = "Threat Meter",
        tooltip = "Player names on the threat meter, for all your characters.",
        disabled = function() return not TM.Get("enabled") end, disabledTooltip = "Threat Meter",
        get = function() return ModeOf(TM.Get("nameFormat")) end,
        set = function(v)
            TM.Cfg().nameFormat = Stored(v)
            TM.ApplyStyle()
        end }
    return list
end

_G._CUI_BuildForeverGeneralPage = function(pageName, parent, yOffset)
    local W = CludesUI.Widgets
    local SU, CS, CT = CludesUI._SpellUprank, CludesUI._ClassicSpellbook, CludesUI._ClassicTalents
    local MT = CludesUI._MapTravel
    local BLANK = CludesUI.BlankRowCfg
    local y = yOffset
    local _, h, hdr
    parent._showRowDivider = true

    ---------------------------------------------------------------------------
    --  GENERAL: Auto Uprank Spells on Bars | Classic Windows (the vanilla
    --  spellbook and talent window as one checkbox dropdown), then Most
    --  Valuable Quest Reward (CludesUIForeverEssentials_QuestRewards.lua) |
    --  Gathering Skill in Tooltips (CludesUIForeverEssentials_GatherSkill.lua,
    --  its Minimap row in the cog), then Auto Summon Pet | Favorites per
    --  Character. Every control reads and writes its feature's own key and
    --  runs that feature's own apply.
    ---------------------------------------------------------------------------
    local QR, GS = CludesUI._QuestRewards, CludesUI._GatherSkill
    _, h = W:SectionHeader(parent, "GENERAL", y);  y = y - h

    local CW_LABEL = "Classic Windows"
    local cwItems = {
        { key = "spellbook", label = "Classic Spellbook",
          tooltip = "Your spellbook key and the micro menu's Spellbook button open the vanilla spellbook.",
          read = function() return CS.Get("enabled") end,
          write = function(v)
              CS.Cfg().enabled = v
              CS.Apply()
          end },
        { key = "talents", label = "Classic Talents",
          tooltip = "Your talents key and the micro menu's Talents button open the vanilla talent window.",
          read = function() return CT.Get("enabled") end,
          write = function(v)
              CT.Cfg().enabled = v
              CT.Apply()
          end },
    }
    -- Global search sees row labels and tooltips only, so this row's entry,
    -- registered before the row (the index keeps the first one), carries the
    -- dropdown's names as search text; it is never shown.
    if CludesUI._RegisterSearchEntry then
        local words = {}
        for i = 1, #cwItems do
            local s = cwItems[i].label
            words[#words + 1] = s
            local loc = CludesUI.L(s)
            if loc ~= s then words[#words + 1] = loc end
        end
        local labelLoc = CludesUI.L(CW_LABEL)
        CludesUI._RegisterSearchEntry(CW_LABEL, labelLoc ~= CW_LABEL and labelLoc or nil,
            table.concat(words, " "), CludesUI._buildingModule, CludesUI._buildingPage,
            parent._currentSection and parent._currentSection._sectionName)
    end

    local generalRow
    generalRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Auto Uprank Spells on Bars",
          tooltip = "Swaps new spell ranks, yours and your pet's, onto your action bars.",
          getValue = function() return SU.Get("enabled") end,
          setValue = function(v)
              SU.Cfg().enabled = v
              SU.Apply()
          end },
        { type = "label", text = CW_LABEL,
          tooltip = "Choose which windows open in their classic version." }
    );  y = y - h
    if not CludesUI._prebuilding then
        local rgn = generalRow._rightRegion
        local byKey = {}
        for i = 1, #cwItems do byKey[cwItems[i].key] = cwItems[i] end
        local cwDD, cwRefresh = CludesUI.BuildVisOptsCBDropdown(
            rgn, 210, rgn:GetFrameLevel() + 2, cwItems,
            function(key) return byKey[key].read() end,
            function(key, v) byKey[key].write(v) end)
        CludesUI.PanelPP.Point(cwDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cwDD
        rgn._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cwRefresh)
    end

    local rewardRow
    rewardRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Most Valuable Quest Reward",
          tooltip = "Among a quest's reward choices, a money bag marks the one that sells for most, its count included.",
          getValue = function() return QR.Get("enabled") end,
          setValue = function(v)
              QR.Cfg().enabled = v
              QR.Apply()
          end },
        { type = "toggle", text = "Gathering Skill in Tooltips",
          tooltip = "Adds the skill a herb or ore node needs to its tooltip, colored by your chance to raise your skill there.",
          getValue = function() return GS.Get("enabled") end,
          setValue = function(v)
              GS.Cfg().enabled = v
              GS.Apply()
              CludesUI:RefreshPage()  -- the cog's disabled state
          end }
    );  y = y - h
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(rewardRow._rightRegion, {
            title = "Gathering Skill in Tooltips",
            rows = {
                { type = "toggle", label = "Minimap",
                  tooltip = "Also adds the required skill to herb and ore names on the minimap.",
                  get = function() return GS.Get("minimap") end,
                  set = function(v)
                      GS.Cfg().minimap = v
                      GS.Apply()
                  end },
            },
            disabled = function() return not GS.Get("enabled") end,
            disabledTooltip = "Gathering Skill in Tooltips",
        })
    end

    -- Auto Summon Pet | Favorites per Character
    -- (CludesUIForeverEssentials_PetSummon.lua), while the Pet Journal exists.
    local PS = CludesUI._PetSummon
    if PS and C_PetJournal then
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Auto Summon Pet",
              tooltip = "Brings a random favorite pet back after loading screens, flights and deaths; a pet you dismiss stays away.",
              getValue = function() return PS.Get("enabled") end,
              setValue = function(v)
                  PS.Cfg().enabled = v
                  PS.Apply(v)  -- turning it on also ends an earlier dismissal
                  CludesUI:RefreshPage()  -- Favorites per Character's disabled state
              end },
            { type = "toggle", text = "Favorites per Character",
              tooltip = "Pick this character's favorites from a pet's right-click menu in the Pet Journal.",
              disabled = function() return not PS.Get("enabled") end,
              disabledTooltip = "Auto Summon Pet",
              -- This character's own setting, read without creating its table.
              getValue = function()
                  local chars, guid = PS.Get("chars"), UnitGUID("player")
                  return chars ~= nil and guid ~= nil and chars[guid] ~= nil and chars[guid].own == true
              end,
              setValue = function(v)
                  local guid = UnitGUID("player")
                  if not guid then return end
                  local cfg = PS.Cfg()
                  cfg.chars = cfg.chars or {}
                  cfg.chars[guid] = cfg.chars[guid] or {}
                  cfg.chars[guid].own = v or nil
                  PS.RefreshJournal()
              end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  NAME FORMAT (while a module with a Name Format is on)
    ---------------------------------------------------------------------------
    local sources = NameFormatSources()
    if #sources > 0 then
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "NAME FORMAT", y);  y = y - h
        -- Placeholder dropdowns keep the labels, tooltips and search entries; the
        -- checkbox dropdowns replace them (DualRow only builds plain widgets).
        local function Slot(text, tooltip)
            return { type = "dropdown", text = text, tooltip = tooltip,
                values = { __placeholder = "..." }, order = { "__placeholder" },
                getValue = function() return "__placeholder" end,
                setValue = function() end }
        end
        local row
        row, h = W:DualRow(parent, y,
            Slot("First Name", "Checked modules show players' first names. A module checked in both lists shows the full name."),
            Slot("Last Name", "Checked modules show players' last names. A module checked in both lists shows the full name."));  y = y - h
        if not CludesUI._prebuilding then
            local PP = CludesUI.PanelPP
            -- A module that is switched off stays greyed out and out of "All".
            local items = {}
            for i = 1, #sources do
                local src = sources[i]
                items[i] = { key = i, label = src.text, tooltip = src.tooltip,
                    lockedFn = src.disabled, excludeFromSummaryFn = src.disabled,
                    lockedTooltip = src.disabled and function()
                        return CludesUI.DisabledTooltip(src.disabledTooltip)
                    end or nil }
            end
            -- Whether a row value shows that part of the name ("mixed" shows neither box).
            local function Has(m, part) return m == part or m == "full" end
            local function List(rgn, part)
                local other = (part == "first") and "last" or "first"
                if rgn._control then rgn._control:Hide() end
                -- 260 wide: room for the longest row label (Friendly Player
                -- Nameplates and its translations); longer ones end in "...".
                local dd, refresh = CludesUI.BuildVisOptsCBDropdown(
                    rgn, 260, rgn:GetFrameLevel() + 2, items,
                    function(i) return Has(sources[i].get(), part) end,
                    function(i, on)
                        local theirs = Has(sources[i].get(), other)
                        -- A name always shows: unchecking the last box keeps it.
                        if not (on or theirs) then return end
                        sources[i].set((on and theirs) and "full" or (on and part or other))
                        -- The other list reads the new value too.
                        CludesUI:RefreshPage()
                    end)
                PP.Point(dd, "RIGHT", rgn, "RIGHT", -20, 0)
                rgn._control = dd
                rgn._lastInline = nil
                CludesUI.RegisterWidgetRefresh(refresh)
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
    local MR = CludesUI._MapReveal
    local ZL = CludesUI._ZoneLevels
    local function revealOff() return not MR.Get("enabled") end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "WORLD MAP", y);  y = y - h

    -- Fade Map While Moving | Show the Game Behind the Map. Runtime in
    -- CludesUIForeverEssentials_MapFade.lua.
    local MF = CludesUI._MapFade
    local function SetFade(key, v)
        MF.Cfg()[key] = v
        MF.Apply()
    end

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Fade Map While Moving",
          tooltip = "The world map fades while you move and comes back when you stop or hover it.",
          getValue = function() return MF.Get("enabled") end,
          setValue = function(v) SetFade("enabled", v) end },
        { type = "toggle", text = "Show the Game Behind the Map",
          tooltip = "Lightens the black behind the maximized world map.",
          getValue = function() return MF.Get("dim") end,
          setValue = function(v) SetFade("dim", v) end }
    );  y = y - h

    local revealRow
    revealRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Reveal Unexplored Areas",
          tooltip = "Shows the parts of the world map you have not explored yet. Use the cog to pick their color.",
          getValue = function() return MR.Get("enabled") end,
          setValue = function(v)
              MR.Cfg().enabled = v
              MR.Apply()
              CludesUI:RefreshPage()  -- the cog's disabled state
          end },
        { type = "toggle", text = "Show Zone Levels",
          tooltip = "Shows the level range of the zone you hover on a continent of the world map, under its name, colored by difficulty.",
          getValue = function() return ZL.Get("enabled") end,
          setValue = function(v)
              ZL.Cfg().enabled = v
              ZL.Apply()
          end }
    );  y = y - h

    local markersRow
    markersRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Map Markers",
          tooltip = "Shows boats, zeppelins, dungeon entrances, flight points and zone exits on the world map; click one to link it in chat.",
          getValue = function() return MT.Get("enabled") end,
          setValue = function(v)
              MT.Cfg().enabled = v
              MT.Apply()
              CludesUI:RefreshPage()  -- the cog's disabled state
          end },
        { type = "toggle", text = "Show Fishing Skill",
          tooltip = "Shows the fishing skill a zone needs under its name on the world map: red, too low; yellow, fish still get away; green, none do.",
          getValue = function() return ZL.Get("fishing") end,
          setValue = function(v)
              ZL.Cfg().fishing = v
              ZL.Apply()
          end }
    );  y = y - h
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(revealRow._leftRegion, {
            title = "Reveal Unexplored Areas Settings",
            rows = {
                { type = "colorpicker", label = "Unexplored Color", hasAlpha = true,
                  tooltip = "Tints the areas you have not explored yet. White shows them as they are.",
                  get = function()
                      local c = MR.Get("color")
                      return c.r, c.g, c.b, c.a
                  end,
                  set = function(r, g, b, a)
                      MR.Cfg().color = { r = r, g = g, b = b, a = a or 1 }
                      MR.Apply()
                  end },
            },
            disabled = revealOff, disabledTooltip = "Reveal Unexplored Areas",
        })
    end

    -- Map Markers: one toggle; the cog picks the sets, all shown until turned
    -- off.
    if not CludesUI._prebuilding then
        local function setRow(label, tooltip, key)
            return { type = "toggle", label = label, tooltip = tooltip,
                get = function() return MT.Get(key) end,
                set = function(v)
                    MT.Cfg()[key] = v
                    MT.Apply()
                end }
        end
        local rows = {
            setRow("Transports",
                "Boats, zeppelins and the tram, from the world map down, with where each one goes when you hover it.",
                "transports"),
            setRow("Zone Exits",
                "On zone maps, an arrow on each road out of the zone, pointing to the zone it leads to.",
                "exits"),
            setRow("Instance Entrances",
                "Dungeon and raid entrances, on continent and zone maps; hover one for its name.",
                "instances"),
            setRow("Flight Points",
                "On zone maps, the flight masters, those you have not found yet included.",
                "flights"),
        }
        CludesUI.BuildInlineCog(markersRow._leftRegion, {
            title = "Map Markers",
            rows = rows,
            disabled = function() return not MT.Get("enabled") end,
            disabledTooltip = "Show Map Markers",
        })
    end

    ---------------------------------------------------------------------------
    --  SIMPLIFIED STATS (item tooltips)
    ---------------------------------------------------------------------------
    local SS = CludesUI._SimplifiedStats
    if SS then
        local function Set(k, v)
            SS.Cfg()[k] = v
            CludesUI:RefreshPage()  -- update the dependent rows' disabled state
        end
        local function shortenOff() return not SS.Get("shorten") end
        local function colorsOff() return not SS.Get("colors") end

        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "SIMPLIFIED STATS", y);  y = y - h

        -- Shorten Equip Lines | Color Stats
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Shorten Equip Lines",
              tooltip = "Shortens Equip: and Set: stat lines on item tooltips to +X Stat.",
              getValue = function() return SS.Get("shorten") end,
              setValue = function(v) Set("shorten", v) end },
            { type = "toggle", text = "Color Stats",
              tooltip = "Colors each stat name on item tooltips, enchants included, and its number per Number Color.",
              getValue = function() return SS.Get("colors") end,
              setValue = function(v) Set("colors", v) end }
        );  y = y - h

        -- Merge Equal Spell Power | Number Color
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Merge Equal Spell Power",
              tooltip = "Shows equal spell damage and healing as one Spell Power line.",
              disabled = shortenOff, disabledTooltip = "Shorten Equip Lines",
              getValue = function() return SS.Get("merge") end,
              setValue = function(v) Set("merge", v) end },
            { type = "dropdown", text = "Number Color",
              disabled = colorsOff, disabledTooltip = "Color Stats",
              values = { signed = "Green / Red", stat = "Stat Color", line = "Line Color" },
              order = { "signed", "stat", "line" },
              getValue = function() return SS.Get("numColor") end,
              setValue = function(v) SS.Cfg().numColor = (v ~= "signed") and v or nil end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  ACTIVE STANCE, FORM, ASPECT & AURA
    ---------------------------------------------------------------------------
    local AF = CludesUI._ActiveForm
    if AF then
        local function afOff() return not AF.Get("enabled") end
        local function AFSet(key, v)
            AF.Cfg()[key] = v
            AF.Apply()
        end
        local _, classFile = UnitClass("player")
        local label = classFile == "WARRIOR" and "Show Current Stance"
            or classFile == "DRUID" and "Show Current Form"
            or classFile == "PALADIN" and "Show Current Aura"
            or classFile == "HUNTER" and "Show Current Aspect"
            or "Show Current Stance / Form"

        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "ACTIVE STANCE, FORM, ASPECT & AURA", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_ActiveForm", disabled = afOff, disabledTooltip = label })

        _, h = CludesUI.BuildVisibilityRow(W, parent, y, {
            leftCfg = { type = "toggle", text = label,
                tooltip = "Shows an icon for your active stance, form, aura or aspect. Hidden while none is active.",
                getValue = function() return not afOff() end,
                setValue = CludesUI.SectionToggleSetValue(function(v) AFSet("enabled", v) end) },
            -- The table exists once it was turned on, and the row is greyed out
            -- while it is off, so viewing the page saves nothing.
            getStore = function() return afOff() and AF.Read() or AF.Cfg() end,
            caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
            disabledFn = afOff, disabledTooltip = label,
            onChanged = CludesUI.RequestVisibilityUpdate,
            onOptionChanged = CludesUI.RequestVisibilityUpdate,
        });  y = y - h

        if not afOff() then
            -- Icon Size | Icon Zoom
            _, h = W:DualRow(parent, y,
                { type = "slider", text = "Icon Size",
                  min = 16, max = 96, step = 1, isPercent = false,
                  getValue = function() return AF.Get("iconSize") end,
                  setValue = function(v) AFSet("iconSize", v) end },
                { type = "slider", text = "Icon Zoom",
                  tooltip = "Crops the icon's edges.",
                  min = 0, max = 25, step = 1, isPercent = false,
                  getValue = function() return AF.Get("zoom") end,
                  setValue = function(v) AFSet("zoom", v) end }
            );  y = y - h

            -- Border Style | Border Size (+ color swatch)
            local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
            local borderRow
            borderRow, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Border Style",
                  values = texValues, order = texOrder,
                  getValue = function() return AF.Get("borderTexture") end,
                  setValue = function(v)
                      local c = AF.Cfg()
                      c.borderTexture = v
                      c.borderTextureOffset, c.borderTextureOffsetY = nil, nil
                      local color = CludesUI.GetBorderStyleSelectDefaults(v)
                      c.borderR, c.borderG, c.borderB, c.borderA = color.r, color.g, color.b, 1
                      local defaultSize = CludesUI.GetBorderDefaultSize(nil, v)
                      if defaultSize then c.borderSize = defaultSize end
                      if c.borderSizePx then c.borderSizePx = false end
                      AF.Apply()
                      -- Rebuild: the offset row follows the Solid / textured pick.
                      CludesUI:RefreshPage(true)
                  end },
                CludesUI.BorderPxSliderCfg{
                  text = "Border Size",
                  getStep = function() return AF.Get("borderSize") end,
                  setStep = function(v) AF.Cfg().borderSize = v end,
                  getTex = function() return AF.Get("borderTexture") end,
                  getPx = function() return AF.Read().borderSizePx end,
                  setPx = function(v) AF.Cfg().borderSizePx = v end,
                  apply = AF.Apply }
            );  y = y - h

            if not CludesUI._prebuilding then
                local rgn = borderRow._rightRegion
                local swatch, updateSwatch = CludesUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        return AF.Get("borderR"), AF.Get("borderG"), AF.Get("borderB"), AF.Get("borderA")
                    end,
                    function(r, g, b, a)
                        local c = AF.Cfg()
                        c.borderR, c.borderG, c.borderB, c.borderA = r, g, b, a or 1
                        AF.Apply()
                    end, true, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
                rgn._lastInline = swatch
                CludesUI.RegisterWidgetRefresh(updateSwatch)
            end

            -- Width | Height Offset: only while a textured style is selected.
            local texKey = AF.Get("borderTexture")
            if texKey ~= "" and texKey ~= "solid" then
                local offL, offR = CludesUI.BorderOffsetRowCfgs{
                    getTex = function() return AF.Get("borderTexture") end,
                    getStep = function() return AF.Get("borderSize") end,
                    getSizeKey = function() return AF.Get("borderSize") end,
                    getPx = function() return AF.Read().borderSizePx end,
                    getX = function() return AF.Read().borderTextureOffset end,
                    setX = function(v) AF.Cfg().borderTextureOffset = v end,
                    getY = function() return AF.Read().borderTextureOffsetY end,
                    setY = function(v) AF.Cfg().borderTextureOffsetY = v end,
                    apply = AF.Apply,
                }
                _, h = W:DualRow(parent, y, offL, offR);  y = y - h
            end
        end
    end

    ---------------------------------------------------------------------------
    --  TRACKING REMINDER
    ---------------------------------------------------------------------------
    local TR = CludesUI._TrackingReminder
    if TR then
        local function trOff() return not TR.Get("enabled") end
        local function TRSet(key, v) TR.Cfg()[key] = v; TR.Apply() end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "TRACKING REMINDER", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_TrackingReminder", disabled = trOff, disabledTooltip = "Tracking Reminder" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Tracking Reminder",
              tooltip = "A row of icons for the tracking you know but have not turned on: Find Treasure, hunter tracks, Track Humanoids in Cat Form, Sense Undead, Sense Demons. Click one to turn it on. Hidden in combat.",
              getValue = function() return not trOff() end,
              setValue = function(v) TRSet("enabled", v and true or false) end },
            { type = "toggle", text = "Include Find Herbs and Minerals",
              disabled = trOff,
              getValue = function() return TR.Get("gathering") end,
              setValue = function(v) TRSet("gathering", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Icon Size", min = 16, max = 64, step = 1, isPercent = false,
              disabled = trOff,
              getValue = function() return TR.Get("iconSize") end,
              setValue = function(v) TRSet("iconSize", math.floor(v + 0.5)) end },
            { type = "label", text = "" }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  SWING TIMER
    ---------------------------------------------------------------------------
    local STm = CludesUI._SwingTimer
    if STm then
        local function stOff() return not STm.Get("enabled") end
        local function STSet(key, v) STm.Cfg()[key] = v; STm.Apply() end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "SWING TIMER", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_SwingTimer", disabled = stOff, disabledTooltip = "Swing Timer" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Swing Timer",
              tooltip = "A bar per weapon that fills to your next auto attack. The game sends each swing's real length, so haste and parry haste are already counted.",
              getValue = function() return not stOff() end,
              setValue = function(v) STSet("enabled", v and true or false) end },
            { type = "toggle", text = "Hide When Idle", disabled = stOff,
              tooltip = "Hide a bar when that weapon has not swung for a moment.",
              getValue = function() return STm.Get("hideIdle") end,
              setValue = function(v) STSet("hideIdle", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Off Hand Bar", disabled = stOff,
              getValue = function() return STm.Get("offHand") end,
              setValue = function(v) STSet("offHand", v and true or false) end },
            { type = "toggle", text = "Ranged Bar", disabled = stOff,
              getValue = function() return STm.Get("ranged") end,
              setValue = function(v) STSet("ranged", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Width", min = 80, max = 400, step = 1, isPercent = false, disabled = stOff,
              getValue = function() return STm.Get("width") end,
              setValue = function(v) STSet("width", math.floor(v + 0.5)) end },
            { type = "slider", text = "Height", min = 6, max = 30, step = 1, isPercent = false, disabled = stOff,
              getValue = function() return STm.Get("height") end,
              setValue = function(v) STSet("height", math.floor(v + 0.5)) end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  MANA BAR AND FIVE-SECOND RULE
    ---------------------------------------------------------------------------
    local DM = CludesUI._DruidMana
    if DM then
        local function dmOff() return not DM.Get("enabled") end
        local function DMSet(key, v) DM.Cfg()[key] = v; DM.Apply() end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "MANA BAR", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_ManaBar", disabled = dmOff, disabledTooltip = "Mana Bar" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Mana Bar",
              tooltip = "Shows a druid's mana while in Bear, Cat or another form that hides it.",
              getValue = function() return not dmOff() end,
              setValue = function(v) DMSet("enabled", v and true or false) end },
            { type = "toggle", text = "Five-Second Rule", disabled = dmOff,
              tooltip = "A line under the bar counts down five seconds after you spend mana, while spirit regen is paused.",
              getValue = function() return DM.Get("fiveSecond") end,
              setValue = function(v) DMSet("fiveSecond", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Always Show", disabled = dmOff,
              tooltip = "Show the bar all the time, for any class with mana, not only a druid in a form.",
              getValue = function() return DM.Get("always") end,
              setValue = function(v) DMSet("always", v and true or false) end },
            { type = "slider", text = "Width", min = 80, max = 400, step = 1, isPercent = false, disabled = dmOff,
              getValue = function() return DM.Get("width") end,
              setValue = function(v) DMSet("width", math.floor(v + 0.5)) end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  CONSUMABLE BAR
    ---------------------------------------------------------------------------
    local CB = CludesUI._ConsumableBar
    if CB then
        local function cbOff() return not CB.Get("enabled") end
        local function CBSet(key, v) CB.Cfg()[key] = v; CB.Apply() end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "CONSUMABLE BAR", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_ConsumableBar", disabled = cbOff, disabledTooltip = "Consumable Bar" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Consumable Bar",
              tooltip = "The consumables in your bags on a bar you can click, with how many you carry and their cooldowns. It works in combat; an item you run out of in a fight keeps its icon until the fight ends.",
              getValue = function() return not cbOff() end,
              setValue = function(v) CBSet("enabled", v and true or false) end },
            { type = "slider", text = "Icon Size", min = 16, max = 64, step = 1, isPercent = false, disabled = cbOff,
              getValue = function() return CB.Get("iconSize") end,
              setValue = function(v) CBSet("iconSize", math.floor(v + 0.5)) end }
        );  y = y - h
        local cats = CB.Categories
        for i = 1, #cats, 2 do
            local function Toggle(c)
                if not c then return { type = "label", text = "" } end
                return { type = "toggle", text = c.label, disabled = cbOff,
                         getValue = function() return CB.Get(c.key) end,
                         setValue = function(v) CBSet(c.key, v and true or false) end }
            end
            _, h = W:DualRow(parent, y, Toggle(cats[i]), Toggle(cats[i + 1]));  y = y - h
        end
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Most Icons", min = 1, max = 30, step = 1, isPercent = false, disabled = cbOff,
              getValue = function() return CB.Get("maxIcons") end,
              setValue = function(v) CBSet("maxIcons", math.floor(v + 0.5)) end },
            { type = "label", text = "" }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  RAID DEBUFFS
    ---------------------------------------------------------------------------
    local RD = CludesUI._RaidDebuffs
    if RD then
        local function rdOff() return not RD.Get("enabled") end
        local function RDSet(key, v) RD.Cfg()[key] = v; RD.Apply() end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "RAID DEBUFFS", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_RaidDebuffs", disabled = rdOff, disabledTooltip = "Raid Debuffs" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Raid Debuffs",
              tooltip = "Icons on your enemy target for the raid debuffs you pick: bright while up with their time, dim while missing. Changes to the picks apply out of combat.",
              getValue = function() return not rdOff() end,
              setValue = function(v) RDSet("enabled", v and true or false) end },
            { type = "toggle", text = "Only in a Group", disabled = rdOff,
              getValue = function() return RD.Get("groupOnly") end,
              setValue = function(v) RDSet("groupOnly", v and true or false) end }
        );  y = y - h
        local list = RD.Debuffs
        for i = 1, #list, 2 do
            local function Toggle(d)
                if not d then return { type = "label", text = "" } end
                return { type = "toggle", text = d.label, disabled = rdOff,
                         getValue = function() return RD.Get("pick_" .. d.key) end,
                         setValue = function(v) RDSet("pick_" .. d.key, v and true or false) end }
            end
            _, h = W:DualRow(parent, y, Toggle(list[i]), Toggle(list[i + 1]));  y = y - h
        end
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Icon Size", min = 16, max = 64, step = 1, isPercent = false, disabled = rdOff,
              getValue = function() return RD.Get("iconSize") end,
              setValue = function(v) RDSet("iconSize", math.floor(v + 0.5)) end },
            { type = "label", text = "" }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  GEAR SETS
    ---------------------------------------------------------------------------
    local GS = CludesUI._GearSets
    if GS then
        local function gsOff() return not GS.Get("enabled") end
        local function GSSet(key, v) GS.Cfg()[key] = v; GS.Apply() end
        local function SetChoices()
            local values, order = { [""] = "None" }, { "" }
            for _, s in ipairs(GS.List()) do values[s.name] = s.name; order[#order + 1] = s.name end
            return values, order
        end
        local values, order = SetChoices()
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "GEAR SETS", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_GearSets", disabled = gsOff, disabledTooltip = "Gear Sets" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Gear Sets Bar",
              tooltip = "Your equipment sets on a bar; click one to wear it. The set you are wearing is lit. Armour cannot change in combat, so a click in combat waits for the fight to end.",
              getValue = function() return not gsOff() end,
              setValue = function(v) GSSet("enabled", v and true or false) end },
            { type = "input", text = "Save What You Wear", inputWidth = 140, inputStyle = "popup",
              placeholder = "Set name",
              tooltip = "Type a name to save the gear you have on as a set. Using an existing name saves over it.",
              getValue = function() return "" end,
              setValue = function(text) GS.Save(text); C_Timer.After(0.5, function() CludesUI:RefreshPage(true) end) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "While Mounted", values = values, order = order, disabled = gsOff,
              tooltip = "Wear this set while mounted, and put your gear back when you dismount.",
              getValue = function() return GS.Get("mountedSet") end,
              setValue = function(v) GSSet("mountedSet", v) end },
            { type = "dropdown", text = "While Resting", values = values, order = order, disabled = gsOff,
              tooltip = "Wear this set in an inn or a city, and put your gear back when you leave.",
              getValue = function() return GS.Get("restingSet") end,
              setValue = function(v) GSSet("restingSet", v) end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  INSTANCE TRACKER
    ---------------------------------------------------------------------------
    local IT = CludesUI._InstanceTracker
    if IT then
        local function itOff() return not IT.Get("enabled") end
        local function ITSet(key, v) IT.Cfg()[key] = v; IT.Apply() end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "INSTANCE TRACKER", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_InstanceTracker", disabled = itOff, disabledTooltip = "Instance Tracker" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Instance Tracker",
              tooltip = "Counts the new dungeons and raids your account enters in a rolling hour against the cap, times your runs, and prints a summary when you leave. Re-entering the same copy does not count again.",
              getValue = function() return not itOff() end,
              setValue = function(v) ITSet("enabled", v and true or false) end },
            { type = "slider", text = "Hourly Cap", min = 1, max = 30, step = 1, isPercent = false, disabled = itOff,
              tooltip = "WoW Forever allows 10 new instances an hour per account. Change this only if the game does.",
              getValue = function() return IT.Get("cap") end,
              setValue = function(v) ITSet("cap", math.floor(v + 0.5)) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show the Counter", disabled = itOff,
              getValue = function() return IT.Get("hud") end,
              setValue = function(v) ITSet("hud", v and true or false) end },
            { type = "toggle", text = "Summary When You Leave", disabled = itOff,
              getValue = function() return IT.Get("summary") end,
              setValue = function(v) ITSet("summary", v and true or false) end }
        );  y = y - h
        if not itOff() then
            local runs = IT.Runs()
            for i = 1, math.min(#runs, 6), 2 do
                local function Run(r)
                    if not r then return { type = "label", text = "" } end
                    return { type = "label", text = ("%s  |cff9aa6b2%d:%02d, %d deaths, %d items|r"):format(
                        r.name or "?", math.floor(r.seconds / 60), r.seconds % 60, r.deaths or 0, r.items or 0) }
                end
                _, h = W:DualRow(parent, y, Run(runs[i]), Run(runs[i + 1]));  y = y - h
            end
        end
    end

    ---------------------------------------------------------------------------
    --  GROUP INSPECT
    ---------------------------------------------------------------------------
    if CludesUI._GroupInspect then
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "GROUP INSPECT", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Group Inspect", buttonText = "Open", width = 90,
              tooltip = "Everyone in your group with their level, item level and unenchanted slots. Click a name to open the game's inspect window on them. /cinspect opens it too.",
              onClick = function() CludesUI._GroupInspect.Show() end },
            { type = "label", text = "Players out of range answer when they come closer." }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  COMBAT EXTRAS
    ---------------------------------------------------------------------------
    local CE = CludesUI._CombatExtras
    if CE then
        local function Set(f, key, v) f.Cfg()[key] = v; f.Apply() end
        local function Off(f) return function() return not f.Get("enabled") end end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "COMBAT EXTRAS", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Combat Timer",
              tooltip = "How long the current fight has run, held for a few seconds after it ends. Move it in Layout Mode.",
              getValue = function() return CE.timer.Get("enabled") end,
              setValue = function(v) Set(CE.timer, "enabled", v and true or false) end },
            { type = "toggle", text = "Fight Length in Chat", disabled = Off(CE.timer),
              getValue = function() return CE.timer.Get("chat") end,
              setValue = function(v) Set(CE.timer, "chat", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Combat Alert",
              tooltip = "+ Combat and - Combat fade in the middle of the screen as you enter and leave combat.",
              getValue = function() return CE.alert.Get("enabled") end,
              setValue = function(v) Set(CE.alert, "enabled", v and true or false) end },
            { type = "toggle", text = "Alert Sound", disabled = Off(CE.alert),
              getValue = function() return CE.alert.Get("sound") end,
              setValue = function(v) Set(CE.alert, "sound", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Stealth Reminder",
              tooltip = "For rogues, and druids in Cat Form: Not stealthed shows while you are out of combat and out of stealth. Never in an inn or a city, or while mounted.",
              getValue = function() return CE.stealth.Get("enabled") end,
              setValue = function(v) Set(CE.stealth, "enabled", v and true or false) end },
            { type = "toggle", text = "Only in a Group", disabled = Off(CE.stealth),
              getValue = function() return CE.stealth.Get("groupOnly") end,
              setValue = function(v) Set(CE.stealth, "groupOnly", v and true or false) end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  BAG SPACE
    ---------------------------------------------------------------------------
    local BS = CludesUI._BagSpace
    if BS then
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "BAG SPACE", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_BagSpace", disabled = function() return not BS.Get("enabled") end, disabledTooltip = "Bag Space" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Bag Space",
              tooltip = "Free bag slots on screen, amber when nearly full and red when full. Hover it for the cheapest items you carry; click it to open your bags.",
              getValue = function() return BS.Get("enabled") end,
              setValue = function(v) BS.Cfg().enabled = v and true or false; BS.Apply() end },
            { type = "toggle", text = "Warn When Nearly Full", disabled = function() return not BS.Get("enabled") end,
              getValue = function() return BS.Get("warn") end,
              setValue = function(v) BS.Cfg().warn = v and true or false; BS.Apply() end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  QUEST AUTOMATION
    ---------------------------------------------------------------------------
    local QA = CludesUI._QuestAutomation
    if QA then
        local function qaOff() return not QA.Get("enabled") end
        local function QASet(key, v) QA.Cfg()[key] = v and true or false; QA.Apply() end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "QUEST AUTOMATION", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Quest Automation",
              tooltip = "Accepts and turns in quests for you. Hold Shift while talking to an NPC to do it yourself. With a choice of rewards it always stops for you to pick.",
              getValue = function() return not qaOff() end,
              setValue = function(v) QASet("enabled", v) end },
            { type = "toggle", text = "Skip Grey Quests", disabled = qaOff,
              tooltip = "Leave quests far below your level alone.",
              getValue = function() return QA.Get("skipGrey") end,
              setValue = function(v) QASet("skipGrey", v) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Auto Accept", disabled = qaOff,
              getValue = function() return QA.Get("accept") end,
              setValue = function(v) QASet("accept", v) end },
            { type = "toggle", text = "Auto Turn In", disabled = qaOff,
              getValue = function() return QA.Get("turnIn") end,
              setValue = function(v) QASet("turnIn", v) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Progress to Party", disabled = qaOff,
              tooltip = "Says your quest objective progress (Kobold Vermin slain: 4/10) in party chat. Never in a raid.",
              getValue = function() return QA.Get("progress") end,
              setValue = function(v) QASet("progress", v) end },
            { type = "label", text = "" }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  ACTION BAR PROFILES
    ---------------------------------------------------------------------------
    local AP = CludesUI._ActionBarProfiles
    if AP then
        local cfg = AP.Cfg()
        local names = AP.Names()
        local values, order = {}, {}
        for _, n in ipairs(names) do values[n] = n; order[#order + 1] = n end
        if #names == 0 then values[""] = "None saved"; order[1] = "" end
        if not values[cfg.selected or ""] then cfg.selected = names[1] or "" end
        local function Rebuild() C_Timer.After(0.1, function() CludesUI:RefreshPage(true) end) end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "ACTION BAR PROFILES", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "input", text = "Save Your Bars", inputWidth = 140, inputStyle = "popup", placeholder = "Profile name",
              tooltip = "Saves every action bar slot under this name, for any character of your class on this account. /cbars save <name> does the same.",
              getValue = function() return "" end,
              setValue = function(text) AP.Save(text); cfg.selected = (text or ""):match("^%s*(.-)%s*$"); Rebuild() end },
            { type = "toggle", text = "Include Keybinds",
              tooltip = "Also save and load your keybinds with the bars.",
              getValue = function() return AP.Get("bindings") end,
              setValue = function(v) cfg.bindings = v and true or false end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Profile", values = values, order = order,
              getValue = function() return cfg.selected or "" end,
              setValue = function(v) cfg.selected = v end },
            { type = "labeledButton", text = "Load It", buttonText = "Load", width = 90,
              tooltip = "Puts the profile on your bars. Spells you have not learned and items you do not carry are skipped. Out of combat only.",
              onClick = function() if cfg.selected and cfg.selected ~= "" then AP.Load(cfg.selected) end end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Delete It", buttonText = "Delete", width = 90,
              onClick = function() if cfg.selected and cfg.selected ~= "" then AP.Delete(cfg.selected); cfg.selected = nil; Rebuild() end end },
            { type = "label", text = "" }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  LOOT SPARKLES
    ---------------------------------------------------------------------------
    local LS = CludesUI._LootSparkles
    if LS then
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "LOOT SPARKLES", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Quest Item Sparkles",
              tooltip = "Keeps the game's sparkle on lootable quest items, even after a graphics preset turns it off. Your outline mode is left as you set it. Switching this off takes effect after restarting the game.",
              getValue = function() return LS.Get("enabled") end,
              setValue = function(v) LS.SetEnabled(v) end },
            { type = "label", text = "Turning it off needs a game restart." }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  BEST IN SLOT
    ---------------------------------------------------------------------------
    local BI = CludesUI._BiS
    if BI then
        local function BSet(key, v) BI.Cfg()[key] = v and true or false end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "BEST IN SLOT", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Your BiS List", buttonText = "Open", width = 90,
              tooltip = "Your pick for every gear slot and whether you have it. Alt+Shift-click any item to add or remove it. Shared by your characters of this class. /cbis opens it too.",
              onClick = function() BI.Show() end },
            { type = "toggle", text = "Alt+Shift-Click to Add",
              getValue = function() return BI.Get("enabled") end,
              setValue = function(v) BSet("enabled", v) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Mark BiS on Tooltips",
              getValue = function() return BI.Get("tooltip") end,
              setValue = function(v) BSet("tooltip", v) end },
            { type = "toggle", text = "Drop Alert",
              tooltip = "A warning, a sound and a chat line when a BiS item you do not have drops: in the loot window, or looted by anyone near you.",
              getValue = function() return BI.Get("alert") end,
              setValue = function(v) BSet("alert", v) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "input", text = "Export", inputWidth = 160, inputStyle = "popup",
              tooltip = "Copy this line to share your list.",
              getValue = function() return BI.Export() end,
              setValue = function() end },
            { type = "input", text = "Import", inputWidth = 160, inputStyle = "popup", placeholder = "CUIBIS1:...",
              tooltip = "Paste a CludesUI BiS line for your class. It replaces your list.",
              getValue = function() return "" end,
              setValue = function(text) BI.Import(text) end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  JUNK ITEMS (the rows after the toggle are built while the window is
    --  on; the toggle rebuilds the page)
    ---------------------------------------------------------------------------
    local JI = CludesUI._JunkItems
    local function junkOff() return not JI.Get("enabled") end
    -- Every write re-applies the window.
    local function JunkSet(key, v)
        JI.Cfg()[key] = v
        JI.Apply()
    end
    local function ClearJunkExclusions()
        CludesUI:ShowConfirmPopup({
            title       = CludesUI.L("Clear Excluded Items"),
            message     = CludesUI.L("Every item you middle-clicked away can show in the Junk Items window again."),
            confirmText = CludesUI.L("Clear"),
            cancelText  = CANCEL,
            onConfirm   = JI.ClearExclusions,
        })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    hdr, h = W:SectionHeader(parent, "JUNK ITEMS", y);  y = y - h
    CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_JunkList", disabled = junkOff, disabledTooltip = "Junk Items Window" })

    _, h = CludesUI.BuildVisibilityRow(W, parent, y, {
        leftCfg = { type = "toggle", text = "Enable Junk Items Window",
            tooltip = "Shows your cheapest junk in a small window.",
            getValue = function() return not junkOff() end,
            setValue = CludesUI.SectionToggleSetValue(function(v) JunkSet("enabled", v) end) },
        -- The window's table exists once it was turned on, and the row is
        -- greyed out while it is off, so viewing the page saves nothing.
        getStore = function() return junkOff() and JI.Read() or JI.Cfg() end,
        legacyKey = "visibility",
        caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
        disabledFn = junkOff, disabledTooltip = "Junk Items Window",
        onChanged = CludesUI.RequestVisibilityUpdate,
        onOptionChanged = CludesUI.RequestVisibilityUpdate,
    });  y = y - h

    if not junkOff() then
        -- Rare and better are never junk by quality (and need DELETE typed), so
        -- both lists stop at Uncommon.
        local qualityValues, qualityOrder = _G._CUI_ItemQualityValues(Enum.ItemQuality.Uncommon)

        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Items Shown",
              min = 1, max = 6, step = 1, isPercent = false,
              tooltip = "How many junk stacks the window lists.",
              getValue = function() return JI.Get("itemCount") end,
              setValue = function(v) JunkSet("itemCount", v) end },
            { type = "dropdown", text = "Maximum Quality",
              values = qualityValues, order = qualityOrder,
              tooltip = "Items above this quality are not shown, unless marked as junk in Bags.",
              getValue = function() return tostring(JI.Get("maxQuality")) end,
              setValue = function(v) JunkSet("maxQuality", tonumber(v)) end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Delete Without Confirming",
              values = qualityValues, order = qualityOrder,
              tooltip = "Items of this quality and below delete on the first Ctrl + Left Click. Higher-quality items need a second click, and Rare and above also need DELETE typed.",
              getValue = function() return tostring(JI.Get("oneClickQuality")) end,
              setValue = function(v) JunkSet("oneClickQuality", tonumber(v)) end },
            { type = "labeledButton", text = "Excluded Items", buttonText = "Clear", width = 90,
              tooltip = "Brings back items you middle-clicked away.",
              onClick = ClearJunkExclusions }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Icon Size",
              min = 16, max = 64, step = 1, isPercent = false,
              getValue = function() return JI.Get("iconSize") end,
              setValue = function(v) JunkSet("iconSize", v) end },
            { type = "slider", text = "Icon Spacing",
              tooltip = "Prices that don't fit show only their largest coin.",
              min = 0, max = 30, step = 1, isPercent = false,
              getValue = function() return JI.Get("iconSpacing") end,
              setValue = function(v) JunkSet("iconSpacing", v) end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Price Position",
              values = { bottom = "Below Icon", top = "Above Icon" },
              order = { "bottom", "top" },
              getValue = function() return JI.Get("priceSide") end,
              setValue = function(v) JunkSet("priceSide", v) end },
            { type = "toggle", text = "Show Empty Bag Slots",
              tooltip = "Shows free and total bag slots as the title.",
              getValue = function() return JI.Get("showFreeSlots") == true end,
              setValue = function(v) JunkSet("showFreeSlots", v) end }
        );  y = y - h

        -- Only Show When Bag Space Is Low (its threshold in the cog) | Use Auctionator Prices
        local lowRow
        lowRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Only Show When Bag Space Is Low",
              tooltip = "Shows the window only while few bag slots are free. Use the cog to set how few.",
              getValue = function() return JI.Get("onlyLowBagSpace") == true end,
              setValue = function(v)
                  JunkSet("onlyLowBagSpace", v)
                  CludesUI:RefreshPage()  -- the cog's disabled state
              end },
            { type = "toggle", text = "Use Auctionator Prices",
              tooltip = "Prices items from Auctionator scans.",
              disabled = function()
                  return CludesUI._ModuleNS["CludesUIForeverEssentials"].AuctionAPI() == nil
              end,
              disabledTooltip = "This option requires Auctionator to be loaded.",
              getValue = function() return JI.Get("auctionPrices") == true end,
              setValue = function(v) JunkSet("auctionPrices", v) end }
        );  y = y - h
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(lowRow._leftRegion, {
                title = "Only Show When Bag Space Is Low",
                disabled = function() return JI.Get("onlyLowBagSpace") ~= true end,
                disabledTooltip = "Only Show When Bag Space Is Low",
                rows = {
                    { type = "slider", label = "Free-Slot Threshold", min = 1, max = 100, step = 1,
                      tooltip = "Shows the window while fewer regular bag slots than this are free.",
                      get = function() return JI.Get("freeSlotThreshold") end,
                      set = function(v) JunkSet("freeSlotThreshold", v) end },
                },
            })
        end
    end

    ---------------------------------------------------------------------------
    --  FISHING (CludesUIForeverEssentials_Fishing.lua)
    ---------------------------------------------------------------------------
    local FI = CludesUI._Fishing
    local function SetFish(key, v)
        FI.Cfg()[key] = v
        FI.Apply()
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    hdr, h = W:SectionHeader(parent, "FISHING", y);  y = y - h
    -- The Bobber Indicator's mover exists only while the indicator can show:
    -- the Fishing Key bound with Reel In and Bobber Indicator on (the cog's
    -- rows), so the button names whichever of the three is missing.
    CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_FishingBobber",
        disabled = function() return FI.Get("key") == nil or not FI.Get("reel") or not FI.Get("indicator") end,
        disabledTooltip = function()
            if FI.Get("key") == nil then return "Fishing Key" end
            if not FI.Get("reel") then return "Reel In With the Key" end
            return "Bobber Indicator"
        end })

    -- Fishing Key (keybind, its options in the cog) | Double-Click to Cast
    local fishKeyRow
    fishKeyRow, h = W:DualRow(parent, y,
        { type = "label", text = "Fishing Key",
          tooltip = "One key casts your line, equipping your best fishing pole first. Use the cog for reeling in, the bobber indicator and lures." },
        { type = "toggle", text = "Double-Click to Cast",
          tooltip = "With a fishing pole in hand, double right-click the world to cast.",
          disabled = function() return CludesUI.PadGamepadUI() end,
          disabledTooltip = "This option does not work with the Gamepad interface style.",
          getValue = function() return FI.Get("doubleClick") end,
          setValue = function(v)
              SetFish("doubleClick", v)
              CludesUI:RefreshPage()  -- the cog's disabled state
          end }
    );  y = y - h
    if not CludesUI._prebuilding then
        local rgn = fishKeyRow._leftRegion
        local kbBtn, refresh = CludesUI.BuildKeybindButton(rgn, {
            w = 140, h = 30, font = 13,
            get = function() return FI.Get("key") end,
            set = function(v)
                SetFish("key", v)
                CludesUI:RefreshPage()  -- the cog's disabled state
            end,
            tooltip = "Left-click to set a keybind.\nRight-click to unbind.",
        })
        CludesUI.PanelPP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -20, 0)
        CludesUI.RegisterWidgetRefresh(refresh)

        local function fishRow(label, tooltip, key)
            return { type = "toggle", label = label, tooltip = tooltip,
                get = function() return FI.Get(key) end,
                set = function(v) SetFish(key, v) end }
        end
        -- A label half has no control: the cog sits left of the keybind
        -- button, which also bounds the label.
        CludesUI.BuildInlineCog(rgn, {
            title = "Fishing Key",
            rows = {
                fishRow("Reel In With the Key", "Once the bobber bites and is on screen, the Fishing Key reels it in.", "reel"),
                fishRow("Bobber Indicator", "Shows whether the key will reel in. Place it in Layout Mode.", "indicator"),
                fishRow("Apply Lure", "With no lure on your pole, the key applies your best lure first.", "lure"),
            },
            anchorTo = kbBtn,
            disabled = function() return FI.Get("key") == nil end,
            disabledTooltip = "Fishing Key",
        })
        CludesUI.BuildInlineCog(fishKeyRow._rightRegion, {
            title = "Double-Click to Cast",
            rows = { fishRow("Apply Lure", "With no lure on your pole, a double-click applies your best lure first.", "clickLure") },
            disabled = function() return CludesUI.PadGamepadUI() or not FI.Get("doubleClick") end,
            disabledTooltip = function()
                if CludesUI.PadGamepadUI() then return "This option does not work with the Gamepad interface style." end
                return "Double-Click to Cast"
            end,
        })
    end

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Fishing Sounds",
          tooltip = "While you fish: music and ambience down, effects up, sound on in the background.",
          getValue = function() return FI.Get("sound") end,
          setValue = function(v) SetFish("sound", v) end },
        BLANK()
    );  y = y - h

    return math.abs(y)
end
