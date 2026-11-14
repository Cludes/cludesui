if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Options.lua
--  Registers the Forever Essentials sidebar addon (WoW Forever only) with its
--  tabs:
--    * General -- quality of life features (built by CUI_ForeverEssentials_General_Options.lua)
--    * Travel -- flight timer (built by CUI_ForeverEssentials_Travel_Options.lua)
--    * Threat -- threat meter (built by CUI_ForeverEssentials_Threat_Options.lua)
--    * Loot   -- loot feed (built by CUI_ForeverEssentials_Loot_Options.lua)
--    * Macros -- macro manager (built by CUI_ForeverEssentials_Macros_Options.lua)
-------------------------------------------------------------------------------
-- Page names are DEEP-LINK IDENTIFIERS: every NavigateToElementSettings tuple
-- and What's New nav carries them as strings and fails SILENTLY on a mismatch.
if not CludesUI._ModuleNS["CludesUIForeverEssentials"] then
    return
end -- module disabled: no options page

local PAGE_GENERAL = "General"
local PAGE_TRAVEL = "Travel"
local PAGE_THREAT = "Threat"
local PAGE_LOOT = "Loot"
local PAGE_MACROS = "Macros"
local PAGE_TRAINING = "Training"
local PAGE_PVP = "PvP"

-- Item quality dropdown values and order from Poor up to last, each in its
-- colour (the General and Loot pages).
_G._CUI_ItemQualityValues = function(last)
    local values, order = {}, {}
    for q = Enum.ItemQuality.Poor, last do
        local key, color = tostring(q), ITEM_QUALITY_COLORS[q]
        local label = _G["ITEM_QUALITY" .. q .. "_DESC"] or key
        values[key] = color and (color.hex .. label .. "|r") or label
        order[#order + 1] = key
    end
    return values, order
end

-- Page reuse: a frame this file builds goes through the options frame pool
-- (CludesUI_FramePool.lua, the options addon's first file), which hands a
-- kept page its previous build's frames back reset to new; on any other
-- parent it is the plain CreateFrame. The buildPage below only hands each
-- tab to its own page file.
local CreateFrame = CludesUI._Pool.CreateFrame

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    CludesUI:RegisterModule("CludesUIForeverEssentials", {
        title = "Forever Tools",
        description = "Essential tools for WoW Forever.",
        pages = { PAGE_GENERAL, PAGE_TRAVEL, PAGE_THREAT, PAGE_LOOT, PAGE_MACROS, PAGE_TRAINING, PAGE_PVP },
        searchTerms = {
            "flight timer",
            "flight path",
            "threat",
            "threat meter",
            "aggro",
            "loot",
            "loot feed",
            "training",
            "trainer",
            "pvp",
            "spy",
            "kill on sight",
            "enemy players",
            "spells to train",
            "reputation",
            "currency",
            "uprank",
            "spell rank",
            "junk",
            "junk items",
            "macro",
            "macros",
            "macro manager",
            "simplified stats",
            "item stats",
            "stat colors",
            "tooltip stats",
            "world map",
            "map",
            "reveal",
            "unexplored",
            "fog of war",
            "fishing skill",
            "quest reward",
            "quest rewards",
            "sell value",
            "boat",
            "zeppelin",
            "zone exit",
            "dungeon entrance",
            "instance",
        },
        buildPage = function(pageName, parent, yOffset)
            if pageName == PAGE_GENERAL and _G._CUI_BuildForeverGeneralPage then
                return _G._CUI_BuildForeverGeneralPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_TRAVEL and _G._CUI_BuildFlightTimerPage then
                return _G._CUI_BuildFlightTimerPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_THREAT and _G._CUI_BuildThreatMeterPage then
                return _G._CUI_BuildThreatMeterPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_LOOT and _G._CUI_BuildLootFeedPage then
                return _G._CUI_BuildLootFeedPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_MACROS and _G._CUI_BuildForeverMacrosPage then
                return _G._CUI_BuildForeverMacrosPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_TRAINING and _G._CUI_BuildForeverTrainingPage then
                return _G._CUI_BuildForeverTrainingPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_PVP and _G._CUI_BuildForeverPvPPage then
                return _G._CUI_BuildForeverPvPPage(pageName, parent, yOffset)
            end
        end,
        -- The Travel, Threat, Loot and Macros headers live in the content header; declaring a
        -- page's builder makes a cached page whose header was dropped rebuild with it.
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_TRAVEL then
                return _G._CUI_TravelHeaderBuilder
            end
            if pageName == PAGE_THREAT then
                return _G._CUI_ThreatHeaderBuilder
            end
            if pageName == PAGE_LOOT then
                return _G._CUI_LootHeaderBuilder
            end
            if pageName == PAGE_MACROS and CludesUI._MacroManager.Enabled() then
                return _G._CUI_MacrosHeaderBuilder
            end
        end,
        resetScope = "account",
        onReset = function()
            if CludesUIDB then
                CludesUIDB.flightTimer = nil
                CludesUIDB.threatMeter = nil
                CludesUIDB.lootFeed = nil
                -- spellUprankChars, the ranks each character has had, is not a setting: it stays, so the
                -- option turned on again swaps only ranks learned since
                CludesUIDB.spellUprank = nil
                CludesUIDB.junkList = nil
                CludesUIDB.junkListExcluded = nil
                CludesUIDB.simplifiedStats = nil
                CludesUIDB.activeForm = nil
                CludesUIDB.classicSpellbook = nil
                CludesUIDB.classicTalents = nil
                CludesUIDB.macroManager = nil
                CludesUIDB.questRewards = nil
                CludesUIDB.zoneLevels = nil
                -- The per-character favorites are the player's picks: only the switch resets.
                if CludesUIDB.petSummon then
                    CludesUIDB.petSummon.enabled = nil
                end
                -- The CVars a session holds stay recorded, so Apply can give them back.
                local fi = CludesUIDB.fishing
                CludesUIDB.fishing = fi and fi.held and { held = fi.held } or nil
                CludesUIDB.mapTravel = nil
                -- The game's mapFade from before stays, so Apply can give it back.
                local mf = CludesUIDB.worldMapFade
                CludesUIDB.worldMapFade = mf and mf.mapFadeWas ~= nil and { mapFadeWas = mf.mapFadeWas }
                    or nil
                CludesUIDB.gatherSkill = nil
                if CludesUIDB.unlockAnchors then
                    CludesUIDB.unlockAnchors.CUI_FlightTimer = nil
                    CludesUIDB.unlockAnchors.CUI_ThreatMeter = nil
                    CludesUIDB.unlockAnchors.CUI_LootFeed = nil
                    CludesUIDB.unlockAnchors.CUI_JunkList = nil
                    CludesUIDB.unlockAnchors.CUI_ActiveForm = nil
                end
            end
            local FT = CludesUI._FlightTimer
            if FT then
                FT.Apply()
                FT.ApplyStyle()
                FT.ApplyPosition()
            end
            local TM = CludesUI._ThreatMeter
            if TM then
                TM.Apply()
                TM.ApplyStyle()
                TM.ApplyPosition()
            end
            local LF = CludesUI._LootFeed
            if LF then
                LF.Apply()
                LF.ApplyStyle()
                LF.ApplyPosition()
            end
            if CludesUI._SpellUprank then
                CludesUI._SpellUprank.Apply()
            end
            if CludesUI._JunkItems then
                CludesUI._JunkItems.Apply()
            end
            if CludesUI._ActiveForm then
                CludesUI._ActiveForm.Apply()
            end
            if CludesUI._ClassicSpellbook then
                CludesUI._ClassicSpellbook.Apply()
            end
            if CludesUI._ClassicTalents then
                CludesUI._ClassicTalents.Apply()
            end
            if CludesUI._QuestRewards then
                CludesUI._QuestRewards.Apply()
            end
            if CludesUI._ZoneLevels then
                CludesUI._ZoneLevels.Apply()
            end
            if CludesUI._PetSummon then
                CludesUI._PetSummon.Apply()
            end
            if CludesUI._Fishing then
                CludesUI._Fishing.Apply()
            end
            if CludesUI._MapTravel then
                CludesUI._MapTravel.Apply()
            end
            if CludesUI._MapFade then
                CludesUI._MapFade.Apply()
            end
            if CludesUI._GatherSkill then
                CludesUI._GatherSkill.Apply()
            end
            CludesUI:InvalidatePageCache()
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then
    initFrame:GetScript("OnEvent")(initFrame)
end
