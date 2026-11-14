if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Character Sheet on WoW Forever
--
--  The retail character sheet gets the full makeover
--  (CludesUIBlizzardSkin_CharacterSheet.lua); that file stands down on the
--  Forever client and this one gives the sheet the ordinary window-skin
--  treatment instead, on Blizzard's own Forever frame:
--    - the standard window shell (dark backdrop, border, top bar) and the
--      house close button, through the same engine calls every skinned
--      Blizzard window uses;
--    - every piece of frame art stripped: the pane backdrops and stone
--      header, the item slot frames, the class icon and its ring, the rock
--      strip under the level line, the right-pane collapse arrow;
--    - the retail sheet's model backdrop behind the character, cover-cropped
--      to the model area, and the retail sidebar's darker panel behind the
--      stats (its left edge is the divider between the two panes);
--    - the item slots as on retail: icons cropped by the Icon Zoom setting,
--      a grey square behind each and a 2px border in the item's quality
--      colour (dark grey when empty), recoloured through Blizzard's own
--      per-slot update;
--    - text beside each slot where retail shows its item level and upgrade
--      track (neither means much on Forever): the item's main and secondary
--      stat, or its armor when it has no stats, a weapon's damage per second
--      under that, and the enchant name under those, painted through the
--      same per-slot update; retail's top-left eyeball hides it all for the
--      session;
--    - the character name and the "Level N Class" line in the house font,
--      as on retail (Blizzard keeps writing the text, so the class colour
--      and the pvp title still come from the client);
--    - the stats list stays Blizzard's list on Blizzard's scrollbar, whose
--      track and thumb take the house thin style in place (arrows kept);
--      its category headers and values take the retail sidebar's colour
--      system (per-category colours, the user's overrides from the options
--      page, the thin header bars) through the scroll box's own frame
--      callbacks, never by touching its data.
--
--  All of this is the CludesUI look (the Character Sheet card's
--  CludesUI and Modern). Under the card's Blizz Default only the slot text
--  stays, on Blizzard's own sheet: the same lines through the same per-slot
--  update, set further out so they clear Blizzard's bronze slot frames. The
--  outer weapon slots' lines start lower (under the columns' bottom slot
--  frames) and the middle weapon slot's lines stack above it, running left
--  from its right edge (the frame border leaves no room under it), clear of
--  the columns' own text; weapon lines too long for their room are cut
--  short. No eyeball there: that corner is Blizzard's portrait.
--  The card's Off and the window skins kill switch stop both looks.
--
--  Cost: a one-time pass at login on frames that already exist (under Blizz
--  Default, a one-time text build at the slots' first show instead), then a
--  recolour per element initialisation (what Blizzard does anyway on each
--  stats refresh) and one colour compare plus one item-link compare per slot
--  update (Blizzard's own, only while the slots are shown). The one event of
--  our own, GET_ITEM_INFO_RECEIVED, is registered only while a shown slot
--  waits on item data the client has not cached yet. Nothing at all while the
--  card is Off.
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
local CludesUI = _G.CludesUI
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end

local FFD, GetFFD = CludesUI.NewFrameData()

-- The Character Sheet card's Off and the window skins kill switch, which
-- stop both looks (as they stop the retail sheet's).
local function SheetOn()
    if not CludesUIDB then
        return true
    end
    if CludesUIDB.themedCharacterSheet == false then
        return false
    end
    return not CludesUI.BlizzWindowSkinsKilled()
end

-- The CludesUI look (the card's style is latched at login, so a change
-- lands at the reload).
local function Enabled()
    return not mod.CharSheetStock() and SheetOn()
end

-- The slot text: both looks.
local function TextEnabled()
    return SheetOn()
end

local function FontPath()
    return (CludesUI.GetFontPath("blizzardSkin")) or STANDARD_TEXT_FONT
end

local MEDIA = "Interface\\AddOns\\CludesUIBlizzardSkin\\Media\\"

-- The retail sheet's Icon Zoom setting (same key, same default).
local function Zoom()
    return (CludesUIDB and CludesUIDB.charSheetIconZoom) or 0.07
end

-- Blizzard pieces that must go for good are parked under a hidden frame:
-- Hide() gets undone by the client's own refreshes, a hidden parent does not.
local Bin
local function Discard(regionFrame)
    if not regionFrame or not regionFrame.SetParent then
        return
    end
    if not Bin then
        Bin = CreateFrame("Frame")
        Bin:Hide()
    end
    regionFrame:SetParent(Bin)
end

--------------------------------------------------------------------------------
--  Colours: the retail sidebar's category palette, keyed the way the options
--  page stores overrides (CludesUIDB.statCategoryColors[key]). Forever's
--  categories map onto it; General gets its own cyan, the pet pane's Combat
--  takes Attack's.
--------------------------------------------------------------------------------
local DEFAULT_COLORS = {
    General = { r = 0.30, g = 0.80, b = 0.95 },
    Attributes = { r = 0.298, g = 0.788, b = 0.941 },
    Attack = { r = 1, g = 0.353, b = 0.122 },
    ["Secondary Stats"] = { r = 0.471, g = 0.255, b = 0.784 },
    Defense = { r = 0.247, g = 0.655, b = 1 },
}
local CATEGORY_KEY = {}
if STAT_CATEGORY_GENERAL then
    CATEGORY_KEY[STAT_CATEGORY_GENERAL] = "General"
end
if STAT_CATEGORY_PRIMARY_ATTRIBUTES then
    CATEGORY_KEY[STAT_CATEGORY_PRIMARY_ATTRIBUTES] = "Attributes"
end
if STAT_CATEGORY_WEAPONS then
    CATEGORY_KEY[STAT_CATEGORY_WEAPONS] = "Attack"
end
if STAT_CATEGORY_MODIFIERS then
    CATEGORY_KEY[STAT_CATEGORY_MODIFIERS] = "Secondary Stats"
end
if STAT_CATEGORY_DEFENSE then
    CATEGORY_KEY[STAT_CATEGORY_DEFENSE] = "Defense"
end
if STAT_CATEGORY_COMBAT then
    CATEGORY_KEY[STAT_CATEGORY_COMBAT] = "Attack"
end

local function CategoryColor(categoryName)
    local key = categoryName and CATEGORY_KEY[categoryName]
    local saved = CludesUIDB
    -- A custom colour applies only while its "use" flag is on, as on retail.
    local custom = key
        and saved
        and saved.statCategoryUseColor
        and saved.statCategoryUseColor[key]
        and saved.statCategoryColors
        and saved.statCategoryColors[key]
    local c = custom or (key and DEFAULT_COLORS[key])
    if c and c.r then
        return c.r, c.g, c.b
    end
    local ACC = CludesUI.CLUDES_GREEN
    if ACC then
        return ACC.r, ACC.g, ACC.b
    end
    return 1, 1, 1
end

-- The category a stat element belongs to: the data provider lists a header
-- then its rows, so it is the last header ahead of the element.
local function CategoryOf(boxFrame, elementData)
    local entries = boxFrame and boxFrame.elementData
    if type(entries) ~= "table" then
        return nil
    end
    local current
    for i = 1, #entries do
        local d = entries[i]
        if d.isHeader then
            current = d.name
        end
        if d == elementData then
            return current
        end
    end
    return current
end

--------------------------------------------------------------------------------
--  Stats list elements
--------------------------------------------------------------------------------
local function OnePixel(widget)
    local Pix = CludesUI.PP
    local perfect = (Pix and Pix.perfect) or 1
    local es = widget:GetEffectiveScale()
    if not es or es <= 0 then
        es = 1
    end
    return perfect / es
end

local function SkinHeader(widget, r, g, b)
    local d = GetFFD(widget)
    if not d.done then
        d.done = true
        if widget.Background then
            widget.Background:SetAlpha(0)
        end
        if widget.Title then
            widget.Title:SetFont(FontPath(), 11, "")
        end
        local leftBar = widget:CreateTexture(nil, "ARTWORK")
        leftBar:SetPoint("LEFT", widget, "LEFT", 8, 0)
        leftBar:SetPoint("RIGHT", widget.Title, "LEFT", -6, 0)
        d.leftBar = leftBar
        local rightBar = widget:CreateTexture(nil, "ARTWORK")
        rightBar:SetPoint("LEFT", widget.Title, "RIGHT", 6, 0)
        rightBar:SetPoint("RIGHT", widget, "RIGHT", -8, 0)
        d.rightBar = rightBar
    end
    if widget.Title then
        widget.Title:SetTextColor(r, g, b, 1)
    end
    local px = OnePixel(widget)
    d.leftBar:SetColorTexture(r, g, b, 0.8)
    d.rightBar:SetColorTexture(r, g, b, 0.8)
    d.leftBar:SetHeight(px)
    d.rightBar:SetHeight(px)
end

local function SkinRow(widget, r, g, b)
    local d = GetFFD(widget)
    if not d.done then
        d.done = true
        if widget.Background then
            widget.Background:SetAlpha(0)
        end
        if widget.Label then
            widget.Label:SetFont(FontPath(), 10, "")
        end
        if widget.Value then
            widget.Value:SetFont(FontPath(), 10, "")
        end
        -- The retail rows carry a faint divider under each line.
        local divider = widget:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(1, 1, 1, 0.06)
        divider:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 8, 0)
        divider:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -8, 0)
        divider:SetHeight(OnePixel(widget))
        d.divider = divider
    end
    if widget.Label then
        widget.Label:SetTextColor(0.7, 0.7, 0.7, 0.8)
    end
    if widget.Value then
        widget.Value:SetTextColor(r, g, b, 1)
    end
end

local function SkinElement(boxFrame, widget, elementData)
    if not widget or not elementData then
        return
    end
    if elementData.isHeader then
        SkinHeader(widget, CategoryColor(elementData.name))
    else
        SkinRow(widget, CategoryColor(CategoryOf(boxFrame, elementData)))
    end
end

local function HookStatsList(boxFrame)
    if not boxFrame or not boxFrame.ScrollBox or GetFFD(boxFrame).hooked then
        return
    end
    GetFFD(boxFrame).hooked = true
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        -- The event hands (owner, frame, elementData); the helper's own
        -- iterateExisting pass hands (frame, elementData) instead, so the
        -- frames already alive are walked separately below.
        ScrollUtil.AddInitializedFrameCallback(boxFrame.ScrollBox, function(_, widget, elementData)
            SkinElement(boxFrame, widget, elementData)
        end, nil, false)
        if boxFrame.ScrollBox.ForEachFrame then
            boxFrame.ScrollBox:ForEachFrame(function(widget, elementData)
                SkinElement(boxFrame, widget, elementData)
            end)
        end
    end
end

-- Options-page refresh: colour overrides and their use flags land here, on
-- the frames alive in both lists. The retail sheet's refresher of the same
-- name is replaced (it walks retail-only state), so the swatches reach this.
local STAT_BOXES = { "CharacterStatsPaneScrollBox", "CharacterStatsPanePetScrollBox" }
function CludesUI._refreshCharacterSheetColors()
    if not Enabled() then
        return
    end
    for i = 1, #STAT_BOXES do
        local boxFrame = _G[STAT_BOXES[i]]
        if boxFrame and boxFrame.ScrollBox and boxFrame.ScrollBox.ForEachFrame then
            boxFrame.ScrollBox:ForEachFrame(function(widget, elementData)
                SkinElement(boxFrame, widget, elementData)
            end)
        end
    end
end

--------------------------------------------------------------------------------
--  The frame
--------------------------------------------------------------------------------
local SLOTS = {
    "CharacterHeadSlot",
    "CharacterNeckSlot",
    "CharacterShoulderSlot",
    "CharacterBackSlot",
    "CharacterChestSlot",
    "CharacterShirtSlot",
    "CharacterTabardSlot",
    "CharacterWristSlot",
    "CharacterHandsSlot",
    "CharacterWaistSlot",
    "CharacterLegsSlot",
    "CharacterFeetSlot",
    "CharacterFinger0Slot",
    "CharacterFinger1Slot",
    "CharacterTrinket0Slot",
    "CharacterTrinket1Slot",
    "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot",
    "CharacterRangedSlot",
    "CharacterAmmoSlot",
}

local function FadeChildren(widget, Fade)
    if not widget then
        return
    end
    local children = { widget:GetChildren() }
    for i = 1, #children do
        local childFrame = children[i]
        if
            childFrame
            and childFrame.GetRegions
            and not (childFrame.IsForbidden and childFrame:IsForbidden())
        then
            Fade(childFrame)
        end
    end
end

-- The equipped item's quality colour; nothing when the slot is empty.
local function QualityColor(slotIndex)
    local quality = GetInventoryItemQuality("player", slotIndex:GetID())
    if quality and not (issecretvalue and issecretvalue(quality)) then
        local r, g, b
        if C_Item and C_Item.GetItemQualityColor then
            r, g, b = C_Item.GetItemQualityColor(quality)
        elseif GetItemQualityColor then
            r, g, b = GetItemQualityColor(quality)
        end
        if r then
            return r, g, b
        end
    end
end

-- The slot border colour: the equipped item's quality, dark grey when empty
-- (the retail sheet's values).
local function SlotBorderColor(slotIndex)
    local r, g, b = QualityColor(slotIndex)
    if r then
        return r, g, b
    end
    return 0.4, 0.4, 0.4
end

local function ColorSlotBorder(slotIndex)
    local PanelPP = CludesUI.PanelPP
    if not (PanelPP and PanelPP.SetBorderColor) then
        return
    end
    local r, g, b = SlotBorderColor(slotIndex)
    PanelPP.SetBorderColor(slotIndex, r, g, b, 1)
end

--------------------------------------------------------------------------------
--  Slot text where the retail sheet shows the item level and upgrade track:
--  the item's main and secondary stat, or its armor when it has no stats,
--  and the enchant name under it. It reads the retail upgrade track and
--  enchant settings keys, sizes and colours, so those options rows drive it
--  through the refreshers redefined below.
--------------------------------------------------------------------------------
local EX_LOOK = 5 -- the CludesUI look's text edge, off the slot edge
local EX = EX_LOOK -- the text's near edge, off the slot edge
local WY = 10 -- the outer weapon slots' first line, above the slot's centre
-- Under Blizz Default Blizzard's bronze slot frames stay: the 55px art round
-- each 37px slot reaches 9px past its edges. The text sits 4px past that,
-- and the outer weapon slots' first line drops to the slot's centre so it
-- clears the frames of the columns' bottom slots (set at the build, the
-- style being latched for the session).
local SLOT_FRAME = 9
local stockPane -- Blizz Default: the left pane, which the side weapon lines stop at

-- Where each slot's text sits: "R" right of it, "L" left of it, "B" below
-- it, "T" above it. The inner side for the two columns; the outer side for
-- the outer weapon slots (the ranged text past the ammo slot while that
-- shows); below the middle weapon slot, whose sides are taken and whose top
-- holds the flyout arrow, or above it under Blizz Default (Blizzard's frame
-- border leaves no room under it). Shirt, tabard and ammo carry none
-- (shirt and tabard carry none on retail either).
local TEXT_SIDE = {
    CharacterHeadSlot = "R",
    CharacterNeckSlot = "R",
    CharacterShoulderSlot = "R",
    CharacterBackSlot = "R",
    CharacterChestSlot = "R",
    CharacterWristSlot = "R",
    CharacterHandsSlot = "L",
    CharacterWaistSlot = "L",
    CharacterLegsSlot = "L",
    CharacterFeetSlot = "L",
    CharacterFinger0Slot = "L",
    CharacterFinger1Slot = "L",
    CharacterTrinket0Slot = "L",
    CharacterTrinket1Slot = "L",
    CharacterMainHandSlot = "L",
    CharacterSecondaryHandSlot = "B",
    CharacterRangedSlot = "R",
}

-- The slots that can hold a weapon carry a dps line (painted only when the
-- item there is one).
local WEAPON_SLOT = {
    CharacterMainHandSlot = true,
    CharacterSecondaryHandSlot = true,
    CharacterRangedSlot = true,
}

-- C_Item.GetItemStats keys in tie order (an earlier key wins a tie), with our
-- own short labels. Main stat: the largest of the first three (the
-- primaries), else of the next two (Stamina, Spirit). Secondary: the largest
-- of every other listed key. Armor, shield block value, weapon damage,
-- sockets and any unlisted key never show. Built on first use, once the
-- locale catalog is active.
local STAT_LIST
local function StatList()
    if STAT_LIST then
        return STAT_LIST
    end
    local crit, hit = CludesUI.L("Crit"), CludesUI.L("Hit")
    local mp5, hp5 = CludesUI.L("MP5"), CludesUI.L("HP5")
    STAT_LIST = {
        { "ITEM_MOD_STRENGTH_SHORT", CludesUI.L("Str") },
        { "ITEM_MOD_AGILITY_SHORT", CludesUI.L("Agi") },
        { "ITEM_MOD_INTELLECT_SHORT", CludesUI.L("Int") },
        { "ITEM_MOD_STAMINA_SHORT", CludesUI.L("Stam") },
        { "ITEM_MOD_SPIRIT_SHORT", CludesUI.L("Spi") },
        { "ITEM_MOD_ATTACK_POWER_SHORT", CludesUI.L("AP") },
        { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", CludesUI.L("RAP") },
        { "ITEM_MOD_SPELL_POWER_SHORT", CludesUI.L("SP") },
        { "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", CludesUI.L("Spell Dmg") },
        { "ITEM_MOD_SPELL_HEALING_DONE_SHORT", CludesUI.L("Heal") },
        { "ITEM_MOD_CRIT_RATING_SHORT", crit },
        { "ITEM_MOD_CRIT_MELEE_RATING_SHORT", crit },
        { "ITEM_MOD_CRIT_RANGED_RATING_SHORT", crit },
        { "ITEM_MOD_CRIT_SPELL_RATING_SHORT", CludesUI.L("Spell Crit") },
        { "ITEM_MOD_HIT_RATING_SHORT", hit },
        { "ITEM_MOD_HIT_MELEE_RATING_SHORT", hit },
        { "ITEM_MOD_HIT_RANGED_RATING_SHORT", hit },
        { "ITEM_MOD_HIT_SPELL_RATING_SHORT", CludesUI.L("Spell Hit") },
        { "ITEM_MOD_HASTE_RATING_SHORT", CludesUI.L("Haste") },
        { "ITEM_MOD_MANA_REGENERATION_SHORT", mp5 },
        { "ITEM_MOD_POWER_REGEN0_SHORT", mp5 },
        { "ITEM_MOD_HEALTH_REGEN_SHORT", hp5 },
        { "ITEM_MOD_HEALTH_REGENERATION_SHORT", hp5 },
        { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", CludesUI.L("Def") },
        { "ITEM_MOD_DODGE_RATING_SHORT", CludesUI.L("Dodge") },
        { "ITEM_MOD_PARRY_RATING_SHORT", CludesUI.L("Parry") },
        { "ITEM_MOD_BLOCK_RATING_SHORT", CludesUI.L("Block") },
        { "ITEM_MOD_SPELL_PENETRATION_SHORT", CludesUI.L("Spell Pen") },
        { "RESISTANCE1_NAME", CludesUI.L("Holy Res") },
        { "RESISTANCE2_NAME", CludesUI.L("Fire Res") },
        { "RESISTANCE3_NAME", CludesUI.L("Nature Res") },
        { "RESISTANCE4_NAME", CludesUI.L("Frost Res") },
        { "RESISTANCE5_NAME", CludesUI.L("Shadow Res") },
        { "RESISTANCE6_NAME", CludesUI.L("Arcane Res") },
    }
    return STAT_LIST
end

-- "+14 Int / +9 Stam": main / secondary, one when only one exists; an item
-- with no listed stat shows its armor ("45 Armor"), else "". Memoized per
-- link (the link carries every input: item, suffix, enchant); an item whose
-- stats have not arrived is not recorded.
local statTextCache = {}
local armorLabel
local function StatText(itemLink)
    local textValue = statTextCache[itemLink]
    if textValue then
        return textValue
    end
    local stats = C_Item.GetItemStats(itemLink)
    if not stats then
        return ""
    end
    local entries = StatList()
    local main, mainV = nil, 0
    for i = 1, 3 do
        local val = stats[entries[i][1]]
        if val and val > mainV then
            main, mainV = i, val
        end
    end
    if not main then
        for i = 4, 5 do
            local val = stats[entries[i][1]]
            if val and val > mainV then
                main, mainV = i, val
            end
        end
    end
    local second, secondV = nil, 0
    for i = 1, #entries do
        local val = i ~= main and stats[entries[i][1]]
        if val and val > secondV then
            second, secondV = i, val
        end
    end
    if main and second then
        textValue = string.format("+%d %s / +%d %s", mainV, entries[main][2], secondV, entries[second][2])
    elseif main or second then
        textValue = string.format("+%d %s", main and mainV or secondV, entries[main or second][2])
    else
        local armor = stats.RESISTANCE0_NAME
        if armor and armor > 0 then
            armorLabel = armorLabel or CludesUI.L("Armor")
            textValue = string.format("%d %s", armor, armorLabel)
        else
            textValue = ""
        end
    end
    statTextCache[itemLink] = textValue
    return textValue
end

-- "6.3 Dps" for a weapon (item class Weapon, so never a shield or a held-in
-- off-hand item), "" for anything else. Memoized per link like the stats.
local dpsTextCache = {}
local dpsLabel
local function DpsText(itemLink)
    local textValue = dpsTextCache[itemLink]
    if textValue then
        return textValue
    end
    textValue = ""
    if select(6, C_Item.GetItemInfoInstant(itemLink)) == Enum.ItemClass.Weapon then
        local stats = C_Item.GetItemStats(itemLink)
        if not stats then
            return ""
        end
        local dps = stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
        if dps and dps > 0 then
            dpsLabel = dpsLabel or CludesUI.L("Dps")
            textValue = string.format("%.1f %s", dps, dpsLabel)
        end
    end
    dpsTextCache[itemLink] = textValue
    return textValue
end

local function SavedDB(key)
    local saved = CludesUIDB
    return saved and saved[key]
end

-- The enchant name through the retail sheet's reader, which takes the
-- engine-tagged permanent enchant tooltip line. A vanilla line is the effect
-- itself ("+7 Agility"): the plus the reader trims goes back on, and an
-- "Enchanted: " prefix, where the client adds one, comes off. The inspect
-- sheet names its enchants through the same function.
local ENCHANT_PREFIX = ENCHANTED_TOOLTIP_LINE and ENCHANTED_TOOLTIP_LINE:match("^(.-)%%s")
function mod.ForeverEnchantName(textValue)
    if textValue == "" then
        return textValue
    end
    if ENCHANT_PREFIX and ENCHANT_PREFIX ~= "" and textValue:sub(1, #ENCHANT_PREFIX) == ENCHANT_PREFIX then
        textValue = textValue:sub(#ENCHANT_PREFIX + 1)
    end
    if textValue:find("^%d") then
        textValue = "+" .. textValue
    end
    return textValue
end
local function EnchantName(slotID)
    return mod.ForeverEnchantName(CludesUI.GetEnchantText(slotID))
end

local textVer = 1 -- bumped by every options refresh
local pending, pendingN = {}, 0 -- SLOTS index -> itemID waiting on item data
local itemWatch -- GET_ITEM_INFO_RECEIVED, registered only while a slot waits

-- The stats font (and the weapon slots' dps line): the retail upgrade
-- track's size, outline and shadow keys. The enchant's font follows its
-- name mode at paint.
local function ApplyLabelFonts(d)
    local filePath = FontPath()
    local dim = SavedDB("charSheetUpgradeTrackSize") or 11
    local flags = SavedDB("charSheetUpgradeTrackOutline") and CludesUI.SlugFlag("OUTLINE, SLUG") or ""
    CludesUI.PrimeFontShadow(d.stats, SavedDB("charSheetUpgradeTrackShadow"))
    d.stats:SetFont(filePath, dim, flags)
    if d.dps then
        CludesUI.PrimeFontShadow(d.dps, SavedDB("charSheetUpgradeTrackShadow"))
        d.dps:SetFont(filePath, dim, flags)
    end
    d.fontVer = textVer
end

-- Blizz Default: a weapon slot's lines capped at the room they have
-- (the stats and dps take its width, justified to their anchored side; the
-- enchant shrinks to it when wider), cut short rather than run past it.
local function CapLines(d, room, justify)
    if not room or room <= 0 then
        return
    end
    d.stats:SetWidth(room)
    d.stats:SetJustifyH(justify)
    d.dps:SetWidth(room)
    d.dps:SetJustifyH(justify)
    if d.ench:GetWidth() > room then
        d.ench:SetWidth(room)
    end
end

-- The side weapon lines stop 6px inside the left pane (its frame border on
-- the left, the stats pane's edge on the right: past the ammo slot the
-- ranged text has about 90px).
local PANE_PAD = 6
local function CapToPane(d, anchorFrame, anchorPoint)
    local room
    if anchorPoint == "LEFT" then
        local a, e = anchorFrame:GetRight(), stockPane:GetRight()
        room = a and e and e - PANE_PAD - a - EX
    else
        local a, e = anchorFrame:GetLeft(), stockPane:GetLeft()
        room = a and e and a - EX - e - PANE_PAD
    end
    CapLines(d, room, anchorPoint)
end

-- Weapon slots stack their lines from the top: the stats, the dps, then the
-- enchant, a line moving up when the one above it is empty. Beside a slot
-- the first line sits where retail's item level does (at the slot's centre
-- under Blizz Default) and the enchant keeps its retail spot unless the dps
-- line pushes it down; below the middle weapon slot the lines stack centred
-- under it, stats and dps sharing a row; above it (Blizz Default) they stack
-- upward, ending at its right edge. Re-run after each paint (the lines'
-- contents and heights decide the stack).
local LINE = 13
local function StackWeaponText(d, anchorFrame)
    local stats, dps, ench = d.stats, d.dps, d.ench
    stats:ClearAllPoints()
    dps:ClearAllPoints()
    ench:ClearAllPoints()
    if d.side == "B" then
        -- About 30px sit between the weapon row and the frame's bottom edge:
        -- three lines do not fit, so under the middle slot the stats and the
        -- dps share one row, centred as a pair.
        local topY = -3
        if d.hasStats and d.hasDps then
            local gap = 6
            local wid = stats:GetStringWidth() + gap + dps:GetStringWidth()
            stats:SetPoint("TOPLEFT", anchorFrame, "BOTTOM", -wid / 2, topY)
            dps:SetPoint("LEFT", stats, "RIGHT", gap, 0)
            topY = topY - math.max(stats:GetStringHeight(), dps:GetStringHeight()) - 1
        elseif d.hasStats then
            stats:SetPoint("TOP", anchorFrame, "BOTTOM", 0, topY)
            topY = topY - stats:GetStringHeight() - 1
        elseif d.hasDps then
            dps:SetPoint("TOP", anchorFrame, "BOTTOM", 0, topY)
            topY = topY - dps:GetStringHeight() - 1
        end
        ench:SetPoint("TOP", anchorFrame, "BOTTOM", 0, topY)
        ench:SetJustifyH("CENTER")
        return
    end
    if d.side == "T" then
        -- The enchant nearest the slot, then the dps, then the stats. The
        -- columns' bottom slots keep their inner lines within their own
        -- height, level with these, so the stack starts at those slots' top,
        -- else just past the bronze frame. Each line ends at the slot's right
        -- edge and runs left into the band beside the shirt and tabard (which
        -- carry no text), capped at the left column's text edge: a centred
        -- stack or a shared stats and dps row would run into the right
        -- column's text.
        local posY = SLOT_FRAME + 2
        local column, topY = _G.CharacterWristSlot, anchorFrame:GetTop()
        local colTop = column and column:GetTop()
        if topY and colTop and colTop - topY + 2 > posY then
            posY = colTop - topY + 2
        end
        local right, colRight = anchorFrame:GetRight(), column and column:GetRight()
        CapLines(d, right and colRight and right - colRight - EX, "RIGHT")
        ench:SetJustifyH("RIGHT")
        if d.hasEnch then
            ench:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, posY)
            posY = posY + ench:GetStringHeight() + 1
        end
        if d.hasDps then
            dps:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, posY)
            posY = posY + dps:GetStringHeight() + 1
        end
        if d.hasStats then
            stats:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, posY)
        end
        return
    end
    local anchorPoint, rel, posX = "LEFT", "RIGHT", EX
    if d.side == "L" then
        anchorPoint, rel, posX = "RIGHT", "LEFT", -EX
    end
    if stockPane then
        CapToPane(d, anchorFrame, anchorPoint)
    end
    local posY = WY
    if d.hasStats then
        stats:SetPoint(anchorPoint, anchorFrame, rel, posX, posY)
        posY = posY - LINE
    end
    if d.hasDps then
        dps:SetPoint(anchorPoint, anchorFrame, rel, posX, posY)
        posY = posY - LINE
    end
    ench:SetPoint(anchorPoint, anchorFrame, rel, posX, math.min(posY, -3) - 2)
    ench:SetJustifyH(anchorPoint)
end

-- The stats off the slot's edge where retail's item level sits, the
-- enchant under them hugging the slot.
local function PlaceText(d, anchorFrame)
    if d.dps then
        return StackWeaponText(d, anchorFrame)
    end
    local stats, ench = d.stats, d.ench
    stats:ClearAllPoints()
    ench:ClearAllPoints()
    if d.side == "R" then
        stats:SetPoint("LEFT", anchorFrame, "RIGHT", EX, 10)
        ench:SetPoint("LEFT", anchorFrame, "RIGHT", EX, -5)
        ench:SetJustifyH("LEFT")
    else
        stats:SetPoint("RIGHT", anchorFrame, "LEFT", -EX, 10)
        ench:SetPoint("RIGHT", anchorFrame, "LEFT", -EX, -5)
        ench:SetJustifyH("RIGHT")
    end
end

-- One slot's text. Runs from Blizzard's per-slot update (only while the
-- slots are shown), from the options refreshers and from item data landing.
local function PaintSlotText(slotIndex)
    local d = FFD[slotIndex]
    local stats = d and d.stats
    if not stats then
        return
    end
    -- The ranged text sits past the ammo slot while that shows (checked
    -- ahead of the memo: the ammo slot comes and goes with the class).
    local ammo = d.ammo
    if ammo then
        local anchorFrame = ammo:IsShown() and ammo or slotIndex
        if d.anchor ~= anchorFrame then
            d.anchor = anchorFrame
            PlaceText(d, anchorFrame)
        end
    end
    -- Memo: the equipped link and the settings version are every input.
    local slotID = slotIndex:GetID()
    local itemLink = GetInventoryItemLink("player", slotID)
    if d.paintLink == itemLink and d.paintVer == textVer then
        return
    end
    d.paintLink, d.paintVer = itemLink, textVer
    local position = d.idx
    if pending[position] then
        pending[position] = nil
        pendingN = pendingN - 1
        if pendingN == 0 then
            itemWatch:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        end
    end
    if d.fontVer ~= textVer then
        ApplyLabelFonts(d)
    end
    local ench = d.ench
    local itemId = itemLink and GetInventoryItemID("player", slotID)
    if not (itemId and C_Item.IsItemDataCachedByID(itemId)) then
        stats:SetText("")
        ench:SetText("")
        if d.dps then
            d.dps:SetText("")
        end
        if itemId then
            -- Not cached yet: one repaint when it lands, watched only while
            -- the slot shows (and ahead of the request, whose answer can
            -- come at once); a hidden one repaints on its next show.
            if slotIndex:IsVisible() then
                pending[position] = itemId
                pendingN = pendingN + 1
                itemWatch:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            else
                d.paintLink = nil
            end
            C_Item.RequestLoadItemDataByID(itemId)
        end
        return
    end

    -- The item's colour as retail colours its item level: the custom colour,
    -- else the item's quality (unless turned off), else white.
    local r, g, b = 1, 1, 1
    local custom = SavedDB("charSheetItemLevelUseColor") and SavedDB("charSheetItemLevelColor")
    if custom then
        r, g, b = custom.r, custom.g, custom.b
    elseif SavedDB("charSheetColorItemLevel") ~= false then
        local qr, qg, qb = QualityColor(slotIndex)
        if qr then
            r, g, b = qr, qg, qb
        end
    end

    -- The upgrade track's key and colour override: the item's stats (or its
    -- armor), else in the item's colour.
    -- A weapon's damage per second rides the same key and colour.
    local showStats = SavedDB("showUpgradeTrack") ~= false
    local statText = showStats and StatText(itemLink) or ""
    stats:SetText(statText)
    local sc = SavedDB("charSheetUpgradeTrackUseColor") and SavedDB("charSheetUpgradeTrackColor")
    local sr, sg, scrollBar = r, g, b
    if sc then
        sr, sg, scrollBar = sc.r, sc.g, sc.b
    end
    stats:SetTextColor(sr, sg, scrollBar, 0.8)
    local dps = d.dps
    if dps then
        local dpsText = showStats and DpsText(itemLink) or ""
        dps:SetText(dpsText)
        dps:SetTextColor(sr, sg, scrollBar, 0.8)
        d.hasStats, d.hasDps = statText ~= "", dpsText ~= ""
    end

    -- Vanilla enchants carry no icon, so the name always shows; Enchants set
    -- to Colored Text gives it retail's name look (outlined, tinted from the
    -- item's colour). Capped at 45% of the gap between the columns, as on
    -- retail, less Blizz Default's extra inset on each side (so the two
    -- columns' enchants keep a gap in the middle).
    local name = SavedDB("showEnchants") ~= false and EnchantName(slotID) or ""
    ench:SetText(name)
    if name ~= "" then
        local dim = SavedDB("charSheetEnchantSize") or 9
        if SavedDB("charSheetEnchantNames") then
            ench:SetFont(FontPath(), dim, CludesUI.SlugFlag("OUTLINE, SLUG"))
            ench:SetTextColor(r + (1 - r) * 0.5, g + (1 - g) * 0.5, b + (1 - b) * 0.5, 0.9)
        else
            ench:SetFont(FontPath(), dim, "")
            ench:SetTextColor(1, 1, 1, 0.8)
        end
        local head, hands = _G.CharacterHeadSlot, _G.CharacterHandsSlot
        local lr, rl = head and head:GetRight(), hands and hands:GetLeft()
        ench:SetWidth((lr and rl and rl > lr) and (rl - lr - 2 * (EX - EX_LOOK)) * 0.45 or 0)
    end
    if dps then
        d.hasEnch = name ~= ""
        StackWeaponText(d, d.anchor)
    end
end

-- The slots went away (tab, pet view, close): nothing waits any more; a
-- slot that was waiting repaints on its next show.
local function ClearPending()
    if pendingN == 0 then
        return
    end
    for i = 1, #SLOTS do
        if pending[i] then
            pending[i] = nil
            local d = FFD[_G[SLOTS[i]]]
            if d then
                d.paintLink = nil
            end
        end
    end
    pendingN = 0
    itemWatch:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end

-- Item data landed: one repaint per waiting slot. A failed load is not
-- asked for again (no retry loop); that slot stays blank until its item or
-- a setting changes.
local function OnItemInfo(_, _, itemId, success)
    for i = 1, #SLOTS do
        if pending[i] == itemId then
            pending[i] = nil
            pendingN = pendingN - 1
            if success then
                local slotIndex = _G[SLOTS[i]]
                local d = FFD[slotIndex]
                if d then
                    d.paintLink = nil
                end
                PaintSlotText(slotIndex)
            end
        end
    end
    if pendingN == 0 then
        itemWatch:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end

local slotOverlay -- every slot's text; the eyeball fades it

local function BuildSlotText()
    local hostRegion = _G.PaperDollItemsFrame
    if not hostRegion or itemWatch then
        return
    end
    -- Blizz Default: the text goes past Blizzard's bronze slot frames.
    local fv = mod.CharSheetForever()
    if fv then
        EX, WY = SLOT_FRAME + 4, 0
        stockPane = _G.CharacterFrame and _G.CharacterFrame.LeftPaneHost
    end
    itemWatch = CreateFrame("Frame")
    itemWatch:SetScript("OnEvent", OnItemInfo)
    -- A child of the slots' own frame, so it goes with them (other tabs, the
    -- pet view); above the model scene, below the slot buttons.
    local overlayFrame = CreateFrame("Frame", nil, hostRegion)
    slotOverlay = overlayFrame
    overlayFrame:SetAllPoints(hostRegion)
    local scene = _G.CharacterModelScene
    overlayFrame:SetFrameLevel((scene and scene:GetFrameLevel() or 50) + 10)
    local ranged = _G.CharacterRangedSlot
    local rangedShown = ranged and ranged:IsShown()
    local filePath = FontPath()
    for i = 1, #SLOTS do
        local name = SLOTS[i]
        local sideName, slotIndex = TEXT_SIDE[name], _G[name]
        if sideName and slotIndex then
            -- Without a ranged slot the off hand is the outer one on the
            -- right; under Blizz Default the middle one's text goes above
            -- it.
            if sideName == "B" then
                if not rangedShown then
                    sideName = "R"
                elseif fv then
                    sideName = "T"
                end
            end
            local d = GetFFD(slotIndex)
            d.idx, d.side, d.anchor = i, sideName, slotIndex
            -- One line each: a capped width (Blizz Default) cuts the
            -- text short rather than wrapping it into the frames around.
            d.stats = overlayFrame:CreateFontString(nil, "OVERLAY")
            d.stats:SetWordWrap(false)
            if WEAPON_SLOT[name] then
                d.dps = overlayFrame:CreateFontString(nil, "OVERLAY")
                d.dps:SetWordWrap(false)
            end
            d.ench = overlayFrame:CreateFontString(nil, "OVERLAY")
            d.ench:SetFont(filePath, SavedDB("charSheetEnchantSize") or 9, "")
            d.ench:SetWordWrap(false)
            ApplyLabelFonts(d)
            if slotIndex == ranged then
                d.ammo = _G.CharacterAmmoSlot
            end
            PlaceText(d, slotIndex)
        end
    end
    hostRegion:HookScript("OnHide", ClearPending)
    -- A first open that skinned the sheet (or, under Blizz Default, the
    -- slots' first show) has already had Blizzard's update.
    for i = 1, #SLOTS do
        local slotIndex = _G[SLOTS[i]]
        if slotIndex and slotIndex:IsVisible() then
            PaintSlotText(slotIndex)
        end
    end
end

-- Options refreshers: the retail slot text setters (the track key shown
-- here as Show Item Stats, Enchants and its cog, the Fonts page's Enchant
-- Text Size) land here; the retail versions walk retail-only state.
-- The version bump feeds every setting into the paint memo, so a hidden
-- sheet repaints on its next show.
local function RefreshSlotText()
    textVer = textVer + 1
    if not TextEnabled() then
        return
    end
    for i = 1, #SLOTS do
        local slotIndex = _G[SLOTS[i]]
        if slotIndex and slotIndex:IsVisible() then
            PaintSlotText(slotIndex)
        end
    end
end
CludesUI._refreshItemLevelVisibility = RefreshSlotText
CludesUI._refreshUpgradeTrackVisibility = RefreshSlotText
CludesUI._refreshEnchantsVisibility = RefreshSlotText
CludesUI._refreshCharSheetSlotLabels = RefreshSlotText
CludesUI._applyCharSheetTextSizes = RefreshSlotText

-- Blizzard refreshes every shown slot through this on equipment changes and
-- on show; the border and the slot text follow. Foreign item buttons (bags)
-- have no entry.
local function OnSlotUpdate(slotIndex)
    local d = FFD[slotIndex]
    if not d then
        return
    end
    if d.border then
        ColorSlotBorder(slotIndex)
    end
    if d.stats then
        PaintSlotText(slotIndex)
    end
end

-- Both looks follow that update through one hook, installed once.
local slotHooked = false
local function HookSlotUpdates()
    if slotHooked or type(_G.PaperDollItemSlotButton_Update) ~= "function" then
        return
    end
    slotHooked = true
    hooksecurefunc("PaperDollItemSlotButton_Update", OnSlotUpdate)
end

local function SkinSlot(slotName, Fade)
    local slotIndex = _G[slotName]
    if not slotIndex or GetFFD(slotIndex).done then
        return
    end
    GetFFD(slotIndex).done = true
    -- The bronze slot frame lives on a child frame; the button art is the
    -- named NormalTexture (hidden, not faded: the client rewrites its vertex
    -- colour, and with it the alpha, on every item update).
    if slotIndex.BorderFrame then
        Fade(slotIndex.BorderFrame)
    else
        -- The ammo slot is built without that child: its ring is an atlas
        -- texture on the button itself. The arrow pointing at the ranged slot
        -- (an unnamed child frame of its own) stays.
        local regions = { slotIndex:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r.GetAtlas and r:GetAtlas() == "UI-Character-Info-GearSlotSmall" then
                r:SetAlpha(0)
            end
        end
    end
    local normal = _G[slotName .. "NormalTexture"]
    if normal then
        normal:Hide()
    end
    -- Blizzard's quality ring gets re-shown and recoloured on every item
    -- update, so it is collapsed onto one blank texel instead of hidden.
    if slotIndex.IconBorder then
        slotIndex.IconBorder:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    end
    -- The item icon is the button's own; the ammo slot also declares a
    -- legacy texture under the same global name, which is not it.
    local glyph = slotIndex.icon or _G[slotName .. "IconTexture"]
    if glyph then
        local z = Zoom()
        glyph:SetTexCoord(z, 1 - z, z, 1 - z)
    end
    local backdrop = slotIndex:CreateTexture(nil, "BACKGROUND", nil, -5)
    backdrop:SetAllPoints(slotIndex)
    backdrop:SetColorTexture(0.5, 0.5, 0.5, 0.7)
    GetFFD(slotIndex).bg = backdrop
    local PanelPP = CludesUI.PanelPP
    if PanelPP and PanelPP.CreateBorder then
        PanelPP.CreateBorder(slotIndex, 0.4, 0.4, 0.4, 1, 2, "OVERLAY", 1)
        local borders = PanelPP.GetBorders and PanelPP.GetBorders(slotIndex)
        if borders then
            borders:SetFrameLevel(slotIndex:GetFrameLevel())
        end
        GetFFD(slotIndex).border = true
        ColorSlotBorder(slotIndex)
    end
end

-- Options-page refresh: the Icon Zoom slider lands here (the retail sheet's
-- own refresher is replaced, it walks the retail slot list).
function CludesUI._refreshCharSheetIconZoom()
    if not Enabled() then
        return
    end
    local z = Zoom()
    for i = 1, #SLOTS do
        local slotIndex = _G[SLOTS[i]]
        if slotIndex and FFD[slotIndex] and FFD[slotIndex].done then
            local glyph = slotIndex.icon or _G[SLOTS[i] .. "IconTexture"]
            if glyph then
                glyph:SetTexCoord(z, 1 - z, z, 1 - z)
            end
        end
    end
end

--------------------------------------------------------------------------------
--  The model backdrop and the sidebar panel, as on retail
--------------------------------------------------------------------------------
local IMG_ASPECT = 787 / 1030 -- character-bg.png

-- Cover crop: the image keeps its aspect and the box shows its centre.
local function CoverCrop(texture, wid, hgt)
    if issecretvalue and (issecretvalue(wid) or issecretvalue(hgt)) then
        return
    end
    if not wid or not hgt or wid <= 0 or hgt <= 0 then
        return
    end
    local boxFrame = wid / hgt
    if boxFrame > IMG_ASPECT then
        local trim = (1 - IMG_ASPECT / boxFrame) / 2
        texture:SetTexCoord(0, 1, trim, 1 - trim)
    else
        local trim = (1 - boxFrame / IMG_ASPECT) / 2
        texture:SetTexCoord(trim, 1 - trim, 0, 1)
    end
end

-- Both panels draw above the shell's top bar (children of the frame render
-- over its own textures), so their top edge is pinned to the bar's bottom:
-- flush under it, never over it, no gap of bare backdrop between.
local function PinTop(regionFrame, topBar, fallback)
    if topBar then
        regionFrame:SetPoint("TOP", topBar, "BOTTOM", 0, 0)
    else
        regionFrame:SetPoint("TOP", fallback, "TOP", 0, 0)
    end
end

local function ModelBackdrop(widget, topBar)
    local scene = _G.CharacterModelScene
    local doll = _G.PaperDollFrame
    if not (scene and doll) or GetFFD(widget).modelBg then
        return
    end
    -- Under the paper doll so it comes and goes with that tab; one level
    -- under the scene so the character renders over it.
    local hostRegion = CreateFrame("Frame", nil, doll)
    PinTop(hostRegion, topBar, scene)
    hostRegion:SetPoint("LEFT", scene, "LEFT", 0, 0)
    hostRegion:SetPoint("RIGHT", scene, "RIGHT", 0, 0)
    hostRegion:SetPoint("BOTTOM", scene, "BOTTOM", 0, 0)
    hostRegion:SetFrameLevel(math.max(0, scene:GetFrameLevel() - 1))
    local texture = hostRegion:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(hostRegion)
    texture:SetTexture(MEDIA .. "character-bg.png")
    hostRegion:SetScript("OnSizeChanged", function(_, wid, hgt)
        CoverCrop(texture, wid, hgt)
    end)
    CoverCrop(texture, hostRegion:GetSize())
    GetFFD(widget).modelBg = hostRegion
end

local function SidebarPanel(widget, topBar)
    local hostRegion = widget.RightPaneHost
    if not hostRegion or GetFFD(widget).sidebar then
        return
    end
    -- A child of the pane host so it collapses with it, at the host's own
    -- level so every list and scrollbar draws over it.
    local panelFrame = CreateFrame("Frame", nil, hostRegion)
    panelFrame:SetFrameLevel(hostRegion:GetFrameLevel())
    PinTop(panelFrame, topBar, hostRegion)
    panelFrame:SetPoint("LEFT", hostRegion, "LEFT", 0, 0)
    panelFrame:SetPoint("RIGHT", hostRegion, "RIGHT", -6, 0)
    panelFrame:SetPoint("BOTTOM", hostRegion, "BOTTOM", 0, 8)
    local texture = panelFrame:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(panelFrame)
    texture:SetColorTexture(0, 0, 0, 0.2)
    GetFFD(widget).sidebar = panelFrame
end

local function SkinFrame()
    local widget = _G.CharacterFrame
    local Skin = mod.WSkin
    if not (widget and Skin and Skin.Shell) then
        return false
    end
    local Fade = Skin.FadeRegions
    if not Fade then
        return false
    end
    local d = GetFFD(widget)
    if d.done then
        return true
    end
    d.done = true

    -- The ordinary window treatment: shell, border, top bar, house close
    -- button, title centred on the bar. explicitControls keeps the engine
    -- away from the stats scrollbar, which stays Blizzard's.
    Skin.Shell("charsheet", widget)
    if Skin.CommonChrome then
        Skin.CommonChrome(widget, "CharacterFrame", true)
    end
    if Skin.RemovePortrait then
        Skin.RemovePortrait(widget)
    end

    -- The right-pane collapse arrow goes. The pane it toggles is kept open:
    -- with the arrow gone a sheet collapsed from an earlier session (the
    -- state is a cvar, read once at load) could never be opened again.
    Discard(widget.RightPaneToggleButton)
    if widget.IsRightPaneCollapsed and widget.SetRightPaneCollapsed then
        widget:HookScript("OnShow", function(self)
            if self:IsRightPaneCollapsed() then
                self:SetRightPaneCollapsed(false)
            end
        end)
    end

    -- Name in the top bar and the level lines (the player's and the pet
    -- view's): the house font on Blizzard's own font strings, so the text
    -- (pvp title, class colour) stays theirs.
    local titleText = _G.CharacterFrameTitleText
        or (widget.TitleContainer and widget.TitleContainer.TitleText)
    if titleText and Skin.Font then
        Skin.Font(titleText, 1, 1, 1)
    end
    local level = _G.CharacterLevelText
    if level and Skin.Font then
        Skin.Font(level)
    end
    local petLevel = _G.PetCharacterLevelText
    if petLevel and Skin.Font then
        Skin.Font(petLevel)
    end

    -- Pane backdrops, the stone header, the divider strip, the stats box
    -- chrome (inside frame, scroll line, class crest) and the model backdrop.
    Fade(widget.LeftPaneHost)
    Fade(widget.RightPaneHost)
    FadeChildren(widget.RightPaneHost, function(childFrame)
        -- The stats and pet lists are children too; their chrome goes, their
        -- rows and scrollbars are handled by the element callback and kept.
        if
            childFrame ~= _G.CharacterStatsPaneScrollBox
            and childFrame ~= _G.CharacterStatsPanePetScrollBox
        then
            Fade(childFrame)
        end
    end)
    if widget.RightPaneHost and widget.RightPaneHost.StoneBg then
        widget.RightPaneHost.StoneBg:SetAlpha(0)
    end
    Fade(_G.CharacterStatsPaneScrollBox)
    Fade(_G.CharacterStatsPanePetScrollBox)
    Fade(_G.PaperDollFrame)
    Fade(_G.PaperDollFrame.TopBackgroundStripHost)
    Fade(_G.CharacterModelScene)
    local shell = Skin.GetFFD and Skin.GetFFD(widget)
    local topBar = shell and shell.topBar
    ModelBackdrop(widget, topBar)
    SidebarPanel(widget, topBar)

    -- Item slots: frames off, icons cropped, a grey square and a quality
    -- border on each, and the slot text beside them; both follow Blizzard's
    -- own slot refresh.
    for i = 1, #SLOTS do
        SkinSlot(SLOTS[i], Fade)
    end
    BuildSlotText()
    -- Top-left eyeball, as on retail: hides every slot's text for the
    -- session by fading their shared overlay.
    if slotOverlay and not d.eyeBtn then
        local EYE_VISIBLE, EYE_INVISIBLE = CludesUI.EYE_VISIBLE_ICON, CludesUI.EYE_INVISIBLE_ICON
        local hidden = false
        -- On the slots' own frame: it goes with the slot text (other tabs,
        -- the pet view) and sits above the mouse-enabled model scene, which
        -- reaches up under the button's lower edge.
        local itemList = slotOverlay:GetParent()
        local eyeBtn = CreateFrame("Button", nil, itemList)
        eyeBtn:SetSize(20, 20)
        eyeBtn:SetPoint("TOPLEFT", widget, "TOPLEFT", 14, -6)
        eyeBtn:SetFrameLevel(itemList:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        eyeTex:SetTexture(EYE_VISIBLE)
        eyeBtn:SetScript("OnClick", function(self)
            hidden = not hidden
            eyeTex:SetTexture(hidden and EYE_INVISIBLE or EYE_VISIBLE)
            slotOverlay:SetAlpha(hidden and 0 or 1)
            CludesUI.ShowWidgetTooltip(self, hidden and "Show Item Text" or "Hide Item Text", { width = 135 })
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.8)
            CludesUI.ShowWidgetTooltip(self, hidden and "Show Item Text" or "Hide Item Text", { width = 135 })
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            CludesUI.HideWidgetTooltip()
        end)
        d.eyeBtn = eyeBtn
    end
    HookSlotUpdates()

    -- Stats list colours.
    HookStatsList(_G.CharacterStatsPaneScrollBox)
    HookStatsList(_G.CharacterStatsPanePetScrollBox)

    -- The stats scrollbars: the house thin thumb in Blizzard's own track
    -- position, the up/down arrows left as they are. Texture work only, the
    -- bar keeps its scripts and its mouse handling.
    if Skin.ScrollBar then
        local stats = _G.CharacterStatsPaneScrollBox
        if stats and stats.ScrollBar then
            Skin.ScrollBar(stats.ScrollBar, true)
        end
        local pet = _G.CharacterStatsPanePetScrollBox
        if pet and pet.ScrollBar then
            Skin.ScrollBar(pet.ScrollBar, true)
        end
    end
    return true
end

-- Blizz Default: the slot text alone, built at the slots' first show;
-- every later show returns at once.
local function BuildStockText()
    if itemWatch then
        return
    end
    BuildSlotText()
    HookSlotUpdates()
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not _G.CharacterFrame then
        return
    end
    if Enabled() then
        if not SkinFrame() then
            -- The engine loads after this addon's own files; one retry on the
            -- first open covers a late shell.
            _G.CharacterFrame:HookScript("OnShow", function()
                SkinFrame()
            end)
        end
    elseif TextEnabled() and _G.PaperDollItemsFrame then
        _G.PaperDollItemsFrame:HookScript("OnShow", BuildStockText)
    end
end)
