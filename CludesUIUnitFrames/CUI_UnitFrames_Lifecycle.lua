if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Lifecycle.lua
--
--  The addon object (OnInitialize creates the DB and runs I.dbSetters,
--  OnEnable builds through EnableBody) and the load-time blocks after it:
--  Boss Frame Range Dimming, Player Dispel Overlay helpers, Party Mode.
--  Loads before PlayerAuraBars/ForeverImbues/AuraContainers (event order).
-------------------------------------------------------------------------------
local _, mod = ...

local GetSpecialization = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    or GetSpecialization
local issecretvalue = issecretvalue

local Inner = mod._internals
local frameList, defaultSet, ResolveFontPath = Inner.frames, Inner.defaults, Inner.ResolveFontPath
local healthBarTextureNames, healthBarTextureOrder, healthBarTextures =
    Inner.healthBarTextureNames, Inner.healthBarTextureOrder, Inner.healthBarTextures
local RegisterUFUnlockElements = Inner.RegisterUFUnlockElements
local InitializeFrames, SetupOptionsPanel = Inner.InitializeFrames, Inner.SetupOptionsPanel
local saved -- assigned by CludesUF:OnInitialize below, no setter

local CludesUF = CludesUI.Lite.NewAddon("CludesUIUnitFrames")

function CludesUF:OnInitialize()
    saved = CludesUI.Lite.NewDB("CludesUIUnitFramesDB", defaultSet, true)
    Inner.SetDB(saved)

    -- A fresh install starts Target of Target on the Target frame's look; a
    -- profile from an earlier version keeps Automatic (no lookSource). Written
    -- here, not a default: the logout strip drops a value equal to its default.
    if CludesUI._firstInstallPending then
        local tot = saved.profile.targettarget
        if tot and tot.lookSource == nil then
            tot.lookSource = "target"
        end
    end

    ResolveFontPath()

    -- Append SharedMedia textures to runtime tables so SM texture keys resolve
    CludesUI.AppendSharedMediaTextures(healthBarTextureNames, healthBarTextureOrder, nil, healthBarTextures)

    -- Blizzard options panel is registered centrally in CludesUI.lua
end

-- Enable-body router. OnEnable runs under the parent addon's lifecycle dispatch, and
-- the engine bills a script handler's whole call tree to the addon whose execution
-- context created the entry frame -- so every frame born inside the build (oUF
-- buttons, event drivers, castbar watchers) would bill the PARENT's CPU row forever.
-- Routing the body through this file-scope frame's PLAYER_LOGIN handler runs the
-- build in this child's context instead. Ordering is safe: the parent's lifecycle
-- frame registered PLAYER_LOGIN first (parent loads before children), so OnEnable has
-- always set the pending flag by the time this frame's handler fires -- within the
-- SAME event dispatch, still inside the combat-reload pre-lockdown window.
local function EnableBody()
    -- A profile already on a stock style gets its seeds before the frames
    -- build (the Style page seeds on the switch); a profile none of them has
    -- reached yet keeps its own values in the CludesUI slot first, so a
    -- switch back restores them.
    if mod.UF_Blizz() then
        local profile = saved.profile
        if
            profile.stockCastTextureSeeded == nil
            and profile.classicTextureSeeded == nil
            and profile.stockCombatSeededStyle == nil
            and CludesUI.BankEuiStyleSlot
        then
            CludesUI.BankEuiStyleSlot(profile, mod.UF_StyleSlotKeys())
        end
        -- WoW Forever's own seed the same way: the other looks' class
        -- resource goes to its Forever-only slot first.
        if mod.UF_Forever() and not profile.foreverClassPowerSeeded and profile.player then
            local cfg = profile._foreverStyleSlots
            if type(cfg) ~= "table" then
                cfg = {}
                profile._foreverStyleSlots = cfg
            end
            cfg.cui = {
                ["player.classPowerStyle"] = profile.player.classPowerStyle,
                ["player.showClassPowerBar"] = profile.player.showClassPowerBar,
            }
        end
        mod.UF_SeedStock(profile, mod.UF_Style(), mod.UF_Forever())
    end
    InitializeFrames()
    -- Register with unlock mode synchronously: on a combat reload this runs
    -- inside the pre-lockdown window, so the login position pass can resolve
    -- and place anchored unit frames before SetPoint gets blocked.
    RegisterUFUnlockElements()
    -- The parent's synchronous PLAYER_LOGIN position pass (CUI_UnlockMode) fires BEFORE
    -- this router drains, so unit frame elements were not yet registered when it ran.
    -- Re-fire it now -- still inside the same PLAYER_LOGIN dispatch, so anchored unit
    -- frames are placed within the combat-reload pre-lockdown window. The pass is
    -- re-entrant by design (CDM and the PEW fallback both re-fire it).
    -- The options page registers from SetupOptionsPanel: queue it first, so no
    -- error in the shared position pass can leave Unit Frames without one.
    C_Timer.After(0, SetupOptionsPanel)
    if CludesUI and CludesUI._applySavedPositions then
        CludesUI._applySavedPositions()
    end
    C_Timer.After(0, function()
        -- Restore the threat watchers saved enabled (nothing registers when off).
        mod.SyncPlayerThreat()
        if mod.SyncThreatPct then
            mod.SyncThreatPct()
        end
    end)
    -- After InitializeFrames, which decided the target frame's source.
    mod.UF_SyncTargetSounds()
end

do
    local loginFired = false
    local router = CreateFrame("Frame")
    router:RegisterEvent("PLAYER_LOGIN")
    -- Backstop only: PLAYER_LOGIN always fires for a startup-loaded addon,
    -- but if it were ever missed the next world entry drains the flag.
    router:RegisterEvent("PLAYER_ENTERING_WORLD")
    router:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        loginFired = true
        if mod._eufEnablePending then
            mod._eufEnablePending = nil
            EnableBody()
        end
    end)

    function CludesUF:OnEnable()
        if loginFired then
            -- Runtime re-enable long after login: run directly (rare; any
            -- parent-context billing lasts only until the next reload).
            EnableBody()
        else
            mod._eufEnablePending = true
        end
        -- Incompatible addon detection is handled globally by CludesUI
    end
end

-------------------------------------------------------------------------------
--  Targeting Sound Effects (db.profile.targetSounds: on by default on WoW
--  Forever, off on retail). Blizzard
--  plays the target and lost-target sounds from its own TargetFrame (its
--  PLAYER_TARGET_CHANGED handler and its OnHide), which this module parks with
--  its events off whenever our target frame, or none, replaces it. This plays
--  them the same way; with Blizzard's frame in use (Frame Source Blizzard
--  Default) it plays them itself. The event is registered only while on.
--  (do-block: no persistent file-level locals.)
-------------------------------------------------------------------------------
do
    local eventFrame = CreateFrame("Frame")
    local hadTarget = false
    eventFrame:SetScript("OnEvent", function()
        if UnitExists("target") then
            hadTarget = true
            if C_PlayerInteractionManager.IsReplacingUnit() then
                return
            end
            if UnitIsEnemy("target", "player") then
                PlaySound(SOUNDKIT.IG_CREATURE_AGGRO_SELECT)
            elseif UnitIsFriend("player", "target") then
                PlaySound(SOUNDKIT.IG_CHARACTER_NPC_SELECT)
            else
                PlaySound(SOUNDKIT.IG_CREATURE_NEUTRAL_SELECT)
            end
        elseif hadTarget then
            hadTarget = false
            -- A soft target going away plays nothing, as on Blizzard's frame.
            if not IsTargetLoose() then
                PlaySound(SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT, nil, true)
            end
        end
    end)

    -- Login, the options toggle and every reload pass (a profile switch or
    -- override changes the saved toggle without its setter).
    function mod.UF_SyncTargetSounds()
        local enabled = saved
            and saved.profile.targetSounds == true
            and mod.GetUnitFrameSource("target") ~= "blizzard"
        if enabled then
            hadTarget = UnitExists("target") and true or false
            eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        else
            eventFrame:UnregisterEvent("PLAYER_TARGET_CHANGED")
        end
    end
end

-- Called by CUI_UnlockMode.lua's Grow Direction dropdown for barKey ==
-- "PAB_Buffs" / "PAB_Debuffs". Thin delegation to
-- CUI_PlayerAuraBars_Bars.lua's ns.PAB_Get/SetGrowDirection so
-- the settings field names stay defined in exactly one file.

function CludesUF:GetGrowDirectionForBar(barId)
    return mod.PAB_GetGrowDirection and mod.PAB_GetGrowDirection(barId)
end

function CludesUF:SetGrowDirectionForBar(barId, direction)
    if mod.PAB_SetGrowDirection then
        mod.PAB_SetGrowDirection(barId, direction)
    end
end

-------------------------------------------------------------------------------
--  Boss Frame Range Dimming. Boss units sit outside UnitInRange's group-member
--  domain, so range is measured against a known spell instead: a harm spell for
--  attackable bosses (all specs, first known spell in the class chain wins), or
--  the class baseline heal for friendly bosses (healer specs only). Whole-frame
--  alpha follows db.profile.boss.oorAlpha; 100% means no fade and the check
--  short-circuits. The ticker exists only while a boss frame is shown.
--  (do-block: no persistent file-level locals.)
-------------------------------------------------------------------------------
do
    local HARM_CHAIN = {
        DEATHKNIGHT = { 49576, 47541 }, -- Death Grip, Death Coil
        DEMONHUNTER = { 185123, 183752, 204021 }, -- Throw Glaive, Consume Magic, Fiery Brand
        DRUID = { 8921, 5176, 6795 }, -- Moonfire, Wrath, Growl
        EVOKER = { 362969 }, -- Azure Strike (25yd native)
        HUNTER = { 75, 466930, 190925 }, -- Auto Shot, Black Arrow, Harpoon
        MAGE = { 116, 133, 44425, 118 }, -- Frostbolt, Fireball, Arcane Barrage, Polymorph
        MONK = { 117952, 115546 }, -- Crackling Jade Lightning, Provoke
        PALADIN = { 20271, 62124 }, -- Judgment, Hand of Reckoning
        PRIEST = { 589, 585, 8092 }, -- Shadow Word: Pain, Smite, Mind Blast
        ROGUE = { 36554, 185763, 2094 }, -- Shadowstep, Pistol Shot, Blind
        SHAMAN = { 188196, 370 }, -- Lightning Bolt, Purge
        WARLOCK = { 234153, 232670, 686, 348, 172, 5782 }, -- Drain Life, Shadow Bolt (both ids), Immolate, Corruption, Fear
        WARRIOR = { 355, 100 }, -- Taunt, Charge
    }
    local HELP_HEAL = {
        PRIEST = 2061,
        PALADIN = 19750,
        SHAMAN = 8004,
        DRUID = 8936,
        MONK = 116670,
        EVOKER = 361469,
    }

    local harmSpell, helpSpell
    local visCount, ticker = 0, nil

    local function Known(spellRef)
        if C_SpellBook and C_SpellBook.IsSpellInSpellBook and Enum.SpellBookSpellBank then
            return C_SpellBook.IsSpellInSpellBook(spellRef, Enum.SpellBookSpellBank.Player, true)
        end
        return IsSpellKnown and IsSpellKnown(spellRef)
    end

    local function ResolveRangeSpells()
        harmSpell, helpSpell = nil, nil
        local _, pClass = UnitClass("player")
        for _, spellRef in ipairs(HARM_CHAIN[pClass] or {}) do
            if Known(spellRef) then
                harmSpell = spellRef
                break
            end
        end
        local specInfo = GetSpecialization and GetSpecialization()
        local role = specInfo and GetSpecializationRole and GetSpecializationRole(specInfo)
        if role == "HEALER" then
            helpSpell = HELP_HEAL[pClass]
        end
        -- WoW Forever has no spec roles: a healing class counts as its healing
        -- spec and range-checks with its best heal in the spellbook.
        if CludesUI.IS_FOREVER then
            local entries = CludesUI.FOREVER_HEAL_SPELLS[pClass]
            for index = 1, (entries and #entries or 0) do
                if Known(entries[index]) then
                    helpSpell = entries[index]
                    break
                end
            end
        end
    end

    local function TickOne(frame, unitToken)
        if not saved then
            return
        end
        local oor = (saved.profile.boss and saved.profile.boss.oorAlpha) or 0.4
        if oor >= 1 or not UnitExists(unitToken) then
            frame:SetAlpha(1)
            return
        end
        local spell
        if UnitCanAttack("player", unitToken) then
            spell = harmSpell
        else
            spell = helpSpell
        end
        if spell then
            -- Secret-safe: the result may be secret in instances, which
            -- SetAlphaFromBoolean accepts natively -- but it can also be NIL
            -- (unit not range-checkable right now / spell momentarily not
            -- evaluable), which it rejects. issecretvalue runs first so the
            -- nil check never touches a secret.
            local inRange = C_Spell.IsSpellInRange(spell, unitToken)
            if issecretvalue(inRange) or inRange ~= nil then
                frame:SetAlphaFromBoolean(inRange, 1, oor)
            else
                frame:SetAlpha(1)
            end
        else
            frame:SetAlpha(1)
        end
    end

    local function Tick()
        for index = 1, 5 do
            local frame = frameList["boss" .. index]
            if frame and frame:IsVisible() then
                TickOne(frame, "boss" .. index)
            end
        end
    end

    local function UpdateTicker()
        local wanted = visCount > 0
        if wanted and not ticker then
            ticker = C_Timer.NewTicker(0.4, Tick)
        elseif not wanted and ticker then
            ticker:Cancel()
            ticker = nil
        end
    end

    local hooked = false
    local function InstallHooks()
        if hooked or not frameList["boss1"] then
            return
        end
        hooked = true
        for index = 1, 5 do
            local frame = frameList["boss" .. index]
            if frame then
                local unitToken = "boss" .. index
                if frame:IsVisible() then
                    visCount = visCount + 1
                end
                frame:HookScript("OnShow", function(self)
                    visCount = visCount + 1
                    TickOne(self, unitToken)
                    UpdateTicker()
                end)
                frame:HookScript("OnHide", function(self)
                    visCount = math.max(0, visCount - 1)
                    self:SetAlpha(1)
                    UpdateTicker()
                end)
            end
        end
        UpdateTicker()
    end

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:SetScript("OnEvent", function()
        ResolveRangeSpells()
        InstallHooks()
    end)
end

-------------------------------------------------------------------------------
--  Player Dispel Overlay (player frame only, health bar only). The 12.1
--  container dispel slots render it (CUI_UnitFrames_AuraContainers.lua); this
--  block keeps what the slots ask the module for: the racial / talent dispel
--  knowledge the RAID_PLAYER_DISPELLABLE token is blind to, and the
--  options-side poke that re-drives the slots after a color or toggle edit.
--  (do-block: no persistent file-level locals.)
-------------------------------------------------------------------------------
do
    -- RAID_PLAYER_DISPELLABLE only knows class and spec dispels, so it answers no for
    -- every bleed: nothing a class learns removes one, only the dwarf racial does.
    -- Without this, "Only Dispellable by You" can never light up for a bleed, for
    -- anyone. A racial cleans its own caster, so this is the player frame's business
    -- alone. Bleed only, deliberately: Stoneform also clears poison/disease/curse, but
    -- a class that dispels those already passes the token, and treating a two-minute
    -- racial as a dispel would overlay most of what a dwarf ever catches.
    local RACIAL_DISPEL_TYPES = {
        bleed = { Dwarf = true }, -- Stoneform
    }
    -- The token is equally blind to talent dispels: a shaman's poison removal is
    -- Poison Cleansing Totem, so Poison never passes for them. Raid Frames applies
    -- the same rule to its group-wide dispel slots (CUI_RaidFrames_AuraContainers.lua).
    -- Cached: IsPlayerSpell can lag both addon load and the trait event that
    -- announces a change; the shaman watcher in CUI_UnitFrames_AuraContainers.lua
    -- calls UF_RefreshPoisonTotem on trait and spellbook events and reloads the
    -- dispel slots when it reports a flip.
    local POISON_CLEANSING_TOTEM = 383013
    local _, ufPlayerClass = UnitClass("player")
    local poisonTotemKnown = ufPlayerClass == "SHAMAN" and IsPlayerSpell(POISON_CLEANSING_TOTEM) or false
    function mod.UF_RefreshPoisonTotem()
        local known = ufPlayerClass == "SHAMAN" and IsPlayerSpell(POISON_CLEANSING_TOTEM) or false
        if known == poisonTotemKnown then
            return false
        end
        poisonTotemKnown = known
        return true
    end
    -- Shared with the 12.1 container slots (CUI_UnitFrames_AuraContainers.lua),
    -- which apply the same rule by choosing which slot style stays visible.
    function mod.UF_TokenBlindDispel(typeKey)
        local races = RACIAL_DISPEL_TYPES[typeKey]
        if races then
            local _, raceToken = UnitRace("player")
            return raceToken ~= nil and races[raceToken] == true
        end
        if typeKey == "poison" then
            return poisonTotemKnown
        end
        return false
    end

    mod.UpdatePlayerDispelOverlay = function()
        -- The container dispel slots own the overlay; poke their fingerprinted
        -- reload so dropdown/cog edits apply live instead of waiting for the
        -- next full container pass.
        if mod.UF_ReloadPlayerDispelSlots then
            mod.UF_ReloadPlayerDispelSlots()
        end
    end
end

-------------------------------------------------------------------------------
--  Party Mode: spinning unit frames. Every CUI unit frame (player, target,
--  focus, pet, target-of-target, focus target, boss) orbits the centre of the
--  screen, so player and target swing round each other like a carousel.
--  Unit frames are secure, so this pauses in combat exactly like the action
--  bar spin. Driver and rest tracking live in the shared engine
--  (CludesUI.PartySpin_Create, CludesUI_PartyMode.lua).
-------------------------------------------------------------------------------
do
    local entries = {}
    local groups = { { pivot = UIParent, frames = entries } }
    CludesUI.PartySpin_Create({
        target = "unitFrames",
        collect = function()
            wipe(entries)
            for _, frame in pairs(frameList) do
                if type(frame) == "table" and frame.GetCenter then
                    entries[#entries + 1] = frame
                end
            end
            return groups
        end,
    })
end

-- Party Mode visibility axis (Visibility > Party Mode): no game event, so the
-- core fires its own edge (re-fired after combat for the secure frames).
if CludesUI.RegisterVisEdge then
    CludesUI.RegisterVisEdge(function()
        if mod.UpdateFrameVisibility then
            mod.UpdateFrameVisibility()
        end
    end)
end
