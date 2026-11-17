if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CUI_RaidFrames_ManagerPages.lua
-- 12.1 redesigned manager options: the Debuff Manager page (sidebar of
-- tiles with the undeletable Base Icons tile first) plus the Buff Manager v2
-- Filter Editor and Assigned Filters section the Buff Manager page splices in.
--
-- All settings written here are new additive keys (dmDebuff table); the
-- legacy mode/preset keys are never written.

local mod = CludesUI._ModuleNS["CludesUIRaidFrames"] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page
local CludesUI = _G.CludesUI

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host (the kept Debuff Manager root, the kept Filter Editor and every frame
-- they hand out) are reset and dressed again by the next render instead of
-- made anew; elsewhere this is CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolKept = CludesUI._Pool.Kept
local PoolOwned = CludesUI._Pool.Owned

local floor = math.floor
local max = math.max

local POS_VALUES = {
    topleft = "Top Left",
    top = "Top",
    topright = "Top Right",
    left = "Left",
    center = "Center",
    right = "Right",
    bottomleft = "Bottom Left",
    bottom = "Bottom",
    bottomright = "Bottom Right",
}
local POS_ORDER = CludesUI.POSITION_GRID_ORDER
local GROW_VALUES = CludesUI.GROW_DIR_VALUES_FULL
local GROW_ORDER = CludesUI.GROW_DIR_ORDER_FULL

local CAT_VALUES = {
    boss = "Boss",
    role = "Boss Role",
    priority = "Important",
    cc = "Crowd Control",
    raid = "Raid",
    raidcombat = "Raid In Combat",
    dispel = "Dispellable",
    nonplayer = "Non-Player",
}
local CAT_ORDER = { "nonplayer", "priority", "boss", "role", "cc", "raid", "raidcombat", "dispel" }
-- The Less Common Filters, named in indicator subtitles after the main ones.
local LESS_CAT_VALUES = {
    castbyme = "Cast By You",
    magic = "Magic",
    curse = "Curse",
    poison = "Poison",
    disease = "Disease",
    bleed = "Bleed",
    canapply = "Can Apply Aura",
}
local LESS_CAT_ORDER = { "castbyme", "magic", "curse", "poison", "disease", "bleed", "canapply" }

local TYPE_NAMES = {
    icons = "Icon",
    glow = "Frame Glow",
    square = "Square",
    healthcolor = "Health Bar Color",
    bar = "Duration Bar",
}
-- Grid types above the divider, frame effects below (BM dropdown parity).
local TYPE_ORDER = { "icons", "square", "---", "glow", "healthcolor", "bar" }

-- 5-state aura tooltip mode stored on the legacy hide-tooltips keys:
-- true/nil = hidden, false = shown, "cursor" = shown at the cursor,
-- "combat" = shown but hidden during combat, "modifier" = shown only while
-- the Use Modifier cog's key is held.
local TIP_VALUES = {
    hidden = "Hidden",
    shown = "Shown",
    cursor = "Shown At Cursor",
    modifier = "Shown on Modifier",
    combat = "Hidden In Combat",
}
local TIP_ORDER = { "hidden", "shown", "cursor", "modifier", "combat" }
local function TipModeKey(val)
    if val == false then
        return "shown"
    end
    if val == "cursor" or val == "combat" or val == "modifier" then
        return val
    end
    return "hidden"
end
local function TipModeStore(k)
    if k == "shown" then
        return false
    end
    if k == "hidden" then
        return true
    end
    return k
end

-- Page-local selection: "base" or a tile id. Reset when the page rebuilds
-- with a vanished selection.
local dmSel = "base"
-- Add New popup's picked indicator type (session-sticky like the BM's).
local dmSelType = "icons"
-- Editing-spec bucket: "allspecs" (the legacy tile list), a group bucket
-- key, or a concrete "spec<ID>". Session-sticky like dmSel.
local dmSpecSel = "allspecs"
-- Inherited-tile selection ({ group, id }); wins over dmSel while set.
local dmInhSel = nil

local function L(s)
    return CludesUI.L(s) or s
end

-- The managers share the unit-frame aura border controls and size/offset helpers.
function mod.RFO_AuraBorderSettings(hostFrame, posY, W, get, set, apply, disabled, dispel)
    local function Val(k, fallback)
        local val = get(k)
        if val ~= nil then
            return val
        end
        return fallback
    end
    local values, sequence = CludesUI.GetBorderTextureDropdown()
    local row, hgt = W:DualRow(
        hostFrame,
        posY,
        {
            type = "dropdown",
            text = "Border Style",
            values = values,
            order = sequence,
            disabled = disabled,
            disabledTooltip = "Hide Icons",
            requireState = "disabled",
            getValue = function()
                return Val("Texture", "solid")
            end,
            setValue = function(val)
                local color = CludesUI.GetBorderStyleSelectDefaults(val)
                set("Texture", val)
                set("TextureOffset", nil)
                set("TextureOffsetY", nil)
                set("TextureShiftX", nil)
                set("TextureShiftY", nil)
                set("Color", color)
                local size = CludesUI.GetBorderDefaultSize("unitframes", val)
                if size then
                    set("Size", size)
                end
                set("SizePx", false)
                apply()
                CludesUI:RefreshPage(true)
            end,
        },
        CludesUI.BorderPxSliderCfg({
            trackWidth = 120,
            disabled = disabled,
            disabledTooltip = "Hide Icons",
            requireState = "disabled",
            getStep = function()
                return Val("Size", 1)
            end,
            setStep = function(val)
                set("Size", val)
            end,
            getTex = function()
                return Val("Texture", "solid")
            end,
            getPx = function()
                return get("SizePx")
            end,
            setPx = function(val)
                set("SizePx", val)
            end,
            apply = apply,
        })
    )
    posY = posY - hgt
    if not CludesUI._prebuilding then
        local region = row._rightRegion
        local swatch, refresh = CludesUI.BuildColorSwatch(region, row:GetFrameLevel() + 3, function()
            local c = Val("Color", {})
            return c.r or 0, c.g or 0, c.b or 0, c.a or 1
        end, function(r, g, b, a)
            set("Color", { r = r, g = g, b = b, a = a })
            apply()
        end, true, 20)
        swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = swatch
        CludesUI.RegisterWidgetRefresh(refresh)
    end
    local texture = Val("Texture", "solid")
    if texture ~= "solid" and texture ~= "" and not CludesUI._prebuilding then
        local rowList = {}
        for idx, axis in ipairs({ "X", "Y" }) do
            rowList[#rowList + 1] = {
                type = "slider",
                label = "Shift " .. axis,
                min = -10,
                max = 10,
                step = 1,
                get = function()
                    local val = get("TextureShift" .. axis)
                    if val ~= nil then
                        return val
                    end
                    local _, _, sx, sy =
                        CludesUI.GetBorderDefaults("unitframes", Val("Texture", "solid"), Val("Size", 1))
                    return idx == 1 and sx or sy
                end,
                set = function(val)
                    set("TextureShift" .. axis, val)
                    apply()
                end,
            }
        end
        local offX, offY = CludesUI.BorderOffsetCogRows({
            addonKey = "unitframes",
            getTex = function()
                return Val("Texture", "solid")
            end,
            getStep = function()
                return Val("Size", 1)
            end,
            getSizeKey = function()
                return Val("Size", 1)
            end,
            getPx = function()
                return get("SizePx")
            end,
            getX = function()
                return get("TextureOffset")
            end,
            setX = function(val)
                set("TextureOffset", val)
            end,
            getY = function()
                return get("TextureOffsetY")
            end,
            setY = function(val)
                set("TextureOffsetY", val)
            end,
            apply = apply,
        })
        rowList[#rowList + 1] = offX
        rowList[#rowList + 1] = offY
        if dispel then
            rowList[#rowList + 1] = {
                type = "toggle",
                label = "Textured Dispel Ring",
                get = function()
                    return Val("DispelTextured", false)
                end,
                set = function(val)
                    set("DispelTextured", val)
                    apply()
                end,
            }
        end
        CludesUI.BuildInlineCog(row._leftRegion, {
            title = "Border Options",
            rows = rowList,
            disabled = disabled,
            disabledTooltip = "Hide Icons",
            requireState = "disabled",
        })
    end
    return posY
end

-- Stable random preview swipe seeds (fraction remaining, 0.2-0.9), keyed by preview
-- slot index -- generated once and reused so refreshes never reshuffle the frozen swipe
-- positions (same pattern as the Buff Manager preview's own seeds).
local pvCDSeeds = {}
local function GetPvCDSeed(idx)
    local val = pvCDSeeds[idx]
    if not val then
        val = 0.2 + math.random() * 0.7
        pvCDSeeds[idx] = val
    end
    return val
end

local function DmApply()
    if mod.ReloadFrames then
        mod.ReloadFrames()
    end
    -- Live preview parity with the BM page: every setting change re-renders
    -- the page's preview band immediately.
    if mod.DMP_RefreshPreview then
        mod.DMP_RefreshPreview()
    end
end
-- After a change: the frames re-applied and the page built again.
local function ApplyAndRedraw()
    DmApply()
    CludesUI:RefreshPage(true)
end

-- Frame Glow tile: the shared glow descriptor over the tile's own keys (always
-- on, no None). The tile editor and the options preview (GO.Spec) share it.
local function TileGlowDesc(t, onChange)
    return {
        host = "engine",
        noNone = true,
        excludes = CludesUI.Glows.RECT_EXCLUDES,
        -- The half next to Filters is too narrow for the color swatches.
        colorInCog = true,
        caps = { mode = true, params = true, bg = true },
        defaultColor = { r = 1, g = 0.78, b = 0.38 },
        onChange = onChange,
        get = function(f)
            if f == "style" then
                return t.glowType or 1
            elseif f == "mode" then
                return t.glowColorMode or "default"
            -- The tile keeps its color under t.color, the rest under glow*.
            elseif f == "color" then
                local c = t.color
                if c then
                    return c.r, c.g, c.b
                end
            end
            return CludesUI.GlowOptions.FlatGet(t, "glow", f)
        end,
        set = function(f, a, b2, c2)
            if f == "style" then
                t.glowType = a
            elseif f == "mode" then
                t.glowColorMode = a
            elseif f == "color" then
                t.color = { r = a, g = b2, b = c2 }
            elseif f == "bg" then
                t.glowBackground = a and true or nil
            else
                CludesUI.GlowOptions.FlatSet(t, "glow", f, a, b2, c2)
            end
        end,
    }
end

local function DmProfile()
    return mod.db and mod.db.profile
end

local function DmTable()
    local p = DmProfile()
    if not p then
        return nil
    end
    local dm = p.dmDebuff
    if not dm then
        dm = {}
        p.dmDebuff = dm
    end
    return dm
end

-------------------------------------------------------------------------------
-- DEBUFF MANAGER page
-------------------------------------------------------------------------------

local function TileSubtitle(t)
    -- Every tile type routes via the catch-all flavor plus the checked filter set;
    -- Match All joins the filters the way they combine.
    local nameList = {}
    if t.all == true then
        nameList[#nameList + 1] = L("All Debuffs")
    end
    if t.hasDuration == true then
        nameList[#nameList + 1] = L("Has Duration")
    end
    local cats = {}
    if t.claim then
        for _, category in ipairs(CAT_ORDER) do
            if t.claim[category] then
                cats[#cats + 1] = L(CAT_VALUES[category])
            end
        end
        for _, category in ipairs(LESS_CAT_ORDER) do
            if t.claim[category] then
                cats[#cats + 1] = L(LESS_CAT_VALUES[category])
            end
        end
    end
    if #nameList == 0 and #cats == 0 then
        return L("No filters routed")
    end
    if #cats > 0 then
        nameList[#nameList + 1] = table.concat(cats, mod.DM_TileMatchOn(t) and " & " or ", ")
    end
    return table.concat(nameList, ", ")
end

-- An indicator's display name, as its sidebar row titles it.
local function TileName(t)
    return t.name or L(TYPE_NAMES[t.type] or t.type)
end

-- The category a Filters row edits: the two dispel rows and the two
-- Non-Player rows are flavors of one category each.
local function RowCat(k)
    if k == "dispel_you" or k == "dispel_typed" then
        return "dispel"
    end
    if k == "anyplayer" then
        return "nonplayer"
    end
    return k
end

-- EFFECTS section (base + grid tile panes): each effect is one DualRow --
-- left = the filters it applies to (checkbox dropdown), right = the effect
-- control. First effect: Icon Glow, a 1:1 copy of the BM display-level
-- Icon Glow control (style dropdown + class/custom inline swatches).
-- fxOwner = the PERSISTED table carrying .fxGlow (the dm table for the
-- base pane, the tile table for grid tiles).
local TILE_FILTER_ITEMS = {
    {
        key = "nonplayer",
        label = "Non-Player Auras",
        tooltip = "Debuffs not caused by any player or player pet (this is what shows most pve debuffs).",
    },
    {
        key = "priority",
        label = "Important",
        tooltip = "Debuffs Blizzard flags as priority for raid frames.",
    },
    { key = "cc", label = "Crowd Control", tooltip = "Loss-of-control debuffs." },
    { key = "boss", label = "Boss Debuffs", tooltip = "Debuffs applied by boss encounters." },
    {
        key = "role",
        label = "Boss Role Debuffs",
        tooltip = "Debuffs from enemies that Blizzard labels as relevant to your role.",
    },
    { key = "raid", label = "Raid", tooltip = "Blizzard's curated raid-frame debuff set." },
    {
        key = "raidcombat",
        label = "Raid In Combat",
        tooltip = "The stricter in-combat subset of the raid set.",
    },
    { key = "dispel_you", label = "Dispellable By You", tooltip = "Debuffs you can dispel." },
    {
        key = "dispel_typed",
        label = "Dispels",
        tooltip = "Any debuff with a dispel type (Magic, Curse, Disease, Poison, Bleed), even if you cannot remove it.",
    },
}
-- Single-lane filter checkbox dropdown for per-filter ICON EFFECTS blocks
-- (`claim` is the effect entry's claim-shaped target set). The two dispel
-- entries are mutually exclusive and steer dm.dispelMode. Tile dropdowns use
-- the full two-lane build below instead.
local function BuildFilterCBDropdown(region, claim, dm)
    local Pix = CludesUI.PP or CludesUI.PanelPP
    if region._control then
        region._control:Hide()
    end
    local cbDD = CludesUI.BuildVisOptsCBDropdown(
        region,
        190,
        region:GetFrameLevel() + 2,
        TILE_FILTER_ITEMS,
        function(k)
            if k == "dispel_you" then
                return (claim.dispel and true or false) and dm.dispelMode ~= "typed"
            elseif k == "dispel_typed" then
                return (claim.dispel and true or false) and dm.dispelMode == "typed"
            end
            return claim[k] and true or false
        end,
        function(k, val)
            if k == "dispel_you" or k == "dispel_typed" then
                if val then
                    claim.dispel = true
                    dm.dispelMode = (k == "dispel_typed") and "typed" or "you"
                else
                    claim.dispel = false
                end
                DmApply()
                return
            end
            claim[k] = val and true or false
            DmApply()
        end,
        nil,
        12
    )
    CludesUI.PanelPP.Point(cbDD, "RIGHT", region, "RIGHT", -20, 0)
    region._control = cbDD
    region._lastInline = nil
end
-- Tile filter dropdown: full two-lane parity with the base Filters dropdown
-- (user directive 2026-08-16) plus All Debuffs and the Has Duration
-- AND-modifier. Checked claims also steer ROUTING (a claimed category renders
-- in the tile instead of the base grid), so the show lane stays live even
-- while All Debuffs is checked -- no lane locks here.
local TILE_CA_ALL = "__caAll"
local TILE_CA_DUR = "__caDur"
local TILE_LANE_ITEMS = {
    {
        key = TILE_CA_ALL,
        label = "All Debuffs",
        tooltip = "Show every debuff in this indicator. Use the Hide lane below to remove specific filters.",
    },
    {
        key = TILE_CA_DUR,
        label = "Has Duration",
        tooltip = "Only show debuffs that have a duration, excluding permanent ones. Combines with the filters below; checked alone it shows every timed debuff.",
    },
    { isHeader = true, label = "Show", rightLabel = "Hide" },
    {
        key = "nonplayer",
        label = "Non-Player Auras",
        dual = true,
        tooltip = "Debuffs not caused by any player or player pet (this is what shows most pve debuffs).",
    },
    {
        key = "priority",
        label = "Important",
        dual = true,
        tooltip = "Debuffs Blizzard flags as priority for raid frames.",
    },
    { key = "cc", label = "Crowd Control", dual = true, tooltip = "Loss-of-control debuffs." },
    {
        key = "boss",
        label = "Boss Debuffs",
        dual = true,
        tooltip = "Debuffs applied by boss encounters.",
    },
    {
        key = "role",
        label = "Boss Role Debuffs",
        dual = true,
        tooltip = "Debuffs from enemies that Blizzard labels as relevant to your role.",
    },
    {
        key = "raid",
        label = "Raid",
        dual = true,
        tooltip = "Blizzard's curated raid-frame debuff set.",
    },
    {
        key = "raidcombat",
        label = "Raid In Combat",
        dual = true,
        tooltip = "The stricter in-combat subset of the raid set.",
    },
    {
        key = "dispel_you",
        label = "Dispellable By You",
        dual = true,
        tooltip = "Debuffs you can dispel.",
    },
    {
        key = "dispel_typed",
        label = "Dispels",
        dual = true,
        tooltip = "Any debuff with a dispel type (Magic, Curse, Disease, Poison, Bleed), even if you cannot remove it.",
    },
    { isHeader = true, label = "Less Common Filters" },
    {
        key = "castbyme",
        label = "Cast By You",
        dual = true,
        tooltip = "Debuffs applied by you or your pet.",
    },
    {
        key = "anyplayer",
        label = "From Any Player",
        dual = true,
        tooltip = "Debuffs caused by any player or player pet. The opposite of Non-Player Auras; checking one clears the other.",
    },
    { key = "magic", label = "Magic", dual = true, tooltip = "Debuffs with the Magic dispel type." },
    { key = "curse", label = "Curse", dual = true, tooltip = "Debuffs with the Curse dispel type." },
    { key = "poison", label = "Poison", dual = true, tooltip = "Debuffs with the Poison dispel type." },
    { key = "disease", label = "Disease", dual = true, tooltip = "Debuffs with the Disease dispel type." },
    { key = "bleed", label = "Bleed", dual = true, tooltip = "Debuffs with the Bleed dispel type." },
    {
        key = "canapply",
        label = "Can Apply Aura",
        dual = true,
        tooltip = "Debuffs your own class is able to apply.",
    },
}
-- Two-lane filter write (base grid and tiles): the show lane lives in
-- `show`, the hide lane in `owner.neg`, and the dispel / nonplayer flavors
-- are global (dm). Checking one lane clears the other.
local function DmSetLane(show, ownerFrame, dm, k, val, neg)
    local category, modeKey, mode = k, nil, nil
    if k == "dispel_you" or k == "dispel_typed" then
        category, modeKey, mode = "dispel", "dispelMode", (k == "dispel_typed") and "typed" or "you"
    elseif k == "nonplayer" or k == "anyplayer" then
        category, modeKey, mode = "nonplayer", "nonplayerMode", (k == "anyplayer") and "any" or nil
    end
    if neg and val then
        ownerFrame.neg = ownerFrame.neg or {}
        ownerFrame.neg[category] = true
        show[category] = nil
    else
        if not neg then
            show[category] = val and true or nil
        end
        if (neg or val) and ownerFrame.neg then
            ownerFrame.neg[category] = nil
            if not next(ownerFrame.neg) then
                ownerFrame.neg = nil
            end
        end
    end
    if val and modeKey then
        dm[modeKey] = mode
    end
end
-- Match Mode rows (a radio pair over t.match, nil = Match Any = the union),
-- locked while the tile's All Debuffs shows everything, spliced in after Has
-- Duration like the Base Icons dropdown's.
local TILE_MATCH_ANY = "__tMatchAny"
local TILE_MATCH_ALL = "__tMatchAll"
local function TileLaneItems(t)
    local function Locked()
        return t.all == true
    end
    local lockTip = CludesUI.L("Uncheck All Debuffs to choose how the Show filters combine.")
    local itemList = {}
    for idx = 1, #TILE_LANE_ITEMS do
        local it = TILE_LANE_ITEMS[idx]
        itemList[#itemList + 1] = it
        if it.key == TILE_CA_DUR then
            itemList[#itemList + 1] = { isHeader = true, label = "Match Mode" }
            itemList[#itemList + 1] = {
                key = TILE_MATCH_ANY,
                label = CludesUI.L("Match Any Filter"),
                isModifier = true,
                lockedFn = Locked,
                lockedTooltip = lockTip,
                tooltip = CludesUI.L("Shows debuffs that match any checked Show filter (the default)."),
            }
            itemList[#itemList + 1] = {
                key = TILE_MATCH_ALL,
                label = CludesUI.L("Match All Filters"),
                isModifier = true,
                lockedFn = Locked,
                lockedTooltip = lockTip,
                tooltip = CludesUI.L(
                    "Shows only debuffs that match every checked Show filter (dispel types count as one); the rest stay where they already show."
                ),
            }
        end
    end
    return itemList
end
-- Owner hints on an indicator's Filters rows: each debuff shows in one place,
-- so a category an indicator before this one already shows renders only
-- there -- its row here dims and names that indicator, and All Debuffs does
-- the same while an earlier indicator hosts the catch-all. Match All
-- indicators and frame effects take no hints (claims never stop them). Read
-- once per page build (an edit elsewhere rebuilds the page); hinted rows are
-- copies, never the shared TILE_LANE_ITEMS rows.
local function WithOwnerHints(itemList, t)
    if t.type ~= "icons" and t.type ~= "square" then
        return itemList
    end
    local claims, claimsAll, place = mod.DM_ClaimOwners(dmSpecSel)
    local mine = place[t]
    if not mine then
        return itemList
    end
    local function Earlier(ownerFrame)
        if ownerFrame and place[ownerFrame] < mine then
            return ownerFrame
        end
    end
    local result = {}
    for idx = 1, #itemList do
        local it = itemList[idx]
        local ownerFrame
        if it.dual then
            ownerFrame = Earlier(claims[RowCat(it.key)])
        elseif it.key == TILE_CA_ALL then
            ownerFrame = Earlier(claimsAll)
        end
        if ownerFrame then
            local row = CopyTable(it)
            if it.key == TILE_CA_ALL then
                row.dimFn = function()
                    return true
                end
            else
                row.dimFn = function()
                    return not mod.DM_TileMatchOn(t)
                end
            end
            row.dimTooltip = CludesUI.Lf("Shown by %1$s, which comes first.", TileName(ownerFrame))
            result[#result + 1] = row
        else
            result[#result + 1] = it
        end
    end
    return result
end
local function BuildTileFiltersDD(region, t, dm)
    local Pix = CludesUI.PP or CludesUI.PanelPP
    if region._control then
        region._control:Hide()
    end
    if not t.claim then
        t.claim = {}
    end
    local claim = t.claim
    local function NegHas(category)
        return t.neg ~= nil and t.neg[category] == true
    end
    local warnClosed
    local cbDD, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
        region,
        190,
        region:GetFrameLevel() + 2,
        WithOwnerHints(TileLaneItems(t), t),
        function(k, neg)
            if k == TILE_MATCH_ALL then
                return t.match == "all"
            end
            if k == TILE_MATCH_ANY then
                return t.match ~= "all"
            end
            if k == TILE_CA_ALL then
                return t.all == true
            end
            if k == TILE_CA_DUR then
                return t.hasDuration == true
            end
            if k == "dispel_you" then
                if neg then
                    return NegHas("dispel") and dm.dispelMode ~= "typed"
                end
                return (claim.dispel and true or false) and dm.dispelMode ~= "typed"
            elseif k == "dispel_typed" then
                if neg then
                    return NegHas("dispel") and dm.dispelMode == "typed"
                end
                return (claim.dispel and true or false) and dm.dispelMode == "typed"
            end
            -- Two flavors of ONE nonplayer category (global dm.nonplayerMode).
            if k == "nonplayer" or k == "anyplayer" then
                if (dm.nonplayerMode == "any") ~= (k == "anyplayer") then
                    return false
                end
                if neg then
                    return NegHas("nonplayer")
                end
                return claim.nonplayer and true or false
            end
            if neg then
                return NegHas(k)
            end
            return claim[k] and true or false
        end,
        function(k, val, neg)
            if k == TILE_MATCH_ANY or k == TILE_MATCH_ALL then
                -- Radio pair: the clicked row wins whatever its checked state.
                t.match = (k == TILE_MATCH_ALL) and "all" or nil
                DmApply()
                CludesUI:RefreshPage()
                return
            end
            if k == TILE_CA_ALL or k == TILE_CA_DUR then
                -- Independent bits: All Debuffs = catch-all, Has Duration =
                -- AND-modifier (combinable with All or any claims).
                if k == TILE_CA_ALL then
                    t.all = val and true or nil
                else
                    t.hasDuration = val and true or nil
                end
                DmApply()
                CludesUI:RefreshPage()
                return
            end
            -- The dispel and nonplayer flavors are shared with the base grid.
            DmSetLane(claim, t, dm, k, val, neg)
            DmApply()
            -- Non-force: re-evaluates the base dropdown's empty-selection
            -- warning (tile claims count as grid content) without closing
            -- the menu.
            CludesUI:RefreshPage()
        end,
        nil,
        12,
        nil,
        nil,
        function()
            if warnClosed then
                warnClosed()
            end
        end,
        -- The summary joins picks the way they combine (Base Icons parity).
        {
            separatorFn = function()
                return mod.DM_TileMatchOn(t) and " & " or ", "
            end,
        }
    )
    CludesUI.PanelPP.Point(cbDD, "RIGHT", region, "RIGHT", -20, 0)
    region._control = cbDD
    region._lastInline = nil
    if cbRefresh then
        CludesUI.RegisterWidgetRefresh(cbRefresh)
    end
    -- Match All picks that can never match together show nothing here (the
    -- runtime's own test); an ordinary empty tile keeps its quiet subtitle.
    warnClosed = CludesUI.AttachEmptyFilterWarn(
        region,
        cbDD,
        CludesUI.L("These filters can never match together."),
        function()
            return not mod.DM_TileMatchEmpty(t)
        end
    )
end
local function BuildFxEffects(widget, sy, fxOwner)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PP or CludesUI.PanelPP
    if not (W and Pix) then
        return sy
    end
    local hh
    local MEDIA_MP = "Interface\\AddOns\\CludesUI\\media\\icons\\"

    -- One-time heal: the first Effects build stored a single fxGlow config.
    if fxOwner.fxGlow then
        local fg = fxOwner.fxGlow
        fxOwner.fxList = fxOwner.fxList or {}
        fxOwner.fxList[#fxOwner.fxList + 1] = {
            filters = fg.filters or {},
            glowType = fg.type,
            glowClassColor = fg.classColor,
            glowR = fg.r,
            glowG = fg.g,
            glowB = fg.b,
        }
        fxOwner.fxGlow = nil
    end
    local entries = fxOwner.fxList or {}

    local GO = CludesUI.GlowOptions

    -- One "ICON EFFECTS" section block per list entry.
    for bi = 1, #entries do
        local e = entries[bi]
        if not e.filters then
            e.filters = {}
        end

        local hdrRgn
        hdrRgn, hh = W:SectionHeader(widget, "ICON EFFECTS", sy)
        sy = sy - hh
        -- Remove X right after the section title text
        if hdrRgn then
            local del = CreateFrame("Button", nil, hdrRgn)
            del:SetSize(14, 14)
            if hdrRgn._label then
                del:SetPoint("LEFT", hdrRgn._label, "RIGHT", 8, 0)
            else
                del:SetPoint("BOTTOMRIGHT", hdrRgn, "BOTTOMRIGHT", 0, 6)
            end
            del:SetFrameLevel(hdrRgn:GetFrameLevel() + 2)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then
                dx:SetSnapToPixelGrid(false)
                dx:SetTexelSnappingBias(0)
            end
            dx:SetTexture(MEDIA_MP .. "cui-close.png")
            del:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                CludesUI.ShowWidgetTooltip(self, CludesUI.L("Delete"))
            end)
            del:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                CludesUI.HideWidgetTooltip()
            end)
            local blockIdx = bi
            del:SetScript("OnClick", function()
                table.remove(entries, blockIdx)
                ApplyAndRedraw()
            end)
        end

        -- Row 1: Filters | Icon Glow (shared glow controls)
        local glowDesc = GO.PrefixSite(function()
            return e
        end, "glow", "engine", DmApply)
        -- The half next to Filters is too narrow for the color swatches.
        glowDesc.colorInCog = true
        local row
        row, hh = W:DualRow(widget, sy, {
            type = "dropdown",
            text = "Filters",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        }, GO.DropdownSpec(glowDesc, "Icon Glow"))
        sy = sy - hh
        do
            -- The SAME filter dropdown as Assigned Debuffs / tile panes
            -- (shared items incl. the split dispel entries + tooltips).
            if not e.filters then
                e.filters = {}
            end
            BuildFilterCBDropdown(row._leftRegion, e.filters, DmTable() or {})
        end
        GO.AttachInline(row._rightRegion, glowDesc)

        -- Row 2: Border (+ swatch, the DISPLAY-section Border style) | Size
        -- (icon size for the matched filters; 0 = the grid's own size).
        local bRow
        bRow, hh = W:DualRow(widget, sy, {
            type = "slider",
            text = "Border",
            min = 0,
            max = 4,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return e.borderSize or 0
            end,
            setValue = function(val)
                e.borderSize = val
                DmApply()
            end,
        }, {
            type = "slider",
            text = "Size",
            min = 0,
            max = 80,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return e.size or 0
            end,
            setValue = function(val)
                e.size = (val and val > 0) and val or nil
                DmApply()
            end,
        })
        sy = sy - hh
        do
            local region = bRow._leftRegion
            local swatch = CludesUI.BuildColorSwatch(region, bRow:GetFrameLevel() + 3, function()
                local c = e.borderColor or { r = 0, g = 0, b = 0 }
                return c.r or 0, c.g or 0, c.b or 0, 1
            end, function(r, g, b)
                e.borderColor = { r = r, g = g, b = b }
                DmApply()
            end, false, 20)
            swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = swatch
        end
    end

    -- "Add Icon Effects Per-Filter" accent text link (centered)
    do
        local ar, ag, ab = 1, 0.82, 0.30
        if CludesUI.GetAccentColor then
            ar, ag, ab = CludesUI.GetAccentColor()
        end
        local addBtn = CreateFrame("Button", nil, widget)
        addBtn:SetHeight(22)
        addBtn:SetPoint("TOP", widget, "TOP", 0, sy - 17)
        addBtn:SetFrameLevel(widget:GetFrameLevel() + 2)
        local labelFS = addBtn:CreateFontString(nil, "OVERLAY")
        local fp = (CludesUI.GetFontPath("options")) or "Fonts\\FRIZQT__.TTF"
        labelFS:SetFont(fp, 16, "")
        labelFS:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
        labelFS:SetText(CludesUI.L("Add Icon Effects Per-Filter"))
        labelFS:SetTextColor(ar, ag, ab)
        labelFS:SetAlpha(0.9)
        addBtn:SetWidth(labelFS:GetStringWidth() + 8)
        addBtn:SetScript("OnEnter", function()
            labelFS:SetAlpha(1)
        end)
        addBtn:SetScript("OnLeave", function()
            labelFS:SetAlpha(0.9)
        end)
        addBtn:SetScript("OnClick", function()
            if not fxOwner.fxList then
                fxOwner.fxList = {}
            end
            fxOwner.fxList[#fxOwner.fxList + 1] = { filters = {} }
            CludesUI:RefreshPage(true)
        end)
        sy = sy - 17 - 22 - 8
    end
    return sy
end

-- Shared tile Filters checkbox dropdown (grid AND effect tiles): identical
-- items/behavior to the Base Icons pane's Base Filters dropdown, writing the tile's
-- t.claim set (the dispel flavors also steer the global mode). Auto-default growth for
-- a just-picked anchor (BM parity): icons flow INTO the frame from the anchored edge;
-- the user can still override the growth afterwards.
local function DmDefaultGrow(place)
    if place == "right" or place == "topright" or place == "bottomright" then
        return "LEFT"
    end
    if place == "left" or place == "topleft" or place == "bottomleft" then
        return "RIGHT"
    end
    if place == "top" then
        return "DOWN"
    end
    if place == "bottom" then
        return "UP"
    end
    return "CENTER"
end

-- Detail builders (left pane). Each builds W rows on `frame` and manages
-- its own vertical cursor.
local function BuildBaseDetailDM(widget, fontFile)
    local W = CludesUI.Widgets
    local p = DmProfile()
    local dm = DmTable()
    if not (W and p and dm) then
        return 0
    end
    widget._showRowDivider = true
    local sy, hh = 0, 0
    -- A local _: the global _ would hold the last row, and through it the page.
    local _

    _, hh = W:SectionHeader(widget, "ASSIGNED DEBUFFS", sy)
    sy = sy - hh

    -- Unified Filters dropdown (Player Aura Bars parity): pinned "All Debuffs" row
    -- above a Show/Hide caption row, then TWO-LANE category rows -- ONE control,
    -- live in both modes. The left checkbox SHOWS a category (dm[cat], add mode;
    -- dimmed while All Debuffs is on), the right red box HIDES it (dm.neg[cat],
    -- subtracting in both modes -- see BuildRecords). Lanes are mutually exclusive
    -- per category and persist across mode flips.
    local safRow
    safRow, hh = W:DualRow(
        widget,
        sy,
        {
            type = "dropdown",
            text = "Filters",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        },
        CludesUI.MaxDurationDropdown(function()
            return dm.maxDurSec
        end, function(val)
            dm.maxDurSec = val
        end, DmApply)
    )
    sy = sy - hh
    do
        local PPl = CludesUI.PP or CludesUI.PanelPP
        local region = safRow._leftRegion
        if region._control then
            region._control:Hide()
        end
        local DM_ALL_KEY = "__all"
        local DM_DUR_KEY = "__hasDuration"
        local DM_HIDE_EXH = "__hideExhaustion"
        local DM_MATCH_ANY = "__matchAny"
        local DM_MATCH_ALL = "__matchAll"
        local function AllOn()
            return dm.all ~= false
        end
        local matchLockTip = CludesUI.L("Uncheck All Debuffs to choose how the Show filters combine.")
        local FILTER_ITEMS = {
            {
                key = DM_ALL_KEY,
                label = "All Debuffs",
                tooltip = "Show every debuff. Use the Hide lane below to remove specific filters.",
            },
            {
                key = DM_DUR_KEY,
                label = "Has Duration",
                tooltip = "Only show debuffs that have a duration, excluding permanent ones. Combines with the filters below; checked alone it shows every timed debuff.",
            },
            -- Hide Exhaustion: a view over the profile's hideLustDebuff (on by
            -- default), which every raid and party debuff display reads. Kept out
            -- of the summary, so the default reads as before.
            {
                key = DM_HIDE_EXH,
                label = "Hide Exhaustion",
                tooltip = "Hides Sated, Exhaustion, Temporal Displacement and the other Bloodlust lockout debuffs.",
                excludeFromSummaryFn = function()
                    return true
                end,
            },
            -- Match Mode: modifier rows (out of the summary and the count), a
            -- radio pair over dm.match (nil = Match Any = the union). Locked
            -- while All Debuffs shows everything; the setting is kept.
            { isHeader = true, label = "Match Mode" },
            {
                key = DM_MATCH_ANY,
                label = CludesUI.L("Match Any Filter"),
                isModifier = true,
                lockedFn = AllOn,
                lockedTooltip = matchLockTip,
                tooltip = CludesUI.L("Shows debuffs that match any checked Show filter (the default)."),
            },
            {
                key = DM_MATCH_ALL,
                label = CludesUI.L("Match All Filters"),
                isModifier = true,
                lockedFn = AllOn,
                lockedTooltip = matchLockTip,
                tooltip = CludesUI.L(
                    "Shows only debuffs that match every checked Show filter (dispel types count as one); opposites like Non-Player Auras with Cast By You, or a filter an indicator shows, show nothing."
                ),
            },
            { isHeader = true, label = "Show", rightLabel = "Hide" },
            {
                key = "nonplayer",
                label = "Non-Player Auras",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs not caused by any player or player pet (this is what shows most pve debuffs).",
            },
            {
                key = "priority",
                label = "Important",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs Blizzard flags as priority for raid frames.",
            },
            {
                key = "cc",
                label = "Crowd Control",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Loss-of-control debuffs. When shown, these lead the row and carry the CC glow.",
            },
            {
                key = "boss",
                label = "Boss Debuffs",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs applied by boss encounters.",
            },
            {
                key = "role",
                label = "Boss Role Debuffs",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs from enemies that Blizzard labels as relevant to your role.",
            },
            {
                key = "raid",
                label = "Raid",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Blizzard's curated raid-frame debuff set.",
            },
            {
                key = "raidcombat",
                label = "Raid In Combat",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "The stricter in-combat subset of the raid set.",
            },
            -- Two flavors of ONE dispel category (mutually exclusive across rows
            -- AND lanes -- either lane's check flips the mode, the widget
            -- refreshes both rows):
            {
                key = "dispel_you",
                label = "Dispellable By You",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs you can dispel.",
            },
            {
                key = "dispel_typed",
                label = "Dispels",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Any debuff with a dispel type (Magic, Curse, Disease, Poison, Bleed), even if you cannot remove it.",
            },
            -- Less common filters: same two-lane rows, engine-evaluated like the
            -- rest. From Any Player is the other flavor of Non-Player Auras.
            { isHeader = true, label = "Less Common Filters" },
            {
                key = "castbyme",
                label = "Cast By You",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs applied by you or your pet.",
            },
            {
                key = "anyplayer",
                label = "From Any Player",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs caused by any player or player pet. The opposite of Non-Player Auras; checking one clears the other.",
            },
            {
                key = "magic",
                label = "Magic",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs with the Magic dispel type.",
            },
            {
                key = "curse",
                label = "Curse",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs with the Curse dispel type.",
            },
            {
                key = "poison",
                label = "Poison",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs with the Poison dispel type.",
            },
            {
                key = "disease",
                label = "Disease",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs with the Disease dispel type.",
            },
            {
                key = "bleed",
                label = "Bleed",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs with the Bleed dispel type.",
            },
            {
                key = "canapply",
                label = "Can Apply Aura",
                dual = true,
                showLockedFn = AllOn,
                tooltip = "Debuffs your own class is able to apply.",
            },
        }
        -- Hovering a dimmed Show box explains the dim (the lane is inert
        -- while All Debuffs already shows everything). Has Duration is an
        -- AND-modifier, not a mode: it never locks the lane.
        do
            local lockedTip = L(
                "All Debuffs is selected, so every debuff already shows. Use the red Hide box to exclude these instead."
            )
            for idx = 1, #FILTER_ITEMS do
                if FILTER_ITEMS[idx].dual then
                    FILTER_ITEMS[idx].showLockedTooltip = lockedTip
                end
            end
        end
        -- Each debuff shows in one place: a category an indicator shows is
        -- never shown here, so its row dims and names that indicator. Read
        -- once per page build (an edit on an indicator rebuilds the page).
        do
            local claims = mod.DM_ClaimOwners(dmSpecSel)
            for idx = 1, #FILTER_ITEMS do
                local it = FILTER_ITEMS[idx]
                local ownerFrame = it.dual and claims[RowCat(it.key)]
                if ownerFrame then
                    it.dimFn = function()
                        return true
                    end
                    it.dimTooltip = CludesUI.Lf("Shown by %1$s instead.", TileName(ownerFrame))
                end
            end
        end
        local function NegHas(category)
            return dm.neg ~= nil and dm.neg[category] == true
        end
        -- One of the grid's content sources (with All Debuffs and enabled
        -- claiming tiles -- see DmHasContent).
        local function AnyShowCat()
            return dm.boss == true
                or dm.role == true
                or dm.priority == true
                or dm.cc == true
                or dm.raid == true
                or dm.raidcombat == true
                or dm.dispel == true
                or dm.nonplayer == true
                or dm.castbyme == true
                or dm.magic == true
                or dm.curse == true
                or dm.poison == true
                or dm.disease == true
                or dm.bleed == true
                or dm.canapply == true
        end
        -- Empty selections are LEGAL here (user directive 2026-08-16, the
        -- same reversal PAB got): any content source can be unchecked,
        -- including the last one, and CludesUI.AttachEmptyFilterWarn owns
        -- the loud feedback (red dropdown border + persistent bubble +
        -- close-pulse) while the grid displays nothing. Enabled tiles with
        -- claimed categories still render those categories under an empty
        -- base selection (EffectiveState forces eff[cat] on for claims and
        -- fx routing), so a claims-only grid displays debuffs and must not
        -- warn -- the same rule that keeps fx-forced PAB bars silent.
        -- Match All picks that can never match build nothing, so they count
        -- as an empty base (the runtime's own test, ns.DM_MatchEmpty).
        local warnClosed
        local function DmHasContent()
            if AllOn() then
                return true
            end
            if AnyShowCat() then
                if not (mod.DM_MatchEmpty and mod.DM_MatchEmpty(dm)) then
                    return true
                end
            elseif dm.hasDuration == true then
                return true
            end
            local tiles = mod.DM_ActiveTiles and mod.DM_ActiveTiles()
            if tiles then
                for idx = 1, #tiles do
                    local t = tiles[idx]
                    if t.enabled then
                        if t.all == true then
                            return true
                        end
                        -- A Match All indicator whose picks can never match shows nothing.
                        if not mod.DM_TileMatchEmpty(t) then
                            if t.hasDuration == true then
                                return true
                            end
                            if t.claim then
                                for _, on in pairs(t.claim) do
                                    if on then
                                        return true
                                    end
                                end
                            end
                        end
                    end
                end
            end
            return false
        end
        local cbDD, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
            region,
            190,
            region:GetFrameLevel() + 2,
            FILTER_ITEMS,
            function(k, neg)
                if k == DM_ALL_KEY then
                    return AllOn()
                end
                if k == DM_DUR_KEY then
                    return dm.hasDuration == true
                end
                if k == DM_HIDE_EXH then
                    return p.hideLustDebuff ~= false
                end
                if k == DM_MATCH_ALL then
                    return dm.match == "all"
                end
                if k == DM_MATCH_ANY then
                    return dm.match ~= "all"
                end
                if k == "dispel_you" then
                    if neg then
                        return NegHas("dispel") and dm.dispelMode ~= "typed"
                    end
                    return dm.dispel == true and dm.dispelMode ~= "typed"
                elseif k == "dispel_typed" then
                    if neg then
                        return NegHas("dispel") and dm.dispelMode == "typed"
                    end
                    return dm.dispel == true and dm.dispelMode == "typed"
                end
                -- Two flavors of ONE nonplayer category (dm.nonplayerMode).
                if k == "nonplayer" or k == "anyplayer" then
                    if (dm.nonplayerMode == "any") ~= (k == "anyplayer") then
                        return false
                    end
                    if neg then
                        return NegHas("nonplayer")
                    end
                    return dm.nonplayer == true
                end
                if neg then
                    return NegHas(k)
                end
                return dm[k] == true
            end,
            function(k, val, neg)
                if k == DM_ALL_KEY then
                    -- Lanes persist across mode flips (the hide lane subtracts in
                    -- both modes; the show lane goes dormant while All is on).
                    dm.all = val and true or false
                    DmApply()
                    CludesUI:RefreshPage()
                    return
                end
                if k == DM_DUR_KEY then
                    -- AND-modifier: combines with All Debuffs or any show-lane
                    -- selection; checked alone it acts as the timed catch-all.
                    dm.hasDuration = val or nil
                    DmApply()
                    CludesUI:RefreshPage()
                    return
                end
                if k == DM_HIDE_EXH then
                    p.hideLustDebuff = val and true or false
                    DmApply()
                    CludesUI:RefreshPage()
                    return
                end
                if k == DM_MATCH_ANY or k == DM_MATCH_ALL then
                    -- Radio pair: the clicked row wins whatever its checked
                    -- state (re-clicking the active row keeps it).
                    dm.match = (k == DM_MATCH_ALL) and "all" or nil
                    DmApply()
                    CludesUI:RefreshPage()
                    return
                end
                DmSetLane(dm, dm, dm, k, val, neg)
                DmApply()
                -- Non-force: re-evaluates the empty-selection warning (and
                -- any other widget refreshers) without closing the menu.
                CludesUI:RefreshPage()
            end,
            nil,
            12,
            nil,
            nil,
            function()
                if warnClosed then
                    warnClosed()
                end
            end,
            -- The summary joins picks the way they combine; Match Any (and
            -- the locked state under All Debuffs) keeps the plain list.
            {
                separatorFn = function()
                    return (dm.match == "all" and not AllOn()) and " & " or ", "
                end,
            }
        )
        CludesUI.PanelPP.Point(cbDD, "RIGHT", region, "RIGHT", -20, 0)
        region._control = cbDD
        region._lastInline = nil
        if cbRefresh then
            CludesUI.RegisterWidgetRefresh(cbRefresh)
        end
        warnClosed = CludesUI.AttachEmptyFilterWarn(
            region,
            cbDD,
            L("You are displaying NO debuffs at all."),
            DmHasContent
        )
    end

    _, hh = W:SectionHeader(widget, "CORE", sy)
    sy = sy - hh

    -- Row: Size (+ Icon Zoom cog) | Max Debuffs
    local sizeRow
    sizeRow, hh = W:DualRow(widget, sy, {
        type = "slider",
        text = "Size",
        min = 10,
        max = 80,
        step = 1,
        trackWidth = 120,
        getValue = function()
            return p.debuffSize or 18
        end,
        setValue = function(val)
            p.debuffSize = val
            DmApply()
        end,
    }, {
        type = "slider",
        text = "Max Debuffs",
        min = 1,
        max = 10,
        step = 1,
        trackWidth = 120,
        getValue = function()
            return p.debuffCap or 3
        end,
        setValue = function(val)
            p.debuffCap = val
            DmApply()
        end,
    })
    sy = sy - hh
    do
        local region = sizeRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Icon Zoom",
            rows = {
                {
                    type = "slider",
                    label = "Zoom",
                    min = 0,
                    max = 0.20,
                    step = 0.01,
                    get = function()
                        return p.debuffIconZoom or 0.08
                    end,
                    set = function(val)
                        p.debuffIconZoom = val
                        DmApply()
                    end,
                },
            },
        })
    end

    -- Row: Position (+ offsets cog) | Growth Direction
    local posRow2
    posRow2, hh = W:DualRow(widget, sy, {
        type = "dropdown",
        text = "Position",
        values = POS_VALUES,
        order = POS_ORDER,
        getValue = function()
            return p.debuffPosition or "bottomright"
        end,
        setValue = function(val)
            p.debuffPosition = val
            p.debuffGrowDirection = DmDefaultGrow(val)
            DmApply()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "dropdown",
        text = "Growth Direction",
        values = GROW_VALUES,
        order = GROW_ORDER,
        getValue = function()
            return p.debuffGrowDirection or "LEFT"
        end,
        setValue = function(val)
            p.debuffGrowDirection = val
            DmApply()
        end,
    })
    sy = sy - hh
    do
        local region = posRow2._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Position Offset",
            rows = {
                {
                    type = "slider",
                    label = "Offset X",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        return p.debuffOffsetX or 0
                    end,
                    set = function(val)
                        p.debuffOffsetX = val
                        DmApply()
                    end,
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        return p.debuffOffsetY or 0
                    end,
                    set = function(val)
                        p.debuffOffsetY = val
                        DmApply()
                    end,
                },
            },
        })
    end

    -- Row: Icons Per Row | Spacing. The key predates this UI (its row
    -- died with the Auras tab): >= 2 wraps -- rows for horizontal growth,
    -- COLUMNS for vertical (12.1 flow axis) -- with the stored
    -- debuffWrapDirection convention deciding the stack side.
    _, hh = W:DualRow(widget, sy, {
        type = "slider",
        text = "Icons Per Row",
        min = 0,
        max = 20,
        step = 1,
        trackWidth = 120,
        tooltip = "Wraps into a new row (or column for vertical growth) after this many icons; below 2 keeps one continuous run.",
        getValue = function()
            return p.debuffPerRow or 5
        end,
        setValue = function(val)
            p.debuffPerRow = val
            DmApply()
        end,
    }, {
        type = "slider",
        pixel = true,
        text = "Spacing",
        min = -1,
        max = 10,
        step = 1,
        trackWidth = 120,
        getValue = function()
            return p.debuffSpacing or 1
        end,
        setValue = function(val)
            p.debuffSpacing = val
            DmApply()
        end,
    })
    sy = sy - hh

    -- Display: the legacy debuff style keys (retired Auras tab), which the
    -- base grid and icon tiles read directly. CC glow settings are
    -- deliberately NOT surfaced here (separate follow-up). Party frames
    -- sync from these keys unless an old party override exists.
    _, hh = W:SectionHeader(widget, "DISPLAY", sy)
    sy = sy - hh

    sy = mod.RFO_AuraBorderSettings(widget, sy, W, function(k)
        return p["debuffBorder" .. k]
    end, function(k, val)
        p["debuffBorder" .. k] = val
    end, DmApply, nil, true)

    -- Row: Show Duration Text (+ cog + swatch) | Show Stacks (+ cog + swatch)
    local dtRow
    dtRow, hh = W:DualRow(widget, sy, {
        type = "toggle",
        text = "Show Duration Text",
        getValue = function()
            return p.debuffShowDurText and true or false
        end,
        setValue = function(val)
            p.debuffShowDurText = val
            DmApply()
        end,
    }, {
        type = "toggle",
        text = "Show Stacks",
        getValue = function()
            return p.debuffShowStacks ~= false
        end,
        setValue = function(val)
            p.debuffShowStacks = val
            DmApply()
        end,
    })
    sy = sy - hh
    do
        local region = dtRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Duration Text",
            rows = {
                {
                    type = "slider",
                    label = "Text Size",
                    min = 6,
                    max = 26,
                    step = 1,
                    get = function()
                        return p.debuffDurTextSize or 10
                    end,
                    set = function(val)
                        p.debuffDurTextSize = val
                        DmApply()
                    end,
                },
                {
                    type = "slider",
                    label = "Offset X",
                    min = -20,
                    max = 20,
                    step = 1,
                    get = function()
                        return p.debuffDurTextOffsetX or 0
                    end,
                    set = function(val)
                        p.debuffDurTextOffsetX = val
                        DmApply()
                    end,
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -20,
                    max = 20,
                    step = 1,
                    get = function()
                        return p.debuffDurTextOffsetY or 0
                    end,
                    set = function(val)
                        p.debuffDurTextOffsetY = val
                        DmApply()
                    end,
                },
            },
        })

        local swatch = CludesUI.BuildColorSwatch(region, dtRow:GetFrameLevel() + 3, function()
            local c = p.debuffDurTextColor or { r = 1, g = 1, b = 1 }
            return c.r or 1, c.g or 1, c.b or 1, 1
        end, function(r, g, b)
            p.debuffDurTextColor = { r = r, g = g, b = b }
            DmApply()
        end, false, 20)
        swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = swatch
    end
    do
        local region = dtRow._rightRegion
        CludesUI.BuildInlineCog(region, {
            title = "Stacks Text",
            rows = {
                {
                    type = "slider",
                    label = "Text Size",
                    min = 6,
                    max = 26,
                    step = 1,
                    get = function()
                        return p.debuffStacksTextSize or 11
                    end,
                    set = function(val)
                        p.debuffStacksTextSize = val
                        DmApply()
                    end,
                },
                {
                    type = "slider",
                    label = "Offset X",
                    min = -20,
                    max = 20,
                    step = 1,
                    get = function()
                        return p.debuffStacksOffsetX or 0
                    end,
                    set = function(val)
                        p.debuffStacksOffsetX = val
                        DmApply()
                    end,
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -20,
                    max = 20,
                    step = 1,
                    get = function()
                        return p.debuffStacksOffsetY or 0
                    end,
                    set = function(val)
                        p.debuffStacksOffsetY = val
                        DmApply()
                    end,
                },
            },
        })

        local swatch = CludesUI.BuildColorSwatch(region, dtRow:GetFrameLevel() + 3, function()
            local c = p.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
            return c.r or 1, c.g or 1, c.b or 1, 1
        end, function(r, g, b)
            p.debuffStacksTextColor = { r = r, g = g, b = b }
            DmApply()
        end, false, 20)
        swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = swatch
    end

    -- Row: Tooltips | Show Duration Swipe. The swipe toggle was not in
    -- the requested layout but silently orphaning a stored setting is
    -- worse -- parked here pending a call on removing it outright.
    local tipRow
    tipRow, hh = W:DualRow(widget, sy, {
        type = "dropdown",
        text = "Tooltips",
        values = TIP_VALUES,
        order = TIP_ORDER,
        getValue = function()
            return TipModeKey(p.debuffHideTooltips)
        end,
        setValue = function(k)
            p.debuffHideTooltips = TipModeStore(k)
            DmApply()
            CludesUI:RefreshPage() -- update the Use Modifier cog disabled state
        end,
    }, {
        type = "toggle",
        text = "Show Duration Swipe",
        getValue = function()
            return p.debuffShowSwipe ~= false
        end,
        setValue = function(val)
            p.debuffShowSwipe = val
            DmApply()
        end,
    })
    sy = sy - hh

    -- "Use Modifier" cog on Tooltips (left region): picks the key for the
    -- "Shown on Modifier" mode, so it is only available there. While that
    -- mode is selected with the key still at None, the cog hover warns that
    -- tooltips will always show (the runtime degrades to plain Shown).
    do
        local leftRgn = tipRow._leftRegion
        local function tipOff()
            return TipModeKey(p.debuffHideTooltips) ~= "modifier"
        end
        local tipModBtn = CludesUI.BuildInlineCog(leftRgn, {
            gap = 9,
            disabled = tipOff,
            -- Whole sentence: DisabledTooltip passes "This option..." strings through verbatim (still localized).
            disabledTooltip = "This option requires Tooltips to be set to Shown on Modifier",
            title = "Tooltips",
            rows = {
                {
                    type = "dropdown",
                    label = "Use Modifier",
                    values = { none = "None", shift = "Shift", control = "Control", alt = "Alt" },
                    order = { "none", "shift", "control", "alt" },
                    get = function()
                        return p.debuffTooltipModifier or "none"
                    end,
                    set = function(val)
                        p.debuffTooltipModifier = val
                        DmApply()
                        CludesUI:RefreshPage() -- clear/raise the no-key warning bubble
                    end,
                },
            },
        })
        if tipModBtn then
            tipModBtn:HookScript("OnEnter", function(self)
                if (p.debuffTooltipModifier or "none") == "none" then
                    CludesUI.ShowWidgetTooltip(
                        self,
                        "Select a modifier key here, or tooltips will always be shown"
                    )
                end
            end)
            tipModBtn:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            -- Persistent red bubble above the cog while Shown on Modifier is
            -- selected with no key picked (the standard empty-selection warning);
            -- the hover tooltip above keeps the explanation.
            CludesUI.AttachEmptyFilterWarn(leftRgn, tipModBtn, L("Select a Modifier"), function()
                return tipOff() or (p.debuffTooltipModifier or "none") ~= "none"
            end)
        end
    end

    sy = BuildFxEffects(widget, sy, dm)
    return sy
end

local function BuildTileDetail(widget, fontFile, t)
    local W = CludesUI.Widgets
    if not W then
        return 0
    end
    widget._showRowDivider = true
    local sy, hh = 0, 0
    -- A local _: the global _ would hold the last row, and through it the page.
    local _

    local function TSet(key, val)
        t[key] = val
        DmApply()
    end

    if t.type == "icons" or t.type == "square" then
        -- Grid tiles (Icon / Square): the Base Icons pane layout 1:1, with
        -- per-tile style values as VIEWS over the base debuff style keys
        -- (nil = inherit; getters show the effective value).
        local p = DmProfile() or {}
        local dm = DmTable() or {}
        local function TEff(key, baseKey, default)
            local val = t[key]
            if key == "borderSizePx" and val == nil and (t.borderSize ~= nil or t.borderTexture ~= nil) then
                return false
            end
            if val == nil then
                val = p[baseKey]
            end
            if val == nil then
                val = default
            end
            return val
        end
        local function TBoolOn(key, baseKey) -- base default ON
            if t[key] ~= nil then
                return t[key] and true or false
            end
            return p[baseKey] ~= false
        end
        local function TBoolOff(key, baseKey) -- base default OFF
            if t[key] ~= nil then
                return t[key] and true or false
            end
            return p[baseKey] and true or false
        end

        _, hh = W:SectionHeader(widget, "ASSIGNED DEBUFFS", sy)
        sy = sy - hh

        local fRow
        fRow, hh = W:DualRow(
            widget,
            sy,
            {
                type = "dropdown",
                text = "Filters",
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function()
                    return "__placeholder"
                end,
                setValue = function() end,
            },
            CludesUI.MaxDurationDropdown(function()
                return t.maxDurSec
            end, function(val)
                t.maxDurSec = val
            end, DmApply)
        )
        sy = sy - hh
        BuildTileFiltersDD(fRow._leftRegion, t, dm)

        _, hh = W:SectionHeader(widget, "CORE", sy)
        sy = sy - hh

        -- Row: Size (+ Icon Zoom cog) | Max Debuffs
        local sizeRow
        sizeRow, hh = W:DualRow(widget, sy, {
            type = "slider",
            text = "Size",
            min = 10,
            max = 80,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return t.size or 18
            end,
            setValue = function(val)
                TSet("size", val)
            end,
        }, {
            type = "slider",
            text = "Max Debuffs",
            min = 1,
            max = 10,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return t.cap or 3
            end,
            setValue = function(val)
                TSet("cap", val)
            end,
        })
        sy = sy - hh
        do
            local region = sizeRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Icon Zoom",
                rows = {
                    {
                        type = "slider",
                        label = "Zoom",
                        min = 0,
                        max = 0.20,
                        step = 0.01,
                        get = function()
                            return TEff("iconZoom", "debuffIconZoom", 0.08)
                        end,
                        set = function(val)
                            TSet("iconZoom", val)
                        end,
                    },
                },
            })
        end

        -- Row: Position (+ offsets cog) | Growth Direction
        local posRow2
        posRow2, hh = W:DualRow(widget, sy, {
            type = "dropdown",
            text = "Position",
            values = POS_VALUES,
            order = POS_ORDER,
            getValue = function()
                return t.position or "top"
            end,
            setValue = function(val)
                t.growDirection = DmDefaultGrow(val)
                TSet("position", val)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Growth Direction",
            values = GROW_VALUES,
            order = GROW_ORDER,
            getValue = function()
                return t.growDirection or "CENTER"
            end,
            setValue = function(val)
                TSet("growDirection", val)
            end,
        })
        sy = sy - hh
        do
            local region = posRow2._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Position Offset",
                rows = {
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return t.offsetX or 0
                        end,
                        set = function(val)
                            TSet("offsetX", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return t.offsetY or 0
                        end,
                        set = function(val)
                            TSet("offsetY", val)
                        end,
                    },
                },
            })
        end

        -- Row: Icons Per Row | Spacing. Tile-local key, no base
        -- inheritance: >= 2 wraps the tile's run -- rows for horizontal
        -- growth, COLUMNS for vertical -- stacking away from the anchored
        -- edge (position rule).
        _, hh = W:DualRow(widget, sy, {
            type = "slider",
            text = "Icons Per Row",
            min = 0,
            max = 20,
            step = 1,
            trackWidth = 120,
            tooltip = "Wraps into a new row (or column for vertical growth) after this many icons; below 2 keeps one continuous run.",
            getValue = function()
                return t.iconsPerRow or 0
            end,
            setValue = function(val)
                TSet("iconsPerRow", val)
            end,
        }, {
            type = "slider",
            pixel = true,
            text = "Spacing",
            min = -1,
            max = 10,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return t.spacing or 1
            end,
            setValue = function(val)
                TSet("spacing", val)
            end,
        })
        sy = sy - hh

        _, hh = W:SectionHeader(widget, "DISPLAY", sy)
        sy = sy - hh

        sy = mod.RFO_AuraBorderSettings(widget, sy, W, function(k)
            return TEff("border" .. k, "debuffBorder" .. k)
        end, function(k, val)
            t["border" .. k] = val
        end, DmApply, nil, true)

        -- Row: Show Duration Text (+ cog + swatch) | Show Stacks (+ cog + swatch)
        local dtRow
        dtRow, hh = W:DualRow(widget, sy, {
            type = "toggle",
            text = "Show Duration Text",
            getValue = function()
                return TBoolOff("showDurText", "debuffShowDurText")
            end,
            setValue = function(val)
                TSet("showDurText", val and true or false)
            end,
        }, {
            type = "toggle",
            text = "Show Stacks",
            getValue = function()
                return TBoolOn("showStacks", "debuffShowStacks")
            end,
            setValue = function(val)
                TSet("showStacks", val and true or false)
            end,
        })
        sy = sy - hh
        do
            local region = dtRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Duration Text",
                rows = {
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 26,
                        step = 1,
                        get = function()
                            return TEff("durTextSize", "debuffDurTextSize", 10)
                        end,
                        set = function(val)
                            TSet("durTextSize", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -20,
                        max = 20,
                        step = 1,
                        get = function()
                            return TEff("durTextOffsetX", "debuffDurTextOffsetX", 0)
                        end,
                        set = function(val)
                            TSet("durTextOffsetX", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -20,
                        max = 20,
                        step = 1,
                        get = function()
                            return TEff("durTextOffsetY", "debuffDurTextOffsetY", 0)
                        end,
                        set = function(val)
                            TSet("durTextOffsetY", val)
                        end,
                    },
                },
            })

            local swatch = CludesUI.BuildColorSwatch(region, dtRow:GetFrameLevel() + 3, function()
                local c = t.durTextColor or p.debuffDurTextColor or { r = 1, g = 1, b = 1 }
                return c.r or 1, c.g or 1, c.b or 1, 1
            end, function(r, g, b)
                t.durTextColor = { r = r, g = g, b = b }
                DmApply()
            end, false, 20)
            swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = swatch
        end
        do
            local region = dtRow._rightRegion
            CludesUI.BuildInlineCog(region, {
                title = "Stacks Text",
                rows = {
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 26,
                        step = 1,
                        get = function()
                            return TEff("stacksTextSize", "debuffStacksTextSize", 11)
                        end,
                        set = function(val)
                            TSet("stacksTextSize", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -20,
                        max = 20,
                        step = 1,
                        get = function()
                            return TEff("stacksOffsetX", "debuffStacksOffsetX", 0)
                        end,
                        set = function(val)
                            TSet("stacksOffsetX", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -20,
                        max = 20,
                        step = 1,
                        get = function()
                            return TEff("stacksOffsetY", "debuffStacksOffsetY", 0)
                        end,
                        set = function(val)
                            TSet("stacksOffsetY", val)
                        end,
                    },
                },
            })

            local swatch = CludesUI.BuildColorSwatch(region, dtRow:GetFrameLevel() + 3, function()
                local c = t.stacksTextColor or p.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
                return c.r or 1, c.g or 1, c.b or 1, 1
            end, function(r, g, b)
                t.stacksTextColor = { r = r, g = g, b = b }
                DmApply()
            end, false, 20)
            swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = swatch
        end

        -- Row: Tooltips | Show Duration Swipe (base pane parity)
        _, hh = W:DualRow(widget, sy, {
            type = "dropdown",
            text = "Tooltips",
            values = TIP_VALUES,
            order = TIP_ORDER,
            getValue = function()
                local val = t.hideTooltips
                if val == nil then
                    val = p.debuffHideTooltips
                end
                return TipModeKey(val)
            end,
            setValue = function(k)
                TSet("hideTooltips", TipModeStore(k))
            end,
        }, {
            type = "toggle",
            text = "Show Duration Swipe",
            getValue = function()
                return TBoolOn("showSwipe", "debuffShowSwipe")
            end,
            setValue = function(val)
                TSet("showSwipe", val and true or false)
            end,
        })
        sy = sy - hh

        -- Square only: the block color the flat squares render with.
        if t.type == "square" then
            _, hh = W:DualRow(widget, sy, {
                type = "colorpicker",
                text = "Color",
                hasAlpha = true,
                getValue = function()
                    local c = t.color or { r = 1, g = 0.35, b = 0.35, a = 1 }
                    return c.r or 1, c.g or 0.35, c.b or 0.35, c.a or 1
                end,
                setValue = function(r, g, b, a)
                    t.color = { r = r, g = g, b = b, a = a or 1 }
                    DmApply()
                end,
            }, { type = "label", text = "" })
            sy = sy - hh
        end

        sy = BuildFxEffects(widget, sy, t)
        return sy
    end

    -- Effect tiles: checked filter categories + type-specific visuals.
    _, hh = W:SectionHeader(widget, "EFFECT", sy)
    sy = sy - hh
    -- Frame Glow: shared glow controls over the tile's own keys (always on: no None).
    local GO = CludesUI.GlowOptions
    local glowDesc
    if t.type == "glow" then
        glowDesc = TileGlowDesc(t, DmApply)
    end
    local catRow
    catRow, hh = W:DualRow(
        widget,
        sy,
        {
            type = "dropdown",
            text = "Filters",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        },
        glowDesc and GO.DropdownSpec(glowDesc, "Glow")
            or { type = "label", text = (t.type == "bar" or t.type == "glow") and "" or "Color" }
    )
    sy = sy - hh
    BuildTileFiltersDD(catRow._leftRegion, t, DmTable() or {})
    if glowDesc then
        GO.AttachInline(catRow._rightRegion, glowDesc)
    elseif t.type ~= "bar" then
        -- Health color rides a dedicated Opacity slider (BM parity), so
        -- its swatch has no alpha strip. (The bar's colors live in its
        -- DISPLAY section below, BM parity.)
        local region = catRow._rightRegion
        local swatch = CludesUI.BuildColorSwatch(region, catRow:GetFrameLevel() + 3, function()
            local c = t.color or { r = 1, g = 1, b = 1 }
            return c.r or 1, c.g or 1, c.b or 1, 1
        end, function(r, g, b)
            local c = t.color or {}
            c.r, c.g, c.b = r, g, b
            t.color = c
            DmApply()
        end, false, 20)
        -- Label slots have no _control: anchor to the region itself.
        swatch:SetPoint("RIGHT", region, "RIGHT", -20, 0)
        region._lastInline = swatch
    end

    if t.type == "bar" then
        -- BM bar indicator CORE + DISPLAY 1:1 (minus Own Only and the
        -- 12.1-removed Max Duration / Threshold).
        local isVert = (t.orientation or "HORIZONTAL") == "VERTICAL"
        _, hh = W:SectionHeader(widget, "CORE", sy)
        sy = sy - hh
        local coreRow
        coreRow, hh = W:DualRow(widget, sy, {
            type = "segmented",
            text = "Orientation",
            values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
            order = { "HORIZONTAL", "VERTICAL" },
            getValue = function()
                return t.orientation or "HORIZONTAL"
            end,
            -- Full rebuild: the Width/Height + Full toggle labels flip
            -- with the orientation.
            setValue = function(val)
                TSet("orientation", val)
                CludesUI:RefreshPage(true)
            end,
        }, {
            type = "dropdown",
            text = "Position",
            values = POS_VALUES,
            order = POS_ORDER,
            getValue = function()
                return t.position or "bottom"
            end,
            setValue = function(val)
                TSet("position", val)
            end,
        })
        sy = sy - hh
        do
            local region = coreRow._rightRegion
            CludesUI.BuildInlineCog(region, {
                title = "Position Offset",
                rows = {
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return t.offsetX or 0
                        end,
                        set = function(val)
                            TSet("offsetX", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return t.offsetY or 0
                        end,
                        set = function(val)
                            TSet("offsetY", val)
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Frame Level",
                        values = {
                            behindBorders = "Behind Borders",
                            behindText = "Behind Text",
                            medium = "Medium",
                            high = "High",
                            highest = "Highest",
                        },
                        order = { "behindBorders", "behindText", "medium", "high", "highest" },
                        get = function()
                            return t.frameLevel or "behindBorders"
                        end,
                        set = function(val)
                            TSet("frameLevel", val)
                        end,
                    },
                },
            })
        end
        _, hh = W:DualRow(widget, sy, {
            type = "toggle",
            text = "Reverse Fill",
            getValue = function()
                return t.reverseFill or false
            end,
            setValue = function(val)
                TSet("reverseFill", val and true or false)
            end,
        }, { type = "label", text = "" })
        sy = sy - hh

        _, hh = W:SectionHeader(widget, "DISPLAY", sy)
        sy = sy - hh
        -- Width | Height: labels flip with orientation so each slot names
        -- the on-screen axis; each is disabled while its Full toggle is on.
        _, hh = W:DualRow(widget, sy, {
            type = "slider",
            text = isVert and "Height" or "Width",
            min = 5,
            max = 200,
            step = 1,
            disabled = function()
                return t.barFullWidth
            end,
            disabledTooltip = isVert and "Full Height Bar" or "Full Width Bar",
            requireState = "disabled",
            getValue = function()
                return t.width or 60
            end,
            setValue = function(val)
                TSet("width", val)
            end,
        }, {
            type = "slider",
            text = isVert and "Width" or "Height",
            min = 1,
            max = 100,
            step = 1,
            disabled = function()
                return t.barFullHeight
            end,
            disabledTooltip = isVert and "Full Width Bar" or "Full Height Bar",
            requireState = "disabled",
            getValue = function()
                return t.height or 5
            end,
            setValue = function(val)
                TSet("height", val)
            end,
        })
        sy = sy - hh
        _, hh = W:DualRow(widget, sy, {
            type = "toggle",
            text = isVert and "Full Height Bar" or "Full Width Bar",
            getValue = function()
                return t.barFullWidth or false
            end,
            setValue = function(val)
                TSet("barFullWidth", val and true or false)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = isVert and "Full Width Bar" or "Full Height Bar",
            getValue = function()
                return t.barFullHeight or false
            end,
            setValue = function(val)
                TSet("barFullHeight", val and true or false)
                CludesUI:RefreshPage()
            end,
        })
        sy = sy - hh
        -- Color | Background: opacity sliders + inline swatches.
        local barBgRow
        barBgRow, hh = W:DualRow(widget, sy, {
            type = "slider",
            text = "Color",
            min = 0,
            max = 100,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return t.barColorOpacity or 100
            end,
            setValue = function(val)
                TSet("barColorOpacity", val)
            end,
        }, {
            type = "slider",
            text = "Background",
            min = 0,
            max = 100,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return t.barBgOpacity or 50
            end,
            setValue = function(val)
                TSet("barBgOpacity", val)
            end,
        })
        sy = sy - hh
        do
            local region = barBgRow._leftRegion
            local colorSwatch = CludesUI.BuildColorSwatch(region, barBgRow:GetFrameLevel() + 3, function()
                local c = t.color or { r = 0.25, g = 0.8, b = 0.45 }
                return c.r or 0.25, c.g or 0.8, c.b or 0.45, 1
            end, function(r, g, b)
                t.color = { r = r, g = g, b = b }
                DmApply()
            end, false, 20)
            colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
        end
        do
            local region = barBgRow._rightRegion
            local bgSwatch = CludesUI.BuildColorSwatch(region, barBgRow:GetFrameLevel() + 3, function()
                local c = t.barBgColor or { r = 0, g = 0, b = 0 }
                return c.r or 0, c.g or 0, c.b or 0, 1
            end, function(r, g, b)
                t.barBgColor = { r = r, g = g, b = b }
                DmApply()
            end, false, 20)
            bgSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = bgSwatch
        end
    elseif t.type == "healthcolor" then
        _, hh = W:DualRow(
            widget,
            sy,
            {
                type = "slider",
                text = "Opacity",
                min = 5,
                max = 100,
                step = 1,
                getValue = function()
                    return t.opacity or 45
                end,
                setValue = function(val)
                    TSet("opacity", val)
                end,
            },
            CludesUI.MaxDurationDropdown(function()
                return t.maxDurSec
            end, function(val)
                t.maxDurSec = val
            end, DmApply)
        )
        sy = sy - hh
    elseif t.type == "glow" then
        -- The runtime folds the tile's cap into its effect filter
        -- (EffectFilterForTile), as for the grid tiles.
        _, hh = W:DualRow(
            widget,
            sy,
            CludesUI.MaxDurationDropdown(function()
                return t.maxDurSec
            end, function(val)
                t.maxDurSec = val
            end, DmApply),
            CludesUI.BlankRowCfg()
        )
        sy = sy - hh
    end
    return sy
end

-------------------------------------------------------------------------------
-- DM preview renderer (BM preview parity): the base debuff grid plus every enabled
-- tile's visual, drawn on the replica frame. The selected element renders at full
-- alpha, everything else dims to 0.5 (never hidden); frame-wide effects (glow / health
-- color) show while their tile is selected or when the eyeball forces everything
-- visible. Clicking any element selects its tile for editing.
-------------------------------------------------------------------------------
-- Sample debuff spells for preview icons + tile faces (ancient, stable ids).
local SAMPLE_DEBUFF_SPELLS = { 589, 118, 2818, 702 }
local function SampleDebuffTexture(idx)
    local ident = SAMPLE_DEBUFF_SPELLS[((idx - 1) % #SAMPLE_DEBUFF_SPELLS) + 1]
    local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ident)
    return texture or 136243
end
local CAT_SAMPLE_SPELL = { cc = 118, dispel = 2818 }
local function TileFaceTexture(t)
    local ident
    if t.claim then
        for _, category in ipairs(CAT_ORDER) do
            if t.claim[category] then
                ident = CAT_SAMPLE_SPELL[category] or 589
                break
            end
        end
    end
    ident = ident or 589
    local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ident)
    return texture or 136243
end

local function DmPvEnter(self)
    if not self._dmSel then
        return
    end
    if self._hoverBdr then
        local lPP = CludesUI.PanelPP or CludesUI.PP
        if lPP then
            local ac = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
            lPP.UpdateBorder(self._hoverBdr, 2, ac.r, ac.g, ac.b, 1)
            self._hoverBdr:Show()
        end
    end
end

local function DmPvLeave(self)
    if self._hoverBdr then
        self._hoverBdr:Hide()
    end
end

local function DmPvClick(self)
    if not self._dmSel then
        return
    end
    local ident = self._dmSel
    -- An id outside the edited bucket belongs to an INHERITED group tile
    -- (concrete spec views union them into the preview): select its
    -- read-only sidebar row instead of the (absent) own tile. The base
    -- grid is an All Specs row, inherited in every concrete spec view.
    if ident == "base" then
        if
            dmSpecSel ~= "allspecs"
            and mod.BM_InheritedGroupsFor
            and mod.BM_InheritedGroupsFor(dmSpecSel, true)
        then
            dmInhSel = { group = "allspecs", id = "base" }
            CludesUI:RefreshPage(true)
            return
        end
    else
        local own = (mod.DM_BucketTiles and mod.DM_BucketTiles(dmSpecSel)) or {}
        local inOwn = false
        for idx = 1, #own do
            if own[idx].id == ident then
                inOwn = true
                break
            end
        end
        if not inOwn then
            local inhG = mod.BM_InheritedGroupsFor and mod.BM_InheritedGroupsFor(dmSpecSel, true)
            if inhG then
                for gi = 1, #inhG do
                    local gl = mod.DM_BucketTiles and mod.DM_BucketTiles(inhG[gi])
                    for idx = 1, #(gl or {}) do
                        if gl[idx].id == ident then
                            dmInhSel = { group = inhG[gi], id = ident }
                            CludesUI:RefreshPage(true)
                            return
                        end
                    end
                end
            end
        end
    end
    dmSel = ident
    dmInhSel = nil
    CludesUI:RefreshPage(true)
end

function mod.DMP_RefreshPreview()
    local pv = mod._dmPreviewFrame
    if not (pv and pv._health and pv:IsShown()) then
        return
    end
    -- Party style: the replica's party view (scaled base grid, kit keys).
    local p = pv._bmPvS or DmProfile()
    if not p then
        return
    end
    -- Tile icon sizes live in dmDebuff, outside the proxy's scaled keys: live
    -- party frames scale them by the party indicator scale, so does this.
    local tileScale = pv._bmPvS and (mod._partyIndicatorScale or 1) or 1
    local Pix = CludesUI.PanelPP or CludesUI.PP
    local fontFile = pv._dmFontPath or (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local health = pv._health
    local host = (mod.RF_AnchorHost and mod.RF_AnchorHost(health, p)) or health
    local allVis = mod._dmAllVisible
    -- The EDITED view's tiles: inherited group tiles first (concrete spec
    -- views only, that spec's per-spec disables applied), then the bucket's
    -- own list -- the preview mirrors what that spec renders.
    local tiles = {}
    do
        local inhG = mod.BM_InheritedGroupsFor and mod.BM_InheritedGroupsFor(dmSpecSel, true)
        if inhG then
            for gi = 1, #inhG do
                local gl = mod.DM_BucketTiles and mod.DM_BucketTiles(inhG[gi])
                if gl then
                    for idx = 1, #gl do
                        local t = gl[idx]
                        if not (mod.DM_InhDisabled and mod.DM_InhDisabled(dmSpecSel, t.id)) then
                            tiles[#tiles + 1] = t
                        end
                    end
                end
            end
        end
        local own = (mod.DM_BucketTiles and mod.DM_BucketTiles(dmSpecSel)) or {}
        for idx = 1, #own do
            tiles[#tiles + 1] = own[idx]
        end
    end
    local Glows = CludesUI.Glows

    -- Reset pools
    local icons = pv._dmIconPool
    if not icons then
        icons = {}
        pv._dmIconPool = icons
    end
    local shapes = pv._dmShapePool
    if not shapes then
        shapes = {}
        pv._dmShapePool = shapes
    end
    for idx = 1, #icons do
        local fr = icons[idx]
        if fr._cooldown then
            fr._cooldown:SetCooldown(0, 0)
            fr._cooldown:Hide()
        end
        if fr._hoverBdr then
            fr._hoverBdr:Hide()
        end
        fr._dmSel = nil
        fr:Hide()
    end
    for idx = 1, #shapes do
        local fr = shapes[idx]
        if fr._hoverBdr then
            fr._hoverBdr:Hide()
        end
        fr._dmSel = nil
        fr:Hide()
    end
    if pv._dmHC then
        pv._dmHC:Hide()
    end
    if pv._dmGlow then
        if Glows then
            if Glows.StopAnimatedAnts then
                Glows.StopAnimatedAnts(pv._dmGlow)
            end
            if pv._dmGlow._cuiGlowActive and Glows.StopGlow then
                Glows.StopGlow(pv._dmGlow)
            end
        end
        pv._dmGlow:Hide()
    end

    local iIdx, sIdx = 0, 0
    local function GetIcon()
        iIdx = iIdx + 1
        local fr = icons[iIdx]
        if not fr then
            fr = CreateFrame("Frame", nil, health)
            -- Live parity: aura icons render in the aura band (frame +
            -- LVL_AURA = 13), above the +8 border and the +12 text band
            -- (matches the BM preview pool and live frames).
            fr:SetFrameLevel(pv:GetFrameLevel() + (mod.LVL_AURA or 13))
            local texture = fr:CreateTexture(nil, "ARTWORK")
            texture:SetAllPoints()
            fr._tex = texture
            local cd = CreateFrame("Cooldown", nil, fr, "CooldownFrameTemplate")
            cd:SetAllPoints()
            cd:SetDrawEdge(false)
            cd:SetReverse(true)
            cd:SetSwipeColor(0, 0, 0, 0.6)
            cd:SetHideCountdownNumbers(true)
            cd:Hide()
            fr._cooldown = cd
            if Pix then
                local b = CreateFrame("Frame", nil, fr)
                b:SetAllPoints()
                b:SetFrameLevel(fr:GetFrameLevel() + 1)
                Pix.CreateBorder(b, 0, 0, 0, 1, 1)
                fr._borderFrame = b
                local hb = CreateFrame("Frame", nil, fr)
                hb:SetAllPoints()
                hb:SetFrameLevel(fr:GetFrameLevel() + 8)
                hb:EnableMouse(false)
                Pix.CreateBorder(hb, 0, 0, 0, 0, 2)
                hb:Hide()
                fr._hoverBdr = hb
            end
            local tc = CreateFrame("Frame", nil, fr)
            tc:SetAllPoints()
            tc:SetFrameLevel(fr:GetFrameLevel() + 5)
            fr._count = tc:CreateFontString(nil, "OVERLAY")
            fr:EnableMouse(true)
            fr:SetScript("OnEnter", DmPvEnter)
            fr:SetScript("OnLeave", DmPvLeave)
            fr:SetScript("OnMouseUp", DmPvClick)
            icons[iIdx] = fr
        end
        return fr
    end
    local function GetShape()
        sIdx = sIdx + 1
        local fr = shapes[sIdx]
        if not fr then
            fr = CreateFrame("Frame", nil, health)
            -- Bars render in the aura band like live (BM bars ride button + LVL_AURA).
            fr:SetFrameLevel(pv:GetFrameLevel() + (mod.LVL_AURA or 13))
            local bgTex = fr:CreateTexture(nil, "BACKGROUND")
            bgTex:SetAllPoints()
            fr._bgTex = bgTex
            local texture = fr:CreateTexture(nil, "ARTWORK")
            fr._tex = texture
            if Pix then
                local hb = CreateFrame("Frame", nil, fr)
                hb:SetAllPoints()
                hb:SetFrameLevel(fr:GetFrameLevel() + 8)
                hb:EnableMouse(false)
                Pix.CreateBorder(hb, 0, 0, 0, 0, 2)
                hb:Hide()
                fr._hoverBdr = hb
            end
            fr:EnableMouse(true)
            fr:SetScript("OnEnter", DmPvEnter)
            fr:SetScript("OnLeave", DmPvLeave)
            fr:SetScript("OnMouseUp", DmPvClick)
            shapes[sIdx] = fr
        end
        return fr
    end

    -- One icon run (the base grid or an icon-container tile). Display keys
    -- (zoom/border/swipe/duration/stacks) resolve through cfg.sv: the base
    -- profile for the base grid, the tile's inherit-until-set view for a
    -- tile -- the same view the live renderer styles that tile with.
    local function RenderRun(conf)
        if conf.count <= 0 then
            return
        end
        local sv = conf.sv or p
        local anchor = string.upper(conf.pos or "center")
        local sz = conf.size or 18
        local gap = conf.spacing or 1
        local dir = conf.grow or "LEFT"
        local cursor = 0
        local selfPoint = anchor
        -- Grid wrap preview: >= 2 wraps lines exactly like live (base rows
        -- follow debuffWrapDirection, tiles the anchored-edge rule -- both
        -- arrive here as cfg.wrapV/cfg.wrapH from the caller).
        local per = conf.perRow or 0
        if per < 2 then
            per = 0
        end
        if dir == "CENTER" then
            -- Live parity: CENTER growth centers the run ON the position point (the
            -- base grid pins the container's row-edge midpoint at the corner, tiles pin
            -- the container's center -- both x-centered on it). Anchoring each icon by
            -- the pos corner would skew the run by that corner's own x-alignment (half
            -- an icon for center-x points, a full icon for right-x corners), so CENTER
            -- runs anchor icons by an explicit
            -- self-point instead: x = symmetric icon-center offsets, y =
            -- the caller's vertical seat (cfg.vAlign -- tiles sit flush
            -- with the anchored edge, base rows hang off the point in the
            -- wrap direction).
            selfPoint = conf.vAlign or "CENTER"
            local lineN = conf.count
            if per > 0 and per < lineN then
                lineN = per
            end
            cursor = -((lineN - 1) * (sz + gap)) / 2
        end
        local lineStart = cursor
        for idx = 1, conf.count do
            local fr = GetIcon()
            fr._dmSel = conf.selKey
            fr:SetSize(sz, sz)
            fr:ClearAllPoints()
            local lineOff = 0
            if per > 0 then
                if idx > 1 and (idx - 1) % per == 0 then
                    cursor = lineStart
                end
                lineOff = math.floor((idx - 1) / per) * (sz + gap)
            end
            local gx, gy = 0, 0
            if dir == "RIGHT" or dir == "CENTER" then
                gx = cursor
                cursor = cursor + sz + gap
                gy = (conf.wrapV == "UP") and lineOff or -lineOff
            elseif dir == "LEFT" then
                gx = -cursor
                cursor = cursor + sz + gap
                gy = (conf.wrapV == "UP") and lineOff or -lineOff
            elseif dir == "DOWN" then
                gy = -cursor
                cursor = cursor + sz + gap
                gx = (conf.wrapH == "LEFT") and -lineOff or lineOff
            elseif dir == "UP" then
                gy = cursor
                cursor = cursor + sz + gap
                gx = (conf.wrapH == "LEFT") and -lineOff or lineOff
            end
            fr:SetPoint(selfPoint, host, anchor, (conf.offX or 0) + gx, (conf.offY or 0) + gy)
            if conf.color then
                -- Square grid tiles: flat color blocks instead of icons.
                fr._tex:SetColorTexture(
                    conf.color.r or 1,
                    conf.color.g or 0.35,
                    conf.color.b or 0.35,
                    conf.color.a or 1
                )
            else
                fr._tex:SetTexture(SampleDebuffTexture(idx))
                local z = sv.debuffIconZoom or 0.08
                fr._tex:SetTexCoord(z, 1 - z, z, 1 - z)
            end
            fr:SetAlpha(conf.alpha)
            mod.RFC_PreviewAuraBorder(fr, fr._borderFrame, sv, "debuffBorder")
            local cd = fr._cooldown
            if cd then
                local wantSwipe = sv.debuffShowSwipe ~= false
                local wantDurText = sv.debuffShowDurText and true or false
                if wantSwipe or wantDurText then
                    -- Randomized FROZEN sweep: stable per-slot fraction on an hour-long
                    -- cooldown, so the preview shows varied mid-flight states without
                    -- visibly animating (same pattern as the Buff Manager preview). The
                    -- native countdown text would read the frozen hour, so it stays
                    -- hidden; duration text is a static seeded number on a manual
                    -- FontString instead, exactly like the BM preview.
                    local seed = GetPvCDSeed(idx)
                    local dur = 3600
                    cd:SetCooldown(GetTime() - dur * (1 - seed), dur)
                    cd:SetDrawSwipe(wantSwipe)
                    cd:SetHideCountdownNumbers(true)
                    cd:Show()
                    if not fr._pvDurText then
                        fr._pvDurText = cd:CreateFontString(nil, "OVERLAY")
                    end
                    if wantDurText then
                        local dt = fr._pvDurText
                        local dtc = sv.debuffDurTextColor or { r = 1, g = 1, b = 1 }
                        CludesUI.ApplyIconTextFont(dt, fontFile, sv.debuffDurTextSize or 10, "raidFrames")
                        dt:SetTextColor(dtc.r or 1, dtc.g or 1, dtc.b or 1)
                        dt:ClearAllPoints()
                        dt:SetPoint(
                            "CENTER",
                            fr,
                            "CENTER",
                            sv.debuffDurTextOffsetX or 0,
                            sv.debuffDurTextOffsetY or 0
                        )
                        dt:SetText(tostring(math.floor(3 + seed * 17)))
                        dt:Show()
                    else
                        fr._pvDurText:Hide()
                    end
                else
                    cd:Hide()
                    if fr._pvDurText then
                        fr._pvDurText:Hide()
                    end
                end
            end
            if fr._count then
                if sv.debuffShowStacks ~= false then
                    local sc = sv.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
                    CludesUI.ApplyIconTextFont(
                        fr._count,
                        fontFile,
                        sv.debuffStacksTextSize or 11,
                        "raidFrames"
                    )
                    fr._count:SetTextColor(sc.r or 1, sc.g or 1, sc.b or 1)
                    fr._count:ClearAllPoints()
                    fr._count:SetPoint(
                        "BOTTOMRIGHT",
                        fr,
                        "BOTTOMRIGHT",
                        sv.debuffStacksOffsetX or -1,
                        sv.debuffStacksOffsetY or 2
                    )
                    fr._count:SetText("3")
                else
                    -- Only the stacks-on branch ever fonts this FontString: a
                    -- bare SetText on a fontless one spams "Font not set"
                    -- (field report 2026-08-16, 122x with stacks disabled).
                    -- Fonted = a previous stacks-on render left text to clear.
                    if fr._count:GetFont() then
                        fr._count:SetText("")
                    end
                end
            end
            fr:Show()
        end
    end

    -- Base grid (BM icon-cap parity: selected 4, unselected 2, dimmed 0.5).
    -- An All Specs indicator: drawn in the All Specs view and in concrete
    -- spec views that have not switched it off; group views omit it like
    -- every other All Specs row.
    local baseShown
    if dmSpecSel == "allspecs" then
        baseShown = true
    elseif mod.BM_InheritedGroupsFor and mod.BM_InheritedGroupsFor(dmSpecSel, true) then
        baseShown = not (mod.DM_BaseDisabled and mod.DM_BaseDisabled(dmSpecSel))
    end
    if baseShown then
        local sel = (dmSel == "base" and not dmInhSel) or (dmInhSel and dmInhSel.id == "base") or false
        local basePos = p.debuffPosition or "bottomright"
        local baseCenterEdge
        if (p.debuffGrowDirection or "LEFT") == "CENTER" then
            baseCenterEdge = (string.find(basePos, "top", 1, true) and "TOP")
                or (string.find(basePos, "bottom", 1, true) and "BOTTOM")
                or nil
        end
        RenderRun({
            selKey = "base",
            count = math.min(p.debuffCap or 3, (sel or allVis) and 4 or 2),
            size = p.debuffSize or 18,
            spacing = p.debuffSpacing or 1,
            pos = p.debuffPosition or "bottomright",
            grow = p.debuffGrowDirection or "LEFT",
            -- CENTER-growth vertical seat: live seats the edge from POSITION
            -- (ResolveFlowAnchor), falling back to wrap only when the position
            -- names neither side. Other growth modes keep wrap as the cross-axis.
            vAlign = baseCenterEdge or ((p.debuffWrapDirection == "DOWN") and "TOP" or "BOTTOM"),
            -- Base wrap: rows follow the stored debuffWrapDirection (the
            -- runtime's cross-axis source); vertical growth wraps columns
            -- by its LEFT/RIGHT reading.
            perRow = p.debuffPerRow or 5,
            wrapV = (baseCenterEdge and ((baseCenterEdge == "TOP") and "DOWN" or "UP"))
                or ((p.debuffWrapDirection == "DOWN") and "DOWN" or "UP"),
            wrapH = (p.debuffWrapDirection == "LEFT") and "LEFT" or "RIGHT",
            offX = p.debuffOffsetX or 0,
            offY = p.debuffOffsetY or 0,
            alpha = (sel or allVis) and 1 or 0.5,
        })
    end

    -- Tiles (enabled only, mirroring the BM preview's enabled gate)
    for ti = 1, #tiles do
        local t = tiles[ti]
        if t.enabled then
            -- Selected = the edited bucket's selection OR the inherited
            -- selection (ids are globally unique across buckets).
            local sel = (dmSel == t.id and not dmInhSel) or (dmInhSel and dmInhSel.id == t.id) or false
            local alpha = (sel or allVis) and 1 or 0.5
            if t.type == "icons" or t.type == "square" then
                RenderRun({
                    selKey = t.id,
                    -- Tile Display values: the tile's own keys over the base (nil = inherit).
                    sv = (mod.DM_TileStyleView and mod.DM_TileStyleView(p, t)) or p,
                    count = math.min(t.cap or 3, (sel or allVis) and 4 or 2),
                    size = (t.size or 18) * tileScale,
                    spacing = t.spacing or 1,
                    pos = t.position or "top",
                    grow = t.growDirection or "CENTER",
                    -- CENTER growth: vertical seat flush with the anchored
                    -- edge (AnchorTileContainer parity -- only the growth
                    -- axis centers on the position point).
                    vAlign = (string.find(t.position or "top", "top", 1, true) and "TOP")
                        or (string.find(t.position or "top", "bottom", 1, true) and "BOTTOM")
                        or "CENTER",
                    -- Tile wrap: away from the anchored edge (position rule,
                    -- matching AnchorTileContainer).
                    perRow = t.iconsPerRow or 0,
                    wrapV = string.find(t.position or "top", "bottom", 1, true) and "UP" or "DOWN",
                    wrapH = string.find(t.position or "top", "right", 1, true) and "LEFT" or "RIGHT",
                    offX = t.offsetX or 0,
                    offY = t.offsetY or 0,
                    alpha = alpha,
                    color = (t.type == "square") and (t.color or { r = 1, g = 0.35, b = 0.35, a = 1 }) or nil,
                })
            elseif t.type == "bar" then
                local fr = GetShape()
                fr._dmSel = t.id
                -- BM_PlaceBar parity: fill-axis sliders + Full pins that
                -- swap screen edges when the bar is vertical.
                local wid = t.width or 60
                local hh2 = t.height or 5
                local isVert = (t.orientation or "HORIZONTAL") == "VERTICAL"
                local anchor = string.upper(t.position or "bottom")
                local fullW, fullH
                if isVert then
                    fullW, fullH = t.barFullHeight, t.barFullWidth
                else
                    fullW, fullH = t.barFullWidth, t.barFullHeight
                end
                fr:ClearAllPoints()
                if fullW and fullH then
                    fr:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                    fr:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
                elseif fullW then
                    local vEdge = (anchor:find("BOTTOM", 1, true) and "BOTTOM")
                        or (anchor:find("TOP", 1, true) and "TOP")
                        or ""
                    local oy = t.offsetY or 0
                    fr:SetPoint(vEdge .. "LEFT", host, vEdge .. "LEFT", 0, oy)
                    fr:SetPoint(vEdge .. "RIGHT", host, vEdge .. "RIGHT", 0, oy)
                    fr:SetHeight(isVert and wid or hh2)
                elseif fullH then
                    local hEdge = (anchor:find("RIGHT", 1, true) and "RIGHT")
                        or (anchor:find("LEFT", 1, true) and "LEFT")
                        or ""
                    local ox = t.offsetX or 0
                    fr:SetPoint("TOP" .. hEdge, host, "TOP" .. hEdge, ox, 0)
                    fr:SetPoint("BOTTOM" .. hEdge, host, "BOTTOM" .. hEdge, ox, 0)
                    fr:SetWidth(isVert and hh2 or wid)
                else
                    if isVert then
                        fr:SetSize(hh2, wid)
                    else
                        fr:SetSize(wid, hh2)
                    end
                    fr:SetPoint(anchor, host, anchor, t.offsetX or 0, t.offsetY or 0)
                end
                local c = t.color or { r = 0.25, g = 0.8, b = 0.45 }
                local bgc = t.barBgColor or { r = 0, g = 0, b = 0 }
                fr._bgTex:SetColorTexture(bgc.r or 0, bgc.g or 0, bgc.b or 0, (t.barBgOpacity or 50) / 100)
                fr._bgTex:Show()
                -- 60% sample fill along the fill axis, reverse-aware.
                local sw = (fullW and (host:GetWidth() or wid)) or (isVert and hh2 or wid)
                local sh = (fullH and (host:GetHeight() or hh2)) or (isVert and wid or hh2)
                fr._tex:ClearAllPoints()
                if isVert then
                    local edge = t.reverseFill and "TOP" or "BOTTOM"
                    fr._tex:SetPoint(edge .. "LEFT", fr, edge .. "LEFT", 0, 0)
                    fr._tex:SetPoint(edge .. "RIGHT", fr, edge .. "RIGHT", 0, 0)
                    fr._tex:SetHeight(math.max(1, floor(sh * 0.6)))
                else
                    local edge = t.reverseFill and "RIGHT" or "LEFT"
                    fr._tex:SetPoint("TOP" .. edge, fr, "TOP" .. edge, 0, 0)
                    fr._tex:SetPoint("BOTTOM" .. edge, fr, "BOTTOM" .. edge, 0, 0)
                    fr._tex:SetWidth(math.max(1, floor(sw * 0.6)))
                end
                fr._tex:SetColorTexture(c.r or 1, c.g or 1, c.b or 1, (t.barColorOpacity or 100) / 100)
                fr:SetAlpha(alpha)
                fr:Show()
            elseif t.type == "healthcolor" then
                -- Frame-wide effect: shown while selected / eyeball (BM parity)
                if sel or allVis then
                    local hc = pv._dmHC
                    if not hc then
                        -- BM parity: ARTWORK sublevel 2 over the FILL texture
                        -- only, so it tints just the filled portion.
                        hc = health:CreateTexture(nil, "ARTWORK", nil, 2)
                        local fill = health.GetStatusBarTexture and health:GetStatusBarTexture()
                        hc:SetAllPoints(fill or health)
                        pv._dmHC = hc
                    end
                    local c = t.color or { r = 1, g = 0.25, b = 0.25 }
                    mod.RF_TintOverBarFill(
                        hc,
                        health,
                        c.r or 1,
                        c.g or 0.25,
                        c.b or 0.25,
                        (t.opacity or 45) / 100
                    )
                    hc:Show()
                end
            elseif t.type == "glow" then
                if (sel or allVis) and Glows and not pv._dmGlowUsed then
                    local gov = pv._dmGlow
                    if not gov then
                        gov = CreateFrame("Frame", nil, pv)
                        gov:SetAllPoints(pv)
                        -- Live parity: the frame-glow host sits at +15,
                        -- above the aura and text bands.
                        gov:SetFrameLevel(pv:GetFrameLevel() + 15)
                        gov:EnableMouse(false)
                        pv._dmGlow = gov
                    end
                    -- Live parity: the tile's own descriptor, the same call as the slot renderer.
                    local specInfo = CludesUI.GlowOptions.Spec(TileGlowDesc(t))
                    gov:Show()
                    Glows.StartSpecGlow(
                        gov,
                        specInfo,
                        pv:GetWidth() or 72,
                        pv:GetHeight() or 72,
                        "engine",
                        Glows.PANEL_EXTRA
                    )
                    -- One overlay: the first qualifying glow tile wins.
                    pv._dmGlowUsed = true
                end
            end
        end
    end
    pv._dmGlowUsed = nil
end

function mod.DMP_BuildPage(page, hostFrame, yOffset)
    local scrollFrame = CludesUI._scrollFrame
    if not scrollFrame then
        return 0
    end
    local fontFile = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local Pix = CludesUI.PanelPP

    local parentW = scrollFrame:GetWidth()
    local fullH = scrollFrame:GetHeight()
    local sidebarW = floor(parentW * 0.28)
    local leftW = parentW - sidebarW

    -- The refreshers this render registers replace the previous render's (it
    -- may run outside a page pass: the deferred renders of a cache restore).
    CludesUI._BeginRootRender("rf.dm")
    -- One root for the session (the options page pool): every render dresses
    -- it again; its reset is the previous render's teardown.
    local outerRoot = PoolKept(mod, "dmRoot", "Frame", scrollFrame)
    outerRoot:SetAllPoints(scrollFrame)
    outerRoot:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
    if mod._dmAddPopup then
        mod._dmAddPopup:Hide()
    end
    if CludesUI._pickMenu then
        CludesUI._pickMenu:Hide()
    end
    mod._dmRoot = outerRoot

    -- Override-session gate: heals a stale Debuff Manager layer FIRST (so
    -- the page content below renders the edited group's fork) and reports
    -- the full-page overlay to build at the end. nil = normal page.
    local dmOverlayState = CludesUI.SpecOverrides_DmPagePrelude() or nil

    local dm = DmTable()

    -- Editing-spec bucket sanity: stale/unknown keys reset to All Specs.
    if
        dmSpecSel ~= "allspecs"
        and not (mod.BM_GROUP_BUCKET_INFO and mod.BM_GROUP_BUCKET_INFO[dmSpecSel])
        and not (type(dmSpecSel) == "string" and dmSpecSel:match("^spec%d"))
    then
        dmSpecSel = "allspecs"
    end
    -- WoW Forever lists All Specs and one row per class, keyed to the bucket
    -- that class renders now: a group view resets to All Specs and a spec
    -- view follows its class's current bucket (it moves with the profile and
    -- when that bucket loses its last tile, per-spec disable or Base Icons off).
    if CludesUI.IS_FOREVER and dmSpecSel ~= "allspecs" then
        local m = type(dmSpecSel) == "string" and dmSpecSel:match("^spec(%d+)$")
        local cls = m and CludesUI.SpecClassOf(tonumber(m))
        dmSpecSel = (cls and mod.DM_ForeverKey and mod.DM_ForeverKey(cls)) or "allspecs"
    end
    local tiles = (mod.DM_BucketTiles and mod.DM_BucketTiles(dmSpecSel)) or {}

    -- Group buckets this view inherits from (concrete "spec<ID>" views
    -- only): their tiles lead the sidebar as read-only rows.
    local inhGroups = mod.BM_InheritedGroupsFor and mod.BM_InheritedGroupsFor(dmSpecSel, true) or nil

    -- The Base Icons grid is an All Specs indicator: OWN in the All Specs
    -- view, INHERITED (read-only, per-spec disable pill) in concrete spec
    -- views, absent from the other group views like any All Specs tile.
    local baseOwn = (dmSpecSel == "allspecs")
    local baseInherited = (inhGroups ~= nil)
    local allSpecsName = (mod.BM_GROUP_BUCKET_INFO and mod.BM_GROUP_BUCKET_INFO.allspecs)
            and L(mod.BM_GROUP_BUCKET_INFO.allspecs.name)
        or L("All Specs")

    -- Inherited selection: resolve against the owning group's bucket; drop
    -- it when the view no longer inherits that group or the tile is gone.
    -- id "base" = the inherited Base Icons grid (concrete spec views only).
    local inhSelTile = nil
    local inhSelBase = false
    if dmInhSel and inhGroups then
        if dmInhSel.id == "base" then
            inhSelBase = (dmInhSel.group == "allspecs")
        else
            for gi = 1, #inhGroups do
                if inhGroups[gi] == dmInhSel.group then
                    local gl = mod.DM_BucketTiles and mod.DM_BucketTiles(dmInhSel.group)
                    for idx = 1, #(gl or {}) do
                        if gl[idx].id == dmInhSel.id then
                            inhSelTile = gl[idx]
                            break
                        end
                    end
                    break
                end
            end
        end
    end
    if not (inhSelTile or inhSelBase) then
        dmInhSel = nil
    end

    -- Validate selection.
    if dmSel ~= "base" then
        local found = false
        for idx = 1, #tiles do
            if tiles[idx].id == dmSel then
                found = true
                break
            end
        end
        if not found then
            dmSel = "base"
        end
    end
    -- "base" in a concrete spec view IS the inherited base grid.
    if dmSel == "base" and not dmInhSel and baseInherited then
        dmInhSel = { group = "allspecs", id = "base" }
        inhSelBase = true
    end

    local p = DmProfile()
    if not p then
        CludesUI._EndRootRender("rf.dm")
        return 0
    end

    -- No header bar (matches the redesigned Buff Manager page): content
    -- starts at the top of the viewport.
    local root = CreateFrame("Frame", nil, outerRoot)
    root:SetPoint("TOPLEFT", outerRoot, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", outerRoot, "BOTTOMRIGHT", 0, 0)
    root:SetFrameLevel(outerRoot:GetFrameLevel() + 1)
    local visibleH = fullH

    -------------------------------------------------------------------
    --  RIGHT SIDEBAR (full visible height, own scroll, dark bg)
    -------------------------------------------------------------------
    local sidebarOuter = CreateFrame("Frame", nil, root)
    sidebarOuter:SetSize(sidebarW, visibleH)
    sidebarOuter:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -1)
    sidebarOuter:SetFrameLevel(root:GetFrameLevel() + 1)
    local sbBg = sidebarOuter:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(0, 0, 0, 0.25)
    CludesUI.CardSidebar(sidebarOuter, sbBg)

    local sidebarScroll = CreateFrame("ScrollFrame", nil, sidebarOuter)
    sidebarScroll:SetAllPoints()
    sidebarScroll:SetFrameLevel(sidebarOuter:GetFrameLevel() + 1)
    local sidebarChild = CreateFrame("Frame", nil, sidebarScroll)
    sidebarChild:SetWidth(sidebarW)
    sidebarScroll:SetScrollChild(sidebarChild)
    sidebarScroll:EnableMouseWheel(true)
    sidebarScroll:SetScript("OnMouseWheel", function(self, delta)
        if CludesUI._ShiftWheelScale(delta) then
            return
        end
        local scroll = self:GetVerticalScroll()
        local maxS = max(0, sidebarChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(max(0, math.min(maxS, scroll - delta * 30)))
    end)

    -- Each tile stacks under the last, the sidebar's width, in its font.
    local tileY = 0
    local function AddTile(opts)
        opts.width = sidebarW
        opts.fontPath = fontFile
        tileY = tileY - CludesUI.BuildManagerTile(sidebarChild, tileY, opts)
    end
    -- A tile's gray position suffix: the icon, square and bar containers sit
    -- at a position; the base grid at the debuff position.
    local function TilePosText(t)
        if t.type == "icons" or t.type == "square" or t.type == "bar" then
            return "(" .. L(POS_VALUES[t.position or "top"] or "") .. ")"
        end
    end
    local basePosText = "(" .. L(POS_VALUES[p.debuffPosition or "bottomright"] or "") .. ")"

    -- Pinned Base Icons tile (All Specs view): undeletable, no toggle (an
    -- empty grid is expressed through the filters).
    if baseOwn then
        AddTile({
            icon = SampleDebuffTexture(1),
            title = L("Base Icons"),
            posText = basePosText,
            subtitle = L("The standard debuff grid"),
            selected = (dmSel == "base" and not dmInhSel),
            enabled = true,
            onSelect = function()
                dmSel = "base"
                dmInhSel = nil
                CludesUI:RefreshPage(true)
            end,
        })
    elseif baseInherited then
        -- Concrete spec view: the All Specs base grid as an INHERITED row
        -- (read-only here; the pill is this spec's own on/off).
        local disHere = mod.DM_BaseDisabled and mod.DM_BaseDisabled(dmSpecSel)
        AddTile({
            icon = SampleDebuffTexture(1),
            title = L("Base Icons"),
            posText = basePosText,
            subtitle = allSpecsName,
            inheritedTooltip = CludesUI.Lf("Inherited from %1$s. Editable only there.", allSpecsName),
            selected = inhSelBase,
            enabled = (not disHere) and true or false,
            showToggle = true,
            onSelect = function()
                dmInhSel = { group = "allspecs", id = "base" }
                CludesUI:RefreshPage(true)
            end,
            onToggle = function()
                mod.DM_SetBaseDisabled(dmSpecSel, not mod.DM_BaseDisabled(dmSpecSel))
                ApplyAndRedraw()
            end,
        })
    end

    -- INHERITED group tiles lead concrete spec views: read-only here (edit
    -- them in their group); the pill toggles ONLY this spec's enable.
    if inhGroups then
        for gi = 1, #inhGroups do
            local gkey = inhGroups[gi]
            local ginfo = mod.BM_GROUP_BUCKET_INFO and mod.BM_GROUP_BUCKET_INFO[gkey]
            local gname = ginfo and L(ginfo.name) or gkey
            local gl = (mod.DM_BucketTiles and mod.DM_BucketTiles(gkey)) or {}
            for idx = 1, #gl do
                local t = gl[idx]
                local disHere = mod.DM_InhDisabled and mod.DM_InhDisabled(dmSpecSel, t.id)
                AddTile({
                    icon = TileFaceTexture(t),
                    title = TileName(t),
                    posText = TilePosText(t),
                    subtitle = gname,
                    inheritedTooltip = CludesUI.Lf("Inherited from %1$s. Editable only there.", gname),
                    selected = (dmInhSel and dmInhSel.group == gkey and dmInhSel.id == t.id) and true
                        or false,
                    -- Pill = the PER-SPEC enable only; a group-level disable
                    -- dims the tile instead (the pill must never look dead).
                    dimmed = not t.enabled or nil,
                    enabled = (not disHere) and true or false,
                    showToggle = true,
                    onSelect = function()
                        dmInhSel = { group = gkey, id = t.id }
                        CludesUI:RefreshPage(true)
                    end,
                    onToggle = function()
                        mod.DM_SetInhDisabled(dmSpecSel, t.id, not mod.DM_InhDisabled(dmSpecSel, t.id))
                        ApplyAndRedraw()
                    end,
                })
            end
        end
    end

    -- Tile list (BM tile parity: icon face, type title, gray position
    -- suffix, routed-filters subtitle, pill toggle, atlas delete)
    for idx = 1, #tiles do
        local t = tiles[idx]
        AddTile({
            icon = TileFaceTexture(t),
            -- User-typed name over the type-name default. Display-only
            -- (additive key; DM_CfgFP serializes explicit fields, so a
            -- rename never re-declares containers).
            title = TileName(t),
            posText = TilePosText(t),
            -- Live: filter and Match Mode clicks refresh without a rebuild.
            subtitleFn = function()
                return TileSubtitle(t)
            end,
            selected = (dmSel == t.id and not dmInhSel),
            enabled = t.enabled and true or false,
            showToggle = true,
            onSelect = function()
                dmSel = t.id
                dmInhSel = nil
                CludesUI:RefreshPage(true)
            end,
            -- Right-click: copy this tile into another editing-spec bucket
            -- (full clone, fresh id; the source stays).
            onContext = function(tileFrame)
                if not CludesUI.ShowPickMenu then
                    return
                end
                CludesUI.ShowPickMenu(tileFrame, {
                    title = L("Add To"),
                    fontPath = fontFile,
                    items = CludesUI.SpecBucketMenuItems(dmSpecSel, nil, mod.DM_ForeverKey),
                    onPick = function(key)
                        if mod.DM_CopyTile and mod.DM_CopyTile(t, key) then
                            ApplyAndRedraw()
                        end
                    end,
                })
            end,
            onToggle = function(val)
                t.enabled = val and true or false
                ApplyAndRedraw()
            end,
            editTooltip = L("Rename Indicator"),
            onEdit = function()
                local current = TileName(t)
                CludesUI:ShowInputPopup({
                    title = L("Rename Indicator"),
                    message = L("Enter a new name for this indicator:"),
                    placeholder = current,
                    confirmText = L("Rename"),
                    cancelText = L("Cancel"),
                    onConfirm = function(textValue)
                        textValue = textValue and textValue:gsub("^%s+", ""):gsub("%s+$", "") or ""
                        -- Empty reverts to the type-name default.
                        t.name = (textValue ~= "") and textValue or nil
                        CludesUI:RefreshPage(true)
                    end,
                })
            end,
            onDelete = function()
                CludesUI:ShowConfirmPopup({
                    title = L("Delete Indicator"),
                    message = L("Delete this indicator? Its settings are removed from the profile."),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        if mod.DM_DeleteTile then
                            mod.DM_DeleteTile(t.id)
                        end
                        if dmSel == t.id then
                            dmSel = "base"
                        end
                        ApplyAndRedraw()
                    end,
                })
            end,
        })
    end

    -------------------------------------------------------------------
    --  "Add New" button at bottom of sidebar tiles (BM parity: green
    --  accent button + dark type-picker popup on the BM popup chrome)
    -------------------------------------------------------------------
    local ADD_BTN_H = 30
    local ADD_BTN_PAD = 10
    do
        local btnW = floor(sidebarW * 0.6)
        local addBtn = CreateFrame("Button", nil, sidebarChild)
        addBtn:SetSize(btnW, ADD_BTN_H)
        addBtn:SetPoint("TOP", sidebarChild, "TOPLEFT", floor(sidebarW / 2), tileY - ADD_BTN_PAD)
        addBtn:SetFrameLevel(sidebarChild:GetFrameLevel() + 1)

        local accentColor = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints()
        addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
        CludesUI.RoundBody(addBtn, addBg)

        local addLabel = addBtn:CreateFontString(nil, "OVERLAY")
        -- Drop shadow via the shadow FontObject, primed BEFORE SetFont
        -- (SetShadowOffset alone does not render).
        CludesUI.PrimeFontShadow(addLabel, true)
        addLabel:SetFont(fontFile, 12, "")
        addLabel:SetPoint("CENTER")
        addLabel:SetText(L("Add New"))
        addLabel:SetTextColor(1, 1, 1)

        addBtn:SetScript("OnEnter", nil) -- CludesUI.OutlineButton below sets the hover
        CludesUI.OutlineButton(addBtn, addBg, true)

        addBtn:SetScript("OnClick", function(self)
            -- Toggle popup (BM Add New popup parity: label + dropdown +
            -- accent Create button on the same chrome and metrics)
            local dialog = mod._dmAddPopup
            if dialog and dialog:IsShown() then
                dialog:Hide()
                return
            end

            if not dialog then
                local POPUP_W = 220
                local POPUP_PAD = 10
                local ROW_H2 = 30
                local LABEL_H = 14
                local LBL_GAP = 4 -- label to dropdown
                local DD_GAP = 11 -- dropdown to next label/button

                dialog = CreateFrame("Frame", nil, UIParent)
                dialog:Hide() -- start hidden so Show() triggers OnShow
                dialog:SetFrameStrata("DIALOG")
                dialog:SetFrameLevel(200)
                dialog:SetSize(
                    POPUP_W,
                    POPUP_PAD + 2 * (LABEL_H + LBL_GAP + ROW_H2 + DD_GAP) + ROW_H2 + POPUP_PAD
                )
                dialog:EnableMouse(true)
                dialog:SetClampedToScreen(true)

                local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
                backdrop:SetAllPoints()
                backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.95)
                CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.2, backdrop)

                -- Pending filter picks for the new tile (wiped on hide)
                dialog._dmFilters = {}

                -- Auto-close when clicking outside (but not on a child
                -- dropdown's open menu)
                dialog:SetScript("OnShow", function(p2)
                    p2:SetScript("OnUpdate", function(m)
                        if not self:IsMouseOver() and not m:IsMouseOver() then
                            local tDD = m._indDD
                            if
                                tDD
                                and tDD._ddMenu
                                and tDD._ddMenu:IsShown()
                                and tDD._ddMenu:IsMouseOver()
                            then
                                return
                            end
                            local fDD = m._fltDD
                            if
                                fDD
                                and fDD._ddMenu
                                and fDD._ddMenu:IsShown()
                                and fDD._ddMenu:IsMouseOver()
                            then
                                return
                            end
                            if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                                m:Hide()
                            end
                        end
                    end)
                end)
                dialog:SetScript("OnHide", function(p2)
                    p2:SetScript("OnUpdate", nil)
                    if p2._dmFilters then
                        wipe(p2._dmFilters)
                    end
                    if p2._fltDDRefresh then
                        p2._fltDDRefresh()
                    end
                end)

                local py = -POPUP_PAD
                local ddW = POPUP_W - POPUP_PAD * 2

                -- Filters label + checkbox dropdown (identical items to the
                -- tile Filters dropdown; picks become the new tile's routed
                -- filters at Create)
                local fltLbl = dialog:CreateFontString(nil, "OVERLAY")
                fltLbl:SetFont(fontFile, 11, "")
                fltLbl:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, py)
                fltLbl:SetText(L("Filters"))
                fltLbl:SetTextColor(1, 1, 1, 0.6)
                py = py - LABEL_H - LBL_GAP

                -- Same two-lane item list as the tile Filters dropdown; picks
                -- pend in popup._dmFilters (show keys plain, hide keys with a
                -- "neg_" prefix; the pinned All/Has Duration keys ride the
                -- plain lane) and become the new tile's claim/neg/all/
                -- hasDuration at Create.
                local pend = dialog._dmFilters
                local fltDD, fltDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                    dialog,
                    ddW,
                    dialog:GetFrameLevel() + 2,
                    TILE_LANE_ITEMS,
                    function(k, neg)
                        if neg then
                            return pend["neg_" .. k] and true or false
                        end
                        return pend[k] and true or false
                    end,
                    function(k, val, neg)
                        if k == TILE_CA_ALL or k == TILE_CA_DUR then
                            -- Independent bits (All Debuffs / Has Duration modifier).
                            pend[k] = val and true or nil
                            return
                        end
                        if k == "dispel_you" or k == "dispel_typed" then
                            -- ONE dispel category (flavors mutually exclusive
                            -- across rows AND lanes, base-dropdown parity).
                            pend.dispel_you, pend.dispel_typed = nil, nil
                            pend.neg_dispel_you, pend.neg_dispel_typed = nil, nil
                            if val then
                                pend[(neg and "neg_" or "") .. k] = true
                            end
                            return
                        end
                        -- Two-lane pend write: checking one lane clears the other.
                        if neg then
                            pend["neg_" .. k] = val and true or nil
                            if val then
                                pend[k] = nil
                            end
                        else
                            pend[k] = val and true or nil
                            if val then
                                pend["neg_" .. k] = nil
                            end
                        end
                    end,
                    nil,
                    12
                )
                fltDD:SetSize(ddW, ROW_H2)
                fltDD:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, py)
                dialog._fltDD = fltDD
                dialog._fltDDRefresh = fltDDRefresh
                py = py - ROW_H2 - DD_GAP

                local indLbl = dialog:CreateFontString(nil, "OVERLAY")
                indLbl:SetFont(fontFile, 11, "")
                indLbl:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, py)
                indLbl:SetText(L("Indicator"))
                indLbl:SetTextColor(1, 1, 1, 0.6)
                py = py - LABEL_H - LBL_GAP

                local indDD = CludesUI.BuildDropdownControl(
                    dialog,
                    ddW,
                    dialog:GetFrameLevel() + 2,
                    TYPE_NAMES,
                    TYPE_ORDER,
                    function()
                        return dmSelType
                    end,
                    function(val)
                        dmSelType = val
                    end
                )
                indDD:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, py)
                dialog._indDD = indDD
                py = py - ROW_H2 - DD_GAP

                local accentColor = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
                local cBtn = CreateFrame("Button", nil, dialog)
                cBtn:SetSize(ddW, ROW_H2)
                cBtn:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, py)
                cBtn:SetFrameLevel(dialog:GetFrameLevel() + 1)
                local cBg = cBtn:CreateTexture(nil, "BACKGROUND")
                cBg:SetAllPoints()
                cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
                CludesUI.RoundBody(cBtn, cBg)
                local cTx = cBtn:CreateFontString(nil, "OVERLAY")
                cTx:SetPoint("CENTER")
                cTx:SetFont(fontFile, 12, "")
                cTx:SetText(L("Create"))
                cTx:SetTextColor(1, 1, 1)
                cBtn:SetScript("OnEnter", nil) -- CludesUI.OutlineButton below sets the hover
                CludesUI.OutlineButton(cBtn, cBg, true)
                cBtn:SetScript("OnClick", function()
                    -- Snapshot picks BEFORE Hide (hide wipes the pending set)
                    local picked, negPicked = {}, nil
                    local caAll = dialog._dmFilters[TILE_CA_ALL] and true or false
                    local caDur = dialog._dmFilters[TILE_CA_DUR] and true or false
                    local mode
                    for k in pairs(dialog._dmFilters) do
                        if k ~= TILE_CA_ALL and k ~= TILE_CA_DUR then
                            local category, isNeg = k, false
                            if category:sub(1, 4) == "neg_" then
                                category = category:sub(5)
                                isNeg = true
                            end
                            if category == "dispel_you" then
                                category = "dispel"
                                mode = "you"
                            elseif category == "dispel_typed" then
                                category = "dispel"
                                mode = "typed"
                            end
                            if isNeg then
                                negPicked = negPicked or {}
                                negPicked[category] = true
                            else
                                picked[category] = true
                            end
                        end
                    end
                    local t = mod.DM_AddTile and mod.DM_AddTile(dmSelType, dmSpecSel)
                    dialog:Hide()
                    if t then
                        if mode then
                            local dm2 = DmTable()
                            if dm2 then
                                dm2.dispelMode = mode
                            end
                        end
                        -- Every tile type takes the full picked set now
                        -- (effect tiles run one slot per category).
                        if not t.claim then
                            t.claim = {}
                        end
                        for category in pairs(picked) do
                            t.claim[category] = true
                        end
                        if negPicked then
                            t.neg = negPicked
                        end
                        if caAll then
                            t.all = true
                        end
                        if caDur then
                            t.hasDuration = true
                        end
                        dmSel = t.id
                        dmInhSel = nil
                        ApplyAndRedraw()
                    end
                end)

                mod._dmAddPopup = dialog
            end

            -- Position below the Add New button, centered on sidebar
            dialog:ClearAllPoints()
            local sc = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            dialog:SetScale(sc)
            dialog:SetPoint("TOP", self, "BOTTOM", 0, -12)
            dialog:Show()
        end)
        tileY = tileY - ADD_BTN_PAD - ADD_BTN_H - ADD_BTN_PAD
    end

    -- Override list (BM parity; builder lives in the Buff Manager file).
    tileY = mod.BM_BuildOverrideList(sidebarChild, tileY, sidebarW, fontFile, "dm")

    sidebarChild:SetHeight(max(10, math.abs(tileY)))

    -------------------------------------------------------------------
    --  LEFT COLUMN (72%): fixed top (preview band + Editing Spec section
    --  + accent title) + scrollable settings below -- a clone of the BM
    --  page's left column, band split 65/35 like the BM's.
    -------------------------------------------------------------------
    local PAD = 20
    local leftFixed = CreateFrame("Frame", nil, root)
    leftFixed:SetSize(leftW, 10) -- height set after content
    leftFixed:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    local ly = 0

    local pvSplitW = floor(leftW * 0.65)
    local specSplitW = leftW - pvSplitW

    -- Preview: the shared health-bar replica in replica-only mode; the DM
    -- renderer draws the base grid + tiles on it. Centered in the LEFT 65%
    -- (the Editing Spec section owns the right 35%).
    local ovRaid, ovParty = mod.BM_PreviewOverrideTips("dm")
    local pvFrame, sectionH, PV_SCALE =
        mod.BM_BuildSimplePreview(leftFixed, p, fontFile, Pix, pvSplitW / 2, -PAD, {
            party = mod.BM_PreviewIsParty(),
            styleToggle = true,
            kitAuras = "debuffs",
            overrideTips = { raid = ovRaid, party = ovParty },
        })
    mod._dmPreviewFrame = pvFrame
    pvFrame._dmFontPath = fontFile

    -- Eyeball toggle: show all tiles at full opacity (BM parity)
    do
        local EYE_VIS = CludesUI.EYE_VISIBLE_ICON
        local EYE_INVIS = CludesUI.EYE_INVISIBLE_ICON
        mod._dmAllVisible = mod._dmAllVisible or false

        local eyeBtn = CreateFrame("Button", nil, leftFixed)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("LEFT", pvFrame, "RIGHT", 18 / PV_SCALE, 0)
        eyeBtn:SetFrameLevel(leftFixed:GetFrameLevel() + 5)

        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        eyeTex:SetTexture(mod._dmAllVisible and EYE_INVIS or EYE_VIS)
        CludesUI.SetGlyphAlpha(eyeBtn, 0.4)

        eyeBtn:SetScript("OnClick", function()
            mod._dmAllVisible = not mod._dmAllVisible
            eyeTex:SetTexture(mod._dmAllVisible and EYE_INVIS or EYE_VIS)
            if mod.DMP_RefreshPreview then
                mod.DMP_RefreshPreview()
            end
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            CludesUI.SetGlyphAlpha(self, 0.7)
            CludesUI.ShowWidgetTooltip(self, "Toggle All Indicators")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            CludesUI.SetGlyphAlpha(self, 0.4)
            CludesUI.HideWidgetTooltip()
        end)
    end

    -------------------------------------------------------------------
    --  EDITING SPEC (right 35% of the band, BM parity): the group
    --  buckets lead, then every spec in the game as its own "spec<ID>"
    --  bucket -- healer specs included (the DM has no healer-key legacy).
    -------------------------------------------------------------------
    do
        local splitDiv = leftFixed:CreateTexture(nil, "ARTWORK")
        splitDiv:SetWidth(1)
        splitDiv:SetPoint("TOP", leftFixed, "TOPLEFT", pvSplitW, ly - 10)
        splitDiv:SetPoint("BOTTOM", leftFixed, "TOPLEFT", pvSplitW, ly - sectionH + 10)
        splitDiv:SetColorTexture(1, 1, 1, 0.08)

        local specCenterX = pvSplitW + specSplitW / 2
        -- Roster shared with the right-click "Add To" menu (the menu
        -- rebuilds it lazily per open).
        local specDDValues, specDDOrder, specDDIcons = CludesUI.BuildSpecBucketRoster(nil, mod.DM_ForeverKey)
        specDDValues._menuOpts = {
            maxHeight = 300,
            icon = function(key)
                return specDDIcons[key]
            end,
        }

        local groupH = 14 + 7 + 30
        local groupTopY = ly - (sectionH - groupH) / 2
        local specLabel = leftFixed:CreateFontString(nil, "OVERLAY")
        specLabel:SetFont(fontFile, 12, "")
        specLabel:SetPoint("TOP", leftFixed, "TOPLEFT", specCenterX, groupTopY)
        specLabel:SetJustifyH("CENTER")
        specLabel:SetText(L("Editing Spec"))
        specLabel:SetTextColor(1, 1, 1, 0.75)

        local specDDW = specSplitW - PAD - 50
        local specDD = CludesUI.BuildDropdownControl(
            leftFixed,
            specDDW,
            leftFixed:GetFrameLevel() + 2,
            specDDValues,
            specDDOrder,
            function()
                return dmSpecSel or "allspecs"
            end,
            function(val)
                dmSpecSel = val
                dmSel = "base"
                dmInhSel = nil
                CludesUI:RefreshPage(true)
            end
        )
        specDD:SetPoint("TOP", specLabel, "BOTTOM", 0, -7)
    end

    -- No text under the DM preview (user call 2026-07-24): the "Edit
    -- Excluded Debuffs" link is retired (exclude list is internal now) and
    -- the BM-style click-hint was dropped the next day. The band-height
    -- accounting stays so the divider seats where it always did.
    ly = ly - sectionH - 10

    -------------------------------------------------------------------
    --  DIVIDER (below preview, above settings title) -- BM parity
    -------------------------------------------------------------------
    local div1 = leftFixed:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT", leftFixed, "TOPLEFT", PAD, ly)
    div1:SetPoint("TOPRIGHT", leftFixed, "TOPRIGHT", -PAD, ly)
    div1:SetColorTexture(1, 1, 1, 0.08)

    ly = ly - 25

    -- Accent-colored title + gray subtitle (BM parity)
    local settingsTitle = leftFixed:CreateFontString(nil, "OVERLAY")
    settingsTitle:SetFont(fontFile, 18, "")
    settingsTitle:SetPoint("TOPLEFT", leftFixed, "TOPLEFT", PAD, ly)
    settingsTitle:SetJustifyH("LEFT")
    settingsTitle:SetWordWrap(false)
    local ac2 = CludesUI.CLUDES_GREEN
    if ac2 then
        settingsTitle:SetTextColor(ac2.r, ac2.g, ac2.b)
    else
        settingsTitle:SetTextColor(0.30, 0.79, 0.94)
    end

    local subTitle = leftFixed:CreateFontString(nil, "OVERLAY")
    subTitle:SetFont(fontFile, 13, "")
    subTitle:SetPoint("LEFT", settingsTitle, "RIGHT", 4, 0)
    subTitle:SetPoint("RIGHT", leftFixed, "RIGHT", -PAD, 0)
    subTitle:SetJustifyH("LEFT")
    subTitle:SetWordWrap(false)
    subTitle:SetTextColor(0.75, 0.75, 0.75, 0.65)

    local selTile
    if not dmInhSel and dmSel ~= "base" then
        for idx = 1, #tiles do
            if tiles[idx].id == dmSel then
                selTile = tiles[idx]
                break
            end
        end
    end
    -- Group views (not All Specs, not a concrete spec) list no base grid: a
    -- "base" selection there means nothing is selected.
    local groupEmpty = (dmSel == "base" and not dmInhSel and not baseOwn and not baseInherited)
    if dmInhSel and inhSelTile then
        local ginfo2 = mod.BM_GROUP_BUCKET_INFO and mod.BM_GROUP_BUCKET_INFO[dmInhSel.group]
        local gname2 = ginfo2 and L(ginfo2.name) or dmInhSel.group
        settingsTitle:SetTextColor(0.55, 0.72, 1)
        settingsTitle:SetText(TileName(inhSelTile))
        subTitle:SetText("(" .. CludesUI.Lf("Inherited from %1$s", gname2) .. ")")
    elseif dmInhSel and inhSelBase then
        settingsTitle:SetTextColor(0.55, 0.72, 1)
        settingsTitle:SetText(L("Base Icons"))
        subTitle:SetText("(" .. CludesUI.Lf("Inherited from %1$s", allSpecsName) .. ")")
    elseif selTile then
        settingsTitle:SetText(L(TYPE_NAMES[selTile.type] or selTile.type))
        subTitle:SetText("(" .. TileSubtitle(selTile) .. ")")
        CludesUI.RegisterWidgetRefresh(function()
            subTitle:SetText("(" .. TileSubtitle(selTile) .. ")")
        end)
    elseif groupEmpty then
        local ginfo3 = mod.BM_GROUP_BUCKET_INFO and mod.BM_GROUP_BUCKET_INFO[dmSpecSel]
        settingsTitle:SetText(ginfo3 and L(ginfo3.name) or dmSpecSel)
        subTitle:SetText("(" .. L("No indicator selected") .. ")")
    else
        settingsTitle:SetText(L("Base Icons"))
        subTitle:SetText("(" .. L("The standard debuff grid") .. ")")
    end

    ly = ly - 18 - 10

    local fixedH = math.abs(ly)
    leftFixed:SetHeight(fixedH)

    -------------------------------------------------------------------
    --  Settings scroll area (BM parity: smooth scroll + thin thumb;
    --  DualRow width compensated so rows align with the 20px PAD)
    -------------------------------------------------------------------
    local contentPad = CludesUI.CONTENT_PAD or 45
    local padDiff = contentPad - PAD
    local viewportH = max(10, visibleH - fixedH)
    local settingsW = leftW + padDiff * 2

    local settingsScroll = CreateFrame("ScrollFrame", nil, root)
    settingsScroll:SetPoint("TOPLEFT", leftFixed, "BOTTOMLEFT", -padDiff, 5)
    settingsScroll:SetSize(settingsW, viewportH)
    settingsScroll:SetFrameLevel(root:GetFrameLevel() + 1)
    settingsScroll:SetClipsChildren(true)

    local settingsChild = CreateFrame("Frame", nil, settingsScroll)
    settingsChild:SetSize(settingsW, viewportH)
    settingsScroll:SetScrollChild(settingsChild)

    local UpdateThumb = CludesUI.AttachSmoothScrollbar(settingsScroll, {
        step = 60,
        width = 5,
        rightInset = 31,
        topInset = 12,
        level = 20,
        trackAlpha = 0.05,
        thumbAlpha = 0.22,
        child = settingsChild,
        panelWheel = true,
    })

    -- Read-only pane for an INHERITED row (group tile or the All Specs base
    -- grid): where it lives, a jump link to the owning group, and a pointer
    -- at the tile toggle for the per-spec enable. No settings render --
    -- edits belong to the group. (Child x = padDiff + PAD aligns with the
    -- PAD margin.) Returns the consumed height.
    local function BuildInheritedPane(gname2, jumpGroup, jumpId)
        local details = settingsChild:CreateFontString(nil, "OVERLAY")
        details:SetFont(fontFile, 12, "")
        details:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", padDiff + PAD, -14)
        details:SetPoint("RIGHT", settingsChild, "RIGHT", -(padDiff + PAD), 0)
        details:SetJustifyH("LEFT")
        details:SetWordWrap(true)
        details:SetText(
            CludesUI.Lf(
                "Inherited from %1$s. Edit it there, or use the tile toggle to enable or disable it for this spec.",
                gname2
            )
        )
        details:SetTextColor(0.65, 0.65, 0.65)
        local itemLink = CreateFrame("Button", nil, settingsChild)
        itemLink:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", padDiff + PAD, -78)
        itemLink:SetFrameLevel(settingsChild:GetFrameLevel() + 2)
        local linkFS = itemLink:CreateFontString(nil, "OVERLAY")
        linkFS:SetFont(fontFile, 12, "")
        linkFS:SetPoint("TOPLEFT")
        linkFS:SetText(CludesUI.Lf("Edit in %1$s", gname2))
        local lac = CludesUI.CLUDES_GREEN
        if lac then
            linkFS:SetTextColor(lac.r, lac.g, lac.b, 0.85)
        else
            linkFS:SetTextColor(0.30, 0.79, 0.94, 0.85)
        end
        itemLink:SetSize(linkFS:GetStringWidth() + 4, 18)
        itemLink:SetScript("OnEnter", function()
            linkFS:SetAlpha(1)
        end)
        itemLink:SetScript("OnLeave", function()
            linkFS:SetAlpha(0.85)
        end)
        itemLink:SetScript("OnClick", function()
            dmSpecSel = jumpGroup
            dmSel = jumpId
            dmInhSel = nil
            CludesUI:RefreshPage(true)
        end)
        return -110
    end

    -- Detail rows build inside the scroll child
    local sy
    if dmInhSel and inhSelTile then
        local ginfo2 = mod.BM_GROUP_BUCKET_INFO and mod.BM_GROUP_BUCKET_INFO[dmInhSel.group]
        local gname2 = ginfo2 and L(ginfo2.name) or dmInhSel.group
        sy = BuildInheritedPane(gname2, dmInhSel.group, dmInhSel.id)
    elseif dmInhSel and inhSelBase then
        sy = BuildInheritedPane(allSpecsName, "allspecs", "base")
    elseif selTile then
        sy = BuildTileDetail(settingsChild, fontFile, selTile)
    elseif groupEmpty then
        -- Group view with nothing selected: All Specs content (base grid
        -- included) is not listed here, exactly like it is not for tiles.
        local details = settingsChild:CreateFontString(nil, "OVERLAY")
        details:SetFont(fontFile, 12, "")
        details:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", padDiff + PAD, -14)
        details:SetPoint("RIGHT", settingsChild, "RIGHT", -(padDiff + PAD), 0)
        details:SetJustifyH("LEFT")
        details:SetWordWrap(true)
        details:SetText(
            CludesUI.Lf(
                "Indicators added here show on every spec in this group. The Base Icons grid lives in %1$s.",
                allSpecsName
            )
        )
        details:SetTextColor(0.65, 0.65, 0.65)
        sy = -60
    else
        sy = BuildBaseDetailDM(settingsChild, fontFile)
    end

    settingsChild:SetHeight(max(viewportH, math.abs(sy or 0) + 12))
    UpdateThumb()

    -- First render of the preview content
    if mod.DMP_RefreshPreview then
        mod.DMP_RefreshPreview()
    end

    -- Override-session overlay (mirror of the Buff Manager page's): built
    -- LAST so it covers the whole page incl. the sidebar. High frame level;
    -- child of outerRoot so every teardown path destroys it.
    if dmOverlayState then
        local st = dmOverlayState
        local _, button = CludesUI.BuildActivationOverlay(outerRoot, {
            fontPath = fontFile,
            width = parentW,
            title = CludesUI.L("Custom Debuff Manager"),
            text = st.text,
            sub = st.sub,
            buttonLabel = st.mode == "activate" and CludesUI.L("Activate Custom Debuff Manager") or nil,
        })
        if button then
            button:SetScript("OnClick", function()
                CludesUI.SpecOverrides_ActivateDm(st.kind, st.gid)
            end)
        end
    end

    CludesUI._EndRootRender("rf.dm")
    return 0
end

-------------------------------------------------------------------------------
-- BUFF MANAGER v2 page (spell -> filter -> indicator). Replaces the legacy
-- BM page wholesale on 12.1 (the options file redirects BuildBuffManagerPage
-- here when v2 is loaded). Assigns ns._bmRoot so every existing cleanup
-- path (page switch, panel close, module switch) manages this page too;
-- the Filter Editor popup parents into the root and dies with it.
-------------------------------------------------------------------------------

local CLASS_ORDER = CludesUI.CLASS_TOKEN_ORDER

-- Filter Editor popup: right sidebar = filter list (presets pinned),
-- left = the selected filter's spells as checkboxes grouped by class
-- (curated data) or under Custom (user-added), plus an Add Spell ID box.
local fdSel = nil -- selected filter id
local fdScrollPos = 0 -- preserved spell-list scroll across editor rebuilds

-- Filter Editor modal, built on the standard popup chrome (mirrors
-- ShowInputPopup: fullscreen dimmer at black 0.25, opaque 0.06/0.08/0.10
-- panel, 0.15 white border, MakeFont title, SolidTex+MakeBorder buttons).
-- Right sidebar = filter list (presets pinned; custom rename via the
-- standard input popup + delete via the standard confirm popup); left =
-- the selected filter's spells as checkbox rows using the checkbox-
-- dropdown widget's exact visuals, grouped by class.
-- show / hide: the opening dropdown's Show and Hide picks (id -> true). The
-- editor opens on the first picked filter in list order; with none picked it
-- keeps the last one viewed.
function mod.BMP_ShowFilterEditor(show, hide)
    local filters = mod.BM2_Filters and mod.BM2_Filters()
    if not filters then
        if mod._bm2FilterEditor then
            mod._bm2FilterEditor:Hide()
            mod._bm2FilterEditor = nil
        end
        return
    end
    -- An open editor stays shown until the kept frame's reset below (that
    -- reset is the previous dress's teardown), so the frame under the cursor,
    -- dressed again in place, gets its OnEnter back from the pool.
    if show or hide then
        for idx = 1, #filters do
            local ident = filters[idx].id
            if (show and show[ident]) or (hide and hide[ident]) then
                fdSel = ident
                break
            end
        end
    end
    local fontFile = (CludesUI.GetFontPath("options"))
        or (CludesUI.GetFontPath("raidFrames"))
        or "Fonts\\FRIZQT__.TTF"
    local ar, ag, ab = 1, 0.82, 0.30
    if CludesUI.GetAccentColor then
        ar, ag, ab = CludesUI.GetAccentColor()
    end
    local eg = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }

    local POPUP_W, POPUP_H = 620, 520
    local SIDE_W = 180

    -- One editor for the session (the options page pool): every open and every
    -- Rebuild below dress it again; its reset is the previous dress's teardown
    -- (a keyboard capture is put back out of combat only, by the pool).
    local dimmer = PoolKept(mod, "bm2FilterEditor", "Frame", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    -- Clicking off the popup closes the editor (the popup is mouse-enabled,
    -- so clicks on it never reach the dimmer).
    dimmer:SetScript("OnMouseDown", function()
        dimmer:Hide()
        mod._bm2FilterEditor = nil
    end)
    local dimTex = CludesUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
    dimTex:SetAllPoints()
    mod._bm2FilterEditor = dimmer

    local dialog = CreateFrame("Frame", nil, dimmer)
    dialog:SetSize(POPUP_W, POPUP_H)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    dialog:EnableMouse(true)
    local popBg = CludesUI.SolidTex(dialog, "BACKGROUND", 0.062, 0.070, 0.082, 1)
    popBg:SetAllPoints()
    CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, popBg)
    local ppScale = CludesUI.GetPopupScale() or 1
    dialog:SetScale(ppScale)

    local title = CludesUI.MakeFont(dialog, 16, "", 1, 1, 1)
    title:SetPoint("TOP", dialog, "TOP", 0, -18)
    title:SetText(CludesUI.L("Edit Filters"))

    -- Close button (top-right): the borderless X (the boxed close-popup
    -- variant reads as a framed button here).
    do
        local close = CreateFrame("Button", nil, dialog)
        close:SetSize(19, 19)
        close:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -13, -8)
        close:SetFrameLevel(dialog:GetFrameLevel() + 5)
        local closeIcon = close:CreateTexture(nil, "ARTWORK")
        closeIcon:SetAllPoints()
        closeIcon:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
        closeIcon:SetAlpha(0.40)
        closeIcon:SetSnapToPixelGrid(false)
        closeIcon:SetTexelSnappingBias(0)
        close:SetScript("OnEnter", function()
            closeIcon:SetAlpha(0.50)
        end)
        close:SetScript("OnLeave", function()
            closeIcon:SetAlpha(0.40)
        end)
        close:SetScript("OnClick", function()
            dimmer:Hide()
            mod._bm2FilterEditor = nil
        end)
    end

    -- Escape closes the editor alone: the key is swallowed here, so it never
    -- reaches the Escape proxy that would close the options window too.
    -- SetPropagateKeyboardInput is protected in combat, so the editor takes
    -- the keyboard only when built out of combat and stands aside in it. The
    -- capture is a frame of its own, owned by the popup outside its child
    -- list: a dress in combat cannot clear keyboard flags, so it leaves only
    -- that frame for the next dress out of combat, never the popup.
    if not InCombatLockdown() then
        local keyList = PoolOwned(dialog, "keys", "Frame", dialog)
        keyList:SetAllPoints(dialog)
        keyList:EnableKeyboard(true)
        keyList:SetPropagateKeyboardInput(true)
        keyList:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then
                return
            end
            self:SetPropagateKeyboardInput(key ~= "ESCAPE")
            if key == "ESCAPE" then
                dimmer:Hide()
                mod._bm2FilterEditor = nil
            end
        end)
    end

    -- Validate selection
    if fdSel then
        local success = false
        for idx = 1, #filters do
            if filters[idx].id == fdSel then
                success = true
            end
        end
        if not success then
            fdSel = nil
        end
    end
    if not fdSel and filters[1] then
        fdSel = filters[1].id
    end

    local function Rebuild()
        mod.BMP_ShowFilterEditor()
    end
    local function Apply()
        if mod.BM2_Invalidate then
            mod.BM2_Invalidate()
        end
        if mod.ReloadFrames then
            mod.ReloadFrames()
        end
    end
    -- The standard input popup is a lazily-created singleton that predates
    -- this (later-created) editor, so at equal strata it renders BEHIND it.
    -- Raise it above the editor whenever it opens from here.
    local function EditorInput(options)
        CludesUI:ShowInputPopup(options)
        local d = _G.CUIInputDimmer
        if d and mod._bm2FilterEditor then
            d:SetFrameLevel(dialog:GetFrameLevel() + 40)
            local p = _G.CUIInputPopup
            if p then
                p:SetFrameLevel(d:GetFrameLevel() + 10)
            end
        end
    end

    local MEDIA_FE = "Interface\\AddOns\\CludesUI\\media\\icons\\"

    -- Standard smooth scroll + thin custom scrollbar for an editor scroll
    -- region (the settings-viewport pattern). Track shows only on overflow.
    -- Returns UpdateThumb and a SetScrollTo(v) that syncs bar + target.
    local function AttachEditorScroll(scroll, childFrame, onScroll)
        return CludesUI.AttachSmoothScrollbar(scroll, {
            step = 60,
            thumbMin = 20,
            topInset = 2,
            level = 5,
            trackAlpha = 0.05,
            thumbAlpha = 0.22,
            child = childFrame,
            onScroll = onScroll,
        })
    end

    -- RIGHT: filter list (dropdown-item styling: hover wash, accent-washed
    -- selected row)
    local side = CreateFrame("Frame", nil, dialog)
    side:SetWidth(SIDE_W)
    -- Flush with the popup's right edge and bottom.
    side:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", 0, -44)
    side:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", 0, 0)
    side:SetFrameLevel(dialog:GetFrameLevel() + 1)
    local sideBg = CludesUI.SolidTex(side, "BACKGROUND", 0, 0, 0, 0.35)
    sideBg:SetAllPoints()
    -- Flush with the popup's bottom-right corner: same shape, rows clipped to it.
    CludesUI.MakeRoundedBorder(side, 1, 1, 1, 0.10, sideBg, nil, true)

    -- Sidebar content scrolls when it outgrows the popup (standard smooth
    -- scroll + thin custom bar; bar shows only on overflow).
    local sideScroll = CreateFrame("ScrollFrame", nil, side)
    sideScroll:SetPoint("TOPLEFT", side, "TOPLEFT", 1, -1)
    sideScroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -1, 1)
    sideScroll:SetFrameLevel(side:GetFrameLevel() + 1)
    local sideChild = CreateFrame("Frame", nil, sideScroll)
    sideChild:SetWidth(SIDE_W - 2)
    sideScroll:SetScrollChild(sideChild)

    local fy = -4
    for idx = 1, #filters do
        local f = filters[idx]
        local isSel = (fdSel == f.id)
        local frow = CreateFrame("Button", nil, sideChild)
        frow:SetHeight(26)
        frow:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 0, fy)
        frow:SetPoint("TOPRIGHT", sideChild, "TOPRIGHT", 0, fy)
        frow:SetFrameLevel(sideChild:GetFrameLevel() + 1)
        local rbg = frow:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        rbg:SetColorTexture(1, 1, 1, isSel and 0.07 or 0)
        local rl = CludesUI.MakeFont(frow, 12, nil, 1, 1, 1)
        rl:SetAlpha(isSel and 0.95 or 0.6)
        rl:SetPoint("LEFT", frow, "LEFT", 10, 0)
        rl:SetPoint("RIGHT", frow, "RIGHT", f.preset and -8 or -42, 0)
        rl:SetJustifyH("LEFT")
        rl:SetWordWrap(false)
        rl:SetText(L(f.name))
        if isSel then
            local accent = frow:CreateTexture(nil, "ARTWORK", nil, 2)
            accent:SetSize(2, 26)
            accent:SetPoint("TOPLEFT", frow, "TOPLEFT", 0, 0)
            accent:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
        end
        frow:SetScript("OnEnter", function()
            if not isSel then
                rbg:SetColorTexture(1, 1, 1, 0.04)
            end
        end)
        frow:SetScript("OnLeave", function()
            rbg:SetColorTexture(1, 1, 1, isSel and 0.07 or 0)
        end)
        frow:SetScript("OnClick", function()
            fdSel = f.id
            fdScrollPos = 0 -- new filter = new list; start at the top
            Rebuild()
        end)
        if not f.preset then
            -- Inline X (delete) + pencil (rename) -- the CDM preset-menu
            -- inline-button pattern (cui-close / cui-edit at 14px).
            local del = CreateFrame("Button", nil, frow)
            del:SetSize(14, 14)
            del:SetPoint("RIGHT", frow, "RIGHT", -6, 0)
            del:SetFrameLevel(frow:GetFrameLevel() + 1)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then
                dx:SetSnapToPixelGrid(false)
                dx:SetTexelSnappingBias(0)
            end
            dx:SetTexture(MEDIA_FE .. "cui-close.png")
            del:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                CludesUI.ShowWidgetTooltip(self, CludesUI.L("Delete"))
            end)
            del:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                CludesUI.HideWidgetTooltip()
            end)
            del:SetScript("OnClick", function()
                CludesUI:ShowConfirmPopup({
                    title = CludesUI.L("Delete Filter"),
                    message = CludesUI.L("Delete this filter? It is removed from every indicator using it."),
                    confirmText = CludesUI.L("Delete"),
                    cancelText = CludesUI.L("Cancel"),
                    onConfirm = function()
                        mod.BM2_DeleteFilter(f.id)
                        Apply()
                        Rebuild()
                    end,
                })
            end)

            local edit = CreateFrame("Button", nil, frow)
            edit:SetSize(14, 14)
            edit:SetPoint("RIGHT", del, "LEFT", -4, 0)
            edit:SetFrameLevel(frow:GetFrameLevel() + 1)
            edit:SetAlpha(0.5)
            local ex = edit:CreateTexture(nil, "OVERLAY")
            ex:SetAllPoints()
            if ex.SetSnapToPixelGrid then
                ex:SetSnapToPixelGrid(false)
                ex:SetTexelSnappingBias(0)
            end
            ex:SetTexture(MEDIA_FE .. "cui-edit.png")
            edit:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                CludesUI.ShowWidgetTooltip(self, CludesUI.L("Edit"))
            end)
            edit:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                CludesUI.HideWidgetTooltip()
            end)
            edit:SetScript("OnClick", function()
                EditorInput({
                    title = CludesUI.L("Rename Filter"),
                    placeholder = f.name,
                    confirmText = CludesUI.L("Rename"),
                    cancelText = CludesUI.L("Cancel"),
                    onConfirm = function(textValue)
                        mod.BM2_RenameFilter(f.id, textValue)
                        Rebuild()
                    end,
                })
            end)
        end
        fy = fy - 27
    end
    local addFilterBtn = CludesUI.BuildPopupButton(sideChild, SIDE_W - 16, 26, "Add Filter", function()
        EditorInput({
            title = CludesUI.L("Add Filter"),
            message = CludesUI.L("Name the new filter."),
            confirmText = CludesUI.L("Add"),
            cancelText = CludesUI.L("Cancel"),
            onConfirm = function(textValue)
                local f = mod.BM2_AddFilter(
                    (textValue and textValue ~= "" and textValue) or CludesUI.L("New Filter")
                )
                if f then
                    fdSel = f.id
                end
                Rebuild()
            end,
        })
    end)
    addFilterBtn:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 8, fy - 8)
    local sideBottom = fy - 8 - 26
    -- One-time copy of the Player Aura Bars filter setups INTO this library
    -- by name (same-named filters replaced, missing ones created). Ids here
    -- never change, so indicator assignments and banked spec-override forks
    -- stay valid. Hidden while that module is disabled.
    if CludesUI._PABFilterBridge then
        local copyBtn = CludesUI.BuildPopupButton(
            sideChild,
            SIDE_W - 16,
            26,
            CludesUI.L("Copy Player Auras Filters"),
            function()
                CludesUI:ShowConfirmPopup({
                    title = CludesUI.L("Copy Player Auras Filters"),
                    message = CludesUI.L(
                        "One-time copy of your Player Aura Bars filter setups into these filters. Same-named filters are OVERWRITTEN; the two lists stay separate afterwards."
                    ),
                    confirmText = CludesUI.L("Copy"),
                    cancelText = CludesUI.L("Cancel"),
                    typeToConfirm = "Confirm",
                    onConfirm = function()
                        local br = CludesUI._PABFilterBridge
                        if br and br.CopyIntoBM2() then
                            Apply()
                            Rebuild()
                        end
                    end,
                })
            end
        )
        copyBtn:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 8, sideBottom - 6)
        sideBottom = sideBottom - 6 - 26
    end
    sideChild:SetHeight(math.abs(sideBottom) + 8)
    local updSideThumb = AttachEditorScroll(sideScroll, sideChild)
    updSideThumb()

    -- LEFT: selected filter detail
    local sel
    for idx = 1, #filters do
        if filters[idx].id == fdSel then
            sel = filters[idx]
        end
    end
    if not sel then
        return
    end

    local leftX = CreateFrame("Frame", nil, dialog)
    leftX:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -44)
    leftX:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -(SIDE_W + 12), 12)
    leftX:SetFrameLevel(dialog:GetFrameLevel() + 1)

    local nm = CludesUI.MakeFont(leftX, 13, nil, 1, 1, 1)
    nm:SetAlpha(0.9)
    nm:SetPoint("TOPLEFT", leftX, "TOPLEFT", 2, -2)
    nm:SetText(L(sel.name))
    if not sel.preset then
        local ren = CreateFrame("Button", nil, leftX)
        ren:SetSize(54, 16)
        ren:SetPoint("LEFT", nm, "RIGHT", 10, 0)
        ren:SetFrameLevel(leftX:GetFrameLevel() + 2)
        local rl = CludesUI.MakeFont(ren, 11, nil, ar, ag, ab)
        rl:SetAlpha(0.9)
        rl:SetPoint("LEFT")
        rl:SetText(CludesUI.L("Rename"))
        ren:SetScript("OnEnter", function()
            rl:SetAlpha(1)
        end)
        ren:SetScript("OnLeave", function()
            rl:SetAlpha(0.9)
        end)
        ren:SetScript("OnClick", function()
            EditorInput({
                title = CludesUI.L("Rename Filter"),
                placeholder = sel.name,
                confirmText = CludesUI.L("Rename"),
                cancelText = CludesUI.L("Cancel"),
                onConfirm = function(textValue)
                    mod.BM2_RenameFilter(sel.id, textValue)
                    Rebuild()
                end,
            })
        end)
    end

    -- Preset-universe spell search (identical list to the Extra Spells
    -- dropdown: curated primaries, name-sorted, spell icons, searchable):
    -- every spell already ON this filter is excluded -- checked or unchecked, curated
    -- or custom alike. Picking one adds it to the filter's Custom group (the same
    -- landing as Add Spell ID) and the editor rebuild re-lists without it.
    local searchDD = CludesUI.BuildVisOptsCBDropdown(
        leftX,
        170,
        leftX:GetFrameLevel() + 5,
        function()
            local f = (mod.BM2_GetFilter and mod.BM2_GetFilter(sel.id)) or sel
            local universe = (mod.BM2_AllPresetSpells and mod.BM2_AllPresetSpells()) or {}
            -- WoW Forever: a rank alternate on the filter holds its family's
            -- primary too, so the search offers no second row for that buff.
            -- nil on every other client.
            local ap = mod.BM2_ForeverAltPrimary
            local held
            if ap then
                held = {}
                if f.spells then
                    for spellRef in pairs(f.spells) do
                        if ap[spellRef] and not mod.BM2_OtherClientSpell(f, spellRef) then
                            held[ap[spellRef]] = true
                        end
                    end
                end
                if f.custom then
                    for spellRef in pairs(f.custom) do
                        if ap[spellRef] then
                            held[ap[spellRef]] = true
                        end
                    end
                end
            end
            local result = {}
            for idx = 1, #universe do
                local ident = universe[idx]
                -- An id kept only for the other client is not on the filter here.
                local onFilter = (
                    f.spells
                    and f.spells[ident] ~= nil
                    and not mod.BM2_OtherClientSpell(f, ident)
                )
                    or (f.custom and f.custom[ident])
                    or (held and held[ident])
                if not onFilter then
                    local nm = (mod.SPELL_NAME_BY_ID and mod.SPELL_NAME_BY_ID[ident])
                        or (C_Spell.GetSpellName and C_Spell.GetSpellName(ident))
                    result[#result + 1] = {
                        key = ident,
                        label = nm or tostring(ident),
                        noCheck = true,
                        icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ident),
                    }
                end
            end
            table.sort(result, function(a, b)
                return tostring(a.label or a.key) < tostring(b.label or b.key)
            end)
            return result
        end,
        function()
            return false
        end, -- nothing listed is ever on the filter
        function(k, val)
            if val and mod.BM2_AddCustomSpell and mod.BM2_AddCustomSpell(sel.id, k) then
                Apply()
                Rebuild()
            end
        end,
        nil,
        10,
        true
    )
    searchDD:ClearAllPoints()
    searchDD:SetPoint("TOPLEFT", leftX, "TOPLEFT", 2, -23)
    -- One-shot title: the checked-count summary a checkbox dropdown shows
    -- ("None") reads wrong for an action search, and every add rebuilds
    -- the editor, so the label never needs re-asserting.
    for _, r in ipairs({ searchDD:GetRegions() }) do
        if r.SetText and r.GetText then
            r:SetText(CludesUI.L("Search Spells"))
            break
        end
    end

    local addSpellBtn = CludesUI.BuildPopupButton(leftX, 110, 24, "Add Spell ID", function()
        EditorInput({
            title = CludesUI.L("Add Spell ID"),
            message = CludesUI.L("Enter the spell ID to add to this filter."),
            confirmText = CludesUI.L("Add"),
            cancelText = CludesUI.L("Cancel"),
            onConfirm = function(textValue)
                local ident = tonumber(textValue or "")
                -- Typed: the ID tracks that aura alone (a Search Spells
                -- pick above keeps the buff's other versions).
                if ident and mod.BM2_AddCustomSpell(sel.id, ident, true) then
                    Apply()
                    Rebuild()
                end
            end,
        })
    end)
    addSpellBtn:SetPoint("LEFT", searchDD, "RIGHT", 8, 0)

    -- Spell checkbox list: rows mirror the checkbox-dropdown widget's
    -- visuals exactly (16px box at 0.12/0.12/0.14, gray 0.4 border, accent
    -- fill inset 2, hover wash), grouped All Classes / class-colored / Custom.
    local scroll = CreateFrame("ScrollFrame", nil, leftX)
    scroll:SetPoint("TOPLEFT", leftX, "TOPLEFT", 0, -58)
    scroll:SetPoint("BOTTOMRIGHT", leftX, "BOTTOMRIGHT", 0, 0)
    local childFrame = CreateFrame("Frame", nil, scroll)
    childFrame:SetWidth(POPUP_W - SIDE_W - 40)
    scroll:SetScrollChild(childFrame)
    -- Standard smooth scroll + thin bar; every scroll write persists the
    -- position so rebuilds land the user back where they were.
    local _updSpellThumb, setSpellScroll = AttachEditorScroll(scroll, childFrame, function(val)
        fdScrollPos = val
    end)

    local curated = (mod.BM2_DEFAULT_FILTER_SPELLS and sel.preset)
            and mod.BM2_DEFAULT_FILTER_SPELLS[sel.preset]
        or nil
    local byClass, customList = {}, {}
    for ident in pairs(sel.spells) do
        local details = curated and curated[ident]
        if details and details.class then
            byClass[details.class] = byClass[details.class] or {}
            table.insert(byClass[details.class], ident)
        elseif not mod.BM2_OtherClientSpell(sel, ident) then
            -- Ids kept only for the other client get no row.
            table.insert(customList, ident)
        end
    end
    -- Alphabetical by spell name (id tiebreak for identical names).
    local function NameOf(ident)
        return (mod.SPELL_NAME_BY_ID and mod.SPELL_NAME_BY_ID[ident])
            or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident))
            or tostring(ident)
    end
    local function ByName(a, b)
        local na, nb = NameOf(a), NameOf(b)
        if na == nb then
            return a < b
        end
        return na < nb
    end
    for _, entries in pairs(byClass) do
        table.sort(entries, ByName)
    end
    table.sort(customList, ByName)

    local cy = 0
    local function SpellRow(ident, classColor)
        local srow = CreateFrame("Button", nil, childFrame)
        srow:SetHeight(24)
        srow:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 2, cy)
        srow:SetPoint("TOPRIGHT", childFrame, "TOPRIGHT", -2, cy)
        srow:SetFrameLevel(childFrame:GetFrameLevel() + 1)
        local highlight = srow:CreateTexture(nil, "ARTWORK")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0)
        local box = CreateFrame("Frame", nil, srow)
        box:SetSize(16, 16)
        box:SetPoint("LEFT", srow, "LEFT", 6, 0)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints()
        boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
        local boxBrd = CludesUI.MakeRoundedBorder(box, 0.4, 0.4, 0.4, 0.6, boxBg)
        local chk = box:CreateTexture(nil, "ARTWORK")
        chk:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
        chk:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        chk:SetColorTexture(eg.r, eg.g, eg.b, 1)
        CludesUI.RoundBody(box, chk, 2)
        local on = sel.spells[ident] and true or false
        local ico = srow:CreateTexture(nil, "ARTWORK")
        ico:SetSize(22, 22)
        ico:SetPoint("LEFT", box, "RIGHT", 6, 0)
        local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ident)
        if texture then
            ico:SetTexture(texture)
        end
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local name = (mod.SPELL_NAME_BY_ID and mod.SPELL_NAME_BY_ID[ident])
            or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident))
        local lr, lg2, lb2 = 1, 1, 1
        if classColor then
            lr, lg2, lb2 = classColor.r, classColor.g, classColor.b
        end
        -- A user-added id the preset has since curated keeps its custom mark
        -- (it stays if the curation is ever dropped) but is a curated row now:
        -- no remove control.
        local removable = sel.custom[ident] and not (curated and curated[ident])
        local labelFS = CludesUI.MakeFont(srow, 13, nil, lr, lg2, lb2)
        labelFS:SetPoint("LEFT", ico, "RIGHT", 6, 0)
        labelFS:SetPoint("RIGHT", srow, "RIGHT", removable and -24 or -6, 0)
        labelFS:SetJustifyH("LEFT")
        labelFS:SetWordWrap(false)
        labelFS:SetText(name or ("Spell " .. tostring(ident)))
        -- Toggles update IN PLACE -- a rebuild here would reset the list
        -- scroll position out from under the cursor.
        local function UpdateRow()
            on = sel.spells[ident] and true or false
            if on then
                chk:Show()
                if boxBrd and boxBrd.SetColor then
                    boxBrd:SetColor(eg.r, eg.g, eg.b, 0.8)
                end
            else
                chk:Hide()
                if boxBrd and boxBrd.SetColor then
                    boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                end
            end
            labelFS:SetAlpha(on and 0.9 or 0.45)
            -- Dim the spell icon with the text (it stayed full-bright).
            ico:SetAlpha(on and 1 or 0.45)
            ico:SetDesaturated(not on)
        end
        UpdateRow()
        srow:SetScript("OnEnter", function()
            highlight:SetColorTexture(1, 1, 1, 0.04)
        end)
        srow:SetScript("OnLeave", function()
            highlight:SetColorTexture(1, 1, 1, 0)
        end)
        srow:SetScript("OnClick", function()
            mod.BM2_SetSpellState(sel.id, ident, not on)
            Apply()
            UpdateRow()
        end)
        if removable then
            local del = CreateFrame("Button", nil, srow)
            del:SetSize(14, 14)
            del:SetPoint("RIGHT", srow, "RIGHT", -6, 0)
            del:SetFrameLevel(srow:GetFrameLevel() + 1)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then
                dx:SetSnapToPixelGrid(false)
                dx:SetTexelSnappingBias(0)
            end
            dx:SetTexture(MEDIA_FE .. "cui-close.png")
            del:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
            end)
            del:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
            end)
            del:SetScript("OnClick", function()
                mod.BM2_SetSpellState(sel.id, ident, nil)
                Apply()
                Rebuild()
            end)
        end
        cy = cy - 29
    end
    local function GroupHeader(textValue)
        local heading = CludesUI.MakeFont(childFrame, 14, nil, 0.5, 0.5, 0.5)
        heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 2, cy - 10)
        heading:SetText(textValue)
        local line = childFrame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", heading, "RIGHT", 6, 0)
        line:SetPoint("RIGHT", childFrame, "RIGHT", -10, 0)
        line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        cy = cy - 30
    end
    -- Custom leads (the user's own additions), then All Classes, then the class groups.
    if #customList > 0 then
        GroupHeader(CludesUI.L("Custom"))
        for idx = 1, #customList do
            SpellRow(customList[idx])
        end
    end
    if byClass.ALL and #byClass.ALL > 0 then
        GroupHeader(CludesUI.L("All Classes"))
        for idx = 1, #byClass.ALL do
            SpellRow(byClass.ALL[idx])
        end
    end
    for c = 1, #CLASS_ORDER do
        local cls = CLASS_ORDER[c]
        local entries = byClass[cls]
        if entries and #entries > 0 then
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            local cname = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls] or cls
            GroupHeader(cc and ("|c" .. cc.colorStr .. cname .. "|r") or cname)
            for idx = 1, #entries do
                SpellRow(entries[idx], cc)
            end
        end
    end
    if cy == 0 then
        local empty = CludesUI.MakeFont(childFrame, 12, nil, 1, 1, 1)
        empty:SetAlpha(0.4)
        empty:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 4, -6)
        empty:SetText(CludesUI.L("No spells yet. Add spell IDs above."))
        cy = -30
    end
    childFrame:SetHeight(math.abs(cy) + 10)

    -- Restore the preserved scroll position (rebuilds from add/remove/
    -- rename land the user back where they were, clamped to the new range).
    setSpellScroll(fdScrollPos)
end

-- "ASSIGNED BUFFS" section for the legacy BM page's settings scroll: one
-- standard DualRow -- left = "Filters" checkbox dropdown (the shared
-- BuildVisOptsCBDropdown widget) with an inline accent "Edit Filters" link,
-- right = "Extra Spells" searchable checkbox dropdown over the curated
-- spell universe plus the indicator's custom ids, with an inline accent
-- "Custom ID" link that opens the standard input popup. Built on the
-- canonical placeholder-dropdown hosting pattern (hide rgn._control, mount
-- the CB dropdown, re-point, register its refresh).
function mod.BMP_BuildAssignedFilters(hostFrame, sy, ind, fontFile)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PP or CludesUI.PanelPP
    if not (W and Pix) then
        return sy
    end
    local hh
    local _r
    _r, hh = W:SectionHeader(hostFrame, "ASSIGNED BUFFS", sy)
    sy = sy - hh

    local row
    row, hh = W:DualRow(hostFrame, sy, {
        type = "dropdown",
        text = "Filters",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
    }, {
        type = "dropdown",
        text = "Extra Spells",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
    })
    sy = sy - hh

    -- LEFT: Filters checkbox dropdown; "Edit Filters" rides the menu as a
    -- pinned top action with a divider (the CDM spell-picker pattern).
    -- TWO-LANE rows: the left checkbox SHOWS a filter's spells (ind.filters,
    -- the classic union), the right red box HIDES them (ind.negFilters --
    -- dropped from the resolved union in BM2_ResolveSpellsOwn; direct Extra
    -- Spells win over the hide lane). Lanes are mutually exclusive per filter.
    do
        local region = row._leftRegion
        if region._control then
            region._control:Hide()
        end
        -- Dynamic items (function): the filter list re-evaluates on every
        -- menu open, so filters added/renamed in the editor appear live.
        local function FilterItems()
            local filters = (mod.BM2_Filters and mod.BM2_Filters()) or {}
            local itemList = {
                {
                    isTopAction = true,
                    label = "Edit Filters",
                    onClick = function()
                        mod.BMP_ShowFilterEditor(ind.filters, ind.negFilters)
                    end,
                },
                { isHeader = true, label = "Show", rightLabel = "Hide" },
            }
            for idx = 1, #filters do
                itemList[#itemList + 1] = { key = filters[idx].id, label = filters[idx].name, dual = true }
            end
            return itemList
        end
        local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            region,
            190,
            region:GetFrameLevel() + 2,
            FilterItems,
            function(k, neg)
                if neg then
                    return ind.negFilters and ind.negFilters[k] == true
                end
                return ind.filters and ind.filters[k] and true or false
            end,
            function(k, val, neg)
                -- Two-lane write: checking one lane clears the other.
                if neg then
                    ind.negFilters = ind.negFilters or {}
                    ind.negFilters[k] = val and true or nil
                    if not next(ind.negFilters) then
                        ind.negFilters = nil
                    end
                    if val and ind.filters then
                        ind.filters[k] = nil
                    end
                else
                    if not ind.filters then
                        ind.filters = {}
                    end
                    ind.filters[k] = val and true or nil
                    if val and ind.negFilters then
                        ind.negFilters[k] = nil
                        if not next(ind.negFilters) then
                            ind.negFilters = nil
                        end
                    end
                end
                if mod.BM2_Invalidate then
                    mod.BM2_Invalidate()
                end
                -- Frames and preview now, then the selected tile's icon and
                -- spell list (a widget refresh keeps this menu open).
                if mod._bmReloadAndUpdate then
                    mod._bmReloadAndUpdate()
                elseif mod.ReloadFrames then
                    mod.ReloadFrames()
                end
                CludesUI:RefreshPage()
            end,
            nil,
            12
        )
        CludesUI.PanelPP.Point(cbDD, "RIGHT", region, "RIGHT", -20, 0)
        region._control = cbDD
        region._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- RIGHT: Extra Spells searchable checkbox dropdown; "Custom Spell ID"
    -- rides the menu as a pinned top action above the search bar
    -- (ns.BM2_SpellIdAction).
    do
        local region = row._rightRegion
        if region._control then
            region._control:Hide()
        end
        local function HasDirect(ident)
            local sp = ind.spells
            if not sp then
                return false
            end
            for idx = 1, #sp do
                if sp[idx] == ident then
                    return true
                end
            end
            return false
        end
        -- A typed ID tracks that aura alone, not the rest of its curated
        -- family; typing one already picked from Presets narrows it the same
        -- way. (WoW Forever writes no mark: a typed rank stands for every
        -- rank, and one that came with a profile stays as it is.)
        local idAction = mod.BM2_SpellIdAction(function(ident)
            local ex = ind.exactSpells
            local was = ex and ex[ident]
            local added = not HasDirect(ident)
            if added then
                ind.spells = ind.spells or {}
                ind.spells[#ind.spells + 1] = ident
            end
            mod.BM2_SetSpellExact(ind, ident, true)
            ex = ind.exactSpells
            if added or (ex and ex[ident]) ~= was then
                if mod.ReloadFrames then
                    mod.ReloadFrames()
                end
                CludesUI:RefreshPage(true)
            end
        end)
        -- Universe = curated preset primaries (name-sorted) plus any custom
        -- ids already on the indicator that fall outside it.
        -- Two groups: "Selected" = everything currently assigned (universe
        -- picks AND custom ids alike), "Presets" = the remaining curated
        -- universe. Dynamic items (function): re-evaluated on every menu open, so
        -- grouping and the filter-covered exclusion never go stale. Spells already
        -- provided by the ASSIGNED FILTERS' enabled spells are excluded from Presets
        -- (adding them as extras would be redundant); direct picks always show under
        -- Selected so they can be unchecked.
        local function SpellEntry(ident)
            local name = (mod.SPELL_NAME_BY_ID and mod.SPELL_NAME_BY_ID[ident])
                or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident))
            local labelText = name or ("Spell " .. tostring(ident))
            -- Truncated rows (long/duplicate names) still need to be told apart on hover.
            return {
                key = ident,
                label = labelText,
                tooltip = labelText,
                icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ident),
            }
        end
        local function ByLabel(a, b)
            return a.label < b.label
        end
        local function ExtraItems()
            -- WoW Forever: a rank alternate stands for its family's primary
            -- (BM2_ResolveSpellsOwn), so Presets offers no second row for a
            -- buff already assigned. nil on every other client.
            local ap = mod.BM2_ForeverAltPrimary
            local covered = {}
            if ind.filters and mod.BM2_GetFilter then
                for fid in pairs(ind.filters) do
                    local f = mod.BM2_GetFilter(fid)
                    if f then
                        for ident, on in pairs(f.spells) do
                            if on and not mod.BM2_OtherClientSpell(f, ident) then
                                covered[ident] = true
                                if ap and ap[ident] then
                                    covered[ap[ident]] = true
                                end
                            end
                        end
                    end
                end
            end
            local universe = (mod.BM2_AllPresetSpells and mod.BM2_AllPresetSpells()) or {}
            local selected, rest = {}, {}
            local seen = {}
            local sp = ind.spells or {}
            for idx = 1, #sp do
                seen[sp[idx]] = true
                if ap and ap[sp[idx]] then
                    seen[ap[sp[idx]]] = true
                end
                selected[#selected + 1] = SpellEntry(sp[idx])
            end
            for idx = 1, #universe do
                local ident = universe[idx]
                if not seen[ident] and not covered[ident] then
                    rest[#rest + 1] = SpellEntry(ident)
                end
            end
            table.sort(selected, ByLabel)
            table.sort(rest, ByLabel)
            local itemList = { idAction }
            if #selected > 0 then
                itemList[#itemList + 1] = { isHeader = true, label = "Selected" }
                for idx = 1, #selected do
                    itemList[#itemList + 1] = selected[idx]
                end
            end
            itemList[#itemList + 1] = { isHeader = true, label = "Presets" }
            for idx = 1, #rest do
                itemList[#itemList + 1] = rest[idx]
            end
            return itemList
        end
        local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            region,
            190,
            region:GetFrameLevel() + 2,
            ExtraItems,
            HasDirect,
            function(k, val)
                ind.spells = ind.spells or {}
                if val then
                    if not HasDirect(k) then
                        ind.spells[#ind.spells + 1] = k
                    end
                else
                    for idx = #ind.spells, 1, -1 do
                        if ind.spells[idx] == k then
                            table.remove(ind.spells, idx)
                        end
                    end
                    -- The typed mark leaves with the entry: a later pick from
                    -- Presets keeps the curated family.
                    mod.BM2_SetSpellExact(ind, k, false)
                end
                if mod.ReloadFrames then
                    mod.ReloadFrames()
                end
            end,
            nil,
            10,
            true
        )
        CludesUI.PanelPP.Point(cbDD, "RIGHT", region, "RIGHT", -20, 0)
        region._control = cbDD
        region._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- SHOW IN (every type): which frames build the indicator. ind.showIn nil =
    -- raid and party frames, "raid" / "party" = only those. The runtime reads
    -- the button's frame kind, so party frames shown in arenas and small raids
    -- count as party. An anchored indicator follows its Anchor To root (one
    -- run), so the dropdown shows the root's value and is locked.
    local showInCfg = {
        type = "dropdown",
        text = "Show In",
        values = { both = "Raid and Party", raid = "Raid Only", party = "Party Only" },
        order = { "both", "raid", "party" },
        tooltip = "Party frames in arenas and small raids count as Party; Friendly Boss frames count as Raid.",
        disabled = function()
            return ind.anchorTo ~= nil
        end,
        disabledTooltip = "Remove the Anchor To position",
        getValue = function()
            local val = ind.showIn
            if ind.anchorTo ~= nil and mod.BM2_EffectiveShowIn then
                local key = mod._bmSelectedSpecKey
                val = mod.BM2_EffectiveShowIn(ind, key and mod.BM2_SpecInds and mod.BM2_SpecInds(key) or nil)
            end
            return (val == "raid" or val == "party") and val or "both"
        end,
        setValue = function(val)
            if val == "raid" or val == "party" then
                ind.showIn = val
            else
                ind.showIn = nil
            end
            if mod.BM2_Invalidate then
                mod.BM2_Invalidate()
            end
            -- Frames and preview: the preview shows the indicator only on the
            -- side of its Raid / Party switch that renders it.
            if mod._bmReloadAndUpdate then
                mod._bmReloadAndUpdate()
            elseif mod.ReloadFrames then
                mod.ReloadFrames()
            end
        end,
    }

    -- CUSTOM ORDER (icon/square indicators, beside Show In): opt-in fixed
    -- arrangement. The cog's drag list writes ind.spellOrder; the runtime
    -- renders one engine group per arranged spell in that order (BmSegments
    -- in the containers file) instead of the engine's default in-group sorting.
    if ind.type == "icon" or ind.type == "square" then
        -- Default presentation for anything the user has not arranged yet:
        -- the editing spec's own class spells lead, then class-agnostic
        -- (consumables/no hint), then other classes' (externals etc.). The
        -- STORED arrangement is never re-prioritized -- it is the user's.
        local function EditingClassToken()
            local key = mod._bmSelectedSpecKey
            local specs = mod.BM_HEALER_SPECS
            if key and specs then
                for idx = 1, #specs do
                    if specs[idx].key == key then
                        return specs[idx].classToken
                    end
                end
            end
            local _, cls = UnitClass("player")
            return cls
        end
        local function PrioritizeResolved(entries)
            local cls = EditingClassToken()
            local sc = mod.BM2_SpellClass or {}
            local mine, shared, other = {}, {}, {}
            for idx = 1, #entries do
                local ident = entries[idx]
                local c = sc[ident]
                if c == cls then
                    mine[#mine + 1] = ident
                elseif c == nil or c == "ALL" then
                    shared[#shared + 1] = ident
                else
                    other[#other + 1] = ident
                end
            end
            for idx = 1, #shared do
                mine[#mine + 1] = shared[idx]
            end
            for idx = 1, #other do
                mine[#mine + 1] = other[idx]
            end
            return mine
        end
        local orow
        orow, hh = W:DualRow(hostFrame, sy, showInCfg, {
            type = "toggle",
            text = "Custom Order",
            tooltip = "Show this indicator's buffs in the exact order you arrange (the first 10 arranged buffs are guaranteed; any beyond follow the default sorting).",
            getValue = function()
                return ind.customOrder == true
            end,
            setValue = function(val)
                ind.customOrder = val or nil
                if val and not ind.spellOrder then
                    -- Seed the arrangement from the current resolved list so
                    -- the ordered groups engage immediately; the cog only
                    -- rearranges from there.
                    local r = (mod.BM2_ResolveSpells and mod.BM2_ResolveSpells(ind)) or ind.spells or {}
                    ind.spellOrder = PrioritizeResolved(r)
                end
                if mod.ReloadFrames then
                    mod.ReloadFrames()
                end
            end,
        })
        sy = sy - hh
        do
            local region = orow._rightRegion
            -- Effective arrangement: stored order first (stale ids skipped),
            -- then any newly-resolved spells appended in prioritized order.
            -- The cog reads the items again each time its list opens.
            local function OrderItems()
                local resolved = (mod.BM2_ResolveSpells and mod.BM2_ResolveSpells(ind)) or ind.spells or {}
                local present, seen, result = {}, {}, {}
                for idx = 1, #resolved do
                    present[resolved[idx]] = true
                end
                local function Add(ident)
                    local nm = (mod.SPELL_NAME_BY_ID and mod.SPELL_NAME_BY_ID[ident])
                        or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident))
                    result[#result + 1] = { key = ident, label = nm or ("Spell " .. tostring(ident)) }
                end
                local so = ind.spellOrder
                if so then
                    -- WoW Forever: an entry saved under a rank alternate
                    -- stands for its family's primary. nil elsewhere.
                    local ap = mod.BM2_ForeverAltPrimary
                    for idx = 1, #so do
                        local ident = so[idx]
                        if ap then
                            ident = ap[ident] or ident
                        end
                        if present[ident] and not seen[ident] then
                            seen[ident] = true
                            Add(ident)
                        end
                    end
                end
                local rest = {}
                for idx = 1, #resolved do
                    if not seen[resolved[idx]] then
                        rest[#rest + 1] = resolved[idx]
                    end
                end
                rest = PrioritizeResolved(rest)
                for idx = 1, #rest do
                    Add(rest[idx])
                end
                return result
            end
            CludesUI.BuildInlineCog(region, {
                title = "Custom Order",
                rows = {
                    {
                        type = "reorder",
                        label = "Buff Order",
                        hint = "Drag to Reorder",
                        maxVisible = 12,
                        items = OrderItems,
                        set = function(keyList)
                            ind.spellOrder = keyList
                            if mod.ReloadFrames then
                                mod.ReloadFrames()
                            end
                        end,
                        disabled = function()
                            return ind.customOrder ~= true
                        end,
                        disabledTooltip = "Custom Order",
                    },
                },
            })
        end
    else
        _r, hh = W:DualRow(hostFrame, sy, showInCfg, { type = "label", text = "" })
        sy = sy - hh
    end

    return sy
end

-- Indicator detail pane for the v2 BM page.
