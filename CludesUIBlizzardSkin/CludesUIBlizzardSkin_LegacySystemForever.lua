if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Progress Legacy on WoW Forever
--
--  Forever's Progress Legacy window is LegacySystemFrame (the load-on-demand
--  Blizzard_LegacySystem addon): a metal portrait window with three side tabs
--  (Reward Track / Challenge / Tree) over its content pages. This skins it under
--  its own card and key ("legacysystem", enable key reskinLegacySystem): the
--  metal frame, tile streaks and backdrop faded under the shell and border, the
--  portrait removed, the close button and title, the side tabs, and the pages'
--  text. Skinned only while the card is CludesUI or Modern; Blizz Default
--  leaves Blizzard's window as is. Forever only.
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
local CludesUI = _G.CludesUI
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
local Skin = mod.WSkin
if not (Skin and Skin.RegisterWindow and Skin.Shell) then
    return
end

do
    -- Chrome atlases covering the shell: the metal frame and textured backdrops.
    local FADE = {
        "ui-frame-metal",
        "ui-frame-portraitmetal",
        "toptilestreaks",
        "gamepad-uiframemetal",
        "legacy-rewards-tracker-background",
    }
    local SIDE_TABS = { "LegacyRewardTrackTab", "LegacyChallengeTab", "LegacyTreeTab" }
    -- Content pages the tabs swap between; each repaints the window when shown.
    local PAGES = { "RewardTrackPage", "ChallengesPage" }

    local function FadeArt(fr, depth)
        if depth > 5 or not fr or fr:IsForbidden() then
            return
        end
        if depth > 0 and Skin.IsForeignFrame(fr) then
            return
        end
        local regions = { fr:GetRegions() }
        for idx = 1, #regions do
            local r = regions[idx]
            local a = r.GetAtlas and r:GetAtlas()
            if a then
                local la = a:lower()
                for _, wid in ipairs(FADE) do
                    if la:find(wid, 1, true) then
                        r:SetAlpha(0)
                        break
                    end
                end
            end
        end
        local children = { fr:GetChildren() }
        for idx = 1, #children do
            FadeArt(children[idx], depth + 1)
        end
    end

    -- House font on every FontString under a page (the reward-track points, labels
    -- and progress), refreshed on each show.
    local function FontKids(fr, depth)
        if depth > 4 or not fr or fr:IsForbidden() then
            return
        end
        if depth > 0 and Skin.IsForeignFrame(fr) then
            return
        end
        local regions = { fr:GetRegions() }
        for idx = 1, #regions do
            local r = regions[idx]
            if r:GetObjectType() == "FontString" then
                Skin.Font(r)
            end
        end
        local children = { fr:GetChildren() }
        for idx = 1, #children do
            FontKids(children[idx], depth + 1)
        end
    end

    -- Gated on the card's style: the engine never applies an "off" (Blizz Default)
    -- window, and this gate keeps the show hooks below inert too when the card is
    -- switched to Blizz Default before the reload.
    local Skin_LegacySystem = Skin.WindowCallback("legacysystem", function()
        local f = _G.LegacySystemFrame
        if not f then
            return
        end
        Skin.Shell("legacysystem", f)
        Skin.RemovePortrait(f)
        Skin.CommonChrome(f, "LegacySystemFrame")
        -- The window's own file-texture backdrop, which the shell does not catch.
        if _G.LegacySystemFrameBg then
            _G.LegacySystemFrameBg:SetAlpha(0)
        end
        FadeArt(f, 0)
        Skin.CloseButton(f.CloseButton or _G.LegacySystemFrameCloseButton)
        local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.LegacySystemFrameTitleText
        if title then
            Skin.Font(title)
            Skin.White(title)
        end
        for _, tn in ipairs(SIDE_TABS) do
            Skin.SideTab(f[tn])
        end
        for _, pn in ipairs(PAGES) do
            if f[pn] then
                FontKids(f[pn], 0)
            end
        end
    end)

    -- Re-skin on show and when a tab swaps a content page in (HookShow hooks each
    -- frame once).
    local function InstallHooks()
        local f = _G.LegacySystemFrame
        if not f then
            return
        end
        local repaint = Skin.Debounce(Skin_LegacySystem)
        Skin.HookShow(f, repaint)
        for _, pn in ipairs(PAGES) do
            if f[pn] then
                Skin.HookShow(f[pn], repaint)
            end
        end
    end

    Skin.RegisterWindow({
        key = "legacysystem",
        apply = function()
            Skin_LegacySystem()
            InstallHooks()
        end,
        addons = { Blizzard_LegacySystem = true },
    })
end -- Progress Legacy pack do-block
