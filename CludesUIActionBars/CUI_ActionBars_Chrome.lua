if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_Chrome.lua
--
--  Bar chrome and end caps for the action bars and the extra bars. Loads
--  right after CUI_ActionBars_Events.lua and reads the main file through ns
--  only.
-------------------------------------------------------------------------------
local _, mod = ...
-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot.
local POOL = CludesUI._Pool

local _G = _G
local pairs = pairs
local min, max = math.min, math.max
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After

local ABAR, BAR_LOOKUP = mod.EAB, mod.BAR_LOOKUP
local Inner = mod._internals
local _fadeAlpha, extraBarHolders = Inner._fadeAlpha, Inner.extraBarHolders

-------------------------------------------------------------------------------
--  The action bars' chrome. Every action bar can
--  carry end caps, left, right or both (the End Caps checklist), in the
--  current look's art (the CludesUI style: the art the player picks), with
--  its own size and offsets. WoW Forever: the metal frame round a bar and the
--  dividers between its buttons (Bar Frame, on by default on Action
--  Bar 1 only) and the faction end caps (both sides on by default on Action
--  Bar 1 only), from Blizzard's own atlases (they draw the Forever art on
--  that client). Built per bar the first time a piece is on (LayoutBar's
--  tail, out of combat, stamp-gated); off, nothing is built and a built
--  piece hides. All on ns.
-------------------------------------------------------------------------------
mod.AB_FV_ART = {
    frame = "UI-HUD-ActionBar-Frame",
    -- Divider slices { start edge, end edge, middle } and the edges' depth
    -- along the divider: between the columns of a horizontal bar, then
    -- between the rows of a vertical one.
    divH = {
        "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeTop",
        "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeBottom",
        "!ui-hud-actionbar-frame-divider-ThreeSlice-Center",
        14,
        15,
    },
    divV = {
        "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeLeft",
        "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeRight",
        "_ui-hud-actionbar-frame-divider-ThreeSlice-Center",
        12,
        12,
    },
}

-- End caps per look: the art by faction (`art`, none while neutral) or the
-- same for every faction (`any`), the size at the icon size `unit` the art is
-- drawn for (caps only ever scale down, as Blizzard's do), the frame levels
-- over the bar (`lvl`), and the anchors { left point, bar point, x, y, right
-- point, bar point, x, y } for one row (near) and several (far, else near).
-- mid: anchored on the bar's side middles, else its bottom corners.
mod.AB_CAPS = {
    -- WoW Forever: inner edge 30 inside the bar's ends, 5 above its middle;
    -- over the buttons.
    forever = {
        unit = 45,
        w = 154,
        h = 95,
        lvl = 4,
        mid = true,
        art = {
            Alliance = { "ui-hud-actionbar-gryphon-left", "ui-hud-actionbar-gryphon-right" },
            Horde = { "ui-hud-actionbar-wyvern-left", "ui-hud-actionbar-wyvern-right" },
        },
        near = { "RIGHT", "LEFT", 30, 5, "LEFT", "RIGHT", -30, 5 },
    },
    -- Blizzard Style: retail's MainActionBar end caps, over the buttons' proc
    -- glows and assisted highlight as retail's are. stock: drawn through
    -- CludesUI.StockAtlas (retail art where the Forever client swaps it).
    blizzard = {
        unit = 45,
        w = 104.5,
        h = 98,
        lvl = 17,
        stock = true,
        near = { "BOTTOMRIGHT", "BOTTOMLEFT", 9, -22, "BOTTOMLEFT", "BOTTOMRIGHT", -8, -22 },
    },
    -- Classic WoW UI: vanilla's compact end caps (a file, the right one
    -- mirrored), out at the bar's corners on a bar of several rows.
    classic = {
        unit = 36,
        w = 128,
        h = 128,
        lvl = 17,
        file = true,
        any = {
            "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf",
            "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf",
        },
        near = { "BOTTOMRIGHT", "BOTTOMLEFT", 28, -3, "BOTTOMLEFT", "BOTTOMRIGHT", -29, -3 },
        far = { "BOTTOMRIGHT", "BOTTOMLEFT", 0, -3, "BOTTOMLEFT", "BOTTOMRIGHT", -1, -3 },
    },
}
mod.AB_CAPS.blizzard.art = mod.AB_CAPS.forever.art

-- Atlas presence, probed once per name (a piece the client lacks is skipped).
mod._abAtlas = {}
function mod.AB_AtlasOK(name)
    local val = mod._abAtlas[name]
    if val == nil then
        val = C_Texture.GetAtlasInfo(name) ~= nil
        mod._abAtlas[name] = val
    end
    return val
end

-- True when `art` (an CludesUI style End Caps art) draws on this client:
-- "blizzard", "classic", or "forever" -- the Forever client's own art, which
-- retail does not ship.
function mod.AB_CapsArtOK(art)
    return art == "blizzard" or art == "classic" or (art == "forever" and CludesUI.IS_FOREVER == true)
end

-- One of a bar's end cap settings (endCapArt, endCapScale, endCapOffsetX,
-- endCapOffsetY), nil = unset: the bar's own key, and on Action Bar 1 an
-- unset key reads the profile-wide key (cuiEndCaps for the art, the same
-- name for the rest), which nothing writes. A bar that carries one of Action
-- Bar 1's caps (the first-install span below) reads bar 1's where unset, so
-- the pair matches.
function mod.AB_CapsVal(key, k)
    local profile = ABAR.db and ABAR.db.profile
    if not profile then
        return nil
    end
    local cfg = profile.bars and profile.bars[key]
    local val = cfg and cfg[k]
    if val == nil then
        if key == "MainBar" then
            val = profile[(k == "endCapArt") and "cuiEndCaps" or k]
        elseif profile.endCapSpanLeft == key or profile.endCapSpanRight == key then
            val = mod.AB_CapsVal("MainBar", k)
        end
    end
    return val
end

-- Whether Action Bar 1's unset sides show caps under the current look: WoW
-- Forever while foreverHideEndCaps is off; Blizzard Style and Classic WoW UI
-- while showEndCaps; the CludesUI style while cuiEndCaps names art this
-- client draws.
function mod.AB_CapsMainDefault(profile)
    if mod.AB_Forever() then
        return profile.foreverHideEndCaps ~= true
    end
    if mod.AB_Style() == "cui" then
        return mod.AB_CapsArtOK(profile.cuiEndCaps)
    end
    return profile.showEndCaps == true
end

-- Which ends of a bar show caps (the End Caps checklist): the bar's own
-- endCapLeft / endCapRight. An unset side reads the bar's default: Action Bar
-- 1 follows the look (ns.AB_CapsMainDefault), both sides alike; every other
-- bar shows none. The first-install span (endCapSpanLeft / endCapSpanRight,
-- written by the Action Bars capture: the outermost bar in a row directly
-- beside bar 1 on that side) moves bar 1's default for that side onto the
-- named bar's same side. Checklist choices always win.
function mod.AB_CapsSides(key)
    local profile = ABAR.db and ABAR.db.profile
    local cfg = profile and profile.bars and profile.bars[key]
    if not cfg then
        return false, false
    end
    local left, right = cfg.endCapLeft, cfg.endCapRight
    if left == nil or right == nil then
        local sl, sr = profile.endCapSpanLeft, profile.endCapSpanRight
        local dl, dr = false, false
        if key == "MainBar" then
            local skinData = mod.AB_CapsMainDefault(profile)
            dl, dr = skinData and sl == nil, skinData and sr == nil
        elseif sl == key or sr == key then
            local skinData = mod.AB_CapsMainDefault(profile)
            dl, dr = skinData and sl == key, skinData and sr == key
        end
        if left == nil then
            left = dl
        end
        if right == nil then
            right = dr
        end
    end
    return left and true or false, right and true or false
end

-- The art the CludesUI style draws on a bar's caps: its End Caps cog
-- pick; none, or art this client lacks, reads Modern.
function mod.AB_CapsArt(key)
    local art = mod.AB_CapsVal(key, "endCapArt")
    if mod.AB_CapsArtOK(art) then
        return art
    end
    return "blizzard"
end

-- The look whose end caps a bar draws, then its left and right sides, or nil
-- while the bar shows neither side: WoW Forever's under that variant,
-- Blizzard Style's and Classic WoW UI's own, and under the CludesUI style
-- the art the player picks.
function mod.AB_CapsLook(key)
    local left, right = mod.AB_CapsSides(key)
    if not (left or right) then
        return nil
    end
    local style
    if mod.AB_Forever() then
        style = "forever"
    else
        style = mod.AB_Style()
        if style == "cui" then
            style = mod.AB_CapsArt(key)
        end
    end
    return style, left, right
end

-- A bar's end cap tweaks (the End Caps cog): the size as a fraction of the
-- look's own, the X/Y offsets (X mirrored: a positive value moves both caps
-- away from the bar; Y defaults to 5, the caps a little higher than the
-- look's own spot), and last the size in percent as stored.
function mod.AB_CapsTweak(key)
    local sc = mod.AB_CapsVal(key, "endCapScale") or 100
    return sc / 100, mod.AB_CapsVal(key, "endCapOffsetX") or 0, mod.AB_CapsVal(key, "endCapOffsetY") or 5, sc
end

-- Every chrome input of a bar in one string, for LayoutBar's stamp (the
-- tweaks only while a cap shows; "-" for a bar with no chrome).
function mod.AB_ChromeStamp(key)
    local style, left, right = mod.AB_CapsLook(key)
    local fv = mod.AB_ForeverBg(key)
    if not style then
        return fv and "fv" or "-"
    end
    local _, dx, dy, sc = mod.AB_CapsTweak(key)
    return style
        .. (left and "L" or "")
        .. (right and "R" or "")
        .. (fv and ",fv," or ",")
        .. sc
        .. ","
        .. dx
        .. ","
        .. dy
end

-- How far a bar's chrome reaches past a button grid gridH tall (top,
-- bottom), for a preview that must make room: WoW Forever's frame (6/5 at
-- button size / 45) and `look`'s caps (nil = none; multi = several rows)
-- with bar `key`'s tweaks. pxK scales the cap offsets (the preview's scale;
-- nil = 1).
function mod.AB_ChromeReach(btnW, gridH, forever, style, multi, pxK, key)
    local topY, bottom = 0, 0
    if forever then
        topY, bottom = 6 * btnW / 45, 5 * btnW / 45
    end
    local c = style and mod.AB_CAPS[style]
    if c then
        local sc, _, dy = mod.AB_CapsTweak(key)
        dy = dy * (pxK or 1)
        local kc = min(btnW / c.unit, 1) * sc
        local posY = ((multi and c.far) or c.near)[4]
        if c.mid then
            topY = max(topY, (c.h / 2 + posY) * kc - gridH / 2 + dy)
            bottom = max(bottom, (c.h / 2 - posY) * kc - gridH / 2 - dy)
        else
            topY = max(topY, (c.h + posY) * kc - gridH + dy)
            bottom = max(bottom, -posY * kc - dy)
        end
    end
    return topY, bottom
end

-- One cap's art: a file (the right cap mirrored) or an atlas (a stock
-- look's through CludesUI.StockAtlas).
function mod.AB_SetCapArt(texture, cfg, name, right)
    if cfg.file then
        texture:SetTexture(name)
        if right then
            texture:SetTexCoord(1, 0, 0, 1)
        else
            texture:SetTexCoord(0, 1, 0, 1)
        end
    elseif cfg.stock then
        -- The art can switch live on the same textures (the CludesUI style's
        -- End Caps choice): clear a previous look's mirror or sheet coords first.
        texture:SetTexCoord(0, 1, 0, 1)
        CludesUI.StockAtlas(texture, name)
    else
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetAtlas(name)
    end
end

-- Paints the caps' art for the player's faction onto a chrome state (the
-- same art for every faction on a look with `any`), each side shown only
-- while the bar asks for it. True once the art no longer waits on the
-- faction (kept as st.capKnown).
function mod.AB_CapsFaction(st)
    local capL, capR = st.capL, st.capR
    if not capL then
        return true
    end
    local c = st.capsOn and mod.AB_CAPS[st.capLook]
    local fac = c and c.art and UnitFactionGroup("player")
    local set = c and (c.any or (fac and c.art[fac])) or nil
    if set and st.capSet ~= set then
        mod.AB_SetCapArt(capL, c, set[1], false)
        mod.AB_SetCapArt(capR, c, set[2], true)
        st.capSet = set
    end
    capL:SetShown(set ~= nil and st.capSideL == true)
    capR:SetShown(set ~= nil and st.capSideR == true)
    st.capKnown = not (c and c.art) or fac ~= nil
    return st.capKnown
end

-- Paints `look`'s end caps (nil = none) onto st (a state table the caller
-- keeps) round a button grid w x h whose TOPLEFT sits at (ox, oy) off
-- owner's TOPLEFT; btnW = the button size, multi = several rows, sideL /
-- sideR = the ends that show a cap. The caps sit the look's lvl over owner
-- (under Action Bar 1's paging arrows), scale with the icon size (down only)
-- times bar `key`'s size, and move by its offsets (times pxK, the preview's
-- scale; nil = 1).
function mod.AB_PaintCaps(st, ownerFrame, ox, oy, wid, hgt, btnW, style, multi, pxK, key, sideL, sideR)
    local c = style and mod.AB_CAPS[style]
    st.capsOn = (c and (sideL or sideR) and (c.any or mod.AB_AtlasOK(c.art.Alliance[1]))) and true or false
    st.capSideL, st.capSideR = sideL and true or false, sideR and true or false
    local owner = st.capHost
    if not st.capsOn then
        if owner then
            owner:Hide()
        end
        return
    end
    if not owner then
        -- Through the options page pool: the options preview builds its chrome on a
        -- frame of that pool, which hands it to the preview's next build; on a
        -- live bar this is CreateFrame.
        owner = POOL.CreateFrame("Frame", nil, ownerFrame)
        st.capL = owner:CreateTexture(nil, "OVERLAY", nil, 5)
        st.capR = owner:CreateTexture(nil, "OVERLAY", nil, 5)
        st.capHost = owner
    end
    local sc, dx, dy = mod.AB_CapsTweak(key)
    local kc = btnW / c.unit
    if kc > 1 then
        kc = 1
    end
    kc = kc * sc
    -- The offsets in the host's (scaled) units.
    dx, dy = dx * (pxK or 1) / kc, dy * (pxK or 1) / kc
    local g = (multi and c.far) or c.near
    if st.capLook ~= style or st.capGeo ~= g or st.capDX ~= dx or st.capDY ~= dy then
        local capL, capR = st.capL, st.capR
        capL:SetSize(c.w, c.h)
        capR:SetSize(c.w, c.h)
        capL:ClearAllPoints()
        capR:ClearAllPoints()
        capL:SetPoint(g[1], owner, g[2], g[3] - dx, g[4] + dy)
        capR:SetPoint(g[5], owner, g[6], g[7] + dx, g[8] + dy)
        if st.capLook ~= style then
            st.capSet = nil
        end
        st.capLook, st.capGeo, st.capDX, st.capDY = style, g, dx, dy
    end
    owner:SetFrameLevel(ownerFrame:GetFrameLevel() + c.lvl)
    owner:SetScale(kc)
    owner:ClearAllPoints()
    owner:SetPoint("TOPLEFT", ownerFrame, "TOPLEFT", ox / kc, oy / kc)
    owner:SetSize(wid / kc, hgt / kc)
    owner:Show()
end

function mod.AB_HideBarChrome(st)
    if st.under then
        st.under:Hide()
    end
    if st.capHost then
        st.capHost:Hide()
    end
    st.capsOn = false
end

-- Paints WoW Forever's frame and dividers onto st (a state table the caller
-- keeps) round a button grid w x h whose TOPLEFT sits at (ox, oy) off
-- owner's TOPLEFT. k = button size / 45 (Blizzard scales the art with the
-- icon size). n = the buttons along the bar when it runs as one line at
-- Blizzard's divider spacing, else 0; step = the distance between button
-- starts along it; the first `extra` buttons carry one onePx more. Both sit
-- on a frame one level under owner (under the buttons).
function mod.AB_PaintForeverChrome(st, ownerFrame, ox, oy, wid, hgt, scale, vertical, num, step, extra, onePx)
    local ART = mod.AB_FV_ART
    local lvl = ownerFrame:GetFrameLevel()

    -- Under the buttons, in 45px-button units.
    local under = st.under
    if not under then
        -- Through the options page pool, as the caps' host (AB_PaintCaps).
        under = POOL.CreateFrame("Frame", nil, ownerFrame)
        st.under = under
        st.divs = {}
    end
    under:SetFrameLevel(lvl > 0 and lvl - 1 or 0)
    under:SetScale(scale)
    under:ClearAllPoints()
    under:SetPoint("TOPLEFT", ownerFrame, "TOPLEFT", ox / scale, oy / scale)
    under:SetSize(wid / scale, hgt / scale)
    under:Show()

    local border = st.border
    if not border and mod.AB_AtlasOK(ART.frame) then
        border = under:CreateTexture(nil, "BACKGROUND", nil, -3)
        border:SetAtlas(ART.frame)
        border:SetPoint("TOPLEFT", under, "TOPLEFT", -6, 6)
        border:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT", 4, -5)
        st.border = border
    end

    -- Dividers: one per pair of neighbours; a divider's end edge overlaps
    -- the later button by 5 (the flared ends fill the rings' corners).
    -- Unlike the frame they keep their native size whatever the icon size
    -- (12 across, 5 of overlap, the edges at the atlas depth), so in the
    -- under frame's units every one of those divides by k.
    local ik = 1 / scale
    local set = vertical and ART.divV or ART.divH
    if num > 1 and not (mod.AB_AtlasOK(set[1]) and mod.AB_AtlasOK(set[2]) and mod.AB_AtlasOK(set[3])) then
        num = 0
    end
    local divs = st.divs
    for index = 1, num - 1 do
        local skinData = divs[index]
        if not skinData then
            skinData = {
                under:CreateTexture(nil, "BACKGROUND", nil, -2),
                under:CreateTexture(nil, "BACKGROUND", nil, -2),
                under:CreateTexture(nil, "BACKGROUND", nil, -2),
            }
            divs[index] = skinData
        end
        local a, b, c = skinData[1], skinData[2], skinData[3]
        if skinData.set ~= set then
            a:SetAtlas(set[1])
            b:SetAtlas(set[2])
            c:SetAtlas(set[3])
            skinData.set = set
        end
        local at = (index * step + (index < extra and index or extra) * onePx) / scale
        a:ClearAllPoints()
        b:ClearAllPoints()
        c:ClearAllPoints()
        if vertical then
            a:SetSize(set[4] * ik, 12 * ik)
            b:SetSize(set[5] * ik, 12 * ik)
            a:SetPoint("TOPLEFT", under, "TOPLEFT", 0, 7 * ik - at)
            b:SetPoint("TOPRIGHT", under, "TOPRIGHT", 0, 7 * ik - at)
            c:SetPoint("TOPLEFT", a, "TOPRIGHT")
            c:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT")
        else
            a:SetSize(12 * ik, set[4] * ik)
            b:SetSize(12 * ik, set[5] * ik)
            a:SetPoint("TOPLEFT", under, "TOPLEFT", at - 7 * ik, 0)
            b:SetPoint("BOTTOMLEFT", under, "BOTTOMLEFT", at - 7 * ik, 0)
            c:SetPoint("TOPLEFT", a, "BOTTOMLEFT")
            c:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT")
        end
        a:Show()
        b:Show()
        c:Show()
    end
    for index = (num > 1 and num or 1), #divs do
        local skinData = divs[index]
        skinData[1]:Hide()
        skinData[2]:Hide()
        skinData[3]:Hide()
    end
end

-- A bar's chrome onto st, for the live bar and the options preview: WoW
-- Forever's frame and dividers when `forever`, then `look`'s end caps (nil =
-- none) on the sideL / sideR ends. Arguments as AB_PaintForeverChrome and
-- AB_PaintCaps. True once the caps' art no longer waits on the faction.
function mod.AB_PaintBarChrome(
    st,
    ownerFrame,
    ox,
    oy,
    wid,
    hgt,
    btnW,
    forever,
    style,
    multi,
    vertical,
    num,
    step,
    extra,
    onePx,
    pxK,
    key,
    sideL,
    sideR
)
    if forever then
        mod.AB_PaintForeverChrome(
            st,
            ownerFrame,
            ox,
            oy,
            wid,
            hgt,
            btnW / 45,
            vertical,
            num,
            step,
            extra,
            onePx
        )
    elseif st.under then
        st.under:Hide()
    end
    mod.AB_PaintCaps(st, ownerFrame, ox, oy, wid, hgt, btnW, style, multi, pxK, key, sideL, sideR)
    return mod.AB_CapsFaction(st)
end

-- The faction listener every bar's caps share: registered only while some
-- bar shows faction caps -- for the pick a neutral character makes, and for
-- one loading screen while a bar's faction art still waits. Runs after a
-- bar's chrome changes (LayoutBar's tail), never per event otherwise.
function mod.AB_CapsEvSync()
    local need, waiting = false, false
    local all = mod._abChrome
    if all then
        for _, st in pairs(all) do
            local c = st.capsOn and mod.AB_CAPS[st.capLook]
            if c and c.art then
                need = true
                if not st.capKnown then
                    waiting = true
                end
            end
        end
    end
    local ev = mod._abCapsEv
    if not need then
        if ev then
            ev:UnregisterAllEvents()
        end
        return
    end
    if not ev then
        ev = mod.TakeShell()
        ev:SetScript("OnEvent", function(self, evt)
            local known = true
            for _, cs in pairs(mod._abChrome) do
                if not mod.AB_CapsFaction(cs) then
                    known = false
                end
            end
            if known and evt == "PLAYER_ENTERING_WORLD" then
                self:UnregisterEvent(evt)
            end
        end)
        mod._abCapsEv = ev
    end
    ev:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
    if waiting then
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        ev:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end

-- A bar's chrome, from LayoutBar's tail: WoW Forever's frame and dividers
-- (Bar Frame), and the bar's end caps on a horizontal bar. Each
-- bar keeps its own state (ns._abChrome[key]), built the first time it shows
-- either piece.
function mod.AB_ApplyBarChrome(key, widget, wid, hgt, btnW, vertical, multi, num, step, extra, onePx)
    local all = mod._abChrome
    local st = all and all[key]
    local fv = mod.AB_ForeverBg(key)
    local style, sideL, sideR
    if not vertical then
        style, sideL, sideR = mod.AB_CapsLook(key)
    end
    if not (fv or style) then
        if st then
            mod.AB_HideBarChrome(st)
            mod.AB_CapsEvSync()
        end
        return
    end
    if not all then
        all = {}
        mod._abChrome = all
    end
    if not st then
        st = {}
        all[key] = st
    end
    mod.AB_PaintBarChrome(
        st,
        widget,
        0,
        0,
        wid,
        hgt,
        btnW,
        fv,
        style,
        multi,
        vertical,
        num,
        step,
        extra,
        onePx,
        nil,
        key,
        sideL,
        sideR
    )
    mod.AB_CapsEvSync()
end

-------------------------------------------------------------------------------
--  End caps on the micro menu and the bag bar. Both are Blizzard frames EAB
--  only follows, so their caps are painted (the painter above, the same keys
--  and checklist as an action bar) onto the bar's follower frame
--  (extraBarHolders, our own), never into Blizzard's tree. They take Action Bar
--  1's button size (neither bar has one), the strata and level of the frame
--  that holds the buttons (so they draw over them as bar 1's do), and the
--  Blizzard frame's alpha through the fader's twin. Shown state follows EAB's
--  own hides (the follower hides with them; SetManagedBlizzOwnedSuppressed
--  reports its own, Data Bars' micro menu hider too), the micro menu's docking
--  (a secure post-hook) and WoW Forever's interface-style switch (its event,
--  one frame later): never an OnShow hook, since Blizzard shows and hides
--  these frames inside functions that go on to call protected ones. The micro
--  menu's caps sit on the buttons' own rect (retail's container also keeps
--  the queue eye's slot), the bag bar's on its shown buttons (retail's bar
--  keeps its length while collapsed). Nothing runs until a side shows.
-------------------------------------------------------------------------------
mod.AB_CAP_EXTRAS = { MicroBar = true, BagBar = true }

-- The frame whose level the buttons ride on.
function mod.AB_ExtraCapsBase(key)
    if key == "MicroBar" then
        return _G.MicroMenu
    end
    return _G.BagsBar
end

-- Edit Mode laid the bar out vertically: no caps (as a vertical action bar).
function mod.AB_ExtraCapsVertical(key)
    local frame = mod.AB_ExtraCapsBase(key)
    return frame ~= nil and frame.isHorizontal == false
end

function mod.AB_ExtraCapsShown(key)
    local st = mod._abChrome and mod._abChrome[key]
    local owner = st and st.capHost
    if not owner then
        return
    end
    local bf = _G[BAR_LOOKUP[key].frameName]
    local enabled = st.capsOn and bf ~= nil and bf:IsShown()
    if enabled and key == "MicroBar" then
        -- Docked into a vehicle or pet battle frame: the container is empty.
        local m = _G.MicroMenu
        enabled = m ~= nil and m:GetParent() == bf and m:IsShown()
    end
    owner:SetShown(enabled and true or false)
end

-- After EAB itself hid or showed one of the two Blizzard frames.
function mod.AB_ExtraCapsFor(widget)
    if not mod._abCapHooked then
        return
    end
    if widget == _G.MicroMenuContainer then
        mod.AB_ExtraCapsShown("MicroBar")
    elseif widget == _G.BagsBar then
        mod.AB_ExtraCapsShown("BagBar")
    end
end

-- Once per bar, the first time its caps show (a secure post-hook cannot be
-- removed; with no caps it returns at the missing layer).
function mod.AB_ExtraCapsHooks(key)
    local done = mod._abCapHooked or {}
    mod._abCapHooked = done
    if done[key] then
        return
    end
    done[key] = true
    local m = _G.MicroMenu
    if key == "MicroBar" and m and m.OverrideMicroMenuPosition then
        hooksecurefunc(m, "OverrideMicroMenuPosition", function()
            mod.AB_ExtraCapsShown("MicroBar")
        end)
    end
end

-- WoW Forever's interface-style switch (keyboard and mouse vs controller)
-- hides and shows both Blizzard frames (INPUT_DEVICE_INTERFACE_TRANSITION):
-- the shown state is re-read one frame later, listened to only while either
-- bar shows caps. Retail's frames never follow that switch.
function mod.AB_ExtraCapsPadFlush()
    mod._abCapStyleArmed = nil
    mod.AB_ExtraCapsShown("MicroBar")
    mod.AB_ExtraCapsShown("BagBar")
end
function mod.AB_ExtraCapsPad()
    if not CludesUI.IS_FOREVER then
        return
    end
    local all = mod._abChrome
    local enabled = all and ((all.MicroBar and all.MicroBar.capsOn) or (all.BagBar and all.BagBar.capsOn))
    local ev = mod._abCapStyleEv
    if not enabled then
        if ev then
            ev:UnregisterAllEvents()
        end
        return
    end
    if not ev then
        if
            C_EventUtils
            and C_EventUtils.IsEventValid
            and not C_EventUtils.IsEventValid("INPUT_DEVICE_INTERFACE_TRANSITION")
        then
            return
        end
        ev = mod.TakeShell()
        ev:SetScript("OnEvent", function()
            if mod._abCapStyleArmed then
                return
            end
            mod._abCapStyleArmed = true
            C_Timer_After(0, mod.AB_ExtraCapsPadFlush)
        end)
        mod._abCapStyleEv = ev
    end
    ev:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
end

-- Retail's bag bar keeps its full length while collapsed (the expand arrow
-- only hides the bag slots), so its caps sit on the shown buttons: their
-- left edge and width in follower units, nil = the whole follower. WoW
-- Forever hides that arrow, so its bar never collapses.
function mod.AB_BagEdge(widget, hs, highlight, minL, maxR)
    if widget and widget:IsShown() then
        local left, right = widget:GetLeft(), widget:GetRight()
        if left and right then
            local k = widget:GetEffectiveScale() / hs
            left, right = left * k - highlight, right * k - highlight
            if not minL or left < minL then
                minL = left
            end
            if not maxR or right > maxR then
                maxR = right
            end
        end
    end
    return minL, maxR
end
function mod.AB_BagCapsExtent(holderFrame)
    local bb, mgr = _G.BagsBar, _G.MainMenuBarBagManager
    if not bb or bb.hideExpandToggle or not (mgr and mgr.EnumerateBagButtons) then
        return nil
    end
    local hs, highlight = holderFrame:GetEffectiveScale(), holderFrame:GetLeft()
    if not highlight then
        return nil
    end
    local minL, maxR = mod.AB_BagEdge(_G.BagBarExpandToggle, hs, highlight, nil, nil)
    for _, btn in mgr:EnumerateBagButtons() do
        minL, maxR = mod.AB_BagEdge(btn, hs, highlight, minL, maxR)
    end
    if not minL or maxR - minL < 1 then
        return nil
    end
    return minL, maxR - minL
end
-- Collapsing or expanding the bag bar repaints its caps (one frame later,
-- after Blizzard's own relayout), listened to only while it shows caps.
function mod.AB_BagCapsExpandFlush()
    mod._abBagArmed = nil
    mod.AB_ExtraCaps("BagBar")
end
function mod.AB_BagCapsExpandChanged()
    if mod._abBagArmed then
        return
    end
    mod._abBagArmed = true
    C_Timer_After(0, mod.AB_BagCapsExpandFlush)
end
function mod.AB_BagCapsWatch(enabled)
    local bb = _G.BagsBar
    if not (bb and not bb.hideExpandToggle and EventRegistry) then
        return
    end
    if enabled then
        if not mod._abBagWatch then
            mod._abBagWatch = true
            EventRegistry:RegisterCallback(
                "MainMenuBarManager.OnExpandChanged",
                mod.AB_BagCapsExpandChanged,
                mod.AB_CAP_EXTRAS
            )
        end
    elseif mod._abBagWatch then
        mod._abBagWatch = nil
        EventRegistry:UnregisterCallback("MainMenuBarManager.OnExpandChanged", mod.AB_CAP_EXTRAS)
    end
end

-- Paints (or clears) a bar's caps. Stamp-gated on every input the paint
-- reads; the shown state is re-read every call.
function mod.AB_ExtraCaps(key)
    local holderFrame = extraBarHolders[key]
    local bf = holderFrame and _G[BAR_LOOKUP[key].frameName]
    if not bf then
        return
    end
    local all = mod._abChrome
    local st = all and all[key]
    local style, sL, sR
    if not mod.AB_ExtraCapsVertical(key) then
        style, sL, sR = mod.AB_CapsLook(key)
    end
    if not style then
        if st and st.capsOn then
            mod.AB_HideBarChrome(st)
            if mod._abFadeTwin then
                mod._abFadeTwin[bf] = nil
            end
            mod.AB_CapsEvSync()
            mod.AB_ExtraCapsPad()
            if key == "BagBar" then
                mod.AB_BagCapsWatch(false)
            end
        end
        return
    end
    if not all then
        all = {}
        mod._abChrome = all
    end
    if not st then
        st = {}
        all[key] = st
    end
    local base = mod.AB_ExtraCapsBase(key) or bf
    local lvl, strata = base:GetFrameLevel(), base:GetFrameStrata()
    local ownerFrame, ox = holderFrame, 0
    local wid, hgt, u = holderFrame:GetWidth(), holderFrame:GetHeight(), mod._abMainBtnW or 45
    local m = (key == "MicroBar") and _G.MicroMenu
    if m then
        -- The buttons' own rect, on a frame of ours anchored to it: it follows
        -- a corner flip of the menu in its container by itself.
        ownerFrame = st.xOwner
        if not ownerFrame then
            ownerFrame = CreateFrame("Frame", nil, holderFrame)
            ownerFrame:SetPoint("TOPLEFT", m, "TOPLEFT")
            ownerFrame:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT")
            st.xOwner = ownerFrame
        end
        local k = m:GetEffectiveScale() / holderFrame:GetEffectiveScale()
        wid, hgt = m:GetWidth() * k, m:GetHeight() * k
    elseif key == "BagBar" then
        local l, bw = mod.AB_BagCapsExtent(holderFrame)
        if l then
            ox, wid = l, bw
        end
    end
    local sc, dx, dy = mod.AB_CapsTweak(key)
    if
        not st.capsOn
        or st.xLook ~= style
        or st.xL ~= sL
        or st.xR ~= sR
        or st.xW ~= wid
        or st.xH ~= hgt
        or st.xU ~= u
        or st.xS ~= sc
        or st.xDX ~= dx
        or st.xDY ~= dy
        or st.xLvl ~= lvl
        or st.xStr ~= strata
        or st.xOX ~= ox
    then
        if holderFrame:GetFrameStrata() ~= strata then
            holderFrame:SetFrameStrata(strata)
        end
        holderFrame:SetFrameLevel(lvl)
        if ownerFrame ~= holderFrame then
            if ownerFrame:GetFrameStrata() ~= strata then
                ownerFrame:SetFrameStrata(strata)
            end
            ownerFrame:SetFrameLevel(lvl)
        end
        mod.AB_PaintCaps(st, ownerFrame, ox, 0, wid, hgt, u, style, false, nil, key, sL, sR)
        mod.AB_CapsFaction(st)
        st.xLook, st.xL, st.xR, st.xW, st.xH, st.xU = style, sL, sR, wid, hgt, u
        st.xS, st.xDX, st.xDY, st.xLvl, st.xStr, st.xOX = sc, dx, dy, lvl, strata, ox
        local tw = mod._abFadeTwin
        if not tw then
            tw = setmetatable({}, { __mode = "k" })
            mod._abFadeTwin = tw
        end
        tw[bf] = st.capsOn and st.capHost or nil
        if st.capHost then
            st.capHost:SetAlpha(_fadeAlpha[bf] or 1)
        end
        if st.capsOn then
            mod.AB_ExtraCapsHooks(key)
        end
        mod.AB_CapsEvSync()
        mod.AB_ExtraCapsPad()
        if key == "BagBar" then
            mod.AB_BagCapsWatch(st.capsOn)
        end
    end
    mod.AB_ExtraCapsShown(key)
end

function mod.AB_ExtraCapsAll()
    mod.AB_ExtraCaps("MicroBar")
    mod.AB_ExtraCaps("BagBar")
end

-- Repaints the bars that carry Action Bar 1's caps (its cap settings reach them).
function mod.AB_CapsSpanApply()
    local profile = ABAR.db and ABAR.db.profile
    if not profile then
        return
    end
    local left, right = profile.endCapSpanLeft, profile.endCapSpanRight
    for index = 1, 2 do
        local k = (index == 1) and left or right
        if k and not (index == 2 and k == left) then
            if mod.AB_CAP_EXTRAS[k] then
                mod.AB_ExtraCaps(k)
            else
                ABAR:ApplyPaddingForBar(k)
            end
        end
    end
end
