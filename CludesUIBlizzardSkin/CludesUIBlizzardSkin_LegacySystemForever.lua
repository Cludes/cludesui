if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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
local CUI = _G.CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
local Skin = mod.WSkin
if not (Skin and Skin.RegisterWindow and Skin.Shell) then return end

do
    -- Chrome atlases covering the shell: the metal frame and textured backdrops.
    local FADE = {
        "ui-frame-metal",
        "ui-frame-portraitmetal",
        "toptilestreaks",
        "gamepad-uiframemetal",
        "legacy-rewards-tracker-background",
        -- The Legacy Tree page: its parchment, divider, points bar, level
        -- circle, the category cards down its left and the nodes' boxes.
        "legacy-tree-frame-background",
        "legacy-tree-frame-divider",
        "legacy-tree-frame-points-bar",
        "legacy-tree-frame-level-circle",
        "legacy-tree-frame-card",
        "talents-square-box",
        -- The Progress Track and Challenges: the bar's bronze frame and its
        -- trough, the challenge cards' art, ribbons and date plates, the
        -- icons' bronze frames.
        "legacy-progressbar-frame",
        "legacy-progressbar-bg",
        "legacy-challenge-cards",
        "legacy-tree-frame-icon-frame",
    }
    local SIDE_TABS = { "LegacyRewardTrackTab", "LegacyChallengeTab", "LegacyTreeTab" }
    -- Content pages the tabs swap between; each repaints the window when shown.
    local PAGES = { "RewardTrackPage", "ChallengesPage", "TreePage" }

    -- The Tree page's controls: Apply Changes and the search box in the house
    -- look, a flat panel behind the tree.
    local function SkinTreePage(page)
        if not page then return end
        local panel = page.LegacyTreeTraitPanel
        if panel then
            if panel.ApplyButton then Skin.Button(panel.ApplyButton) end
            if panel.SearchBox then Skin.EditBox(panel.SearchBox) end
            if not Skin.GetFFD(panel).cuiPanel then
                Skin.GetFFD(panel).cuiPanel = true
                Skin.Panel(panel)
            end
        end
        if page.SearchBox then Skin.EditBox(page.SearchBox) end
    end

    -- Legacy progress bars: a flat accent fill on a dark trough with a 1 px
    -- border (the bronze frame and trough are faded by the list above).
    local function SkinBar(bar)
        if not (bar and bar.SetStatusBarTexture) or Skin.GetFFD(bar).cuiBar then return end
        Skin.GetFFD(bar).cuiBar = true
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        if Skin.ApplyBarFill then Skin.ApplyBarFill(bar) end
        local trough = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
        trough:SetAllPoints()
        trough:SetColorTexture(0, 0, 0, 0.5)
        if Skin.AddBorder then Skin.AddBorder(bar, 0, 0, 0, 1) end
    end

    -- The cards the pages build as they show (reward cards, challenge cards):
    -- their art goes and each is a flat house panel; bars inside are skinned.
    local function SkinCards(found, depth)
        if depth > 6 or not found or found:IsForbidden() then return end
        if found.RewardCardBG or (found.Background and found.TitleBar) or found.ProgressBarFrame then
            if found.RewardCardBG then
                found.RewardCardBG:SetAlpha(0)
                if found.LevelSquare then found.LevelSquare:SetAlpha(0) end
                if found.IconBorder then found.IconBorder:SetAlpha(0) end
            end
            if found.ProgressBarFrame then
                SkinBar(found)
            elseif not Skin.GetFFD(found).cuiCard then
                -- A flat backdrop and 1 px border under the card's own icon
                -- and text (Skin.Panel would fade the reward's icon too).
                Skin.GetFFD(found).cuiCard = true
                local back = found:CreateTexture(nil, "BACKGROUND", nil, -7)
                back:SetAllPoints()
                back:SetColorTexture(0, 0, 0, 0.35)
                if Skin.AddBorder then Skin.AddBorder(found) end
            end
        end
        if found.LegacyRewardProgressBar then SkinBar(found.LegacyRewardProgressBar) end
        if found.ProgressBar and found.ProgressBar.SetStatusBarTexture then SkinBar(found.ProgressBar) end
        local children = { found:GetChildren() }
        for idx = 1, #children do
            SkinCards(children[idx], depth + 1)
        end
    end

    local function FadeArt(found, depth)
        if depth > 5 or not found or found:IsForbidden() then return end
        if depth > 0 and Skin.IsForeignFrame(found) then return end
        local regionList = { found:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            local a = region.GetAtlas and region:GetAtlas()
            if a then
                local la = a:lower()
                for _, wid in ipairs(FADE) do
                    if la:find(wid, 1, true) then
                        region:SetAlpha(0)
                        break
                    end
                end
            end
        end
        local children = { found:GetChildren() }
        for idx = 1, #children do
            FadeArt(children[idx], depth + 1)
        end
    end

    -- House font on every FontString under a page (the reward-track points, labels
    -- and progress), refreshed on each show.
    local function FontKids(found, depth)
        if depth > 4 or not found or found:IsForbidden() then return end
        if depth > 0 and Skin.IsForeignFrame(found) then return end
        local regionList = { found:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region:GetObjectType() == "FontString" then Skin.Font(region) end
        end
        local children = { found:GetChildren() }
        for idx = 1, #children do
            FontKids(children[idx], depth + 1)
        end
    end

    -- Gated on the card's style: the engine never applies an "off" (Blizz Default)
    -- window, and this gate keeps the show hooks below inert too when the card is
    -- switched to Blizz Default before the reload.
    local Skin_LegacySystem = Skin.WindowCallback("legacysystem", function()
        local frame = _G.LegacySystemFrame
        if not frame then return end
        Skin.Shell("legacysystem", frame)
        Skin.RemovePortrait(frame)
        Skin.CommonChrome(frame, "LegacySystemFrame")
        -- The window's own file-texture backdrop, which the shell does not catch.
        if _G.LegacySystemFrameBg then _G.LegacySystemFrameBg:SetAlpha(0) end
        FadeArt(frame, 0)
        Skin.CloseButton(frame.CloseButton or _G.LegacySystemFrameCloseButton)
        local titleText = (frame.TitleContainer and frame.TitleContainer.TitleText)
            or _G.LegacySystemFrameTitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end
        for _, tn in ipairs(SIDE_TABS) do
            Skin.SideTab(frame[tn])
        end
        for _, pn in ipairs(PAGES) do
            if frame[pn] then FontKids(frame[pn], 0) end
        end
        SkinTreePage(frame.TreePage)
        for _, pn in ipairs(PAGES) do
            if frame[pn] then SkinCards(frame[pn], 0) end
        end
    end)

    -- Re-skin on show and when a tab swaps a content page in (HookShow hooks each
    -- frame once).
    local function InstallHooks()
        local frame = _G.LegacySystemFrame
        if not frame then return end
        local repaint = Skin.Debounce(Skin_LegacySystem)
        Skin.HookShow(frame, repaint)
        for _, pn in ipairs(PAGES) do
            if frame[pn] then Skin.HookShow(frame[pn], repaint) end
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
