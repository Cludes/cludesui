if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\Shared.lua
-- Shared scaffolding for the DataBars block factories. Loads before every other
-- Blocks\*.lua file; each block file lives in its own file and imports helpers
-- from ns.BlockKit.
--
-- Contract (engine calls, see CludesUIDataBars.lua):
--   ns.BlockFactories[typeKey] = function(blockCfg, slot, content, barCtx) -> inst
--   inst:Refresh()        re-read settings+state, repaint, re-measure; re-layouts
--                         when the measured auto extent changed
--   inst:Enable()/Disable()  register/unregister events+heartbeat (idempotent)
--   inst:GetAutoLength()  content extent along the bar axis (px); 0 = COLLAPSED
--                         (solver drops it: content gaps in auto, share in even mode)
--   inst:Destroy()        full teardown; secure frames park OOC
--
-- All frames in Blocks\ are OURS (CreateFrame by these files), so SetScript and custom fields
-- are allowed. Only Blizzard frames touched: micro menu containers (via a
-- SecureHandlerStateTemplate hider) and the MicroButtons/ProfessionMicroButton/QuestLogMicroButton (via secure attributes).

local ADDON_NAME, mod = ...

-- Helpers shared by every block file.
local K = {}
mod.BlockKit = K

-- Max-level check with layered fallbacks, matching the Action Bars XP bar's:
-- the Is* helpers are nil-guarded, so client API churn can silently disable
-- them -- a plain numeric compare against the expansion max level backstops
-- the check.
function K.AtMaxLevel()
    local level = UnitLevel("player") or 0
    if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then
        return true
    end
    if IsLevelAtEffectiveMaxLevel and IsLevelAtEffectiveMaxLevel(level) then
        return true
    end
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
        or (GetMaxPlayerLevel and GetMaxPlayerLevel())
    return (maxLevel and level >= maxLevel) or false
end

-- One knob: icon -> content spacing for every icon-bearing block.
local ICON_GAP = 8

-- Bar fill textures for block statusbars (XP/Rep, professions): mirrors the
-- Unit Frames Bar Texture set; SharedMedia appended below + at dropdown build.
-- "none" = flat fill.
local barTextures, barTextureNames, barTextureOrder = CludesUI.BuildBarTextureTables(true)
mod.barTextures = barTextures
mod.barTextureOrder = barTextureOrder
mod.barTextureNames = barTextureNames

-- Seed SharedMedia statusbar textures once at load so a saved LSM key resolves at login; the parent helper also registers for late LSM packs.
CludesUI.AppendSharedMediaTextures(barTextureNames, barTextureOrder, nil, barTextures)

local InCombatLockdown = InCombatLockdown

-------------------------------------------------------------------------------
--  What every block uses
-------------------------------------------------------------------------------
-- A block's key, unique per bar and block (frame names, deferred work).
local function InstKey(barCtx, blockCfg)
    return "EDB" .. barCtx.id .. "_" .. blockCfg.id
end

-- An event frame that calls handler(block, event, ...).
local function MakeEventFrame(block, handler)
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        handler(block, event, ...)
    end)
    return frame
end

-- block.events onto block.eventFrame; an event the client lacks is skipped.
local function RegisterInstEvents(block)
    local frame, events = block.eventFrame, block.events
    if not (frame and events) then
        return
    end
    for _, event in ipairs(events) do
        pcall(frame.RegisterEvent, frame, event)
    end
end

local function UnregisterInstEvents(block)
    if block.eventFrame then
        block.eventFrame:UnregisterAllEvents()
    end
end

-- Fonts and icons size from this constant, never the live bar height: the
-- Height setting resizes the bar only (Text Scale, Content Scale and the
-- per-block fonts size the content). 30 is the height they were tuned at.
local CONTENT_BASE = 30

-- A block's content scale (its content is scaled as a group, so a slot's
-- pixels are divided by it to get content pixels).
local function ScaleOf(block)
    local scale = ((block.cfg and block.cfg.scale) or 100) / 100
    return scale > 0 and scale or 1
end

-- The width a horizontal block may use: its slot's, once the bar has laid out.
local function HBudget(block, fallback)
    local width = block.slot and block.slot:GetWidth()
    if width and width > 8 then
        return width / ScaleOf(block)
    end
    return fallback
end

-- A vertical block's width: its slot's, or the bar's thickness before layout.
local function VSlotW(block)
    local width = block.slot and block.slot:GetWidth()
    if width and width > 2 then
        return width / ScaleOf(block)
    end
    return block.ctx.GetThickness()
end

-- Asks the bar to lay out again, but only when this block's own length
-- changed (which also stops Refresh -> layout -> Refresh loops). Only bars
-- in automatic sizing size from content, and never from the fill block,
-- which takes what is left.
local function MaybeRelayout(block)
    local barCfg = block.ctx and block.ctx.cfg
    if not barCfg then
        return
    end
    local length = block.GetAutoLength and block:GetAutoLength() or 0
    local last = block._lastAuto
    if mod.BarSizingMode(barCfg) ~= "auto" then
        -- Even sizing ignores lengths, but a block appearing or leaving
        -- (length 0) changes how many shares there are.
        block._lastAuto = length
        if last ~= nil and (last <= 0) ~= (length <= 0) then
            block.ctx.RequestLayout()
        end
        return
    end
    if barCfg.fillBlockId == block.cfg.id then
        return
    end
    if last == nil or math.abs(length - last) > 0.5 then
        block._lastAuto = length
        block.ctx.RequestLayout()
    end
end

-- The block's Text X/Y offset (textXOff/textYOff): every anchor of this
-- FontString carries it. Only for a block's main text: texts anchored to it
-- (Gold's slot count, Spec's loot spec) move with it already and would be
-- shifted twice.
local function AttachTextOffset(block, text)
    if not text or text._cuiOffset then
        return
    end
    text._cuiOffset = true
    local SetPoint = text.SetPoint
    text.SetPoint = function(self, point, a2, a3, a4, a5)
        local c = block.cfg
        local dx, dy = (c and c.textXOff) or 0, (c and c.textYOff) or 0
        if a2 == nil then
            return SetPoint(self, point, dx, dy)
        elseif type(a2) == "number" then
            return SetPoint(self, point, a2 + dx, (a3 or 0) + dy)
        end
        return SetPoint(self, point, a2, a3 or point, (a4 or 0) + dx, (a5 or 0) + dy)
    end
end

local function ClassColour()
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        return c.r, c.g, c.b
    end
end

-- A block's text colour (the Text Color row: Custom, Class, Accent or
-- Dynamic; white by default). Hover and other state colours are applied
-- where they happen.
local function BlockColorOf(b)
    if b.useDynamicColor then
        return mod.BlockTextDynamic(b.type)
    end
    if b.useClassColor then
        local region, g, bl = ClassColour()
        if region then
            return region, g, bl
        end
    elseif b.useAccentColor then
        return mod.GetAccent()
    end
    local c = b.color
    if c then
        return c.r or 1, c.g or 1, c.b or 1
    end
    return 1, 1, 1
end

-- Zone coloring by the current PvP ruleset; identical to the minimap module's GetZoneReactionColor so bar location text and minimap zone text agree.
local function ZoneReactionColor()
    local pvpType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    if pvpType == "friendly" then
        return 0.05, 0.85, 0.03
    elseif pvpType == "sanctuary" then
        return 0.035, 0.58, 0.84
    elseif pvpType == "arena" or pvpType == "hostile" or pvpType == "combat" then
        return 0.84, 0.03, 0.03
    end
    return 0.9, 0.85, 0.05
end

-- SEASON UPDATE: replace the ids when the crest set rotates; the tints are the
-- item-quality colors the crest art itself uses and only move if Blizzard
-- restyles them. Keep in sync with CludesUIQoL/CUI_UpgradeCalc.lua's
-- Data.tracks, which tracks the same currencies for the upgrade planner (that
-- addon can be disabled, so DataBars carries its own copy rather than reaching
-- across for it). Names and icons come live from C_CurrencyInfo, so only the
-- ids and tints are hardcoded. The keys are TIER slots, not ids: a season swap
-- edits the ids here and every player's crest checklist still applies.
local CRESTS = {
    { key = "t1", id = 3442, hex = "1EFF00", r = 0.118, g = 1, b = 0 },
    { key = "t2", id = 3443, hex = "0070DD", r = 0, g = 0.439, b = 0.867 },
    { key = "t3", id = 3444, hex = "A335EE", r = 0.639, g = 0.208, b = 0.933 },
    { key = "t4", id = 3445, hex = "FF8000", r = 1, g = 0.502, b = 0 },
    { key = "t5", id = 3446, hex = "FFD100", r = 1, g = 0.820, b = 0 },
}
mod.CRESTS = CRESTS
-- Currency id set: the crest block's CURRENCY_DISPLAY_UPDATE handler drops
-- events that name some other currency (payload currencyType; nil = bulk).
do
    local ids = {}
    for index = 1, #CRESTS do
        ids[CRESTS[index].id] = true
    end
    mod.CREST_IDS = ids
end

-- SEASON UPDATE: rank-1 item level of each upgrade track, highest first;
-- mirrors Data.tracks[*].ranks[1] in CludesUIQoL/CUI_UpgradeCalc.lua. Feeds
-- the item level block's "Band" text swatch, which tints the number with the
-- crest color of the track its gear sits in.
local ILVL_BANDS = {
    { 318, 5 },
    { 305, 4 },
    { 292, 3 },
    { 279, 2 },
    { 266, 1 },
}
-- Equipped item level, written by the ilvl block's Refresh; read by the band
-- tint below (and its swatch preview) exactly like K.lastDurabilityPct.
K.lastAvgIlvl = nil

-- Themed per-block icon defaults (Icon Color row's "Default" swatch): spec ->
-- live class color; professions -> live accent (matches their skill-bar fill,
-- so no separate Default swatch there); durability -> DYNAMIC red->green tint
-- from its sampler (swatch "Dynamic").
local ICON_DEFAULTS = {
    gold = { 0.886, 0.675, 0.478 }, -- E2AC7A
    bags = { 0.886, 0.675, 0.478 }, -- E2AC7A, same bag art as gold
    travel = { 0.596, 0.804, 0.961 }, -- 98CDF5
    currency = { 0.886, 0.675, 0.478 }, -- E2AC7A
    greatvault = { 0.569, 0.502, 1 }, -- 9180FF
    audio = { 1, 1, 1 },
    -- Map-marker red, not the soft module red (salmon at 65% sat; blooms as pure FF0000 at icon size).
    -- Plain stored default: unlike the text beside it, the pin never follows the zone.
    location = { 0.918, 0.263, 0.208 }, -- EA4335
    -- Map-marker yellow, distinct from gold's peachy E2AC7A at a glance.
    coords = { 0.961, 0.784, 0.259 }, -- F5C842
    ilvl = { 1, 1, 1 },
}
-- NOTE: no `crests` entry, and the block is deliberately absent from the
-- options page's ICON_COLOR_BLOCKS. Its icons are inline |T|t escapes inside
-- one FontString (variable segment count, per-crest tinting), and inline
-- textures cannot be vertex-tinted -- the crest art is meant to read by its own
-- tier color anyway.

-- Block icon art in one place: the CludesUI file (full path) and its
-- Blizzard counterpart (a path or a fileID). Entries without
-- `wow` have no stock equivalent and always show the custom art.
local MEDIA, MM = mod.MEDIA, mod.MICROMENU_MEDIA
local ICON_ART = {
    audio = { custom = MEDIA .. "audio.png", wow = "Interface\\Common\\VoiceChat-Speaker" },
    bags = { custom = MM .. "menu-bags.png", wow = "Interface\\Buttons\\Button-Backpack-Up" },
    gold = { custom = MM .. "menu-bags.png", wow = "Interface\\MoneyFrame\\UI-GoldIcon" },
    ilvl = { custom = MM .. "menu-character.png", wow = "Interface\\Icons\\INV_Chest_Chain" },
    location = { custom = MM .. "menu-map.png", wow = "Interface\\Icons\\INV_Misc_Map09" },
    coords = { custom = MEDIA .. "coordinates.png", wow = "Interface\\Icons\\INV_Misc_Spyglass_02" },
    durability = { custom = MM .. "menu-professions.png", wow = "Interface\\Minimap\\Tracking\\Repair" },
    travel = { custom = MEDIA .. "hearthstone.png", wow = 134414 }, -- Hearthstone item icon
    greatvault = { custom = MM .. "menu-vault.png" },
    home = { custom = MEDIA .. "home_latency.png" },
    world = { custom = MEDIA .. "world_latency.png" },
}
-- Blocks that resolve their Blizzard art themselves (API icons per spec,
-- profession or micro button); they read settings.iconStyle directly.
local OWN_ICON_STYLE = { spec = true, profession = true, profession2 = true, micromenu = true }

function mod.BlockHasIconStyle(bType)
    if OWN_ICON_STYLE[bType] then
        return true
    end
    local art = ICON_ART[bType]
    return art ~= nil and art.wow ~= nil
end

-- Crops a stock item/spell icon (Interface\Icons, fileID) off its baked-in border.
function K.CropStockIcon(iconTex)
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
end

-- Paints a block icon in its selected style. key defaults to the block type.
-- Cheap to call from Refresh: the texture is only set when it changes.
function K.SetBlockIcon(iconTex, blockCfg, key)
    local art = ICON_ART[key or blockCfg.type]
    local s = blockCfg.settings
    local texture = art.wow and s and s.iconStyle == "wow" and art.wow
    local wanted = texture or art.custom
    if iconTex._cuiIconArt == wanted then
        return
    end
    iconTex._cuiIconArt = wanted
    if texture then
        iconTex:SetTexture(texture)
        local crop = type(texture) == "number" or texture:find("^Interface\\Icons\\")
        if crop then
            K.CropStockIcon(iconTex)
        else
            iconTex:SetTexCoord(0, 1, 0, 1)
        end
    else
        iconTex:SetTexture(art.custom)
        iconTex:SetTexCoord(0, 1, 0, 1)
    end
end

-- Lowest equipped-durability percent, written by the durability block's sampler; read by the dynamic tint below (and its swatch preview).
K.lastDurabilityPct = nil
function mod.BlockIconDefault(bType, prefs)
    -- Stock art carries its own colors; durability keeps its low-durability tint.
    if prefs and prefs.iconStyle == "wow" and bType ~= "durability" and mod.BlockHasIconStyle(bType) then
        return 1, 1, 1
    end
    if bType == "spec" then
        local _, class = UnitClass("player")
        local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if cc then
            return cc.r, cc.g, cc.b
        end
        return 1, 1, 1
    end
    if bType == "profession" or bType == "profession2" then
        return mod.GetAccent()
    end
    if bType == "durability" then
        -- White(100%) fades to soft red(1,.35,.35) over 20..100; <=20% is fully red.
        local pct = K.lastDurabilityPct or 100
        local t = (pct - 20) * (100 / 80)
        if t < 0 then
            t = 0
        elseif t > 100 then
            t = 100
        end
        local gb = 0.35 + 0.65 * (t / 100)
        return 1, gb, gb
    end
    local skinData = ICON_DEFAULTS[bType]
    if skinData then
        return skinData[1], skinData[2], skinData[3]
    end
    return 1, 1, 1
end

-- Per-block STATE-DRIVEN TEXT color (Text Color row's 4th swatch). Fallback is
-- BlockIconDefault (same source as the icon; durability tints both from its
-- red->green gradient). Override: location's zone name follows the PvP
-- ruleset, its map pin stays user-owned.
local TEXT_DYNAMIC = {
    location = ZoneReactionColor,
    coords = ZoneReactionColor,
    -- Item level "Band": the crest color of the upgrade track the equipped
    -- gear sits in. Below the lowest track it stays white.
    ilvl = function()
        local lvl = K.lastAvgIlvl
        if not lvl then
            return 1, 1, 1
        end
        for index = 1, #ILVL_BANDS do
            local band = ILVL_BANDS[index]
            if lvl >= band[1] then
                local c = CRESTS[band[2]]
                return c.r, c.g, c.b
            end
        end
        return 1, 1, 1
    end,
}
function mod.BlockTextDynamic(bType)
    local func = TEXT_DYNAMIC[bType]
    if func then
        return func()
    end
    return mod.BlockIconDefault(bType)
end

-- A block's icon colour (the Icon Color row: Custom, Class, Accent or
-- Default). Nothing chosen = the block type's default above.
local function IconColorOf(b)
    if b.useIconDefaultColor then
        -- Default chosen explicitly: a stored custom colour is kept, unused.
        return mod.BlockIconDefault(b.type, b.settings)
    end
    if b.useIconClassColor then
        local region, g, bl = ClassColour()
        if region then
            return region, g, bl
        end
    elseif b.useIconAccentColor then
        return mod.GetAccent()
    end
    local c = b.iconColor
    if c then
        return c.r or 1, c.g or 1, c.b or 1
    end
    return mod.BlockIconDefault(b.type, b.settings)
end

-- Retires a secure frame: hidden and moved to the bar engine's park frame.
-- In combat it is made invisible now and moved when combat ends.
local function ParkSecureFrame(frame, key)
    if not frame then
        return
    end
    local function Park()
        frame:Hide()
        frame:SetParent(mod._park)
    end
    if InCombatLockdown() then
        frame:SetAlpha(0)
        mod.DeferUntilOOC("edbkill:" .. key, Park)
    else
        Park()
    end
end

K.ICON_GAP = ICON_GAP
K.CONTENT_BASE = CONTENT_BASE
K.CRESTS = CRESTS
K.InstKey = InstKey
K.MakeEventFrame = MakeEventFrame
K.RegisterInstEvents = RegisterInstEvents
K.UnregisterInstEvents = UnregisterInstEvents
K.HBudget = HBudget
K.VSlotW = VSlotW
K.MaybeRelayout = MaybeRelayout
K.AttachTextOffset = AttachTextOffset
K.BlockColorOf = BlockColorOf
K.ZoneReactionColor = ZoneReactionColor
K.IconColorOf = IconColorOf
K.ParkSecureFrame = ParkSecureFrame
