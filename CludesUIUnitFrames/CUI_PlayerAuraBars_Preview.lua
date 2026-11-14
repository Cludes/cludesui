if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_PlayerAuraBars_Preview.lua
--
--  The preview box of the options page.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._pabInternals
-- CludesUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ExpandFamily, PAB, PAB_FxListView = Inner.ExpandFamily, Inner.PAB, Inner.PAB_FxListView
local PabShapeBorderSize, PabShapedSize = Inner.PabShapeBorderSize, Inner.PabShapedSize
local BuildDispelColorMap, BuildStyle = Inner.BuildDispelColorMap, Inner.BuildStyle
local PV_DISPEL_ICON_ATLAS = Inner.PV_DISPEL_ICON_ATLAS
local PV_DISPEL_ICON_POINTS, ComputeGrid = Inner.PV_DISPEL_ICON_POINTS, Inner.ComputeGrid
local DefaultBuffsCfg, DefaultDebuffsCfg = Inner.DefaultBuffsCfg, Inner.DefaultDebuffsCfg
local CornerFor, SetMaybeRefreshPreview = Inner.CornerFor, Inner.SetMaybeRefreshPreview

-- Assigned below and handed to the earlier files (SetMaybeRefreshPreview).
local PAB_MaybeRefreshPreview

-------------------------------------------------------------------------------
-- Options-page preview box, embedded inside the bar's own detail page (NOT an
--  on-screen overlay at the bar's real position). Shows FAKE buffs/debuffs at the
--  bar's REAL configured icon size/grid (iconSize, iconsPerRow, maxRows, maxTotal,
--  via the same ComputeGrid the live bar uses), styled with the bar's real
--  BuildStyle/dispel-color output, so size/count/row-wrap/growth/spacing/border/
--  duration+stack formatting all preview live. No real aura data, and the real
--  bar/container is never touched. Debuffs cycle through fake spellIDs carrying real
--  dispel tokens (Magic/Curse/Poison/Disease/Bleed) so BuildDispelColorMap's border
--  coloring previews too.
--
--  Icons are hand-built Frame/Texture/FontString regions, not AK buttons: AK's
--  AuraContainer has no supported way to receive synthetic aura data.
-------------------------------------------------------------------------------

-- Class-appropriate fake buff pool: the preview draws from buffs the player's class
-- actually has, not a fixed generic list. Purely cosmetic (icon texture only, see
-- PreviewSpellIcon's fallback), so a wrong/renamed ID just shows the question-mark
-- icon. Keyed by the class FILE token (UnitClass's 2nd return, e.g. "PRIEST").
local CLASS_PREVIEW_BUFFS = {
    WARRIOR = { 6673, 97462, 871, 12975, 1719, 107574, 184364, 118038, 46924, 3411 },
    PALADIN = { 465, 6940, 1044, 1022, 31850, 86659, 642, 498, 31884, 105809 },
    HUNTER = { 186257, 288613, 19574, 186265, 109304, 5384, 34477, 264735, 193530, 90355 },
    ROGUE = { 13750, 1784, 5277, 31224, 1966, 2983, 13877, 121471, 185311, 1856 },
    PRIEST = { 21562, 17, 139, 33206, 47788, 586, 47585, 41635, 6346, 64843 },
    DEATHKNIGHT = { 48792, 48707, 55233, 49039, 51052, 42650, 47568, 194844, 194679, 81256 },
    SHAMAN = { 2825, 108271, 79206, 98008, 108281, 8178, 30823, 51490, 16188, 974 },
    MAGE = { 1459, 11426, 190319, 45438, 55342, 12042, 108978, 66, 80353, 12051 },
    WARLOCK = { 104773, 108416, 111400, 6789, 20707, 89808, 108503, 755, 6229, 5697 },
    MONK = { 115203, 122470, 116849, 122783, 115176, 116841, 124682, 116680, 101643, 322507 },
    DRUID = { 1126, 774, 22812, 61336, 102342, 106898, 29166, 33891, 192081, 108238 },
    DEMONHUNTER = { 191427, 198589, 196555, 203720, 196718, 258920, 217832, 195072, 191786, 188501 },
    EVOKER = { 364342, 374348, 355936, 357170, 363916, 358267, 370960, 360995, 359816, 370537 },
}

-- Fallback for an unrecognized class token (defensive only) or a missing entry.
local PREVIEW_BUFF_SPELLS = { 21562, 1459, 1126, 6673 } -- Fort, Arcane Intellect, Mark of the Wild, Battle Shout

-- Cross-class/consumable buffs for the "All Buffs" preview fill: All Buffs has no
-- finite spell list, and real raid buffs come from every class plus food/flask/
-- world-buff consumables, not just the player's class. Same 4 IDs as
-- CUI_RaidFrames_BuffManager2.lua's curated "consumables" preset (class="ALL"
-- entries), duplicated rather than cross-addon-referenced: RaidFrames' ns table is
-- not shared with this addon and may not be loaded.
local EXTRA_WORLD_PREVIEW_BUFFS = { 1236998, 1236616, 1239479, 1236994 }

-- Shuffles a fresh copy of `source` (Fisher-Yates), never mutating the source table.
local function ShuffleCopy(source)
    local result = {}
    for i = 1, #source do
        result[i] = source[i]
    end
    for i = #result, 2, -1 do
        local jdx = math.random(i)
        result[i], result[jdx] = result[jdx], result[i]
    end
    return result
end

-- Builds a freshly shuffled copy of the "All Buffs" preview pool. Called ONCE per
-- ns.PAB_BuildPreviewBox, not per live-apply refresh: the order is stashed on
-- activePreview and reused by every RenderPreviewIcons call for that box, so icons
-- keep their spell identity across slider ticks and only style/position/count changes.
--
-- Combines every class's CLASS_PREVIEW_BUFFS (13 x 10 = 130) plus
-- EXTRA_WORLD_PREVIEW_BUFFS' consumables (134 total), shuffled flat with NO class
-- priority (own-class-first is explicitly not wanted). 134 is far larger than any
-- configured grid (maxTotal defaults to 32), so the pool-exhausted fallback
-- effectively never triggers.
local function BuildBuffPreviewPool()
    local combined = {}
    for _, spells in pairs(CLASS_PREVIEW_BUFFS) do
        for i = 1, #spells do
            combined[#combined + 1] = spells[i]
        end
    end
    for i = 1, #EXTRA_WORLD_PREVIEW_BUFFS do
        combined[#combined + 1] = EXTRA_WORLD_PREVIEW_BUFFS[i]
    end
    if #combined == 0 then
        combined = PREVIEW_BUFF_SPELLS
    end
    return ShuffleCopy(combined)
end

-- Curated by hand (mostly recent Mythic+/dungeon trash debuffs): no verified debuff
-- catalog in this repo to source from, unlike CLASS_PREVIEW_BUFFS.
local PREVIEW_DEBUFF_SPELLS = {
    { id = 122, dispel = "Magic" }, -- Frost Nova
    { id = 702, dispel = "Curse" }, -- Curse of Weakness
    { id = 2823, dispel = "Poison" }, -- Deadly Poison
    { id = 55095, dispel = "Disease" }, -- Frost Fever
    { id = 772, dispel = "Bleed" }, -- Rend
    { id = 6788, dispel = nil }, -- Weakened Soul -- NOT dispellable, previews the plain base border color (no dispel-type override)
    -- Magic
    { id = 434083, dispel = "Magic" }, -- Lightning Bolt Volley
    { id = 426735, dispel = "Magic" }, -- Void Rift
    { id = 428161, dispel = "Magic" }, -- Frost Shock
    { id = 409465, dispel = "Magic" }, -- Astral Bomb
    { id = 397911, dispel = "Magic" }, -- Mystic Vapors
    { id = 385963, dispel = "Magic" }, -- Burnout
    { id = 387564, dispel = "Magic" }, -- Arcane Eruption
    { id = 372749, dispel = "Magic" }, -- Ice Cutter
    { id = 369365, dispel = "Magic" }, -- Curse of Stone (Magic)
    { id = 388777, dispel = "Magic" }, -- Arcane Vulnerability
    -- Curse
    { id = 381692, dispel = "Curse" }, -- Decaying Strength
    { id = 377488, dispel = "Curse" }, -- Cursed Blood
    { id = 384978, dispel = "Curse" }, -- Hextrick Totem
    { id = 328664, dispel = "Curse" }, -- Curse of Desolation
    { id = 322817, dispel = "Curse" }, -- Lingering Curse
    { id = 340288, dispel = "Curse" }, -- Curse of Obliteration
    { id = 426308, dispel = "Curse" }, -- Void Curse
    { id = 433443, dispel = "Curse" }, -- Shadow Curse
    { id = 373509, dispel = "Curse" }, -- Withering Curse
    { id = 375602, dispel = "Curse" }, -- Curse of Decay
    -- Disease
    { id = 373391, dispel = "Disease" }, -- Choking Rotcloud
    { id = 374389, dispel = "Disease" }, -- Rotting Sickness
    { id = 409492, dispel = "Disease" }, -- Diseased Bite
    { id = 322486, dispel = "Disease" }, -- Plague Rot
    { id = 321821, dispel = "Disease" }, -- Viral Contagion
    { id = 330868, dispel = "Disease" }, -- Festering Rot
    { id = 325552, dispel = "Disease" }, -- Necrotic Rot
    { id = 345245, dispel = "Disease" }, -- Putrid Bile
    { id = 426660, dispel = "Disease" }, -- Diseased Claws
    { id = 209858, dispel = "Disease" }, -- Necrotic Rot (different id, same name)
    -- Poison
    { id = 322358, dispel = "Poison" }, -- Venomous Spit
    { id = 324859, dispel = "Poison" }, -- Toxic Pool
    { id = 373614, dispel = "Poison" }, -- Decaying Venom
    { id = 385039, dispel = "Poison" }, -- Venom Strike
    { id = 376149, dispel = "Poison" }, -- Poisoned Spear
    { id = 384620, dispel = "Poison" }, -- Noxious Stench
    { id = 326092, dispel = "Poison" }, -- Poison Bolt
    { id = 257483, dispel = "Poison" }, -- Pile of Bones (Poison)
    { id = 381664, dispel = "Poison" }, -- Toxic Trap
    { id = 428019, dispel = "Poison" }, -- Poisoned Fang
    -- Bleed
    { id = 196497, dispel = "Bleed" }, -- Ravenous Leap
    { id = 257775, dispel = "Bleed" }, -- Gushing Wound
    { id = 381379, dispel = "Bleed" }, -- Jagged Bite
    { id = 373735, dispel = "Bleed" }, -- Bloody Bite
    { id = 391191, dispel = "Bleed" }, -- Savage Peck
    { id = 372718, dispel = "Bleed" }, -- Rending Slash
    { id = 385356, dispel = "Bleed" }, -- Tear Flesh
    { id = 328181, dispel = "Bleed" }, -- Jagged Quarrel
    { id = 381514, dispel = "Bleed" }, -- Serrated Strike
    { id = 424414, dispel = "Bleed" }, -- Brutal Rend
    -- No dispel type
    { id = 240559, dispel = nil }, -- Grievous Wound
    { id = 226512, dispel = nil }, -- Sanguine Ichor
    { id = 257908, dispel = nil }, -- Oozing Leftovers
    { id = 268008, dispel = nil }, -- Snake Charm
    { id = 274358, dispel = nil }, -- Rending Maul
    { id = 320788, dispel = nil }, -- Frozen Binds
    { id = 323043, dispel = nil }, -- Blood Barrier
    { id = 373429, dispel = nil }, -- Gash Frenzy
    { id = 424889, dispel = nil }, -- Brutal Strike
}
local PREVIEW_DURATIONS = { 8, 15, 23, 41, 5, 30, 12, 60, 3, 18 }
local PREVIEW_STACKS = { nil, 3, nil, nil, 2, nil, nil, 5, nil, 1 } -- a few icons show a fake stack count, rest hidden

-- Shuffled once per box build, same reasoning as BuildBuffPreviewPool: icons must
-- not swap identity on every slider tick.
local function BuildDebuffPreviewPool()
    return ShuffleCopy(PREVIEW_DEBUFF_SPELLS)
end

-- Memoized fake-icon texture lookup: C_Spell.GetSpellInfo's iconID, falls back to
-- the generic question-mark icon.
local previewIconCache = {}
local function PreviewSpellIcon(spellId)
    local cached = previewIconCache[spellId]
    if cached then
        return cached
    end
    local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
    local glyph = (details and details.iconID) or 134400
    previewIconCache[spellId] = glyph
    return glyph
end

-- Weapon-enchant preview cells, leading the bar exactly like the live ones
-- (the engine flows its item-enchantment group ahead of the aura groups).
-- Main hand + off hand only: those are the two slots reachable in current
-- retail content, even though the engine declares a third (ranged), as
-- Blizzard's own UpdateTemporaryEnchantmentBuffs does -- so a bar sized for
-- three enchants shows one placeholder cell of genuine spare capacity here,
-- which is what the live bar would do too.
--
-- Paints the player's OWN equipped weapon icons rather than an invented sample:
-- that is literally what the live buttons draw (PaintContent ->
-- GetInventoryItemTexture), so the preview matches the real thing instead of
-- approximating it. 134400 is the codebase's standard unknown-icon fallback,
-- used when a slot is empty.
local PREVIEW_ENCHANT_SLOTS = { INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17 }

-- Only slots actually holding a weapon get a cell. With a two-hander (or any
-- empty off hand) there is no second weapon to enchant, and drawing the
-- unknown-icon question mark there would advertise a cell the player can never
-- fill. An unarmed character still gets the single main-hand cell, so ticking
-- the option always previews as something rather than silently nothing.
-- Walked in REVERSE, mirroring the live group's sortDirection: the engine puts
-- the first element at the leading edge, so main hand ends up adjacent to the
-- aura run (see BuildEnchantSpec), off hand out at the corner.
local function PreviewEnchantSlots()
    local result = {}
    for i = #PREVIEW_ENCHANT_SLOTS, 1, -1 do
        local slotIndex = PREVIEW_ENCHANT_SLOTS[i]
        if GetInventoryItemTexture("player", slotIndex) then
            result[#result + 1] = slotIndex
        end
    end
    if #result == 0 then
        result[1] = PREVIEW_ENCHANT_SLOTS[1]
    end
    return result
end

-- Empty-slot art per weapon slot, for a character with nothing equipped:
-- Blizzard's own character-pane silhouette reads as "a weapon goes here", where
-- the generic unknown-icon question mark reads as "something is broken".
-- C_PaperDollInfo.GetInventorySlotInfo(slotName) -> id, textureName, checkRelic
-- (verified against Blizzard_UIPanels_Game/PaperDollFrame.lua, which uses the
-- same namespaced call).
local PREVIEW_ENCHANT_SLOT_NAMES =
    { [INVSLOT_MAINHAND or 16] = "MainHandSlot", [INVSLOT_OFFHAND or 17] = "SecondaryHandSlot" }
local function PreviewEnchantIcon(slotIndex)
    local tex = GetInventoryItemTexture("player", slotIndex)
    if tex then
        return tex
    end
    local name = PREVIEW_ENCHANT_SLOT_NAMES[slotIndex]
    if name and C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo then
        local _, slotTex = C_PaperDollInfo.GetInventorySlotInfo(name)
        if slotTex then
            return slotTex
        end
    end
    return 134400
end

-- Same memoization for the preview's "Name" sort simulation below.
local previewNameCache = {}
local function PreviewSpellName(spellId)
    local cached = previewNameCache[spellId]
    if cached then
        return cached
    end
    local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
    local name = (details and details.name) or ""
    previewNameCache[spellId] = name
    return name
end

-- Best-effort preview simulation of the 4 curated sort methods (Default/Expiration/
-- Name/ImportantOnly, see CUI_PlayerAuraBars_ManagerPages.lua's SORT_METHOD_VALUES).
-- Per Blizzard's AuraUtil.lua comparators: Expiration = ascending expirationTime,
-- Name = alphabetical spell name, ImportantOnly = `C_Spell.IsSpellImportant(spellId)`
-- first (a native per-spell flag, NOT dispel-type-based, applies equally to buffs).
-- Expiration/Name resolve to the native *Only comparators (see ResolveSortMethod), so
-- the live order is the named criterion alone, tie-broken on auraInstanceID.
-- `sortDirection == "Reverse"` flips every comparison INCLUDING under Default: whether
-- the engine's Default ordering respects direction is unknown, and reversing the
-- pool's own order beats ignoring the toggle. Never mutates `list`.
--
-- Second return: each output entry's ORIGINAL index in `list`. The fake duration and
-- stack text are keyed by that index (slot.pv in BuildPreviewSlots), so they travel WITH
-- their icon; keying them by display cell instead left the Expiration sort invisible.
local function SortPreviewList(entries, isBuff, conf)
    local method = conf.sortMethod or "Default"
    local reverse = conf.sortDirection == "Reverse"
    if method == "Default" then
        local result, src = {}, {}
        local num = #entries
        for i = 1, num do
            local from = reverse and (num - i + 1) or i
            result[i] = entries[from]
            src[i] = from
        end
        return result, src
    end

    local tagged = {}
    for i = 1, #entries do
        tagged[i] = { entry = entries[i], idx = i }
    end

    if method == "Expiration" then
        table.sort(tagged, function(a, b)
            local da = PREVIEW_DURATIONS[((a.idx - 1) % #PREVIEW_DURATIONS) + 1]
            local saved = PREVIEW_DURATIONS[((b.idx - 1) % #PREVIEW_DURATIONS) + 1]
            if da ~= saved then
                if reverse then
                    return da > saved
                end
                return da < saved
            end
            return a.idx < b.idx
        end)
    elseif method == "Name" then
        table.sort(tagged, function(a, b)
            local sa = isBuff and a.entry or a.entry.id
            local scrollBar = isBuff and b.entry or b.entry.id
            local na, nb = PreviewSpellName(sa), PreviewSpellName(scrollBar)
            if na ~= nb then
                if reverse then
                    return na > nb
                end
                return na < nb
            end
            return a.idx < b.idx
        end)
    elseif method == "ImportantOnly" then
        table.sort(tagged, function(a, b)
            local sa = isBuff and a.entry or a.entry.id
            local scrollBar = isBuff and b.entry or b.entry.id
            local ia = (C_Spell and C_Spell.IsSpellImportant and C_Spell.IsSpellImportant(sa)) and 0 or 1
            local ib = (C_Spell and C_Spell.IsSpellImportant and C_Spell.IsSpellImportant(scrollBar)) and 0
                or 1
            if ia ~= ib then
                if reverse then
                    return ia > ib
                end
                return ia < ib
            end
            return a.idx < b.idx
        end)
    end

    local result, src = {}, {}
    for i = 1, #tagged do
        result[i] = tagged[i].entry
        src[i] = tagged[i].idx
    end
    return result, src
end

-- Which bar-detail pane owns the visible preview box (kind: "buff"/"debuff", id:
-- "default" or a custom bar id), plus that box's icon pool and the fontPath it was
-- built with, so a live-apply hook can re-render in place without rebuilding the
-- detail pane. Reset to a fresh box on every ns.PAB_BuildPreviewBox call, since the
-- owning pane is always torn down and rebuilt on structural changes (switching bars,
-- add/rename/delete).
local activePreview

-- Stable random preview swipe seeds (fraction remaining, 0.2-0.9), keyed by slot
-- index: generated once and reused so re-renders never reshuffle frozen swipe positions.
local pvCDSeeds = {}
local function GetPvCDSeed(i)
    local val = pvCDSeeds[i]
    if not val then
        val = 0.2 + math.random() * 0.7
        pvCDSeeds[i] = val
    end
    return val
end

-- Layer order matches the live bar exactly (AK's own ApplyStyleToRegions): icon
-- texture (btn, ARTWORK) below border (child frame, level+1) below duration/stack
-- text (textHost, child frame, level+2, ABOVE the border).
local function CreatePreviewIcon(boxFrame)
    -- Options preview only: the options frame pool (CludesUI_FramePool.lua)
    -- hands the box's next render these frames back reset to new.
    local Pool = CludesUI._Pool
    local CreateFrame = Pool.CreateFrame
    local button = CreateFrame("Frame", nil, boxFrame)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    -- "Nothing configured" placeholder: a red X over the icon's flat grey fill,
    -- shown instead of a fake spell icon when the bar's real config would show zero
    -- buffs (Show All Buffs off, no Filters/Extra Spells resolved) -- see
    -- RenderPreviewIcons' noneConfigured check. Reuses the existing close/X media icon.
    button.placeholder = button:CreateTexture(nil, "OVERLAY")
    button.placeholder:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
    button.placeholder:SetVertexColor(1, 0.2, 0.2, 1)
    button.placeholder:Hide()
    -- Duration-swipe preview: same CooldownFrameTemplate child the live bar's
    -- buttons carry. Created hidden; armed per refresh from the bar's Show Duration
    -- Swipe setting. Created BEFORE the border/text hosts so it renders above the
    -- icon but below both (live ladder).
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()
    button.cooldown:SetDrawEdge(false)
    button.cooldown:SetHideCountdownNumbers(true)
    button.cooldown:Hide()
    -- A cooldown the pool dressed before keeps the swipe texture an earlier
    -- dress gave it (the engine's reset keeps a cooldown's settings, and no
    -- getter reads that one back): the first render of this dress applies
    -- the bar's shape or the plain swipe either way. A new cooldown keeps its
    -- template swipe untouched.
    local cdGen = Pool.Gen and Pool.Gen(button.cooldown)
    if cdGen and cdGen > 1 then
        button._cdShapeApplied = false
    end
    button.border = CreateFrame("Frame", nil, button)
    -- The border frame is its own secret-safe border state (as the boss preview's
    -- aura border): a pooled frame's reset wipes these keys, so a pixel-grid
    -- change never repaints an earlier dress's look over this one.
    button.borderState = button.border
    -- Dispel-type icon host: a child frame created after the cooldown and the border,
    -- so the icon draws above the swipe and the border like the live button's holder.
    -- A texture on the button itself sits under every child frame whatever its layer,
    -- so the frozen preview swipe covered it.
    button.typeHost = CreateFrame("Frame", nil, button)
    button.typeHost:SetAllPoints()
    -- Plain preview region, not a real AuraKit button -- masking is unguarded here.
    button.shapeMask = button:CreateMaskTexture()
    button.shapeMask:Hide()
    button.textHost = CreateFrame("Frame", nil, button)
    button.duration = button.textHost:CreateFontString(nil, "OVERLAY")
    button.stack = button.textHost:CreateFontString(nil, "OVERLAY")
    return button
end

-- Resolves a bar's live cfg + polarity from its (kind,id) identity, via the same
-- lookups every other engine-side path uses.
local function ResolvePreviewCfg(kindOf, ident)
    local s = PAB()
    if not s then
        return nil
    end
    if ident == "default" then
        local isBuff = kindOf == "buff"
        return (isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)), isBuff
    elseif kindOf == "buff" then
        return mod.PAB_GetCustomBuffBar(ident), true
    else
        return mod.PAB_GetCustomDebuffBar(ident), false
    end
end

-- Options-panel "pixel perfect" compensation: the options window runs at effective
-- scale baseScale*userScale (CludesUI.GetPopupScale()), while real PAB bars are
-- parented straight to UIParent with no extra scale, so identical iconSize/padding/
-- border/text-size NUMBERS render visibly SMALLER in the panel whenever that scale is
-- below 1 (the common case). Do NOT SetScale the preview box itself -- that desyncs it
-- from the sy layout accounting placing widgets below it. Instead every size-affecting
-- cfg field is pre-multiplied by 1/GetPopupScale() before reaching
-- BuildStyle/ComputeGrid, so the ENTIRE preview inflates by exactly the panel's scale
-- factor and lands at the same TRUE on-screen size as the live bar. WoW's own UI Scale
-- cancels out algebraically (UIParent's effective scale multiplies both equally), so
-- only the panel's OWN extra SetScale factor matters.
local function PreviewScaleFactor()
    local s = (CludesUI.GetPopupScale()) or 1
    if not s or s <= 0 then
        return 1
    end
    return 1 / s
end

-- Duplicates BuildStyle's own `or <default>` fallbacks for every scaled field
-- (32/5/1/11/0/11/0) since a size can't be scaled without first resolving what
-- "unset" means -- keep in sync if BuildStyle's defaults change. Non-size fields
-- (growDirection, iconsPerRow/maxRows/maxTotal, dispel colors, ...) pass through.
local function ApplyPreviewScale(conf, comp)
    if comp == 1 then
        return conf
    end
    local result = {}
    for key, val in pairs(conf) do
        result[key] = val
    end
    result.iconSize = (conf.iconSize or 32) * comp
    result.padding = (conf.padding or 5) * comp
    result.rowSpacing = conf.rowSpacing and (conf.rowSpacing * comp) or nil
    result.borderSize = (conf.borderSize or 1) * comp
    -- Textured borders use a discrete 0-4 lookup for edge art. Preserve that raw
    -- key and scale the resolved edge/offset geometry separately; Solid continues
    -- to use the compensated borderSize above.
    result.borderTextureSizeOverride = conf.borderSize or 1
    result.borderTextureScaleOverride = comp
    -- PabShapeBorderSize is keyed by the raw 0-4 level, so it must run BEFORE scaling
    -- (unlike out.borderSize above) -- resolve the level, then scale the result,
    -- mirroring iconSize's own scale-after-resolve treatment. BuildStyle prefers this
    -- over recomputing from the already-scaled out.borderSize when present.
    result.shapeBorderSizeOverride = PabShapeBorderSize(conf.borderSize or 1) * comp
    -- The exact size (borderSizePx) pairs with the RAW step and texture, so it is
    -- resolved here, before the compensation above, and handed to BuildStyle as
    -- borderPxOverride. Solid scales like borderSize; a textured edge stays raw
    -- because the eight-slice draw scales it by borderTextureScaleOverride itself.
    local rawTex = conf.borderTexture
    local rawPx = CludesUI.BorderPx(conf.borderSizePx, conf.borderSize or 1, rawTex)
    if rawPx then
        local textured = rawTex and rawTex ~= "" and rawTex ~= "solid"
        result.borderPxOverride = textured and rawPx or (rawPx * comp)
    end
    result.durationTextSize = (conf.durationTextSize or 11) * comp
    result.durationOffsetX = (conf.durationOffsetX or 0) * comp
    result.durationOffsetY = (conf.durationOffsetY or 0) * comp
    result.dispelIconSize = (conf.dispelIconSize or 16) * comp
    result.dispelIconOffsetX = (conf.dispelIconOffsetX or 0) * comp
    result.dispelIconOffsetY = (conf.dispelIconOffsetY or 0) * comp
    result.stackTextSize = (conf.stackTextSize or 11) * comp
    result.stackOffsetX = (conf.stackOffsetX or 0) * comp
    result.stackOffsetY = (conf.stackOffsetY or 0) * comp
    -- Icon Effects Per-Filter Size overrides need the same panel-scale compensation
    -- as iconSize: a per-block shallow copy (never mutating the real saved fxList or
    -- its filters/borderColor sub-tables) with only `.size` rescaled, so both the
    -- preview's box footprint (ComputeGrid's MaxIconSizeFor) and the fake-icon
    -- SetSize read the right pixel value.
    if conf.fxList then
        local scaledFx = {}
        for i = 1, #conf.fxList do
            local e = conf.fxList[i]
            local se = {}
            for key, val in pairs(e) do
                se[key] = val
            end
            if se.size then
                se.size = se.size * comp
            end
            scaledFx[i] = se
        end
        result.fxList = scaledFx
    end
    return result
end

-- Preview area height budget: Up/Down growth with several icons-per-column makes the
-- box very tall very fast, pushing the rest of the options page down. Applied as an
-- EXTRA proportional shrink on top of the panel-zoom compensation, combined into ONE
-- factor so iconSize/padding/rowSpacing/etc are scaled once, not twice. Only ever
-- shrinks (extra <= 1); horizontal and short vertical bars are unaffected.
local MAX_PREVIEW_CONTENT_HEIGHT = 330

local function ScaledPreviewCfg(conf, isBuff)
    local comp = PreviewScaleFactor()
    local extra = 1
    if isBuff ~= nil then
        local probe = ApplyPreviewScale(conf, comp)
        local grid = ComputeGrid(isBuff, probe)
        if grid.height > MAX_PREVIEW_CONTENT_HEIGHT then
            extra = MAX_PREVIEW_CONTENT_HEIGHT / grid.height
        end
    end
    return ApplyPreviewScale(conf, comp * extra)
end

-- Renders (or re-renders in place) the fake icon grid using the bar's CURRENT cfg --
-- safe on every live slider tick, only touches plain addon-owned
-- Frame/Texture/FontString regions, never the real bar. Row/column math mirrors
-- ComputeGrid/BuildContainerSpec's own corner-anchored flow layout so the preview
-- wraps exactly like the live bar.
local function HasAnyTrue(map)
    if not map then
        return false
    end
    for _, val in pairs(map) do
        if val then
            return true
        end
    end
    return false
end

-- True when the FILLER portion (whatever is left after real resolved spells, see
-- BuildPreviewSlots) should show fake example icons rather than empty placeholders.
-- Buffs: ONLY All Buffs justifies fake filler, since it has no finite spell list --
-- Filters/Extra Spells resolve to a concrete finite set (ns.PAB_ResolveSpells, drawn
-- as real icons), so anything beyond that count is genuinely empty capacity, not
-- content pretending to exist. Debuffs have no per-spell resolution for class filters
-- (aura filter string/category tokens), so Show All Debuffs OR any Base Filter class
-- justifies fake filler (mirrors BuildChain's includeCatchAll condition); debuffs CAN
-- show truly nothing.
local function HasFillerSource(isBuff, conf)
    if isBuff then
        return conf.showAllBuffs ~= false or conf.hasDuration == true
    end
    -- Match All picks that can never match together render nothing.
    if mod.PAB_DebuffMatchEmpty(conf) then
        return false
    end
    return conf.showAllDebuffs ~= false or conf.hasDuration == true or HasAnyTrue(conf.classFilters)
end

-- BuildPreviewSlots (below) builds one descriptor per icon slot (length `count`).
-- Buffs: the bar's REAL resolved spells (ns.PAB_ResolveSpells -- Filters' enabled
-- spells + Extra Spells, deliberately NOT All Buffs, which has no finite list) take
-- the LEADING slots as {kind="extra", spellID=} with their own real icons; a Filter
-- selection and an Extra Spell are equally "real content" to the preview. Whatever is
-- left is {kind="fake", entry=} when HasFillerSource is true, else
-- {kind="placeholder"} -- e.g. 4 resolved spells in room for 8 with All Buffs off
-- renders 4 real + 4 placeholders, never 4 fake. Debuffs have no per-spell
-- resolution, so every slot there is fake-or-placeholder.
--
-- DedupeByIcon: ns.PAB_ResolveSpells dedupes by SPELL ID, but a filter's `alts`
-- (rank/alternate ids for the same visual buff) are DIFFERENT ids sharing the SAME
-- icon, rendering it twice. Dedupe the preview's real-spell list by ICON TEXTURE,
-- keeping the first occurrence (lowest spell ID, ResolveSpells sorts numerically).
-- Preview-only: the real bar shows active aura instances, not an enumeration of
-- possible spell IDs.
local function DedupeByIcon(ids)
    local seenIcons, result = {}, {}
    for i = 1, #ids do
        local glyph = PreviewSpellIcon(ids[i])
        if not seenIcons[glyph] then
            seenIcons[glyph] = true
            result[#result + 1] = ids[i]
        end
    end
    return result
end

-- ns.PAB_ResolveSpells unions every selected Filter's + Extra Spells' ids into ONE
-- numerically sorted set. Truncating that to the first `count` would let whichever
-- Filter holds the lowest-numbered spells win every visible slot while other Filters
-- never appear. Instead interleave round-robin ACROSS sources (each selected Filter is
-- a source, Extra Spells is one more), so truncation samples a bit of everything.
-- Deterministic (no math.random) on purpose: unlike the fake pools this must NOT
-- reshuffle on every live-apply refresh.
local function BuildMixedRealSpells(conf)
    local sources = {}
    -- Broad modes render through the catch-all, so show-lane real icons only exist in
    -- add mode; the hide lane (cfg.negFilters) drops its spells from these sources the
    -- same way the live spells group resolves (PAB_ResolveSpells) -- Extra Spells are
    -- a separate source below and win over the hide lane there too.
    if conf.filters and conf.showAllBuffs == false and conf.hasDuration ~= true then
        local negSet
        if conf.negFilters then
            for filterId in pairs(conf.negFilters) do
                local nf = mod.PAB_GetFilter and mod.PAB_GetFilter(filterId)
                if nf and nf.spells then
                    for ident, enabled in pairs(nf.spells) do
                        if enabled and not mod.PAB_OtherClientSpell(nf, ident) then
                            negSet = negSet or {}
                            negSet[ident] = true
                            ExpandFamily(negSet, ident, nf.spells)
                        end
                    end
                end
            end
        end
        local allFilters = mod.PAB_Filters and mod.PAB_Filters()
        if allFilters then
            for i = 1, #allFilters do
                local f = allFilters[i]
                if conf.filters[f.id] then
                    local ids = {}
                    for ident, enabled in pairs(f.spells) do
                        if
                            enabled
                            and not (negSet and negSet[ident])
                            and not mod.PAB_OtherClientSpell(f, ident)
                        then
                            ids[#ids + 1] = ident
                        end
                    end
                    if #ids > 0 then
                        table.sort(ids)
                        sources[#sources + 1] = ids
                    end
                end
            end
        end
    end
    if conf.spells and #conf.spells > 0 then
        local extra = {}
        for i = 1, #conf.spells do
            extra[i] = conf.spells[i]
        end
        sources[#sources + 1] = extra
    end

    local result = {}
    local position = 1
    while true do
        local addedAny = false
        for s = 1, #sources do
            local ident = sources[s][position]
            if ident then
                result[#result + 1] = ident
                addedAny = true
            end
        end
        if not addedAny then
            break
        end
        position = position + 1
    end
    return result
end

local function BuildPreviewSlots(isBuff, conf, entries, listLen, count)
    local hasFiller = HasFillerSource(isBuff, conf)
    -- Sort Method/Direction must apply to the REAL extra icons too, not just the fake
    -- filler pool: with All Buffs off the content is mostly/only these real slots, so
    -- skipping them leaves the sort controls looking dead.
    --
    -- SELECT before SORT: with more resolved+deduped spells than icon slots, sorting
    -- the FULL list and truncating afterward puts a DIFFERENT subset into the
    -- surviving first `count` per sort, so changing sort would swap WHICH spells
    -- appear, not just their order. Truncate to `count` on the stable, sort-
    -- independent mixed order FIRST, then sort that fixed selection for display.
    -- Weapon enchants take the LEADING cells and are never sorted into the aura
    -- content: they are not auras. They do take a cell each, though: Max Icons
    -- counts the whole bar, so the aura slots below are what is left after them.
    local numEnch, enchSlots = 0, nil
    if isBuff and mod.PAB_EnchantsOn(conf) then
        enchSlots = PreviewEnchantSlots()
        numEnch = #enchSlots
    end
    -- Both modes render exactly `count` cells, which is what Max Icons promises:
    -- the enchant cells lead, the aura slots take the rest. The enchants-only
    -- bar keeps its leftovers as placeholders on purpose -- they are what
    -- explains where the bar's width comes from.
    --
    -- The live bar counts the enchants ACTUALLY up (BuffAuraMax); the preview
    -- counts the weapon slots that could carry one, so an unenchanted character
    -- still sees the shape the option produces.
    local avail = math.max(0, count - numEnch)

    local mixed = isBuff and DedupeByIcon(BuildMixedRealSpells(conf)) or nil
    local extraIDs, extraSrc
    if mixed then
        local numSelected = math.min(#mixed, avail)
        local selected = {}
        for i = 1, numSelected do
            selected[i] = mixed[i]
        end
        extraIDs, extraSrc = SortPreviewList(selected, isBuff, conf)
    end
    local numExtra = extraIDs and #extraIDs or 0
    local numFiller = avail - numExtra
    local slots = {}
    for i = 1, numEnch do
        slots[i] = { kind = "enchant", slot = enchSlots[i] }
    end
    -- pv: the icon's fake duration/stack index, the same one SortPreviewList sorted it
    -- by -- so the displayed numbers follow the chosen sort.
    for i = 1, numExtra do
        slots[numEnch + i] = { kind = "extra", spellID = extraIDs[i], pv = extraSrc[i] }
    end
    if numFiller > 0 then
        if hasFiller then
            -- Buff subtract mode (broad mode + hide-lane filters): the filler pool
            -- drops every subtracted spell, matching what the live catch-all's
            -- excludeSpellIDs removes.
            local subSet
            if isBuff and (conf.showAllBuffs ~= false or conf.hasDuration == true) and conf.negFilters then
                for filterId in pairs(conf.negFilters) do
                    local f = mod.PAB_GetFilter and mod.PAB_GetFilter(filterId)
                    if f and f.spells then
                        for ident, enabled in pairs(f.spells) do
                            if enabled and not mod.PAB_OtherClientSpell(f, ident) then
                                subSet = subSet or {}
                                subSet[ident] = true
                                ExpandFamily(subSet, ident, f.spells)
                            end
                        end
                    end
                end
            end
            -- Same select-before-sort fix as the real extra icons above, applied to
            -- All Buffs' fake filler too: select the fixed filler slice from `list`
            -- (stable, shuffled once per box build, NOT sorted) first, then sort only
            -- that selection -- so Sort Method/Direction reorders the SAME fake icons
            -- already showing instead of pulling different ones from the pool.
            local fillerSelected = {}
            if subSet then
                local num = 0
                for scan = 1, listLen do
                    if num >= numFiller then
                        break
                    end
                    local e = entries[scan]
                    if not subSet[e] then
                        num = num + 1
                        fillerSelected[num] = e
                    end
                end
            else
                for i = 1, numFiller do
                    fillerSelected[i] = entries[((i - 1) % listLen) + 1]
                end
            end
            local fillerSrc
            fillerSelected, fillerSrc = SortPreviewList(fillerSelected, isBuff, conf)
            for i = 1, numFiller do
                local e = fillerSelected[i]
                slots[numEnch + numExtra + i] = e and { kind = "fake", entry = e, pv = fillerSrc[i] }
                    or { kind = "placeholder" }
            end
        else
            for i = 1, numFiller do
                slots[numEnch + numExtra + i] = { kind = "placeholder" }
            end
        end
    end
    return slots, numEnch
end

-- Icon Effects Per-Filter preview: applies a matched fx block's Glow/Border to a
-- fake preview icon. Plain addon-owned frames (CreatePreviewIcon), so hosts are
-- created lazily; the glow renders on the engine path anyway so the preview shows
-- exactly what the live aura buttons can. `e` is nil when no active fx block
-- matches this icon's category (or for buff/placeholder slots), clearing any fx
-- left over from a previous render of this reused frame.
mod.PAB_PREVIEW_GLOW_SPEC = {}
local function ApplyPreviewFx(button, e)
    local CreateFrame = CludesUI._Pool.CreateFrame -- options preview only (the pool)
    local Glows = CludesUI.Glows
    local specInfo = e and Glows.SpecFromPrefix(mod.PAB_PREVIEW_GLOW_SPEC, e, "glow", 1.0, 0.776, 0.376)
    local gov = button.fxGlow
    if specInfo then
        if not gov then
            gov = CreateFrame("Frame", nil, button)
            gov:SetAllPoints(button)
            gov:SetFrameLevel(button.border:GetFrameLevel() + 2)
            gov:EnableMouse(false)
            button.fxGlow = gov
        end
        gov:Show()
        local sz = button:GetWidth() or 18
        Glows.StartSpecGlow(gov, specInfo, sz, button:GetHeight() or sz, "engine", Glows.PANEL_EXTRA)
    elseif gov then
        if gov._cuiGlowActive then
            Glows.StopGlow(gov)
        end
        gov:Hide()
    end

    local Pix = CludesUI.PP
    local bSize = (e and e.borderSize) or 0
    if bSize > 0 and Pix then
        local hostRegion = button.fxBorder
        if not hostRegion then
            hostRegion = CreateFrame("Frame", nil, button)
            hostRegion:SetAllPoints(button)
            hostRegion:SetFrameLevel(button.border:GetFrameLevel() + 1)
            hostRegion:EnableMouse(false)
            Pix.CreateBorder(hostRegion, 0, 0, 0, 1, 1)
            button.fxBorder = hostRegion
        end
        local bc = e.borderColor or { r = 0, g = 0, b = 0 }
        Pix.UpdateBorder(hostRegion, bSize, bc.r or 0, bc.g or 0, bc.b or 0, 1)
        hostRegion:Show()
    elseif button.fxBorder then
        button.fxBorder:Hide()
    end

    -- Size override is deliberately NOT applied here: it feeds RenderPreviewIcons'
    -- per-icon flow packing (slotSize/colOffset/rowYOffset), which must know each
    -- icon's footprint BEFORE positioning any of them.
end

-- `pool` is the box's own stable, pre-shuffled fake-icon pool (shuffled once per box
-- build for BOTH polarities, see BuildBuffPreviewPool/BuildDebuffPreviewPool).
local function RenderPreviewIcons(boxFrame, icons, isBuff, conf, fontFile, pool)
    conf = ScaledPreviewCfg(conf, isBuff)
    local look = BuildStyle(isBuff, conf)
    local dcMap = (not isBuff) and BuildDispelColorMap(conf) or nil
    local grid = ComputeGrid(isBuff, conf)

    -- The box itself (and the header darken band/divider below it, see
    -- ns.PAB_BuildPreviewBox) is FIXED at its build-time size: divider/box stay put,
    -- only the CONTENT changes on a live settings edit. Icons are instead centered as
    -- a BLOCK inside the box's current (unchanging) width/height, using
    -- box:GetCenter()-relative offsets rather than anchoring to one of the box's own
    -- corners -- growDirection still decides which edge of that centered block fills
    -- first (matches the live bar's own fill order), it just doesn't move the
    -- box/divider while doing it.
    local growDir = conf.growDirection or "LEFT"
    local wrapDir = conf.iconWrapDirection or "LEFT"
    local centeredVertical = growDir == "CENTER_VERTICAL"
    local vertical = (growDir == "UP" or growDir == "DOWN" or centeredVertical)
    local corner = CornerFor(growDir, wrapDir)
    local pad = conf.padding or 5
    local rowGap = conf.rowSpacing or 12
    local iconSize = conf.iconSize or 32
    local cols = math.max(1, conf.iconsPerRow or (isBuff and 11 or 8))
    local count = grid.effectiveMax
    -- NOT sorted here (same "select before sort" reasoning as the real extra icons
    -- below): `list` is much larger than `count` (fake pools are 134/66 entries), so
    -- sorting the WHOLE pool before BuildPreviewSlots selects its filler slice would
    -- let a sort change pull a DIFFERENT subset of fake icons into view. BuildPreviewSlots
    -- selects the fixed filler slice from this stable, shuffled-once order FIRST, sorts after.
    local entries = (pool and #pool > 0 and pool) or (isBuff and PREVIEW_BUFF_SPELLS or PREVIEW_DEBUFF_SPELLS)
    local listLen = #entries
    -- Enchant cells are the leading `slots` entries and carry their own kind,
    -- so the packing below needs no separate count of them.
    local slots = BuildPreviewSlots(isBuff, conf, entries, listLen, count)
    -- Enchants are additive leading cells, so the rendered total exceeds the
    -- bar's aura capacity by however many are showing.
    local sum = #slots

    -- Icon Effects Per-Filter preview (debuffs only): deliberately NOT tied to the
    -- bar's own active Base Filters/Show All Debuffs state -- requiring a matching
    -- Base Filter meant the preview usually showed nothing, since the two dropdowns
    -- serve different purposes and aren't meant to be set identically. Instead every
    -- ACTIVE fx block claims 1-2 fake icon slots outright regardless of which
    -- categories are actually enabled -- a "here's what this effect looks like"
    -- demonstration, not a claim these icons represent that category on a real bar
    -- (the fake pool has no Blizzard boss/role/priority flags to support that anyway).
    local fxBySlot
    if not isBuff then
        local fxListView = PAB_FxListView(conf.fxList)
        if fxListView and #fxListView > 0 then
            local fakeIdx = {}
            for i = 1, #slots do
                if slots[i].kind == "fake" then
                    fakeIdx[#fakeIdx + 1] = i
                end
            end
            local nFake = #fakeIdx
            if nFake > 0 then
                fxBySlot = {}
                for bi = 1, #fxListView do
                    local perBlock = math.min(2, nFake)
                    for key = 1, perBlock do
                        local place = ((bi - 1) * 2 + (key - 1)) % nFake + 1
                        fxBySlot[fakeIdx[place]] = fxListView[bi]
                    end
                end
            end
        end
    end

    -- Enchant cells share the line with the auras (one engine flow, see the
    -- packing block below), so they count toward the wrap.
    local rowList = math.max(1, math.ceil(sum / cols))

    -- Real per-icon flow packing: each slot's OWN actual render size (its fx Size
    -- override, or the bar's base iconSize) drives its own footprint directly, so
    -- spacing between normal icons stays tight and only an oversized icon's immediate
    -- neighbors get pushed out -- true flow-layout behavior rather than a uniform
    -- worst-case cell grid (which left too much gap around every normal icon). Shape-
    -- expanded the same as the live bar's own button SetSize (BuildStyle/
    -- EnsurePabSizedStyle), so preview spacing/footprint matches the real bar.
    local slotSize, slotHeight = {}, conf.iconShape == "cropped" and {} or nil
    for i = 1, sum do
        local e = fxBySlot and fxBySlot[i]
        local sz = e and tonumber(e.size)
        slotSize[i] = PabShapedSize((sz and sz > 0) and sz or iconSize, conf.iconShape)
        if slotHeight then
            slotHeight[i] = mod.PAB_CroppedHeight(slotSize[i], conf)
        end
    end

    local rowWidth, rowHeight, colOffset, rowYOffset = {}, {}, {}, {}
    do
        -- ONE uniform flow, enchants first: the engine lays the weapon-enchant
        -- frames out as their own layout group placed BEFORE the aura groups
        -- on the same container, so they lead row 0 as plain members of the
        -- line and row 2 wraps back to the bar's own edge, no per-row indent.
        -- Their cells come out of the aura cap, so the box always fits.
        local runningX, runningY = {}, 0
        for r = 0, rowList - 1 do
            runningX[r] = 0
        end
        for i = 1, sum do
            local r = math.floor((i - 1) / cols)
            colOffset[i] = runningX[r] or 0
            runningX[r] = (runningX[r] or 0)
                + (vertical and slotHeight and slotHeight[i] or slotSize[i])
                + pad
            rowHeight[r] =
                math.max(rowHeight[r] or 0, (not vertical) and slotHeight and slotHeight[i] or slotSize[i])
        end
        for r = 0, rowList - 1 do
            rowWidth[r] = math.max(0, runningX[r] - pad) -- drop the trailing gap
        end
        for r = 0, rowList - 1 do
            rowYOffset[r] = runningY
            runningY = runningY + (rowHeight[r] or 0) + rowGap
        end
    end
    -- blockW/blockH are generic axis extents: "within-line" (rowWidth, primary/fill
    -- axis) and "across-lines" (wrap axis) -- screen X/Y only for horizontal growth.
    -- Vertical growth (Up/Down) swaps which maps to X vs Y below.
    local blockW = 0
    for r = 0, rowList - 1 do
        blockW = math.max(blockW, rowWidth[r] or 0)
    end
    local blockH = math.max(0, (rowYOffset[rowList - 1] or 0) + (rowHeight[rowList - 1] or 0))
    local halfPrimary, halfCross = blockW / 2, blockH / 2
    local growUp = (growDir == "UP")
    local wrapRight = (wrapDir == "RIGHT")
    -- Read the wrap-up state off the CORNER, not off wrapDir: CornerFor only emits a
    -- BOTTOM component where an Up wrap is actually in effect, so the preview cannot
    -- drift from the real bars or inherit a stale wrap in the centered modes.
    local wrapUp = (corner == "BOTTOMLEFT" or corner == "BOTTOMRIGHT")

    for i = 1, math.max(sum, #icons) do
        if i <= sum then
            local button = icons[i]
            if not button then
                button = CreatePreviewIcon(boxFrame)
                icons[i] = button
            end

            local rowFrame = math.floor((i - 1) / cols)
            local withinLineStep = colOffset[i]
            local acrossLinesStep = rowYOffset[rowFrame]
            -- btn's own anchor point is `corner` (matching growDirection/
            -- iconWrapDirection), placed at an offset from the box's CENTER -- see the
            -- block-centering comment above `local rows = ...`. Vertical growth
            -- swaps which step drives X vs Y: the within-line step (icons
            -- stacking inside one column) becomes Y, the across-lines step (columns
            -- wrapping sideways) becomes X -- mirrors the corner/growthH/growthV swap
            -- in CornerFor/BuildContainerSpec used by the real (non-preview) bars.
            local btnX, btnY
            if centeredVertical then
                btnY = halfPrimary - withinLineStep - (slotHeight and slotHeight[i] or slotSize[i]) / 2
                btnX = -halfCross + acrossLinesStep + slotSize[i] / 2
            elseif vertical then
                btnY = growUp and (-halfPrimary + withinLineStep) or (halfPrimary - withinLineStep)
                btnX = wrapRight and (-halfCross + acrossLinesStep) or (halfCross - acrossLinesStep)
            else
                btnY = wrapUp and (-halfCross + acrossLinesStep) or (halfCross - acrossLinesStep)
                btnX = (corner == "TOPRIGHT" or corner == "BOTTOMRIGHT") and (halfPrimary - withinLineStep)
                    or (-halfPrimary + withinLineStep)
            end
            button:ClearAllPoints()
            button:SetPoint(centeredVertical and "CENTER" or corner, boxFrame, "CENTER", btnX, btnY)
            button:SetSize(slotSize[i], slotHeight and slotHeight[i] or slotSize[i])

            local slotIndex = slots[i]
            local dispel

            if slotIndex.kind == "placeholder" then
                -- Flat grey box + centered red X (see CreatePreviewIcon) instead of a
                -- fake spell icon -- nothing would actually render on the real bar
                -- here. Border still draws -- only icon texture and duration/stack
                -- text are placeholder-specific.
                button.icon:SetTexture(nil)
                button.icon:SetColorTexture(0.16, 0.16, 0.16, 1)
                button.placeholder:ClearAllPoints()
                local inset = iconSize * 0.2
                button.placeholder:SetPoint("TOPLEFT", button.icon, "TOPLEFT", inset, -inset)
                button.placeholder:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", -inset, inset)
                button.placeholder:Show()
                button.textHost:Hide()
            else
                button.placeholder:Hide()
                button.textHost:Show()

                if slotIndex.kind == "enchant" then
                    -- Weapon enchant: an ITEM texture, not a spell icon -- the
                    -- live buttons paint the equipped weapon the same way.
                    button.icon:SetTexture(PreviewEnchantIcon(slotIndex.slot))
                else
                    local spellId
                    if slotIndex.kind == "extra" then
                        -- Real Extra Spell: always its own actual icon, never folded into
                        -- the fake cycling pool.
                        spellId = slotIndex.spellID
                    else -- "fake"
                        local record = slotIndex.entry
                        spellId = isBuff and record or record.id
                        dispel = (not isBuff) and record.dispel or nil
                    end
                    button.icon:SetTexture(PreviewSpellIcon(spellId))
                end
                -- The live icons' texcoords, the shaped fill included (AuraKit).
                button.icon:SetTexCoord(CludesUI.AuraKit.IconTexCoord(look))
            end

            -- Mirrors CludesUI_AuraKit.lua's ApplyStyleToRegions, unguarded (plain regions).
            local shapeActive = look.iconShape and look.iconShape ~= "none" and look.shapeMaskPath
            if shapeActive then
                button.shapeMask:SetTexture(
                    look.shapeMaskPath,
                    "CLAMPTOBLACKADDITIVE",
                    "CLAMPTOBLACKADDITIVE"
                )
                button.shapeMask:SetAllPoints(button)
                button.shapeMask:Show()
                if button._shapeApplied ~= look.iconShape then
                    pcall(button.icon.RemoveMaskTexture, button.icon, button.shapeMask)
                    button.icon:AddMaskTexture(button.shapeMask)
                    button._shapeApplied = look.iconShape
                end
            else
                if button._shapeApplied then
                    pcall(button.icon.RemoveMaskTexture, button.icon, button.shapeMask)
                    button._shapeApplied = nil
                end
                button.shapeMask:Hide()
            end

            button.border:SetAllPoints(shapeActive and button or button.icon)
            button.border:SetFrameLevel(
                look.border and look.border.behind and math.max(0, button:GetFrameLevel() - 1)
                    or (button:GetFrameLevel() + 1)
            )
            -- Type-icon host above the border's strip container (+1) and the fx
            -- border/glow hosts (+1/+2), like the live dispel holder clears them.
            button.typeHost:SetFrameLevel(button.border:GetFrameLevel() + 3)
            local Pix = CludesUI and CludesUI.PanelPP
            if Pix and look.border then
                local br, backdrop, bb, ba = look.border[1], look.border[2], look.border[3], look.border[4]
                if dispel and dcMap and dcMap[dispel] then
                    local c = dcMap[dispel]
                    br, backdrop, bb, ba = c.r, c.g, c.b, 1
                end
                local dim = look.border.size or 1
                if shapeActive and look.shapeBorderPath and Pix.ApplyMaskedShapeBorder then
                    CludesUI.HideBorderStyle(button.border)
                    if button.borderState and button.borderState._secretBorderEdges then
                        for _, tex in pairs(button.borderState._secretBorderEdges) do
                            tex:Hide()
                        end
                    end
                    Pix:ApplyMaskedShapeBorder(
                        button.border,
                        button.shapeMask,
                        look.shapeBorderPath,
                        look.shapeBorderSize or dim,
                        br,
                        backdrop,
                        bb,
                        ba
                    )
                    button.border:Show()
                else
                    if Pix.HideMaskedShapeBorder then
                        Pix:HideMaskedShapeBorder(button.border)
                    elseif button.border._shapeBorderTex then
                        button.border._shapeBorderTex:Hide()
                    end
                    local b = look.border
                    local appliedSize = (b.texture and b.texture ~= "" and b.texture ~= "solid")
                            and (b.textureSize or dim)
                        or dim
                    CludesUI.ApplySecretSafeBorderStyle(
                        button.border,
                        button.borderState,
                        appliedSize,
                        br,
                        backdrop,
                        bb,
                        ba,
                        b.texture or "solid",
                        b.offsetX,
                        b.offsetY,
                        b.shiftX,
                        b.shiftY,
                        b.addonKey or "unitframes",
                        b.sizeKey or dim,
                        b.edgeScale,
                        b.edgePx
                    )
                    button.borderMade = true
                end
            else
                if CludesUI.ApplySecretSafeBorderStyle then
                    CludesUI.ApplySecretSafeBorderStyle(
                        button.border,
                        button.borderState,
                        0,
                        0,
                        0,
                        0,
                        0,
                        "solid"
                    )
                elseif Pix and Pix.HideBorder then
                    Pix.HideBorder(button.border)
                else
                    button.border:Hide()
                end
                if Pix and Pix.HideMaskedShapeBorder then
                    Pix:HideMaskedShapeBorder(button.border)
                elseif button.border._shapeBorderTex then
                    button.border._shapeBorderTex:Hide()
                end
            end

            -- Dispel-type indicator icon (style.dispelTypeIcon): the live bar's
            -- engine channel picks the art per aura; here the fake entry's own
            -- dispel token does. Drawn on its own host above the swipe and border.
            local ti = look.dispelTypeIcon
            if ti and dispel and PV_DISPEL_ICON_ATLAS[dispel] then
                if not button.typeIcon then
                    button.typeIcon = button.typeHost:CreateTexture(nil, "OVERLAY", nil, 3)
                end
                button.typeIcon:SetAtlas(PV_DISPEL_ICON_ATLAS[dispel])
                -- Geometry from the (panel-scaled) cfg, like iconSize above --
                -- style carries the live pixel-snapped size, wrong units here.
                local tiSz = conf.dispelIconSize or 16
                button.typeIcon:SetSize(tiSz, tiSz)
                button.typeIcon:ClearAllPoints()
                local tiPt = PV_DISPEL_ICON_POINTS[ti.pos] or "CENTER"
                button.typeIcon:SetPoint(
                    tiPt,
                    button,
                    tiPt,
                    conf.dispelIconOffsetX or 0,
                    conf.dispelIconOffsetY or 0
                )
                button.typeIcon:Show()
            elseif button.typeIcon then
                button.typeIcon:Hide()
            end

            local cdMaskKey = shapeActive and look.iconShape or nil
            if button._cdShapeApplied ~= cdMaskKey then
                if cdMaskKey then
                    pcall(button.cooldown.AddMaskTexture, button.cooldown, button.shapeMask)
                    if button.cooldown.SetSwipeTexture then
                        pcall(button.cooldown.SetSwipeTexture, button.cooldown, look.shapeMaskPath)
                    end
                else
                    pcall(button.cooldown.RemoveMaskTexture, button.cooldown, button.shapeMask)
                    if button.cooldown.SetSwipeTexture then
                        pcall(button.cooldown.SetSwipeTexture, button.cooldown, "")
                    end
                end
                button._cdShapeApplied = cdMaskKey
            end

            if slotIndex.kind ~= "placeholder" then
                button.textHost:SetAllPoints(button)
                button.textHost:SetFrameLevel(button:GetFrameLevel() + 2)

                button.duration:ClearAllPoints()
                button.duration:SetFont(fontFile, look.durationFontSize or 11, "OUTLINE")
                button.duration:SetPoint(
                    look.durationPoint or "CENTER",
                    button,
                    look.durationRelPoint or "CENTER",
                    look.durationX or 0,
                    look.durationY or 0
                )
                local dc = look.durationColor
                button.duration:SetTextColor(dc and dc.r or 1, dc and dc.g or 1, dc and dc.b or 1)
                button.duration:SetShown(not look.hideDurationText)
                local pv = slotIndex.pv or i
                button.duration:SetText(PREVIEW_DURATIONS[((pv - 1) % #PREVIEW_DURATIONS) + 1])

                button.stack:ClearAllPoints()
                button.stack:SetFont(fontFile, look.stackFontSize or 11, "OUTLINE")
                button.stack:SetPoint(
                    look.stackPoint or "BOTTOMRIGHT",
                    button,
                    look.stackPoint or "BOTTOMRIGHT",
                    look.stackX or 0,
                    look.stackY or 0
                )
                local sc = look.stackColor
                button.stack:SetTextColor(sc and sc.r or 1, sc and sc.g or 1, sc and sc.b or 1)
                local stackVal = PREVIEW_STACKS[((pv - 1) % #PREVIEW_STACKS) + 1]
                button.stack:SetShown(look.showStacks ~= false and stackVal ~= nil)
                if stackVal then
                    button.stack:SetText(stackVal)
                end
            end

            -- Duration-swipe preview: randomized FROZEN sweep -- a stable per-slot
            -- fraction on an hour-long cooldown, so each icon shows a varied
            -- mid-flight state without visibly animating. Reverse per the bar's
            -- Reverse Swipe cog; placeholder slots carry no swipe.
            local cd = button.cooldown
            if cd then
                if slotIndex.kind ~= "placeholder" and look.hideSwipe ~= true then
                    local dur = 3600
                    cd:SetReverse(look.cooldownReverse ~= false)
                    cd:SetCooldown(GetTime() - dur * (1 - GetPvCDSeed(i)), dur)
                    cd:Show()
                else
                    cd:SetCooldown(0, 0)
                    cd:Hide()
                end
            end

            -- nil clears any fx left over on a reused icon frame from a previous
            -- render (slot not claimed this pass, or block removed/deactivated).
            ApplyPreviewFx(button, fxBySlot and fxBySlot[i])

            button:Show()
        elseif icons[i] then
            icons[i]:Hide()
        end
    end
end

-- Public hook for the Options UI: builds this bar's embedded preview box entirely
-- OUTSIDE the scrollable settings area (the scrollbar must only scroll the settings
-- fields, never the preview) -- box, "PREVIEW" label, darkened header band, and divider
-- are all children of `outerFrame` (the detail pane's top-level, non-scrolling frame
-- title/desc already live on), sized to the bar's REAL configured grid (ComputeGrid,
-- same as the live bar), horizontally centered (TOP-to-TOP anchor).
--
-- The "PREVIEW" label is wrapped in a small padDiff-compensated + clipped frame (same
-- CONTENT_PAD-vs-20px trick as CUI_PlayerAuraBars_ManagerPages.lua's
-- WrapCompensatedBody, duplicated rather than shared -- W:SectionHeader assumes a 45px
-- margin but this pane only reserves 20px); the box itself needs no such compensation,
-- positioned via a plain SetPoint not a W: widget.
--
-- Geometry (box size, header band, divider Y, and the caller's scroll-area top offset
-- via the onResize hook -- see PAB_MaybeRefreshPreview) is recomputed on every
-- live-apply refresh too, not just at build time: a row/column/icon-count change
-- (Icons Per Row, Max Rows, Max Total, Icon Size, Row Spacing, ...) changes the grid's
-- real footprint, and a stale-size box would clip new icons or leave a gap until the
-- next rebuild. Box/divider position stays fixed at build time (so settings fields
-- don't jump on slider ticks) but the box's own footprint must track its grid.
--   outerFrame: detail pane's top-level frame (title/desc's parent). startY:
--   outerFrame-local Y to start the PREVIEW label/box (caller's fixed offset below
--   title/desc, e.g. -50). kind: "buff" or "debuff"; id: "default" | a custom bar's
--   id. cfg: the same cfg table the caller already resolved for its own field builders.
-- Returns the outerFrame-local Y where the preview area ends -- passed straight to
-- WrapCompensatedBody(outerFrame, returnedY) as the scroll area's top offset.
function mod.PAB_BuildPreviewBox(outerFrame, fontFile, startY, kindOf, ident, conf)
    -- Options page only: under the kept manager root the options frame pool
    -- (CludesUI_FramePool.lua) hands the next render these frames back.
    local CreateFrame = CludesUI._Pool.CreateFrame
    local isBuff = kindOf == "buff"
    local sy = startY

    do
        local contentPad = CludesUI.CONTENT_PAD or 45
        local padDiff = contentPad - 20
        local visibleW = outerFrame:GetWidth()
        -- Was W:SectionHeader, a shared widget fixed at 40px tall with its label
        -- anchored 8px from the BOTTOM -- meant for spacing consistency among stacked
        -- option rows elsewhere, not this floating title/desc/box context, and it left
        -- ~20px of blank padding above "PREVIEW" with nothing needing that room here.
        -- Replaced with a lightweight, purpose-built label + separator at a fraction
        -- of the height, matching SectionHeader's look (CludesUI.TEXT_SECTION/
        -- BORDER_COLOR) without touching the shared widget file.
        local hdrH = 18

        -- Shift lives on the clipping frame (hdrClip), not hdrBody inside it --
        -- mirrors WrapCompensatedBody's own fix in CUI_PlayerAuraBars_
        -- ManagerPages.lua ("shift the child instead of the clip frame" measured a
        -- real ~30px extra gap in-game vs shifting the clip/scroll frame itself).
        local hdrClip = CreateFrame("Frame", nil, outerFrame)
        hdrClip:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", -padDiff, sy)
        hdrClip:SetSize(math.max(visibleW, 1) + padDiff * 2, hdrH)
        hdrClip:SetClipsChildren(true)

        local hdrBody = CreateFrame("Frame", nil, hdrClip)
        hdrBody:SetSize(visibleW + padDiff * 2, hdrH)

        local TS = CludesUI.TEXT_SECTION or { r = 0.5, g = 0.5, b = 0.5, a = 1 }
        local labelText = hdrBody:CreateFontString(nil, "OVERLAY")
        labelText:SetFont(fontFile, 12, "")
        labelText:SetTextColor(TS.r, TS.g, TS.b, TS.a or 1)
        labelText:SetPoint("BOTTOMLEFT", hdrBody, "BOTTOMLEFT", contentPad, 0)
        labelText:SetText(CludesUI.L("PREVIEW"))

        local BC = CludesUI.BORDER_COLOR or { r = 1, g = 1, b = 1 }
        local sep = hdrBody:CreateTexture(nil, "ARTWORK")
        sep:SetColorTexture(BC.r, BC.g, BC.b, 0.02)
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", hdrBody, "BOTTOMLEFT", contentPad, 0)
        sep:SetPoint("BOTTOMRIGHT", hdrBody, "BOTTOMRIGHT", -contentPad, 0)

        sy = sy - hdrH
    end

    -- Sized from the SCALED cfg (see ScaledPreviewCfg/PreviewScaleFactor) so the
    -- box's footprint matches what RenderPreviewIcons actually draws into it.
    local grid = ComputeGrid(isBuff, ScaledPreviewCfg(conf, isBuff))
    -- +30 (scaled) extra vertical room for duration/stack text above/below the icon
    -- grid -- ComputeGrid's width/height are the icon grid's bounding box only (same
    -- as the real bar), text can render outside it depending on Duration/Stacks Position.
    local boxHeight = grid.height + 30 * PreviewScaleFactor()
    local boxFrame = CreateFrame("Frame", nil, outerFrame)
    boxFrame:SetPoint("TOP", outerFrame, "TOP", 0, sy)
    boxFrame:SetSize(math.max(grid.width, 1), boxHeight)

    local headerBg = outerFrame._pabPreviewHeaderBg
    if not headerBg then
        headerBg = outerFrame:CreateTexture(nil, "BACKGROUND")
        headerBg:SetColorTexture(0, 0, 0, 0.15)
        outerFrame._pabPreviewHeaderBg = headerBg
    end
    -- The tinted band covers the PREVIEW header + box only, starting at startY --
    -- the pane's own title row above it stays on the plain background.
    headerBg:ClearAllPoints()
    headerBg:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 0, startY)
    headerBg:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", 0, startY)

    local divider = outerFrame._pabPreviewDivider
    if not divider then
        divider = outerFrame:CreateTexture(nil, "OVERLAY")
        divider:SetColorTexture(1, 1, 1, 0.10)
        divider:SetHeight(1)
        outerFrame._pabPreviewDivider = divider
    end

    local bottomY = sy - boxHeight - 10
    headerBg:SetHeight(startY - bottomY)
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 0, bottomY)
    divider:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", 0, bottomY)

    local icons = {}
    -- Shuffled once per box build, not per refresh (see BuildBuffPreviewPool: icons
    -- shouldn't swap spell identity on every slider tick, only style/position/count).
    -- Debuffs get the same treatment via BuildDebuffPreviewPool().
    local pool
    if isBuff then
        pool = BuildBuffPreviewPool()
    else
        pool = BuildDebuffPreviewPool()
    end
    activePreview = {
        kind = kindOf,
        id = ident,
        box = boxFrame,
        icons = icons,
        fontPath = fontFile,
        pool = pool,
        outerFrame = outerFrame,
        boxTopY = sy,
        bandTopY = startY,
        headerBg = headerBg,
        divider = divider,
        -- the box's dress (nil off the pool): PAB_MaybeRefreshPreview stands down
        -- once a later render parked the box or dressed it again
        gen = CludesUI._Pool.Gen(boxFrame),
    }
    RenderPreviewIcons(boxFrame, icons, isBuff, conf, fontFile, pool)

    return bottomY
end

-- Registers a callback the caller's WrapCompensatedBody (CUI_PlayerAuraBars_
-- ManagerPages.lua) uses to reposition its scroll frame's top edge whenever
-- PAB_MaybeRefreshPreview resizes the box below. Set on activePreview (not a
-- standalone module-level var) so a callback from a since-torn-down detail pane can
-- never fire against the wrong pane's box after a tab switch rebuilds activePreview.
function mod.PAB_SetPreviewResizeHandler(func)
    if activePreview then
        activePreview.onResize = func
    end
end

-- Piggyback hook, called at the end of every live-apply path (ApplyLiveConfig,
-- PAB_ReloadCustomBuffBar, PAB_ReloadCustomDebuffBar) so a currently-open preview box
-- stays in sync with slider drags/dropdown changes without CUI_PlayerAuraBars_
-- ManagerPages.lua needing to know the preview exists or wrap its ApplyBar() closures.
PAB_MaybeRefreshPreview = function(kindOf, ident)
    if not (activePreview and activePreview.kind == kindOf and activePreview.id == ident) then
        return
    end
    -- The page was left: its root waits parked and hidden until its next
    -- render, which builds a new preview, so nothing is drawn into the hidden
    -- box meanwhile (ns._pabRoot is nil only while the root is parked).
    if not mod._pabRoot then
        activePreview = nil
        return
    end
    -- A render of the kept manager root without this box parked it (or a later
    -- one dressed it again): its frames belong to the pool now, not to this
    -- preview. (activePreview exists only once the options addon, and with it
    -- the pool, has loaded.)
    local Pool = CludesUI._Pool
    if Pool.IsIdle(activePreview.box) or Pool.Gen(activePreview.box) ~= activePreview.gen then
        activePreview = nil
        return
    end
    local conf, isBuff = ResolvePreviewCfg(kindOf, ident)
    if not conf then
        return
    end

    -- Re-derive the box's footprint from the SAME scaled grid RenderPreviewIcons is
    -- about to draw into, mirroring PAB_BuildPreviewBox's own boxHeight/bottomY math
    -- (kept in sync manually).
    local grid = ComputeGrid(isBuff, ScaledPreviewCfg(conf, isBuff))
    local boxHeight = grid.height + 30 * PreviewScaleFactor()
    activePreview.box:SetSize(math.max(grid.width, 1), boxHeight)

    local bottomY = activePreview.boxTopY - boxHeight - 10
    if activePreview.headerBg then
        activePreview.headerBg:SetHeight((activePreview.bandTopY or 0) - bottomY)
    end
    if activePreview.divider and activePreview.outerFrame then
        activePreview.divider:ClearAllPoints()
        activePreview.divider:SetPoint("TOPLEFT", activePreview.outerFrame, "TOPLEFT", 0, bottomY)
        activePreview.divider:SetPoint("TOPRIGHT", activePreview.outerFrame, "TOPRIGHT", 0, bottomY)
    end
    if activePreview.onResize then
        activePreview.onResize(bottomY)
    end

    RenderPreviewIcons(
        activePreview.box,
        activePreview.icons,
        isBuff,
        conf,
        activePreview.fontPath,
        activePreview.pool
    )
end
SetMaybeRefreshPreview(PAB_MaybeRefreshPreview)

Inner.broken = false
