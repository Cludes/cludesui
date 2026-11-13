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
    --  PLAYER HISTORY
    ---------------------------------------------------------------------------
    local PH = CludesUI._PlayerHistory
    if PH then
        local function Set(key, v) PH.Cfg()[key] = v; PH.Apply() end
        local function pOff() return not PH.Get("enabled") end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "PLAYER HISTORY", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Player History",
              tooltip = "Remembers the players you group with on this computer: how often, the dungeons and raids together, and your last sessions. /chistory lists them. Right-click a player for Player Note to tag them and write a note.",
              getValue = function() return not pOff() end,
              setValue = function(v) Set("enabled", v and true or false) end },
            { type = "toggle", text = "Record Chats", disabled = pOff,
              tooltip = "Also keeps your last whispers and group chat lines with each player.",
              getValue = function() return PH.Get("chats") end,
              setValue = function(v) Set("chats", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Forget After (days)", min = 7, max = 365, step = 1, isPercent = false, disabled = pOff,
              getValue = function() return PH.Get("days") end,
              setValue = function(v) PH.Cfg().days = math.floor(v + 0.5) end },
            { type = "toggle", text = "Notes on Tooltips",
              getValue = function() return PH.Get("tooltip") end,
              setValue = function(v) PH.Cfg().tooltip = v and true or false end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Player History", buttonText = "Open", width = 90,
              onClick = function() PH.Show() end },
            { type = "labeledButton", text = "Clear History (keeps notes)", buttonText = "Clear", width = 90,
              onClick = function() PH.Clear("history") end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  BOAT AND ZEPPELIN TIMERS
    ---------------------------------------------------------------------------
    local TR2 = CludesUI._Transport
    if TR2 then
        local function tOff() return not TR2.Get("enabled") end
        local function Set(key, v) TR2.Cfg()[key] = v; TR2.Apply() end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "BOAT AND ZEPPELIN TIMERS", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_ShipTimer", disabled = tOff, disabledTooltip = "Boat and Zeppelin Timer" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Boat and Zeppelin Timers",
              tooltip = "When each ship leaves and arrives, on minimap pins at its docks. A ship is timed when you ride it, when you click its pin as it arrives (left) or leaves (right), or from players who share timings.",
              getValue = function() return not tOff() end,
              setValue = function(v) Set("enabled", v and true or false) end },
            { type = "toggle", text = "Zone Timer", disabled = tOff,
              tooltip = "A list of the boats and zeppelins in your zone with their times. Move it in Layout Mode.",
              getValue = function() return TR2.Get("zone") end,
              setValue = function(v) Set("zone", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Share Timings", disabled = tOff,
              tooltip = "Sends the ships you time to your group and guild, and takes theirs, and the timings of ForeverTransport and NauticusClassic users.",
              getValue = function() return TR2.Get("share") end,
              setValue = function(v) Set("share", v and true or false) end },
            { type = "slider", text = "Text Size", min = 10, max = 24, step = 1, isPercent = false, disabled = tOff,
              getValue = function() return TR2.Get("size") end,
              setValue = function(v) Set("size", math.floor(v + 0.5)) end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  TOWN MAP
    ---------------------------------------------------------------------------
    local TWN = CludesUI._TownMap
    if TWN then
        local function nOff() return not TWN.Get("enabled") end
        local function Tog(key, text, tip, dis)
            return { type = "toggle", text = text, tooltip = tip, disabled = dis or nOff,
                     getValue = function() return TWN.Get(key) end,
                     setValue = function(v) TWN.Cfg()[key] = v and true or false; TWN.Apply() end }
        end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "TOWN MAP", y);  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("enabled", "Town Map", "Service NPCs for your faction, mailboxes and spirit healers on the world map. Hover a pin for its name.", function() return false end),
            Tog("capitalsOnly", "Vendors and Trainers Only in Cities", "Keeps vendors, trainers and the bank off questing maps. Flight masters, innkeepers and stable masters still show everywhere."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("minimapMail", "Mailboxes on Minimap", "Pins the mailboxes near you on the minimap."),
            Tog("minimapSpirit", "Spirit Healers on Minimap", "Pins the spirit healers near you on the minimap."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("mail", "Mailboxes", "Every mailbox, in towns and out in the world."),
            Tog("spirit", "Spirit Healers", "Every graveyard's spirit healer, in towns and out in the world."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("class", "Class Trainers", "Your own class's trainers only."),
            Tog("profession", "Profession Trainers"));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("flight", "Flight Masters", "Left to Map Markers when its Flight Points pins are on."),
            Tog("inn", "Innkeepers"));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("bank", "Bank and Auction House"),
            Tog("repair", "Repairs"));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("supplies", "Reagents, Ammo and Food"),
            Tog("stable", "Stable Masters", "Hunters only."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("vendors", "Other Vendors", "Trade goods and every other merchant."),
            { type = "slider", text = "Pin Size", min = 10, max = 32, step = 1, isPercent = false, disabled = nOff,
              getValue = function() return TWN.Get("size") end,
              setValue = function(v) TWN.Cfg().size = math.floor(v + 0.5); TWN.Apply() end });  y = y - h
    end

    ---------------------------------------------------------------------------
    --  PALADIN BLESSINGS
    ---------------------------------------------------------------------------
    local BL = CludesUI._Blessings
    if BL then
        local function bOff() return not BL.Get("enabled") end
        local function Set(key, v) BL.Cfg()[key] = v; BL.Apply() end
        local function Tog(key, text, tip)
            return { type = "toggle", text = text, tooltip = tip, disabled = bOff,
                     getValue = function() return BL.Get(key) end,
                     setValue = function(v) Set(key, v and true or false) end }
        end
        local function Slider(key, text, lo, hi, tip)
            return { type = "slider", text = text, tooltip = tip, min = lo, max = hi, step = 1, isPercent = false, disabled = bOff,
                     getValue = function() return BL.Get(key) end,
                     setValue = function(v) Set(key, math.floor(v + 0.5)) end }
        end
        local ROLE_VALUES = { none = "None", might = "Blessing of Might", wisdom = "Blessing of Wisdom", kings = "Blessing of Kings" }
        local ROLE_ORDER = { "none", "might", "wisdom", "kings" }
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "PALADIN BLESSINGS", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_BlessingBar", disabled = bOff, disabledTooltip = "Blessing Bar" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Blessing Bar",
              tooltip = "For paladins: your aura and a button per class in the group. Left-click a class to bless the next member who needs it, missing first; in combat each click steps to the next. Right-click a class for its blessing, its player list or the assignments. Plans are shared with the group's other paladins, and PallyPower users' plans are read too.",
              getValue = function() return not bOff() end,
              setValue = function(v) Set("enabled", v and true or false) end },
            { type = "labeledButton", text = "Assignments", buttonText = "Open", width = 90, disabled = bOff,
              tooltip = "Every paladin's blessing for each class and their aura, with Auto-Assign, a saved preset and a report to chat. Also /cbless.",
              onClick = function() BL.Open() end });  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("showAura", "Aura Button", "Casts your aura. Right-click it to choose which, wheel to cycle."),
            Tog("showFury", "Righteous Fury Button", "Casts Righteous Fury on yourself. A red ! means it is not up."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("showSeal", "Seal Button", "Casts your seal. Right-click it to choose which, wheel to cycle."),
            Tog("showAuto", "Auto Buff Button", "Left-click blesses the next player in need, right-click the next Greater Blessing."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("autoGreater", "Auto Buff Greater First", "Swaps the Auto Buff button: left-click casts a Greater Blessing, right-click a single one."),
            Tog("showClasses", "Class Buttons", "Off leaves only the Auto Buff button and the key bindings."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("playerList", "Player List", "Right-click a class to list its players: bless one, or give one their own blessing."),
            Tog("tooltips", "Show Tooltips", "A tooltip on each bar button."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("labels", "Class Labels", "Each class's name under its button, or beside it when the bar is vertical."),
            Tog("timers", "Minutes Left", "Minutes left on each class's shortest blessing, and on each player's."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("smart", "Smart Blessings", "No Wisdom for warriors and rogues, no Might for priests, mages and warlocks in the menus."),
            Tog("respect", "Respect Blessing Time", "Only bless players who are missing a blessing or running out."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("wait", "Wait for Players", "Cast a Greater Blessing only when the whole class is in range."),
            Tog("bench", "Hide the Bench", "In a raid dungeon, leave out the players outside its usual groups."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("inParty", "Use in Party", "Show the bar in a party. It always shows in a raid."),
            Tog("solo", "Use When Solo", "Show the bar when you are not in a group."));  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Main Tank Blessing", values = ROLE_VALUES, order = ROLE_ORDER, disabled = bOff,
              tooltip = "A warrior, druid or paladin marked as tank or main tank gets this instead of their class blessing.",
              getValue = function() return BL.Get("tank") end,
              setValue = function(v) Set("tank", v) end },
            { type = "dropdown", text = "Main Assist Blessing", values = ROLE_VALUES, order = ROLE_ORDER, disabled = bOff,
              tooltip = "A warrior, druid or paladin marked as main assist gets this instead of their class blessing.",
              getValue = function() return BL.Get("assist") end,
              setValue = function(v) Set("assist", v) end });  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("vertical", "Vertical Bar", "The bar grows down instead of right, with the class names beside the buttons."),
            { type = "dropdown", text = "Button Border", disabled = bOff,
              values = { black = "Black", status = "Status Color", none = "None" }, order = { "black", "status", "none" },
              tooltip = "With Status Color the class buttons show their state on their edge instead of tinting the icon: red missing, yellow running out, blue only players with their own.",
              getValue = function() return BL.Get("border") end,
              setValue = function(v) Set("border", v) end });  y = y - h
        _, h = W:DualRow(parent, y,
            Slider("size", "Button Size", 20, 60),
            Slider("spacing", "Button Spacing", 0, 30));  y = y - h
        _, h = W:DualRow(parent, y,
            Slider("groupGap", "Aura / Class Gap", 0, 40, "The extra gap between your own buttons and the class buttons."),
            Slider("perRow", "Class Buttons per Row", 1, 9));  y = y - h
        _, h = W:DualRow(parent, y,
            Slider("timerSize", "Timer Text Size", 8, 20),
            { type = "label", text = "Key bindings: Next Blessing and Next Greater Blessing, under CludesUI in the game's Key Bindings." });  y = y - h
    end

    ---------------------------------------------------------------------------
    --  DISCOVERY
    ---------------------------------------------------------------------------
    local DC = CludesUI._Discovery
    if DC then
        local function dOff() return not DC.Get("enabled") end
        local function Set(key, v) DC.Cfg()[key] = v; DC.Apply() end
        local function Tog(key, text, tip)
            return { type = "toggle", text = text, tooltip = tip, disabled = dOff,
                     getValue = function() return DC.Get(key) end,
                     setValue = function(v) Set(key, v and true or false) end }
        end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "DISCOVERY", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_DiscoveryTracker", disabled = dOff, disabledTooltip = "Discovery Tracker" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Discovery",
              tooltip = "A window (/cdiscovery) of the library books, the Cozy Sleeping Bag's hidden chain, the Field Journal, and every quest and rare by zone, with trackers and map pins.",
              getValue = function() return not dOff() end,
              setValue = function(v) Set("enabled", v and true or false) end },
            { type = "labeledButton", text = "Discovery Window", buttonText = "Open", width = 90, disabled = dOff,
              tooltip = "Opens the Discovery window. Also /cdiscovery.",
              onClick = function() DC.Open() end });  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("tracker", "Library Books Tracker", "Lists the books still to find in your zone, and the ones you carry. Its X closes it until you enter another zone. Move it in Layout Mode."),
            Tog("bagTracker", "Sleeping Bag Tracker", "From level 14 until you have the bag, the chain's next step on the same tracker."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("mapPins", "Library Book Pins", "A pin on the world map for each book you still need."),
            Tog("mapTurnIn", "Librarian Pin", "While you carry books, a pin at the librarian or mage trainer who takes them."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("bagMapPins", "Sleeping Bag Pins", "A pin on the world map at the chain's next step."),
            Tog("fieldJournal", "Count the Field Journal", "Counts the fish you catch, the herbs you pick from their nodes and the dishes you cook, for this character."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("nearby", "Nearby Book Alert", "A ping and a chat line when you come within range of a book you still need."),
            { type = "slider", text = "Alert Range (yards)", min = 10, max = 100, step = 5, isPercent = false, disabled = dOff,
              getValue = function() return DC.Get("nearbyRange") end,
              setValue = function(v) Set("nearbyRange", math.floor(v + 0.5)) end });  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("nearbyPing", "Alert Sound", "The map ping sound with the alert."),
            Tog("nearbyChat", "Alert Chat Line", "A chat line with the book's name and how far it is."));  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Map Pin Size", min = 12, max = 36, step = 1, isPercent = false, disabled = dOff,
              getValue = function() return DC.Get("pinSize") end,
              setValue = function(v) Set("pinSize", math.floor(v + 0.5)) end },
            { type = "label", text = "" });  y = y - h
    end

    ---------------------------------------------------------------------------
    --  QUEST LIST AND RARES (Discovery's last two tabs)
    ---------------------------------------------------------------------------
    local QL = CludesUI._QuestList
    if QL and DC then
        local function qOff() return not DC.Get("enabled") end
        local function Set(key, v) QL.Cfg()[key] = v; QL.Apply() end
        local function Tog(key, text, tip)
            return { type = "toggle", text = text, tooltip = tip, disabled = qOff,
                     getValue = function() return QL.Get(key) end,
                     setValue = function(v) Set(key, v and true or false) end }
        end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "QUEST LIST AND RARES", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_RareAlert", disabled = function() return qOff() or not QL.Get("rareAlert") end, disabledTooltip = "Rare Alert" })
        _, h = W:DualRow(parent, y,
            Tog("questPins", "Quest Giver Pins", "A ! on the world map at each quest giver with a quest you can take now. Green for dungeon quests, blue for repeatable ones."),
            Tog("pinGrey", "Low Level Quests", "Pins givers whose quests are grey to you too."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("chainsOnly", "Chains Only", "Pins only quests that are part of a chain, and dungeon quests."),
            Tog("rarePins", "Rare Pins", "A star on the world map where each rare spawns."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("rarePinsKilled", "Pins for Killed Rares", "Keeps the stars of rares you have killed, greyed."),
            { type = "slider", text = "Quest and Rare Pin Size", min = 12, max = 36, step = 1, isPercent = false, disabled = qOff,
              getValue = function() return QL.Get("pinSize") end,
              setValue = function(v) Set("pinSize", math.floor(v + 0.5)) end });  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("rareAlert", "Rare Alerts", "A card and a sound when a rare's nameplate, your target, your mouseover or the minimap shows one. Left-click the card to target it, right-click to close it. Move it in Layout Mode."),
            Tog("rareAlertKilled", "Alert for Killed Rares", "Also alerts for rares you have killed before."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("rareSound", "Alert Sound", "The Gruntling Horn with each alert."),
            Tog("rareAlertSkull", "Skull on Click", "Clicking the card also puts a skull on the rare. Your whole group sees the mark."));  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Alert Time (seconds)", min = 5, max = 60, step = 1, isPercent = false, disabled = qOff,
              getValue = function() return QL.Get("rareAlertTime") end,
              setValue = function(v) Set("rareAlertTime", math.floor(v + 0.5)) end },
            { type = "labeledButton", text = "Test the Alert", buttonText = "Test", width = 90, disabled = qOff,
              tooltip = "Shows the card for your target, or a sample rare.",
              onClick = function() QL.TestAlert() end });  y = y - h
    end

    ---------------------------------------------------------------------------
    --  AUCTION PRICES
    ---------------------------------------------------------------------------
    local AU = CludesUI._Auction
    if AU then
        local function aOff() return not AU.Get("enabled") end
        local function Set(key, v) AU.Cfg()[key] = v; AU.Apply(); CludesUI:RefreshPage() end
        local function Tog(key, text, tip)
            return { type = "toggle", text = text, tooltip = tip, disabled = aOff,
                     getValue = function() return AU.Get(key) end,
                     setValue = function(v) Set(key, v and true or false) end }
        end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "AUCTION PRICES", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Auction Prices",
              tooltip = "The lowest buyout of every item for your realm and faction: the prices of every Forever auction house when this version was built, then your own scans. Junk Items and the Loot Feed use them when Auctionator is not loaded.",
              getValue = function() return not aOff() end,
              setValue = function(v) Set("enabled", v and true or false) end },
            Tog("tooltip", "Price on Item Tooltips", "Item tooltips show the price of one and how old it is."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("panel", "Market Panel", "A panel beside the auction house with Scan Prices, your Watch List (/cwatch) and what your bags would fetch."),
            Tog("capture", "Keep Other Addons' Scans", "Also keeps the prices from full scans that other addons start, such as Auctionator."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("autoScan", "Scan on Opening", "Scans when you open the auction house and your last scan is old."),
            { type = "slider", text = "Scan When Older Than (min)", min = 5, max = 120, step = 5, isPercent = false,
              disabled = function() return aOff() or not AU.Get("autoScan") end,
              getValue = function() return AU.Get("autoMinutes") end,
              setValue = function(v) Set("autoMinutes", math.floor(v + 0.5)) end });  y = y - h
    end

    ---------------------------------------------------------------------------
    --  MAIL AND ALTS
    ---------------------------------------------------------------------------
    local MA = CludesUI._MailAlts
    if MA then
        local function Tog(key, text, tip)
            return { type = "toggle", text = text, tooltip = tip,
                     getValue = function() return MA.Get(key) end,
                     setValue = function(v) MA.Cfg()[key] = v and true or false; MA.Apply() end }
        end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "MAIL AND ALTS", y);  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("altCounts", "Alt Item Counts", "Item tooltips show how many your characters on this realm and faction hold in their bags, bank and mailbox. Each is counted once you log in on it, its bank once you open it."),
            Tog("mailAlts", "Alts Button on Mail", "An Alts button beside the mailbox's Send tab lists your characters with level and gold; pick one to fill the To box."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog("quickAttach", "Quick Attach", "An Attach button beside the Send tab: attach every trade good, one type of trade good, or your unbound gear in one click."),
            Tog("expiry", "Mail Expiry Warning", "At login, names any of your characters with mail expiring within three days."));  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Forget a Character", buttonText = "Forget", width = 90,
              tooltip = "Removes a deleted or moved character from the counts and the Alts list.",
              onClick = function(self) MA.Forget(self) end },
            { type = "label", text = "" });  y = y - h
    end

    ---------------------------------------------------------------------------
    --  LAYERS
    ---------------------------------------------------------------------------
    local LY = CludesUI._Layers
    if LY then
        local lt, ls = LY.tracker, LY.swap
        local function lOff() return not lt.Get("enabled") end
        local function Set(key, v) lt.Cfg()[key] = v; lt.Apply() end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "LAYERS", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_LayerTracker", disabled = lOff, disabledTooltip = "Layer Tracker" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Layer Tracker",
              tooltip = "Which layer of the zone you are on, read from the NPCs around you. Hover it for the layers seen in this zone.",
              getValue = function() return not lOff() end,
              setValue = function(v) Set("enabled", v and true or false) end },
            { type = "toggle", text = "Auto-Accept Layer Swap",
              tooltip = "Confirms the game's layer swap prompt when you join a group.",
              getValue = function() return ls.Get("enabled") end,
              setValue = function(v) ls.Cfg().enabled = v and true or false end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Countdown to a Layer Change", disabled = lOff,
              getValue = function() return lt.Get("countdown") end,
              setValue = function(v) Set("countdown", v and true or false) end },
            { type = "toggle", text = "Say When You Move", disabled = lOff,
              getValue = function() return lt.Get("chat") end,
              setValue = function(v) Set("chat", v and true or false) end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  XP PER HOUR AND GROUP XP
    ---------------------------------------------------------------------------
    local XP = CludesUI._XP
    if XP then
        local xt, gx = XP.ticker, XP.group
        local function Set(f, key, v) f.Cfg()[key] = v; f.Apply() end
        local function Tog(f, key, text, tip, off)
            return { type = "toggle", text = text, tooltip = tip, disabled = off,
                     getValue = function() return f.Get(key) end,
                     setValue = function(v) Set(f, key, v and true or false) end }
        end
        local function Num(f, key, text, min, max, step, off)
            return { type = "slider", text = text, min = min, max = max, step = step, isPercent = false, disabled = off,
                     getValue = function() return f.Get(key) end,
                     setValue = function(v) Set(f, key, math.floor(v + 0.5)) end }
        end
        local function xOff() return not xt.Get("enabled") end
        local function gOff() return not gx.Get("enabled") end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "XP PER HOUR", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_XPTicker", disabled = xOff, disabledTooltip = "XP per Hour" })
        _, h = W:DualRow(parent, y,
            Tog(xt, "enabled", "XP per Hour", "This session's XP per hour, the time to your next level, the session's time and how long your last levels took. Pause and reset on the card, or /cxp start, pause, reset."),
            Tog(xt, "hideResting", "Hide While Resting", nil, xOff));  y = y - h
        _, h = W:DualRow(parent, y, Tog(xt, "splits", "Show Level Times", nil, xOff), Num(xt, "history", "Levels Shown", 1, 10, 1, xOff));  y = y - h
        _, h = W:DualRow(parent, y, Num(xt, "size", "Text Size", 10, 28, 1, xOff), { type = "label", text = "" });  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "GROUP XP", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_GroupXP", disabled = gOff, disabledTooltip = "Group XP" })
        _, h = W:DualRow(parent, y,
            Tog(gx, "enabled", "Group XP", "A bar per group member with their level and XP. They need CludesUI or Naowh Forever, which share the same message."),
            Tog(gx, "showSelf", "Show Yourself", nil, gOff));  y = y - h
        _, h = W:DualRow(parent, y, Tog(gx, "raid", "Also in Raids", nil, gOff), Num(gx, "width", "Width", 160, 500, 10, gOff));  y = y - h
        _, h = W:DualRow(parent, y, Num(gx, "size", "Text Size", 8, 20, 1, gOff), { type = "label", text = "" });  y = y - h
    end

    ---------------------------------------------------------------------------
    --  RESTOCK AND REMINDERS
    ---------------------------------------------------------------------------
    local RM = CludesUI._Reminders
    if RM then
        local rs, lk, gr, tp = RM.restock, RM.lock, RM.gear, RM.talents
        local function Set(f, key, v) f.Cfg()[key] = v; if f.Apply then f.Apply() end end
        local function Tog(f, key, text, tip, off)
            return { type = "toggle", text = text, tooltip = tip, disabled = off,
                     getValue = function() return f.Get(key) end,
                     setValue = function(v) Set(f, key, v and true or false) end }
        end
        local function Num(f, key, text, min, max, step, off)
            return { type = "slider", text = text, min = min, max = max, step = step, isPercent = false, disabled = off,
                     getValue = function() return f.Get(key) end,
                     setValue = function(v) Set(f, key, math.floor(v + 0.5)) end }
        end
        local function rsOff() return not rs.Get("enabled") end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "RESTOCK REMINDER", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_Restock", disabled = rsOff, disabledTooltip = "Restock Reminder" })
        _, h = W:DualRow(parent, y,
            Tog(rs, "enabled", "Restock Reminder", "When you reach a city or inn, a flashing list of what you are short on. It stays up until you have what you need or leave."),
            Tog(rs, "buy", "Buy at Vendors", "At a vendor who sells them, tops your class reagents and ammo up to what you carry, and prints what it spent. Off by default: it spends gold for you.", rsOff)
        );  y = y - h
        _, h = W:DualRow(parent, y, Tog(rs, "reagents", "Class Reagents", nil, rsOff), Tog(rs, "ammo", "Ammo (thrown, arrows, shot)", nil, rsOff));  y = y - h
        _, h = W:DualRow(parent, y, Num(rs, "ammoTarget", "Ammo to Carry", 50, 4000, 50, rsOff), Tog(rs, "food", "Food & Drink", "Warriors and rogues do not need drink.", rsOff));  y = y - h
        _, h = W:DualRow(parent, y, Num(rs, "foodBelow", "Food & Drink Below", 1, 40, 1, rsOff), Tog(rs, "vendor", "Junk & Full Bags", nil, rsOff));  y = y - h
        _, h = W:DualRow(parent, y, Num(rs, "foodMinLevel", "Food Minimum Level", 0, 60, 1, rsOff), Num(rs, "foodMaxLevel", "Food Maximum Level", 0, 60, 1, rsOff));  y = y - h
        if rs.Class == "HUNTER" then
            _, h = W:DualRow(parent, y, Tog(rs, "hunterAmmo", "Hunter Ammo Reminder", "Reminds about your equipped ammo at its own amount.", rsOff),
                Num(rs, "hunterAmmoBelow", "Remind When Ammo Falls To", 50, 4000, 50, rsOff));  y = y - h
        end
        _, h = W:DualRow(parent, y, Num(rs, "bagsBelow", "Free Slots Below", 1, 20, 1, rsOff), Num(rs, "size", "Text Size", 10, 32, 1, rsOff));  y = y - h
        local reagents = rs.Reagents()
        for i = 1, #reagents, 2 do
            local function Carry(r)
                if not r then return { type = "label", text = "" } end
                return { type = "slider", text = r.name .. " to Carry", min = 0, max = 200, step = 1, isPercent = false, disabled = rsOff,
                         tooltip = "How many to carry. 0 stops reminding you about it.",
                         getValue = function() return rs.Target(r.item) end,
                         setValue = function(v)
                             local c = rs.Cfg(); c.targets = c.targets or {}; c.targets[r.item] = math.floor(v + 0.5); rs.Apply()
                         end }
            end
            _, h = W:DualRow(parent, y, Carry(reagents[i]), Carry(reagents[i + 1]));  y = y - h
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "OTHER REMINDERS", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_GearReminders", disabled = function() return not (gr.Get("worn") or gr.Get("pole")) end, disabledTooltip = "Gear Reminders" })
        _, h = W:DualRow(parent, y,
            Tog(lk, "enabled", "Lockpicking Skill", "Lockbox tooltips show the Lockpicking needed to open them, coloured by yours."),
            Tog(tp, "enabled", "Unspent Talent Points", "Text on screen while you have talent points to spend. Hidden in combat."));  y = y - h
        _, h = W:DualRow(parent, y,
            Tog(gr, "worn", "Worn Gear Reminder", "An icon while you wear Cloak of Hermitic Bliss in Wailing Caverns, so you remember to swap it."),
            Tog(gr, "pole", "Fishing Pole Reminder", "An icon while you have a fishing pole equipped."));  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Fishing Pole Shows In", values = { always = "Everywhere", instance = "Dungeons & Raids" }, order = { "always", "instance" },
              disabled = function() return not gr.Get("pole") end,
              getValue = function() return gr.Get("poleWhere") end,
              setValue = function(v) Set(gr, "poleWhere", v) end },
            Num(gr, "size", "Gear Icon Size", 20, 96, 1));  y = y - h
    end

    ---------------------------------------------------------------------------
    --  MANA EFFICIENCY
    ---------------------------------------------------------------------------
    local SE = CludesUI._SpellEfficiency
    if SE then
        local function seOff() return not SE.Get("enabled") end
        local function SESet(key, v) SE.Cfg()[key] = v end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "MANA EFFICIENCY", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Mana Efficiency",
              tooltip = "A line on a mana spell's tooltip (and a macro that casts one) with its healing or damage per mana and per second, with your spell power and talents counted.",
              getValue = function() return not seOff() end,
              setValue = function(v) SESet("enabled", v and true or false) end },
            { type = "dropdown", text = "Show", disabled = seOff,
              values = { all = "Healing and Damage", heal = "Healing Only", damage = "Damage Only" }, order = { "all", "heal", "damage" },
              getValue = function() return SE.Get("show") end,
              setValue = function(v) SESet("show", v) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Per Mana", disabled = seOff,
              getValue = function() return SE.Get("perMana") end,
              setValue = function(v) SESet("perMana", v and true or false) end },
            { type = "toggle", text = "Per Second", disabled = seOff,
              getValue = function() return SE.Get("perSecond") end,
              setValue = function(v) SESet("perSecond", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Per Mana per Second", disabled = seOff,
              getValue = function() return SE.Get("perManaSecond") end,
              setValue = function(v) SESet("perManaSecond", v and true or false) end },
            { type = "dropdown", text = "Style", disabled = seOff,
              values = { long = "Words (healing per mana)", short = "Short (HPM, HPS)" }, order = { "long", "short" },
              getValue = function() return SE.Get("style") end,
              setValue = function(v) SESet("style", v) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Count Spell Power", disabled = seOff,
              getValue = function() return SE.Get("bonus") end,
              setValue = function(v) SESet("bonus", v and true or false) end },
            { type = "toggle", text = "Count Talents", disabled = seOff,
              getValue = function() return SE.Get("talents") end,
              setValue = function(v) SESet("talents", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Decimals", min = 0, max = 2, step = 1, isPercent = false, disabled = seOff,
              getValue = function() return SE.Get("decimals") end,
              setValue = function(v) SESet("decimals", math.floor(v + 0.5)) end },
            { type = "label", text = "" }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  HEALER MANA AND PET TRACKER
    ---------------------------------------------------------------------------
    local GW = CludesUI._GroupWatch
    if GW then
        local hm, pt = GW.healer, GW.pet
        local function Set(f, key, v) f.Cfg()[key] = v; f.Apply() end
        local function hmOff() return not hm.Get("enabled") end
        local function ptOff() return not pt.Get("enabled") end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "HEALER MANA", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_HealerMana", disabled = hmOff, disabledTooltip = "Healer Mana" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Healer Mana",
              tooltip = "Your group's healers and their mana, lowest first, with a cup beside anyone drinking. Move it in Layout Mode.",
              getValue = function() return not hmOff() end,
              setValue = function(v) Set(hm, "enabled", v and true or false) end },
            { type = "dropdown", text = "Show In", disabled = hmOff,
              values = { instance = "Dungeons & Raids", group = "Any Group" }, order = { "instance", "group" },
              getValue = function() return hm.Get("where") end,
              setValue = function(v) Set(hm, "where", v) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Yourself", disabled = hmOff,
              getValue = function() return hm.Get("showSelf") end,
              setValue = function(v) Set(hm, "showSelf", v and true or false) end },
            { type = "toggle", text = "Mark Drinking", disabled = hmOff,
              getValue = function() return hm.Get("drinking") end,
              setValue = function(v) Set(hm, "drinking", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Width", min = 100, max = 300, step = 5, isPercent = false, disabled = hmOff,
              getValue = function() return hm.Get("width") end,
              setValue = function(v) Set(hm, "width", math.floor(v + 0.5)) end },
            { type = "slider", text = "Text Size", min = 8, max = 20, step = 1, isPercent = false, disabled = hmOff,
              getValue = function() return hm.Get("size") end,
              setValue = function(v) Set(hm, "size", math.floor(v + 0.5)) end }
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h
        hdr, h = W:SectionHeader(parent, "PET TRACKER", y);  y = y - h
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_PetTracker", disabled = ptOff, disabledTooltip = "Pet Tracker" })
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Pet Tracker",
              tooltip = "A warning while a hunter or warlock has no pet out. A warlock who sacrificed their demon, and a hunter with Lone Wolf, are left alone.",
              getValue = function() return not ptOff() end,
              setValue = function(v) Set(pt, "enabled", v and true or false) end },
            { type = "toggle", text = "Warn While Passive", disabled = ptOff,
              getValue = function() return pt.Get("passive") end,
              setValue = function(v) Set(pt, "passive", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Warn on Low Pet Health", disabled = ptOff,
              getValue = function() return pt.Get("lowHealth") end,
              setValue = function(v) Set(pt, "lowHealth", v and true or false) end },
            { type = "slider", text = "Low Health Below", min = 5, max = 90, step = 1, isPercent = false, disabled = ptOff,
              getValue = function() return pt.Get("lowBelow") end,
              setValue = function(v) Set(pt, "lowBelow", math.floor(v + 0.5)) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Only In Combat", disabled = ptOff,
              getValue = function() return pt.Get("combatOnly") end,
              setValue = function(v) Set(pt, "combatOnly", v and true or false) end },
            { type = "toggle", text = "Only In Dungeons & Raids", disabled = ptOff,
              getValue = function() return pt.Get("instanceOnly") end,
              setValue = function(v) Set(pt, "instanceOnly", v and true or false) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Hide While Mounted", disabled = ptOff,
              getValue = function() return pt.Get("hideMounted") end,
              setValue = function(v) Set(pt, "hideMounted", v and true or false) end },
            { type = "toggle", text = "Show Icon", disabled = ptOff,
              getValue = function() return pt.Get("showIcon") end,
              setValue = function(v) Set(pt, "showIcon", v and true or false) end }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  DUNGEON JOURNAL
    ---------------------------------------------------------------------------
    if CludesUI._Journal then
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "DUNGEON JOURNAL", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Dungeon Journal", buttonText = "Open", width = 90,
              tooltip = "Every dungeon and raid: bosses in kill order, their loot and drop chances, a tip per boss, and the quests. Alt+Shift-click an item to add it to your BiS list. /cjournal opens it too.",
              onClick = function() CludesUI._Journal.Show() end },
            { type = "label", text = "Opens on the dungeon you are in." }
        );  y = y - h
    end

    ---------------------------------------------------------------------------
    --  STAT WEIGHTS
    ---------------------------------------------------------------------------
    local SWt = CludesUI._StatWeights
    if SWt then
        local cfg = SWt.Cfg()
        local function Rebuild() C_Timer.After(0.05, function() CludesUI:RefreshPage(true) end) end
        local values, order = { [""] = "Automatic (talents)" }, { "" }
        for _, s in ipairs(SWt.Specs()) do values[s.key] = s.name; order[#order + 1] = s.key end
        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "STAT WEIGHTS", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Upgrades on Tooltips",
              tooltip = "Gear that is an upgrade for your spec says so on its tooltip, as a percent over what you wear. The BiS window shows each pick's gain too. An estimate from these weights.",
              getValue = function() return SWt.Get("enabled") end,
              setValue = function(v) cfg.enabled = v and true or false; Rebuild() end },
            { type = "dropdown", text = "Spec", values = values, order = order,
              tooltip = "Automatic weighs by the talent tree you spent most points in.",
              getValue = function() return cfg.spec or "" end,
              setValue = function(v) cfg.spec = v; Rebuild() end }
        );  y = y - h
        if SWt.Get("enabled") then
            local key = SWt.ActiveSpec()
            local weights = SWt.For(key) or {}
            local list = {}
            for _, st in ipairs(SWt.Stats) do
                if (weights[st[1]] or 0) ~= 0 then list[#list + 1] = st end
            end
            local function Slider(st)
                if not st then return { type = "label", text = "" } end
                local max = st[3]
                local step = max >= 20 and 0.5 or (max >= 5 and 0.1 or (max >= 1 and 0.05 or 0.005))
                return { type = "slider", text = st[2], min = 0, max = max, step = step, isPercent = false,
                         getValue = function() return (SWt.For(key) or {})[st[1]] or 0 end,
                         setValue = function(v) SWt.Set(key, st[1], v) end }
            end
            for i = 1, #list, 2 do
                _, h = W:DualRow(parent, y, Slider(list[i]), Slider(list[i + 1]));  y = y - h
            end
            _, h = W:DualRow(parent, y,
                { type = "labeledButton", text = "Weights for " .. (SWt.Spec(key) and SWt.Spec(key).name or "?"), buttonText = "Reset", width = 90,
                  tooltip = "Put this spec's weights back to the defaults.",
                  onClick = function() SWt.Reset(key); Rebuild() end },
                { type = "label", text = "Main stat, Spell Damage, Healing or Stamina is 1." }
            );  y = y - h
        end
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

        -- Only Show When Bag Space Is Low (its threshold in the cog) | Use Auction Prices
        local lowRow
        lowRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Only Show When Bag Space Is Low",
              tooltip = "Shows the window only while few bag slots are free. Use the cog to set how few.",
              getValue = function() return JI.Get("onlyLowBagSpace") == true end,
              setValue = function(v)
                  JunkSet("onlyLowBagSpace", v)
                  CludesUI:RefreshPage()  -- the cog's disabled state
              end },
            { type = "toggle", text = "Use Auction Prices",
              tooltip = "Prices items from Auctionator scans, or CludesUI's Auction Prices when Auctionator is not loaded.",
              disabled = function()
                  return not CludesUI._ModuleNS["CludesUIForeverEssentials"].AuctionSource()
              end,
              disabledTooltip = "This option requires Auctionator, or Auction Prices in this page's AUCTION PRICES section.",
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
