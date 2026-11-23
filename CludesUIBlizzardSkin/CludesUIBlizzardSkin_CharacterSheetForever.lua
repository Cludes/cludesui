if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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
local CUI = _G.CludesUI
if not (CUI and CUI.IS_FOREVER) then return end

local FFD, GetFFD = CUI.NewFrameData()

-- The Character Sheet card's Off and the window skins kill switch, which
-- stop both looks (as they stop the retail sheet's).
local function SheetOn()
    if not CludesUIDB then return true end
    if CludesUIDB.themedCharacterSheet == false then return false end
    return not CUI.BlizzWindowSkinsKilled()
end

-- The CludesUI look (the card's style is latched at login, so a change
-- lands at the reload).
local function Enabled() return not mod.CharSheetStock() and SheetOn() end

-- The slot text: both looks.
local function TextEnabled() return SheetOn() end

local function FontPath() return (CUI.GetFontPath("blizzardSkin")) or STANDARD_TEXT_FONT end

local MEDIA = "Interface\\AddOns\\CludesUIBlizzardSkin\\Media\\"

-- The retail sheet's Icon Zoom setting (same key, same default).
local function Zoom() return (CludesUIDB and CludesUIDB.charSheetIconZoom) or 0.07 end

-- Blizzard pieces that must go for good are parked under a hidden frame:
-- Hide() gets undone by the client's own refreshes, a hidden parent does not.
local Bin
local function Discard(regionFrame)
    if not regionFrame or not regionFrame.SetParent then return end
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
if STAT_CATEGORY_GENERAL then CATEGORY_KEY[STAT_CATEGORY_GENERAL] = "General" end
if STAT_CATEGORY_PRIMARY_ATTRIBUTES then CATEGORY_KEY[STAT_CATEGORY_PRIMARY_ATTRIBUTES] = "Attributes" end
if STAT_CATEGORY_WEAPONS then CATEGORY_KEY[STAT_CATEGORY_WEAPONS] = "Attack" end
if STAT_CATEGORY_MODIFIERS then CATEGORY_KEY[STAT_CATEGORY_MODIFIERS] = "Secondary Stats" end
if STAT_CATEGORY_DEFENSE then CATEGORY_KEY[STAT_CATEGORY_DEFENSE] = "Defense" end
if STAT_CATEGORY_COMBAT then CATEGORY_KEY[STAT_CATEGORY_COMBAT] = "Attack" end

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
    local color = custom or (key and DEFAULT_COLORS[key])
    if color and color.r then return color.r, color.g, color.b end
    local ACC = CUI.CLUDES_GREEN
    if ACC then return ACC.r, ACC.g, ACC.b end
    return 1, 1, 1
end

-- The category a stat element belongs to: the data provider lists a header
-- then its rows, so it is the last header ahead of the element.
local function CategoryOf(box, elementData)
    local entries = box and box.elementData
    if type(entries) ~= "table" then return nil end
    local current
    for i = 1, #entries do
        local skinData = entries[i]
        if skinData.isHeader then current = skinData.name end
        if skinData == elementData then return current end
    end
    return current
end

--------------------------------------------------------------------------------
--  Stats list elements
--------------------------------------------------------------------------------
local function OnePixel(widget)
    local Pix = CUI.PP
    local perfect = (Pix and Pix.perfect) or 1
    local es = widget:GetEffectiveScale()
    if not es or es <= 0 then es = 1 end
    return perfect / es
end

local function SkinHeader(widget, red, green, blue)
    local skinData = GetFFD(widget)
    if not skinData.done then
        skinData.done = true
        if widget.Background then widget.Background:SetAlpha(0) end
        if widget.Title then widget.Title:SetFont(FontPath(), 11, "") end
        local leftBar = widget:CreateTexture(nil, "ARTWORK")
        leftBar:SetPoint("LEFT", widget, "LEFT", 8, 0)
        leftBar:SetPoint("RIGHT", widget.Title, "LEFT", -6, 0)
        skinData.leftBar = leftBar
        local rightBar = widget:CreateTexture(nil, "ARTWORK")
        rightBar:SetPoint("LEFT", widget.Title, "RIGHT", 6, 0)
        rightBar:SetPoint("RIGHT", widget, "RIGHT", -8, 0)
        skinData.rightBar = rightBar
    end
    if widget.Title then widget.Title:SetTextColor(red, green, blue, 1) end
    local pixel = OnePixel(widget)
    skinData.leftBar:SetColorTexture(red, green, blue, 0.8)
    skinData.rightBar:SetColorTexture(red, green, blue, 0.8)
    skinData.leftBar:SetHeight(pixel)
    skinData.rightBar:SetHeight(pixel)
end

local function SkinRow(widget, red, green, blue)
    local skinData = GetFFD(widget)
    if not skinData.done then
        skinData.done = true
        if widget.Background then widget.Background:SetAlpha(0) end
        if widget.Label then widget.Label:SetFont(FontPath(), 10, "") end
        if widget.Value then widget.Value:SetFont(FontPath(), 10, "") end
        -- The retail rows carry a faint divider under each line.
        local divider = widget:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(1, 1, 1, 0.06)
        divider:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 8, 0)
        divider:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -8, 0)
        divider:SetHeight(OnePixel(widget))
        skinData.divider = divider
    end
    if widget.Label then widget.Label:SetTextColor(0.7, 0.7, 0.7, 0.8) end
    if widget.Value then widget.Value:SetTextColor(red, green, blue, 1) end
end

local function SkinElement(box, widget, elementData)
    if not widget or not elementData then return end
    if elementData.isHeader then
        SkinHeader(widget, CategoryColor(elementData.name))
    else
        SkinRow(widget, CategoryColor(CategoryOf(box, elementData)))
    end
end

local function HookStatsList(box)
    if not box or not box.ScrollBox or GetFFD(box).hooked then return end
    GetFFD(box).hooked = true
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        -- The event hands (owner, frame, elementData); the helper's own
        -- iterateExisting pass hands (frame, elementData) instead, so the
        -- frames already alive are walked separately below.
        ScrollUtil.AddInitializedFrameCallback(
            box.ScrollBox,
            function(_, widget, elementData) SkinElement(box, widget, elementData) end,
            nil,
            false
        )
        if box.ScrollBox.ForEachFrame then
            box.ScrollBox:ForEachFrame(
                function(widget, elementData) SkinElement(box, widget, elementData) end
            )
        end
    end
end

-- Options-page refresh: colour overrides and their use flags land here, on
-- the frames alive in both lists. The retail sheet's refresher of the same
-- name is replaced (it walks retail-only state), so the swatches reach this.
local STAT_BOXES = { "CharacterStatsPaneScrollBox", "CharacterStatsPanePetScrollBox" }
function CUI._refreshCharacterSheetColors()
    if not Enabled() then return end
    for i = 1, #STAT_BOXES do
        local box = _G[STAT_BOXES[i]]
        if box and box.ScrollBox and box.ScrollBox.ForEachFrame then
            box.ScrollBox:ForEachFrame(
                function(widget, elementData) SkinElement(box, widget, elementData) end
            )
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
    if not widget then return end
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
local function QualityColor(slot)
    local quality = GetInventoryItemQuality("player", slot:GetID())
    if quality and not (issecretvalue and issecretvalue(quality)) then
        local red, green, blue
        if C_Item and C_Item.GetItemQualityColor then
            red, green, blue = C_Item.GetItemQualityColor(quality)
        elseif GetItemQualityColor then
            red, green, blue = GetItemQualityColor(quality)
        end
        if red then return red, green, blue end
    end
end

-- The slot border colour: the equipped item's quality, dark grey when empty
-- (the retail sheet's values).
local function SlotBorderColor(slot)
    local red, green, blue = QualityColor(slot)
    if red then return red, green, blue end
    return 0.4, 0.4, 0.4
end

local function ColorSlotBorder(slot)
    local PanelPP = CUI.PanelPP
    if not (PanelPP and PanelPP.SetBorderColor) then return end
    local red, green, blue = SlotBorderColor(slot)
    PanelPP.SetBorderColor(slot, red, green, blue, 1)
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
-- The slots Group Inspect checks for a permanent enchant (by slot ID): chest,
-- legs, feet, wrists, hands, back, main hand. An empty one says "No enchant".
local ENCHANTABLE = { [5] = true, [7] = true, [8] = true, [9] = true, [10] = true, [15] = true, [16] = true }

-- C_Item.GetItemStats keys in tie order (an earlier key wins a tie), with our
-- own short labels. Main stat: the largest of the first three (the
-- primaries), else of the next two (Stamina, Spirit). Secondary: the largest
-- of every other listed key. Armor, shield block value, weapon damage,
-- sockets and any unlisted key never show. Built on first use, once the
-- locale catalog is active.
local STAT_LIST
local function StatList()
    if STAT_LIST then return STAT_LIST end
    local crit, hit = CUI.L("Crit"), CUI.L("Hit")
    local mp5, hp5 = CUI.L("MP5"), CUI.L("HP5")
    STAT_LIST = {
        { "ITEM_MOD_STRENGTH_SHORT", CUI.L("Str") },
        { "ITEM_MOD_AGILITY_SHORT", CUI.L("Agi") },
        { "ITEM_MOD_INTELLECT_SHORT", CUI.L("Int") },
        { "ITEM_MOD_STAMINA_SHORT", CUI.L("Stam") },
        { "ITEM_MOD_SPIRIT_SHORT", CUI.L("Spi") },
        { "ITEM_MOD_ATTACK_POWER_SHORT", CUI.L("AP") },
        { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", CUI.L("RAP") },
        { "ITEM_MOD_SPELL_POWER_SHORT", CUI.L("SP") },
        { "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", CUI.L("Spell Dmg") },
        { "ITEM_MOD_SPELL_HEALING_DONE_SHORT", CUI.L("Heal") },
        { "ITEM_MOD_CRIT_RATING_SHORT", crit },
        { "ITEM_MOD_CRIT_MELEE_RATING_SHORT", crit },
        { "ITEM_MOD_CRIT_RANGED_RATING_SHORT", crit },
        { "ITEM_MOD_CRIT_SPELL_RATING_SHORT", CUI.L("Spell Crit") },
        { "ITEM_MOD_HIT_RATING_SHORT", hit },
        { "ITEM_MOD_HIT_MELEE_RATING_SHORT", hit },
        { "ITEM_MOD_HIT_RANGED_RATING_SHORT", hit },
        { "ITEM_MOD_HIT_SPELL_RATING_SHORT", CUI.L("Spell Hit") },
        { "ITEM_MOD_HASTE_RATING_SHORT", CUI.L("Haste") },
        { "ITEM_MOD_MANA_REGENERATION_SHORT", mp5 },
        { "ITEM_MOD_POWER_REGEN0_SHORT", mp5 },
        { "ITEM_MOD_HEALTH_REGEN_SHORT", hp5 },
        { "ITEM_MOD_HEALTH_REGENERATION_SHORT", hp5 },
        { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", CUI.L("Def") },
        { "ITEM_MOD_DODGE_RATING_SHORT", CUI.L("Dodge") },
        { "ITEM_MOD_PARRY_RATING_SHORT", CUI.L("Parry") },
        { "ITEM_MOD_BLOCK_RATING_SHORT", CUI.L("Block") },
        { "ITEM_MOD_SPELL_PENETRATION_SHORT", CUI.L("Spell Pen") },
        { "RESISTANCE1_NAME", CUI.L("Holy Res") },
        { "RESISTANCE2_NAME", CUI.L("Fire Res") },
        { "RESISTANCE3_NAME", CUI.L("Nature Res") },
        { "RESISTANCE4_NAME", CUI.L("Frost Res") },
        { "RESISTANCE5_NAME", CUI.L("Shadow Res") },
        { "RESISTANCE6_NAME", CUI.L("Arcane Res") },
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
    if textValue then return textValue end
    local stats = C_Item.GetItemStats(itemLink)
    if not stats then return "" end
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
            armorLabel = armorLabel or CUI.L("Armor")
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
    if textValue then return textValue end
    textValue = ""
    if select(6, C_Item.GetItemInfoInstant(itemLink)) == Enum.ItemClass.Weapon then
        local stats = C_Item.GetItemStats(itemLink)
        if not stats then return "" end
        local dps = stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
        if dps and dps > 0 then
            dpsLabel = dpsLabel or CUI.L("Dps")
            textValue = string.format("%.1f %s", dps, dpsLabel)
        end
    end
    dpsTextCache[itemLink] = textValue
    return textValue
end

local function SavedVal(key)
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
    if textValue == "" then return textValue end
    if ENCHANT_PREFIX and ENCHANT_PREFIX ~= "" and textValue:sub(1, #ENCHANT_PREFIX) == ENCHANT_PREFIX then
        textValue = textValue:sub(#ENCHANT_PREFIX + 1)
    end
    if textValue:find("^%d") then textValue = "+" .. textValue end
    return textValue
end
local function EnchantName(slotID) return mod.ForeverEnchantName(CUI.GetEnchantText(slotID)) end

local textVer = 1 -- bumped by every options refresh
local pending, pendingN = {}, 0 -- SLOTS index -> itemID waiting on item data
local itemWatch -- GET_ITEM_INFO_RECEIVED, registered only while a slot waits

-- The stats font (and the weapon slots' dps line): the retail upgrade
-- track's size, outline and shadow keys. The enchant's font follows its
-- name mode at paint.
local function ApplyLabelFonts(skinData)
    local filePath = FontPath()
    local size = SavedVal("charSheetUpgradeTrackSize") or 11
    local flags = SavedVal("charSheetUpgradeTrackOutline") and CUI.SlugFlag("OUTLINE, SLUG") or ""
    CUI.PrimeFontShadow(skinData.stats, SavedVal("charSheetUpgradeTrackShadow"))
    skinData.stats:SetFont(filePath, size, flags)
    if skinData.dps then
        CUI.PrimeFontShadow(skinData.dps, SavedVal("charSheetUpgradeTrackShadow"))
        skinData.dps:SetFont(filePath, size, flags)
    end
    skinData.fontVer = textVer
end

-- Blizz Default: a weapon slot's lines capped at the room they have
-- (the stats and dps take its width, justified to their anchored side; the
-- enchant shrinks to it when wider), cut short rather than run past it.
local function CapLines(skinData, room, justify)
    if not room or room <= 0 then return end
    skinData.stats:SetWidth(room)
    skinData.stats:SetJustifyH(justify)
    skinData.dps:SetWidth(room)
    skinData.dps:SetJustifyH(justify)
    if skinData.ench:GetWidth() > room then skinData.ench:SetWidth(room) end
end

-- The side weapon lines stop 6px inside the left pane (its frame border on
-- the left, the stats pane's edge on the right: past the ammo slot the
-- ranged text has about 90px).
local PANE_PAD = 6
local function CapToPane(skinData, anchor, anchorPoint)
    local room
    if anchorPoint == "LEFT" then
        local a, e = anchor:GetRight(), stockPane:GetRight()
        room = a and e and e - PANE_PAD - a - EX
    else
        local a, e = anchor:GetLeft(), stockPane:GetLeft()
        room = a and e and a - EX - e - PANE_PAD
    end
    CapLines(skinData, room, anchorPoint)
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
local function StackWeaponText(skinData, anchor)
    local stats, dps, ench = skinData.stats, skinData.dps, skinData.ench
    stats:ClearAllPoints()
    dps:ClearAllPoints()
    ench:ClearAllPoints()
    if skinData.side == "B" then
        -- About 30px sit between the weapon row and the frame's bottom edge:
        -- three lines do not fit, so under the middle slot the stats and the
        -- dps share one row, centred as a pair.
        local topY = -3
        if skinData.hasStats and skinData.hasDps then
            local gap = 6
            local wid = stats:GetStringWidth() + gap + dps:GetStringWidth()
            stats:SetPoint("TOPLEFT", anchor, "BOTTOM", -wid / 2, topY)
            dps:SetPoint("LEFT", stats, "RIGHT", gap, 0)
            topY = topY - math.max(stats:GetStringHeight(), dps:GetStringHeight()) - 1
        elseif skinData.hasStats then
            stats:SetPoint("TOP", anchor, "BOTTOM", 0, topY)
            topY = topY - stats:GetStringHeight() - 1
        elseif skinData.hasDps then
            dps:SetPoint("TOP", anchor, "BOTTOM", 0, topY)
            topY = topY - dps:GetStringHeight() - 1
        end
        ench:SetPoint("TOP", anchor, "BOTTOM", 0, topY)
        ench:SetJustifyH("CENTER")
        return
    end
    if skinData.side == "T" then
        -- The enchant nearest the slot, then the dps, then the stats. The
        -- columns' bottom slots keep their inner lines within their own
        -- height, level with these, so the stack starts at those slots' top,
        -- else just past the bronze frame. Each line ends at the slot's right
        -- edge and runs left into the band beside the shirt and tabard (which
        -- carry no text), capped at the left column's text edge: a centred
        -- stack or a shared stats and dps row would run into the right
        -- column's text.
        local posY = SLOT_FRAME + 2
        local colour, topY = _G.CharacterWristSlot, anchor:GetTop()
        local colTop = colour and colour:GetTop()
        if topY and colTop and colTop - topY + 2 > posY then posY = colTop - topY + 2 end
        local right, colRight = anchor:GetRight(), colour and colour:GetRight()
        CapLines(skinData, right and colRight and right - colRight - EX, "RIGHT")
        ench:SetJustifyH("RIGHT")
        if skinData.hasEnch then
            ench:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, posY)
            posY = posY + ench:GetStringHeight() + 1
        end
        if skinData.hasDps then
            dps:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, posY)
            posY = posY + dps:GetStringHeight() + 1
        end
        if skinData.hasStats then stats:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, posY) end
        return
    end
    local anchorPoint, rel, posX = "LEFT", "RIGHT", EX
    if skinData.side == "L" then
        anchorPoint, rel, posX = "RIGHT", "LEFT", -EX
    end
    if stockPane then CapToPane(skinData, anchor, anchorPoint) end
    local posY = WY
    if skinData.hasStats then
        stats:SetPoint(anchorPoint, anchor, rel, posX, posY)
        posY = posY - LINE
    end
    if skinData.hasDps then
        dps:SetPoint(anchorPoint, anchor, rel, posX, posY)
        posY = posY - LINE
    end
    ench:SetPoint(anchorPoint, anchor, rel, posX, math.min(posY, -3) - 2)
    ench:SetJustifyH(anchorPoint)
end

-- The stats off the slot's edge where retail's item level sits, the
-- enchant under them hugging the slot.
local function PlaceText(skinData, anchor)
    if skinData.dps then return StackWeaponText(skinData, anchor) end
    local stats, ench = skinData.stats, skinData.ench
    stats:ClearAllPoints()
    ench:ClearAllPoints()
    if skinData.side == "R" then
        stats:SetPoint("LEFT", anchor, "RIGHT", EX, 10)
        ench:SetPoint("LEFT", anchor, "RIGHT", EX, -5)
        ench:SetJustifyH("LEFT")
    else
        stats:SetPoint("RIGHT", anchor, "LEFT", -EX, 10)
        ench:SetPoint("RIGHT", anchor, "LEFT", -EX, -5)
        ench:SetJustifyH("RIGHT")
    end
end

-- One slot's text. Runs from Blizzard's per-slot update (only while the
-- slots are shown), from the options refreshers and from item data landing.
local function DrawSlotText(slot)
    local skinData = FFD[slot]
    local stats = skinData and skinData.stats
    if not stats then return end
    -- The ranged text sits past the ammo slot while that shows (checked
    -- ahead of the memo: the ammo slot comes and goes with the class).
    local ammo = skinData.ammo
    if ammo then
        local anchor = ammo:IsShown() and ammo or slot
        if skinData.anchor ~= anchor then
            skinData.anchor = anchor
            PlaceText(skinData, anchor)
        end
    end
    -- Memo: the equipped link and the settings version are every input.
    local slotID = slot:GetID()
    local itemLink = GetInventoryItemLink("player", slotID)
    if skinData.paintLink == itemLink and skinData.paintVer == textVer then return end
    skinData.paintLink, skinData.paintVer = itemLink, textVer
    local position = skinData.idx
    if pending[position] then
        pending[position] = nil
        pendingN = pendingN - 1
        if pendingN == 0 then itemWatch:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
    end
    if skinData.fontVer ~= textVer then ApplyLabelFonts(skinData) end
    local ench = skinData.ench
    local itemId = itemLink and GetInventoryItemID("player", slotID)
    if not (itemId and C_Item.IsItemDataCachedByID(itemId)) then
        stats:SetText("")
        ench:SetText("")
        if skinData.dps then skinData.dps:SetText("") end
        if itemId then
            -- Not cached yet: one repaint when it lands, watched only while
            -- the slot shows (and ahead of the request, whose answer can
            -- come at once); a hidden one repaints on its next show.
            if slot:IsVisible() then
                pending[position] = itemId
                pendingN = pendingN + 1
                itemWatch:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            else
                skinData.paintLink = nil
            end
            C_Item.RequestLoadItemDataByID(itemId)
        end
        return
    end

    -- The item's colour as retail colours its item level: the custom colour,
    -- else the item's quality (unless turned off), else white.
    local red, green, blue = 1, 1, 1
    local custom = SavedVal("charSheetItemLevelUseColor") and SavedVal("charSheetItemLevelColor")
    if custom then
        red, green, blue = custom.r, custom.g, custom.b
    elseif SavedVal("charSheetColorItemLevel") ~= false then
        local qr, qg, qb = QualityColor(slot)
        if qr then
            red, green, blue = qr, qg, qb
        end
    end

    -- The upgrade track's key and colour override: the item's stats (or its
    -- armor), else in the item's colour.
    -- A weapon's damage per second rides the same key and colour.
    local showStats = SavedVal("showUpgradeTrack") ~= false
    local statText = showStats and StatText(itemLink) or ""
    stats:SetText(statText)
    local sc = SavedVal("charSheetUpgradeTrackUseColor") and SavedVal("charSheetUpgradeTrackColor")
    local sr, sg, scrollBar = red, green, blue
    if sc then
        sr, sg, scrollBar = sc.r, sc.g, sc.b
    end
    stats:SetTextColor(sr, sg, scrollBar, 0.8)
    local dps = skinData.dps
    if dps then
        local dpsText = showStats and DpsText(itemLink) or ""
        dps:SetText(dpsText)
        dps:SetTextColor(sr, sg, scrollBar, 0.8)
        skinData.hasStats, skinData.hasDps = statText ~= "", dpsText ~= ""
    end

    -- Vanilla enchants carry no icon, so the name always shows; Enchants set
    -- to Colored Text gives it retail's name look (outlined, tinted from the
    -- item's colour). Capped at 45% of the gap between the columns, as on
    -- retail, less Blizz Default's extra inset on each side (so the two
    -- columns' enchants keep a gap in the middle).
    local name = SavedVal("showEnchants") ~= false and EnchantName(slotID) or ""
    -- An enchantable slot with none says so, in amber.
    local missing = name == "" and SavedVal("showEnchants") ~= false and ENCHANTABLE[slotID]
    if missing then name = "No enchant" end
    ench:SetText(name)
    if missing then
        ench:SetFont(FontPath(), SavedVal("charSheetEnchantSize") or 9, "")
        ench:SetTextColor(1, 0.7, 0.25, 0.9)
        local head, hands = _G.CharacterHeadSlot, _G.CharacterHandsSlot
        local lr, rl = head and head:GetRight(), hands and hands:GetLeft()
        ench:SetWidth((lr and rl and rl > lr) and (rl - lr - 2 * (EX - EX_LOOK)) * 0.45 or 0)
    elseif name ~= "" then
        local size = SavedVal("charSheetEnchantSize") or 9
        if SavedVal("charSheetEnchantNames") then
            ench:SetFont(FontPath(), size, CUI.SlugFlag("OUTLINE, SLUG"))
            ench:SetTextColor(red + (1 - red) * 0.5, green + (1 - green) * 0.5, blue + (1 - blue) * 0.5, 0.9)
        else
            ench:SetFont(FontPath(), size, "")
            ench:SetTextColor(1, 1, 1, 0.8)
        end
        local head, hands = _G.CharacterHeadSlot, _G.CharacterHandsSlot
        local lr, rl = head and head:GetRight(), hands and hands:GetLeft()
        ench:SetWidth((lr and rl and rl > lr) and (rl - lr - 2 * (EX - EX_LOOK)) * 0.45 or 0)
    end
    if dps then
        skinData.hasEnch = name ~= ""
        StackWeaponText(skinData, skinData.anchor)
    end
end

-- The slots went away (tab, pet view, close): nothing waits any more; a
-- slot that was waiting repaints on its next show.
local function ClearPending()
    if pendingN == 0 then return end
    for i = 1, #SLOTS do
        if pending[i] then
            pending[i] = nil
            local skinData = FFD[_G[SLOTS[i]]]
            if skinData then skinData.paintLink = nil end
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
                local slot = _G[SLOTS[i]]
                local skinData = FFD[slot]
                if skinData then skinData.paintLink = nil end
                DrawSlotText(slot)
            end
        end
    end
    if pendingN == 0 then itemWatch:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

local slotOverlay -- every slot's text; the eyeball fades it

local function BuildSlotText()
    local owner = _G.PaperDollItemsFrame
    if not owner or itemWatch then return end
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
    local overlayFrame = CreateFrame("Frame", nil, owner)
    slotOverlay = overlayFrame
    overlayFrame:SetAllPoints(owner)
    local scene = _G.CharacterModelScene
    overlayFrame:SetFrameLevel((scene and scene:GetFrameLevel() or 50) + 10)
    local ranged = _G.CharacterRangedSlot
    local rangedShown = ranged and ranged:IsShown()
    local filePath = FontPath()
    for i = 1, #SLOTS do
        local name = SLOTS[i]
        local side, slot = TEXT_SIDE[name], _G[name]
        if side and slot then
            -- Without a ranged slot the off hand is the outer one on the
            -- right; under Blizz Default the middle one's text goes above
            -- it.
            if side == "B" then
                if not rangedShown then
                    side = "R"
                elseif fv then
                    side = "T"
                end
            end
            local skinData = GetFFD(slot)
            skinData.idx, skinData.side, skinData.anchor = i, side, slot
            -- One line each: a capped width (Blizz Default) cuts the
            -- text short rather than wrapping it into the frames around.
            skinData.stats = overlayFrame:CreateFontString(nil, "OVERLAY")
            skinData.stats:SetWordWrap(false)
            if WEAPON_SLOT[name] then
                skinData.dps = overlayFrame:CreateFontString(nil, "OVERLAY")
                skinData.dps:SetWordWrap(false)
            end
            skinData.ench = overlayFrame:CreateFontString(nil, "OVERLAY")
            skinData.ench:SetFont(filePath, SavedVal("charSheetEnchantSize") or 9, "")
            skinData.ench:SetWordWrap(false)
            ApplyLabelFonts(skinData)
            if slot == ranged then skinData.ammo = _G.CharacterAmmoSlot end
            PlaceText(skinData, slot)
        end
    end
    owner:HookScript("OnHide", ClearPending)
    -- A first open that skinned the sheet (or, under Blizz Default, the
    -- slots' first show) has already had Blizzard's update.
    for i = 1, #SLOTS do
        local slot = _G[SLOTS[i]]
        if slot and slot:IsVisible() then DrawSlotText(slot) end
    end
end

-- Options refreshers: the retail slot text setters (the track key shown
-- here as Show Item Stats, Enchants and its cog, the Fonts page's Enchant
-- Text Size) land here; the retail versions walk retail-only state.
-- The version bump feeds every setting into the paint memo, so a hidden
-- sheet repaints on its next show.
local function RedrawSlotText()
    textVer = textVer + 1
    if not TextEnabled() then return end
    for i = 1, #SLOTS do
        local slot = _G[SLOTS[i]]
        if slot and slot:IsVisible() then DrawSlotText(slot) end
    end
end
CUI._refreshItemLevelVisibility = RedrawSlotText
CUI._refreshUpgradeTrackVisibility = RedrawSlotText
CUI._refreshEnchantsVisibility = RedrawSlotText
CUI._refreshCharSheetSlotLabels = RedrawSlotText
CUI._applyCharSheetTextSizes = RedrawSlotText

-- Blizzard refreshes every shown slot through this on equipment changes and
-- on show; the border and the slot text follow. Foreign item buttons (bags)
-- have no entry.
local function OnSlotUpdate(slot)
    local skinData = FFD[slot]
    if not skinData then return end
    if skinData.border then ColorSlotBorder(slot) end
    if skinData.stats then DrawSlotText(slot) end
end

-- Both looks follow that update through one hook, installed once.
local slotHooked = false
local function HookSlotUpdates()
    if slotHooked or type(_G.PaperDollItemSlotButton_Update) ~= "function" then return end
    slotHooked = true
    hooksecurefunc("PaperDollItemSlotButton_Update", OnSlotUpdate)
end

local function SkinSlot(slotName, Fade)
    local slot = _G[slotName]
    if not slot or GetFFD(slot).done then return end
    GetFFD(slot).done = true
    -- The bronze slot frame lives on a child frame; the button art is the
    -- named NormalTexture (hidden, not faded: the client rewrites its vertex
    -- colour, and with it the alpha, on every item update).
    if slot.BorderFrame then
        Fade(slot.BorderFrame)
    else
        -- The ammo slot is built without that child: its ring is an atlas
        -- texture on the button itself. The arrow pointing at the ranged slot
        -- (an unnamed child frame of its own) stays.
        local regionList = { slot:GetRegions() }
        for i = 1, #regionList do
            local region = regionList[i]
            if region.GetAtlas and region:GetAtlas() == "UI-Character-Info-GearSlotSmall" then
                region:SetAlpha(0)
            end
        end
    end
    local normal = _G[slotName .. "NormalTexture"]
    if normal then normal:Hide() end
    -- Blizzard's quality ring gets re-shown and recoloured on every item
    -- update, so it is collapsed onto one blank texel instead of hidden.
    if slot.IconBorder then slot.IconBorder:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8) end
    -- The item icon is the button's own; the ammo slot also declares a
    -- legacy texture under the same global name, which is not it.
    local iconTex = slot.icon or _G[slotName .. "IconTexture"]
    if iconTex then
        local z = Zoom()
        iconTex:SetTexCoord(z, 1 - z, z, 1 - z)
    end
    local backdrop = slot:CreateTexture(nil, "BACKGROUND", nil, -5)
    backdrop:SetAllPoints(slot)
    backdrop:SetColorTexture(0.5, 0.5, 0.5, 0.7)
    GetFFD(slot).bg = backdrop
    local PanelPP = CUI.PanelPP
    if PanelPP and PanelPP.CreateBorder then
        PanelPP.CreateBorder(slot, 0.4, 0.4, 0.4, 1, 2, "OVERLAY", 1)
        local borders = PanelPP.GetBorders and PanelPP.GetBorders(slot)
        if borders then borders:SetFrameLevel(slot:GetFrameLevel()) end
        GetFFD(slot).border = true
        ColorSlotBorder(slot)
    end
end

-- Options-page refresh: the Icon Zoom slider lands here (the retail sheet's
-- own refresher is replaced, it walks the retail slot list).
function CUI._refreshCharSheetIconZoom()
    if not Enabled() then return end
    local z = Zoom()
    for i = 1, #SLOTS do
        local slot = _G[SLOTS[i]]
        if slot and FFD[slot] and FFD[slot].done then
            local iconTex = slot.icon or _G[SLOTS[i] .. "IconTexture"]
            if iconTex then iconTex:SetTexCoord(z, 1 - z, z, 1 - z) end
        end
    end
end

--------------------------------------------------------------------------------
--  The model backdrop and the sidebar panel, as on retail
--------------------------------------------------------------------------------
local IMG_ASPECT = 787 / 1030 -- character-bg.png

-- Cover crop: the image keeps its aspect and the box shows its centre.
local function CoverCrop(texture, wid, hgt)
    if issecretvalue and (issecretvalue(wid) or issecretvalue(hgt)) then return end
    if not wid or not hgt or wid <= 0 or hgt <= 0 then return end
    local box = wid / hgt
    if box > IMG_ASPECT then
        local trim = (1 - IMG_ASPECT / box) / 2
        texture:SetTexCoord(0, 1, trim, 1 - trim)
    else
        local trim = (1 - box / IMG_ASPECT) / 2
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
    if not (scene and doll) or GetFFD(widget).modelBg then return end
    -- Under the paper doll so it comes and goes with that tab; one level
    -- under the scene so the character renders over it.
    local owner = CreateFrame("Frame", nil, doll)
    PinTop(owner, topBar, scene)
    owner:SetPoint("LEFT", scene, "LEFT", 0, 0)
    owner:SetPoint("RIGHT", scene, "RIGHT", 0, 0)
    owner:SetPoint("BOTTOM", scene, "BOTTOM", 0, 0)
    owner:SetFrameLevel(math.max(0, scene:GetFrameLevel() - 1))
    local texture = owner:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(owner)
    texture:SetTexture(MEDIA .. "character-bg.png")
    owner:SetScript("OnSizeChanged", function(_, wid, hgt) CoverCrop(texture, wid, hgt) end)
    CoverCrop(texture, owner:GetSize())
    GetFFD(widget).modelBg = owner
end

local function SidebarPanel(widget, topBar)
    local owner = widget.RightPaneHost
    if not owner or GetFFD(widget).sidebar then return end
    -- A child of the pane host so it collapses with it, at the host's own
    -- level so every list and scrollbar draws over it.
    local panelFrame = CreateFrame("Frame", nil, owner)
    panelFrame:SetFrameLevel(owner:GetFrameLevel())
    PinTop(panelFrame, topBar, owner)
    panelFrame:SetPoint("LEFT", owner, "LEFT", 0, 0)
    panelFrame:SetPoint("RIGHT", owner, "RIGHT", -6, 0)
    panelFrame:SetPoint("BOTTOM", owner, "BOTTOM", 0, 8)
    local texture = panelFrame:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(panelFrame)
    texture:SetColorTexture(0, 0, 0, 0.2)
    GetFFD(widget).sidebar = panelFrame
end

local function SkinFrame()
    local widget = _G.CharacterFrame
    local Skin = mod.WSkin
    if not (widget and Skin and Skin.Shell) then return false end
    local Fade = Skin.FadeRegions
    if not Fade then return false end
    local skinData = GetFFD(widget)
    if skinData.done then return true end
    skinData.done = true

    -- The ordinary window treatment: shell, border, top bar, house close
    -- button, title centred on the bar. explicitControls keeps the engine
    -- away from the stats scrollbar, which stays Blizzard's.
    Skin.Shell("charsheet", widget)
    if Skin.CommonChrome then Skin.CommonChrome(widget, "CharacterFrame", true) end
    if Skin.RemovePortrait then Skin.RemovePortrait(widget) end

    -- The mode tabs down the right edge (Character, Reputation, Skills, PvP,
    -- Currency, Statistics) as the house's flat squares.
    if Skin.SideTab then
        for index = 1, 6 do
            Skin.SideTab(_G["CharacterFrameModeTab" .. index])
        end
    end
    -- The paper doll's sidebar buttons over the stats (stats, titles,
    -- equipment sets): their gold frame goes, the icon sits in a 1 px border,
    -- the shown one in the accent.
    for index = 1, 4 do
        local tab = _G["PaperDollSidebarTab" .. index]
        if tab and not GetFFD(tab).flat then
            GetFFD(tab).flat = true
            for _, region in ipairs({ tab:GetRegions() }) do
                if region ~= tab.Icon and region.GetAtlas and region:GetAtlas() == "UI-Character-Info-StatTab" then
                    region:SetAlpha(0)
                end
            end
            local checked = tab.GetCheckedTexture and tab:GetCheckedTexture()
            if checked then checked:SetAlpha(0) end
            -- The icons keep the game's own crop: the titles and equipment set
            -- icons are pieces of one sheet the game positions itself.
            local function Paint()
                local Pix = CUI.PanelPP or CUI.PP
                local on = tab:GetChecked()
                local red, green, blue = 0, 0, 0
                if on and Skin.AccentBarColor then red, green, blue = Skin.AccentBarColor() end
                if not GetFFD(tab).edge and Skin.AddBorder then
                    GetFFD(tab).edge = true
                    Skin.AddBorder(tab, red, green, blue, 1)
                elseif Pix and Pix.SetBorderColor then
                    Pix.SetBorderColor(tab, red, green, blue, 1)
                end
            end
            hooksecurefunc(tab, "SetChecked", Paint)
            tab:HookScript("OnClick", Paint)
            Paint()
        end
    end

    -- The right-pane collapse arrow goes. The pane it toggles is kept open:
    -- with the arrow gone a sheet collapsed from an earlier session (the
    -- state is a cvar, read once at load) could never be opened again.
    Discard(widget.RightPaneToggleButton)
    if widget.IsRightPaneCollapsed and widget.SetRightPaneCollapsed then
        widget:HookScript("OnShow", function(self)
            if self:IsRightPaneCollapsed() then self:SetRightPaneCollapsed(false) end
        end)
    end

    -- Name in the top bar and the level lines (the player's and the pet
    -- view's): the house font on Blizzard's own font strings, so the text
    -- (pvp title, class colour) stays theirs.
    local titleText = _G.CharacterFrameTitleText
        or (widget.TitleContainer and widget.TitleContainer.TitleText)
    if titleText and Skin.Font then Skin.Font(titleText, 1, 1, 1) end
    local level = _G.CharacterLevelText
    if level and Skin.Font then Skin.Font(level) end
    local petLevel = _G.PetCharacterLevelText
    if petLevel and Skin.Font then Skin.Font(petLevel) end

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
    if widget.RightPaneHost and widget.RightPaneHost.StoneBg then widget.RightPaneHost.StoneBg:SetAlpha(0) end
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
    if slotOverlay and not skinData.eyeBtn then
        local EYE_VISIBLE, EYE_INVISIBLE = CUI.EYE_VISIBLE_ICON, CUI.EYE_INVISIBLE_ICON
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
            CUI.ShowWidgetTooltip(self, hidden and "Show Item Text" or "Hide Item Text", { width = 135 })
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.8)
            CUI.ShowWidgetTooltip(self, hidden and "Show Item Text" or "Hide Item Text", { width = 135 })
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            CUI.HideWidgetTooltip()
        end)
        skinData.eyeBtn = eyeBtn
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
        if stats and stats.ScrollBar then Skin.ScrollBar(stats.ScrollBar, true) end
        local pet = _G.CharacterStatsPanePetScrollBox
        if pet and pet.ScrollBar then Skin.ScrollBar(pet.ScrollBar, true) end
    end
    return true
end

-- Blizz Default: the slot text alone, built at the slots' first show;
-- every later show returns at once.
local function BuildStockText()
    if itemWatch then return end
    BuildSlotText()
    HookSlotUpdates()
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not _G.CharacterFrame then return end
    if Enabled() then
        if not SkinFrame() then
            -- The engine loads after this addon's own files; one retry on the
            -- first open covers a late shell.
            _G.CharacterFrame:HookScript("OnShow", function() SkinFrame() end)
        end
    elseif TextEnabled() and _G.PaperDollItemsFrame then
        _G.PaperDollItemsFrame:HookScript("OnShow", BuildStockText)
    end
end)
