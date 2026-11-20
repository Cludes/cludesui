if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_StockStyles.lua
--
--  Stock styles (Global Settings > Style): the Blizzard, Classic and WoW
--  Forever art kits and the post-pass that lays them over the built frames.
--  Loads after the main file and reads it through ns and ns._internals;
--  db is set through I.dbSetters when CludesUF:OnInitialize creates the DB.
-------------------------------------------------------------------------------
local _, mod = ...

local issecretvalue = issecretvalue
local Pix = CludesUI.PP

local Inner = mod._internals
local frameList, GetSettingsForUnit, UnsnapTex = Inner.frames, Inner.GetSettingsForUnit, Inner.UnsnapTex
local CastbarUnlockKey, CreatePowerBar, ApplyFramePosition =
    Inner.CastbarUnlockKey, Inner.CreatePowerBar, Inner.ApplyFramePosition
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-------------------------------------------------------------------------------
--  Stock styles (Global Settings > Style). A stock unit frame look on our own
--  frames: the frame art, portrait masks, bar shapes and bar placement of one
--  ART KIT, applied as an idempotent post-pass over the built CUI frame so
--  every CUI feature (text zones, auras, absorbs, cast bars, class power,
--  unlock movers) keeps working; only the CUI-look settings step aside. The
--  pass runs after every geometry re-apply (UpdateBordersForScale, the class
--  power re-anchor, the ReloadFrames sweep), creates its regions once per
--  frame, and costs nothing while the style is off. Two kits share the pass:
--  ns.UF_KITS.blizzard (Blizzard Style: the current stock atlases, rounded
--  masks and bevels) and ns.UF_KITS.classic (Classic WoW UI: the vanilla
--  frame files, plain rectangular bars). ns.UF_BLIZZ is the ACTIVE kit,
--  pointed at the latched style once per session (ns.UF_Style). An art entry
--  is an atlas name (validated once per session; a missing one leaves that
--  piece on the CUI look) or a file descriptor { key, file, l, r, t, b, w,
--  h, point, x, y }. Reload-gated per-profile flags. ns fields only:
--  written under the main file's local cap.
-------------------------------------------------------------------------------
mod.UF_BLIZZ = {
    player = {
        w = 232,
        h = 100,
        hit = { 6, 0, 4, 9 },
        side = "left",
        -- Insets from the stock box to the visible art (the 198x71 atlas is
        -- centred in the box; measured from its alpha): what auras, anchors and
        -- the unlock mover line up with.
        vis = { l = 20, r = 18, t = 16.5, b = 15.5 },
        -- Transparent rows above / below the visible art (the options preview
        -- trims them; the live frame keeps the stock box for its hit rect).
        -- Same rows as vis, so the preview and the live alignment agree.
        pad = { top = 16.5, bottom = 15.5 },
        art = "UI-HUD-UnitFrame-Player-PortraitOn",
        -- The player mask squares off the lower-right corner (under the bars);
        -- rawArt = the client's own round crop is switched off so it shows.
        portrait = {
            point = "TOPLEFT",
            x = 24,
            y = -19,
            size = 60,
            mask = "UI-HUD-UnitFrame-Player-Portrait-Mask",
            rawArt = true,
        },
        health = {
            x = 85,
            y = 40,
            w = 124,
            h = 20,
            atlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
            mask = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask",
            mx = -2,
            my = 6,
        },
        power = {
            x = 85,
            y = 61,
            w = 124,
            h = 10,
            prefix = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-",
            mask = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask",
            mx = -2,
            my = 2,
        },
        name = { point = "TOPLEFT", x = 88, y = -27, w = 96 },
        -- Level number in the art's level circle (right end of the name bar).
        level = { point = "TOPRIGHT", x = -24.5, y = -28, justify = "RIGHT" },
    },
    target = {
        w = 232,
        h = 100,
        hit = { 0, 5, 4, 9 },
        side = "right",
        vis = { l = 20, r = 21, t = 17.5, b = 17.5 },
        pad = { top = 17.5, bottom = 17.5 },
        art = "UI-HUD-UnitFrame-Target-PortraitOn",
        artRare = "UI-HUD-UnitFrame-Target-Rare-PortraitOn",
        portrait = { point = "TOPRIGHT", x = -26, y = -19, size = 58, mask = "CircleMask" },
        health = {
            x = 23,
            y = 40,
            w = 126,
            h = 20,
            atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health",
            mask = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask",
            mx = -1,
            my = 6,
        },
        power = {
            x = 23,
            y = 61,
            w = 134,
            h = 10,
            prefix = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-",
            mask = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana-Mask",
            mx = -61,
            my = 3,
        },
        -- Hide Power Bar's health bar (UF_MergedHealth): the power track runs
        -- further right under the ring than the health track, so the taller
        -- bar takes the power track's width and a mask of both stock openings
        -- joined (.tools/stock-merged-mask), 1 texel per unit.
        mergedHealth = {
            x = 23,
            y = 40,
            w = 134,
            h = 31,
            maskFile = "Interface\\AddOns\\CludesUIUnitFrames\\Media\\blizz-target-merged-mask.tga",
            mx = 0,
            my = 0,
            mw = 256,
            mh = 32,
        },
        rep = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Type", x = -75, y = -25 },
        -- Level number on the type strip: the stock frame puts it in the
        -- circle at the strip's LEFT end (-133,-2 off the strip's top-right),
        -- but every frame keeps its level on the RIGHT here (user ruling), so
        -- it sits right-aligned where the name ends, just before the portrait
        -- ring, and the name gives up that much width (nameTrim).
        level = { point = "TOPRIGHT", x = -91, y = -27, justify = "RIGHT", nameTrim = 26 },
        name = { point = "TOPLEFT", x = 30, y = -26, w = 120 },
        boss = {
            gold = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold",
            silver = "ui-hud-unitframe-target-portraiton-boss-rare-silver",
            winged = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged",
        },
    },
    mini = {
        w = 120,
        h = 49,
        hit = { 0, 0, 0, 0 },
        side = "left",
        small = true,
        vis = { l = 2, r = 1, t = 3, b = 1 },
        art = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn",
        portrait = { point = "TOPLEFT", x = 5, y = -5, size = 37, mask = "CircleMask" },
        health = {
            x = 44,
            y = 17,
            w = 70,
            h = 10,
            atlas = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Health",
            mask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask",
            mx = -29,
            my = 3,
        },
        power = {
            x = 40,
            y = 28,
            w = 74,
            h = 7,
            prefix = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-",
            mask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana-Mask",
            mx = -27,
            my = 4,
        },
        name = { point = "TOPLEFT", x = 44, y = -5, w = 68 },
    },
}
mod.UF_CAST_BLIZZ = {
    bg = { "ui-castingbar-background", "UI-CastingBar-Background" },
    frame = { "ui-castingbar-frame", "UI-CastingBar-Frame" },
    textbox = { "ui-castingbar-textbox", "UI-CastingBar-TextBox" },
    cast = { "ui-castingbar-filling-standard", "UI-CastingBar-Fill" },
    channel = { "ui-castingbar-filling-channel", "UI-CastingBar-Fill" },
}
-- Classic WoW UI: the vanilla frames. The 256x128 frame sheet is drawn as
-- the 230x99 region the stock frame samples (x 26..256, y 1..100), which
-- also holds the elite, rare and boss variants' dragons; the player frame
-- samples it flipped so its portrait ring sits on the left. Bars are plain
-- rectangles in the art's transparent tracks (no masks, no bevel), the
-- portrait a plain round crop. Every art draws OVER the bars: its tracks are
-- windows in opaque art whose rim overlaps the fills' edges, which is the
-- look; a fill drawn over the art covers that rim. Sizes at 1x.
mod.UF_CLASSIC_SHEET = "Interface\\TargetingFrame\\UI-TargetingFrame"
mod.UF_KITS = {}
mod.UF_KITS.blizzard = mod.UF_BLIZZ
mod.UF_KITS.classic = {
    noBevel = true,
    skull = { key = "c-skull", file = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", w = 16, h = 16 },
    -- The vanilla cast bar frame: the shared nine-slice in
    -- CludesUI_ClassicArt.lua round the bar (caps and rims at the sheet's
    -- own pixel size, only the window stretching); `frame` is the file the
    -- presence probe checks before it is drawn.
    cast = {
        frame = { key = "c-castframe", file = "Interface\\CastingBar\\UI-CastingBar-Border" },
    },
    player = {
        w = 232,
        h = 100,
        hit = { 21, 19, 12, 15 },
        side = "left",
        artAbove = true,
        vis = { l = 19.5, r = 19.5, t = 11.5, b = 11.5 },
        pad = { top = 11.5, bottom = 11.5 },
        art = {
            key = "c-player",
            file = mod.UF_CLASSIC_SHEET,
            l = 1,
            r = 0.1015625,
            t = 0.0078125,
            b = 0.78125,
            w = 230,
            h = 99,
            x = -18.5,
            y = -4,
        },
        -- The dark plaque behind the name and both bars.
        back = { x = 89.5, y = 26, w = 119, h = 41 },
        portrait = { point = "TOPLEFT", x = 24, y = -16, size = 64, mask = "CircleMask" },
        health = { x = 90, y = 45, w = 119, h = 12 },
        power = { x = 90, y = 56, w = 119, h = 12 },
        -- Hide Power Bar (UF_PaintArtCut): the divider between the health and
        -- power windows is the sheet's rows 50..55, between the clear rows
        -- 45..49 and 56..61. The band runs from row 48 (a clear row) to the
        -- bottom rim at 62; across the windows and their left rim (the sheet's
        -- columns before 147) it takes the health window's clear rows 46..47,
        -- stretched, so the shadow by the portrait ring keeps the health
        -- window's width down to the rim (the power window's is narrower, and
        -- the boss sheet's holds an ornament). From 147 the right rim and the
        -- portrait ring's edge slant with the rows, so they keep their own.
        -- The target's elite, rare, rare-elite and boss sheets share this layout.
        merge = { t = 48 / 128, b = 62 / 128, src = 46 / 128, srcB = 48 / 128, x = 147 / 256 },
        name = { point = "CENTER", x = 34, y = 15, w = 100, justify = "CENTER" },
        -- Level number in the ring under the portrait. The ring is an oval
        -- in the sheet (28 wide, 24 tall) centred 35.6 from the frame's left
        -- and 31.4 up from its bottom, measured on the client's own render;
        -- the box sits half a unit right and under that so the digits' ink,
        -- which rides a little above and left of its box's middle, lands
        -- on the ring's middle.
        level = { point = "CENTER", relPoint = "BOTTOMLEFT", x = 36, y = 30.5, justify = "CENTER" },
    },
    target = {
        w = 232,
        h = 100,
        hit = { 19, 21, 12, 15 },
        side = "right",
        artAbove = true,
        vis = { l = 19.5, r = 19.5, t = 11.5, b = 11.5 },
        pad = { top = 11.5, bottom = 11.5 },
        art = {
            key = "c-target",
            file = mod.UF_CLASSIC_SHEET,
            l = 0.1015625,
            r = 1,
            t = 0.0078125,
            b = 0.78125,
            w = 230,
            h = 99,
            x = 18.5,
            y = -4,
        },
        -- Whole-frame variants by classification (the dragon is part of the art).
        artByClass = {
            elite = {
                key = "c-elite",
                file = mod.UF_CLASSIC_SHEET .. "-Elite",
                l = 0.1015625,
                r = 1,
                t = 0.0078125,
                b = 0.78125,
                w = 230,
                h = 99,
                x = 18.5,
                y = -4,
            },
            rareelite = {
                key = "c-rareelite",
                file = mod.UF_CLASSIC_SHEET .. "-Rare-Elite",
                l = 0.1015625,
                r = 1,
                t = 0.0078125,
                b = 0.78125,
                w = 230,
                h = 99,
                x = 18.5,
                y = -4,
            },
            rare = {
                key = "c-rare",
                file = mod.UF_CLASSIC_SHEET .. "-Rare",
                l = 0.1015625,
                r = 1,
                t = 0.0078125,
                b = 0.78125,
                w = 230,
                h = 99,
                x = 18.5,
                y = -4,
            },
            boss = {
                key = "c-boss",
                file = "Interface\\TargetingFrame\\UI-UnitFrame-Boss",
                l = 0.1015625,
                r = 1,
                t = 0.0078125,
                b = 0.78125,
                w = 230,
                h = 99,
                x = 18.5,
                y = -4,
            },
        },
        back = { x = 23.5, y = 26, w = 119, h = 41 },
        portrait = { point = "TOPRIGHT", x = -24, y = -16, size = 64, mask = "CircleMask" },
        health = { x = 23, y = 45, w = 119, h = 12 },
        power = { x = 23, y = 56, w = 119, h = 12 },
        merge = { t = 48 / 128, b = 62 / 128, src = 46 / 128, srcB = 48 / 128, x = 147 / 256 },
        -- The name plaque behind the name, tinted by the unit's selection
        -- colour, under the art (the art's name window shows it).
        rep = {
            art = {
                key = "c-namebg",
                file = "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground",
                w = 119,
                h = 19,
            },
            point = "TOPRIGHT",
            x = -90,
            y = -26,
            below = true,
        },
        name = { point = "CENTER", x = -34, y = 15, w = 100, justify = "CENTER" },
        -- The player ring's measured centre, mirrored.
        level = { point = "CENTER", relPoint = "BOTTOMRIGHT", x = -36, y = 30.5, justify = "CENTER" },
    },
    -- Target-of-target / focus-target.
    mini = {
        w = 93,
        h = 45,
        hit = { 0, 0, 0, 0 },
        side = "left",
        small = true,
        artAbove = true,
        vis = { l = 2, r = 1, t = 3, b = 1 },
        art = {
            key = "c-tot",
            file = "Interface\\TargetingFrame\\UI-TargetofTargetFrame",
            l = 0.015625,
            r = 0.7265625,
            t = 0,
            b = 0.703125,
            w = 93,
            h = 45,
        },
        back = { x = 42, y = 17, w = 46, h = 15 },
        portrait = { point = "TOPLEFT", x = 6, y = -6, size = 35, mask = "CircleMask" },
        health = { x = 45, y = 15, w = 46, h = 7 },
        power = { x = 45, y = 23, w = 46, h = 7 },
        name = { point = "TOPLEFT", x = 42, y = -33, w = 49, justify = "LEFT" },
    },
    pet = {
        w = 128,
        h = 53,
        hit = { 7, 10, 6, 7 },
        side = "left",
        small = true,
        artAbove = true,
        vis = { l = 2, r = 1, t = 3, b = 1 },
        art = {
            key = "c-pet",
            file = "Interface\\TargetingFrame\\UI-SmallTargetingFrame",
            w = 128,
            h = 64,
            point = "TOPLEFT",
            x = 0,
            y = -2,
        },
        portrait = { point = "TOPLEFT", x = 7, y = -6, size = 37, mask = "CircleMask" },
        health = { x = 47, y = 22, w = 69, h = 8 },
        power = { x = 47, y = 29, w = 69, h = 8 },
        name = { point = "TOPLEFT", x = 50, y = -9, w = 70, justify = "LEFT" },
    },
}
-- Hide Power Bar on the stock atlas art (Blizzard Style, WoW Forever): that
-- art draws under the bars, but a health fill or background that is not
-- fully opaque shows the groove between its health and power tracks through
-- the taller bar, so the art goes on cut as the classic sheet does
-- (UF_PaintArtCut). Keyed by the file the client draws for the atlas, 1x and
-- 2x (the WoW Forever look draws its own player and target art, and the
-- retail sheet for the rare target), then by atlas name. In the atlas's 1x
-- pixels (w x h; the 2x art scales with it): rows t..b-1 -- the groove plus
-- the soft shadow the 2x art draws round it -- take the track rows from src
-- instead, on the bars' side of column x; the portrait ring's side (left of
-- x when ringLeft) keeps its own rows. Every row next to a piece's edge is
-- plain track, so a scaled draw that samples one row past an edge never
-- picks up the groove.
do
    local retail = {
        ["UI-HUD-UnitFrame-Player-PortraitOn"] = {
            w = 198,
            h = 71,
            t = 44,
            b = 51,
            src = 36,
            x = 68,
            ringLeft = true,
        },
        ["UI-HUD-UnitFrame-Target-PortraitOn"] = { w = 192, h = 67, t = 41, b = 49, src = 33, x = 126 },
        ["UI-HUD-UnitFrame-Target-Rare-PortraitOn"] = { w = 192, h = 67, t = 41, b = 49, src = 33, x = 126 },
    }
    local forever = {
        ["UI-HUD-UnitFrame-Player-PortraitOn"] = {
            w = 198,
            h = 71,
            t = 44,
            b = 50,
            src = 38,
            x = 69,
            ringLeft = true,
        },
        ["UI-HUD-UnitFrame-Target-PortraitOn"] = { w = 194, h = 68, t = 41, b = 47, src = 34, x = 127 },
    }
    mod.UF_ATLAS_MERGE = { [4631591] = retail, [4642466] = retail, [8036204] = forever, [8036209] = forever }
end
-- WoW Forever (a Blizzard Style variant, Forever client only): the stock kit,
-- whose atlas names the client already paints with its Forever art, plus the
-- Forever layout -- the bars in the Forever art's tracks, the names centred
-- on their strips, the level in a round badge at the frame's bottom corner
-- (the target's skull centred in it, the target name widened into the strip
-- the level left), the PvP crest below the portrait, Forever's dragon
-- offsets and the silver-winged dragon on rares too. The badge hangs below
-- the art, so the visible bottom edge (auras, cast bar, mover) is the
-- badge's. Built once, when the variant latches.
function mod.UF_ForeverKit()
    local k = mod.UF_KITS.forever
    if k then
        return k
    end
    k = CopyTable(mod.UF_KITS.blizzard)
    local circle = "UI-HUD-UnitFrame-SmallCircle"
    local P, T, M = k.player, k.target, k.mini
    -- Every bar fills its track up to the bright bronze rim on all four
    -- sides (the art's dark inner line and bevel covered): the bar takes the
    -- rect inside the rim, and its mask is stretched so the mask's opening
    -- (cols l..r, rows t..b of its mw x mh file) covers exactly that rect.
    -- The player art is centred half a unit down the box, so its rows fall
    -- on halves.
    local function Fit(barFrame, posX, posY, wid, hgt, l, region, t, b, mw, mh)
        local kx, ky = wid / (region - l + 1), hgt / (b - t + 1)
        barFrame.x, barFrame.y, barFrame.w, barFrame.h = posX, posY, wid, hgt
        barFrame.mx, barFrame.my = -l * kx, t * ky
        barFrame.mw, barFrame.mh = mw * kx, mh * ky
    end
    Fit(P.health, 88, 45.5, 123, 15, 4, 123, 9, 21, 128, 32)
    Fit(P.power, 88, 61.5, 123, 10, 4, 123, 4, 11, 128, 16)
    P.name = { point = "CENTER", x = 33, y = 13, w = 116, justify = "CENTER" }
    P.badge = { point = "BOTTOMLEFT", x = 13, y = 7, size = 39, atlas = circle }
    P.level = { point = "CENTER", x = 0, y = -0.5, justify = "CENTER", skullDy = 0.5 }
    P.pvp = { point = "TOP", relPoint = "TOPLEFT", x = 22, y = -65, scale = 0.8 }
    P.vis.b, P.pad.bottom = 7, 7
    Fit(T.health, 22, 44, 123, 15, 4, 123, 10, 22, 128, 32)
    Fit(T.power, 22, 60, 123, 10, 68, 187, 4, 11, 256, 16)
    -- Both Forever target bars end alike: Hide Power Bar's stretched health
    -- mask fits, not the retail art's joined one.
    T.mergedHealth = nil
    T.rep.x, T.rep.y = -82, -26
    T.badge = { point = "BOTTOMRIGHT", x = -13, y = 7, size = 39, atlas = circle }
    T.level = { point = "CENTER", x = 0, y = -0.5, justify = "CENTER", skullDy = 0.5 }
    T.name = { point = "TOPLEFT", x = 24, y = -30, w = 117, justify = "CENTER" }
    T.pvp = { point = "TOP", relPoint = "TOPRIGHT", x = -24, y = -65, scale = 0.8 }
    T.vis.t, T.pad.top = 17, 17
    T.vis.b, T.pad.bottom = 7, 7
    -- The small masks' names can still draw the retail files (the Forever
    -- health file is left out of the client's Forever atlas set), whose
    -- openings sit elsewhere, so each mask fits by the file that draws.
    local hm = C_Texture.GetAtlasInfo(M.health.mask)
    if hm and hm.file == 4737301 then
        Fit(M.health, 45, 18, 70, 11, 29, 98, 3, 12, 128, 16)
    else
        Fit(M.health, 45, 18, 70, 11, 26, 96, 4, 12, 128, 16)
    end
    local pm = C_Texture.GetAtlasInfo(M.power.mask)
    if pm and pm.file == 4737298 then
        Fit(M.power, 45, 30, 70, 7, 28, 100, 4, 10, 128, 16)
    else
        Fit(M.power, 45, 30, 70, 7, 29, 98, 4, 10, 128, 16)
    end
    M.name = { point = "TOPLEFT", x = 44, y = -6, w = 68, justify = "CENTER" }
    -- The Forever small art ends above the box's bottom (its ring's lowest row).
    M.vis = { l = 2, r = 2, t = 2, b = 5 }
    T.boss.silver = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged"
    T.boss.silverRare = true
    T.boss.pos = { winged = { 11, -4 }, silver = { 8, -7 }, gold = { 0, 1 } }
    mod.UF_KITS.forever = k
    return k
end
mod._ufAtlasMemo = {}
-- The style this module renders: "cui", "blizzard" or "classic". Read from
-- the profile once (first call with a profile present) and latched for the
-- session, pointing ns.UF_BLIZZ at the kit: a live profile switch never flips
-- the look under the one-time art setup; the profile system prompts for a
-- reload instead. The Classic flag wins when both flags are set.
function mod.UF_Style()
    local val = mod._ufStyle
    if val == nil then
        local p = saved and saved.profile
        if not p then
            return "cui"
        end
        val = (p.useClassicStyle and "classic") or (p.useBlizzardStyle and "blizzard") or "cui"
        mod._ufStyle = val
        -- The WoW Forever variant of Blizzard Style, latched with it: the
        -- Forever client, Blizzard Style, and the sibling useForeverStyle
        -- flag set together with the Blizzard one.
        mod._ufForever = val == "blizzard" and CludesUI.IS_FOREVER == true and p.useForeverStyle == true
        if val == "classic" then
            mod.UF_BLIZZ = mod.UF_KITS.classic
        end
        if mod._ufForever then
            mod.UF_BLIZZ = mod.UF_ForeverKit()
        end
    end
    return val
end
-- Stock-art mode: a kit dictates the geometry (true for both stock styles).
function mod.UF_Blizz()
    return mod.UF_Style() ~= "cui"
end
-- WoW Forever variant: UF_Style() still reads "blizzard" (every stock site
-- stays as it is); this gates the Forever-only pieces. False off Forever.
function mod.UF_Forever()
    if mod._ufStyle == nil then
        mod.UF_Style()
    end
    return mod._ufForever == true
end
-- The class resource style that builds. WoW Forever outside its own style
-- has no Blizzard class resource bar to adopt, so a saved "blizzard" builds
-- as modern there. Read-side only: the saved style is never rewritten.
-- nil on every other client (readers test the field).
if CludesUI.IS_FOREVER == true then
    -- Rogues under the CludesUI look keep a class resource style of their
    -- own, hidden until picked, so a rogue's choice
    -- and the other classes' player.classPowerStyle never overwrite each
    -- other on a shared profile. The key to write, or nil when the shared one
    -- applies.
    function mod.UF_RogueCPKey()
        if mod.UF_Blizz() then
            return nil
        end
        local _, class = UnitClass("player")
        if class ~= "ROGUE" then
            return nil
        end
        return "foreverRogueClassPowerStyle"
    end
    -- The player's built style: for a rogue it replaces the argument with the
    -- rogue's own saved style, so call it for the player frame only.
    function mod.UF_ForeverCPStyle(style)
        local rogueKey = mod.UF_RogueCPKey()
        if rogueKey then
            local p = saved and saved.profile and saved.profile.player
            style = (p and p[rogueKey]) or "none"
        end
        if style == "blizzard" and not mod.UF_Forever() then
            return "modern"
        end
        return style
    end
end
-- A custom frame border Color Custom Borders can copy (the player's Dispel
-- Overlay cog): a Border Style other than Solid with a size, under the
-- CludesUI style. Read from the saved keys, like the options gate, so a
-- saved true stands down under a stock style or a Solid border.
function mod.UF_CustomBorderOn(cfg)
    if mod.UF_Blizz() then
        return false
    end
    local texture = cfg and cfg.borderTexture
    if texture == nil or texture == "" or texture == "solid" then
        return false
    end
    return (cfg.borderSize or 1) > 0
end
-- Blizzard Style's coloured type strip over the target-family name ("Blizz
-- Colored Target Header", on unless the unit's settings turn it off, which
-- leaves the header uncoloured like the player frame's). Classic keeps its
-- name plaque either way.
function mod.UF_BlizzHeaderOn(cfg)
    return not (mod.UF_Style() == "blizzard" and cfg and cfg.blizzColoredHeader == false)
end
-- Hide Power Bar (blizzHidePower, a main frame's own setting under a stock
-- style): no power bar, the health bar taking the power track too. Unset, a
-- saved Bar Position of None reads as hidden, as it drew no bar there before.
function mod.UF_StockHidesPower(cfg)
    if not cfg then
        return false
    end
    local val = cfg.blizzHidePower
    if val == nil then
        return cfg.powerPosition == "none"
    end
    return val == true
end
-- The main frames (player, target, focus), known by their settings tables.
function mod.UF_IsMainSettings(s)
    local p = s and saved and saved.profile
    return p ~= nil and (s == p.player or s == p.target or s == p.focus)
end
-- The power bar position a frame is laid out with. Under a stock style a
-- main frame's bar sits in the stock track below the health bar whatever
-- its Bar Position says, or is not drawn while Hide Power Bar is on; every
-- other frame, and every frame under the CludesUI look, reads its own.
function mod.UF_PowerPos(cfg)
    if not cfg then
        return "below"
    end
    if mod.UF_Blizz() and mod.UF_IsMainSettings(cfg) then
        return mod.UF_StockHidesPower(cfg) and "none" or "below"
    end
    return cfg.powerPosition or "below"
end
-- Hide Power Bar's health bar: the kit's health bar grown down to the power
-- bar's bottom, its mask stretched with it so the mask's opening still covers
-- the whole bar (the opening's rows map onto the taller bar, the columns
-- stay). A mask the kit seats at its own size (no mw / mh) scales that size
-- by sy (UF_SeatBarMask). Built once per kit geometry. A kit whose two tracks
-- end apart gives its own (G.mergedHealth: the retail target art).
mod._ufMergedMemo = setmetatable({}, { __mode = "k" })
function mod.UF_MergedHealth(G)
    if G.mergedHealth then
        return G.mergedHealth
    end
    local m = mod._ufMergedMemo[G]
    if m then
        return m
    end
    local H, P = G.health, G.power
    local k = (P.y + P.h - H.y) / H.h
    m = {}
    for key, val in pairs(H) do
        m[key] = val
    end
    m.h = H.h * k
    if H.my then
        m.my = H.my * k
    end
    if H.mh then
        m.mh = H.mh * k
    elseif H.mask then
        m.sy = k
    end
    mod._ufMergedMemo[G] = m
    return m
end
-- The stock-style seeds on the profile `p` for `styleKey` ("blizzard" |
-- "classic"). Once per profile: the "Blizzard" cast fill (the vanilla cast
-- bar's own texture) as the cast bar texture, and under Classic the Plating
-- health bar texture on every frame (per-frame choices cleared so they
-- inherit it). Once per style switch: the
-- player frame's combat indicator on the portrait, in the style's own icon
-- (the Classic icon under Classic WoW UI, the Dungeoneer icon under
-- Blizzard Style), so each stock look starts with its matching indicator
-- while a later choice stands until the style changes again. Run by the
-- Style page on the switch and at enable for a profile that arrived already
-- switched (an import, an older build).
mod.UF_STOCK_COMBAT = { classic = "combat2", blizzard = "combat1" }
-- Frames whose own bar texture key overrides (or inherits) the global one.
mod.UF_TEXTURE_UNITS = { "player", "target", "focus", "pet", "targettarget", "focustarget", "boss" }
-- The keys the Style page keeps per style for this module (its SLOT_KEYS).
function mod.UF_StyleSlotKeys()
    local k = {
        "castBarTexture",
        "healthBarTexture",
        "player.combatIndicatorStyle",
        "player.combatIndicatorPosition",
    }
    local units = mod.UF_TEXTURE_UNITS
    for index = 1, #units do
        k[#k + 1] = units[index] .. ".healthBarTexture"
    end
    return k
end
-- The WoW Forever variant's own seed: its combo point arc (the "Blizzard"
-- class resource there), once per profile. The Style page keeps these keys
-- in a Forever-only slot (p._foreverStyleSlots): the other looks' values are
-- banked on the way into the variant and come back on the way out.
function mod.UF_SeedForever(profile)
    if not (profile and profile.player) or profile.foreverClassPowerSeeded then
        return
    end
    profile.foreverClassPowerSeeded = true
    profile.player.classPowerStyle = "blizzard"
    profile.player.showClassPowerBar = true
end
-- `isForever`: the WoW Forever variant of Blizzard Style, which also runs
-- its own seed (UF_SeedForever).
function mod.UF_SeedStock(profile, styleKey, isForever)
    if not profile then
        return
    end
    if isForever then
        mod.UF_SeedForever(profile)
    end
    if not profile.stockCastTextureSeeded then
        profile.stockCastTextureSeeded = true
        profile.castBarTexture = "blizzard"
    end
    -- Classic WoW UI: "Plating" as the bar texture, once per profile (the
    -- controls stay the user's afterwards): the global key, with each frame's
    -- own override cleared so every frame (and its power bar) follows it.
    if styleKey == "classic" and not profile.classicTextureSeeded then
        profile.classicTextureSeeded = true
        profile.healthBarTexture = "plating"
        local units = mod.UF_TEXTURE_UNITS
        for index = 1, #units do
            local cfg = profile[units[index]]
            if type(cfg) == "table" then
                cfg.healthBarTexture = nil
            end
        end
    end
    local iconTex = mod.UF_STOCK_COMBAT[styleKey]
    if iconTex and profile.player and profile.stockCombatSeededStyle ~= styleKey then
        profile.stockCombatSeededStyle = styleKey
        profile.player.combatIndicatorStyle = iconTex
        profile.player.combatIndicatorPosition = "portrait"
    end
end
function mod.UF_AtlasOK(name)
    if not name then
        return false
    end
    local memo = mod._ufAtlasMemo
    local val = memo[name]
    if val == nil then
        val = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) and true or false
        memo[name] = val
    end
    return val
end
-- Art entries: an atlas name or a file descriptor (see the header). A file
-- is probed once through the client's path table (memo on the descriptor),
-- so a file this client does not ship leaves its piece on the fallback art
-- instead of painting blank.
function mod.UF_ArtOK(a)
    if type(a) == "table" then
        if not a.file then
            return false
        end
        local success = a._ok
        if success == nil then
            success = true
            if GetFileIDFromPath then
                success = GetFileIDFromPath(a.file) and true or false
            end
            a._ok = success
        end
        return success
    end
    return mod.UF_AtlasOK(a)
end
function mod.UF_ArtName(a)
    if type(a) == "table" then
        return a.key or a.file or ""
    end
    return a or ""
end
-- Kit atlas paints in place of tex:SetAtlas / C_Texture.GetAtlasInfo: the
-- stock looks draw the retail art on the Forever client (the shared stock
-- atlas helper), the WoW Forever look keeps the client's own frame art (the
-- cast bar background skips this: a bar texture, retail under the WoW
-- Forever look too).
-- Plain textures only (never a mask or a StatusBar fill).
function mod.UF_StockAtlas(texture, name, ...)
    if mod.UF_Forever() then
        return texture:SetAtlas(name, ...)
    end
    return CludesUI.StockAtlas(texture, name, ...)
end
function mod.UF_StockAtlasInfo(name)
    if mod.UF_Forever() then
        return C_Texture.GetAtlasInfo(name)
    end
    return CludesUI.StockAtlasInfo(name)
end
-- Bar and portrait masks the same way: the stock looks take the retail
-- masks on the Forever client (it redrew them under the retail names), the
-- WoW Forever look the client's own.
function mod.UF_StockMask(maskTex, name, useSize)
    if mod.UF_Forever() then
        return maskTex:SetAtlas(name, useSize)
    end
    return CludesUI.StockMask(maskTex, name, useSize)
end
-- A kit bar's mask on `bar`: the stock mask at its own size, or at the size
-- the kit stretches it to (mw x mh), hung from the bar's top-left. B.maskFile:
-- a mask file of ours instead of the stock atlas.
function mod.UF_SeatBarMask(maskTex, barFrame, B)
    if B.maskFile then
        maskTex:SetTexture(B.maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    else
        mod.UF_StockMask(maskTex, B.mask, true)
    end
    if B.mw then
        maskTex:SetSize(B.mw, B.mh)
    elseif B.sy then
        -- Hide Power Bar's taller health bar: the mask's own size, stretched down.
        local wid, hgt = maskTex:GetSize()
        maskTex:SetSize(wid, hgt * B.sy)
    end
    maskTex:ClearAllPoints()
    maskTex:SetPoint("TOPLEFT", barFrame, "TOPLEFT", B.mx, B.my)
end
-- Paints an art entry on a texture; useSize takes the entry's own size.
function mod.UF_SetArt(texture, a, useSize)
    if type(a) == "table" then
        if not mod.UF_ArtOK(a) then
            return false
        end
        texture:SetTexture(a.file)
        texture:SetTexCoord(a.l or 0, a.r or 1, a.t or 0, a.b or 1)
        if useSize and a.w and a.h then
            texture:SetSize(a.w, a.h)
        end
        return true
    end
    if not mod.UF_AtlasOK(a) then
        return false
    end
    mod.UF_StockAtlas(texture, a, useSize)
    return true
end
-- The classic cast frame round a horizontal cast bar `bar`: the shared
-- nine-slice (CludesUI.ClassicFrame) whose pieces ride `tex`'s parent on
-- its layer, created once; `tex` is the callers' handle and draws nothing.
-- `pct` is the unit's Border Size percentage (nil = the shared default).
-- Idempotent (the seat memoizes on the rect and scale).
function mod.UF_SeatClassicCastFrame(texture, barFrame, hgt, pct)
    local CK = mod.UF_BLIZZ.cast
    local CF = CludesUI.ClassicFrame
    if not (texture and barFrame and CK and CF) then
        return
    end
    if not mod.UF_ArtOK(CK.frame) then
        texture:Hide()
        return
    end
    local p = texture._classicPieces
    if not p then
        local layer, sub = texture:GetDrawLayer()
        p = CF.Create(texture:GetParent(), layer, sub)
        texture._classicPieces = p
        texture:Hide()
    end
    CF.Seat(p, barFrame, CF.ScaleK(pct), false)
end
-- First existing atlas of a candidate list (nil when none is available).
function mod.UF_BlizzAtlas(entries)
    for index = 1, #entries do
        if mod.UF_AtlasOK(entries[index]) then
            return entries[index]
        end
    end
    return nil
end
-- Frame kind: the player art, the target/focus/boss art, the pet art where
-- the kit has one, or the small target-of-target / focus-target art.
function mod.UF_BlizzKind(unitToken)
    if not unitToken then
        return nil
    end
    if unitToken == "player" then
        return "player"
    end
    if unitToken == "target" or unitToken == "focus" or unitToken:match("^boss%d$") then
        return "target"
    end
    if unitToken == "pet" and mod.UF_BLIZZ.pet then
        return "pet"
    end
    return "mini"
end
-- Portrait Side keeps working. Each art is drawn for one side (G.side). A
-- full frame set to the other side takes the stock layout drawn for that
-- side instead (player art for a left portrait, target art for a right one),
-- so its art, bars, masks and portrait are all native pieces. The small
-- frames have a single art, so the other side renders it mirrored: anchors
-- flip left/right with x negated and the art flips; their bar masks cannot
-- flip (MaskTextures ignore texcoords), so mirrored small bars run unmasked.
-- Resolved by the layout pass and stamped on the frame for the art helpers.
function mod.UF_BlizzResolve(widget, unitToken)
    unitToken = unitToken or widget._cuiBaseUnit or widget._cuiUnit
    local kind = mod.UF_BlizzKind(unitToken)
    if not kind then
        return nil
    end
    local native = mod.UF_BLIZZ[kind]
    local edgeSide = mod.UF_BlizzSide(GetSettingsForUnit(unitToken), native)
    local G, mirror = native, false
    if native.small then
        mirror = edgeSide ~= native.side
    elseif edgeSide == "right" then
        G = mod.UF_BLIZZ.target
    else
        G = mod.UF_BLIZZ.player
    end
    widget._blizzGeom = G
    widget._blizzMirror = mirror or nil
    -- The type strip, elite dragon and rare frame belong to the target family
    -- on its own art only.
    widget._blizzExtras = (G.rep and kind == "target") or nil
    return G, mirror
end
function mod.UF_BlizzGeom(widget)
    if not widget then
        return nil
    end
    return widget._blizzGeom or mod.UF_BlizzResolve(widget)
end
-- Visible art edges under the style: the frame is the stock box, whose art is
-- centred inside it with transparent padding round the visible frame (about
-- 20px each side and 16px above/below on the full frames). Returns the insets
-- from the box edges to the visible art -- left, right, top, bottom, in the
-- frame's units -- or nil while the style is off. A mirrored small frame
-- swaps left and right with its art.
function mod.UF_BlizzVis(widget)
    if not widget or not mod.UF_Blizz() then
        return nil
    end
    local G = mod.UF_BlizzGeom(widget)
    local val = G and G.vis
    if not val then
        return nil
    end
    if widget._blizzMirror then
        return val.r, val.l, val.t, val.b
    end
    return val.l, val.r, val.t, val.b
end
-- The aura block: an invisible frame spanning the stock box's width from the
-- visible art's bottom edge down to the bottom of the frame's lowest
-- bottom-anchored aura stack (the aura containers re-point it through
-- ns.UF_BlizzAuraBlockBottom; see AnchorContainer in
-- CUI_UnitFrames_AuraContainers). A cast bar linked under the frame anchors
-- to it (the follow provider below), so it hangs below the auras the way the
-- stock spell bar does and rides the rows engine-side: an engine aura
-- container's geometry is a secret value under aura restriction, so the
-- stack's extent can only ever be followed by anchoring, never read. The
-- block is the box's width so its centre is the frame's centre, which the
-- anchor math works from. Created once per frame, only under the style.
-- An engine aura container refuses any dependent that would silently inherit
-- its layout aspect ("Anchoring disallowed as dependent object would inherit
-- forbidden aspects: UntrustedLayoutScriptExecution"): a frame may anchor to
-- it only when it already carries that aspect, which Blizzard's opt-in
-- template stamps at creation (Blizzard_SharedXMLBase/ForbiddenAspectTemplates
-- .xml; the stock target spell bar takes the same aspect before anchoring to
-- its aura container). The aspect only stops the frame's own OnSizeChanged
-- scripts, which nothing on the block or the cast bar uses. Verified once on
-- a probe: a client without the template (or one that ignores it) keeps the
-- block on the resting bottom and never anchors to a container.
mod.UF_LAYOUT_ASPECT_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"
function mod.UF_LayoutAspectOK()
    local val = mod._ufLayoutAspectOK
    if val == nil then
        val = false
        local success, probe = pcall(CreateFrame, "Frame", nil, UIParent, mod.UF_LAYOUT_ASPECT_TEMPLATE)
        if success and probe then
            local wanted = Enum
                and Enum.ForbiddenAspect
                and Enum.ForbiddenAspect.UntrustedLayoutScriptExecution
            local maskTex = probe.GetForbiddenAspects and probe:GetForbiddenAspects()
            if wanted and type(maskTex) == "number" and bit.band(maskTex, wanted) ~= 0 then
                val = true
            end
            probe:Hide()
        end
        mod._ufLayoutAspectOK = val
    end
    return val
end
-- The template a unit's cast bar holder is created with under the style, so
-- it can hang off the aura block (nil = a plain frame: off-style, boss frames,
-- or a client without the aspect).
function mod.UF_CastbarAspectTemplate(unitToken)
    if mod.UF_Blizz() and CastbarUnlockKey(unitToken) and mod.UF_LayoutAspectOK() then
        return mod.UF_LAYOUT_ASPECT_TEMPLATE
    end
    return nil
end
function mod.UF_BlizzAuraBlock(widget)
    local blk = widget and widget._blizzAuraBlock
    if blk then
        return blk
    end
    if not mod.UF_BlizzVis(widget) then
        return nil
    end
    if mod.UF_LayoutAspectOK() then
        blk = CreateFrame("Frame", nil, widget, mod.UF_LAYOUT_ASPECT_TEMPLATE)
    else
        blk = CreateFrame("Frame", nil, widget)
    end
    blk:EnableMouse(false)
    widget._blizzAuraBlock = blk
    mod.UF_BlizzAuraBlockBottom(widget, nil)
    return blk
end
-- Re-point the block's bottom edge: `rel` nil = the visible art's bottom
-- (nothing stacked below); else the container's BOTTOMLEFT/BOTTOMRIGHT corner
-- (`relPoint`), x shifted by `x` so the corner lands on the box's own edge --
-- the top corners already pin left and right, and a bottom corner that
-- agrees with them keeps the rect from being over-constrained.
function mod.UF_BlizzAuraBlockBottom(widget, rel, relPoint, posX)
    local blk = widget and widget._blizzAuraBlock
    if not blk then
        return
    end
    local _, _, _, b = mod.UF_BlizzVis(widget)
    b = b or 0
    blk:ClearAllPoints()
    blk:SetPoint("TOPLEFT", widget, "BOTTOMLEFT", 0, b)
    blk:SetPoint("TOPRIGHT", widget, "BOTTOMRIGHT", 0, b)
    -- A refused container anchor (the probe passed but this container still
    -- denies it) must not abort the aura pass: fall back to the resting bottom.
    if
        rel
        and mod.UF_LayoutAspectOK()
        and pcall(blk.SetPoint, blk, relPoint, rel, relPoint, posX or 0, 0)
    then
        return
    end
    blk:SetPoint("BOTTOM", widget, "BOTTOM", 0, b)
end
-- Anchor-target edges for the unlock anchor system under the style: the
-- visible art's edges rather than the stock box. Static insets only -- the
-- aura stack below is never read (see the block). Chained in front of any
-- provider installed before this file loaded (ns fields, like the rest of
-- this file).
mod._ufPrevAnchorExtent = CludesUI._GetAnchorTargetExtent
mod._ufAnchorKeys = {
    player = true,
    target = true,
    focus = true,
    pet = true,
    targettarget = true,
    focustarget = true,
    boss = true,
}
CludesUI._GetAnchorTargetExtent = function(targetKey, edgeSide)
    if mod._ufAnchorKeys[targetKey] and mod.UF_Blizz() then
        local frame = (targetKey == "boss") and frameList.boss1 or frameList[targetKey]
        local l, region, t, b = mod.UF_BlizzVis(frame)
        if l and frame:GetLeft() then
            local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if edgeSide == "LEFT" then
                return (frame:GetLeft() + l) * ratio
            elseif edgeSide == "RIGHT" then
                return (frame:GetRight() - region) * ratio
            elseif edgeSide == "TOP" then
                return (frame:GetTop() - t) * ratio
            elseif edgeSide == "BOTTOM" then
                return (frame:GetBottom() + b) * ratio
            end
        end
    end
    local previous = mod._ufPrevAnchorExtent
    if previous then
        return previous(targetKey, edgeSide)
    end
    return nil
end
-- Follow provider for the unlock anchor system: a unit's own cast bar linked
-- to the BOTTOM of its frame anchors to the frame's aura block instead of an
-- absolute position (its offsets stay edge-to-edge from the visible art's
-- bottom, the block's resting edge), so it rides the aura stack engine-side.
mod._ufPrevAnchorFollow = CludesUI._GetAnchorFollowFrame
CludesUI._GetAnchorFollowFrame = function(childKey, targetKey, edgeSide)
    -- Inert in unlock mode: a bar on the block reports a SECRET rect (the
    -- container's geometry is secret-wrapped), which the movers must read, so
    -- the bar sits at its resting spot there and re-attaches on the exit
    -- re-apply (the same posture as the tracking bar extent provider).
    if
        edgeSide == "BOTTOM"
        and mod.UF_Blizz()
        and not CludesUI._unlockActive
        and childKey == CastbarUnlockKey(targetKey)
    then
        -- Only a holder created with the layout aspect may hang off the block.
        local frame = frameList[targetKey]
        local holderFrame = frame and frame.Castbar and frame.Castbar:GetParent()
        if holderFrame and holderFrame._blizzAspect then
            return mod.UF_BlizzAuraBlock(frame)
        end
    end
    local previous = mod._ufPrevAnchorFollow
    if previous then
        return previous(childKey, targetKey, edgeSide)
    end
    return nil
end

-- Saved positions are UIParent offsets, but a frame reads anchor offsets in
-- its own scale: a frame scaled by Frame Scale (Blizzard Style, where the
-- stock size is fixed) divides them back down so it lands where it was
-- saved. Identity at scale 1, which is every frame outside the style.
function mod.UF_ScaledOffsets(fr, posX, posY)
    local s = fr and fr:GetScale() or 1
    if s ~= 1 and s > 0 and posX and posY then
        return posX / s, posY / s
    end
    return posX, posY
end

-- Boss frames' Vertical Spacing: the top-to-top step between boss 2..5 and
-- the one before. Stack Direction alone sets the sign, so a negative value
-- saved while the slider allowed one stacks the same way as its positive.
function mod.UF_BossSpacing()
    return math.abs(saved.profile.bossSpacing or 80)
end

mod._ufMirrorPoint = {
    TOPLEFT = "TOPRIGHT",
    TOPRIGHT = "TOPLEFT",
    LEFT = "RIGHT",
    RIGHT = "LEFT",
    BOTTOMLEFT = "BOTTOMRIGHT",
    BOTTOMRIGHT = "BOTTOMLEFT",
}
function mod.UF_BlizzPoint(regionFrame, anchorPoint, rel, relPoint, posX, posY, mirror)
    if mirror then
        anchorPoint = mod._ufMirrorPoint[anchorPoint] or anchorPoint
        relPoint = mod._ufMirrorPoint[relPoint] or relPoint
        posX = -posX
    end
    regionFrame:SetPoint(anchorPoint, rel, relPoint, posX, posY)
end
-- Flipped art is drawn straight from the atlas's sheet with the sheet coords
-- reversed (SetTexCoord on an atlas-mode texture does not address the sheet,
-- so SetAtlas + SetTexCoord samples the wrong region); see UF_PaintBlizzArt.
-- The side the portrait renders on: the frame's Portrait Side setting (the
-- inside variants map to their side), else the art's own side.
function mod.UF_BlizzSide(prefs, G)
    local edgeSide = prefs and prefs.portraitSide
    if edgeSide == "insideleft" then
        edgeSide = "left"
    elseif edgeSide == "insideright" then
        edgeSide = "right"
    end
    if edgeSide ~= "left" and edgeSide ~= "right" then
        edgeSide = G.side
    end
    return edgeSide
end

-- Re-seat a mask on a fill (AddMaskTexture is additive, so drop first).
function mod.UF_SetMask(texture, maskTex)
    if not texture or not maskTex then
        return
    end
    pcall(texture.RemoveMaskTexture, texture, maskTex)
    texture:AddMaskTexture(maskTex)
end
-- Health + power bars: the user's own Bar Texture stays on the fills (the
-- stock fill art is pre-coloured and would darken every chosen colour), so
-- colours, gradients, opacity and textures render exactly as on the CUI
-- look; the stock rounded masks shape the fills AND the CUI bar backgrounds,
-- so Bar Background keeps working inside the stock track. Masks are
-- (re)seated after every texture swap (a swap replaces the fill object), so
-- a re-apply can never leave a bar unmasked.
function mod.UF_ApplyBlizzBarArt(widget)
    local G = mod.UF_BlizzGeom(widget)
    if not G then
        return
    end
    local mirror = widget._blizzMirror
    local healthBar = widget.Health
    if healthBar then
        -- Hide Power Bar: the taller bar and its stretched mask.
        local HB = widget._blizzMerged and mod.UF_MergedHealth(G) or G.health
        local fillTex = healthBar:GetStatusBarTexture()
        healthBar:SetOrientation("HORIZONTAL")
        mod.ApplyFillRotation(healthBar)
        -- The mask object exists only for a kit with bar masks (the classic
        -- kit's bars are plain rectangles).
        local maskTex = healthBar._blizzMask
        if not maskTex and mod.UF_AtlasOK(G.health.mask) then
            maskTex = healthBar:CreateMaskTexture()
            healthBar._blizzMask = maskTex
        end
        local hp = widget.HealthPrediction and widget.HealthPrediction.damageAbsorb
        -- Reused scratch list (a layout pass allocates nothing).
        local barList = mod._ufBarScratch
        if not barList then
            barList = {}
            mod._ufBarScratch = barList
        end
        barList[1], barList[2], barList[3], barList[4], barList[5] =
            hp, hp and hp._forward, hp and hp._healAbsorb, hp and hp._topBar, hp and hp._healTopBar
        if not mirror and mod.UF_AtlasOK(G.health.mask) then
            mod.UF_SeatBarMask(maskTex, healthBar, HB)
            mod.UF_SetMask(fillTex, maskTex)
            if healthBar.bg then
                mod.UF_SetMask(healthBar.bg, maskTex)
            end
            if healthBar._cuiBgTex then
                mod.UF_SetMask(healthBar._cuiBgTex, maskTex)
            end -- Textured Background layer
            mod.UF_BlizzBarShadow(healthBar, maskTex, HB.h)
            -- Absorb fills ride the same rounded ends.
            for index = 1, 5 do
                local scrollBar = barList[index]
                if scrollBar and scrollBar.GetStatusBarTexture then
                    mod.UF_SetMask(scrollBar:GetStatusBarTexture(), maskTex)
                end
            end
            if hp then
                hp._blizzMaskOn = true
            end
        else
            -- Mirrored small frame (or no mask art): plain fills.
            if maskTex then
                if fillTex then
                    pcall(fillTex.RemoveMaskTexture, fillTex, maskTex)
                end
                if healthBar.bg then
                    pcall(healthBar.bg.RemoveMaskTexture, healthBar.bg, maskTex)
                end
                if healthBar._cuiBgTex then
                    pcall(healthBar._cuiBgTex.RemoveMaskTexture, healthBar._cuiBgTex, maskTex)
                end
                for index = 1, #barList do
                    local scrollBar = barList[index]
                    local tbl = scrollBar and scrollBar.GetStatusBarTexture and scrollBar:GetStatusBarTexture()
                    if tbl then
                        pcall(tbl.RemoveMaskTexture, tbl, maskTex)
                    end
                end
            end
            if hp then
                hp._blizzMaskOn = nil
            end
            mod.UF_BlizzBarShadow(healthBar, nil, HB.h)
        end
        -- Heal prediction segments take the shape too (Overheal 0 only).
        if hp and hp._predMy then
            mod.UF_HealPredMasks(hp)
        end
    end
    local powerBar = widget.Power
    if powerBar then
        local pfill = powerBar:GetStatusBarTexture()
        -- Stock rounded mask on the attached bar (stamped by the layout pass);
        -- a mirrored small frame runs unmasked.
        if pfill then
            local pm = powerBar._blizzMask
            if powerBar._blizzMasked and not mirror and mod.UF_AtlasOK(G.power.mask) then
                if not pm then
                    pm = powerBar:CreateMaskTexture()
                    powerBar._blizzMask = pm
                end
                mod.UF_SeatBarMask(pm, powerBar, G.power)
                mod.UF_SetMask(pfill, pm)
                if powerBar.bg then
                    mod.UF_SetMask(powerBar.bg, pm)
                end
                mod.UF_BlizzBarShadow(powerBar, pm, G.power.h)
            else
                if pm then
                    pcall(pfill.RemoveMaskTexture, pfill, pm)
                    if powerBar.bg then
                        pcall(powerBar.bg.RemoveMaskTexture, powerBar.bg, pm)
                    end
                end
                if powerBar._blizzMasked then
                    -- Mirrored small frame: in the track, unmasked.
                    mod.UF_BlizzBarShadow(powerBar, nil, G.power.h)
                elseif powerBar._blizzShadow then
                    -- Detached bar: it carries its own CUI border.
                    for index = 1, 4 do
                        powerBar._blizzShadow[index]:Hide()
                    end
                end
            end
        end
    end
end

-- Paints the frame art (one texture on the art frame, centred) from the
-- atlas sheet; a mirrored small frame samples the sheet flipped. The extras
-- (type strip, dragon) draw above it on higher sublevels.
-- Hide Power Bar: the art goes on in four pieces of its own sheet, so the
-- divider between the health and power windows is never drawn -- over the
-- bars (the classic frames) it would cross the health bar, under them (the
-- stock atlas art) it shows through a fill that is not fully opaque. `cut`
-- (in sheet texcoords): rows t..b are the divider band; on the bars' side of
-- column x the band takes the clear window rows from src down instead (src to
-- srcB stretched over the band when given), which carries the windows' end
-- rims through it, and on the portrait ring's side it keeps its own rows.
-- A scaled draw samples a row past each piece's edge, so an edge that falls
-- inside a window (t, b, src, srcB) lies between two plain track rows (clear
-- window rows on the classic sheets); b may also sit on the window's rim,
-- whose edge the art draws soft anyway. keepLeft: the ring lies left of x;
-- unset, the bars lie on the sheet's columns before x (the classic sheets,
-- whose player frame samples its sheet flipped). The art is centred on the
-- frame plus (ax, ay), w x h, from sheet coords l, r, t, b.
local function PlaceArtPiece(texture, widget, file, leftX, topY, x0, x1, y0, y1, u0, u1, v0, v1)
    texture:SetTexture(file)
    texture:SetTexCoord(u0, u1, v0, v1)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", widget, "CENTER", leftX + x0, topY - y0)
    texture:SetSize(x1 - x0, y1 - y0)
    texture:Show()
end
function mod.UF_PaintArtCut(widget, artTex, pieces, file, cut, l, region, t, b, wid, hgt, ax, ay, keepLeft)
    -- Art-local spans (y down from the art's top) and the art's top-left off
    -- the frame's centre.
    local y0 = (cut.t - t) / (b - t) * hgt
    local y1 = (cut.b - t) / (b - t) * hgt
    local xs = (cut.x - l) / (region - l) * wid
    local leftX, topY = ax - wid / 2, ay + hgt / 2
    local du = (region - l) / wid
    -- The art's own texture draws the rows above the band.
    PlaceArtPiece(artTex, widget, file, leftX, topY, 0, wid, 0, y0, l, region, t, cut.t)
    PlaceArtPiece(pieces[1], widget, file, leftX, topY, 0, wid, y1, hgt, l, region, cut.b, b)
    -- The sheet's columns past x lie right of xs, or left of it on an art
    -- sampled flipped (the classic player frame's).
    if keepLeft == nil then
        keepLeft = region < l
    end
    local kx0, kx1, cx0, cx1
    if keepLeft then
        kx0, kx1, cx0, cx1 = 0, xs, xs, wid
    else
        kx0, kx1, cx0, cx1 = xs, wid, 0, xs
    end
    PlaceArtPiece(
        pieces[2],
        widget,
        file,
        leftX,
        topY,
        kx0,
        kx1,
        y0,
        y1,
        l + kx0 * du,
        l + kx1 * du,
        cut.t,
        cut.b
    )
    PlaceArtPiece(
        pieces[3],
        widget,
        file,
        leftX,
        topY,
        cx0,
        cx1,
        y0,
        y1,
        l + cx0 * du,
        l + cx1 * du,
        cut.src,
        cut.srcB or (cut.src + (cut.b - cut.t))
    )
end

function mod.UF_PaintBlizzArt(widget, atlasName)
    local artFrame = widget._blizzArtFrame
    local artTex = artFrame._art
    if not artTex then
        artTex = artFrame:CreateTexture(nil, "BACKGROUND")
        UnsnapTex(artTex)
        artFrame._art = artTex
    end
    -- Hide Power Bar's art pieces show only while that paint runs (below).
    local pieces = artFrame._artCut
    if pieces then
        for index = 1, 3 do
            pieces[index]:Hide()
        end
    end
    local file, l, region, t, b, wid, hgt, anchorPoint, posX, posY
    if type(atlasName) == "table" then
        -- File descriptor: its own sheet coords and anchor (CENTER by default).
        if not mod.UF_ArtOK(atlasName) then
            artTex:Hide()
            return
        end
        file = atlasName.file
        l, region, t, b = atlasName.l or 0, atlasName.r or 1, atlasName.t or 0, atlasName.b or 1
        wid, hgt = atlasName.w, atlasName.h
        anchorPoint, posX, posY = atlasName.point or "CENTER", atlasName.x or 0, atlasName.y or 0
    else
        local details = mod.UF_StockAtlasInfo(atlasName)
        if not details then
            artTex:Hide()
            return
        end
        file = details.file or details.filename
        l, region, t, b = details.leftTexCoord, details.rightTexCoord, details.topTexCoord, details.bottomTexCoord
        wid, hgt = details.width, details.height
        anchorPoint, posX, posY = "CENTER", 0, 0
    end
    if not file then
        artTex:Hide()
        return
    end
    artTex:SetTexture(file)
    -- Hide Power Bar: the kit's own cut (the classic sheets), else the stock
    -- atlas art's for the file the client draws (UF_ATLAS_MERGE).
    local cut, keepLeft = widget._blizzMergeCut, nil
    if not cut and widget._blizzMerged and type(atlasName) == "string" then
        local byName = mod.UF_ATLAS_MERGE[file]
        local c = byName and byName[atlasName]
        if c then
            cut = artFrame._atlasCut
            if not cut then
                cut = {}
                artFrame._atlasCut = cut
            end
            local dv, du = (b - t) / c.h, (region - l) / c.w
            cut.t, cut.b, cut.src = t + c.t * dv, t + c.b * dv, t + c.src * dv
            cut.x = l + c.x * du
            keepLeft = c.ringLeft == true
        end
    end
    if cut and anchorPoint == "CENTER" and not widget._blizzMirror then
        if not pieces then
            pieces = {}
            for index = 1, 3 do
                local texture = artFrame:CreateTexture(nil, "BACKGROUND")
                UnsnapTex(texture)
                pieces[index] = texture
            end
            artFrame._artCut = pieces
        end
        mod.UF_PaintArtCut(widget, artTex, pieces, file, cut, l, region, t, b, wid, hgt, posX, posY, keepLeft)
        return
    end
    if widget._blizzMirror then
        artTex:SetTexCoord(region, l, t, b)
        anchorPoint = mod._ufMirrorPoint[anchorPoint] or anchorPoint
        posX = -posX
    else
        artTex:SetTexCoord(l, region, t, b)
    end
    artTex:ClearAllPoints()
    artTex:SetPoint(anchorPoint, widget, anchorPoint, posX, posY)
    artTex:SetSize(wid, hgt)
    artTex:Show()
end

-- Inner shadow on a bar, above its fill and under the bar's rounded mask so
-- it follows the track's shape: the stock fill art bakes this shading in,
-- and our fills are the user's own textures, so it is drawn here. Black
-- fading in from the top (deepest), the bottom and both ends. Regions of
-- the bar itself (no frame-level games); created once, resized per pass.
mod._ufShadeClear = CreateColor(0, 0, 0, 0)
mod._ufShadeTop = CreateColor(0, 0, 0, 0.55)
mod._ufShadeBottom = CreateColor(0, 0, 0, 0.30)
mod._ufShadeEnd = CreateColor(0, 0, 0, 0.35)
function mod.UF_BlizzBarShadow(barFrame, maskTex, hgt)
    local sh = barFrame._blizzShadow
    -- A kit with flat bars (the classic frames) draws no bevel.
    if mod.UF_BLIZZ.noBevel then
        if sh then
            for index = 1, 4 do
                sh[index]:Hide()
            end
        end
        return
    end
    if not sh then
        sh = {}
        barFrame._blizzShadow = sh
        for index = 1, 4 do
            local texture = barFrame:CreateTexture(nil, "OVERLAY", nil, -3)
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            UnsnapTex(texture)
            sh[index] = texture
        end
        -- VERTICAL runs bottom -> top, HORIZONTAL left -> right.
        sh[1]:SetGradient("VERTICAL", mod._ufShadeClear, mod._ufShadeTop)
        sh[2]:SetGradient("VERTICAL", mod._ufShadeBottom, mod._ufShadeClear)
        sh[3]:SetGradient("HORIZONTAL", mod._ufShadeEnd, mod._ufShadeClear)
        sh[4]:SetGradient("HORIZONTAL", mod._ufShadeClear, mod._ufShadeEnd)
    end
    -- nil = unmasked strips (mirrored small frames): an earlier mask comes off.
    if sh._mask ~= maskTex then
        for index = 1, 4 do
            if sh._mask then
                pcall(sh[index].RemoveMaskTexture, sh[index], sh._mask)
            end
            if maskTex then
                sh[index]:AddMaskTexture(maskTex)
            end
        end
        sh._mask = maskTex
    end
    local topY, bottom, ends =
        math.max(2, math.floor(hgt * 0.2)),
        math.max(1, math.floor(hgt * 0.1)),
        math.max(2, math.floor(hgt * 0.15))
    sh[1]:ClearAllPoints()
    sh[1]:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
    sh[1]:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", 0, 0)
    sh[1]:SetHeight(topY)
    sh[2]:ClearAllPoints()
    sh[2]:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
    sh[2]:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
    sh[2]:SetHeight(bottom)
    sh[3]:ClearAllPoints()
    sh[3]:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
    sh[3]:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
    sh[3]:SetWidth(ends)
    sh[4]:ClearAllPoints()
    sh[4]:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", 0, 0)
    sh[4]:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
    sh[4]:SetWidth(ends)
    for index = 1, 4 do
        sh[index]:Show()
    end
end

-- Frame art (plus the reputation strip and boss/elite dragon on the target
-- family) on a child frame under the bars and over the portrait, as the
-- stock frame layers it: the art's ring overlaps the portrait, the bars
-- draw over the art's tracks.
function mod.UF_ApplyBlizzFrameArt(widget, G)
    local mirror = widget._blizzMirror
    local artFrame = widget._blizzArtFrame
    if not artFrame then
        artFrame = CreateFrame("Frame", nil, widget)
        artFrame:SetAllPoints(widget)
        artFrame:EnableMouse(false)
        widget._blizzArtFrame = artFrame
    end
    -- Target-family extras (type strip, dragon), created the first time a
    -- frame renders on the target art; a side change can turn them off again.
    if widget._blizzExtras and not artFrame._rep then
        local repBar = artFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        UnsnapTex(repBar)
        artFrame._rep = repBar
        local dragon = artFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
        UnsnapTex(dragon)
        dragon:Hide()
        artFrame._dragon = dragon
        -- One shared event frame refreshes every target-family frame's
        -- art; created with the first such frame, so it never exists
        -- while the style is off.
        if not mod._ufBlizzArtEvents then
            mod._ufBlizzArtFrames = {}
            local event = CreateFrame("Frame")
            event:RegisterEvent("PLAYER_TARGET_CHANGED")
            event:RegisterEvent("PLAYER_FOCUS_CHANGED")
            event:RegisterEvent("PLAYER_ENTERING_WORLD")
            event:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
            event:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target", "focus")
            event:RegisterUnitEvent("UNIT_FACTION", "target", "focus")
            event:SetScript("OnEvent", function()
                local entries = mod._ufBlizzArtFrames
                for index = 1, #entries do
                    mod.UF_RefreshBlizzTargetArt(entries[index])
                end
            end)
            mod._ufBlizzArtEvents = event
        end
        table.insert(mod._ufBlizzArtFrames, widget)
    end
    -- Draw order: art UNDER the bars, over the portrait. The bars live in a
    -- clipping container that renders as one group at the container's level
    -- (a frame AT that level ties with the group, and the tie fell either
    -- way in-game), so the art sits one level below the container; strata
    -- follows the container so a custom Strata setting cannot separate them.
    local clip = widget._barClip
    local base = (clip and clip:GetFrameLevel()) or widget:GetFrameLevel()
    artFrame:SetFrameStrata((clip and clip:GetFrameStrata()) or widget:GetFrameStrata())
    -- A kit whose art is opaque round transparent bar windows (the classic
    -- target and pet frames) draws it OVER the bars instead: above the
    -- clipped group, still under the text overlays.
    if G.artAbove then
        artFrame:SetFrameLevel(base + 2)
    else
        artFrame:SetFrameLevel(math.max(0, base - 1))
    end
    -- The paint memo's key: the mirror, and Hide Power Bar's cut art.
    artFrame._artSig = (mirror and "|m" or "") .. (widget._blizzMerged and "|h" or "")
    -- The target family resolves its art (classification variants) in the
    -- refresh below: one paint per change, never the base art first.
    if not artFrame._rep then
        local key = mod.UF_ArtName(G.art) .. artFrame._artSig
        if artFrame._artKey ~= key then
            artFrame._artKey = key
            mod.UF_PaintBlizzArt(widget, G.art)
        end
    end
    -- The dark plaque behind the name and bars (classic kit): its own frame
    -- under the bars whatever level the art takes.
    if G.back then
        local borderFrame = artFrame._backFrame
        if not borderFrame then
            borderFrame = CreateFrame("Frame", nil, widget)
            borderFrame:SetAllPoints(widget)
            borderFrame:EnableMouse(false)
            local bk = borderFrame:CreateTexture(nil, "BACKGROUND")
            bk:SetColorTexture(0, 0, 0, 0.5)
            UnsnapTex(bk)
            borderFrame._tex = bk
            artFrame._backFrame = borderFrame
        end
        borderFrame:SetFrameStrata(artFrame:GetFrameStrata())
        -- Under the art whether the art sits under the bars (base - 1) or
        -- over them; beside the portrait backdrop's level, never overlapping it.
        borderFrame:SetFrameLevel(math.max(0, base - 2))
        borderFrame._tex:ClearAllPoints()
        mod.UF_BlizzPoint(borderFrame._tex, "TOPLEFT", widget, "TOPLEFT", G.back.x, -G.back.y, mirror)
        borderFrame._tex:SetSize(G.back.w, G.back.h)
        borderFrame:Show()
    elseif artFrame._backFrame then
        artFrame._backFrame:Hide()
    end
    if artFrame._rep then
        local repBar = G.rep
        local repArt = repBar and (repBar.art or repBar.atlas)
        if
            widget._blizzExtras
            and mod.UF_ArtOK(repArt)
            and mod.UF_BlizzHeaderOn(GetSettingsForUnit(widget._cuiBaseUnit or widget._cuiUnit))
        then
            mod.UF_SetArt(artFrame._rep, repArt, true)
            -- Over the art (the stock type strip) or under it (the classic
            -- name plaque, seen through the art's name window).
            artFrame._rep:SetDrawLayer("BACKGROUND", repBar.below and -1 or 1)
            artFrame._rep:ClearAllPoints()
            local rp = repBar.point or "TOPRIGHT"
            artFrame._rep:SetPoint(rp, widget, rp, repBar.x, repBar.y)
            artFrame._rep:Show()
        else
            artFrame._rep:Hide()
        end
        mod.UF_RefreshBlizzTargetArt(widget)
    end
end

-- Target-family art that follows the unit: rare frame variant, elite/rare/
-- boss dragon, reputation strip tint. Every unit read is secrecy-guarded.
function mod.UF_RefreshBlizzTargetArt(widget)
    local artFrame = widget and widget._blizzArtFrame
    if not artFrame or not artFrame._rep then
        return
    end
    local G = widget._blizzGeom
    if not G then
        return
    end
    local unitToken = widget._cuiUnit
    local extras = widget._blizzExtras and G.rep and unitToken and UnitExists(unitToken)
    local c
    if extras then
        local red, green, blue = UnitSelectionColor(unitToken)
        if red and not issecretvalue(red) and not issecretvalue(green) and not issecretvalue(blue) then
            artFrame._rep:SetVertexColor(red, green, blue)
        else
            artFrame._rep:SetVertexColor(0.5, 0.5, 0.5)
        end
        c = UnitClassification(unitToken)
        if issecretvalue(c) then
            c = nil
        end
    end
    local boss = extras and UnitIsBossMob and UnitIsBossMob(unitToken)
    if issecretvalue(boss) then
        boss = false
    end
    -- The one art paint for this family (see UF_ApplyBlizzFrameArt): the
    -- classification variant -- the stock kit's rare frame, or the classic
    -- kit's whole-frame elite / rare / rare-elite / boss arts (boss frames
    -- always wear the boss art) -- else the base art, memo on the result.
    local artName = G.art
    local byc = G.artByClass
    if byc then
        -- A variant this client does not ship falls back a step (boss art to
        -- the elite frame, then the base art).
        if unitToken and unitToken:match("^boss%d$") and mod.UF_ArtOK(byc.boss) then
            artName = byc.boss
        elseif (boss or (unitToken and unitToken:match("^boss%d$"))) and mod.UF_ArtOK(byc.elite) then
            artName = byc.elite
        elseif extras and c and mod.UF_ArtOK(byc[c]) then
            artName = byc[c]
        end
    elseif (c == "rare" or c == "rareelite") and mod.UF_ArtOK(G.artRare) then
        artName = G.artRare
    end
    local artKey = mod.UF_ArtName(artName) .. (artFrame._artSig or "")
    if artFrame._artKey ~= artKey then
        artFrame._artKey = artKey
        mod.UF_PaintBlizzArt(widget, artName)
    end
    -- The classic arts carry their dragon; the stock kit adds it below.
    if not extras or byc then
        artFrame._dragon:Hide()
        return
    end
    -- Stock rule: the winged dragon for boss mobs, silver for rare elites,
    -- gold for elites, nothing else. WoW Forever puts the silver dragon on
    -- plain rares too and places each dragon its own way (the kit's `pos`).
    local B = G.boss
    local dragon, dx, place
    if boss then
        dragon, dx, place = B.winged, 8, B.pos and B.pos.winged
    elseif c == "rareelite" or (B.silverRare and c == "rare") then
        dragon, dx, place = B.silver, -11, B.pos and B.pos.silver
    elseif c == "elite" then
        dragon, dx, place = B.gold, -11, B.pos and B.pos.gold
    end
    local dy = -8
    if place then
        dx, dy = place[1], place[2]
    end
    if dragon and mod.UF_AtlasOK(dragon) then
        mod.UF_StockAtlas(artFrame._dragon, dragon, true)
        artFrame._dragon:ClearAllPoints()
        artFrame._dragon:SetPoint("TOPRIGHT", widget, "TOPRIGHT", dx, dy)
        artFrame._dragon:Show()
    else
        artFrame._dragon:Hide()
    end
end

-- Portrait: always shown (the stock frames carry one), the stock size and
-- position with the stock mask (round, or the player frame's own crop), full
-- art, no CUI backdrop, and UNDER the frame art (the art's ring and bar edge
-- overlap it exactly as on the stock frame).
function mod.UF_ApplyBlizzPortrait(widget, G)
    local pt = widget.Portrait
    local edge = pt and pt.backdrop
    if not edge then
        return
    end
    local mirror = widget._blizzMirror
    edge:ClearAllPoints()
    mod.UF_BlizzPoint(edge, G.portrait.point, widget, G.portrait.point, G.portrait.x, G.portrait.y, mirror)
    edge:SetSize(G.portrait.size, G.portrait.size)
    -- Under the art (which sits one level below the bar clip container; see
    -- UF_ApplyBlizzFrameArt), in the same strata.
    local clip = widget._barClip
    edge:SetFrameStrata((clip and clip:GetFrameStrata()) or widget:GetFrameStrata())
    edge:SetFrameLevel(math.max(0, ((clip and clip:GetFrameLevel()) or widget:GetFrameLevel()) - 2))
    edge:SetClipsChildren(false)
    if edge._bg then
        edge._bg:SetAlpha(0)
    end
    if edge._2d then
        edge._2d:SetTexCoord(0, 1, 0, 1)
    end
    local m = edge._blizzMask
    if not m and mod.UF_AtlasOK(G.portrait.mask) then
        m = edge:CreateMaskTexture()
        m:SetAllPoints(edge)
        if edge._2d then
            edge._2d:AddMaskTexture(m)
        end
        if edge._class then
            edge._class:AddMaskTexture(m)
        end
        edge._blizzMask = m
    end
    -- Re-set each pass: a side change swaps the player crop for the circle.
    -- (A mirrored small frame keeps its circle; masks cannot flip anyway.)
    if m and mod.UF_AtlasOK(G.portrait.mask) then
        mod.UF_StockMask(m, G.portrait.mask)
    end
    -- SetPortraitTexture crops the art to a circle by itself (the stock
    -- target/pet frames keep that crop under their CircleMask); the player
    -- frame's mask is not a circle, so there the crop is switched off and the
    -- atlas mask is the only shape. The engine's portrait paint reads the
    -- stamp; a change repaints the current art.
    local repaint
    if edge._2d then
        local raw = (m and G.portrait.rawArt) or nil
        if edge._2d._blizzNoMask ~= raw then
            edge._2d._blizzNoMask = raw
            repaint = true
        end
    end
    -- Forced on: a profile with the portrait hidden or set to None still shows it.
    edge:Show()
    if widget.IsElementEnabled and not widget:IsElementEnabled("Portrait") then
        widget:EnableElement("Portrait")
        repaint = true
    end
    if repaint and pt.ForceUpdate then
        pt:ForceUpdate()
    end
end

-- Text zones: the left zone (the name by default) moves onto the stock name
-- strip; the other zones keep their bar-relative placement.
function mod.UF_BlizzTextPass(widget)
    local G = mod.UF_BlizzGeom(widget)
    local lt = widget and widget.LeftText
    if not (G and lt and G.name) then
        return
    end
    -- The Left Text offsets still apply on top of the stock spot, in screen
    -- terms (+X right, +Y up) on the mirrored art too, so they are added
    -- after the mirror rather than through it.
    local cfg = GetSettingsForUnit(widget._cuiBaseUnit or widget._cuiUnit)
    local lxo, lyo = (cfg and cfg.leftTextX) or 0, (cfg and cfg.leftTextY) or 0
    lt:ClearAllPoints()
    lt:SetJustifyH(G.name.justify or "LEFT")
    local anchorPoint, posX = G.name.point, G.name.x
    if widget._blizzMirror then
        anchorPoint = mod._ufMirrorPoint[anchorPoint] or anchorPoint
        posX = -posX
    end
    lt:SetPoint(anchorPoint, widget, anchorPoint, posX + lxo, G.name.y + lyo)
    lt:SetWidth(G.name.w)
end

-- Level number in the frame's level circle, as the stock frames draw it:
-- the stock number font at the stock spot (the right end of the player
-- art's name bar, the left end of the target art's type strip), gold, green
-- while the player is level-scaled, the creature difficulty colour on an
-- attackable target, and the stock skull for a level the client will not
-- tell. One FontString per full frame on its own host above the bars,
-- refreshed by a shared event frame created with the first frame (nothing
-- exists while the style is off). Per-unit "Show Level" (blizzShowLevel,
-- default on) hides it; per-unit "Difficulty Color" (blizzLevelDifficultyColor,
-- default on) off keeps an attackable unit's level gold too.
mod.UF_BLIZZ_SKULL = "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon"
function mod.UF_BlizzLevelPass(widget)
    local G = mod.UF_BlizzGeom(widget)
    local L = G and G.level
    if not L then
        return
    end
    local clip = widget._barClip
    local owner = widget._blizzLevelHost
    if not owner then
        owner = CreateFrame("Frame", nil, widget)
        owner:SetAllPoints(widget)
        owner:EnableMouse(false)
        widget._blizzLevelHost = owner
        local fontStr = owner:CreateFontString(nil, "OVERLAY")
        -- The stock number font as the baseline: the name's font is copied
        -- below once the name text carries one (not yet at first spawn).
        fontStr:SetFontObject(GameNormalNumberFont)
        widget._blizzLevel = fontStr
        local skull = owner:CreateTexture(nil, "OVERLAY", nil, 1)
        skull:Hide()
        widget._blizzLevelSkull = skull
        if not mod._ufBlizzLevelEvents then
            mod._ufBlizzLevelFrames = {}
            local event = CreateFrame("Frame")
            event:RegisterEvent("PLAYER_TARGET_CHANGED")
            event:RegisterEvent("PLAYER_FOCUS_CHANGED")
            event:RegisterEvent("PLAYER_ENTERING_WORLD")
            event:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
            event:RegisterEvent("PLAYER_LEVEL_UP")
            event:RegisterEvent("UNIT_LEVEL")
            event:RegisterEvent("UNIT_FACTION")
            event:SetScript("OnEvent", function(_, evt, unitToken)
                -- Unit events refresh their frame; everything else refreshes all.
                local entries = mod._ufBlizzLevelFrames
                local byUnit = type(unitToken) == "string"
                for index = 1, #entries do
                    local frame = entries[index]
                    if not byUnit or frame._cuiUnit == unitToken then
                        mod.UF_BlizzLevelRefresh(frame, evt)
                    end
                end
            end)
            mod._ufBlizzLevelEvents = event
        end
        table.insert(mod._ufBlizzLevelFrames, widget)
    end
    -- Re-seated every pass: the host follows the bar clip's strata and sits
    -- above the bars, like the art frame does below them.
    owner:SetFrameStrata((clip and clip:GetFrameStrata()) or widget:GetFrameStrata())
    owner:SetFrameLevel(((clip and clip:GetFrameLevel()) or widget:GetFrameLevel()) + 12)
    local fontStr, skull = widget._blizzLevel, widget._blizzLevelSkull
    local cfg = GetSettingsForUnit(widget._cuiBaseUnit or widget._cuiUnit)
    -- Same face, outline and shadow as the unit name (and its size, unless
    -- the level has its own): the name's font object first (it carries the
    -- shadow), then its face. A name on a font family gives its roman member's
    -- face, the chosen font, whatever script the name holds. The colour keeps
    -- the stock rules (set as an instance text colour, never vertex-only).
    local lt = widget.LeftText
    if lt then
        local fo = lt:GetFontObject()
        local source = (fo and CludesUI._fontFamilySet[fo] and fo:GetFontObjectForAlphabet("roman")) or lt
        local face, size, flags = source:GetFont()
        if face then
            if fo then
                fontStr:SetFontObject(fo)
            end
            fontStr:SetFont(face, (cfg and cfg.blizzLevelSize) or size, flags)
        end
    end
    -- The stock spot, plus the level's own offsets.
    local ox, oy = (cfg and cfg.blizzLevelX) or 0, (cfg and cfg.blizzLevelY) or 0
    -- WoW Forever: the level sits in a round badge at the frame's bottom
    -- corner, which the level's own offsets move as a whole; the number and
    -- the skull centre on it (a fixed size, so a missing atlas keeps the spot).
    local rel, B = widget, G.badge
    if B then
        local badge = widget._blizzLevelBadge
        if not badge then
            badge = owner:CreateTexture(nil, "OVERLAY", nil, -1)
            UnsnapTex(badge)
            mod.UF_SetArt(badge, B.atlas)
            widget._blizzLevelBadge = badge
        end
        badge:SetSize(B.size, B.size)
        badge:ClearAllPoints()
        mod.UF_BlizzPoint(badge, B.point, widget, B.point, B.x + ox, B.y + oy, widget._blizzMirror)
        rel, ox, oy = badge, 0, 0
    end
    fontStr:ClearAllPoints()
    fontStr:SetJustifyH(L.justify or "CENTER")
    mod.UF_BlizzPoint(fontStr, L.point, rel, L.relPoint or L.point, L.x + ox, L.y + oy, widget._blizzMirror)
    -- The skull takes the number's spot (its own anchor, so a hidden number
    -- never moves it).
    skull:ClearAllPoints()
    mod.UF_BlizzPoint(
        skull,
        L.point,
        rel,
        L.relPoint or L.point,
        L.x + ox,
        L.y + (L.skullDy or 2) + oy,
        widget._blizzMirror
    )
    mod.UF_SetArt(skull, mod.UF_BLIZZ.skull or mod.UF_BLIZZ_SKULL, true)
    -- WoW Forever: the PvP crest on the player, target and focus frames
    -- (Blizzard's own display rule paints and shows it, below).
    local PV = G.pvp
    local u = widget._cuiUnit
    if PV and (u == "player" or u == "target" or u == "focus") then
        local els = widget._blizzPvP
        if not els then
            els = { pvpIcon = owner:CreateTexture(nil, "OVERLAY", nil, 3) }
            UnsnapTex(els.pvpIcon)
            -- Blizzard's own scale and offsets, so the crest lands where the
            -- stock frame puts it whatever the scale does to the offsets.
            els.pvpIcon:SetScale(PV.scale)
            els.pvpIcon:Hide()
            widget._blizzPvP = els
        end
        els.pvpIcon:ClearAllPoints()
        mod.UF_BlizzPoint(els.pvpIcon, PV.point, widget, PV.relPoint, PV.x, PV.y, widget._blizzMirror)
    end
    -- Where the level shares the name's end of the strip, the name gives up
    -- that width while the level shows (the text pass set the full width).
    if lt and G.name and L.nameTrim then
        local enabled = cfg and cfg.blizzShowLevel ~= false
        lt:SetWidth(G.name.w - (enabled and L.nameTrim or 0))
    end
    mod.UF_BlizzLevelRefresh(widget)
end
-- `event`: the level event that asked (nil = the layout pass).
function mod.UF_BlizzLevelRefresh(widget, evt)
    local fontStr = widget and widget._blizzLevel
    if not fontStr then
        return
    end
    local skull = widget._blizzLevelSkull
    -- WoW Forever's level badge (nil on every other kit).
    local badge = widget._blizzLevelBadge
    local unitToken = widget._cuiUnit
    -- WoW Forever's PvP badge, only where its unit can have changed.
    if widget._blizzPvP then
        local only = evt and mod.UF_PVP_EVENT_UNIT[evt]
        if only == nil or only == unitToken then
            mod.UF_ForeverPvPRefresh(widget, unitToken)
        end
    end
    local cfg = unitToken and GetSettingsForUnit(widget._cuiBaseUnit or unitToken)
    if not cfg or cfg.blizzShowLevel == false or not UnitExists(unitToken) then
        fontStr:Hide()
        skull:Hide()
        if badge then
            badge:Hide()
        end
        return
    end
    -- Every unit read is treated as possibly secret: a secret level still
    -- paints (SetText takes it), a secret flag reads as its stock default.
    local gold, levelText = true, nil
    if unitToken == "player" then
        levelText = UnitEffectiveLevel(unitToken)
        local base = UnitLevel(unitToken)
        if not issecretvalue(levelText) and not issecretvalue(base) and levelText ~= base then
            fontStr:SetTextColor(0.1, 1, 0.1)
            gold = false
        end
    else
        local corpse = UnitIsCorpse(unitToken)
        if issecretvalue(corpse) then
            corpse = false
        end
        local pet = UnitIsWildBattlePet(unitToken) or UnitIsBattlePetCompanion(unitToken)
        if issecretvalue(pet) then
            pet = false
        end
        if corpse then
            levelText = 0
        elseif pet and badge then
            -- WoW Forever shows neither the level nor its badge for a battle pet.
            fontStr:Hide()
            skull:Hide()
            badge:Hide()
            return
        elseif pet then
            levelText = UnitBattlePetLevel(unitToken)
        else
            levelText = UnitEffectiveLevel(unitToken)
            local can = cfg.blizzLevelDifficultyColor ~= false and UnitCanAttack("player", unitToken)
            if not issecretvalue(can) and can then
                local diff = C_PlayerInfo.GetContentDifficultyCreatureForPlayer(unitToken)
                local color = not issecretvalue(diff) and GetDifficultyColor and GetDifficultyColor(diff)
                if color then
                    fontStr:SetTextColor(color.r, color.g, color.b)
                    gold = false
                end
            end
        end
    end
    if gold then
        -- WoW Forever paints the player's own level white.
        if badge and unitToken == "player" then
            fontStr:SetTextColor(1, 1, 1)
        else
            fontStr:SetTextColor(1, 0.82, 0)
        end
    end
    if badge then
        badge:Show()
    end
    -- A level the client will not tell (corpse, or 0 and below): the stock skull.
    if issecretvalue(levelText) or (levelText and levelText > 0) then
        fontStr:SetText(levelText)
        fontStr:Show()
        skull:Hide()
    else
        fontStr:Hide()
        skull:Show()
    end
end
-- WoW Forever's PvP crest: the client's own secret-safe painter (the one its
-- unit frames call, offered to addons) sets the faction or free for all
-- crest and shows it under Blizzard's rule, including the mercenary swap on
-- the player. Rides the level refresh's events.
-- The level events that leave the badge alone, or repaint one frame's only:
-- a target or focus swap repaints that frame alone, and a level change or
-- an encounter unit none. Every other event (the unit's own UNIT_FACTION,
-- the loading screen) and the layout pass repaint each badge they reach.
mod.UF_PVP_EVENT_UNIT = {
    PLAYER_TARGET_CHANGED = "target",
    PLAYER_FOCUS_CHANGED = "focus",
    INSTANCE_ENCOUNTER_ENGAGE_UNIT = false,
    PLAYER_LEVEL_UP = false,
    UNIT_LEVEL = false,
}
function mod.UF_ForeverPvPRefresh(widget, unitToken)
    local els = widget._blizzPvP
    local paint = UnitFrameUtil and UnitFrameUtil.UpdateUnitPvPIndicator
    if paint and UnitExists(unitToken) then
        paint(els, unitToken, unitToken == "player")
    else
        els.pvpIcon:Hide()
    end
end

-- Cast bar fill per cast kind ("cast" | "channel"); one field test when the
-- style is off, memoized per bar.
function mod.UF_SetBlizzCastFill(callback, kind)
    if not callback or not callback._blizzCast then
        return
    end
    kind = kind or "cast"
    if callback._blizzFillKind == kind then
        return
    end
    local atlasName = mod.UF_BlizzAtlas(mod.UF_CAST_BLIZZ[kind] or mod.UF_CAST_BLIZZ.cast)
    if not atlasName then
        return
    end
    callback._blizzFillKind = kind
    callback:GetStatusBarTexture():SetAtlas(atlasName)
end
-- Spell name into the text box under the bar (honouring its side + offsets).
function mod.UF_BlizzCastText(callback)
    local box = callback and callback._blizzTextBox
    if not box or not box:IsShown() or not callback.Text then
        return
    end
    if callback._nameSide == "none" then
        return
    end
    -- The box spans the bar (not the holder: an in-width icon takes part of
    -- the holder), so the name's width follows the bar.
    local wid = callback:GetWidth()
    -- Secret under aura restriction when the holder rides the aura block:
    -- keep the out-of-combat layout (the width is fixed in combat).
    if issecretvalue(wid) then
        return
    end
    wid = wid or 0
    callback.Text:ClearAllPoints()
    local edgeSide = callback._nameSide or "left"
    local ox, oy = callback._nameOX or 0, callback._nameOY or 0
    if edgeSide == "right" then
        callback.Text:SetJustifyH("RIGHT")
        callback.Text:SetPoint("RIGHT", box, "RIGHT", -8 + ox, oy)
    elseif edgeSide == "center" then
        callback.Text:SetJustifyH("CENTER")
        callback.Text:SetPoint("CENTER", box, "CENTER", ox, oy)
    else
        callback.Text:SetJustifyH("LEFT")
        callback.Text:SetPoint("LEFT", box, "LEFT", 8 + ox, oy)
    end
    if wid > 20 then
        callback.Text:SetWidth(wid - 16)
    end
    mod.ReflowFontString(callback.Text)
end
-- Cast icon under the style: a square spanning the bar and the stock text
-- box under it (the box hangs 13px below the bar while the spell name
-- shows), hung from the holder's top corner on the configured side -- inside
-- the footprint, where the bar then starts past it, or off its edge -- with
-- the user's offsets, so its top lines up with the bar and its bottom with
-- the box. Inputs are the ones LayoutCastbarIcon stamped; the only rect read
-- is the holder's explicit height (plain on every anchor chain).
function mod.UF_BlizzCastIcon(callback)
    local ico = callback and callback._iconFrame
    local owner = callback and callback:GetParent()
    if not ico or not owner then
        return
    end
    -- The configured height LayoutCastbarIcon stamped (the holder's own rect
    -- reads back secret while it rides the aura block).
    local hostH = callback._icoSide or owner:GetHeight()
    if issecretvalue(hostH) or not hostH or hostH <= 0 then
        return
    end
    local box = callback._blizzTextBox
    local edgeSide = hostH + ((box and box:IsShown()) and 13 or 0)
    local inWidth, onRight = callback._icoInWidth, callback._icoOnRight
    local offX, offY = callback._icoOffX or 0, callback._icoOffY or 0
    ico:ClearAllPoints()
    ico:SetSize(edgeSide, edgeSide)
    if inWidth then
        if onRight then
            Pix.Point(ico, "TOPRIGHT", owner, "TOPRIGHT", offX, offY)
        else
            Pix.Point(ico, "TOPLEFT", owner, "TOPLEFT", offX, offY)
        end
        -- The bar takes the rest of the footprint (LayoutCastbarIcon inset it
        -- by the CUI square; this icon is wider).
        callback:ClearAllPoints()
        if onRight then
            Pix.Point(callback, "TOPLEFT", owner, "TOPLEFT", 0, 0)
            Pix.Point(callback, "BOTTOMRIGHT", owner, "BOTTOMRIGHT", -edgeSide, 0)
        else
            Pix.Point(callback, "TOPLEFT", owner, "TOPLEFT", edgeSide, 0)
            Pix.Point(callback, "BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
        end
    elseif onRight then
        Pix.Point(ico, "TOPLEFT", owner, "TOPRIGHT", offX, offY)
    else
        Pix.Point(ico, "TOPRIGHT", owner, "TOPLEFT", offX, offY)
    end
end
-- Cast bar: stock background, fill art, frame and text box; the CUI tint
-- layer stays off (the fill art is its own colour). Border and icon frame go.
function mod.UF_ApplyBlizzCastbar(callback)
    if not callback then
        return
    end
    -- The stock chrome owns the frame: a Custom Border Style host stays hidden.
    if callback._cbBorder then
        callback._cbBorder:Hide()
    end
    local owner = callback:GetParent()
    local CK = mod.UF_BLIZZ.cast
    if CK then
        -- Classic kit: the vanilla cast bar frame round the user's own fill
        -- and colours; no stock background, fill art or text box (the spell
        -- name stays on the bar in its CUI zone). The frame is the shared
        -- nine-slice anchored to the HOLDER's corners (bar plus icon: the
        -- icon is part of the bar under this kit and sits inside the frame's
        -- window), so no rect is read here. Its pieces ride an art child of
        -- the holder above the bar and the icon (both holder +1) and under
        -- the text overlay, so the rim overlaps the icon's edges as it does
        -- the fill's.
        callback._blizzCast = nil
        Pix.HideBorder(callback)
        if not callback._blizzFrame and owner then
            local artFrame = CreateFrame("Frame", nil, owner)
            artFrame:SetAllPoints(owner)
            artFrame:EnableMouse(false)
            artFrame:SetFrameLevel(owner:GetFrameLevel() + 3)
            callback._classicArt = artFrame
            local fr = artFrame:CreateTexture(nil, "OVERLAY", nil, 2)
            UnsnapTex(fr)
            callback._blizzFrame = fr
        end
        if callback._blizzFrame then
            mod.UF_SeatClassicCastFrame(callback._blizzFrame, owner, nil, callback._classicPct)
        end
        local ico = callback._iconFrame
        if ico then
            Pix.HideBorder(ico)
            if ico._bg then
                ico._bg:Hide()
            end
            if callback.Icon then
                callback.Icon:ClearAllPoints()
                callback.Icon:SetAllPoints(ico)
            end
        end
        if callback.Icon then
            callback.Icon:SetTexCoord(0, 1, 0, 1)
        end
        mod.UF_BlizzCastIcon(callback)
        if callback._layoutTextZones then
            callback:_layoutTextZones()
        end
        return
    end
    callback._blizzCast = true
    callback._blizzFillKind = nil
    callback:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fillTex = callback:GetStatusBarTexture()
    if fillTex then
        fillTex:SetHorizTile(false)
        UnsnapTex(fillTex)
    end
    mod.UF_SetBlizzCastFill(callback, callback.channeling and "channel" or "cast")
    callback:SetStatusBarColor(1, 1, 1, callback._fillOp or 1)
    if callback.castTintLayer then
        callback.castTintLayer:SetAlpha(0)
        callback._castTintOn = nil
    end
    if owner and owner._bgTex then
        -- A bar texture, not frame chrome: the retail background under
        -- Blizzard Style, WoW Forever included.
        local bgAtlas = mod.UF_BlizzAtlas(mod.UF_CAST_BLIZZ.bg)
        if bgAtlas then
            CludesUI.StockAtlas(owner._bgTex, bgAtlas)
        end
        owner._bgTex:ClearAllPoints()
        owner._bgTex:SetPoint("TOPLEFT", owner, "TOPLEFT", -1, 1)
        owner._bgTex:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 1, -1)
    end
    Pix.HideBorder(callback)
    if not callback._blizzFrame then
        -- The frame art rides its own child of the bar, above the
        -- uninterruptible shield's host (bar +1) and the kick marker (bar +2),
        -- under the text overlay: as a region of the bar itself, the shield
        -- frame would draw its grey over the art.
        local artFrame = CreateFrame("Frame", nil, callback)
        artFrame:SetAllPoints(callback)
        artFrame:EnableMouse(false)
        callback._blizzArtFr = artFrame
        local fr = artFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        UnsnapTex(fr)
        callback._blizzFrame = fr
        local tb = owner:CreateTexture(nil, "BACKGROUND", nil, -1)
        UnsnapTex(tb)
        callback._blizzTextBox = tb
        local orig = callback._layoutTextZones
        if orig then
            callback._layoutTextZones = function(self)
                orig(self)
                mod.UF_BlizzCastText(self)
            end
        end
    end
    -- Re-asserted every pass (a strata change rebuilds child levels).
    local artLvl = callback:GetFrameLevel() + 3
    if callback._blizzArtFr and callback._blizzArtFr:GetFrameLevel() ~= artLvl then
        callback._blizzArtFr:SetFrameLevel(artLvl)
    end
    local frAtlas = mod.UF_BlizzAtlas(mod.UF_CAST_BLIZZ.frame)
    if frAtlas then
        mod.UF_StockAtlas(callback._blizzFrame, frAtlas)
        callback._blizzFrame:ClearAllPoints()
        callback._blizzFrame:SetPoint("TOPLEFT", callback, "TOPLEFT", -2, 2)
        callback._blizzFrame:SetPoint("BOTTOMRIGHT", callback, "BOTTOMRIGHT", 2, -2)
        callback._blizzFrame:Show()
    else
        callback._blizzFrame:Hide()
    end
    local tbAtlas = mod.UF_BlizzAtlas(mod.UF_CAST_BLIZZ.textbox)
    if tbAtlas and callback._nameSide ~= "none" then
        -- Under the BAR (not the holder): with an in-width icon the bar
        -- starts past the icon, and the box's left edge follows the bar's.
        mod.UF_StockAtlas(callback._blizzTextBox, tbAtlas)
        callback._blizzTextBox:ClearAllPoints()
        callback._blizzTextBox:SetPoint("TOPLEFT", callback, "BOTTOMLEFT", 0, 3)
        callback._blizzTextBox:SetPoint("BOTTOMRIGHT", callback, "BOTTOMRIGHT", 0, -13)
        callback._blizzTextBox:Show()
    else
        callback._blizzTextBox:Hide()
    end
    -- The icon is the bare art, as stock: no CUI black plate, no border and
    -- no 1px inset (the inset was that border's room).
    local ico = callback._iconFrame
    if ico then
        Pix.HideBorder(ico)
        if ico._bg then
            ico._bg:Hide()
        end
        if callback.Icon then
            callback.Icon:ClearAllPoints()
            callback.Icon:SetAllPoints(ico)
        end
    end
    if callback.Icon then
        callback.Icon:SetTexCoord(0, 1, 0, 1)
    end
    mod.UF_BlizzCastIcon(callback)
    if callback._layoutTextZones then
        callback:_layoutTextZones()
    end
end

-- Small-frame power bar (pet focus/energy/mana, target-of-target and
-- focus-target mana), as the stock small frames carry it. Built at spawn
-- ONLY under Blizzard Style, from the unit's own settings with the stock bar
-- geometry stamped over them, so it is not a user-positioned bar: the layout
-- pass owns its spot, size and art. Zero cost otherwise: the frame keeps no
-- Power widget (a WoW Forever pet builds its own user-positioned bar in
-- StyleSimpleFrame instead), so the engine registers no power channel and the
-- painter returns on the first field test, exactly as today.
function mod.UF_BlizzMiniPower(widget, unitToken, prefs)
    if not mod.UF_Blizz() or not widget.Health then
        return nil
    end
    local view = setmetatable(
        { powerPosition = "below", powerHeight = 7, powerWidth = 0 },
        { __index = prefs }
    )
    return CreatePowerBar(widget, unitToken, view)
end

-- The post-pass. Idempotent: geometry is re-asserted, regions exist once.
function mod.UF_ApplyBlizzardLayout(widget, unitToken)
    if not widget or not widget.Health then
        return
    end
    if InCombatLockdown() then
        return
    end
    unitToken = unitToken or widget._cuiBaseUnit or widget._cuiUnit
    -- Layout by unit + Portrait Side (stamped on the frame for the helpers).
    local G, mirror = mod.UF_BlizzResolve(widget, unitToken)
    if not G then
        return
    end
    local prefs = GetSettingsForUnit(unitToken)

    -- Frame: stock size + hit rect.
    widget:SetSize(G.w, G.h)
    local hit = G.hit
    if mirror then
        widget:SetHitRectInsets(hit[2], hit[1], hit[3], hit[4])
    else
        widget:SetHitRectInsets(hit[1], hit[2], hit[3], hit[4])
    end
    -- Frame Scale: the stock size is fixed, so the whole frame scales instead.
    -- A change re-seats the saved position (anchor offsets follow the scale);
    -- chained boss frames and unlock-anchored frames sit relative to their
    -- anchor and need nothing.
    local sc = prefs and prefs.blizzScale or 1
    if sc < 0.5 then
        sc = 0.5
    elseif sc > 2 then
        sc = 2
    end
    local prevScale = widget:GetScale()
    if prevScale ~= sc then
        widget:SetScale(sc)
        local posKey = unitToken:match("^boss%d$") and "boss" or unitToken
        if
            (posKey ~= "boss" or unitToken == "boss1")
            and not (CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(posKey))
        then
            ApplyFramePosition(widget, posKey)
        end
        -- Elements size-matched to the frame from another scale (bars on
        -- UIParent) re-pull its art width at the new scale; the frame's own
        -- size never changes, so no resize notify would reach them. Only on a
        -- real change: GetScale reads back float32, so most scales never
        -- compare equal to the setting.
        if
            math.abs(prevScale - sc) > 0.001
            and (posKey ~= "boss" or unitToken == "boss1")
            and CludesUI.ReapplyMatchPads
        then
            CludesUI.ReapplyMatchPads(posKey)
        end
    end
    if widget._barClip then
        widget._barClip:ClearAllPoints()
        widget._barClip:SetAllPoints(widget)
    end

    -- Hide Power Bar: a main frame's health bar takes the power track too.
    -- Stamped for the bar art pass, and for the art painter (the cut that a
    -- kit drawing its art over the bars needs, UF_PaintArtCut).
    local main = mod.UF_IsMainSettings(prefs)
    local merged = main and not G.small and G.power ~= nil and mod.UF_StockHidesPower(prefs)
    widget._blizzMerged = merged or nil
    widget._blizzMergeCut = (merged and G.merge) or nil

    -- Health bar at the stock position; the offsets the class power and
    -- scale passes read back are kept in step.
    local healthBar = widget.Health
    local clip = widget._barClip or widget
    local HB = merged and mod.UF_MergedHealth(G) or G.health
    healthBar:ClearAllPoints()
    mod.UF_BlizzPoint(healthBar, "TOPLEFT", clip, "TOPLEFT", HB.x, -HB.y, mirror)
    healthBar:SetSize(HB.w, HB.h)
    local hx = mirror and (G.w - HB.x - HB.w) or HB.x
    healthBar._xOffset = hx
    healthBar._rightInset = G.w - hx - HB.w
    healthBar._topOffset = HB.y

    -- Power bar: stock position when attached; detached bars keep their own
    -- spot (only the art changes); "none" stays hidden. The main frames' bar
    -- is always attached (ns.UF_PowerPos). The small frames carry the stock
    -- bar in the art's track, never a user-positioned one.
    local powerBar = widget.Power
    local ppPos = mod.UF_PowerPos(prefs)
    if powerBar and G.small then
        -- The stock power bar starts under the portrait ring and its mask
        -- rounds it off round the ring; mirrored it runs unmasked (masks
        -- cannot flip), so it stops where the health bar does instead.
        local px, pw = G.power.x, G.power.w
        if mirror and px < HB.x then
            pw = pw - (HB.x - px)
            px = HB.x
        end
        powerBar:ClearAllPoints()
        mod.UF_BlizzPoint(powerBar, "TOPLEFT", clip, "TOPLEFT", px, -G.power.y, mirror)
        powerBar:SetSize(pw, G.power.h)
        if powerBar._pbBorder then
            powerBar._pbBorder:Hide()
        end
        powerBar._blizzMasked = true
        powerBar:Show()
    elseif powerBar and ppPos ~= "none" then
        local detached = (ppPos == "detached_top" or ppPos == "detached_bottom")
        if not detached then
            powerBar:ClearAllPoints()
            mod.UF_BlizzPoint(powerBar, "TOPLEFT", clip, "TOPLEFT", G.power.x, -G.power.y, mirror)
            powerBar:SetSize(G.power.w, G.power.h)
            -- The art pass below seats the stock mask after the fill texture is set.
            powerBar._blizzMasked = true
        else
            powerBar._blizzMasked = nil
        end
        if powerBar._pbBorder then
            powerBar._pbBorder:Hide()
        end
    end
    -- Hide Power Bar: the bar stays down (the reload pass hides it for its
    -- "none" position; its text and Power element stand down with it there,
    -- through the power text and ns.UF_PowerElementSync).
    if merged and powerBar then
        powerBar:Hide()
    end

    mod.UF_ApplyBlizzFrameArt(widget, G)

    mod.UF_ApplyBlizzBarArt(widget)

    -- Absorb overlays share the bar's new footprint.
    local hp = widget.HealthPrediction and widget.HealthPrediction.damageAbsorb
    if hp then
        local hw, hh = healthBar:GetWidth(), healthBar:GetHeight()
        local barList = mod._ufBarScratch
        if not barList then
            barList = {}
            mod._ufBarScratch = barList
        end
        barList[1], barList[2], barList[3], barList[4], barList[5] = hp, hp._forward, hp._healAbsorb, nil, nil
        for index = 1, 3 do
            local scrollBar = barList[index]
            if scrollBar and scrollBar.SetSize then
                scrollBar:SetSize(hw, hh)
            end
        end
    end

    mod.UF_ApplyBlizzPortrait(widget, G)

    -- No CUI chrome: unified border and text bar step aside for the art.
    if widget.unifiedBorder then
        widget.unifiedBorder:Hide()
    end
    if widget.BottomTextBar then
        widget.BottomTextBar:Hide()
    end

    mod.UF_BlizzTextPass(widget)
    mod.UF_BlizzLevelPass(widget)
    -- Live text-position edits re-run the style's ApplyTextPositions directly;
    -- follow every call with the strip placement (wrapped once per frame).
    if widget._applyTextPositions and not widget._blizzTextWrapped then
        widget._blizzTextWrapped = true
        local orig = widget._applyTextPositions
        widget._applyTextPositions = function(s)
            orig(s)
            mod.UF_BlizzTextPass(widget)
            mod.UF_BlizzLevelPass(widget)
        end
    end
    if widget.Castbar then
        mod.UF_ApplyBlizzCastbar(widget.Castbar)
    end
end
