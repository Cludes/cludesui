if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_Textures_Options.lua
--
--  Global Settings > Textures: the centralized textures page, built on the
--  same card layout as the Fonts page. Every control is a WRITE-THROUGH
--  MIRROR of a module's own texture row: same DB key, same stored value
--  format, same apply path (including setter side-writes like absorb opacity
--  re-seeds). Selection-bound families (per tracked bar, per data bar,
--  per indicator) and the border-style pickers (whose setters re-seed
--  color/size/offset companions per site) are link rows instead.
--
--  Statusbar dropdown data: AppendSharedMediaTextures registers consumers BY
--  TABLE IDENTITY in a permanent registry, so this file NEVER hands it fresh
--  throwaway tables per build. Where a module publishes its own registered
--  tables (UF/RF/NP ns.healthBarTextures*, RB _G._CURB_Bar*, DM _G._CUDM_Bar*,
--  AB ns.dataBarTextures*, Chat ns.chatBgTextures*, MovementAlert
--  _MovementBarTextures) the mirror re-calls the appender with THOSE tables
--  (identity dedup makes it a sync) and derives fresh display copies, exactly
--  like the module's own options page. Where the registered names/order live
--  in another file's locals (MythicTimer, Dragonriding) the mirror keeps its
--  own memoized triple, registered once per session.
-------------------------------------------------------------------------------

local PAGE_TEXTURES = "Textures"
local GLOBAL_KEY = "_CUIGlobal"

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

-- Session-only card expand state (never saved).
local _txExpanded = {}

local NS = CUI.ModuleNS

-------------------------------------------------------------------------------
--  Statusbar catalogue helpers
-------------------------------------------------------------------------------

-- Own memoized catalogue for sites whose registered tables are unreachable.
-- Built + SM-registered ONCE per session per key; the LibSharedMedia callback
-- keeps the tables current afterwards.
local _ownCat = {}
local function OwnBarCatalogue(key, includeExtras)
    local c = _ownCat[key]
    if not c then
        local texture, nameList, sequence = CUI.BuildBarTextureTables(includeExtras)
        CUI.AppendSharedMediaTextures(nameList, sequence, nil, texture)
        c = { lookup = texture, names = nameList, order = sequence }
        _ownCat[key] = c
    end
    return c
end

-- Fresh per-build display copy of a catalogue (values/order), mirroring the
-- module options pages: values maps key -> display name, order is copied with
-- the site's own separator policy, and _menuOpts paints the texture preview.
local function CopyBarDD(nameList, sequence, lookup, dropSep, bgFn)
    local values, ord = {}, {}
    for _, key in ipairs(sequence or {}) do
        if key == "---" then
            if not dropSep then ord[#ord + 1] = "---" end
        else
            values[key] = (nameList and nameList[key]) or key
            ord[#ord + 1] = key
        end
    end
    values._menuOpts = {
        itemHeight = 28,
        background = bgFn or function(key) return lookup and lookup[key] end,
    }
    return values, ord
end

-- Append the SharedMedia tail of a module's registered order onto hand-built
-- style lists (the absorb-style pattern shared by UF, RF and NP).
local function AppendSmTail(values, orders, moduleNames, moduleOrder)
    local smKeys = {}
    for _, keyName in ipairs(moduleOrder or {}) do
        if type(keyName) == "string" and keyName:find("^sm:") then
            smKeys[#smKeys + 1] = keyName
            values[keyName] = (moduleNames and moduleNames[keyName]) or keyName
        end
    end
    if #smKeys > 0 then
        for _, ord in ipairs(orders) do
            ord[#ord + 1] = "---"
            for _, keyName in ipairs(smKeys) do
                ord[#ord + 1] = keyName
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Shared row helpers (CludesUI_Widgets.lua, shared with the Fonts page)
-------------------------------------------------------------------------------

local BLANK, LinkRow, NoteRow = CUI.BlankRowCfg, CUI.BuildLinkRow, CUI.BuildNoteRow

local function DisabledTile(hostFrame, cursorY, W, tile)
    return NoteRow(
        hostFrame,
        cursorY,
        CUI.Lf("Enable %1$s to edit its texture settings.", CUI.L(tile.display))
    )
end

-- A texture row's Textured Background cog: the module page's own toggle row
-- (rowFn builds it; nil while the module's options are not loaded), greyed while
-- the Blizzard Style of styleKey draws its stock art there instead.
local function AddTexBgCog(region, rowFn, styleKey)
    if CUI._prebuilding then return end
    local row = rowFn()
    if not row then return end
    local blizzOn = styleKey and CUI.BlizzStyle.Active(styleKey) == "blizzard"
    CUI.BuildInlineCog(region, {
        disabled = blizzOn and function() return true end or nil,
        disabledTooltip = blizzOn and CUI.BlizzStyle.Label(styleKey) or nil,
        requireState = blizzOn and "disabled" or nil,
        title = "Texture Settings",
        rows = { row },
    })
end

-------------------------------------------------------------------------------
--  Per-module card content builders
-------------------------------------------------------------------------------

local function TileActionBars(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    local ABAR = mod.EAB
    CUI.AppendSharedMediaTextures(
        mod.dataBarTextureNames or {},
        mod.dataBarTextureOrder or {},
        nil,
        mod.dataBarTextures
    )
    local lookup = mod.dataBarTextures or {}
    -- AB's own preview resolves sm: keys through ResolveTexturePath.
    local values, sequence = CopyBarDD(
        mod.dataBarTextureNames,
        mod.dataBarTextureOrder,
        lookup,
        false,
        function(key)
            if not key or key == "---" or key == "none" then return nil end
            return CUI.ResolveTexturePath(lookup, key, nil)
        end
    )
    local function barTexCfg(labelText, barId)
        return {
            type = "dropdown",
            text = labelText,
            values = values,
            order = sequence,
            getValue = function()
                local barList = ABAR and ABAR.db and ABAR.db.profile and ABAR.db.profile.bars
                local cfg = barList and barList[barId]
                return (cfg and cfg.barTexture) or "none"
            end,
            setValue = function(value)
                local barList = ABAR and ABAR.db and ABAR.db.profile and ABAR.db.profile.bars
                local cfg = barList and barList[barId]
                if not cfg then return end
                cfg.barTexture = value
                if mod.ApplyDataBarLayout then mod.ApplyDataBarLayout(barId) end
            end,
        }
    end
    local _, height = W:DualRow(
        hostFrame,
        cursorY,
        barTexCfg("XP Bar Texture", "XPBar"),
        barTexCfg("Reputation Bar Texture", "RepBar")
    )
    cursorY = cursorY - height
    -- WoW Forever has no House Favor bar: its row is not built there.
    if not CUI.IS_FOREVER then
        _, height = W:DualRow(hostFrame, cursorY, barTexCfg("House Favor Bar Texture", "FavorBar"), BLANK())
        cursorY = cursorY - height
    end -- not IS_FOREVER
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Bar & Button Border Styles",
        tile.folder,
        "Bar Display",
        nil,
        "Border Style"
    )
    return cursorY
end

local function TileNameplates(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    local function saved() return mod.db and mod.db.profile end
    local DEF = mod.defaults or {}
    CUI.AppendSharedMediaTextures(
        mod.healthBarTextureNames or {},
        mod.healthBarTextureOrder or {},
        nil,
        mod.healthBarTextures
    )
    local hbtValues, hbtOrder =
        CopyBarDD(mod.healthBarTextureNames, mod.healthBarTextureOrder, mod.healthBarTextures, false)
    -- Health + cast bar textures repaint live plates the way the module's own
    -- RefreshAllTextures does: full reapply plus the friendly-plate loop.
    local function NPTexApply()
        if mod.RefreshAllSettings then mod.RefreshAllSettings() end
        if mod.friendlyPlates then
            for _, pl in pairs(mod.friendlyPlates) do
                if mod.ApplyHealthBarTexture then mod.ApplyHealthBarTexture(pl) end
                if mod.ApplyCastBarTexture then mod.ApplyCastBarTexture(pl) end
            end
        end
    end
    local function texCfg(labelText, key)
        return {
            type = "dropdown",
            text = labelText,
            values = hbtValues,
            order = hbtOrder,
            getValue = function()
                local profile = saved()
                return (profile and profile[key]) or DEF[key] or "none"
            end,
            setValue = function(value)
                local profile = saved()
                if not profile then return end
                profile[key] = value
                NPTexApply()
            end,
        }
    end

    -- Absorb style: hand list + SM tail, alpha side-write, exactly like the
    -- module row (values/keys shared with the stripe-overlay set).
    local absorbStyleValues = {
        ["blizzard"] = "Blizzard",
        ["striped"] = "Striped",
        ["striped-v2"] = "Stripes",
        ["striped-wide-v2"] = "Wide Stripes",
        ["stripes-medium"] = "Medium Stripes",
        ["stripes-small-close"] = "Small Dense Stripes",
        ["stripes-small-spread"] = "Small Spread Stripes",
        ["striped-tiny"] = "Tiny Stripes",
        ["clean"] = "Clean (Flat)",
        ["pixelsShield"] = "Pixels Shield",
        ["pixelsShieldEdge"] = "Pixels Shield Edge",
        ["pixelsShieldFill"] = "Pixels Shield Fill",
    }
    local absorbStyleOrder = {
        "blizzard",
        "striped",
        "striped-v2",
        "striped-wide-v2",
        "stripes-medium",
        "stripes-small-close",
        "stripes-small-spread",
        "striped-tiny",
        "clean",
        "pixelsShield",
        "pixelsShieldEdge",
        "pixelsShieldFill",
    }
    AppendSmTail(
        absorbStyleValues,
        { absorbStyleOrder },
        mod.healthBarTextureNames,
        mod.healthBarTextureOrder
    )
    absorbStyleValues._menuOpts = {
        itemHeight = 28,
        background = function(key)
            if not key or key == "---" then return nil end
            return (mod.NP_ABSORB_STYLE_TEX and mod.NP_ABSORB_STYLE_TEX[key])
                or (mod.ResolveOverlayTexPath and mod.ResolveOverlayTexPath(key))
        end,
    }

    -- Target/Focus overlay list: stripes first, then the full bar catalogue
    -- (including its "none"); Hover variant leads with "none" and skips the
    -- catalogue's duplicate.
    local STRIPE_ORDER = {
        "striped-v2",
        "striped-wide-v2",
        "stripes-medium",
        "stripes-small-close",
        "stripes-small-spread",
        "striped-tiny",
    }
    local STRIPE_NAMES = {
        ["striped-v2"] = "Stripes",
        ["striped-wide-v2"] = "Wide Stripes",
        ["stripes-medium"] = "Medium Stripes",
        ["stripes-small-close"] = "Small Dense Stripes",
        ["stripes-small-spread"] = "Small Spread Stripes",
        ["striped-tiny"] = "Tiny Stripes",
    }
    local function OverlayBg(key)
        if not key or key == "---" or key == "none" then return nil end
        if mod.OVERLAY_STRIPE_KEYS and mod.OVERLAY_STRIPE_KEYS[key] and mod.ResolveOverlayTexPath then
            return mod.ResolveOverlayTexPath(key)
        end
        return mod.healthBarTextures and mod.healthBarTextures[key]
    end
    local ovtValues, ovtOrder = {}, {}
    for _, keyName in ipairs(STRIPE_ORDER) do
        ovtValues[keyName] = STRIPE_NAMES[keyName]
        ovtOrder[#ovtOrder + 1] = keyName
    end
    ovtOrder[#ovtOrder + 1] = "---"
    for _, keyName in ipairs(hbtOrder) do
        ovtOrder[#ovtOrder + 1] = keyName
        if keyName ~= "---" then ovtValues[keyName] = hbtValues[keyName] end
    end
    ovtValues._menuOpts = { itemHeight = 28, background = OverlayBg }
    local hovValues, hovOrder = {}, {}
    hovValues.none = "None"
    hovOrder[1] = "none"
    hovOrder[2] = "---"
    for _, keyName in ipairs(STRIPE_ORDER) do
        hovValues[keyName] = STRIPE_NAMES[keyName]
        hovOrder[#hovOrder + 1] = keyName
    end
    hovOrder[#hovOrder + 1] = "---"
    for _, keyName in ipairs(hbtOrder) do
        if keyName ~= "none" then
            hovOrder[#hovOrder + 1] = keyName
            if keyName ~= "---" then hovValues[keyName] = hbtValues[keyName] end
        end
    end
    hovValues._menuOpts = { itemHeight = 28, background = OverlayBg }

    local function overlayCfg(labelText, key, applyName)
        return {
            type = "dropdown",
            text = labelText,
            values = (key == "hoverOverlayTexture") and hovValues or ovtValues,
            order = (key == "hoverOverlayTexture") and hovOrder or ovtOrder,
            getValue = function()
                local profile = saved()
                return (profile and profile[key]) or DEF[key]
            end,
            setValue = function(value)
                local profile = saved()
                if not profile then return end
                profile[key] = value
                local func = mod[applyName]
                if func then
                    func()
                elseif mod.RefreshAllSettings then
                    mod.RefreshAllSettings()
                end
            end,
        }
    end

    local _, texRow, height
    texRow, height = W:DualRow(
        hostFrame,
        cursorY,
        texCfg("Bar Texture", "healthBarTexture"),
        texCfg("Cast Bar Texture", "castBarTexture")
    )
    cursorY = cursorY - height
    -- Textured Background cogs.
    local function TexRowCfg(kind)
        return function()
            local environ = mod._NPO_OptEnv
            return environ and environ.TexBgRowCfg(kind, NPTexApply)
        end
    end
    AddTexBgCog(texRow._leftRegion, TexRowCfg("health"), "nameplates")
    AddTexBgCog(texRow._rightRegion, TexRowCfg("cast"), "nameplates")
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Absorb Style",
        values = absorbStyleValues,
        order = absorbStyleOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.absorbStyle) or "blizzard"
        end,
        setValue = function(value)
            local profile = saved()
            if not profile then return end
            profile.absorbStyle = value
            profile.absorbAlpha = math.floor(
                (((mod.NP_ABSORB_STYLE_ALPHA and mod.NP_ABSORB_STYLE_ALPHA[value]) or 0.8) * 100) + 0.5
            )
            if mod.ApplyAbsorbStyleAll then mod.ApplyAbsorbStyleAll() end
        end,
    }, overlayCfg("Hover Texture", "hoverOverlayTexture", "RefreshHoverEffect"))
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        overlayCfg("Target Texture", "targetOverlayTexture", "RefreshAllSettings"),
        overlayCfg("Focus Texture", "focusOverlayTexture", "RefreshAllSettings")
    )
    cursorY = cursorY - height
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Custom Border Style",
        tile.folder,
        "Display",
        "STYLE",
        "Custom Border Style"
    )
    return cursorY
end

local function TileUnitFrames(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    local function saved() return mod.db and mod.db.profile end
    CUI.AppendSharedMediaTextures(
        mod.healthBarTextureNames or {},
        mod.healthBarTextureOrder or {},
        nil,
        mod.healthBarTextures
    )
    -- UF's own dropdown copy drops the separator.
    local hbtValues, hbtOrder =
        CopyBarDD(mod.healthBarTextureNames, mod.healthBarTextureOrder, mod.healthBarTextures, true)

    -- The module's own lists (ns, CUI_UnitFrames_Absorb.lua), copied: the
    -- SharedMedia tail is appended into them.
    local absorbStyleValues = CopyTable(mod.ABSORB_STYLE_NAMES)
    local absorbStyleOrder = CopyTable(mod.ABSORB_STYLE_ORDER)
    local healAbsorbStyleOrder = CopyTable(mod.HEAL_ABSORB_STYLE_ORDER)
    AppendSmTail(
        absorbStyleValues,
        { absorbStyleOrder, healAbsorbStyleOrder },
        mod.healthBarTextureNames,
        mod.healthBarTextureOrder
    )
    absorbStyleValues._menuOpts = {
        itemHeight = 28,
        background = function(key)
            if not key or key == "---" or key == "none" then return nil end
            return mod.ResolveAbsorbStyleTex and mod.ResolveAbsorbStyleTex(key) or nil
        end,
    }

    local UNITS = { "player", "target", "focus" }
    local UNIT_LABEL = { player = "Player", target = "Target", focus = "Focus" }
    local function unitTable(unit)
        local profile = saved()
        return profile and profile[unit]
    end
    local function ReloadUnitFrames()
        if mod.ReloadFrames then mod.ReloadFrames() end
    end
    local function barTexCfg(unit)
        return {
            type = "dropdown",
            text = UNIT_LABEL[unit] .. " Bar Texture",
            values = hbtValues,
            order = hbtOrder,
            getValue = function()
                local ut, p = unitTable(unit), saved()
                return (ut and ut.healthBarTexture) or (p and p.healthBarTexture) or "none"
            end,
            setValue = function(value)
                local ut = unitTable(unit)
                if not ut then return end
                ut.healthBarTexture = value
                ReloadUnitFrames()
            end,
        }
    end
    local function absorbCfg(unit)
        return {
            type = "dropdown",
            text = UNIT_LABEL[unit] .. " Absorb Style",
            values = absorbStyleValues,
            order = absorbStyleOrder,
            getValue = function()
                local ut = unitTable(unit)
                return (ut and ut.showPlayerAbsorb) or "none"
            end,
            setValue = function(value)
                local ut = unitTable(unit)
                if not ut then return end
                ut.absorbOpacity = (value == "clean") and 30 or 90
                ut.showPlayerAbsorb = value
                ReloadUnitFrames()
            end,
        }
    end
    local function healAbsorbCfg(unit)
        return {
            type = "dropdown",
            text = UNIT_LABEL[unit] .. " Heal Absorb Style",
            values = absorbStyleValues,
            order = healAbsorbStyleOrder,
            getValue = function()
                local ut = unitTable(unit)
                return (ut and ut.healAbsorbStyle) or "clean"
            end,
            setValue = function(value)
                local ut = unitTable(unit)
                if not ut then return end
                ut.healAbsorbOpacity = (value == "clean") and 50 or 75
                ut.healAbsorbStyle = value
                ReloadUnitFrames()
            end,
        }
    end
    -- Cast bars follow the unit's bar texture ("Inherit") unless this names
    -- one of their own; "Blizzard" is the vanilla cast bar's fill (the same
    -- entry the Resource Bars cast bar offers), and the stock styles seed it.
    -- Under Blizzard Style the stock fill art draws instead, so the row is
    -- gated there; Classic WoW UI keeps the user's fill, so it stays live.
    local cbtValues, cbtOrder =
        CopyBarDD(mod.healthBarTextureNames, mod.healthBarTextureOrder, mod.healthBarTextures, true)
    cbtValues.inherit, cbtValues.blizzard = "Inherit", "Blizzard"
    table.insert(cbtOrder, 1, "inherit")
    table.insert(cbtOrder, 2, "blizzard")
    local castTexCfg = {
        type = "dropdown",
        text = "Cast Bar Texture",
        values = cbtValues,
        order = cbtOrder,
        tooltip = "Texture for every unit frame cast bar. Inherit follows each unit's bar texture.",
        getValue = function()
            local profile = saved()
            return (profile and profile.castBarTexture) or "inherit"
        end,
        setValue = function(value)
            local profile = saved()
            if not profile then return end
            profile.castBarTexture = value
            ReloadUnitFrames()
        end,
    }
    if CUI.BlizzStyle.Active("unitframes") == "blizzard" then
        CUI.BlizzStyle.Gate("unitframes", castTexCfg)
    end
    local _, focusRow, castRow
    local ptRow, height = W:DualRow(hostFrame, cursorY, barTexCfg("player"), barTexCfg("target"))
    cursorY = cursorY - height
    focusRow, height = W:DualRow(hostFrame, cursorY, barTexCfg("focus"), absorbCfg("player"))
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, absorbCfg("target"), absorbCfg("focus"))
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, healAbsorbCfg("player"), healAbsorbCfg("target"))
    cursorY = cursorY - height
    castRow, height = W:DualRow(hostFrame, cursorY, healAbsorbCfg("focus"), castTexCfg)
    cursorY = cursorY - height
    -- Textured Background cogs (u nil: the cast bars' row).
    local environ = mod._UFO_OptEnv
    local function TexRowCfg(unit)
        return function()
            return environ
                and environ.TexBgRowCfg(unit and function() return unitTable(unit) end, ReloadUnitFrames)
        end
    end
    AddTexBgCog(ptRow._leftRegion, TexRowCfg("player"))
    AddTexBgCog(ptRow._rightRegion, TexRowCfg("target"))
    AddTexBgCog(focusRow._leftRegion, TexRowCfg("focus"))
    AddTexBgCog(castRow._rightRegion, TexRowCfg(), "unitframes")
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Pet, Target-of-Target & Boss Bar Textures",
        tile.folder,
        "Mini Frames",
        "DISPLAY",
        "Bar Texture"
    )
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Frame, Power & Aura Border Styles",
        tile.folder,
        "Main Frames",
        "DISPLAY",
        "Border Style"
    )
    return cursorY
end

local function TileRaidFrames(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    local function saved() return mod.db and mod.db.profile end
    CUI.AppendSharedMediaTextures(
        mod.healthBarTextureNames or {},
        mod.healthBarTextureOrder or {},
        nil,
        mod.healthBarTextures
    )
    -- RF's own copy keeps the separator in the order array.
    local hbtValues, hbtOrder =
        CopyBarDD(mod.healthBarTextureNames, mod.healthBarTextureOrder, mod.healthBarTextures, false)
    local function ReloadRaidFrames()
        if mod.ReloadFrames then mod.ReloadFrames() end
        if mod.ReloadPartyFrames then mod.ReloadPartyFrames() end
    end

    local absorbStyleValues = {
        ["none"] = "None",
        ["striped"] = "Striped",
        ["stripedReversed"] = "Striped Reversed",
        ["stripedThick"] = "Striped Thick",
        ["stripedThickR"] = "Striped Thick Reversed",
        ["clean"] = "Clean (Flat)",
        ["blizzard"] = "Classic WoW",
        ["blizzardModern"] = "Default Blizz Frames",
        ["healBlizzModern"] = "Default Blizz Frames",
        ["largeOutlinedStripes"] = "Large Outlined Stripes",
        ["largeOutlinedStripesR"] = "Large Outlined Stripes R",
        ["largeStripes"] = "Large Stripes",
        ["largeStripesR"] = "Large Stripes R",
        ["maxHealthStripes"] = "Max Health Stripes",
        ["blizzardRaid"] = "Blizzard Raid Bar",
        ["pixelsShield"] = "Pixels Shield",
        ["pixelsShieldEdge"] = "Pixels Shield Edge",
        ["pixelsShieldFill"] = "Pixels Shield Fill",
    }
    local absorbStyleOrder = {
        "none",
        "blizzardModern",
        "striped",
        "stripedReversed",
        "stripedThick",
        "stripedThickR",
        "clean",
        "blizzard",
        "largeStripes",
        "largeStripesR",
        "blizzardRaid",
        "pixelsShield",
        "pixelsShieldEdge",
        "pixelsShieldFill",
    }
    local healAbsorbStyleOrder = {
        "none",
        "healBlizzModern",
        "striped",
        "stripedReversed",
        "stripedThick",
        "stripedThickR",
        "clean",
        "blizzard",
        "largeOutlinedStripes",
        "largeOutlinedStripesR",
        "largeStripes",
        "largeStripesR",
        "blizzardRaid",
        "pixelsShield",
    }
    local maxHealthStyleOrder = {
        "none",
        "maxHealthStripes",
        "striped",
        "stripedReversed",
        "stripedThick",
        "stripedThickR",
        "clean",
        "blizzard",
        "healBlizzModern",
        "largeOutlinedStripes",
        "largeOutlinedStripesR",
        "largeStripes",
        "largeStripesR",
        "blizzardRaid",
        "pixelsShield",
    }
    AppendSmTail(
        absorbStyleValues,
        { absorbStyleOrder, healAbsorbStyleOrder, maxHealthStyleOrder },
        mod.healthBarTextureNames,
        mod.healthBarTextureOrder
    )
    -- Default Blizz Frames' swatch draws its in-game compound (see the Raid & Party Frames page).
    local modernSwatch = { base = { 0.776, 0.784, 1.0 }, tint = { 0.569, 0.588, 1.0 }, tile = true }
    absorbStyleValues._menuOpts = {
        itemHeight = 28,
        background = function(key)
            if not key or key == "---" or key == "none" then return nil end
            if key == "blizzardModern" then
                return mod.ResolveAbsorbStyleTex and mod.ResolveAbsorbStyleTex("striped"), modernSwatch
            end
            if key == "maxHealthStripes" then return CUI.MAX_HEALTH_STRIPES_TEX end
            return mod.ResolveAbsorbStyleTex and mod.ResolveAbsorbStyleTex(key) or nil
        end,
    }

    -- Mirrors write the RAID keys (same as the Raid tab); the Party tab's
    -- unsynced party_ variants stay in the module and are linked below.
    local _, texRow, height
    texRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Health Bar Texture",
        values = hbtValues,
        order = hbtOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.healthBarTexture) or "atrocity"
        end,
        setValue = function(value)
            local profile = saved()
            if not profile then return end
            profile.healthBarTexture = value
            if mod._BumpAbsorbGen then mod._BumpAbsorbGen() end
            ReloadRaidFrames()
        end,
    }, {
        type = "dropdown",
        text = "Absorb Style",
        values = absorbStyleValues,
        order = absorbStyleOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.absorbStyle) or "none"
        end,
        setValue = function(value)
            local profile = saved()
            if not profile then return end
            -- Blizzard Glow Line follows the pick (see the Raid & Party Frames page).
            if value == "blizzardModern" then
                profile.absorbGlowLine = true
            elseif profile.absorbStyle == "blizzardModern" then
                profile.absorbGlowLine = false
            end
            profile.absorbStyle = value
            if value == "clean" then
                profile.absorbOpacity = 30
            elseif value ~= "blizzardModern" then
                profile.absorbOpacity = 90
            end
            ReloadRaidFrames()
        end,
    })
    cursorY = cursorY - height
    -- Textured Background cog: the Raid tab's row on the raid keys, as this card writes.
    local function RaidRead(key, default)
        local profile = saved()
        local value = profile and profile[key]
        if value == nil then return default end
        return value
    end
    local function RaidWrite(key, value)
        local profile = saved()
        if not profile then return end
        profile[key] = value
        if mod._BumpAbsorbGen then mod._BumpAbsorbGen() end
        ReloadRaidFrames()
    end
    AddTexBgCog(texRow._leftRegion, function()
        local environ = mod._RFO_OptEnv
        return environ and environ.TexBgRowCfg(RaidRead, RaidWrite)
    end)
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Heal Absorb Style",
        values = absorbStyleValues,
        order = healAbsorbStyleOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.healAbsorbStyle) or "clean"
        end,
        setValue = function(value)
            local profile = saved()
            if not profile then return end
            profile.healAbsorbStyle = value
            profile.healAbsorbOpacity = (value == "clean") and 50 or 75
            ReloadRaidFrames()
        end,
    }, {
        type = "dropdown",
        text = "Max Health Style",
        values = absorbStyleValues,
        order = maxHealthStyleOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.maxHealthStyle) or "maxHealthStripes"
        end,
        setValue = function(value)
            local profile = saved()
            if not profile then return end
            profile.maxHealthStyle = value
            ReloadRaidFrames()
        end,
    })
    cursorY = cursorY - height
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Party-Specific Textures",
        tile.folder,
        "Party",
        "HEALTH BAR",
        "Health Bar Texture"
    )
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Frame Border Style",
        tile.folder,
        "Frames",
        "FRAME DISPLAY",
        "Border Style"
    )
    return cursorY
end

local function TileCooldownManager(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Tracking Bar Texture & Border (per bar)",
        tile.folder,
        "Tracking Bars",
        "BAR LAYOUT",
        "Bar Texture"
    )
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Icon Border Styles (per bar)",
        tile.folder,
        "CDM Bars",
        "ICON DISPLAY",
        "Border Style"
    )
    return cursorY
end

local function TileResourceBars(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    local function saved() return _G._CURB_AceDB and _G._CURB_AceDB.profile end
    local function ApplyResourceBars()
        if _G._CURB_Apply then _G._CURB_Apply() end
    end
    if CUI.AppendSharedMediaTextures then
        CUI.AppendSharedMediaTextures(
            _G._CURB_BarTextureNames or {},
            _G._CURB_BarTextureOrder or {},
            nil,
            _G._CURB_BarTextures
        )
        CUI.AppendSharedMediaTextures(
            _G._CURB_CastBarTextureNames or {},
            _G._CURB_CastBarTextureOrder or {},
            nil,
            _G._CURB_CastBarTextures
        )
    end
    local barValues, barOrder =
        CopyBarDD(_G._CURB_BarTextureNames, _G._CURB_BarTextureOrder, _G._CURB_BarTextures, false)
    local gcdValues, gcdOrder =
        CopyBarDD(_G._CURB_BarTextureNames, _G._CURB_BarTextureOrder, _G._CURB_BarTextures, false)
    -- Cast bar tables carry the module-side "blizzard" ATLAS entry.
    local castValues, castOrder =
        CopyBarDD(_G._CURB_CastBarTextureNames, _G._CURB_CastBarTextureOrder, _G._CURB_CastBarTextures, false)
    -- Health and power can each take their own texture (the module's Texture cog). While
    -- one does, they get a row here too, Match Main Texture first; the cog drops this
    -- page's cached build when that starts or ends, so reading the flag at build time holds.
    local p0 = saved()
    local split = p0 and p0.splitTex == true
    local barTexRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Bar Texture",
        values = barValues,
        order = barOrder,
        tooltip = split and "Texture for the class resource bar and any bar set to Match Main Texture."
            or "Texture for the health, power and class resource bars.",
        getValue = function()
            local profile = saved()
            return (profile and profile.general and profile.general.barTexture) or "none"
        end,
        setValue = function(value)
            local profile = saved()
            if not (profile and profile.general) then return end
            profile.general.barTexture = value
            ApplyResourceBars()
        end,
    }, {
        type = "dropdown",
        text = "Cast Bar Texture",
        values = castValues,
        order = castOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.castBar and profile.castBar.texture) or "none"
        end,
        setValue = function(value)
            local profile = saved()
            if not (profile and profile.castBar) then return end
            profile.castBar.texture = value
            ApplyResourceBars()
            if CUI.NotifyElementResized then CUI.NotifyElementResized("ERB_CastBar") end
        end,
    })
    cursorY = cursorY - height
    -- Textured Background cogs.
    local environ = mod._CURB_OptEnv
    local function TexRowCfg(kind)
        return function() return environ and environ.TexBgRowCfg(kind, ApplyResourceBars) end
    end
    AddTexBgCog(barTexRow._leftRegion, TexRowCfg("bars"))
    AddTexBgCog(barTexRow._rightRegion, TexRowCfg("cast"), "castbar")
    if split then
        local function BarRow(textValue, barId)
            local value, o =
                CopyBarDD(_G._CURB_BarTextureNames, _G._CURB_BarTextureOrder, _G._CURB_BarTextures, false)
            value.__match = "Match Main Texture"
            table.insert(o, 1, "---")
            table.insert(o, 1, "__match")
            return {
                type = "dropdown",
                text = textValue,
                values = value,
                order = o,
                getValue = function()
                    local profile = saved()
                    return profile and mod.ERB_BarTexture(profile, barId) or "__match"
                end,
                setValue = function(val)
                    local profile = saved()
                    if not profile then return end
                    mod.ERB_SetBarTexture(profile, barId, val ~= "__match" and val)
                    ApplyResourceBars()
                    -- Neither bar has its own texture any more: the row goes.
                    if profile.splitTex ~= true then CUI:RefreshPage(true) end
                end,
            }
        end
        local _
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            BarRow("Health Bar Texture", "health"),
            BarRow("Power Bar Texture", "primary")
        )
        cursorY = cursorY - height
    end
    local gcdTexRow
    gcdTexRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "GCD Bar Texture",
        values = gcdValues,
        order = gcdOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.gcdBar and profile.gcdBar.texture) or "none"
        end,
        setValue = function(value)
            local profile = saved()
            if not (profile and profile.gcdBar) then return end
            profile.gcdBar.texture = value
            ApplyResourceBars()
            if CUI.NotifyElementResized then CUI.NotifyElementResized("ERB_GCDBar") end
        end,
    }, BLANK())
    cursorY = cursorY - height
    AddTexBgCog(gcdTexRow._leftRegion, TexRowCfg("gcd"))
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Border Styles (per bar)",
        tile.folder,
        "Class, Power and Health Bars",
        nil,
        "Border Style"
    )
    return cursorY
end

local function TileChat(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    local CHAT = mod.ECHAT
    local function saved() return _G._CUCHAT_DB and _G._CUCHAT_DB.profile and _G._CUCHAT_DB.profile.chat end
    -- Stock styles (Style page): Blizzard's own chat background, and either
    -- Blizzard's tabs or the painted vanilla tab sheet -- none take a texture,
    -- and the linked border row is hidden there too.
    local BS = CUI.BlizzStyle
    if BS and BS.Get("chat") then
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf(
                "%1$s is active: chat keeps Blizzard's own background and tab art.",
                CUI.L(BS.Label("chat"))
            )
        )
    end
    if CHAT and CHAT.RefreshBgTextureCatalogue then CHAT.RefreshBgTextureCatalogue() end
    -- Chat's own copies drop the separator.
    local btValues, btOrder =
        CopyBarDD(mod.chatBgTextureNames, mod.chatBgTextureOrder, mod.chatBgTextures, true)
    local tabValues, tabOrder =
        CopyBarDD(mod.chatBgTextureNames, mod.chatBgTextureOrder, mod.chatBgTextures, true)
    local _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Background Texture",
        values = btValues,
        order = btOrder,
        tooltip = "Texture drawn over the chat background color.",
        getValue = function()
            local profile = saved()
            return (profile and profile.bgTexture) or "none"
        end,
        setValue = function(value)
            local profile = saved()
            if not profile then return end
            profile.bgTexture = value
            if CHAT and CHAT.ApplyBackground then CHAT.ApplyBackground() end
        end,
    }, {
        type = "dropdown",
        text = "Tab Texture",
        values = tabValues,
        order = tabOrder,
        tooltip = "Texture drawn over the tab background colors.",
        getValue = function()
            local profile = saved()
            return (profile and profile.tabBackgroundTexture) or "none"
        end,
        setValue = function(value)
            local profile = saved()
            if not profile then return end
            profile.tabBackgroundTexture = value
            if CHAT and CHAT.ApplyTabAppearance then CHAT.ApplyTabAppearance() end
        end,
    })
    cursorY = cursorY - height
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Panel & Tab Border Styles",
        tile.folder,
        "Chat",
        "DISPLAY",
        "Border Style"
    )
    return cursorY
end

local function TileQoL(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    -- Movement alert bar texture: module-owned registered tables.
    local mt = CUI._MovementBarTextures
    local maCfg
    if mt then
        CUI.AppendSharedMediaTextures(mt.names, mt.order, nil, mt.lookup)
        local values, sequence = CopyBarDD(mt.names, mt.order, mt.lookup, false)
        maCfg = {
            type = "dropdown",
            text = "Movement Alert Bar Texture",
            values = values,
            order = sequence,
            tooltip = "Used by the movement alert's Bar display mode.",
            getValue = function()
                local db = _G._CUI_MovementAlert_DB and _G._CUI_MovementAlert_DB()
                local ma = db and db.profile and db.profile.movementAlert
                return (ma and ma.barTexture) or "none"
            end,
            setValue = function(value)
                local db = _G._CUI_MovementAlert_DB and _G._CUI_MovementAlert_DB()
                local ma = db and db.profile and db.profile.movementAlert
                if not ma then return end
                ma.barTexture = value
                if CUI._applyMovementAlert then CUI._applyMovementAlert() end
                if CUI._applyTimeSpiral then CUI._applyTimeSpiral() end
                if CUI._applyGateway then CUI._applyGateway() end
            end,
        }
    end

    -- Cursor art pickers: bespoke ring art, hand-built lists mirroring the
    -- Cursor page exactly (note the ring_ prefix difference between the
    -- cursor texture and the two ring pickers).
    local function cursorDB() return _G._CUCL_AceDB and _G._CUCL_AceDB.profile end
    local cursorCfg = {
        type = "dropdown",
        text = "Cursor Texture",
        values = {
            ring_normal = "Ring Normal",
            ring_light = "Ring Light",
            custom = "Cludes Logo",
            ring_thin = "Ring Thin",
            ring_heavy = "Ring Heavy",
            ring_thick = "Ring Thick",
        },
        order = { "ring_normal", "ring_light", "custom", "---", "ring_thin", "ring_heavy", "ring_thick" },
        getValue = function()
            local profile = cursorDB()
            return (profile and profile.texture) or "ring_normal"
        end,
        setValue = function(value)
            local profile = cursorDB()
            if not profile then return end
            profile.texture = value
            if _G._CUCL_Apply then _G._CUCL_Apply() end
        end,
    }
    local ringValues = {
        normal = "Ring Normal",
        light = "Ring Light",
        thin = "Ring Thin",
        heavy = "Ring Heavy",
        thick = "Ring Thick",
    }
    local ringOrder = { "normal", "light", "---", "thin", "heavy", "thick" }
    local gcdRingCfg = {
        type = "dropdown",
        text = "GCD Ring Texture",
        values = ringValues,
        order = ringOrder,
        getValue = function()
            local profile = cursorDB()
            local g = profile and profile.gcd
            return (g and g.ringTex) or "light"
        end,
        setValue = function(value)
            local profile = cursorDB()
            local g = profile and profile.gcd
            if not g then return end
            g.ringTex = value
            if _G._CUCL_ApplyGCDCircle then _G._CUCL_ApplyGCDCircle() end
            if _G._CUCL_RegisterUnlock then _G._CUCL_RegisterUnlock() end
        end,
    }
    local castRingCfg = {
        type = "dropdown",
        text = "Cast Ring Texture",
        values = ringValues,
        order = ringOrder,
        getValue = function()
            local profile = cursorDB()
            local c = profile and profile.castCircle
            return (c and c.ringTex) or "normal"
        end,
        setValue = function(value)
            local profile = cursorDB()
            local c = profile and profile.castCircle
            if not c then return end
            c.ringTex = value
            if _G._CUCL_ApplyCastCircle then _G._CUCL_ApplyCastCircle() end
            if _G._CUCL_RegisterUnlock then _G._CUCL_RegisterUnlock() end
        end,
    }

    local _, height = W:DualRow(hostFrame, cursorY, maCfg or BLANK(), cursorCfg)
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, gcdRingCfg, castRingCfg)
    cursorY = cursorY - height
    return cursorY
end

local function TileMythicTimer(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    local function saved() return _G._CUMT_AceDB and _G._CUMT_AceDB.profile end
    local function MTApply()
        if _G._CUMT_ApplyTimer then _G._CUMT_ApplyTimer() end
    end
    -- MT's registered tables live in module/options locals; own memoized
    -- core-set catalogue (registered once), separator dropped like MT's own.
    local category = OwnBarCatalogue("mt", nil)
    local values, sequence = CopyBarDD(category.names, category.order, category.lookup, true)
    local function texCfg(labelText, key)
        return {
            type = "dropdown",
            text = labelText,
            values = values,
            order = sequence,
            getValue = function()
                local profile = saved()
                return (profile and profile[key]) or "none"
            end,
            setValue = function(value)
                local profile = saved()
                if not profile then return end
                profile[key] = value
                MTApply()
            end,
        }
    end
    local function subTexCfg(labelText, getT, applyName)
        return {
            type = "dropdown",
            text = labelText,
            values = values,
            order = sequence,
            getValue = function()
                local tbl = getT()
                return (tbl and tbl.texture) or "none"
            end,
            setValue = function(value)
                local tbl = getT()
                if not tbl then return end
                tbl.texture = value
                local func = mod[applyName]
                if func then
                    func()
                else
                    MTApply()
                end
            end,
        }
    end
    local function tsb()
        local profile = saved()
        return profile and profile.tsb
    end
    local function tfbT()
        local profile = saved()
        return profile and profile.tfb and profile.tfb.target
    end
    local function tfbF()
        local profile = saved()
        return profile and profile.tfb and profile.tfb.focus
    end
    local function kt()
        local profile = saved()
        return profile and profile.kickTracker
    end
    local _, height = W:DualRow(
        hostFrame,
        cursorY,
        texCfg("Timer Bar Texture", "barTexture"),
        texCfg("Timer Background Texture", "barBgTexture")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        texCfg("Forces Bar Texture", "enemyBarTexture"),
        texCfg("Forces Background Texture", "enemyBarBgTexture")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        subTexCfg("Cast Bars Texture", tsb, "TSB_Refresh"),
        subTexCfg("Target Cast Bar Texture", tfbT, "TFB_Refresh")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        subTexCfg("Focus Cast Bar Texture", tfbF, "TFB_Refresh"),
        subTexCfg("Kick Tracker Bar Texture", kt, "KT_Refresh")
    )
    cursorY = cursorY - height
    return cursorY
end

local function TileDamageMeters(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    local function saved() return _G._CUDM_DB and _G._CUDM_DB.profile and _G._CUDM_DB.profile.dm end
    CUI.AppendSharedMediaTextures(
        _G._CUDM_BarTextureNames or {},
        _G._CUDM_BarTextureOrder or {},
        nil,
        _G._CUDM_BarTextures
    )
    -- DM keeps the separator in its order arrays.
    local dmValues, dmOrder =
        CopyBarDD(_G._CUDM_BarTextureNames, _G._CUDM_BarTextureOrder, _G._CUDM_BarTextures, false)
    -- "Match" variant used by the breakdown + spell history rows.
    local matchValues, matchOrder =
        CopyBarDD(_G._CUDM_BarTextureNames, _G._CUDM_BarTextureOrder, _G._CUDM_BarTextures, false)
    matchValues.match = "Match Damage Meters"
    table.insert(matchOrder, 1, "---")
    table.insert(matchOrder, 1, "match")
    local _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Bar Texture",
        values = dmValues,
        order = dmOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.barTexture) or "none"
        end,
        setValue = function(value)
            local profile = saved()
            if not profile then return end
            profile.barTexture = value
            if mod.RefreshMeter then mod.RefreshMeter() end
            if mod.ApplySpellHistory then mod.ApplySpellHistory() end
        end,
    }, {
        type = "dropdown",
        text = "Breakdown Bar Texture",
        values = matchValues,
        order = matchOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.breakdownBarTexture) or "match"
        end,
        setValue = function(value)
            local profile = saved()
            if not profile then return end
            profile.breakdownBarTexture = value
            if mod.RefreshMeter then mod.RefreshMeter() end
        end,
    })
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Spell History Bar Texture",
        values = matchValues,
        order = matchOrder,
        getValue = function()
            local profile = saved()
            local sh = profile and profile.spellHistory
            return (sh and sh.spellHistoryBarTexture) or "match"
        end,
        setValue = function(value)
            local profile = saved()
            if not profile then return end
            if not profile.spellHistory then profile.spellHistory = {} end
            profile.spellHistory.spellHistoryBarTexture = value
            if mod.ApplySpellHistory then mod.ApplySpellHistory() end
        end,
    }, BLANK())
    cursorY = cursorY - height
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Window & Bar Border Styles",
        tile.folder,
        "Damage Meters",
        nil,
        "Border Style"
    )
    return cursorY
end

local function TileDataBars(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Bar Texture (per data bar)",
        tile.folder,
        "Info Bar",
        "BAR SETTINGS",
        "Bar Texture"
    )
    return cursorY
end

local function TileBlizzardSkin(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    local category = OwnBarCatalogue("edr", nil)
    local values, sequence = CopyBarDD(category.names, category.order, category.lookup, true)
    local _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Dragonriding Bar Texture",
        values = values,
        order = sequence,
        getValue = function()
            local p = mod.edrDB and mod.edrDB.profile
            return (p and p.barTexture) or "none"
        end,
        setValue = function(value)
            local p = mod.edrDB and mod.edrDB.profile
            if not p then return end
            p.barTexture = value
            if mod.edrRedraw then mod.edrRedraw() end
        end,
    }, BLANK())
    cursorY = cursorY - height
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Popup & Tooltip Border Styles",
        tile.folder,
        "Tooltips, Menus & Popups",
        nil,
        "Border Style"
    )
    return cursorY
end

local function TileMinimap(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    if not mod then return DisabledTile(hostFrame, cursorY, W, tile) end
    cursorY =
        LinkRow(hostFrame, cursorY, "Minimap Border Style", tile.folder, "Minimap", "DISPLAY", "Border Style")
    return cursorY
end

-------------------------------------------------------------------------------
--  Card list -- roster order, modules with texture settings only
-------------------------------------------------------------------------------

local TILE_BUILDERS = {
    CludesUIActionBars = { TileActionBars, "XP, reputation and favor bar textures" },
    CludesUINameplates = { TileNameplates, "Health, cast, absorb and highlight textures" },
    CludesUIUnitFrames = { TileUnitFrames, "Bar and absorb textures for the main frames" },
    CludesUIRaidFrames = { TileRaidFrames, "Health bar and absorb textures" },
    CludesUICooldownManager = { TileCooldownManager, "Tracking bar textures and icon borders" },
    CludesUIResourceBars = { TileResourceBars, "Resource, cast and GCD bar textures" },
    CludesUIQoL = { TileQoL, "Movement alert bar and cursor ring art" },
    CludesUIBlizzardSkin = { TileBlizzardSkin, "Dragonriding speed bar texture" },
    CludesUIMythicTimer = { TileMythicTimer, "Timer, forces and spell bar textures" },
    CludesUIMinimap = { TileMinimap, "Minimap border style" },
    CludesUIChat = { TileChat, "Chat background and tab textures" },
    CludesUIDamageMeters = { TileDamageMeters, "Meter, breakdown and history bar textures" },
    CludesUIDataBars = { TileDataBars, "Per-bar background textures" },
}

local function BuildTileList()
    local tiles = {}
    local roster = CUI.ADDON_ROSTER or {}
    for _, record in ipairs(roster) do
        local def = not record.comingSoon and TILE_BUILDERS[record.folder]
        if def then
            tiles[#tiles + 1] = {
                key = record.folder,
                folder = record.folder,
                display = record.display,
                desc = def[2],
                buildContent = def[1],
            }
        end
    end
    return tiles
end

-------------------------------------------------------------------------------
--  Texture card (same chrome as the Fonts card; chevron-only header with a
--  small statusbar-strip glyph -- there is no per-module texture override
--  system, so the header hosts no dropdown)
-------------------------------------------------------------------------------

local TX_GLYPH_TEX = "Interface\\AddOns\\CludesUI\\media\\textures\\melli.tga"

local function BuildTexCard(hostFrame, cursorY, W, tile)
    return CUI.BuildModuleCard(hostFrame, cursorY, W, tile, {
        enabled = NS(tile.folder) ~= nil,
        expanded = _txExpanded,
        descW = 560,
        -- Mini statusbar glyph: a texture strip in a thin frame.
        glyph = function(heading, enabled)
            local Pix = CUI.PanelPP
            local ACC = CUI.CLUDES_GREEN
            local icon = CreateFrame("Frame", nil, heading)
            Pix.Size(icon, 26, 12)
            Pix.Point(icon, "LEFT", heading, "LEFT", 14, 0)
            CUI.MakeBorder(icon, 1, 1, 1, 0.3, Pix)
            local glyphTex = icon:CreateTexture(nil, "ARTWORK")
            glyphTex:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
            glyphTex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
            glyphTex:SetTexture(TX_GLYPH_TEX)
            if enabled then
                glyphTex:SetVertexColor(ACC.r, ACC.g, ACC.b, 0.8)
            else
                glyphTex:SetVertexColor(1, 1, 1, 0.15)
            end
        end,
    })
end

-------------------------------------------------------------------------------
--  Deep-link pre-hook: expand every card before a jump into the Textures page
-------------------------------------------------------------------------------
do
    local origNav = CUI.NavigateToElementSettings
    function CUI:NavigateToElementSettings(moduleName, page, sectionName, preSelectFn, highlightText)
        -- The original refuses in combat: no page state changes then.
        if InCombatLockdown() then
            return origNav(self, moduleName, page, sectionName, preSelectFn, highlightText)
        end
        if moduleName == GLOBAL_KEY and page == PAGE_TEXTURES and (sectionName or highlightText) then
            local changed = false
            for _, tile in ipairs(BuildTileList()) do
                if not _txExpanded[tile.key] then
                    _txExpanded[tile.key] = true
                    changed = true
                end
            end
            if changed and CUI.InvalidatePageCache then CUI:InvalidatePageCache() end
        end
        return origNav(self, moduleName, page, sectionName, preSelectFn, highlightText)
    end
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------

function _G._CUI_BuildTexturesPage(page, hostFrame, yOffset)
    local W = CUI.Widgets
    local Pix = CUI.PanelPP
    local cursorY = yOffset
    local _, height

    hostFrame._showRowDivider = true

    -- Orientation note above the section title: everything on this page is a
    -- write-through mirror, not a separate setting. Sized host + single
    -- TOPLEFT point per the search framework's geometry contract (raw
    -- parent-level regions are invisible to the search and float over
    -- filtered results).
    local introHost = CreateFrame("Frame", nil, hostFrame)
    Pix.Size(introHost, hostFrame:GetWidth() - CUI.CONTENT_PAD * 2, 44)
    -- 10px breathing room above; the host's slack below is trimmed the same
    -- amount so the section title sits tighter under the text.
    introHost:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", CUI.CONTENT_PAD, cursorY - 20)
    local intro = CUI.MakeFont(introHost, 14, nil, 1, 1, 1, 0.65)
    intro:SetPoint("TOPLEFT", introHost, "TOPLEFT", 0, -2)
    intro:SetPoint("TOPRIGHT", introHost, "TOPRIGHT", 0, -2)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText(
        CUI.L("A quick view of every texture setting in one place.")
            .. "\n"
            .. CUI.L("These are the same settings found on each module's own pages, not separate ones.")
    )
    cursorY = cursorY - 48

    _, height = W:SectionHeader(hostFrame, "MODULE TEXTURES", cursorY)
    cursorY = cursorY - height

    for _, tile in ipairs(BuildTileList()) do
        cursorY = BuildTexCard(hostFrame, cursorY, W, tile)
    end

    -- Framework contract: return the positive total content height.
    return math.abs(cursorY)
end
