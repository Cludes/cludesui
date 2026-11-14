if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Quickdraw_Actions.lua
--
--  Dynamic rez, the usability filter, ResolveAction, FireInsecure and what
--  a slot shows: icon, spell id, cooldown, count, usability.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._qdInternals
-- CludesUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local tonumber, type, select = tonumber, type, select
local GetCursorInfo = GetCursorInfo
local InCombatLockdown = InCombatLockdown

local ChildIndex, Prm, QUESTION_MARK = Inner.ChildIndex, Inner.P, Inner.QUESTION_MARK
local ReadPalette, CycleNext, CycleSteps = Inner.ReadPalette, Inner.CycleNext, Inner.CycleSteps
local MARKER_NAMES, MarkerIcon = Inner.MARKER_NAMES, Inner.MarkerIcon
local RANDOM_FAVORITE_MOUNT, SpecIndexFor = Inner.RANDOM_FAVORITE_MOUNT, Inner.SpecIndexFor
local WORLD_MARKER_ENGINE, SetUsableSlots = Inner.WORLD_MARKER_ENGINE, Inner.SetUsableSlots

-- Assigned below with the usability filter; CludesUIQuickdraw.lua holds
-- the forward declaration ChildSlots reads through.
local UsableSlots

-- Forever gives each spell rank its own id; resolve to the highest known one, as /cast does.
-- Kept per stored id until the next push (PushAllPalettes wipes it, and SPELLS_CHANGED
-- requests one); a lookup made before the spell's data loaded is not kept.
local TopRank
do
    local memo = {}
    function mod.WipeRankCache()
        wipe(memo)
    end
    TopRank = function(ident)
        if not CludesUI.IS_FOREVER or type(ident) ~= "number" then
            return ident
        end
        local hit = memo[ident]
        if hit then
            return hit
        end
        local details = C_Spell.GetSpellInfo(ident)
        local topY = details and C_Spell.GetSpellInfo(details.name)
        if not topY then
            return ident
        end
        local result = ident
        if topY.spellID ~= ident and C_SpellBook.IsSpellKnown(topY.spellID) then
            result = topY.spellID
        end
        memo[ident] = result
        return result
    end
end

-- The spell a spell entry casts: exactly its stored rank when picked from a
-- lower one (slot.rankPinned, Forever only), the highest known rank otherwise.
local function SlotRank(slotIndex)
    if slotIndex.rankPinned and CludesUI.IS_FOREVER and type(slotIndex.id) == "number" then
        return slotIndex.id
    end
    return TopRank(slotIndex.id)
end

-------------------------------------------------------------------------------
--  Dynamic Rez
--
--  One entry that is whichever resurrection spell this character has, so a
--  palette shared between a druid, a priest and a death knight carries the rez
--  once rather than three times over with two of them dead on every character.
--
--  single and group are the out-of-combat casts; battle is the in-combat one.
--  The same kit the raid frames' Dynamic Rez click-cast binding uses
--  (CUI_RaidFrames_ClickCast.lua:90), kept as a copy of the table rather than
--  read across from it: that is a separate addon the user can switch off, and
--  an entry on a palette must not stop working when they do. The two lists have
--  to be changed together when a class gains or loses a rez.
--
--  One table rather than a local per entry point, and everything else scoped to
--  the do-block below. That is not tidiness: as one file the module's main
--  chunk sat within a handful of Lua's ceiling of 200 locals, and neither a
--  field nor a block-local costs one of them.
-------------------------------------------------------------------------------
local Rez = {}
do
    local UnitExists, UnitIsFriend, UnitIsDeadOrGhost = UnitExists, UnitIsFriend, UnitIsDeadOrGhost

    local REZ_BY_CLASS = {
        PRIEST = { single = 2006, group = 212036 },
        PALADIN = { single = 7328, group = 212056, battle = 391054 },
        SHAMAN = { single = 2008, group = 212048 },
        DRUID = { single = 50769, group = 212040, battle = 20484 },
        MONK = { single = 115178, group = 212051 },
        EVOKER = { single = 361227, group = 361178 },
        DEATHKNIGHT = { battle = 61999 },
        WARLOCK = { battle = 20707 },
    }
    -- WoW Forever: the vanilla spells, every rank ID listed (rank 1 first).
    if CludesUI.IS_FOREVER then
        REZ_BY_CLASS = {
            PRIEST = { single = { 2006, 2010, 10880, 10881, 20770 } },
            PALADIN = { single = { 7328, 10322, 10324, 20772, 20773 } },
            SHAMAN = { single = { 2008, 20609, 20610, 20776, 20777 } },
            DRUID = {
                single = { 437138, 1237948, 1237949, 1237950, 1237951 },
                battle = { 20484, 20739, 20742, 20747, 20748 },
            },
        }
    end

    -- battle, single, group for this character, any of them nil. Filtered by what
    -- is actually in the spellbook, because the macro below picks a branch by
    -- CONDITION rather than by knowledge: a /cast line naming a spell the character
    -- has not got is a branch that matches and then casts nothing, which would eat
    -- the fallback the next branch was there to be.
    --
    -- Not cached, and deliberately so. What is known moves with talents --
    -- Intercession is a holy paladin's -- and it is also simply WRONG for a moment
    -- at login, while the spellbook is still cold. A cache would latch that empty
    -- answer and hold it until something invalidated it, which is a worse failure
    -- than the reads it saves: three spellbook lookups, on a path that runs once
    -- per palette open rather than per frame. See AdvanceLiveIcons for the one that
    -- does run per frame.
    --
    -- The macro this feeds is written at push time, and SPELLS_CHANGED already
    -- requests a push for the usability filter -- so a talent swap, a spec change,
    -- levelling into a rez and the spellbook warming up after login all rebuild it
    -- with no registration of its own.
    local function RezKit()
        local _, classFile = UnitClass("player")
        local kit = classFile and REZ_BY_CLASS[classFile]
        if not kit then
            return nil
        end
        local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        local function Known(ident)
            if not ident then
                return nil
            end
            -- A rank list (Forever) answers with the first rank in the book.
            if type(ident) == "table" then
                for idx = 1, #ident do
                    local hit = Known(ident[idx])
                    if hit then
                        return hit
                    end
                end
                return nil
            end
            if
                C_SpellBook.IsSpellInSpellBook
                and bank
                and not C_SpellBook.IsSpellInSpellBook(ident, bank, true)
            then
                return nil
            end
            return ident
        end
        return Known(kit.battle), Known(kit.single), Known(kit.group)
    end

    -- A corpse worth casting the single-target rez at. UnitIsDeadOrGhost rather
    -- than UnitIsDead, to agree with the macro's [dead]: that conditional is true
    -- for a player who has released as well, and a released player is exactly who
    -- needs resurrecting.
    --
    -- Identity APIs can answer SECRET booleans in restricted content, and this
    -- runs EVERY FRAME from IconState while a menu holding a live-icon entry is
    -- open -- truthiness on a secret throws, and a throw here storms the whole
    -- OnUpdate. Every read is issecretvalue-guarded FIRST and a secret fails to
    -- false: an unknowable corpse keeps the current branch, and the next
    -- readable frame corrects the picture.
    function Rez.HasDeadTarget()
        local exists = UnitExists("target")
        if issecretvalue(exists) or not exists then
            return false
        end
        local friend = UnitIsFriend("player", "target")
        if issecretvalue(friend) or not friend then
            return false
        end
        local dead = UnitIsDeadOrGhost("target")
        if issecretvalue(dead) or not dead then
            return false
        end
        return true
    end

    -- Which spell the entry would cast RIGHT NOW, for the icon and the live state
    -- beneath it. Display only -- the macro decides again at fire time and the game
    -- evaluates its conditionals then -- so this exists to keep the picture honest,
    -- and its branch order has to match Rez.MacroText's exactly or the palette shows
    -- one spell and casts another.
    function Rez.SpellNow()
        local battle, single, group = RezKit()
        -- A class whose only rez is the battle one casts it in every state, which
        -- is what the bare macro line below does for the same case.
        if not (single or group) then
            return battle
        end
        if battle and InCombatLockdown() then
            return battle
        end
        if single and Rez.HasDeadTarget() then
            return single
        end
        return group or single
    end

    -- The macro a Dynamic Rez entry fires, or nil for a character with no rez at
    -- all. One /cast with a fallback chain rather than a line each: the chain
    -- attempts exactly ONE cast -- the first branch whose condition holds -- where
    -- separate lines would each try in turn and the second would land on "another
    -- action is in progress".
    function Rez.MacroText()
        local battle, single, group = RezKit()
        local Name = C_Spell.GetSpellName
        if not Name then
            return nil
        end

        local parts = {}
        local function Add(cond, ident)
            -- By NAME: /cast resolves against the localized one, and a hardcoded
            -- English name would fail silently on every other client.
            local name = ident and Name(ident)
            if name then
                parts[#parts + 1] = cond .. name
            end
        end

        -- [combat] only when there is something after it to be the out-of-combat
        -- answer. A death knight or a warlock, whose only rez IS the battle one,
        -- would otherwise cast nothing out of combat -- where that spell works
        -- perfectly well.
        Add((single or group) and "[combat] " or "", battle)
        -- Not a safety check: a corpse is a rez's only valid target, so there is no
        -- exists/nodead here the way there is on an ordinary cast. This condition is
        -- how the single-target spell is chosen over the group one.
        Add("[@target,help,dead] ", single)
        -- Bare, and last: the group rez takes no target, so it is the honest answer
        -- to "none of the above".
        --
        -- Falling back to the single one when there is no group rez -- a character
        -- still levelling into it -- is what keeps this line in step with
        -- Rez.SpellNow, which ends on the same `group or single`. Without the
        -- fallback the macro has no unconditional branch at all, and the entry
        -- draws the single rez, tints it usable and casts nothing. Attempting it
        -- and being told there is no target is the same answer the spell gives from
        -- an action bar, and it matches the picture.
        Add("", group or single)

        if #parts == 0 then
            return nil
        end
        return "/cast " .. table.concat(parts, "; ")
    end

    -- Does this character's class have a resurrection spell at all? The picker asks
    -- so it can leave the entry out for a class that has none -- an entry that
    -- could never do anything is worse than no entry. By CLASS rather than by what
    -- is currently in the spellbook: a paladin who has not taken Intercession still
    -- has Redemption, and a druid at level 10 will have Rebirth soon enough.
    function mod.HasRezKit()
        local _, classFile = UnitClass("player")
        return (classFile and REZ_BY_CLASS[classFile]) ~= nil
    end
end

-------------------------------------------------------------------------------
--  Random Hearthstone
--
--  One entry that is a different owned hearthstone toy each time a menu
--  holding it opens. The pick is shared by every Random Hearthstone cell on
--  every palette, so whatever a cell draws is what its pushed attributes fire.
--  Rolled again by the press of such a menu's key (RerollHearth in
--  CUI_Quickdraw_Runtime.lua), which also rewrites every such cell's
--  attributes -- out of combat only, since combat refuses the writes, so a
--  menu opened mid-fight keeps the last roll.
--
--  The roll is the portal flyout's own (CludesUI.ResolveHearthSlot), so
--  the two agree on what counts: a random owned toy, or the plain Hearthstone
--  item for a character with none. Without the flyout's Astral Recall swap:
--  the entry is a hearthstone, and a shaman who wants the spell can put it on
--  the palette beside it. That function rolls again on every call, so its
--  answer is kept here until the next press asks for a new one.
-------------------------------------------------------------------------------
local Hearth = {}
do
    local pickKind, pickID

    -- A new pick, rolled once more when the first repeats the last pick, so two
    -- opens in a row rarely draw the same toy.
    function Hearth.Roll()
        local lastID = pickID
        local kindOf, ident = CludesUI.ResolveHearthSlot(true)
        if ident == lastID then
            kindOf, ident = CludesUI.ResolveHearthSlot(true)
        end
        -- The flyout fires every toy as "item"; the toy action is the one the
        -- rest of this module uses for toys.
        if kindOf == "item" and PlayerHasToy(ident) then
            kindOf = "toy"
        end
        pickKind, pickID = kindOf, ident
    end

    -- kind ("toy" or "item") and itemID of what the entry fires right now.
    function Hearth.Current()
        if not pickID then
            Hearth.Roll()
        end
        return pickKind, pickID
    end
end

-- The filtered answers, one per palette table. Wiped ONLY at the top of
-- PushAllPalettes: the memo is what keeps the drawn menu and the pushed
-- secure attributes reading the SAME list even when the spellbook shifts
-- between the push and the open (a pet swap mid-fight, say) -- usability is
-- allowed to go stale until the next push rather than ever disagreeing with
-- what a cell index fires. Every input that can change an answer lands here
-- through that same wipe: SPELLS_CHANGED and UPDATE_MACROS request a push,
-- every slot edit, the toggle itself and an Assign to Spec pick request one
-- through Refresh, a spec change that moves which palettes load requests one
-- through SpecSync, class and spec-list are fixed for the session, and a
-- profile switch hands out different palette tables (weak keys let the old
-- ones go).
local usableMemo = setmetatable({}, { __mode = "k" })

-- KnownForm, SpellKnownHere and SlotUsable are private to UsableSlots, and
-- are scoped so they cost no main-chunk local: as one file the module's main
-- chunk was at Lua's ceiling of 200 locals, and merging two features into it
-- went over. usableMemo stays outside the block -- PushAllPalettes wipes it.
do
    -- Is this one spell id in either of this character's books, player or pet?
    local function KnownForm(spellRef)
        return (spellRef and spellRef > 0)
                and (C_SpellBook.IsSpellKnown(spellRef) or (C_SpellBook.IsSpellKnownOrInSpellBook and C_SpellBook.IsSpellKnownOrInSpellBook(
                    spellRef
                )))
            or false
    end

    -- Whether this character's books hold the spell in ANY of its forms: the
    -- stored id, its talent override, and its base form. Generous on purpose --
    -- hiding a castable entry is a worse failure than drawing a dead one, so
    -- every form is checked before answering no, and a malformed id answers yes
    -- and leaves the slot to render as the placeholder it always was.
    local function SpellKnownHere(ident)
        if type(ident) ~= "number" or ident <= 0 then
            return true
        end
        if KnownForm(ident) then
            return true
        end
        local ovr = C_SpellBook
            and C_SpellBook.FindSpellOverrideByID
            and C_SpellBook.FindSpellOverrideByID(ident)
        if ovr ~= ident and KnownForm(ovr) then
            return true
        end
        local baseValue = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(ident)
        return baseValue ~= ident and KnownForm(baseValue)
    end

    -- Can this character do anything with the slot? Only the kinds that resolve
    -- against one character's own kit are tested -- another class's
    -- specialization, a profession position this character does not reach, a
    -- spell no book here holds, a macro this character does not have, a
    -- resurrection this class has none of. Everything else (items, toys,
    -- mounts, pets, markers, nested menus) is account-wide or self-resolving
    -- and stays.
    local function SlotUsable(slotIndex)
        local key = slotIndex and slotIndex.kind
        if key == "spec" or key == "dynamicspec" then
            return SpecIndexFor(slotIndex) ~= nil
        elseif key == "dynamicprofession" then
            return mod.ProfessionSpellFor(slotIndex) ~= nil
        elseif key == "spell" then
            return SpellKnownHere(tonumber(slotIndex.id))
        elseif key == "macro" then
            return GetMacroInfo(slotIndex.name or slotIndex.id) ~= nil
        elseif key == "outfit" then
            return mod.OutfitInfo(slotIndex) ~= nil
        elseif key == "equipmentset" then
            return mod.EquipmentSetInfo(slotIndex) ~= nil
        elseif key == "panel" then
            -- The one kind whose availability is the CLIENT's rather than the
            -- character's: Housing arrived in 12.0 and the Shop is not in every
            -- region's build. Hidden by the same setting all the same -- an entry
            -- that can never open anything is one to keep off the ring.
            return mod.PanelAvailable(mod.PanelDef(slotIndex))
        elseif key == "dynamicrez" then
            -- By CLASS rather than by what is in the book right now, which is what
            -- ns.HasRezKit answers: a paladin who has not taken Intercession still
            -- has Redemption, and a druid too low for Rebirth will have it. Hiding
            -- the entry on those would take it away from the character it is FOR.
            -- A mage carrying the shared menu is the case this catches, and it is
            -- the one the entry's own note names.
            return mod.HasRezKit()
        end
        return true
    end

    -- Nested palette slots inside a nest fire nothing (one level), so they never count.
    local function NestOffersAny(childFrame)
        local palette = ReadPalette(childFrame)
        if not palette then
            return false
        end
        local cp = Inner.PA(childFrame)
        local all = cp and cp.hideUnusable == false
        for _, slotIndex in ipairs(palette.slots) do
            if slotIndex.kind ~= "palette" and (all or SlotUsable(slotIndex)) then
                return true
            end
        end
        return false
    end

    -- The entries of the palette this character can use ("Hide Unavailable
    -- Actions"). A view, never a mutation: returns the stored array itself while
    -- nothing is filtered, and a fresh dense array otherwise -- the stored slots
    -- keep every entry for the characters that CAN use them. A nested palette
    -- that does not load in this spec (Assign to Spec), or that would open with
    -- nothing this character can use under its own setting, is left out whatever
    -- this palette's setting says; with it off, everything else stays.
    function UsableSlots(palette, p)
        local slots = palette and palette.slots
        if not slots then
            return slots
        end
        local memo = usableMemo[palette]
        if memo then
            return memo
        end
        local all = p and p.hideUnusable == false
        local result
        for idx = 1, #slots do
            local slotIndex = slots[idx]
            local keep
            if slotIndex.kind == "palette" then
                local childFrame = ChildIndex(slotIndex)
                keep = not childFrame or (mod.PaletteActive(childFrame) and NestOffersAny(childFrame))
            else
                keep = all or SlotUsable(slotIndex)
            end
            if not keep then
                if not result then
                    result = {}
                    for jdx = 1, idx - 1 do
                        result[jdx] = slots[jdx]
                    end
                end
            elseif result then
                result[#result + 1] = slotIndex
            end
        end
        usableMemo[palette] = result or slots
        return result or slots
    end
end
SetUsableSlots(UsableSlots)

-- kind -> attribute triple for the secure button, plus an optional 4th value:
-- a sibling attribute key that must be cleared because the same action type
-- would otherwise read it in preference. Returns nil for the kinds with no
-- secure action type at all (battlepet, the two spec kinds, the mounts), which
-- FireInsecure handles instead.
--
-- p is the palette's appearance view, for the one kind whose action depends on
-- a setting rather than only on the slot (worldmarker). It is the view of the
-- palette being PUSHED, which for a nest's cells is the owner's -- the same
-- palette whose appearance draws them.
local function ResolveAction(slotIndex, p)
    if not slotIndex or not slotIndex.kind then
        return nil
    end
    local key = slotIndex.kind

    -- A palette opens entries; it never fires one. Returning nothing is what
    -- makes a release on the parent itself a cancel, which is the only sensible
    -- reading of "you stopped on the door rather than going through it".
    if key == "palette" then
        return nil
    end

    if key == "spell" then
        if type(slotIndex.id) ~= "number" then
            return nil
        end
        return "spell", "spell", SlotRank(slotIndex)
    elseif key == "dynamicprofession" then
        -- Resolved to the CURRENT position's spell every time the
        -- attributes are written, then fired the same way any other spell
        -- slot is -- see ns.ProfessionSpellFor above for what makes the
        -- position current.
        local spellId = mod.ProfessionSpellFor(slotIndex)
        if not spellId then
            return nil
        end
        return "spell", "spell", spellId
    elseif key == "item" then
        if type(slotIndex.id) ~= "number" then
            return nil
        end
        return "item", "item", "item:" .. slotIndex.id
    elseif key == "toy" then
        if type(slotIndex.id) ~= "number" then
            return nil
        end
        return "toy", "toy", slotIndex.id
    elseif key == "randomhearth" then
        local kindOf, ident = Hearth.Current()
        if kindOf == "toy" then
            return "toy", "toy", ident
        end
        return "item", "item", "item:" .. ident
    elseif key == "outfit" then
        local details = mod.OutfitInfo(slotIndex)
        if not details then
            return nil
        end
        return "outfit", "outfit-index", details.playerFacingOutfitIndex
    elseif key == "equipmentset" then
        local name = mod.EquipmentSetInfo(slotIndex)
        if not name then
            return nil
        end
        return "equipmentset", "equipmentset", name
    elseif key == "macro" then
        -- Stored by name so reordering the macro list doesn't repoint the
        -- slot. RunMacro accepts a name, so the name is what we hand over.
        -- The 4th return clears the sibling key: type="macro" reads "macro"
        -- first and only falls through to "macrotext" when it is unset
        -- (SecureTemplates.lua:441). The direction that matters is therefore
        -- the other branch -- a macrotext slot must clear a stale "macro", or
        -- the earlier slot's macro name wins. This branch clears macrotext for
        -- symmetry, so neither key can outlive the slot that set it.
        local nameOrIndex = slotIndex.name or slotIndex.id
        if not nameOrIndex then
            return nil
        end
        return "macro", "macro", nameOrIndex, "macrotext"
    elseif key == "macrotext" then
        if type(slotIndex.macrotext) ~= "string" or slotIndex.macrotext == "" then
            return nil
        end
        return "macro", "macrotext", slotIndex.macrotext, "macro"
    elseif key == "mount" then
        -- C_MountJournal.SummonByID is protected, so the mount is summoned
        -- through its own summon spell instead.
        --
        -- By NAME, not by id: SECURE_ACTIONS.spell routes a numeric value to
        -- CastSpellByID and a string to CastSpellByName
        -- (SecureTemplates.lua:387-395). Mount summon spells do not live in the
        -- spellbook, and CastSpellByID does nothing for them; CastSpellByName is
        -- the path a plain "/cast <mount>" macro takes, which does work.
        local mountName, spellId = nil, slotIndex.spellID
        if slotIndex.id then
            mountName, spellId = C_MountJournal.GetMountInfoByID(slotIndex.id)
            spellId = slotIndex.spellID or spellId
        end
        -- The spell's own name over the journal's display name: it is what
        -- CastSpellByName resolves against.
        local details = type(spellId) == "number" and C_Spell.GetSpellInfo(spellId)
        local castName = (details and details.name) or mountName
        if type(castName) ~= "string" or castName == "" then
            return nil
        end
        return "spell", "spell", castName
    elseif key == "raidtarget" then
        -- Fired as the /tm slash command rather than through
        -- SECURE_ACTIONS.raidtarget: that action reads TWO attributes, marker
        -- and action, and the firing end of the snippet pushes exactly one key
        -- per cell. The command reaches SetRaidTarget itself
        -- (SlashCommands.lua:1381-1406), and /tm 0 is its documented clear.
        --
        -- What makes that legal is the secure button running the macro, NOT
        -- anything about SetRaidTarget: it is protected, and refuses any call
        -- an addon makes from its own Lua. See the clearmarkers branch below,
        -- which was written on the opposite assumption and did not work.
        local ident = tonumber(slotIndex.id)
        if not ident or ident < 0 or ident > 8 then
            return nil
        end
        return "macro", "macrotext", "/tm " .. ident, "macro"
    elseif key == "clearmarkers" then
        -- SECURE_ACTIONS.raidtarget's own clear-all branch, which calls
        -- RemoveRaidTargets (SecureTemplates.lua:590-592). SetRaidTarget is
        -- documented AllowedWhenUntainted and is refused outright from an
        -- addon's own Lua -- the sweep this replaces raised
        -- ADDON_ACTION_FORBIDDEN on its first call -- so going through the
        -- secure button, which runs the action untainted, is the only route.
        --
        -- The ACTION rides in the ordinary key/value slot: raidtarget reads
        -- "marker" and "action", and the firing end of the snippet pushes one
        -- key per cell. clear-all is the one branch that never looks at
        -- "marker", so the single key can be spent on "action" instead.
        --
        -- It also clears more than the loop could: RemoveRaidTargets reaches
        -- marks on units the client cannot currently name, which no clear-all
        -- macro can. In a group it needs lead or assist, and quietly does
        -- nothing without them -- the same rule as marking itself.
        return "raidtarget", "action", "clear-all"
    elseif key == "worldmarker" then
        -- Same one-attribute reasoning as /tm above: /wm places a world
        -- marker, /cwm clears. Both take the ENGINE's marker number, so the
        -- stored icon position goes through the map.
        local ident = tonumber(slotIndex.id)
        if not ident or ident < 0 or ident > 8 then
            return nil
        end
        if ident == 0 then
            -- The /cwm handler compares its argument against the client's own
            -- ALL string (SlashCommands.lua:824-830), so that string is what
            -- gets baked -- a hardcoded "all" would fail on a localized client.
            return "macro", "macrotext", "/cwm " .. (ALL or "all"), "macro"
        end
        if p == nil or p.worldMarkerToggle ~= false then
            -- Toggle World Markers. Not a macro: /wm is PlaceRaidMarker with
            -- no test at all (SlashCommands.lua:820), and no macro conditional
            -- reports a world marker as down. SECURE_ACTIONS.worldmarker does
            -- the test itself (SecureTemplates.lua:602-618), and still costs
            -- the ONE attribute a cell may spend -- it reads "marker" and
            -- "action", and "action" falls back to "toggle" when unset, which
            -- the snippet's clear guarantees it is.
            --
            -- Placement is unchanged: neither Blizzard nor /wm passes a unit
            -- token, so the marker still lands under the cursor.
            return "worldmarker", "marker", WORLD_MARKER_ENGINE[ident]
        end
        -- Repeating ONE marker fast stalls here, where cycling eight does not:
        -- the game holds each marker on its own cooldown -- about four spammed
        -- presses -- and answers "You can't do that right now". Nothing to do
        -- with this module: a plain /wm macro alone does it.
        --
        -- Clearing before placing, the way retail's own marker button does
        -- (Mainline/Blizzard_CompactRaidFrameManager.lua:1065-1066), does not
        -- buy anything from a macro: the /cwm spends the cooldown and the /wm
        -- behind it lands inside the window, which reads as a toggle. Blizzard
        -- gets away with it by calling both C functions straight from an
        -- OnClick, which is not a route an addon has.
        return "macro", "macrotext", "/wm " .. WORLD_MARKER_ENGINE[ident], "macro"
    elseif key == "dynamicrez" then
        -- Fired as macro text, which is what makes it dynamic in the way that
        -- matters: the attributes are written out of combat, and a rez has to
        -- pick its branch DURING the fight. The game evaluates [combat] when
        -- the macro runs, so a menu pushed before the pull still casts the
        -- battle rez in it. A resolved spellID could not do that.
        local textValue = Rez.MacroText()
        if not textValue then
            return nil
        end
        return "macro", "macrotext", textValue, "macro"
    elseif key == "panel" then
        -- "/click <micro button>", so the panel opens on Blizzard's own click
        -- rather than on ours: the macro runs untainted from the secure
        -- button, and a panel opened by an addon's Lua carries that addon's
        -- taint into everything it draws. The panels with no micro button
        -- answer nothing here and go to FireInsecure instead.
        local textValue = mod.PanelMacro(mod.PanelDef(slotIndex))
        if not textValue then
            return nil
        end
        return "macro", "macrotext", textValue, "macro"
    elseif key == "cycleraidtarget" or key == "cycleworldmarker" then
        -- The step the position on the slot says is up. The snippet overwrites
        -- this with its own answer on every press -- see the eqdCycN branch --
        -- so what is pushed here is only what the entry would fire if the
        -- cycle attributes went missing: the right marker, just not advancing.
        --
        -- Deliberately NOT affected by Toggle World Markers, though the step
        -- machinery would carry a marker number as readily as a macro. A cycle
        -- is a run THROUGH the eight, and a step that picks its marker back up
        -- because that one happened to be down already breaks the run: the
        -- press that should have placed the circle places nothing, and the
        -- position still advances. Placing every time is the only behavior
        -- that keeps a cycle predictable.
        local steps = CycleSteps(key)
        return "macro", "macrotext", steps[CycleNext(slotIndex)], "macro"
    end

    return nil
end
mod.ResolveAction = ResolveAction

-- The kinds with no secure action type at all. None of these calls is
-- protected -- summoning a battle pet or a mount and changing specialization
-- are all ordinary API -- so all are safe straight from PostClick.
--
-- WHICH cell reaches here is the snippet's answer rather than the live view's
-- selection; see OnPostClick.
local function FireInsecure(slotIndex)
    if not slotIndex then
        return
    end
    if slotIndex.kind == "battlepet" and slotIndex.guid and C_PetJournal then
        C_PetJournal.SummonPetByGUID(slotIndex.guid)
    elseif slotIndex.kind == "randommount" and C_MountJournal then
        -- The Mount Journal button's own call
        -- (Blizzard_MountCollection.lua:998); 0 means "a random favorite".
        -- Refused by the game itself in combat, where no mount can be
        -- summoned anyway.
        C_MountJournal.SummonByID(0)
    elseif slotIndex.kind == "lastmount" and C_MountJournal then
        -- The same call with the mount the player last rode, tracked rather
        -- than stored on the slot -- the whole point of the entry is that it
        -- changes on its own. Nothing tracked yet (a fresh profile, or a
        -- session where the player has not mounted) falls back to the random
        -- favorite rather than doing nothing: an entry that answers a press
        -- with silence reads as broken.
        local popFrame = Prm()
        local ident = popFrame and popFrame.lastMountID
        C_MountJournal.SummonByID(type(ident) == "number" and ident or 0)
    elseif slotIndex.kind == "panel" then
        -- Only the panels ResolveAction had no micro button for. Out of combat
        -- only, which is the game's rule rather than ours: an insecure
        -- ShowUIPanel is refused in a fight, and it refuses it quietly.
        mod.PanelFire(mod.PanelDef(slotIndex))
    elseif slotIndex.kind == "spec" or slotIndex.kind == "dynamicspec" then
        local slotPos = SpecIndexFor(slotIndex)
        -- Refused in combat by the game itself, with its own error message.
        -- Nothing to defer to PLAYER_REGEN_ENABLED: a spec change the user
        -- asked for mid-fight and got minutes later is not what they meant.
        if slotPos then
            C_SpecializationInfo.SetSpecialization(slotPos)
        end
    end
end

-- The fileID behind the question mark path above. GetMacroInfo answers a fileID
-- rather than a path, so the two cannot be compared without this.
local QUESTION_MARK_ID = GetFileIDFromPath and GetFileIDFromPath(QUESTION_MARK)

-- The icon for what a macro would fire RIGHT NOW, or nil to fall back to the
-- icon the macro was saved with.
--
-- A macro's conditionals are evaluated when it runs, so a [mod] macro fires a
-- different spell depending on what is held at the release -- and the palette
-- has to draw the branch it is going to take, or it shows one picture and casts
-- the other. GetMacroSpell and GetMacroItem answer the current branch.
--
-- ONLY for a macro sitting on the dynamic "?" icon, which is what the caller's
-- question-mark test is for. A macro the player gave a real icon keeps it, the
-- way Blizzard's own action buttons keep it: that icon is a choice, and
-- resolving over the top of it would take the choice away. It also makes this
-- safe whichever of the two things GetMacroInfo does -- return the saved icon,
-- or resolve the dynamic one itself -- because in the resolving case a "?" macro
-- never reaches here with a question mark to begin with.
--
-- By macro NAME resolved to an index, which is the pairing the rest of the suite
-- settled on (CludesUICooldownManager.lua:6986-6992): the id a macro action
-- carries is not reliably a macro index, and these two want the index.
local function MacroIcon(nameOrIndex)
    if not nameOrIndex then
        return nil
    end
    local slotPos = nameOrIndex
    if type(slotPos) ~= "number" then
        slotPos = GetMacroIndexByName(slotPos)
    end
    if not slotPos or slotPos <= 0 then
        return nil
    end

    local spellId = GetMacroSpell(slotPos)
    if spellId then
        local details = C_Spell.GetSpellInfo(spellId)
        if details and details.iconID then
            return details.iconID
        end
    end

    -- An item branch answers no spell. The link, not the name: it carries the
    -- itemID, and a name would have to be looked up again to get one.
    --
    -- The existence guard is a statement rather than `GetMacroItem and
    -- GetMacroItem(index)` -- an `and` expression is truncated to ONE value, so
    -- that form would drop the link and leave every item macro on its saved
    -- icon. Same trap SlotDisplay's own note names, one function below.
    if GetMacroItem then
        local _, itemLink = GetMacroItem(slotPos)
        if itemLink then
            local _, _, _, _, glyph = C_Item.GetItemInfoInstant(itemLink)
            if glyph then
                return glyph
            end
        end
    end

    -- Neither -- a macro that only marks, targets or emotes. The saved icon is
    -- the honest answer for those, and it is the one the caller falls back to.
    return nil
end

-- icon, name for display. Never returns nil for icon so a slot whose target
-- has been removed from the game still renders as an occupied slot.
--
-- Note the deliberate absence of `C_Foo and C_Foo.Bar(x)` guards here: an
-- `and` expression is truncated to ONE value, which would silently drop every
-- return past the first and leave every icon nil.
local function SlotDisplay(slotIndex)
    if not slotIndex or not slotIndex.kind then
        return nil, nil
    end
    local key = slotIndex.kind

    if key == "spell" then
        local ident = SlotRank(slotIndex)
        local details = C_Spell.GetSpellInfo(ident)
        if details then
            local name = details.name
            -- A pinned rank is named with it ("Shadow Bolt (Rank 3)"); nothing
            -- else tells it from the entry that follows the highest rank.
            if slotIndex.rankPinned and CludesUI.IS_FOREVER then
                local subFrame = C_Spell.GetSpellSubtext(ident)
                if subFrame and subFrame ~= "" then
                    name = name .. " (" .. subFrame .. ")"
                end
            end
            return details.iconID or QUESTION_MARK, name
        end
    elseif key == "item" then
        if type(slotIndex.id) ~= "number" then
            return QUESTION_MARK, slotIndex.name
        end
        local _, _, _, _, glyph = C_Item.GetItemInfoInstant(slotIndex.id)
        local name = C_Item.GetItemInfo(slotIndex.id)
        return glyph or QUESTION_MARK, name or slotIndex.name
    elseif key == "toy" then
        if type(slotIndex.id) ~= "number" then
            return QUESTION_MARK, slotIndex.name
        end
        local _, name, glyph = C_ToyBox.GetToyInfo(slotIndex.id)
        return glyph or QUESTION_MARK, name or slotIndex.name
    elseif key == "randomhearth" then
        -- The hearthstone this open rolled, like the last-mount entry draws
        -- the mount it would summon. The entry's own name stands in until the
        -- toy's data has loaded.
        local kindOf, ident = Hearth.Current()
        if kindOf == "toy" then
            local _, name, glyph = C_ToyBox.GetToyInfo(ident)
            return glyph or QUESTION_MARK, name or "Random Hearthstone"
        end
        local _, _, _, _, glyph = C_Item.GetItemInfoInstant(ident)
        return glyph or QUESTION_MARK, C_Item.GetItemInfo(ident) or "Random Hearthstone"
    elseif key == "outfit" then
        local details = mod.OutfitInfo(slotIndex)
        return mod.OutfitIcon(details) or mod.OutfitIcon(slotIndex) or QUESTION_MARK,
            (details and details.name) or slotIndex.name or "Outfit"
    elseif key == "equipmentset" then
        local name, glyph = mod.EquipmentSetInfo(slotIndex)
        return glyph or slotIndex.icon or QUESTION_MARK, name or slotIndex.name or "Equipment Set"
    elseif key == "macro" then
        local nameOrIndex = slotIndex.name or slotIndex.id
        local name, glyph = GetMacroInfo(nameOrIndex)
        -- A question mark here means the macro carries no icon of its own, so
        -- what it is about to fire is the only thing left to draw. Anything else
        -- is an icon the player picked, and it stands. See MacroIcon.
        if glyph == nil or glyph == QUESTION_MARK or glyph == QUESTION_MARK_ID then
            glyph = MacroIcon(nameOrIndex) or glyph
        end
        return glyph or QUESTION_MARK, name or slotIndex.name
    elseif key == "macrotext" then
        -- slot.icon may be a { atlas = ... } table (the Pings preset stores
        -- one verbatim); SetIconTexture/ApplyIconCrop render both forms.
        return slotIndex.icon or QUESTION_MARK, slotIndex.name or "Macro"
    elseif key == "dynamicrez" then
        -- The spell it would cast, not a fixed emblem: the entry is worth
        -- having because it changes, and one picture over three different casts
        -- would hide the only thing it has to say.
        local ident = Rez.SpellNow()
        local details = ident and C_Spell.GetSpellInfo(ident)
        if details then
            return details.iconID or QUESTION_MARK, details.name
        end
        -- A character with no resurrection spell at all -- the mage carrying
        -- the shared palette. Drawn as an occupied slot under its own name, the
        -- same as a spec this character does not have.
        return QUESTION_MARK, "Dynamic Rez"
    elseif key == "mount" then
        if type(slotIndex.id) ~= "number" then
            return QUESTION_MARK, slotIndex.name
        end
        local name, _, glyph = C_MountJournal.GetMountInfoByID(slotIndex.id)
        return glyph or QUESTION_MARK, name or slotIndex.name
    elseif key == "lastmount" then
        -- Whatever is tracked right now, so the entry shows the mount it would
        -- actually summon. Before anything is tracked it shows what it would
        -- fall back to, which is the random favorite (see FireInsecure), under
        -- a name that says what the entry IS rather than what it is standing
        -- in for.
        local popFrame = Prm()
        local ident = popFrame and popFrame.lastMountID
        if type(ident) == "number" then
            local name, _, glyph = C_MountJournal.GetMountInfoByID(ident)
            if name then
                return glyph or QUESTION_MARK, name
            end
        end
        local details = C_Spell.GetSpellInfo(RANDOM_FAVORITE_MOUNT)
        return (details and details.iconID) or QUESTION_MARK, "Last Used Mount"
    elseif key == "randommount" then
        local details = C_Spell.GetSpellInfo(RANDOM_FAVORITE_MOUNT)
        -- The client's own caption for the Mount Journal button, so the entry
        -- reads the same on a localized client as the thing it summons.
        return (details and details.iconID) or QUESTION_MARK,
            MOUNT_JOURNAL_SUMMON_RANDOM_FAVORITE_MOUNT
                or (details and details.name)
                or "Random Favorite Mount"
    elseif key == "spec" or key == "dynamicspec" then
        local slotPos = SpecIndexFor(slotIndex)
        if slotPos then
            -- Both kinds draw the specialization they would switch to, which
            -- is the whole point of the dynamic one: the icon and the name are
            -- this character's, so a palette carried to another class arrives
            -- showing that class's specs rather than the owner's.
            local _, name, _, glyph = C_SpecializationInfo.GetSpecializationInfo(slotPos)
            return glyph or QUESTION_MARK, name or slotIndex.name
        end
        if key == "dynamicspec" then
            -- A position this class has not got: four on anything but a
            -- druid, three on a demon hunter. The entry names a seat rather
            -- than an occupant, so with no occupant to draw it says the seat.
            return QUESTION_MARK, mod.SpecPositionName(tonumber(slotIndex.index))
        end
        -- A spec this character's class does not have. Its identity is still
        -- global -- the specID answers by itself -- so the editor and an
        -- unfiltered menu draw the real specialization, not a placeholder.
        local wanted = tonumber(slotIndex.specID)
        if wanted and GetSpecializationInfoByID then
            local _, name, _, glyph = GetSpecializationInfoByID(wanted)
            if glyph or name then
                return glyph or QUESTION_MARK, name or slotIndex.name
            end
        end
        return QUESTION_MARK, slotIndex.name
    elseif key == "dynamicprofession" then
        if slotIndex.extra or slotIndex.specialization then
            -- The ABILITY's own name and icon rather than the profession's:
            -- unlike the opener, these entries are distinct spells.
            local spellId = mod.ProfessionSpellFor(slotIndex)
            if spellId then
                local details = C_Spell.GetSpellInfo(spellId)
                if details then
                    return details.iconID or QUESTION_MARK, details.name or slotIndex.name
                end
            end
        else
            local bookIndex = mod.ProfessionBookIndexFor(slotIndex)
            if bookIndex then
                -- The profession's own name and icon, not the opener
                -- spell's -- the same skill icon its spellbook entry shows.
                local name, glyph = GetProfessionInfo(bookIndex)
                return glyph or QUESTION_MARK, name or slotIndex.name
            end
        end
        -- An unavailable position, native extra, or specialization ability.
        -- Name the seat rather than an occupant, like an empty dynamicspec.
        return QUESTION_MARK,
            mod.ProfessionPositionName(tonumber(slotIndex.index), slotIndex.extra, slotIndex.specialization)
    elseif key == "battlepet" then
        if type(slotIndex.guid) ~= "string" then
            return QUESTION_MARK, slotIndex.name
        end
        local _, _, _, _, _, _, _, name, glyph = C_PetJournal.GetPetInfoByPetID(slotIndex.guid)
        return glyph or QUESTION_MARK, name or slotIndex.name
    elseif key == "raidtarget" then
        local ident = tonumber(slotIndex.id) or 0
        if ident < 1 or ident > 8 then
            return "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Clear Target Marker"
        end
        return MarkerIcon(ident), "Target Marker: " .. MARKER_NAMES[ident]
    elseif key == "clearmarkers" then
        return "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Clear All Target Markers"
    elseif key == "worldmarker" then
        local ident = tonumber(slotIndex.id) or 0
        if ident < 1 or ident > 8 then
            return "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Clear World Markers"
        end
        return MarkerIcon(ident), "World Marker: " .. MARKER_NAMES[ident]
    elseif key == "cycleraidtarget" or key == "cycleworldmarker" then
        -- Drawn as the marker the next press places, not as a fixed emblem: in
        -- a radial the icon is what the entry is picked by, and one that never
        -- changed while the action did would be worse than no entry at all.
        local ident = CycleNext(slotIndex)
        local what = (key == "cycleraidtarget") and "Target" or "World"
        return MarkerIcon(ident), "Cycle " .. what .. " Marker: " .. MARKER_NAMES[ident]
    elseif key == "panel" then
        -- The art is ours rather than the micro button's own: those atlases
        -- are the 32x40 shape of a micro button and would be stretched square
        -- by the icon a menu entry draws at.
        local spec_def = mod.PanelDef(slotIndex)
        if spec_def then
            return spec_def.icon, mod.PanelName(spec_def)
        end
        -- A key from a newer version of the module, or one that has been
        -- retired. Drawn as an occupied slot, like every other unresolved kind.
        return QUESTION_MARK, slotIndex.name or "Interface Panel"
    elseif key == "palette" then
        -- ReadPalette, not EnsurePalette: a nested parent is repainted from the
        -- steering path, which must not rewrite the profile's slot array.
        local palette = ReadPalette(ChildIndex(slotIndex))
        -- Two choices before the fallback, narrowest first: this entry's own
        -- override, then the palette's first entry -- so a "Mounts" palette
        -- looks like a mount without anyone having to pick an icon for it.
        -- Only one level down: a first entry that is itself a palette would
        -- send this round its own loop.
        local glyph = slotIndex.icon
        local first = palette and palette.slots[1]
        if not glyph and first and first.kind ~= "palette" then
            glyph = SlotDisplay(first)
        end
        return glyph or QUESTION_MARK, slotIndex.name or (palette and palette.name) or "Action Menu"
    end

    return QUESTION_MARK, slotIndex.name
end
mod.SlotDisplay = SlotDisplay

-- Cooldown source per kind. Returns start, duration, enable -- handed to
-- CooldownFrame_Set verbatim, never compared or arithmetic'd, so secret
-- cooldown values stay untouched.
-- Returns EITHER a duration object (spells, mounts) OR start, duration, enable
-- (items, toys). Two shapes because only spells have a secret-safe getter.
--
-- Spell cooldowns must not go through C_Spell.GetSpellCooldown: it is flagged
-- SecretWhenCooldownsRestricted (SpellDocumentation.lua:252), so once cooldowns
-- are restricted its startTime and duration come back as SECRET numbers. Our
-- execution is an addon's and therefore tainted, and CooldownFrame_Set opens with
-- `start > 0 and duration > 0` (Cooldown.lua:3) -- comparing a secret from
-- tainted execution throws. C_Spell.GetSpellCooldownDuration returns an opaque
-- duration object instead: it is AllowedWhenTainted, and it goes straight into
-- the widget C-side, so nothing here ever reads a secret.
--
-- Items keep the plain numeric path -- C_Item.GetItemCooldown carries no secret
-- flag and there is no duration-object equivalent for items.
--
-- The spellID an entry's live state is read from, for the kinds that HAVE one.
-- Dynamic entries answer the spell they resolve to right now, so their
-- cooldown describes the same spell as their icon and secure action.
local function SlotSpellID(slotIndex)
    if not slotIndex then
        return nil
    end
    if slotIndex.kind == "spell" then
        return type(slotIndex.id) == "number" and SlotRank(slotIndex) or nil
    elseif slotIndex.kind == "dynamicrez" then
        return Rez.SpellNow()
    elseif slotIndex.kind == "dynamicprofession" then
        return mod.ProfessionSpellFor(slotIndex)
    end
    return nil
end

-- The itemID an entry's live state is read from, for the item-backed kinds.
-- A toy's id IS its itemID. Random Hearthstone answers this open's pick.
local function SlotItemID(slotIndex)
    local key = slotIndex and slotIndex.kind
    if key == "item" or key == "toy" then
        return type(slotIndex.id) == "number" and slotIndex.id or nil
    elseif key == "randomhearth" then
        local _, ident = Hearth.Current()
        return ident
    end
    return nil
end

-- Display data the client only has once it has been ASKED for: GetSpellInfo
-- answers nothing for a spell whose data has not been loaded this session
-- (SpellDocumentation.lua:800-803), and the toy and item getters answer nothing
-- until their item has. A palette paints once per open, so an entry drawn ahead
-- of its data kept the question mark for the whole of that open, and the second
-- open was right only because the first one's failed lookup had fetched it.
-- Both ns-hosted for the reason ns.SetIconTexture is: as one file the module's
-- main chunk was at Lua 5.1's 200-local cap.
function mod.SlotDataReady(slotIndex)
    if not slotIndex then
        return true
    end
    local key = slotIndex.kind

    if key == "spell" or key == "dynamicrez" or key == "dynamicprofession" then
        local ident = SlotSpellID(slotIndex)
        return not ident or C_Spell.IsSpellDataCached(ident)
    end

    -- A toy's id IS its itemID, so the two kinds share the one cache. An item's
    -- icon comes off the client's own table and is right either way; its NAME
    -- is what the load is for, and the hub caption reads that.
    if key == "item" or key == "toy" or key == "randomhearth" then
        local ident = SlotItemID(slotIndex)
        return not ident or C_Item.IsItemDataCachedByID(ident)
    end

    -- Every other kind reads a client-side table -- the mount journal, the pet
    -- journal, the spec and profession lists -- and answers on the first ask.
    return true
end

-- Ask for it, and say whether the answer is still outstanding. Separate from the
-- test above because AdvancePendingIcons retests every frame and must not send
-- the request again with each one.
function mod.WarmSlot(slotIndex)
    if mod.SlotDataReady(slotIndex) then
        return false
    end
    local itemId = SlotItemID(slotIndex)
    if itemId then
        C_Item.RequestLoadItemDataByID(itemId)
    else
        C_Spell.RequestLoadSpellData(SlotSpellID(slotIndex))
    end
    return true
end

local function SlotCooldown(slotIndex)
    if not slotIndex then
        return nil
    end
    local key = slotIndex.kind
    if
        key == "spell"
        or key == "mount"
        or key == "dynamicrez"
        or key == "dynamicprofession"
        or key == "outfit"
    then
        local ident
        if key == "mount" then
            -- No falling back to slot.id here: that is a mountID, and looking
            -- a mountID up as a spellID reports some unrelated spell's cooldown.
            ident = slotIndex.spellID or select(2, C_MountJournal.GetMountInfoByID(slotIndex.id))
        elseif key == "outfit" then
            ident = Constants.TransmogOutfitDataConsts.EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID
        else
            ident = SlotSpellID(slotIndex)
        end
        if ident and C_Spell.GetSpellCooldownDuration then
            -- Parenthesised, so only the duration comes back: 12.1 returns a
            -- second value that would land in this function's `start` slot and
            -- hand a boolean to CooldownFrame_Set.
            return (C_Spell.GetSpellCooldownDuration(ident))
        end
    elseif key == "item" or key == "toy" or key == "randomhearth" then
        local ident = SlotItemID(slotIndex)
        if ident and C_Item.GetItemCooldown then
            return nil, C_Item.GetItemCooldown(ident)
        end
    end
    return nil
end

-- WHETHER an entry writes a number in its corner, and WHAT that number is --
-- deliberately two returns rather than one nilable value. Two things earn a
-- number: a stack of items, and a spell's charges.
--
-- The charge count must never be looked at, not even for truth or for nil.
-- C_Spell.GetSpellCharges is flagged SecretWhenCooldownsRestricted
-- (SpellDocumentation.lua:234), so currentCharges comes back a SECRET number
-- once restrictions are in effect, and touching one from tainted execution
-- throws -- the same wall the spell cooldown hit. So the caller is told
-- separately that there IS a count, and the count itself only ever reaches
-- SetText, which swallows a secret; Blizzard's own action button hands the
-- identical kind of value to the identical call (ActionButton.lua:810).
--
-- What is safe to test is the TABLE the call returns, which is not itself
-- secret: it comes back as nothing for a spell that has no charges at all.
--
-- Neither item call carries a secret flag, so those may be compared -- and
-- have to be, because a count only means something on a stackable item. A
-- Hearthstone writing "1" in its corner is noise.
local function SlotCount(slotIndex)
    if not slotIndex then
        return false
    end
    local key = slotIndex.kind

    -- A battle rez is the charge-carrying spell this matters most for: how many
    -- are left is the whole question a raid asks of it.
    if key == "spell" or key == "dynamicrez" then
        local ident = SlotSpellID(slotIndex)
        if not ident or not C_Spell.GetSpellCharges then
            return false
        end
        local charges = C_Spell.GetSpellCharges(ident)
        if not charges then
            return false
        end
        return true, charges.currentCharges
    elseif key == "item" then
        if type(slotIndex.id) ~= "number" then
            return false
        end
        -- Position 8 is the stack size. It is nil until the item's data has
        -- been cached, which costs at most the count on one open -- the
        -- palette repaints from scratch every time it is drawn.
        local stack = select(8, C_Item.GetItemInfo(slotIndex.id))
        if not stack or stack <= 1 then
            return false
        end
        return true, C_Item.GetItemCount(slotIndex.id)
    end

    return false
end

-- How an entry that CANNOT be fired right now is tinted, in the three states
-- an action button has always distinguished. The idle and selected tints are
-- multiplied through these, so an unusable entry still reads as selected while
-- saying why it would do nothing.
local USABILITY_TINT = {
    OUTOFRANGE = { 0.90, 0.20, 0.20, false },
    NOPOWER = { 0.45, 0.45, 1.00, false },
    UNUSABLE = { 0.45, 0.45, 0.45, true },
}

-- Which of those states an entry is in, or nil for an entry that is fine and
-- for a kind with nothing to say.
--
-- Every call here is secret-SAFE, and that was checked rather than assumed:
-- C_Spell.IsSpellUsable, C_Spell.IsSpellInRange, C_Item.IsUsableItem,
-- C_Item.ItemHasRange, C_Item.IsItemInRange,
-- C_MountJournal.GetMountUsabilityByID and IsIndoors all carry no
-- SecretWhenCooldownsRestricted flag in the generated documentation, unlike
-- the cooldown and charge getters two functions up. So these results may be
-- branched on. Secrecy is not protection, though: C_Item.IsItemInRange is
-- additionally a PROTECTED call in combat and in protected instances against
-- a unit the player cannot attack, so it sits behind the Range module's gate
-- below. Do not add a kind here without checking its getter both ways -- a
-- mount's usability, for one, has to come from the Mount Journal rather than
-- from its summon spell, which is not in the spellbook and answers unusable
-- for every mount.
--
-- Out of range OUTRANKS the other two, matching every action bar: a spell you
-- cannot reach is the thing to say first, and it is the state a step forward
-- fixes.
--
-- Macros, markers and palettes answer nil. A macro's usability is whatever its
-- body resolves to, which is not knowable from here, and tinting one gray on a
-- guess is worse than saying nothing.
--
-- Toys also answer nil. A toy is not a bag item, so C_Item.IsUsableItem says
-- unusable for every toy a player owns, and graying the whole Hearthstones
-- palette is exactly what that produced. The toy box itself draws no
-- usability tint -- Blizzard_ToyBox.lua desaturates only UNCOLLECTED toys --
-- and the cooldown swipe already tells the one thing a toy has to tell.
local function SlotUsability(slotIndex)
    if not slotIndex then
        return nil
    end
    local key = slotIndex.kind

    if key == "spell" or key == "dynamicrez" then
        local ident = SlotSpellID(slotIndex)
        if not ident then
            return nil
        end
        if C_Spell.IsSpellInRange(ident) == false then
            return "OUTOFRANGE"
        end
        local usable, noPower = C_Spell.IsSpellUsable(ident)
        if usable then
            return nil
        end
        return noPower and "NOPOWER" or "UNUSABLE"
    elseif key == "item" then
        if type(slotIndex.id) ~= "number" then
            return nil
        end
        -- Range against the target is a PROTECTED query in combat and in
        -- protected instances when the target cannot be attacked; the Range
        -- module owns that rule. Skipped = no range tint, usability still applies.
        local allowed = CludesUI.ItemRangeChecksAllowed
        if
            C_Item.ItemHasRange(slotIndex.id)
            and allowed
            and allowed("target")
            and C_Item.IsItemInRange(slotIndex.id, "target") == false
        then
            return "OUTOFRANGE"
        end
        local usable, noPower = C_Item.IsUsableItem(slotIndex.id)
        if usable then
            return nil
        end
        return noPower and "NOPOWER" or "UNUSABLE"
    elseif key == "outfit" then
        return InCombatLockdown() and "UNUSABLE" or nil
    elseif key == "equipmentset" then
        if InCombatLockdown() or not mod.EquipmentSetInfo(slotIndex) then
            return "UNUSABLE"
        end
    elseif key == "mount" or key == "lastmount" or key == "randommount" then
        -- The Mount Journal's own answer, the one behind its Summon button's
        -- "You can't mount here" line, indoors counted (checkIndoors): plain
        -- booleans, no secret flags, on both clients. A mount entry asks about
        -- its mount and the last-mount entry about the mount it summons. The
        -- random favorite summons whichever favorite is usable, so it has no
        -- one mount to ask about: it dims only where no mount can be summoned,
        -- indoors or in combat -- the test the last-mount entry falls back to
        -- before a mount is tracked, or when the journal answers nothing (its
        -- getter may return nothing).
        if key == "randommount" then
            return (IsIndoors() or InCombatLockdown()) and "UNUSABLE" or nil
        end
        local ident = slotIndex.id
        if key == "lastmount" then
            local popFrame = Prm()
            ident = popFrame and popFrame.lastMountID
        end
        if type(ident) == "number" and ident > 0 then
            local usable = C_MountJournal.GetMountUsabilityByID(ident, true)
            if usable ~= nil then
                return usable == false and "UNUSABLE" or nil
            end
        end
        if key == "lastmount" and (IsIndoors() or InCombatLockdown()) then
            return "UNUSABLE"
        end
    end

    return nil
end

-- Build a slot table from whatever is on the cursor. Returns nil when the
-- cursor holds something the palette can't fire.
local function SlotFromCursor()
    local cursorType, a, b, c = GetCursorInfo()
    if not cursorType then
        return nil
    end

    if cursorType == "spell" then
        -- Position 2 is the spellbook SLOT, not the spell -- Blizzard's own
        -- comment says so at SharedUIPanelTemplates.lua:1823, where it reads
        -- select(4, GetCursorInfo()) for the id. No fallback to position 2:
        -- that would store a slot number as a spellID and silently create a
        -- slot that casts the wrong thing.
        if type(c) ~= "number" then
            return nil
        end
        -- A lower rank than the highest known one is kept as that rank.
        if CludesUI.IS_FOREVER and TopRank(c) ~= c then
            return { kind = "spell", id = c, rankPinned = true }
        end
        return { kind = "spell", id = c }
    elseif cursorType == "item" then
        local itemId = tonumber(a)
        if not itemId then
            return nil
        end
        -- The Toy Box frame hands back cursorType "item", not "toy", so
        -- reclassify here to match what the search picker already stores.
        if PlayerHasToy(itemId) then
            return { kind = "toy", id = itemId }
        end
        return { kind = "item", id = itemId }
    elseif cursorType == "macro" then
        local name = GetMacroInfo(a)
        if not name then
            return nil
        end
        return { kind = "macro", id = a, name = name }
    elseif cursorType == "mount" then
        -- Position 2 is the mountID: Blizzard reads it exactly this way at
        -- SharedUIPanelTemplates.lua:1827. Guessing at other positions is
        -- unsafe here because display indices and mountIDs are both small
        -- integers, so a wrong guess resolves to a real but unrelated mount.
        local mountID = tonumber(a)
        if not mountID then
            return nil
        end
        local name, spellId = C_MountJournal.GetMountInfoByID(mountID)
        if not name then
            return nil
        end
        return { kind = "mount", id = mountID, spellID = spellId, name = name }
    elseif cursorType == "toy" then
        local itemId = tonumber(a)
        if not itemId then
            return nil
        end
        return { kind = "toy", id = itemId }
    elseif cursorType == "battlepet" then
        if not a then
            return nil
        end
        return { kind = "battlepet", guid = a }
    elseif cursorType == "outfit" then
        local details = mod.OutfitInfo(a)
        if not details then
            return nil
        end
        return {
            kind = "outfit",
            id = details.outfitID,
            name = details.name,
            icon = mod.OutfitIcon(details),
        }
    end

    return nil
end
mod.SlotFromCursor = SlotFromCursor

Inner.FireInsecure, Inner.ResolveAction, Inner.Rez = FireInsecure, ResolveAction, Rez
Inner.Hearth = Hearth
Inner.SlotCooldown, Inner.SlotCount, Inner.SlotDisplay = SlotCooldown, SlotCount, SlotDisplay
Inner.SlotUsability, Inner.USABILITY_TINT, Inner.usableMemo = SlotUsability, USABILITY_TINT, usableMemo
Inner.UsableSlots = UsableSlots
Inner.broken = false
