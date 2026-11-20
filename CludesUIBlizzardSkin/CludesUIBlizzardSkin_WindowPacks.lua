if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBlizzardSkin_WindowPacks.lua
--  Per-window skin packs on the shared engine (..._WindowEngine.lua):
--  style-aware shell, flat panels, white-hover buttons, accent-underlined tabs,
--  squared icons, flat scroll bars. Each pack registers via
--  WSkin.RegisterWindow, which gates it on the window's style ("off" = never
--  runs, zero cost), applies it when its load-on-demand Blizzard addon arrives,
--  and pcall-isolates it. Repaint hooks are debounced and early-out while
--  hidden, so navigation spam costs one pass per frame at most.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
local Skin = mod.WSkin
if not Skin then
    return
end

local Theme = Skin.Theme
local GetFFD = Skin.GetFFD
local FFD = Skin.FFD
local SolidTex = Skin.SolidTex

-- LOCAL LIMIT: Lua 5.1 allows 200 ACTIVE locals per function, and this file's
-- main chunk is one function. Going over is a compile error that takes every
-- pack in the file down with it. So each pack lives in its own do...end block:
-- its locals are released when the block closes, and the packs no longer add
-- up. Only the core aliases above and the few helpers shared ACROSS packs sit
-- outside a block (right after their section header, before its `do`). A new
-- helper goes inside its pack's block; hoist it out only once a later pack
-- actually calls it.

-------------------------------------------------------------------------------
--  Collections (Mounts / Pets / Toys / Heirlooms / Appearances / Campsites)
-------------------------------------------------------------------------------
-- Collection-tab filter dropdown: pins "Filter" left of the arrow (as on
-- achievement/housing/professions filters). Appearances' FilterButton
-- re-anchors or re-creates its label on tab-show, so SetPoint is hooked
-- (synchronous re-assert, no blink) and the fontstring re-derived each OnShow.
local function LeftAlignFilterLabel(dropdown)
    if not dropdown then
        return
    end
    local fieldData = GetFFD(dropdown)
    if fieldData.labHooked then
        return
    end
    fieldData.labHooked = true
    local guard = false
    local hooked = setmetatable({}, { __mode = "k" })
    local function applyFn()
        if guard then
            return
        end
        guard = true
        local labelText = dropdown.Text or (dropdown.GetFontString and dropdown:GetFontString())
        if labelText and labelText.ClearAllPoints then
            labelText:ClearAllPoints()
            labelText:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
            labelText:SetPoint("RIGHT", dropdown, "RIGHT", -22, 0)
            if labelText.SetJustifyH then
                labelText:SetJustifyH("LEFT")
            end
            if not hooked[labelText] then
                hooked[labelText] = true
                hooksecurefunc(labelText, "SetPoint", applyFn)
            end
        end
        guard = false
    end
    applyFn()
    if dropdown.HookScript then
        dropdown:HookScript("OnShow", function()
            applyFn()
            if C_Timer then
                C_Timer.After(0, applyFn)
            end
        end)
    end
end

-- Active-filter reset "X": WSkin.FilterResetX (the window engine).
local SkinFilterResetX = Skin.FilterResetX

do
    local PREVIEW_JOURNALS = { WarbandSceneJournal = true } -- texture previews are content

    -- Tabs whose filter dropdown height should track the search box beside it.
    local MATCH_FILTER_HEIGHT = {
        MountJournal = true,
        HeirloomsJournal = true,
        WardrobeCollectionFrame = true,
    }

    -- Collected-count bar (Appearances/Heirlooms/Toys): 2px taller, non-fill
    -- regions faded, flat accent fill (Blizzard's fill kept as driver, re-textured),
    -- dark trough, white text, VISIBLE themed border (a black BorderRegion would
    -- vanish on the dark backplate).
    local function SkinCollectionsProgressBar(progressBar)
        if not progressBar then
            return
        end
        local progressData = GetFFD(progressBar)
        if not progressData.heightBumped then
            progressData.heightBumped = true
            progressBar:SetHeight(progressBar:GetHeight() + 2)
        end
        if progressBar.border and progressBar.border.SetAlpha then
            progressBar.border:SetAlpha(0)
        end
        local fillTex = progressBar.GetStatusBarTexture and progressBar:GetStatusBarTexture()
        local regionList = { progressBar:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region ~= fillTex and region ~= progressData.bg and region.IsObjectType then
                if region:IsObjectType("Texture") and region:GetDrawLayer() ~= "HIGHLIGHT" then
                    region:SetAlpha(0)
                elseif region:IsObjectType("FontString") then
                    Skin.White(region)
                end
            end
        end
        if progressBar.SetStatusBarTexture then
            progressBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            Skin.ApplyBarFill(progressBar)
        end
        if not progressData.bg then
            local troughTex = progressBar:CreateTexture(nil, "BACKGROUND", nil, -1)
            troughTex:SetColorTexture(0.12, 0.12, 0.12, 0.85)
            troughTex:SetAllPoints(progressBar)
            progressData.bg = troughTex
        end
        Skin.AddBorder(progressBar)
    end

    local _mountRowHook = false
    local function Skin_Collections()
        local win = _G.CollectionsJournal
        if not win then
            return
        end
        Skin.Shell("collections", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win)
        local cTabs = {}
        for _, key in ipairs({
            "MountsTab",
            "PetsTab",
            "ToysTab",
            "HeirloomsTab",
            "WardrobeTab",
            "WarbandScenesTab",
        }) do
            local t = win[key]
            if t then
                Skin.Tab(t)
                cTabs[#cTabs + 1] = t
            end
        end
        -- Blizzard re-anchors bottom tabs to native spacing on every show, flashing
        -- the wide gap before our debounced re-skin. Re-normalize synchronously off
        -- each tab's SetPoint (reentry-guarded) so the seam is restored same-frame;
        -- scoped to this window, the shared helper stays untouched.
        local cd = GetFFD(win)
        if not cd.tabNormHook then
            cd.tabNormHook = true
            local guard = false
            local function ReNorm()
                if guard then
                    return
                end
                guard = true
                Skin.NormalizeTabRow(cTabs)
                guard = false
            end
            cd.tabReNorm = ReNorm
            for _, tab in ipairs(cTabs) do
                hooksecurefunc(tab, "SetPoint", ReNorm)
            end
        end
        if cd.tabReNorm then
            cd.tabReNorm()
        end
        -- Wardrobe's inner Items/Sets tabs are real tabs; treat them before the
        -- journal button sweep below flattens them into plain blocks.
        local wardrobe = _G.WardrobeCollectionFrame
        if wardrobe then
            local wTabs = {}
            if wardrobe.ItemsTab then
                Skin.Tab(wardrobe.ItemsTab, { darkActive = true })
                wTabs[#wTabs + 1] = wardrobe.ItemsTab
            end
            if wardrobe.SetsTab then
                Skin.Tab(wardrobe.SetsTab, { darkActive = true })
                wTabs[#wTabs + 1] = wardrobe.SetsTab
            end
            Skin.NormalizeTabRow(wTabs)
        end
        -- Mount-equipment slot (BottomLeftInset.SlotButton) is its own art (slot
        -- border + icon), not journal chrome -- exempt before the art sweeps run.
        local _mj = _G.MountJournal
        if _mj and _mj.BottomLeftInset and _mj.BottomLeftInset.SlotButton then
            Skin.ExemptArt(_mj.BottomLeftInset.SlotButton)
        end
        for _, label in ipairs({
            "MountJournal",
            "PetJournal",
            "ToyBox",
            "HeirloomsJournal",
            "WardrobeCollectionFrame",
            "WarbandSceneJournal",
        }) do
            local jdx = _G[label]
            if jdx then
                for _, keyName in ipairs({ "RightInset", "LeftInset", "Inset" }) do
                    if jdx[keyName] then
                        Skin.Inset(jdx[keyName])
                    end
                end
                -- Tiled bg + corners live on the icons frame; fade chrome, never the grid content.
                local icons = jdx.iconsFrame or jdx.IconsFrame
                if icons then
                    Skin.FadeRegions(icons)
                    Skin.FadeKeyedArt(icons)
                    Skin.Register(icons, true)
                end
                Skin.PagingIn(jdx)
                Skin.ScrollBarsIn(jdx)
                if not PREVIEW_JOURNALS[label] then
                    Skin.ButtonsIn(jdx)
                    Skin.FadeKeyedArt(jdx)
                    Skin.FadeArtIn(jdx)
                end
                -- Collected-count bar last, so the keyed-art sweep above cannot re-fade it.
                if jdx.progressBar then
                    SkinCollectionsProgressBar(jdx.progressBar)
                end
                local filter = jdx.FilterDropdown
                    or jdx.FilterButton
                    or _G[label .. "FilterDropdown"]
                    or _G[label .. "FilterButton"]
                LeftAlignFilterLabel(filter)
                if filter then
                    SkinFilterResetX(filter.ResetButton or filter.ClearFiltersButton, filter)
                end
                if MATCH_FILTER_HEIGHT[label] and filter and filter.SetHeight then
                    local scrollBar = jdx.SearchBox or jdx.searchBox or _G[label .. "SearchBox"]
                    local hgt = scrollBar and scrollBar.GetHeight and scrollBar:GetHeight()
                    if hgt and hgt > 0 then
                        filter:SetHeight(hgt)
                    end
                end
            end
        end

        -- Mount list rows recycle; restyle in the row initializer.
        if MountJournal_InitMountButton and not _mountRowHook then
            _mountRowHook = true
            hooksecurefunc("MountJournal_InitMountButton", function(btnFrame)
                if not btnFrame or btnFrame:IsForbidden() then
                    return
                end
                if btnFrame.background then
                    btnFrame.background:SetAlpha(0)
                end
                local skinData = GetFFD(btnFrame)
                if not skinData.bg then
                    local bgTex = btnFrame:CreateTexture(nil, "BACKGROUND")
                    bgTex:SetColorTexture(Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
                    bgTex:SetPoint("TOPLEFT", 1, -1)
                    bgTex:SetPoint("BOTTOMRIGHT", -1, 1)
                    skinData.bg = bgTex
                    Skin.AddBorder(btnFrame)
                end
                if btnFrame.name then
                    Skin.White(btnFrame.name)
                end
            end)
        end

        -- Warband campsites is a preview journal: Show Owned sits outside the
        -- button sweep, treat checkbox + label directly.
        local wj = _G.WarbandSceneJournal
        local so = wj
            and wj.IconsFrame
            and wj.IconsFrame.Icons
            and wj.IconsFrame.Icons.Controls
            and wj.IconsFrame.Icons.Controls.ShowOwned
        if so then
            if so.Checkbox then
                Skin.Checkbox(so.Checkbox)
            end
            if so.Text then
                Skin.White(so.Text)
            end
        end

        local mj = _G.MountJournal
        if mj and mj.MountDisplay then
            local mountDisplay = mj.MountDisplay
            if mountDisplay.ShadowOverlay then
                mountDisplay.ShadowOverlay:SetAlpha(0)
            end
            if mountDisplay.ModelScene and mountDisplay.ModelScene.ShadowOverlay then
                mountDisplay.ModelScene.ShadowOverlay:SetAlpha(0)
            end
            for _, keyName in ipairs({ "Border", "BorderFrame", "NineSlice" }) do
                if mountDisplay[keyName] then
                    Skin.FadeRegions(mountDisplay[keyName])
                    Skin.Register(mountDisplay[keyName], true)
                end
            end
            -- Scenic backdrop -> flat 3% white fill; SetAlpha(0) survives Blizzard's Yes/No toggle.
            for _, keyName in ipairs({ "YesMountsTex", "NoMountsTex" }) do
                if mountDisplay[keyName] and mountDisplay[keyName].SetAlpha then
                    mountDisplay[keyName]:SetAlpha(0)
                end
            end
            local mdd = GetFFD(mountDisplay)
            if not mdd.modelFill then
                local fillTex = mountDisplay:CreateTexture(nil, "BACKGROUND")
                fillTex:SetColorTexture(1, 1, 1, 0.03)
                fillTex:SetAllPoints(mountDisplay.YesMountsTex or mountDisplay.ModelScene or mountDisplay)
                mdd.modelFill = fillTex
            end
        end

        Skin.ButtonsIn(win)
        Skin.FadeKeyedArt(win)
        -- Appearances area keeps a faint 50% backing; the keyed-art sweep above
        -- zeroes Bg + BackgroundTile, so re-assert every pass (NineSlice/shadows stay stripped).
        local icf = wardrobe and wardrobe.ItemsCollectionFrame
        if icf then
            if icf.Bg then
                icf.Bg:SetAlpha(0.5)
            end
            if icf.BackgroundTile then
                icf.BackgroundTile:SetAlpha(0.5)
            end
        end
        -- Battle pet loadout: card + every border piece at a matched faint 25%
        -- (survives Blizzard re-texturing on pet swaps).
        for idx = 1, 3 do
            local bgTex = _G["PetJournalLoadoutPet" .. idx .. "BG"]
            if bgTex and bgTex.SetAlpha then
                bgTex:SetAlpha(0.25)
            end
        end
        local ploadBorder = _G.PetJournalLoadoutBorder
        if ploadBorder and ploadBorder.GetRegions then
            local regionList = { ploadBorder:GetRegions() }
            for ri = 1, #regionList do
                local region = regionList[ri]
                if region and region.SetAlpha and region.IsObjectType and region:IsObjectType("Texture") then
                    region:SetAlpha(0.25)
                end
            end
        end
        -- Bottom-bar action buttons (Mount/Summon/Find Battle) default gold;
        -- force white (color only), re-applied on OnEnable since re-enabling resets the gold font object.
        for _, bn in ipairs({
            "MountJournalMountButton",
            "PetJournalSummonButton",
            "PetJournalFindBattle",
        }) do
            local btnFrame = _G[bn]
            local labelText = btnFrame and (btnFrame.Text or (btnFrame.GetFontString and btnFrame:GetFontString()))
            if labelText then
                Skin.White(labelText)
                local buttonData = GetFFD(btnFrame)
                if not buttonData.whiteHook then
                    buttonData.whiteHook = true
                    btnFrame:HookScript("OnEnable", function()
                        Skin.White(labelText)
                    end)
                end
            end
        end
        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    Skin_Collections()
                    Skin.Restrip()
                    Skin.UpdateAllTabs()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "collections",
        addons = { Blizzard_Collections = true },
        apply = Skin_Collections,
    })
end

-------------------------------------------------------------------------------
--  Talents & Spellbook (PlayerSpellsFrame)
-------------------------------------------------------------------------------
do
    -- Blizzard re-raises the spellbook parchment backplate + gilded item frame on
    -- every populate/mouseover, so re-fade in post-hooks. Visual-only (SetAlpha),
    -- never the item's own alpha knobs or click path.
    local function FadeSpellItem(entry)
        if not entry or entry:IsForbidden() then
            return
        end
        if entry.Backplate and entry.Backplate.SetAlpha then
            entry.Backplate:SetAlpha(0)
        end
        local button = entry.Button
        if button then
            -- The per-icon ring stays, at half strength and half color.
            if button.Border and button.Border.SetAlpha then
                button.Border:SetAlpha(0.5)
                if button.Border.SetDesaturation then
                    button.Border:SetDesaturation(0.5)
                end
            end
            if button.BorderSheen and button.BorderSheen.SetAlpha then
                button.BorderSheen:SetAlpha(0)
            end
            if button.IconHighlight and button.IconHighlight.SetAlpha then
                button.IconHighlight:SetAlpha(0)
            end
        end
        if entry.Name then
            Skin.White(entry.Name)
        end
        if entry.SubName then
            Skin.White(entry.SubName)
        end
        -- The "Level N" / trainable line of an unlearned spell: the same parchment ink.
        if entry.RequiredLevel then
            Skin.White(entry.RequiredLevel)
        end
    end

    local function FadeSpellItemsIn(widget, nestDepth)
        nestDepth = nestDepth or 0
        if not widget or nestDepth > 10 or not widget.GetChildren or widget:IsForbidden() then
            return
        end
        if nestDepth > 0 and Skin.IsForeignFrame(widget) then
            return
        end
        if widget.Backplate and widget.Button then
            FadeSpellItem(widget)
        end
        local children = { widget:GetChildren() }
        for idx = 1, #children do
            FadeSpellItemsIn(children[idx], nestDepth + 1)
        end
    end

    -- Talents tab: tree art stays, dimmed to 75%, lower-only (never raise),
    -- BACKGROUND layer only, shallow (talent buttons/icons live deeper on ARTWORK,
    -- untouched). Re-runs are no-ops.
    local function DimTalentArt(owner, nestDepth)
        nestDepth = nestDepth or 0
        if not owner or nestDepth > 2 or not owner.GetRegions or owner:IsForbidden() then
            return
        end
        if nestDepth > 0 and Skin.IsForeignFrame(owner) then
            return
        end
        local regionList = { owner:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region.IsObjectType and region:IsObjectType("Texture") and region:GetDrawLayer() == "BACKGROUND" then
                local alpha = region:GetAlpha() or 1
                if alpha > 0.75 then
                    region:SetAlpha(0.75)
                end
            end
        end
        local children = { owner:GetChildren() }
        for idx = 1, #children do
            DimTalentArt(children[idx], nestDepth + 1)
        end
    end

    -- Spellbook page chrome: category headers -> white house-font text, gold glow
    -- washes gone, dividers stay white, "Page X/Y" matches. Decoration lives on
    -- both OVERLAY page-view regions and pooled header textures: wide-short strips
    -- are dividers (kept, whitened), the rest is wash (faded).
    local function SkinSpellBookChrome(scrollBar)
        local paged = scrollBar and scrollBar.PagedSpellsFrame
        if not paged then
            return
        end
        local pc = paged.PagingControls
        if pc and pc.PageText then
            Skin.Font(pc.PageText)
            Skin.White(pc.PageText)
        end
        -- The divider is an anonymous non-OVERLAY texture region on the view.
        local function SweepDeco(owner)
            local regionList = { owner:GetRegions() }
            for idx = 1, #regionList do
                local region = regionList[idx]
                if region and region.IsObjectType then
                    if region:IsObjectType("FontString") then
                        Skin.Font(region)
                        Skin.White(region)
                    elseif region:IsObjectType("Texture") and not (FFD[region] and FFD[region].isOurLine) then
                        -- Skip our own replacement lines above (else the divider branch
                        -- would re-chain each one 20px shorter per sweep). Rects not yet
                        -- computed (hidden first pass) measure 0x0 and land in the fade
                        -- bucket; the next sweep sees real sizes.
                        local wid, hgt = region:GetSize()
                        if wid and hgt and wid > 0 and hgt > 0 then
                            if hgt <= 30 and wid > 80 then
                                -- Ornate divider art is too dark to read white: fade it,
                                -- draw a clean 1px white 25% line over the same rect.
                                region:SetAlpha(0)
                                local regionData = GetFFD(region)
                                if not regionData.line then
                                    local line = region:GetParent():CreateTexture(nil, "OVERLAY")
                                    line:SetColorTexture(1, 1, 1, 0.25)
                                    local PPx = CludesUI and CludesUI.PanelPP
                                    if PPx and PPx.DisablePixelSnap then
                                        PPx.DisablePixelSnap(line)
                                        line:SetHeight(PPx.mult or 1)
                                    else
                                        line:SetHeight(1)
                                    end
                                    line:SetPoint("LEFT", region, "LEFT", 20, 0)
                                    line:SetPoint("RIGHT", region, "RIGHT", 0, 0)
                                    regionData.line = line
                                    GetFFD(line).isOurLine = true
                                end
                            else
                                region:SetAlpha(0)
                            end
                        end
                    end
                end
            end
        end
        for _, keyName in ipairs({ "View1", "View2" }) do
            if paged[keyName] then
                SweepDeco(paged[keyName])
            end
        end
        -- Pooled elements: items answer HasValidData, headers/spacers do not. The
        -- header's gold "card" wash is its keyed Backplate texture, on a lower draw
        -- layer the OVERLAY sweep never saw.
        pcall(function()
            for _, part in paged:EnumerateFrames() do
                if not (part.HasValidData and part:HasValidData()) and part.GetRegions then
                    if part.Backplate and part.Backplate.SetAlpha then
                        part.Backplate:SetAlpha(0)
                    end
                    SweepDeco(part)
                end
            end
        end)
    end

    -- Talent loadout popups (import/edit): dark panel + border, white title, house
    -- buttons + inputs. Separate top-level frames created with the PlayerSpells
    -- addon, so skinning sticks on the talent pass even though shown on demand.
    local function SkinTalentDialog(dialog)
        if not dialog or dialog:IsForbidden() then
            return
        end
        -- STYLE-AWARE shell (not a flat WSkin.Panel): the popup must follow the
        -- Talents window's theme (atlas "glass" or Modern flat color); a plain
        -- Panel is style-agnostic and reads as opaque next to it.
        Skin.Shell("playerspells", dialog)
        -- Leftover Blizzard border sub-frame: shell's atlas border replaces it, alpha 0 inherits to all pieces.
        if dialog.Border and dialog.Border.SetAlpha then
            dialog.Border:SetAlpha(0)
        end
        local titleText = dialog.Title
            or (dialog.TitleContainer and dialog.TitleContainer.TitleText)
            or dialog.TitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
            -- Seat the title on the shell's top bar (1px above center): the shell's
            -- 25px top strip sits below the native title anchor.
            local partData = Skin.FFD and Skin.FFD[dialog]
            local titleData = GetFFD(titleText)
            if partData and partData.topBar and titleText.ClearAllPoints and not titleData.centered then
                titleData.centered = true
                titleText:ClearAllPoints()
                titleText:SetPoint("CENTER", partData.topBar, "CENTER", 0, 1)
            end
        end
        for _, keyName in ipairs({ "AcceptButton", "CancelButton", "DeleteButton" }) do
            local button = dialog[keyName]
            if button then
                Skin.Button(button)
                local fontStr = button.GetFontString and button:GetFontString()
                if fontStr then
                    Skin.White(fontStr)
                end
            end
        end
        -- Loadout-name input: down 15px, 20px shorter. Top+bottom anchored so
        -- SetHeight is ignored -- move anchors instead (top -15, bottom +5); falls
        -- back to SetHeight when there is no bottom anchor. One-shot.
        local nc = dialog.NameControl
        if nc and nc.EditBox then
            Skin.EditBox(nc.EditBox)
            local editField = nc.EditBox
            local ed = GetFFD(editField)
            if not ed.shorter then
                ed.shorter = true
                local numPoints = editField:GetNumPoints() or 0
                local pts, hasBottom = {}, false
                for idx = 1, numPoints do
                    local point, relTo, relPoint, posX, posY = editField:GetPoint(idx)
                    if point and point:find("BOTTOM") then
                        pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + 5 }
                        hasBottom = true
                    elseif point then
                        -- TOP / LEFT / RIGHT / CENTER: shift down 15.
                        pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) - 15 }
                    end
                end
                editField:ClearAllPoints()
                for idx = 1, #pts do
                    local tbl = pts[idx]
                    editField:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                end
                if not hasBottom then
                    local hgt = editField:GetHeight()
                    if hgt and hgt > 20 then
                        editField:SetHeight(hgt - 20)
                    end
                end
            end
        end
    end

    local _spellItemHook = false
    local function Skin_PlayerSpells()
        local win = _G.PlayerSpellsFrame
        if not win then
            return
        end
        Skin.Shell("playerspells", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win)
        Skin.TabSystem(win.TabSystem)
        -- Spellbook class/general tabs get real tab treatment before the button
        -- sweep flattens them; our label stays centered vs. Blizzard's low-seated inactive text.
        if win.SpellBookFrame and win.SpellBookFrame.CategoryTabSystem then
            Skin.TabSystem(win.SpellBookFrame.CategoryTabSystem, { darkActive = true })
        end
        -- WoW Forever's talents page carries its own dual-spec tabs (Primary /
        -- Secondary): the same tab treatment, also ahead of the button sweep.
        if win.TalentsFrame and win.TalentsFrame.TabSystem then
            Skin.TabSystem(win.TalentsFrame.TabSystem, { darkActive = true })
        end
        -- Collapse/restore control: quest-tracker collapse/expand atlas pair,
        -- 16x16, desaturated white. Atlas-guarded: a missing name keeps Blizzard's art.
        local function MaxMinGlyph(btnFrame, atlas)
            if not btnFrame or btnFrame:IsForbidden() then
                return
            end
            if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then
                return
            end
            local skinData = GetFFD(btnFrame)
            if skinData.glyph then
                return
            end
            for _, g in ipairs({
                "GetNormalTexture",
                "GetPushedTexture",
                "GetHighlightTexture",
                "GetDisabledTexture",
            }) do
                local part = btnFrame[g] and btnFrame[g](btnFrame)
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
            Skin.FadeRegions(btnFrame)
            local glyphTex = btnFrame:CreateTexture(nil, "OVERLAY")
            glyphTex:SetAtlas(atlas)
            glyphTex:SetSize(16, 16)
            glyphTex:SetPoint("CENTER", -2, 0)
            glyphTex:SetDesaturated(true)
            glyphTex:SetVertexColor(1, 1, 1, 0.75)
            skinData.glyph = glyphTex
            btnFrame:HookScript("OnEnter", function()
                glyphTex:SetVertexColor(1, 1, 1, 1)
            end)
            btnFrame:HookScript("OnLeave", function()
                glyphTex:SetVertexColor(1, 1, 1, 0.75)
            end)
        end
        local maxMinBtn = win.MaximizeMinimizeButton or win.MaxMinButtonFrame
        if maxMinBtn then
            MaxMinGlyph(maxMinBtn.MinimizeButton, "UI-QuestTrackerButton-Secondary-Collapse")
            MaxMinGlyph(maxMinBtn.MaximizeButton, "UI-QuestTrackerButton-Secondary-Expand")
        end
        for _, key in ipairs({ "SpellBookFrame", "TalentsFrame", "InspectFrame" }) do
            local subPanel = win[key]
            if subPanel then
                Skin.ButtonsIn(subPanel)
                Skin.ScrollBarsIn(subPanel)
                if key == "SpellBookFrame" then
                    -- Page art returns dimmed (halved page is the minimized layout's
                    -- art); center bookmark stays full, top bar/corner flipbook stay off.
                    Skin.ExemptArt(subPanel)
                    for _, bk in ipairs({ "BookBGLeft", "BookBGRight", "BookBGHalved" }) do
                        local part = subPanel[bk]
                        if part and part.SetAlpha then
                            part:SetAlpha(0.1)
                        end
                    end
                    if subPanel.TopBar and subPanel.TopBar.SetAlpha then
                        subPanel.TopBar:SetAlpha(0)
                    end
                    if subPanel.BookCornerFlipbook and subPanel.BookCornerFlipbook.SetAlpha then
                        subPanel.BookCornerFlipbook:SetAlpha(0)
                    end
                    -- Assisted-rotation separator: exemption above blocks the art
                    -- sweeps reaching it, so fade directly (its button child survives).
                    if subPanel.AssistedCombatRotationSpellFrame then
                        Skin.FadeRegions(subPanel.AssistedCombatRotationSpellFrame)
                        Skin.Register(subPanel.AssistedCombatRotationSpellFrame, true)
                    end
                elseif key == "TalentsFrame" then
                    -- Tree background is content: exempt from art sweeps, shown at 75%.
                    Skin.ExemptArt(subPanel)
                    DimTalentArt(subPanel)
                    -- WoW Forever keeps the spec art in ClassBackground and draws a
                    -- backdrop of its own as Background, 20px taller than the page,
                    -- over the shell's top bar: off, so the shell shows round the tree.
                    if subPanel.ClassBackground and subPanel.Background and subPanel.Background.SetAlpha then
                        subPanel.Background:SetAlpha(0)
                    end
                    -- WoW Forever's search options button beside the search box: our
                    -- arrow alone, no block, on the search box's centre line (Blizzard
                    -- seats the button 2px below it). One-shot.
                    local sod = subPanel.SearchOptionsDropdown
                    if sod and not sod:IsForbidden() and not GetFFD(sod).arrow then
                        Skin.FadeRegions(sod)
                        local arrowTex = sod:CreateTexture(nil, "OVERLAY")
                        arrowTex:SetAtlas("Azerite-PointingArrow")
                        arrowTex:SetSize(14, 10)
                        arrowTex:SetPoint("CENTER", sod, "CENTER", 0, 2)
                        GetFFD(sod).arrow = arrowTex
                    end
                    -- Search box matches loadout dropdown height (one-shot, retries until laid out).
                    local dropdown = subPanel.LoadSystem and subPanel.LoadSystem.Dropdown
                    local searchField = subPanel.SearchBox
                    if dropdown and searchField and not GetFFD(searchField).hMatched then
                        local dh = dropdown:GetHeight()
                        if dh and dh > 0 then
                            GetFFD(searchField).hMatched = true
                            searchField:SetHeight(dh)
                        end
                    end
                else
                    Skin.FadeKeyedArt(subPanel)
                    Skin.FadeArtIn(subPanel)
                end
            end
        end

        -- Spec page: per-spec tile art IS content, so the pane is exempt from art
        -- sweeps and tiles keep their backgrounds. Only the page-level black
        -- underlay + background go (direct sf regions, not tile art, that fight the shell).
        local scrollFrame = win.SpecFrame
        if scrollFrame then
            Skin.ExemptArt(scrollFrame)
            if scrollFrame.BlackBG and scrollFrame.BlackBG.SetAlpha then
                scrollFrame.BlackBG:SetAlpha(0)
            end
            if scrollFrame.Background and scrollFrame.Background.SetAlpha then
                scrollFrame.Background:SetAlpha(0)
            end
            Skin.ButtonsIn(scrollFrame)
            Skin.ScrollBarsIn(scrollFrame)
        end

        if win.SpellBookFrame then
            FadeSpellItemsIn(win.SpellBookFrame)
            local scrollBar = win.SpellBookFrame
            SkinSpellBookChrome(scrollBar)
            -- Headers are pooled/re-realized on tab changes and page flips; re-sweep chrome one debounced frame after each.
            local partData = GetFFD(scrollBar)
            if not partData.chromeHooked then
                partData.chromeHooked = true
                local re = Skin.Debounce(function()
                    if win:IsVisible() then
                        SkinSpellBookChrome(scrollBar)
                    end
                end)
                if scrollBar.SetTab then
                    hooksecurefunc(scrollBar, "SetTab", re)
                end
                -- Returning from Spec/Talents re-realizes pooled headers but only
                -- fires the spellbook subframe's OnShow (window never hid).
                scrollBar:HookScript("OnShow", re)
                local paged = scrollBar.PagedSpellsFrame
                local pc = paged and paged.PagingControls
                if pc and pc.PrevPageButton then
                    pc.PrevPageButton:HookScript("OnClick", re)
                end
                if pc and pc.NextPageButton then
                    pc.NextPageButton:HookScript("OnClick", re)
                end
                if paged then
                    paged:HookScript("OnMouseWheel", re)
                end
            end
        end
        if SpellBookItemMixin and not _spellItemHook then
            _spellItemHook = true
            if SpellBookItemMixin.UpdateVisuals then
                hooksecurefunc(SpellBookItemMixin, "UpdateVisuals", FadeSpellItem)
            end
            -- Both hover edges re-fade the full art set: enter raises highlight art,
            -- leave restores Blizzard's baseline (else a stuck texture is left behind items).
            if SpellBookItemMixin.OnIconEnter then
                hooksecurefunc(SpellBookItemMixin, "OnIconEnter", FadeSpellItem)
            end
            if SpellBookItemMixin.OnIconLeave then
                hooksecurefunc(SpellBookItemMixin, "OnIconLeave", FadeSpellItem)
            end
        end

        -- Loadout popups.
        local importD = _G.ClassTalentLoadoutImportDialog
        if importD then
            SkinTalentDialog(importD)
            -- Import-string box.
            local importControl = importD.ImportControl
            if importControl and importControl.InputContainer then
                Skin.Panel(importControl.InputContainer)
            end
        end
        local createD = _G.ClassTalentLoadoutCreateDialog
        if createD then
            SkinTalentDialog(createD)
        end
        local editD = _G.ClassTalentLoadoutEditDialog
        if editD then
            SkinTalentDialog(editD)
            if editD.LoadoutName then
                Skin.EditBox(editD.LoadoutName)
            end
            local chk = editD.UsesSharedActionBars and editD.UsesSharedActionBars.CheckButton
            if chk then
                Skin.Checkbox(chk)
            end
        end

        Skin.ButtonsIn(win)
        Skin.ScrollBarsIn(win)
        Skin.FadeKeyedArt(win)
        Skin.FadeArtIn(win)
        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    Skin_PlayerSpells()
                    Skin.Restrip()
                    Skin.UpdateAllTabs()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "playerspells",
        addons = { Blizzard_PlayerSpells = true },
        apply = Skin_PlayerSpells,
    })
end

-------------------------------------------------------------------------------
--  Adventure Guide (EncounterJournal)
-------------------------------------------------------------------------------
-- Some Blizzard text bakes a |cff000000 black or |cff414141 grey run INTO the
-- string (gossip/quest titles, reward/greeting blurbs); SetTextColor cannot
-- lighten those, the embedded run wins. Rewrite only those two tones in place,
-- leaving other colors (links, quest difficulty) untouched; idempotent since
-- the source codes are gone after rewrite.
local DARK_TEXT_RECOLOR = { ["000000"] = "ffffff", ["414141"] = "b0b8bc" }
local function RecolorDarkText(fontStr)
    if not fontStr or not fontStr.GetText then
        return
    end
    local txt = fontStr:GetText()
    if not txt or txt == "" or not txt:find("|cff", 1, true) then
        return
    end
    local new, n = txt:gsub("|c[fF][fF](%x%x%x%x%x%x)", function(hex)
        local repl = DARK_TEXT_RECOLOR[hex:lower()]
        if repl then
            return "|cff" .. repl
        end
    end)
    if n > 0 and new ~= txt then
        fontStr:SetText(new)
    end
end

-- Force encounter text white once the parchment is gone (SimpleHTML bodies
-- take per-element colors). Embedded hyperlink |c codes are rewritten to the
-- Global Options link color; the |H payload stays untouched so clicking still
-- works and re-runs are idempotent.
local function RecolorLinks(fontStr)
    local txt = fontStr.GetText and fontStr:GetText()
    if not txt or txt == "" or not txt:find("|H", 1, true) then
        return
    end
    local new, n = txt:gsub("|c%x%x%x%x%x%x%x%x|H", "|cff" .. Skin.LinkColorHex() .. "|H")
    if n > 0 and new ~= txt then
        fontStr:SetText(new)
    end
end

local function WhitenTextIn(widget, nestDepth)
    nestDepth = nestDepth or 0
    if not widget or nestDepth > 9 or widget:IsForbidden() then
        return
    end
    if widget.GetRegions then
        local regionList = { widget:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region.IsObjectType and region:IsObjectType("FontString") and region.SetTextColor then
                region:SetTextColor(1, 1, 1)
                RecolorLinks(region)
                RecolorDarkText(region)
            end
        end
    end
    if widget.GetChildren then
        local children = { widget:GetChildren() }
        for idx = 1, #children do
            local child = children[idx]
            if child and not Skin.IsForeignFrame(child, widget) then
                if child.GetObjectType and child:GetObjectType() == "SimpleHTML" and child.SetTextColor then
                    for _, part in ipairs({ "P", "H1", "H2", "H3" }) do
                        pcall(child.SetTextColor, child, part, 1, 1, 1)
                    end
                end
                WhitenTextIn(child, nestDepth + 1)
            end
        end
    end
end

do
    local EJ_ART_MATCH = {
        "journalbg",
        "ui-ej-cataclysm",
        "abilitytextbg",
        "paperoverlay",
        "activities-background",
        "adventureguide-pane",
    }
    local function ejKeepTex(hay)
        if not hay then
            return false
        end
        if Skin.TexIsIcon(hay) then
            return true
        end
        if hay:find("ui-ej-lorebg", 1, true) then
            return true
        end -- instance picture
        if hay:find("ui-ej-boss", 1, true) then
            return true
        end -- boss render
        if hay:find("ui-ej-icons", 1, true) then
            return true
        end
        return false
    end
    local function FadeEJArt(widget, nestDepth)
        nestDepth = nestDepth or 0
        if not widget or nestDepth > 11 or not widget.GetRegions or widget:IsForbidden() then
            return
        end
        if Skin.IsArtExempt(widget) then
            return
        end
        if nestDepth > 0 and Skin.IsForeignFrame(widget) then
            return
        end
        local mybg = FFD[widget] and FFD[widget].bg
        local regionList = { widget:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if
                region
                and region ~= mybg
                and region.IsObjectType
                and region:IsObjectType("Texture")
                and (region:GetAlpha() or 0) > 0
            then
                local hay = Skin.TexHay(region)
                if hay and not ejKeepTex(hay) then
                    for _, m in ipairs(EJ_ART_MATCH) do
                        if hay:find(m, 1, true) then
                            region:SetAlpha(0)
                            break
                        end
                    end
                end
            end
        end
        local children = { widget:GetChildren() }
        for idx = 1, #children do
            FadeEJArt(children[idx], nestDepth + 1)
        end
    end

    -- Breadcrumb nav button: art gone, white text, 1px right-edge divider (hidden
    -- on the last crumb), subnav caret drawn with the house arrow. Crumbs resize to
    -- content (|pad| text (gap arrow) |pad|) and re-chain seamlessly in RefreshNav.
    local NAV_PAD = 14 -- even padding on each side of a crumb's content
    local NAV_ARROW_GAP = 4 -- gap between text and the subnav arrow
    local NAV_ARROW_W = 12 -- arrow width (62x44 atlas at 12x8.5)
    local _navReflow -- assigned to RefreshNav once the nav is skinned
    local function SkinNavButton(btnFrame)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(btnFrame)
        if not skinData.navskin then
            skinData.navskin = true
            -- Rewinding (earlier crumb/Home click) relayouts survivors inside the
            -- click handler; reflow synchronously so they never render at Blizzard's layout.
            btnFrame:HookScript("OnClick", function()
                local nv = btnFrame:GetParent()
                local rf = nv and FFD[nv] and FFD[nv].reflow
                if rf then
                    rf()
                elseif _navReflow then
                    _navReflow()
                end
            end)
            for _, g in ipairs({
                "GetNormalTexture",
                "GetHighlightTexture",
                "GetPushedTexture",
                "GetDisabledTexture",
            }) do
                local func = btnFrame[g]
                local part = func and func(btnFrame)
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
            Skin.FadeRegions(btnFrame)
            local hoverTex = SolidTex(btnFrame, "HIGHLIGHT", 1, 1, 1, 0.1)
            hoverTex:SetPoint("TOPLEFT", 2, -3)
            hoverTex:SetPoint("BOTTOMRIGHT", -2, 3)
            skinData.hover = hoverTex
            local div = btnFrame:CreateTexture(nil, "OVERLAY")
            div:SetColorTexture(1, 1, 1, 0.15)
            div:SetWidth(1)
            div:SetPoint("TOPRIGHT", btnFrame, "TOPRIGHT", 0, -5)
            div:SetPoint("BOTTOMRIGHT", btnFrame, "BOTTOMRIGHT", 0, 5)
            skinData.divider = div
        end
        if btnFrame.text then
            Skin.White(btnFrame.text)
        end

        local menuArrow = btnFrame.MenuArrowButton
        if menuArrow and not skinData.arrow then
            -- Arrow lives ON the caret button, so it follows Blizzard's show/hide for crumbs with a subnav menu.
            local arrowTex = menuArrow:CreateTexture(nil, "OVERLAY")
            arrowTex:SetAtlas("Azerite-PointingArrow")
            arrowTex:SetSize(12, 8.5) -- native 62x44 aspect
            arrowTex:SetPoint("CENTER")
            skinData.arrow = arrowTex
        end
        if menuArrow then
            -- Blizzard re-applies caret/border/glow art on nav rebuild AND raises
            -- hover art on OnEnter, so fade ALL native art every pass and from
            -- enter/leave hooks too, keeping our arrow.
            local mountDisplay = GetFFD(menuArrow)
            local function FadeArrowArt()
                local keepSet = { [skinData.arrow] = true }
                Skin.FadeRegions(menuArrow, keepSet)
                for _, g in ipairs({
                    "GetNormalTexture",
                    "GetPushedTexture",
                    "GetHighlightTexture",
                    "GetDisabledTexture",
                }) do
                    local func = menuArrow[g]
                    local part = func and func(menuArrow)
                    if part and not keepSet[part] and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
                if menuArrow.Art and menuArrow.Art.SetAlpha then
                    menuArrow.Art:SetAlpha(0)
                end
            end
            FadeArrowArt()
            if not mountDisplay.hoverHooked then
                mountDisplay.hoverHooked = true
                menuArrow:HookScript("OnEnter", FadeArrowArt)
                menuArrow:HookScript("OnLeave", FadeArrowArt)
            end
        end

        -- |pad| text (gap arrow) |pad| -- even spacing against the dividers.
        if btnFrame.text then
            btnFrame.text:ClearAllPoints()
            btnFrame.text:SetPoint("LEFT", btnFrame, "LEFT", NAV_PAD, 0)
            if menuArrow and not skinData.maMoved then
                skinData.maMoved = true
                menuArrow:ClearAllPoints()
                -- 5px left of the nominal gap position (arrow hugs the text).
                menuArrow:SetPoint("LEFT", btnFrame.text, "RIGHT", NAV_ARROW_GAP - 5, 0)
            end
        end
    end

    -- Breadcrumb bar restyle (adventure guide + world map): faint wash over just
    -- the crumbs, white text with 1px dividers, house subnav arrows,
    -- content-driven widths chained seamlessly. dx/dy reseat from Blizzard's spot
    -- (captured once), bar runs 6px slimmer. bgColor {r,g,b,a} sets the crumb wash
    -- (default 5% white; map uses 20% black).
    local function RestyleNavGeneric(navBar, dx, dy, bgColor)
        if not navBar then
            return
        end
        for _, keyName in ipairs({
            "InsetBorderBottomLeft",
            "InsetBorderBottomRight",
            "InsetBorderBottom",
            "InsetBorderLeft",
            "InsetBorderRight",
        }) do
            local part = navBar[keyName]
            if part and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        local navData = GetFFD(navBar)
        if not navData.bg then
            local washTex = navBar:CreateTexture(nil, "BACKGROUND", nil, -6)
            washTex:SetAllPoints(navBar)
            navData.bg = washTex
        end
        local bc = bgColor or { 1, 1, 1, 0.05 }
        navData.bg:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        if navData.origP == nil then
            local point, relTo, relPoint, posX, posY = navBar:GetPoint(1)
            if point then
                navData.origP, navData.origRel, navData.origRP = point, relTo, relPoint
                navData.origX, navData.origY = posX or 0, posY or 0
            end
        end
        if navData.origP then
            navBar:ClearAllPoints()
            navBar:SetPoint(navData.origP, navData.origRel, navData.origRP, navData.origX + (dx or 0), navData.origY + (dy or 0))
        end
        if navData.origH == nil then
            local hgt = navBar:GetHeight()
            if hgt and hgt > 0 then
                navData.origH = hgt
            end
        end
        if navData.origH then
            navBar:SetHeight(navData.origH - 6)
        end
        local keepSet = { [navData.bg] = true }
        Skin.FadeRegions(navBar, keepSet)
        Skin.Register(navBar, true)
        if navBar.overlay then
            -- Decorative overlay: alpha the whole frame so anonymous textures cannot resurface.
            Skin.FadeRegions(navBar.overlay)
            local nt = navBar.overlay.GetNormalTexture and navBar.overlay:GetNormalTexture()
            if nt and nt.SetAlpha then
                nt:SetAlpha(0)
            end
            if navBar.overlay.SetAlpha then
                navBar.overlay:SetAlpha(0)
            end
            Skin.Register(navBar.overlay, true)
        end
        if navBar.navList then
            local n = #navBar.navList
            -- Wash covers only the crumbs, not the full nav width: left edges ride the nav, right edge rides the last crumb.
            local last = navBar.navList[n]
            if last and navData.bg then
                navData.bg:ClearAllPoints()
                navData.bg:SetPoint("TOPLEFT", navBar, "TOPLEFT", 0, 0)
                navData.bg:SetPoint("BOTTOMLEFT", navBar, "BOTTOMLEFT", 0, 0)
                navData.bg:SetPoint("RIGHT", last, "RIGHT", 0, 0)
            end
            for idx = 1, n do
                local button = navBar.navList[idx]
                if button then
                    SkinNavButton(button)
                    -- Content-driven width: each crumb is exactly |pad|text (gap
                    -- arrow)|pad| wide, butting its neighbour so the divider sits on
                    -- the boundary with even spacing both sides.
                    local tw = (button.text and button.text.GetStringWidth and button.text:GetStringWidth()) or 0
                    local menuArrow = button.MenuArrowButton
                    local hasArrow = menuArrow and menuArrow:IsShown()
                    button:SetWidth(NAV_PAD + tw + (hasArrow and (NAV_ARROW_GAP + NAV_ARROW_W) or 0) + NAV_PAD)
                    if idx > 1 and navBar.navList[idx - 1] then
                        button:ClearAllPoints()
                        button:SetPoint("LEFT", navBar.navList[idx - 1], "RIGHT", 0, 0)
                    end
                    local buttonData = FFD[button]
                    if buttonData and buttonData.divider then
                        buttonData.divider:SetShown(idx < n)
                    end
                end
            end
        end
    end

    -- Boss-list row: keep the creature render, 10% white block behind, white name.
    local function SkinBossButton(btnFrame)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(btnFrame)
        if not skinData.bossbtn then
            skinData.bossbtn = true
            for _, g in ipairs({
                "GetNormalTexture",
                "GetPushedTexture",
                "GetHighlightTexture",
                "GetDisabledTexture",
            }) do
                local func = btnFrame[g]
                local part = func and func(btnFrame)
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
            local fillTex = btnFrame:CreateTexture(nil, "BACKGROUND", nil, -2)
            fillTex:SetColorTexture(1, 1, 1, 0.1)
            fillTex:SetPoint("TOPLEFT", 1, -1)
            fillTex:SetPoint("BOTTOMRIGHT", -1, 1)
            skinData.bg = fillTex
            -- No border: the creature render overflows the row and a border would
            -- draw a line across the model.
        end
        if btnFrame.text then
            Skin.White(btnFrame.text)
        end
        if btnFrame.name then
            Skin.White(btnFrame.name)
        end
        -- Active boss keeps the full plate, the rest read at half. With no boss
        -- selected (instance overview), all stay full.
        local ejID = _G.EncounterJournal and _G.EncounterJournal.encounterID
        local isActive = not ejID or (btnFrame.encounterID and btnFrame.encounterID == ejID)
        skinData.bg:SetAlpha(isActive and 1 or 0.5)
    end
    local function FlattenBossButtons(widget, nestDepth)
        nestDepth = nestDepth or 0
        if not widget or nestDepth > 8 or widget:IsForbidden() or not widget.GetChildren then
            return
        end
        local children = { widget:GetChildren() }
        for idx = 1, #children do
            local child = children[idx]
            if child and not Skin.IsForeignFrame(child, widget) then
                if
                    child.creature
                    and (child.text or child.name)
                    and child.GetObjectType
                    and child:GetObjectType() == "Button"
                then
                    SkinBossButton(child)
                end
                FlattenBossButtons(child, nestDepth + 1)
            end
        end
    end

    -- Instance-select tile: keep the splash image, square it, frame with the AH
    -- item-header atlas (sized to image) + white hover. Raid tiles carry extra baked
    -- border art getter fades miss, so every region except splash/frame/hover is
    -- faded, re-asserted per pass (tiles are pooled and repainted).
    local function SkinInstanceButton(btnFrame)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(btnFrame)
        if not skinData.instbtn then
            skinData.instbtn = true
            local frameArt = btnFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            frameArt:SetAtlas("shop-card-wide-frame-default")
            frameArt:SetAlpha(0.5)
            if btnFrame.bgImage then
                frameArt:SetAllPoints(btnFrame.bgImage)
            else
                frameArt:SetAllPoints(btnFrame)
            end
            skinData.frameArt = frameArt
            local hoverTex = btnFrame:CreateTexture(nil, "HIGHLIGHT")
            hoverTex:SetAtlas("shop-card-wide-frame-hover")
            hoverTex:SetAllPoints(frameArt)
            skinData.hover = hoverTex
        end
        -- Blizzard re-anchors the splash on pool updates; re-assert a 1px inset every pass to clear the clipping viewport.
        if btnFrame.bgImage and btnFrame.bgImage.SetPoint then
            btnFrame.bgImage:ClearAllPoints()
            btnFrame.bgImage:SetPoint("TOPLEFT", 1, -1)
            btnFrame.bgImage:SetPoint("BOTTOMRIGHT", -1, 1)
        end
        -- Native tile art blends at half strength under our frame art (splash/frame/
        -- hover stay full); native highlight fully faded since our hover atlas replaces it.
        local keepSet = {}
        if btnFrame.bgImage then
            keepSet[btnFrame.bgImage] = true
        end
        if skinData.frameArt then
            keepSet[skinData.frameArt] = true
        end
        if skinData.hover then
            keepSet[skinData.hover] = true
        end
        local regionList = { btnFrame:GetRegions() }
        for jdx = 1, #regionList do
            local region = regionList[jdx]
            if region and not keepSet[region] and region.IsObjectType and region:IsObjectType("Texture") then
                region:SetAlpha(0.5)
            end
        end
        for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
            local func = btnFrame[getter]
            local part = func and func(btnFrame)
            if part and not keepSet[part] and part.SetAlpha then
                part:SetAlpha(0.5)
            end
        end
        local highlight = btnFrame.GetHighlightTexture and btnFrame:GetHighlightTexture()
        if highlight and not keepSet[highlight] and highlight.SetAlpha then
            highlight:SetAlpha(0)
        end
    end
    local function FlattenInstanceButtons(widget, nestDepth)
        nestDepth = nestDepth or 0
        if not widget or nestDepth > 8 or widget:IsForbidden() or not widget.GetChildren then
            return
        end
        local children = { widget:GetChildren() }
        for idx = 1, #children do
            local child = children[idx]
            if child and not Skin.IsForeignFrame(child, widget) then
                if child.bgImage and child.name and child.GetObjectType and child:GetObjectType() == "Button" then
                    SkinInstanceButton(child)
                end
                FlattenInstanceButtons(child, nestDepth + 1)
            end
        end
    end

    -- Side icon tab (overview/loot/boss/model): smaller dark box behind the glyph
    -- (icon keeps its size) with a black border, pushed right so tabs hang off the
    -- window's side, extra spacing between them. Hover glow (HighlightTexture) is
    -- re-faded every detail pass since the journal re-raises tab art on navigation.
    local SIDE_TAB_X = 16 -- push right so the box sits flush on the panel edge
    local SIDE_TAB_GAP = 2 -- extra vertical space between tabs
    local SIDE_TAB_INSET = 3 -- how much smaller the dark box is than the tab

    -- Idempotent: original anchor offsets captured once, shift is always original
    -- + constants (never compounds). Handles both anchoring shapes: chained
    -- (tab -> previous tab) and flat (every tab -> shared host).
    local function PositionSideTab(tabBtn, index)
        if not tabBtn or tabBtn:IsForbidden() then
            return
        end
        local skinData = GetFFD(tabBtn)
        local point, relTo, relPoint, posX, posY = tabBtn:GetPoint(1)
        if not point then
            return
        end
        if skinData.origX == nil then
            skinData.origX, skinData.origY = posX or 0, posY or 0
        end
        local relIsTab = relTo and FFD[relTo] and FFD[relTo].sidetab
        local xAdd = relIsTab and 0 or SIDE_TAB_X
        local yMult = relIsTab and 1 or ((index or 1) - 1)
        tabBtn:ClearAllPoints()
        tabBtn:SetPoint(point, relTo, relPoint, skinData.origX + xAdd, skinData.origY - SIDE_TAB_GAP * yMult)
    end

    local function SkinSideTab(tabBtn, index)
        if not tabBtn or tabBtn:IsForbidden() then
            return
        end
        local skinData = GetFFD(tabBtn)
        if not skinData.sidetab then
            skinData.sidetab = true
            -- Box sits two levels below the tab so its fill AND its border
            -- container (box level + 1) both draw beneath the tab's glyph.
            local tabBox = CreateFrame("Frame", nil, tabBtn)
            tabBox:SetPoint("TOPLEFT", SIDE_TAB_INSET, -SIDE_TAB_INSET)
            tabBox:SetPoint("BOTTOMRIGHT", -SIDE_TAB_INSET, SIDE_TAB_INSET)
            tabBox:SetFrameLevel(math.max(0, tabBtn:GetFrameLevel() - 2))
            local fillTex = SolidTex(tabBox, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
            fillTex:SetAllPoints(tabBox)
            Skin.AddBorder(tabBox, 0, 0, 0, 1)
            skinData.box = tabBox
            skinData.bg = fillTex
            local hoverTex = SolidTex(tabBtn, "HIGHLIGHT", 1, 1, 1, 0.1)
            hoverTex:SetPoint("TOPLEFT", tabBox, "TOPLEFT", 0, 0)
            hoverTex:SetPoint("BOTTOMRIGHT", tabBox, "BOTTOMRIGHT", 0, 0)
            skinData.hover = hoverTex
        end
        for _, g in ipairs({
            "GetNormalTexture",
            "GetPushedTexture",
            "GetDisabledTexture",
            "GetHighlightTexture",
        }) do
            local func = tabBtn[g]
            local part = func and func(tabBtn)
            if part and part ~= skinData.hover and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        -- Pin the glyph to its original anchor (no nudge: icons read off-center).
        -- Blizzard re-seats it on click/selection, so the pin re-asserts synchronously
        -- inside that SetPoint (reentry-guarded); single-point regions only, all-points state textures left alone.
        local regionList = { tabBtn:GetRegions() }
        for jdx = 1, #regionList do
            local region = regionList[jdx]
            if
                region
                and region ~= skinData.hover
                and region.IsObjectType
                and region:IsObjectType("Texture")
                and region.GetNumPoints
                and region:GetNumPoints() == 1
            then
                local regionData = GetFFD(region)
                if not regionData.pinned then
                    local point, relTo, relPoint, posX, posY = region:GetPoint(1)
                    if point then
                        regionData.pinned = true
                        regionData.pin = { point, relTo, relPoint, posX or 0, posY or 0 }
                        hooksecurefunc(region, "SetPoint", function()
                            if regionData.inPin then
                                return
                            end
                            regionData.inPin = true
                            region:ClearAllPoints()
                            region:SetPoint(regionData.pin[1], regionData.pin[2], regionData.pin[3], regionData.pin[4], regionData.pin[5])
                            regionData.inPin = false
                        end)
                    end
                end
            end
        end
        -- Disabled tabs read at half opacity: plate/border/icon dim together via the tab's own alpha.
        local enabled = not tabBtn.IsEnabled or tabBtn:IsEnabled()
        tabBtn:SetAlpha(enabled and 1 or 0.5)
        -- Tab 10% smaller (one-shot; the box follows its insets, the glyph keeps
        -- its native size).
        if not skinData.shrunk then
            local wid, hgt = tabBtn:GetSize()
            if wid and hgt and wid > 0 and hgt > 0 then
                skinData.shrunk = true
                tabBtn:SetSize(wid * 0.9, hgt * 0.9)
            end
        end
        PositionSideTab(tabBtn, index)
    end

    -- Loot row: parchment art gone, flat block, squared item icon, light subtext.
    local function SkinLootRow(btnFrame)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        if btnFrame.bossTexture and btnFrame.bossTexture.SetAlpha then
            btnFrame.bossTexture:SetAlpha(0)
        end
        if btnFrame.bosslessTexture and btnFrame.bosslessTexture.SetAlpha then
            btnFrame.bosslessTexture:SetAlpha(0)
        end
        local skinData = GetFFD(btnFrame)
        if not skinData.lootrow then
            skinData.lootrow = true
            local fillTex = btnFrame:CreateTexture(nil, "BACKGROUND", nil, -3)
            fillTex:SetColorTexture(Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
            fillTex:SetPoint("TOPLEFT", 1, -1)
            fillTex:SetPoint("BOTTOMRIGHT", -1, 1)
            skinData.bg = fillTex
            Skin.AddBorder(btnFrame)
            if btnFrame.icon then
                Skin.SquareIcon(btnFrame.icon, btnFrame)
            end
        end
        for _, keyName in ipairs({ "slot", "armorType", "boss" }) do
            local fontStr = btnFrame[keyName]
            if fontStr then
                Skin.White(fontStr, 0.82, 0.82, 0.82)
            end
        end
    end
    local function FlattenLootRows(widget, nestDepth)
        nestDepth = nestDepth or 0
        if not widget or nestDepth > 8 or widget:IsForbidden() or not widget.GetChildren then
            return
        end
        local children = { widget:GetChildren() }
        for idx = 1, #children do
            local child = children[idx]
            if child and not Skin.IsForeignFrame(child, widget) then
                if child.bossTexture and child.slot and child.GetObjectType and child:GetObjectType() == "Button" then
                    SkinLootRow(child)
                end
                FlattenLootRows(child, nestDepth + 1)
            end
        end
    end

    -- Gear-tab filter dropdowns: native caret faded, house arrow seated just past
    -- the label's MEASURED text end, re-seated on text change. Label rect is wider
    -- than the text, so anchoring to Blizzard's caret position sits it too far away.
    local function SwapFilterArrow(filt)
        if not filt then
            return
        end
        local fieldData = GetFFD(filt)
        if filt.Arrow and filt.Arrow.SetAlpha then
            filt.Arrow:SetAlpha(0)
        end
        if fieldData.arrow then
            return
        end
        local arrowTex = filt:CreateTexture(nil, "OVERLAY")
        arrowTex:SetAtlas("Azerite-PointingArrow")
        arrowTex:SetSize(12, 8.5)
        fieldData.arrow = arrowTex
        local labelText = filt.Text or (filt.GetFontString and filt:GetFontString())
        if labelText and labelText.GetStringWidth then
            local function seat()
                arrowTex:ClearAllPoints()
                -- GetStringWidth is the FULL untruncated width; a width-constrained
                -- label ellipsis-truncates, so hug the visible edge (label width), not the phantom one.
                local sw = labelText:GetStringWidth() or 0
                local lw = (labelText.GetWidth and labelText:GetWidth()) or 0
                if lw > 0 and sw > lw then
                    sw = lw
                end
                arrowTex:SetPoint("LEFT", labelText, "LEFT", sw + 4, 0)
            end
            seat()
            hooksecurefunc(labelText, "SetText", seat)
        elseif filt.Arrow then
            arrowTex:SetPoint("CENTER", filt.Arrow, "CENTER", 0, 0)
        else
            arrowTex:SetPoint("RIGHT", filt, "RIGHT", -6, 0)
        end
    end

    -- Ability/overview section header: paper art gone, flat block, white title,
    -- hover glow -> subtle whiten wash. Covers encounter-info headers (title +
    -- expandedIcon) and Overview headers (Title only, separate Glow child frame).
    -- All native art re-faded per pass since Blizzard repaints on expand/collapse.
    local function SkinAbilityHeaders(widget, nestDepth)
        nestDepth = nestDepth or 0
        if not widget or nestDepth > 9 or widget:IsForbidden() or not widget.GetChildren then
            return
        end
        local children = { widget:GetChildren() }
        for idx = 1, #children do
            local child = children[idx]
            if child and not Skin.IsForeignFrame(child, widget) then
                if child.descriptionBG and child.descriptionBG.SetAlpha then
                    child.descriptionBG:SetAlpha(0)
                end
                if child.descriptionBGBottom and child.descriptionBGBottom.SetAlpha then
                    child.descriptionBGBottom:SetAlpha(0)
                end
                -- Description bullets -> round status orb (first cell of the lootroll reveal sheet), white.
                local bulletTex = child.Bullet
                if bulletTex and bulletTex.SetTexture and not GetFFD(bulletTex).orbed then
                    GetFFD(bulletTex).orbed = true
                    local details = C_Texture
                        and C_Texture.GetAtlasInfo
                        and C_Texture.GetAtlasInfo("lootroll-animreveal-a")
                    if details and details.file then
                        local aL, aR = details.leftTexCoord or 0, details.rightTexCoord or 1
                        local aT, aB = details.topTexCoord or 0, details.bottomTexCoord or 1
                        bulletTex:SetTexture(details.file)
                        bulletTex:SetTexCoord(aL, aL + (aR - aL) / 6, aT, aT + (aB - aT) / 2)
                    else
                        bulletTex:SetAtlas("lootroll-animreveal-a")
                        bulletTex:SetTexCoord(0, 1 / 6, 0, 0.5)
                    end
                    bulletTex:SetVertexColor(1, 1, 1, 1)
                    local bw, bh = bulletTex:GetSize()
                    if bw and bh and bw > 0 and bh > 0 then
                        bulletTex:SetSize(bw + 2, bh + 2)
                    end
                end
                local button = child.button
                local bTitle = button and (button.title or button.Title)
                if button and bTitle then
                    local skinData = GetFFD(button)
                    if not skinData.abilrow then
                        skinData.abilrow = true
                        local fillTex = button:CreateTexture(nil, "BACKGROUND", nil, -2)
                        fillTex:SetColorTexture(Theme.bgR + 0.02, Theme.bgG + 0.02, Theme.bgB + 0.02, Theme.bgA)
                        fillTex:SetPoint("TOPLEFT", 0, -1)
                        fillTex:SetPoint("BOTTOMRIGHT", 0, 1)
                        skinData.bg = fillTex
                        Skin.AddBorder(button)
                        local hoverTex = SolidTex(button, "HIGHLIGHT", 1, 1, 1, 0.05)
                        hoverTex:SetPoint("TOPLEFT", 0, -1)
                        hoverTex:SetPoint("BOTTOMRIGHT", 0, 1)
                        skinData.hover = hoverTex
                    end
                    -- Every native texture region goes (paper caps, highlight strips,
                    -- anonymous art), keeping our fill+wash AND the boss ability icon
                    -- (<button>AbilityIcon) -- a real region the blanket fade would
                    -- strip unless preserved by name/parentKey.
                    local keepSet = { [skinData.bg] = true, [skinData.hover] = true }
                    local abIcon = button.AbilityIcon
                        or (button.GetName and button:GetName() and _G[button:GetName() .. "AbilityIcon"])
                    if abIcon then
                        keepSet[abIcon] = true
                    end
                    Skin.FadeRegions(button, keepSet)
                    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
                    if highlight and not keepSet[highlight] and highlight.SetAlpha then
                        highlight:SetAlpha(0)
                    end
                    -- Glow lives on a child frame found by name (parentKey varies).
                    local children2 = { button:GetChildren() }
                    for jdx = 1, #children2 do
                        local childFrame = children2[jdx]
                        if childFrame and childFrame.GetName then
                            local nm = childFrame:GetName()
                            if nm and nm:find("Glow", 1, true) and childFrame.SetAlpha then
                                Skin.FadeRegions(childFrame)
                                childFrame:SetAlpha(0)
                            end
                        end
                    end
                    Skin.White(bTitle)
                    if button.expandedIcon and button.expandedIcon.SetTextColor then
                        button.expandedIcon:SetTextColor(1, 1, 1)
                    end
                    -- Role icons (tank/healer/dps): 4px smaller. Hang off the header
                    -- button by GLOBAL name only (no parent key): <button>Icon1..4
                    -- frames, each with an <icon>Icon texture inside (also shrunk when
                    -- explicitly sized; all-points ones follow the frame).
                    if not skinData.iconShrunk then
                        skinData.iconShrunk = true
                        local bn = button.GetName and button:GetName()
                        local seen = {}
                        for jdx = 0, 4 do
                            local importControl
                            if jdx == 0 then
                                importControl = button.icon or button.Icon
                            else
                                importControl = button["Icon" .. jdx] or (bn and _G[bn .. "Icon" .. jdx])
                            end
                            if importControl and importControl.GetSize then
                                local wid, hgt = importControl:GetSize()
                                if wid and hgt and wid > 4 and hgt > 4 then
                                    importControl:SetSize(wid - 4, hgt - 4)
                                    local inner = importControl.Icon
                                        or (importControl.GetName and importControl:GetName() and _G[importControl:GetName() .. "Icon"])
                                    if inner and inner.GetSize then
                                        local iw, ih = inner:GetSize()
                                        if iw and ih and iw > 4 and ih > 4 then
                                            inner:SetSize(iw - 4, ih - 4)
                                        end
                                    end
                                end
                                -- 3px left, chain roots only: an icon chained to a
                                -- previous icon keeps its relative anchor since shifting the root moves the whole group.
                                local point, relTo, relPoint, posX, posY = importControl:GetPoint(1)
                                if point and not seen[relTo] then
                                    importControl:ClearAllPoints()
                                    importControl:SetPoint(point, relTo, relPoint, (posX or 0) - 3, posY or 0)
                                end
                                seen[importControl] = true
                            end
                        end
                    end
                end
                SkinAbilityHeaders(child, nestDepth + 1)
            end
        end
    end

    -- Instance-select pane scene (shared by Tutorials and Dungeons/Raids) drops
    -- alpha so the shell shows through: true translucency, not a darken. The art is
    -- $parentBG plus anonymous BACKGROUND regions; every BACKGROUND texture above
    -- 50% is lowered (never raised, so art already faded stays faded). Re-applied
    -- per refresh pass in case Blizzard re-asserts.
    local function RestyleInstanceScene(isel)
        if not isel then
            return
        end
        local regionList = { isel:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region.IsObjectType and region:IsObjectType("Texture") and region:GetDrawLayer() == "BACKGROUND" then
                local alpha = region:GetAlpha() or 1
                if alpha > 0.5 then
                    region:SetAlpha(0.25)
                end
            end
        end
    end

    -- Great Vault shortcut (top right of Journeys/instance views): same vault art
    -- as the minimap's button, state textures retextured in place (geometry/anchors/hover untouched).
    local VAULT_BUTTON_ATLAS = "greatVault-whole-normal"
    local function RestyleGreatVaultButton(gv)
        if not gv or gv:IsForbidden() then
            return
        end
        local skinData = GetFFD(gv)
        -- 14px smaller (one-shot; retries until the button has a laid-out size).
        if not skinData.shrunk then
            local wid, hgt = gv:GetSize()
            if wid and hgt and wid > 14 and hgt > 14 then
                skinData.shrunk = true
                gv:SetSize(wid - 14, hgt - 14)
            end
        end
        -- 4px right of wherever Blizzard seats it, applied relative to the CURRENT
        -- anchor via a SetPoint post-hook so per-view repositioning is kept (a fixed
        -- captured anchor would bleed the Journeys position onto other tabs).
        if not skinData.nudged then
            skinData.nudged = true
            local function nudge()
                if skinData.inNudge then
                    return
                end
                local point, relTo, relPoint, posX, posY = gv:GetPoint(1)
                if not point then
                    return
                end
                skinData.inNudge = true
                gv:ClearAllPoints()
                gv:SetPoint(point, relTo, relPoint, (posX or 0) + 4, posY or 0)
                skinData.inNudge = false
            end
            hooksecurefunc(gv, "SetPoint", nudge)
            nudge()
        end
        if skinData.vaultSwapped then
            return
        end
        local swapped = false
        for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
            local part = gv[getter] and gv[getter](gv)
            if part and part.SetAtlas then
                part:SetAtlas(VAULT_BUTTON_ATLAS)
                swapped = true
            end
        end
        local regionList = { gv:GetRegions() }
        for jdx = 1, #regionList do
            local region = regionList[jdx]
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                local hay = Skin.TexHay(region)
                if hay and hay:find("vault", 1, true) then
                    region:SetAtlas(VAULT_BUTTON_ATLAS)
                    swapped = true
                end
            end
        end
        if swapped then
            skinData.vaultSwapped = true
        end
    end

    -- Round creature portraits: delve companion ring as circle border, sized 2px
    -- outside the CREATURE texture (not its frame), no plate -- their field shape
    -- matches the boss-row pass, which would otherwise light-background them. No
    -- active/inactive styling.
    local function RingCreatureFrame(creatureBtn, creature)
        if not creatureBtn or creatureBtn:IsForbidden() then
            return
        end
        local skinData = GetFFD(creatureBtn)
        creature = creature or creatureBtn.creature or creatureBtn.Creature
        if not creature then
            local n = creatureBtn.GetName and creatureBtn:GetName()
            creature = n and _G[n .. "Creature"] or nil
        end
        if not skinData.ring then
            local ring = creatureBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            ring:SetAtlas("UI-Journeys-Delve-Companion-Ring")
            -- 2px outset per side (4px larger than the portrait).
            local anchor = creature or creatureBtn
            ring:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, 2)
            ring:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 2, -2)
            skinData.ring = ring
            skinData.creature = creature
        end
        -- Neutralize the white plate laid on by the boss-row pass.
        if skinData.bg then
            skinData.bg:SetColorTexture(0, 0, 0, 0)
        end
    end

    local function SkinCreatureButtons()
        for idx = 1, 9 do
            local creatureBtn = _G["EncounterJournalEncounterFrameInfoCreatureButton" .. idx]
            if not creatureBtn then
                break
            end
            RingCreatureFrame(creatureBtn)
        end
        -- Main creature display: anonymous child of info carrying a CircleMask;
        -- its portrait is the info-named Creature texture.
        local details = _G.EncounterJournalEncounterFrameInfo
        if details then
            local children = { details:GetChildren() }
            for idx = 1, #children do
                local childFrame = children[idx]
                if childFrame and childFrame.CircleMask and not GetFFD(childFrame).ring then
                    local creature = _G.EncounterJournalEncounterFrameInfoCreature
                    if creature and creature.GetParent and creature:GetParent() ~= childFrame then
                        creature = nil
                    end
                    RingCreatureFrame(childFrame, creature)
                end
            end
        end
    end

    local _ejHooked = false
    local function Skin_EncounterJournal()
        local win = _G.EncounterJournal
        if not win then
            return
        end
        Skin.Shell("adventureguide", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "EncounterJournal")
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if _G.EncounterJournalBg then
            _G.EncounterJournalBg:SetAlpha(0)
        end
        for _, keyName in ipairs({ "inset", "Inset" }) do
            if win[keyName] then
                Skin.Inset(win[keyName])
            end
        end

        -- The scene background (instanceSelect.evergreenBg) is shared by Tutorials
        -- and Dungeons/Raids and IS the content there, so every art sweep skips
        -- those subtrees; instance tiles still get squared by FlattenInstanceButtons (a targeted pass, not a sweep).
        if win.TutorialsFrame then
            Skin.ExemptArt(win.TutorialsFrame)
        end
        if win.instanceSelect then
            Skin.ExemptArt(win.instanceSelect)
        end

        -- Breadcrumb bar: faint 5% white wash (no border), seated 8px lower and
        -- 35px left of Blizzard's spot, white crumbs with dividers. Reseat is idempotent (original anchors captured once).
        local navBar = win.navBar
        local function RefreshNav()
            RestyleNavGeneric(navBar, -37, -8)
        end
        _navReflow = RefreshNav
        if navBar then
            GetFFD(navBar).reflow = RefreshNav
        end
        RefreshNav()

        if win.LootJournalViewDropdown then
            Skin.Dropdown(win.LootJournalViewDropdown)
        end
        if win.searchBox then
            Skin.EditBox(win.searchBox)
            -- Seat 2px lower than Blizzard's spot (idempotent, original anchor captured once).
            local partData = GetFFD(win.searchBox)
            if partData.origP == nil then
                local point, relTo, relPoint, posX, posY = win.searchBox:GetPoint(1)
                if point then
                    partData.origP, partData.origRel, partData.origRP = point, relTo, relPoint
                    partData.origX, partData.origY = posX or 0, posY or 0
                end
            end
            if partData.origP then
                win.searchBox:ClearAllPoints()
                win.searchBox:SetPoint(partData.origP, partData.origRel, partData.origRP, partData.origX, partData.origY - 2)
            end
        end
        -- Search autocomplete popout + full results window: container -> flat dark
        -- panel; preview rows + "show all results" -> subtle hover + white text;
        -- results window -> panel + slim scrollbar + house close button.
        local sbox = win.searchBox
        local prevC = sbox and sbox.searchPreviewContainer
        if prevC then
            Skin.Panel(prevC)
            -- framed = the button is its OWN panel (bg + border). Preview rows sit
            -- inside the container's panel so need none; showAllResults is a SIBLING
            -- below the container with no backdrop, so it gets its own fill+border.
            local function SkinEJSearchBtn(btnFrame, framed)
                if not btnFrame or btnFrame:IsForbidden() then
                    return
                end
                local skinData = GetFFD(btnFrame)
                if not skinData.ejSearchSkinned then
                    skinData.ejSearchSkinned = true
                    local glyphTex = btnFrame.icon or btnFrame.Icon
                    local keepSet = glyphTex and { [glyphTex] = true } or nil
                    Skin.FadeRegions(btnFrame, keepSet)
                    if framed then
                        local bgTex = btnFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
                        bgTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
                        bgTex:SetAllPoints(btnFrame)
                        skinData.bg = bgTex
                        Skin.AddBorder(btnFrame)
                    end
                    local hoverTex = SolidTex(btnFrame, "HIGHLIGHT", 1, 1, 1, 0.1)
                    hoverTex:SetAllPoints(btnFrame)
                    skinData.hover = hoverTex
                    Skin.Register(btnFrame, keepSet or true)
                    if glyphTex then
                        Skin.SquareIcon(glyphTex, btnFrame)
                    end
                end
                if btnFrame.selectedTexture and btnFrame.selectedTexture.SetColorTexture then
                    btnFrame.selectedTexture:SetColorTexture(1, 1, 1, 0.12)
                end
                for _, keyName in ipairs({ "name", "text", "resultType" }) do
                    local fontStr = btnFrame[keyName]
                    if fontStr and fontStr.SetTextColor then
                        Skin.White(fontStr)
                    end
                end
            end
            local function SkinAllEJSearch()
                -- Re-assert the container panel: Blizzard re-raises corner art on popout show, hiding our border.
                Skin.Panel(prevC)
                for idx = 1, (_G.EJ_NUM_SEARCH_PREVIEWS or 5) do
                    SkinEJSearchBtn(sbox["searchPreview" .. idx])
                end
                SkinEJSearchBtn(sbox.showAllResults, true)
            end
            SkinAllEJSearch()
            -- Preview rows re-populate as you type; re-white after each update.
            if not GetFFD(sbox).searchHook and type(_G.EncounterJournal_SetSearchPreview) == "function" then
                GetFFD(sbox).searchHook = true
                hooksecurefunc("EncounterJournal_SetSearchPreview", SkinAllEJSearch)
            end
        end
        local sr = _G.EncounterJournalSearchResults
        if sr then
            Skin.Panel(sr)
            if sr.ScrollBar then
                Skin.ScrollBar(sr.ScrollBar)
            end
            local creatureBtn = _G.EncounterJournalSearchResultsCloseButton or sr.CloseButton
            if creatureBtn then
                Skin.CloseButton(creatureBtn)
            end
        end
        if win.instanceSelect then
            if win.instanceSelect.ExpansionDropdown then
                Skin.Dropdown(win.instanceSelect.ExpansionDropdown)
            end
            if win.instanceSelect.Title then
                Skin.White(win.instanceSelect.Title)
            end
            FlattenInstanceButtons(win.instanceSelect)
        end
        if win.encounter and win.encounter.info and win.encounter.info.difficulty then
            local diff = win.encounter.info.difficulty
            Skin.Dropdown(diff)
            -- Seat 4px left of Blizzard's spot (idempotent: original anchor captured once).
            local dropdown = GetFFD(diff)
            if dropdown.origP == nil then
                local point, relTo, relPoint, posX, posY = diff:GetPoint(1)
                if point then
                    dropdown.origP, dropdown.origRel, dropdown.origRP = point, relTo, relPoint
                    dropdown.origX, dropdown.origY = posX or 0, posY or 0
                end
            end
            if dropdown.origP then
                diff:ClearAllPoints()
                diff:SetPoint(
                    dropdown.origP,
                    dropdown.origRel,
                    dropdown.origRP,
                    dropdown.origX - 6,
                    dropdown.origY
                )
            end
        end

        local ejTabs = {}
        for _, keyName in ipairs({
            "JourneysTab",
            "MonthlyActivitiesTab",
            "suggestTab",
            "dungeonsTab",
            "raidsTab",
            "LootJournalTab",
            "TutorialsTab",
        }) do
            local t = win[keyName]
            if t then
                Skin.Tab(t)
                ejTabs[#ejTabs + 1] = t
            end
        end
        Skin.NormalizeTabRow(ejTabs)

        if win.instanceSelect then
            RestyleGreatVaultButton(win.instanceSelect.GreatVaultButton)
            RestyleInstanceScene(win.instanceSelect)
        end

        local function RefreshSuggest()
            local scrollFrame = win.suggestFrame
            if not scrollFrame then
                return
            end
            WhitenTextIn(scrollFrame)
            -- The three suggestion panels keep their big artwork: exempt their
            -- subtrees from the art fade and restore the bg it zeroed.
            for idx = 1, 3 do
                local cfg = scrollFrame["Suggestion" .. idx]
                if cfg then
                    Skin.ExemptArt(cfg)
                    if cfg.bg then
                        cfg.bg:SetAlpha(0.4)
                    end
                end
            end
            local s1 = scrollFrame.Suggestion1
            if s1 then
                if s1.prevButton then
                    Skin.PageButton(s1.prevButton, "<", 12)
                end
                if s1.nextButton then
                    Skin.PageButton(s1.nextButton, ">", 12)
                end
                -- Hero suggestion action button label 2px smaller (target captured once,
                -- re-asserted since Blizzard re-applies its font object on refresh).
                local buttonText = s1.button and s1.button.GetFontString and s1.button:GetFontString()
                if buttonText then
                    local filePath, sz, flags = buttonText:GetFont()
                    if filePath and sz then
                        local buttonData = GetFFD(buttonText)
                        if not buttonData.size then
                            buttonData.size = sz - 2
                        end
                        if math.abs(sz - buttonData.size) > 0.01 then
                            buttonText:SetFont(filePath, buttonData.size, flags)
                        end
                    end
                end
            end
        end
        RefreshSuggest()

        -- Traveler's Log: seat the info (help) button on the window's left edge,
        -- keeping its vertical spot. Anchored to the WINDOW, not the inset activities
        -- pane (its left edge is not the window's). Retries until laid out.
        local function SeatMonthlyHelp()
            local menuArrow = win.MonthlyActivitiesFrame
            local hb = menuArrow and menuArrow.HelpButton
            if not hb or GetFFD(hb).moved then
                return
            end
            local top, fTop = hb:GetTop(), win:GetTop()
            if top and fTop then
                GetFFD(hb).moved = true
                hb:ClearAllPoints()
                hb:SetPoint("TOPLEFT", win, "TOPLEFT", 4, top - fTop)
            end
        end
        SeatMonthlyHelp()

        -- Boss detail "book": strip parchment, flatten rows, white the text.
        local function RefreshDetail()
            local e = win.encounter
            if not e then
                return
            end
            if _G.EncounterJournalEncounterFrameInfoBG then
                _G.EncounterJournalEncounterFrameInfoBG:SetAlpha(0)
            end
            local details = e.info
            if details then
                for _, keyName in ipairs({ "leftShadow", "rightShadow", "titleBG" }) do
                    local part = details[keyName]
                    if part and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
                -- Model tab: scene backdrop + vignette re-texture per encounter, so re-fade each pass.
                for _, n in ipairs({
                    "EncounterJournalEncounterFrameInfoModelFrameDungeonBG",
                    "EncounterJournalEncounterFrameInfoModelFrameShadow",
                }) do
                    local part = _G[n]
                    if part and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
                local lc = details.LootContainer
                if lc then
                    for _, keyName in ipairs({ "bossTexture", "bosslessTexture" }) do
                        local part = lc[keyName]
                        if part and part.SetAlpha then
                            part:SetAlpha(0)
                        end
                    end
                    FlattenLootRows(lc)
                    -- Pooled rows: scrolling realizes/re-inits frames via paths that
                    -- fire no journal repaint, bringing Blizzard's art back on
                    -- scroll-up. Re-skin realized rows on every ScrollBox update (cost scales with visible rows only).
                    local scrollBar = lc.ScrollBox
                    if scrollBar and scrollBar.ForEachFrame then
                        pcall(scrollBar.ForEachFrame, scrollBar, SkinLootRow)
                        if scrollBar.Update and not GetFFD(scrollBar).rowHook then
                            GetFFD(scrollBar).rowHook = true
                            hooksecurefunc(scrollBar, "Update", function(tabBox)
                                pcall(tabBox.ForEachFrame, tabBox, SkinLootRow)
                            end)
                        end
                    end
                    -- Gear tab filters: house arrows hugging the label text.
                    SwapFilterArrow(lc.filter)
                    SwapFilterArrow(lc.slotFilter)
                end
                local sideTabs = { "overviewTab", "lootTab", "bossTab", "modelTab" }
                for idx = 1, #sideTabs do
                    SkinSideTab(details[sideTabs[idx]], idx)
                end
                -- Vertical divider down the center of the detail view. The info
                -- frame spans the whole detail area (boss list lives INSIDE it),
                -- so the true split is the boss list's right edge.
                local ed = GetFFD(details)
                local bossList = details.BossesScrollBox
                if bossList and not ed.centerDivider then
                    local div = details:CreateTexture(nil, "ARTWORK")
                    div:SetColorTexture(1, 1, 1, 0.15)
                    div:SetWidth(1)
                    div:SetPoint("TOPLEFT", bossList, "TOPRIGHT", 24, 8)
                    div:SetPoint("BOTTOMLEFT", bossList, "BOTTOMRIGHT", 24, 12)
                    ed.centerDivider = div
                end
                if
                    details.overviewScroll
                    and details.overviewScroll.child
                    and details.overviewScroll.child.header
                    and details.overviewScroll.child.header.SetAlpha
                then
                    details.overviewScroll.child.header:SetAlpha(0)
                end
            end
            if e.instance and e.instance.titleBG and e.instance.titleBG.SetAlpha then
                e.instance.titleBG:SetAlpha(0)
            end
            SkinAbilityHeaders(e)
            FadeEJArt(e)
            FlattenBossButtons(e)
            SkinCreatureButtons()
            WhitenTextIn(e)
        end
        RefreshDetail()

        FadeEJArt(win)
        Skin.ButtonsIn(win)
        Skin.ScrollBarsIn(win)
        Skin.FadeKeyedArt(win)

        -- Blizzard repopulates the detail panes on navigation; the hooks fire many
        -- times per click, so the pass is debounced and skipped while hidden.
        if not _ejHooked then
            _ejHooked = true
            local refresh = Skin.Debounce(function()
                if not win:IsVisible() then
                    return
                end
                RefreshDetail()
                RefreshNav()
                if win.instanceSelect then
                    FlattenInstanceButtons(win.instanceSelect)
                    RestyleGreatVaultButton(win.instanceSelect.GreatVaultButton)
                    RestyleInstanceScene(win.instanceSelect)
                end
                SeatMonthlyHelp()
                Skin.Restrip()
            end)
            local function deferRefresh()
                -- Kill the biggest parchment synchronously so it cannot flash a
                -- frame before the debounced pass runs.
                if _G.EncounterJournalEncounterFrameInfoBG then
                    _G.EncounterJournalEncounterFrameInfoBG:SetAlpha(0)
                end
                refresh()
            end
            for _, func in ipairs({
                "EncounterJournal_DisplayInstance",
                "EncounterJournal_DisplayEncounter",
                "EncounterJournal_SetUpOverview",
                "EncounterJournal_ToggleHeaders",
                "EncounterJournal_SetTab",
                "EJ_ContentTab_Select",
                "NavBar_AddButton",
            }) do
                if type(_G[func]) == "function" then
                    hooksecurefunc(func, deferRefresh)
                end
            end
            -- The debounced pass runs a frame late, so a new crumb would render one
            -- frame at Blizzard's layout (a visible snap). Reflow the nav
            -- synchronously the moment a crumb is added; cheap (a handful of buttons).
            if type(_G.NavBar_AddButton) == "function" then
                hooksecurefunc("NavBar_AddButton", function(barFrame)
                    if barFrame == navBar then
                        RefreshNav()
                    end
                end)
            end
            if type(_G.EJSuggestFrame_RefreshDisplay) == "function" then
                hooksecurefunc("EJSuggestFrame_RefreshDisplay", Skin.Debounce(RefreshSuggest))
            end
            -- Global Options edits (link color) re-run the text passes live.
            Skin.OnLooksChanged(function()
                if win:IsVisible() then
                    deferRefresh()
                    RefreshSuggest()
                end
            end)
        end

        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    RefreshDetail()
                    RefreshNav()
                    if win.instanceSelect then
                        RestyleGreatVaultButton(win.instanceSelect.GreatVaultButton)
                        RestyleInstanceScene(win.instanceSelect)
                    end
                    Skin.Restrip()
                    Skin.UpdateAllTabs()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "adventureguide",
        addons = { Blizzard_EncounterJournal = true },
        apply = Skin_EncounterJournal,
    })
end

-------------------------------------------------------------------------------
--  Professions Book (ProfessionsBookFrame)
-------------------------------------------------------------------------------
do
    local PROF_FRAMES = {
        "PrimaryProfession1",
        "PrimaryProfession2",
        "SecondaryProfession1",
        "SecondaryProfession2",
        "SecondaryProfession3",
    }

    -- Settle gate: Shifter applies the user's scale on OnShow AFTER the book has
    -- shown, so content reflows across several passes on a scaled reopen; text
    -- seating run mid-reflow nudges strings from a transient baseline and the
    -- correction stacks (text flung 60-70px off). Seat ONLY when the content
    -- geometry signature matches the prior pass; while moving, skip and schedule one trailing pass.
    local _profSettleSig, _profSettlePending
    local function ProfContentSig()
        local sig = 0
        for _, n in ipairs(PROF_FRAMES) do
            local found = _G[n]
            if found then
                local t = found.GetTop and found:GetTop()
                local scrollBar = found.statusBar
                local bt = scrollBar and scrollBar.GetTop and scrollBar:GetTop()
                sig = sig + (t or 0) * 7 + (bt or 0) * 13
            end
        end
        return sig
    end

    local function SkinProfSpellButton(button)
        if not button then
            return
        end
        local bn = button.GetName and button:GetName()
        if bn then
            local nf = _G[bn .. "NameFrame"]
            if nf and nf.SetAlpha then
                nf:SetAlpha(0)
            end
        end
        for _, keyName in ipairs({ "Border", "FlyoutBorder", "FlyoutBorderShadow", "Background", "Flash" }) do
            local part = button[keyName]
            if part and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        local nt = button.GetNormalTexture and button:GetNormalTexture()
        if nt and nt.SetAlpha then
            nt:SetAlpha(0)
        end
        local glyphTex = button.IconTexture or (bn and _G[bn .. "IconTexture"])
        if glyphTex then
            Skin.SquareIcon(glyphTex, button)
        end
        if button.spellString then
            Skin.Font(button.spellString)
            Skin.White(button.spellString)
        end
        if button.subSpellString then
            Skin.Font(button.subSpellString)
            Skin.White(button.subSpellString, 0.8, 0.8, 0.8)
        end
    end

    local function SkinProfStatusBar(scrollBar)
        if not scrollBar then
            return
        end
        local n = scrollBar.GetName and scrollBar:GetName()
        if n then
            for _, suf in ipairs({ "Left", "Right", "BGLeft", "BGMiddle", "BGRight" }) do
                local part = _G[n .. suf]
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
        end
        if scrollBar.capRight and scrollBar.capRight.SetAlpha then
            scrollBar.capRight:SetAlpha(0)
        end
        if scrollBar.SetStatusBarTexture then
            scrollBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            Skin.ApplyBarFill(scrollBar)
        end
        local skinData = GetFFD(scrollBar)
        -- Blizzard's bar VISUAL (cap + middle + cap art) is wider than the StatusBar
        -- frame, so the flat fill reads short and skews text anchored around it.
        -- Stretch the frame to the art's measured span, but ONLY when the art sits
        -- a plausible cap-width (<= 20px) away: a bigger delta means a different
        -- row layout (secondary rows), and moving the bar would yank those off their tiles.
        if not skinData.stretched and n and not InCombatLockdown() then
            local bgl, bgr = _G[n .. "BGLeft"], _G[n .. "BGRight"]
            local L = bgl and bgl.GetLeft and bgl:GetLeft()
            local R = bgr and bgr.GetRight and bgr:GetRight()
            local sL = scrollBar.GetLeft and scrollBar:GetLeft()
            if L and R and sL and R > L then
                skinData.stretched = true
                local delta = L - sL
                if math.abs(delta) <= 20 then
                    local point, relTo, relPoint, posX, posY = scrollBar:GetPoint(1)
                    if point and point:find("LEFT", 1, true) then
                        scrollBar:ClearAllPoints()
                        scrollBar:SetPoint(point, relTo, relPoint, (posX or 0) + delta, posY or 0)
                    end
                    scrollBar:SetWidth(R - L)
                end
            end
        end
        if not skinData.bg then
            local bgTex = scrollBar:CreateTexture(nil, "BACKGROUND", nil, -1)
            bgTex:SetColorTexture(0.12, 0.12, 0.12, 0.85)
            bgTex:SetAllPoints(scrollBar)
            skinData.bg = bgTex
            Skin.AddBorder(scrollBar)
        end
        if scrollBar.rankText then
            Skin.Font(scrollBar.rankText)
            Skin.White(scrollBar.rankText)
            -- 3px lower (one-shot).
            local regionData = GetFFD(scrollBar.rankText)
            if not regionData.lowered then
                local point, relTo, relPoint, posX, posY = scrollBar.rankText:GetPoint(1)
                if point then
                    regionData.lowered = true
                    scrollBar.rankText:ClearAllPoints()
                    scrollBar.rankText:SetPoint(point, relTo, relPoint, posX or 0, (posY or 0) - 3)
                end
            end
        end
    end

    local function RecolorProfessions()
        -- Profession frames chain to each other; a chained frame inherits the shift
        -- of the frame it hangs from, so only chain roots get the x offset
        -- (shifting every frame would compound 30px per row down the chain).
        local profSet = {}
        for _, n in ipairs(PROF_FRAMES) do
            local found = _G[n]
            if found then
                profSet[found] = true
            end
        end
        -- Text seating runs only on a settled layout (signature matches prior pass);
        -- while reflowing (Shifter-scaled reopen) skip and queue one trailing pass.
        -- The one-shot geometry below is idempotent and runs every pass; only the
        -- delta-nudge seating is gated.
        local sig = ProfContentSig()
        local seatOK = (_profSettleSig ~= nil) and (math.abs(sig - _profSettleSig) <= 0.5)
        _profSettleSig = sig
        if not seatOK and not _profSettlePending then
            _profSettlePending = true
            C_Timer.After(0.05, function()
                _profSettlePending = false
                local popFrame = _G.ProfessionsBookFrame
                if popFrame and popFrame:IsVisible() then
                    RecolorProfessions()
                end
            end)
        end
        for _, n in ipairs(PROF_FRAMES) do
            local found = _G[n]
            if found then
                -- Content reaches 30px further left, right edge unchanged (one-shot;
                -- left-anchored roots shift+widen, right-anchored just widen
                -- leftward). Row frames are PROTECTED (host secure profession spell
                -- buttons), so combat blocks geometry writes: skip WITHOUT setting
                -- the one-shot flag, letting the next OOC repaint apply it.
                local foundData = GetFFD(found)
                if not foundData.extended and not InCombatLockdown() then
                    local point, relTo, relPoint, posX, posY = found:GetPoint(1)
                    local wid = found:GetWidth()
                    if point and wid and wid > 0 then
                        foundData.extended = true
                        if point:find("LEFT", 1, true) and not profSet[relTo] then
                            found:ClearAllPoints()
                            found:SetPoint(point, relTo, relPoint, (posX or 0) - 30, posY or 0)
                        end
                        found:SetWidth(wid + 30)
                        -- Rects are stale right after re-anchor; let text alignment below measure on the NEXT pass.
                        foundData.skipAlignOnce = true
                    end
                end
                -- Primary tiles: big left icon 12px smaller, seated 10px lower
                -- (one-shot; border lines follow its rect). Secondary: icon 2px smaller.
                local isPrimary = n:find("Primary", 1, true) ~= nil
                if found.icon and not foundData.iconAdj then
                    local iw, ih = found.icon:GetSize()
                    if iw and ih and iw > 12 and ih > 12 then
                        foundData.iconAdj = true
                        local shrink = isPrimary and 12 or 2
                        found.icon:SetSize(iw - shrink, ih - shrink)
                        if isPrimary then
                            local point, relTo, relPoint, posX, posY = found.icon:GetPoint(1)
                            if point then
                                found.icon:ClearAllPoints()
                                found.icon:SetPoint(point, relTo, relPoint, posX or 0, (posY or 0) - 10)
                            end
                        end
                    end
                end
                -- Bar cluster rises 20px on learned primaries to close the gap the
                -- title drop opens. MUST run before text seating, or a bar-anchored
                -- skill line double-shifts (targets need post-raise geometry).
                SkinProfStatusBar(found.statusBar, isPrimary and 20 or 0)
                if isPrimary then
                    local ub = found.unlearn
                        or found.UnlearnButton
                        or _G[n .. "Unlearn"]
                        or _G[n .. "UnlearnButton"]
                    if ub and not GetFFD(ub).raised and not InCombatLockdown() then
                        local point, relTo, relPoint, posX, posY = ub:GetPoint(1)
                        if point then
                            GetFFD(ub).raised = true
                            if relTo ~= found.statusBar and relTo ~= found.rank then
                                ub:ClearAllPoints()
                                ub:SetPoint(point, relTo, relPoint, posX or 0, (posY or 0) + 20)
                            end
                        end
                    end
                end
                -- Text seating re-runs every pass since Blizzard re-anchors these
                -- strings (one-shots get stomped): delta-based against measured
                -- targets (bar-left for x, captured top minus drop for y), so an
                -- already-seated string is a no-op. Learned primary titles drop 20px;
                -- unlearned header stays put (else a blank band opens above "Second
                -- Profession"); skill line rises 20 only when off the bar.
                if foundData.skipAlignOnce then
                    foundData.skipAlignOnce = nil
                elseif seatOK then
                    local sbL = found.statusBar and found.statusBar.GetLeft and found.statusBar:GetLeft()
                    -- Y target is a gap from the FRAME top, never absolute local-Y:
                    -- GetTop deltas are scale-invariant since a frame and its strings
                    -- share one effective scale, but local-Y shifts with scale and
                    -- would fling every string ~300px on a scale change + reopen.
                    local frameTop = found.GetTop and found:GetTop()
                    if sbL and frameTop then
                        local rankRel = found.rank and found.rank.GetPoint and select(2, found.rank:GetPoint(1))
                        -- Anything the BAR hangs from (directly or up its chain) must
                        -- NOT be aligned TO the bar: moving such a string drags the bar
                        -- with it and the cluster creeps 1px left per open.
                        local barChain = {}
                        do
                            local node = found.statusBar
                            for _ = 1, 4 do
                                if not (node and node.GetPoint) then
                                    break
                                end
                                local _, rel2 = node:GetPoint(1)
                                if not rel2 then
                                    break
                                end
                                barChain[rel2] = true
                                node = rel2
                            end
                        end
                        local strings = {
                            { fs = found.professionName, alignX = true, drop = isPrimary and 20 or 0 },
                            {
                                fs = found.rank,
                                alignX = true,
                                drop = (isPrimary and rankRel ~= found.statusBar) and -20 or 0,
                            },
                            { fs = found.missingHeader, alignX = false, drop = 0 },
                        }
                        for _, s in ipairs(strings) do
                            local fontStr = s.fs
                            if fontStr and fontStr.GetLeft then
                                local l, t = fontStr:GetLeft(), fontStr:GetTop()
                                if l and t then
                                    local titleData = GetFFD(fontStr)
                                    -- Title capture sanity: the profession name always
                                    -- sits ABOVE its bar, so a mid-relayout capture
                                    -- (name at/below bar) would lock a bogus gap.
                                    -- Skip until a settled pass measures it above.
                                    if
                                        fontStr == found.professionName
                                        and titleData.gapTop == nil
                                        and found.statusBar
                                        and found.statusBar.GetTop
                                    then
                                        local barTop = found.statusBar:GetTop()
                                        if barTop and t <= barTop then
                                            l = nil -- stale measure; skip this pass
                                        end
                                    end
                                    -- Capture the default gap from the frame top
                                    -- once, then drive to frameTop + gap - drop.
                                    if l and titleData.gapTop == nil then
                                        titleData.gapTop = t - frameTop
                                    end
                                    local targetTop = titleData.gapTop and (frameTop + titleData.gapTop - s.drop)
                                    if l and targetTop then
                                        -- WHOLE pixels only: rects are quantized but point
                                        -- offsets are continuous, so a fractional residual
                                        -- re-measures every pass and creeps the cluster ~1px left per open.
                                        local wantX = s.alignX and not barChain[fontStr]
                                        local dx = math.floor((wantX and (sbL - l) or 0) + 0.5)
                                        local dy = math.floor((targetTop - t) + 0.5)
                                        if dx ~= 0 or dy ~= 0 then
                                            local point, relTo, relPoint, posX, posY = fontStr:GetPoint(1)
                                            if point then
                                                fontStr:ClearAllPoints()
                                                fontStr:SetPoint(
                                                    point,
                                                    relTo,
                                                    relPoint,
                                                    (posX or 0) + dx,
                                                    (posY or 0) + dy
                                                )
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                -- Tile backdrop: dialog sheet art at half strength, padded past the
                -- frame so content never crowds the card edges. Top pad stays SMALL,
                -- else a tall card overlaps the row above and cuts a seam through it.
                if not foundData.bg then
                    local bgTex = found:CreateTexture(nil, "BACKGROUND", nil, -6)
                    bgTex:SetAtlas("Ui-Dialog-New-Background")
                    -- Primary tiles are taller than content: pinched card with bottom
                    -- pulled up (bar cluster rides 20px higher) keeps a visible gap
                    -- between the two primary cards. Secondary rows get 6px extra height above/below.
                    local topY = isPrimary and -4 or 10
                    local botY = isPrimary and 6 or -16
                    bgTex:SetPoint("TOPLEFT", found, "TOPLEFT", -16, topY)
                    bgTex:SetPoint("BOTTOMRIGHT", found, "BOTTOMRIGHT", 16, botY)
                    bgTex:SetAlpha(0.5)
                    foundData.bg = bgTex
                    foundData.bgBottomY = botY
                end
                -- Secondary rows lay rank bar BELOW the frame's rect; drop the card bottom under it once geometry is readable.
                if foundData.bg and not foundData.bgFit then
                    local foundBottom = found.GetBottom and found:GetBottom()
                    local bb = found.statusBar and found.statusBar.GetBottom and found.statusBar:GetBottom()
                    if foundBottom then
                        foundData.bgFit = true
                        if bb and bb < foundBottom then
                            foundData.bg:SetPoint("BOTTOMRIGHT", found, "BOTTOMRIGHT", 16, (bb - foundBottom) - 16)
                        end
                    end
                end
                if found.professionName then
                    Skin.Font(found.professionName)
                    Skin.White(found.professionName)
                end
                if found.missingHeader then
                    Skin.Font(found.missingHeader)
                    Skin.White(found.missingHeader)
                end
                if found.rank then
                    Skin.Font(found.rank)
                    Skin.White(found.rank)
                end
                if found.missingText then
                    Skin.Font(found.missingText)
                    Skin.White(found.missingText)
                end

                local ib = _G[n .. "IconBorder"]
                if ib and ib.SetAlpha then
                    ib:SetAlpha(0)
                end
                if found.icon then
                    if found.CircleMask and found.icon.RemoveMaskTexture then
                        pcall(found.icon.RemoveMaskTexture, found.icon, found.CircleMask)
                    end
                    if found.icon.SetBlendMode then
                        found.icon:SetBlendMode("BLEND")
                    end
                    if found.icon.SetDesaturated then
                        found.icon:SetDesaturated(false)
                    end
                    Skin.SquareIcon(found.icon, found)
                end

                SkinProfSpellButton(found.SpellButton1)
                SkinProfSpellButton(found.SpellButton2)
            end
        end

        -- Both primary cards render at the same height: once both are measurable the shorter one's bottom extends by the difference (one-shot).
        local p1, p2 = _G.PrimaryProfession1, _G.PrimaryProfession2
        local d1, d2 = p1 and FFD[p1], p2 and FFD[p2]
        if d1 and d2 and d1.bg and d2.bg and not d1.eqDone then
            local h1, h2 = d1.bg:GetHeight(), d2.bg:GetHeight()
            if h1 and h2 and h1 > 0 and h2 > 0 then
                d1.eqDone = true
                if math.abs(h1 - h2) > 0.5 then
                    local partData = (h1 < h2) and d1 or d2
                    local scrollFrame = (h1 < h2) and p1 or p2
                    -- Never extend past 2px below the frame: an uncapped match
                    -- runs the card into the next tile and eats the gap.
                    partData.bg:SetPoint(
                        "BOTTOMRIGHT",
                        scrollFrame,
                        "BOTTOMRIGHT",
                        16,
                        math.max((partData.bgBottomY or 6) - math.abs(h1 - h2), -2)
                    )
                end
            end
        end
    end

    local _profHook = false
    local function Skin_ProfessionsBook()
        local win = _G.ProfessionsBookFrame
        if not win then
            return
        end
        Skin.Shell("professionsbook", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win)
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if _G.ProfessionsBookFrameBg then
            _G.ProfessionsBookFrameBg:SetAlpha(0)
        end
        for _, n in ipairs({ "ProfessionsBookPage1", "ProfessionsBookPage2" }) do
            local p = _G[n]
            if p and p.GetObjectType then
                if p:GetObjectType() == "Texture" then
                    p:SetAlpha(0)
                else
                    Skin.FadeRegions(p)
                end
            end
        end
        for _, keyName in ipairs({ "Inset", "RightInset", "LeftInset" }) do
            if win[keyName] then
                Skin.Inset(win[keyName])
            end
        end
        Skin.FadeKeyedArt(win)

        -- Info (help plate) button: seat on the window's left edge keeping its
        -- vertical spot (as with the Adventure Guide Traveler's Log). No parent
        -- key, found by its help-i art; retries until laid out.
        local function SeatProfHelp(owner, nestDepth)
            owner = owner or win
            nestDepth = nestDepth or 0
            if nestDepth > 3 or not owner.GetChildren then
                return
            end
            local children = { owner:GetChildren() }
            for idx = 1, #children do
                local child = children[idx]
                if
                    child
                    and not Skin.IsForeignFrame(child, owner)
                    and child.GetObjectType
                    and child:GetObjectType() == "Button"
                then
                    if not GetFFD(child).moved then
                        local nt = child.GetNormalTexture and child:GetNormalTexture()
                        local hay = nt and Skin.TexHay(nt)
                        if hay and hay:find("help-i", 1, true) then
                            local top, fTop = child:GetTop(), win:GetTop()
                            if top and fTop then
                                GetFFD(child).moved = true
                                child:ClearAllPoints()
                                child:SetPoint("TOPLEFT", win, "TOPLEFT", 4, top - fTop)
                            end
                        end
                    end
                elseif child then
                    SeatProfHelp(child, nestDepth + 1)
                end
            end
        end
        SeatProfHelp()

        RecolorProfessions()
        if not _profHook and type(_G.ProfessionsBookFrame_Update) == "function" then
            _profHook = true
            hooksecurefunc(
                "ProfessionsBookFrame_Update",
                Skin.Debounce(function()
                    if win:IsVisible() then
                        RecolorProfessions()
                    end
                end)
            )
        end

        Skin.ButtonsIn(win)
        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    RecolorProfessions()
                    SeatProfHelp()
                    Skin.Restrip()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "professionsbook",
        addons = { Blizzard_ProfessionsBook = true },
        apply = Skin_ProfessionsBook,
    })
end

-------------------------------------------------------------------------------
--  Archaeology (ArchaeologyFrame). Opened from the professions book, so it
--  rides the professionsbook style key.
-------------------------------------------------------------------------------
do
    local function Skin_Archaeology()
        local win = _G.ArchaeologyFrame
        if not win then
            return
        end
        Skin.Shell("professionsbook", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win)
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if _G.ArchaeologyFrameNineSlice then
            Skin.FadeNineSlice(_G.ArchaeologyFrameNineSlice)
        end
        for _, g in ipairs({
            "ArchaeologyFrameBg",
            "ArchaeologyFrameBgLeft",
            "ArchaeologyFrameBgRight",
            "ArchaeologyFrameInset",
            "ArchaeologyFrameportrait",
            "ArchaeologyFramePortrait",
        }) do
            local part = _G[g]
            if part then
                if part.IsObjectType and part:IsObjectType("Texture") then
                    part:SetAlpha(0)
                elseif part.GetObjectType then
                    if part.NineSlice then
                        Skin.FadeNineSlice(part.NineSlice)
                    end
                    Skin.FadeRegions(part)
                    Skin.Register(part, true)
                end
            end
        end
        -- Old-template art lives all over the child tree: keyed bg pieces + keyword art (parchment/corner/frametexture family) both swept.
        Skin.FadeKeyedArt(win)
        Skin.FadeArtIn(win)
        -- Direct fontstrings go white (color-only; this is a profession-specific window, not the font-exempt book).
        WhitenTextIn(win)
        if win.CloseButton then
            Skin.CloseButton(win.CloseButton)
        end
        if win.raceFilterDropdown then
            Skin.Dropdown(win.raceFilterDropdown)
        end
        if win.RaceFilterDropdown then
            Skin.Dropdown(win.RaceFilterDropdown)
        end
        for _, keyName in ipairs({
            "summaryPage",
            "SummaryPage",
            "artifactPage",
            "ArtifactPage",
            "completedPage",
            "CompletedPage",
            "helpPage",
            "HelpPage",
        }) do
            local pg = win[keyName]
            if pg then
                Skin.FadeKeyedArt(pg)
                WhitenTextIn(pg)
            end
        end
        -- Help page scroll text lives a level deeper than the page sweeps.
        local helpText = _G.ArchaeologyFrameHelpPageHelpScrollHelpText
        if helpText and helpText.SetTextColor then
            Skin.White(helpText)
        end
        for _, base in ipairs({ "ArchaeologyFrameSummaryPage", "ArchaeologyFrameCompletedPage" }) do
            for suffix, childFrame in pairs({ PrevPageButton = "<", NextPageButton = ">" }) do
                local progressBar = _G[base .. suffix]
                if progressBar then
                    Skin.PageButton(progressBar, childFrame)
                    -- These old buttons repaint arrow art on every state change:
                    -- sweep all non-house art per repaint and clamp the icon's alpha
                    -- against Blizzard's re-raises.
                    local importControl = _G[base .. suffix .. "Icon"]
                    local function SweepArrowArt()
                        if importControl and importControl.SetAlpha then
                            importControl:SetAlpha(0)
                        end
                        -- Spare OUR pieces by identity: the arrow path resolves to a fileID later, so name matching is unreliable.
                        local own = GetFFD(progressBar)
                        local regionList = { progressBar:GetRegions() }
                        for idx = 1, #regionList do
                            local region = regionList[idx]
                            if
                                region
                                and region ~= own.arrow
                                and region ~= own.bg
                                and region ~= own.hover
                                and region.IsObjectType
                                and region:IsObjectType("Texture")
                                and region:GetDrawLayer() ~= "HIGHLIGHT"
                            then
                                region:SetAlpha(0)
                            end
                        end
                    end
                    SweepArrowArt()
                    local progressData = GetFFD(progressBar)
                    if not progressData.arrowHooks then
                        progressData.arrowHooks = true
                        local function Deferred()
                            if C_Timer then
                                C_Timer.After(0, SweepArrowArt)
                            else
                                SweepArrowArt()
                            end
                        end
                        progressBar:HookScript("OnClick", Deferred)
                        progressBar:HookScript("OnEnable", Deferred)
                        progressBar:HookScript("OnDisable", Deferred)
                        progressBar:HookScript("OnShow", Deferred)
                        if importControl and importControl.SetAlpha then
                            hooksecurefunc(importControl, "SetAlpha", function(_, a)
                                if progressData.inIcAlpha then
                                    return
                                end
                                if a and not issecretvalue(a) and a > 0 then
                                    progressData.inIcAlpha = true
                                    importControl:SetAlpha(0)
                                    progressData.inIcAlpha = false
                                end
                            end)
                        end
                    end
                end
            end
        end
        -- Skill/rank bar -> full house bar: chrome uses its own names (Background/
        -- Border + anonymous pieces), so fade everything but the fill, flatten it, and seat the house trough+border.
        local arb = win.rankBar or win.RankBar or _G.ArchaeologyFrameRankBar
        if arb then
            local abd = GetFFD(arb)
            for _, g in ipairs({
                "ArchaeologyFrameRankBarBackground",
                "ArchaeologyFrameRankBarBorder",
            }) do
                local part = _G[g]
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
            local fillTex = arb.GetStatusBarTexture and arb:GetStatusBarTexture()
            local regionList = { arb:GetRegions() }
            for idx = 1, #regionList do
                local region = regionList[idx]
                if
                    region
                    and region ~= fillTex
                    and region ~= abd.bg
                    and region.IsObjectType
                    and region:IsObjectType("Texture")
                    and region:GetDrawLayer() ~= "HIGHLIGHT"
                then
                    region:SetAlpha(0)
                end
            end
            if arb.SetStatusBarTexture then
                arb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                Skin.ApplyBarFill(arb)
            end
            if not abd.bg then
                local troughTex = arb:CreateTexture(nil, "BACKGROUND", nil, -1)
                troughTex:SetColorTexture(0.12, 0.12, 0.12, 0.85)
                troughTex:SetAllPoints(arb)
                abd.bg = troughTex
                Skin.BorderRegion(arb, troughTex)
            end
            local regions2 = { arb:GetRegions() }
            for idx = 1, #regions2 do
                local region = regions2[idx]
                if region and region.IsObjectType and region:IsObjectType("FontString") then
                    Skin.White(region)
                end
            end
        end
        Skin.ScrollBarsIn(win)
        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    Skin.Restrip()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "professionsbook",
        addons = { Blizzard_ArchaeologyUI = true },
        apply = Skin_Archaeology,
    })
end

-------------------------------------------------------------------------------
--  Guild & Communities (CommunitiesFrame)
-------------------------------------------------------------------------------
-- Custom themed checkbox: Blizzard's atlas check art on these templates resists
-- the generic checkbox skin, so every texture region is cleared and a 14px
-- bordered box with an accent tick draws instead, whitening 10% on hover/check.
local function SkinGuildCheck(creatureBtn)
    if not creatureBtn or creatureBtn:IsForbidden() then
        return
    end
    local skinData = GetFFD(creatureBtn)
    if skinData.custom then
        return
    end
    skinData.custom = true
    local regionList = { creatureBtn:GetRegions() }
    for idx = 1, #regionList do
        local region = regionList[idx]
        if region and region.IsObjectType and region:IsObjectType("Texture") and region.SetTexture then
            region:SetTexture("")
        end
    end
    for _, g in ipairs({
        "GetNormalTexture",
        "GetPushedTexture",
        "GetHighlightTexture",
        "GetCheckedTexture",
        "GetDisabledCheckedTexture",
    }) do
        local part = creatureBtn[g] and creatureBtn[g](creatureBtn)
        if part and part.SetTexture then
            part:SetTexture("")
        end
    end
    local boxF = CreateFrame("Frame", nil, creatureBtn)
    boxF:SetSize(14, 14)
    boxF:SetPoint("LEFT", creatureBtn, "LEFT", 4, 0)
    local fillTex = SolidTex(boxF, "BACKGROUND", 0.02, 0.02, 0.02, 1)
    fillTex:SetAllPoints(boxF)
    Skin.AddBorder(boxF, 0.25, 0.25, 0.25, 1)
    local EG2 = CludesUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }
    local tick = boxF:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("TOPLEFT", 3, -3)
    tick:SetPoint("BOTTOMRIGHT", -3, 3)
    tick:SetColorTexture(EG2.r or 0.298, EG2.g or 0.788, EG2.b or 0.941, 1)
    local washTex = SolidTex(boxF, "ARTWORK", 1, 1, 1, 0.1)
    washTex:SetAllPoints(boxF)
    washTex:Hide()
    local hovering = false
    local function updState()
        local checked = creatureBtn:GetChecked() and true or false
        tick:SetShown(checked)
        washTex:SetShown(hovering or checked)
    end
    creatureBtn:HookScript("OnEnter", function()
        hovering = true
        updState()
    end)
    creatureBtn:HookScript("OnLeave", function()
        hovering = false
        updState()
    end)
    creatureBtn:HookScript("OnClick", updState)
    hooksecurefunc(creatureBtn, "SetChecked", updState)
    updState()
    local labelFS = creatureBtn.Text or (creatureBtn.GetFontString and creatureBtn:GetFontString())
    if labelFS then
        Skin.White(labelFS)
    end
end

-- Side tab (Chat/Roster/Benefits/Info): square the icon, drop the gold ring.
local function SquareTabIcon(tabBtn)
    if not tabBtn then
        return
    end
    local skinData = GetFFD(tabBtn)
    local glyphTex = tabBtn.Icon
    local overlayFrame = tabBtn.IconOverlay
    if glyphTex then
        Skin.SquareIcon(glyphTex)
        if glyphTex.SetDrawLayer then
            glyphTex:SetDrawLayer("ARTWORK")
        end
    end
    if tabBtn.GetRegions then
        local regionList = { tabBtn:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if
                region
                and region ~= glyphTex
                and region ~= overlayFrame
                and region ~= skinData.hover
                and region.IsObjectType
                and region:IsObjectType("Texture")
                and region.SetAlpha
            then
                region:SetAlpha(0)
            end
        end
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetCheckedTexture", "GetHighlightTexture" }) do
        local func = tabBtn[getter]
        local part = func and func(tabBtn)
        if part and part.SetAlpha then
            part:SetAlpha(0)
        end
    end
end

-- Guild dialog popouts (member detail, request-to-join): chrome lives in child
-- FRAMES ("BG"/"Border" wrappers holding the bg + nine-slice), invisible to
-- the keyed art sweeps, so flatten to a house panel.
local function ApplyGuildPopup(pop, skinData)
    Skin.FadeRegions(pop, skinData.bg and { [skinData.bg] = true })
    if pop.NineSlice then
        Skin.FadeNineSlice(pop.NineSlice)
    end
    for _, keyName in ipairs({ "BG", "Border" }) do
        local piece = pop[keyName]
        if piece then
            if piece.IsObjectType and piece:IsObjectType("Texture") then
                piece:SetAlpha(0)
            else
                Skin.FadeRegions(piece)
                if piece.NineSlice then
                    Skin.FadeNineSlice(piece.NineSlice)
                end
                Skin.Register(piece, true)
            end
        end
    end
    local bgTex = skinData.bg
    if not bgTex then
        bgTex = pop:CreateTexture(nil, "BACKGROUND", nil, -6)
        skinData.bg = bgTex
    end
    bgTex:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    bgTex:SetAllPoints(pop)
    Skin.AddBorder(pop)
    Skin.Register(pop, true)
    if pop.CloseButton then
        Skin.CloseButton(pop.CloseButton)
    end
    -- The member detail popup's name and rank are player and guild writing: a
    -- font family.
    local regionList = { pop:GetRegions() }
    for idx = 1, #regionList do
        local region = regionList[idx]
        if region and region.IsObjectType and region:IsObjectType("FontString") then
            if region == pop.Name or region == pop.RankText then
                Skin.FontFamily(region)
            else
                Skin.Font(region)
            end
            Skin.White(region)
        end
    end
end

local function SkinGuildPopup(pop)
    -- Some same-named globals are functions until their dialog exists.
    if type(pop) ~= "table" or not pop.IsForbidden or pop:IsForbidden() then
        return
    end
    Skin.CompleteSetup(pop, "popupSkinned", ApplyGuildPopup)
end

do
    -- Max/Min glyph matching the transmog / dressing-room look: quest-tracker
    -- collapse/expand chevron (up = maximize/Expand, down = minimize/Collapse),
    -- desaturated white at 0.75, brightening on hover.
    local function CaretGlyph(btnFrame, up)
        if not btnFrame then
            return
        end
        local atlas = up and "UI-QuestTrackerButton-Secondary-Expand"
            or "UI-QuestTrackerButton-Secondary-Collapse"
        if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then
            return
        end
        local skinData = GetFFD(btnFrame)
        -- The glyph is a texture region on the button itself: keep it out of the
        -- region fade on re-runs.
        Skin.FadeRegions(btnFrame, skinData.caret and { [skinData.caret] = true } or nil)
        for _, m in ipairs({
            "GetNormalTexture",
            "GetPushedTexture",
            "GetHighlightTexture",
            "GetDisabledTexture",
        }) do
            local part = btnFrame[m] and btnFrame[m](btnFrame)
            if part and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        if not skinData.caret then
            local part = btnFrame:CreateTexture(nil, "OVERLAY")
            part:SetAtlas(atlas, false)
            part:SetSize(16, 16)
            part:SetPoint("CENTER", -2, 0)
            part:SetDesaturated(true)
            part:SetVertexColor(1, 1, 1, 0.75)
            skinData.caret = part
            btnFrame:HookScript("OnEnter", function()
                part:SetVertexColor(1, 1, 1, 1)
            end)
            btnFrame:HookScript("OnLeave", function()
                part:SetVertexColor(1, 1, 1, 0.75)
            end)
        end
    end

    -- Community list entry: flat block + accent selection. Blizzard repaints the
    -- entry background per type, so this re-runs from the list update hook.
    local function SkinCommunityEntry(record)
        if not record then
            return
        end
        -- Each entry reads as a defined tile: the professions tiles' dialog-sheet
        -- card art at half strength, pulled in 2px top/bottom so neighbours never
        -- sit flush. Selection + hover washes clamp to the same card rect (native
        -- regions run past it). `extra` = extra inset for the flat washes, since
        -- the card atlas bakes in soft edges and a wash on the same rect reads
        -- bigger than the visible art.
        local function CardRect(texture, extra)
            extra = extra or 0
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", record, "TOPLEFT", extra, -2 - extra)
            texture:SetPoint("BOTTOMRIGHT", record, "BOTTOMRIGHT", -extra, 2 + extra)
        end
        if record.Background and record.Background.SetAtlas then
            local texture = record.Background
            local bgd = GetFFD(texture)
            -- Self-guarding card: Blizzard re-sets this texture per entry type
            -- from several paths, and pooled entries carry mixin COPIES so mixin
            -- table hooks miss them. Post-hooks on the TEXTURE OBJECT re-assert
            -- the card synchronously against every caller.
            if not bgd.guard then
                bgd.guard = true
                local function reapply()
                    if bgd.inSet then
                        return
                    end
                    bgd.inSet = true
                    texture:SetAtlas("Ui-Dialog-New-Background")
                    texture:SetTexCoord(0, 1, 0, 1)
                    texture:SetVertexColor(1, 1, 1, 1)
                    texture:SetAlpha(0.5)
                    bgd.inSet = false
                end
                bgd.reapply = reapply
                hooksecurefunc(texture, "SetAtlas", reapply)
                hooksecurefunc(texture, "SetTexture", reapply)
                hooksecurefunc(texture, "SetAlpha", reapply)
            end
            bgd.reapply()
            CardRect(texture)
        end
        -- Selected entry = the same subtle white wash as hover: never accent, and
        -- no brighter than hovering.
        if record.Selection and record.Selection.SetTexture then
            record.Selection:SetTexture("Interface\\Buttons\\WHITE8X8")
            record.Selection:SetVertexColor(1, 1, 1, 0.05)
            record.Selection:SetTexCoord(0, 1, 0, 1)
            CardRect(record.Selection, 3)
        end
        if record.IconRing and record.IconRing.SetAlpha then
            record.IconRing:SetAlpha(0)
        end
        local highlight = record.GetHighlightTexture and record:GetHighlightTexture()
        if highlight and highlight.SetTexture then
            highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
            highlight:SetVertexColor(1, 1, 1, 0.05)
            highlight:SetTexCoord(0, 1, 0, 1)
            CardRect(highlight, 3)
        end
    end

    -- Popup inputs get 6px of left padding: the BOX edge moves left (left-edge
    -- anchors shift, or centered fixed-width boxes widen +6 and recenter), with a
    -- matching text inset so the text's on-screen start is unchanged.
    local function PadPopupInput(editField)
        if not editField or not editField.GetNumPoints then
            return
        end
        local skinData = GetFFD(editField)
        if skinData.padLeft then
            return
        end
        local pointCount = editField:GetNumPoints() or 0
        if pointCount == 0 then
            return
        end
        local pts, success, hasLeft = {}, true, false
        for idx = 1, pointCount do
            local point, relTo, relPoint, posX, posY = editField:GetPoint(idx)
            if not point then
                success = false
                break
            end
            if point:find("LEFT", 1, true) then
                hasLeft = true
            end
            pts[idx] = { point, relTo, relPoint, posX or 0, posY or 0 }
        end
        if not success then
            return
        end
        skinData.padLeft = true
        if hasLeft then
            for idx = 1, #pts do
                if pts[idx][1]:find("LEFT", 1, true) then
                    pts[idx][4] = pts[idx][4] - 6
                end
            end
        else
            local wid = editField:GetWidth()
            if wid and wid > 0 then
                editField:SetWidth(wid + 6)
            end
            for idx = 1, #pts do
                pts[idx][4] = pts[idx][4] - 3
            end
        end
        editField:ClearAllPoints()
        for idx = 1, #pts do
            local tbl = pts[idx]
            editField:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
        end
        if editField.GetTextInsets and editField.SetTextInsets then
            local left, right, t2, button = editField:GetTextInsets()
            editField:SetTextInsets((left or 0) + 6, right or 0, t2 or 0, button or 0)
        end
    end
    CludesUI._WSkinPadInput = PadPopupInput

    local function PopupEditBox(editField)
        if not editField then
            return
        end
        Skin.EditBox(editField)
        PadPopupInput(editField)
    end

    local _guildNewsHook = false

    -- Only named controls belong to this skin. In particular, never discover
    -- buttons by walking the member ScrollBox or its pooled rows.
    local GUILD_CONTROL_HOSTS = {
        "CommunitiesControlFrame",
        "GuildMemberDetailFrame",
        "InvitationFrame",
        "ClubFinderInvitationFrame",
        "TicketFrame",
        "GuildFinderFrame",
        "CommunityFinderFrame",
        "NotificationSettingsDialog",
    }
    local GUILD_BUTTON_KEYS = {
        "InviteButton",
        "GuildLogButton",
        "GuildControlButton",
        "GuildRecruitmentButton",
        "CommunitiesSettingsButton",
        "RemoveButton",
        "GroupInviteButton",
        "AcceptButton",
        "DeclineButton",
        "ApplyButton",
        "FindAGuildButton",
        "OkayButton",
        "AllButton",
        "NoneButton",
    }
    local GUILD_TAB_KEYS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }
    local function SkinGuildControlHost(owner)
        if not owner then
            return
        end
        for _, key in ipairs(GUILD_BUTTON_KEYS) do
            if owner[key] then
                Skin.Button(owner[key])
            end
        end
        if owner.ScrollBar then
            Skin.ScrollBar(owner.ScrollBar)
        end
        if owner.RankDropdown then
            Skin.Dropdown(owner.RankDropdown)
        end
        if owner.InsetFrame then
            Skin.Inset(owner.InsetFrame)
        end
    end
    local function SkinGuildControls(win)
        SkinGuildControlHost(win)
        for _, key in ipairs(GUILD_CONTROL_HOSTS) do
            SkinGuildControlHost(win[key])
        end
        if win.Chat then
            SkinGuildControlHost(win.Chat)
        end
        if win.MemberList and win.MemberList.ScrollBar then
            Skin.ScrollBar(win.MemberList.ScrollBar)
        end
        if win.CommunitiesList and win.CommunitiesList.ScrollBar then
            Skin.ScrollBar(win.CommunitiesList.ScrollBar)
        end
    end

    local function SkinGuildDialogs(win)
        SkinGuildPopup(win.GuildMemberDetailFrame)
        SkinGuildPopup(_G.CommunitiesAddDialog)
        SkinGuildPopup(_G.CommunitiesCreateCommunityDialog)
        -- Add/Create Community dialogs: their globals are NOT live frames at addon
        -- load (the real frame appears when the dialog first opens), so catch it
        -- from StaticPopupSpecial_Show, which receives the frame itself. The BG is
        -- a layout-KIT frame whose chrome pieces are not plain regions, so
        -- container alpha suppresses all of it at once.
        if type(_G.StaticPopupSpecial_Show) == "function" and not GetFFD(win).addDlgHook then
            GetFFD(win).addDlgHook = true
            local wanted = {
                CommunitiesAddDialog = true,
                CommunitiesCreateCommunityDialog = true,
            }
            hooksecurefunc(
                "StaticPopupSpecial_Show",
                Skin.WindowCallback("guild", function(guildDialog)
                    if type(guildDialog) ~= "table" or not guildDialog.GetName then
                        return
                    end
                    local success, nm2 = pcall(guildDialog.GetName, guildDialog)
                    if not success or not nm2 or not wanted[nm2] then
                        return
                    end
                    SkinGuildPopup(guildDialog)
                    local d2 = GetFFD(guildDialog)
                    if guildDialog.BG and not d2.bgKilled then
                        d2.bgKilled = true
                        pcall(guildDialog.BG.SetAlpha, guildDialog.BG, 0)
                    end
                    for _, keyName in ipairs({ "InviteLinkBox", "NameEdit", "ShortNameEdit" }) do
                        if guildDialog[keyName] then
                            PopupEditBox(guildDialog[keyName])
                        end
                    end
                    if guildDialog.JoinButton then
                        Skin.Button(guildDialog.JoinButton)
                        local jfs = guildDialog.JoinButton.Text
                            or (guildDialog.JoinButton.GetFontString and guildDialog.JoinButton:GetFontString())
                        if jfs then
                            Skin.White(jfs)
                        end
                    end
                end)
            )
        end
        -- Community settings dialog (name/description/MOTD editor).
        local csd = _G.CommunitiesSettingsDialog
        if csd and type(csd) == "table" and not GetFFD(csd).csdSkinned then
            GetFFD(csd).csdSkinned = true
            SkinGuildPopup(csd)
            for _, keyName in ipairs({
                "Accept",
                "AcceptButton",
                "Cancel",
                "CancelButton",
                "Delete",
                "DeleteButton",
                "ChangeAvatarButton",
            }) do
                local button = csd[keyName]
                if button and button.GetObjectType and button:GetObjectType() == "Button" then
                    Skin.Button(button)
                    local buttonText = button.GetFontString and button:GetFontString()
                    if buttonText then
                        Skin.White(buttonText)
                    end
                end
            end
            for _, keyName in ipairs({ "NameEdit", "ShortNameEdit" }) do
                if csd[keyName] then
                    PopupEditBox(csd[keyName])
                end
            end
            for _, keyName in ipairs({ "ClubFocusDropdown", "LookingForDropdown", "LanguageDropdown" }) do
                if csd[keyName] then
                    Skin.Dropdown(csd[keyName])
                end
            end
            Skin.ScrollBarsIn(csd)
        end
        -- Guild recruitment settings dialog ("List My Guild in Guild Finder"):
        -- parented INSIDE CommunitiesFrame like EditStreamDialog, so the art sweeps strip
        -- its DialogBorderDark BG and it renders see-through without the house popup pass.
        local regionData = win.RecruitmentDialog
        if regionData and not GetFFD(regionData).rdSkinned then
            GetFFD(regionData).rdSkinned = true
            SkinGuildPopup(regionData)
            -- Blizzard pins this to the SCREEN (UIParent), nowhere near a
            -- repositioned Communities window; dock it to the panel's right edge
            -- instead (nothing re-anchors it at runtime). 38 = the 32px side tabs
            -- riding that edge + a 6px gap.
            regionData:ClearAllPoints()
            regionData:SetPoint("TOPLEFT", win, "TOPRIGHT", 38, 0)
            -- Docked to the panel it can leave the screen, so clamp.
            regionData:SetClampedToScreen(true)
            for _, keyName in ipairs({ "Accept", "Cancel" }) do
                local button = regionData[keyName]
                if button and button.GetObjectType and button:GetObjectType() == "Button" then
                    Skin.Button(button)
                    local buttonText = button.GetFontString and button:GetFontString()
                    if buttonText then
                        Skin.White(buttonText)
                    end
                end
            end
            for _, keyName in ipairs({ "ClubFocusDropdown", "LookingForDropdown", "LanguageDropdown" }) do
                if regionData[keyName] then
                    Skin.Dropdown(regionData[keyName])
                end
            end
            Skin.ScrollBarsIn(regionData)
        end
        -- Create/Edit Channel dialog: parented INSIDE CommunitiesFrame, so the recursive
        -- Bg-family art sweeps reach it and strip its fill (standalone UIParent dialogs are
        -- untouched). The house popup pass restores a backdrop.
        local esd = win.EditStreamDialog
        if esd and not GetFFD(esd).esdSkinned then
            GetFFD(esd).esdSkinned = true
            SkinGuildPopup(esd)
            for _, keyName in ipairs({
                "Accept",
                "AcceptButton",
                "Cancel",
                "CancelButton",
                "Delete",
                "DeleteButton",
            }) do
                local button = esd[keyName]
                if button and button.GetObjectType and button:GetObjectType() == "Button" then
                    Skin.Button(button)
                    local buttonText = button.GetFontString and button:GetFontString()
                    if buttonText then
                        Skin.White(buttonText)
                    end
                end
            end
            if esd.NameEdit then
                PopupEditBox(esd.NameEdit)
            end
            if esd.Description then
                PopupEditBox(esd.Description)
            end
            local modCheck = esd.TypeCheckBox or esd.ModeratorsOnlyCheckBox or esd.ModeratorsOnlyCheckbox
            if modCheck then
                SkinGuildCheck(modCheck)
            end
        end
        -- Notification settings dialog (chat bell): house popup + its extras.
        local nsd = win.NotificationSettingsDialog
        if nsd then
            SkinGuildPopup(nsd)
            if nsd.Selector then
                Skin.FadeRegions(nsd.Selector)
                Skin.Register(nsd.Selector, true)
                for _, keyName in ipairs({ "OkayButton", "AllButton", "NoneButton" }) do
                    if nsd.Selector[keyName] then
                        Skin.Button(nsd.Selector[keyName])
                    end
                end
            end
            for _, keyName in ipairs({ "OkayButton", "AllButton", "NoneButton" }) do
                if nsd[keyName] then
                    Skin.Button(nsd[keyName])
                end
            end
            if nsd.CommunitiesListDropdown then
                Skin.Dropdown(nsd.CommunitiesListDropdown)
            end
            Skin.ScrollBarsIn(nsd)
        end
    end

    local function Skin_Guild()
        local win = _G.CommunitiesFrame
        if not win then
            return
        end
        local status = GetFFD(win)
        if status.refreshGuild then
            status.refreshGuild()
            return
        end
        Skin.Shell("guild", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, nil, true)
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if win.PortraitOverlay then
            Skin.FadeRegions(win.PortraitOverlay)
            if win.PortraitOverlay.SetAlpha then
                win.PortraitOverlay:SetAlpha(0)
            end
            Skin.Register(win.PortraitOverlay, true)
        end
        if win.StreamDropdown then
            if win.StreamDropdown.NotificationOverlay then
                Skin.FadeRegions(win.StreamDropdown.NotificationOverlay)
                win.StreamDropdown.NotificationOverlay:SetAlpha(0)
            end
            Skin.Dropdown(win.StreamDropdown)
            -- Chat tab's stream picker: 10% smaller, seated 10px left (one-shot).
            local sdd = GetFFD(win.StreamDropdown)
            if not sdd.adjusted then
                sdd.adjusted = true
                win.StreamDropdown:SetScale(0.9)
                local point, relTo, relPoint, posX, posY = win.StreamDropdown:GetPoint(1)
                if point then
                    win.StreamDropdown:ClearAllPoints()
                    win.StreamDropdown:SetPoint(point, relTo, relPoint, (posX or 0) - 10, posY or 0)
                end
            end
        end
        -- Minimized view swaps the community-list sidebar for a dropdown; style it.
        if win.CommunitiesListDropdown then
            Skin.Dropdown(win.CommunitiesListDropdown)
        end
        -- Side tabs, EJ-style plates without geometry fights: the dark box +
        -- black border anchor AROUND THE ICON, never the tab, so the plate rides
        -- along wherever Blizzard's display-mode layout seats the tab. Tab size,
        -- icon anchors and the native tab chain are never touched. Only the root
        -- tab re-anchors (flush to the window edge); the others chain to it.
        for _, keyName in ipairs(GUILD_TAB_KEYS) do
            local tabBtn = win[keyName]
            if tabBtn and not tabBtn:IsForbidden() then
                SquareTabIcon(tabBtn)
                local glyphTex = tabBtn.Icon
                local titleData = GetFFD(tabBtn)
                if glyphTex and not titleData.box then
                    local tabBox = CreateFrame("Frame", nil, tabBtn)
                    tabBox:SetPoint("TOPLEFT", glyphTex, "TOPLEFT", -2, 2)
                    tabBox:SetPoint("BOTTOMRIGHT", glyphTex, "BOTTOMRIGHT", 2, -2)
                    tabBox:SetFrameLevel(math.max(0, tabBtn:GetFrameLevel() - 2))
                    local fillTex = SolidTex(tabBox, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
                    fillTex:SetAllPoints(tabBox)
                    Skin.AddBorder(tabBox, 0, 0, 0, 1)
                    titleData.box = tabBox
                    titleData.bg = fillTex
                    local hoverTex = SolidTex(tabBtn, "HIGHLIGHT", 1, 1, 1, 0.1)
                    hoverTex:SetPoint("TOPLEFT", tabBox, "TOPLEFT", 0, 0)
                    hoverTex:SetPoint("BOTTOMRIGHT", tabBox, "BOTTOMRIGHT", 0, 0)
                    titleData.hover = hoverTex
                end
                -- Tighter icon zoom than the standard crop, re-applied per pass:
                -- SquareTabIcon resets it to the 0.08 standard above.
                if glyphTex and glyphTex.SetTexCoord then
                    glyphTex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
                end
                tabBtn:SetAlphaFromBoolean(tabBtn:IsEnabled(), 1, 0.5)
                -- Chain gap 10px tighter (one-shot): the native anchor to the
                -- previous tab is kept, only its y offset closes.
                if keyName ~= "ChatTab" and not titleData.gapAdj then
                    local point, relTo, relPoint, posX, posY = tabBtn:GetPoint(1)
                    if point then
                        titleData.gapAdj = true
                        tabBtn:ClearAllPoints()
                        tabBtn:SetPoint(point, relTo, relPoint, posX or 0, (posY or 0) + 10)
                    end
                end
            end
        end
        local chat = win.ChatTab
        if chat and not GetFFD(chat).rooted then
            GetFFD(chat).rooted = true
            chat:ClearAllPoints()
            chat:SetPoint("TOPLEFT", win, "TOPRIGHT", 1, -36)
        end

        -- Club finder (Guild Finder / Find a Community): the search input ships
        -- far taller than the search button, so both become the same slim size,
        -- stacked input-over-button.
        for _, finder in ipairs({ _G.ClubFinderGuildFinderFrame, _G.ClubFinderCommunityAndGuildFinderFrame }) do
            if finder and finder.InsetFrame then
                Skin.Inset(finder.InsetFrame)
            end
            -- Card pagers carry PreviousPage/NextPage keys, which the generic
            -- paging sweep does not match.
            if finder then
                for _, ck in ipairs({
                    "GuildCards",
                    "CommunityCards",
                    "PendingGuildCards",
                    "PendingCommunityCards",
                }) do
                    local cards = finder[ck]
                    if cards then
                        if cards.PreviousPage then
                            Skin.PageButton(cards.PreviousPage, "<", 13)
                        end
                        if cards.NextPage then
                            Skin.PageButton(cards.NextPage, ">", 13)
                        end
                    end
                end
            end
            local optionsList = finder and finder.OptionsList
            if optionsList and optionsList.SearchBox and optionsList.Search then
                local optionsData = GetFFD(optionsList)
                if not optionsData.searchFit then
                    optionsData.searchFit = true
                    optionsList.SearchBox:SetSize(118, 20)
                    optionsList.Search:SetSize(120, 22)
                end
                -- Blizzard's options layout re-anchors these controls after us, so
                -- one-shot moves never show: both PIN their seats via synchronous
                -- SetPoint post-hooks. Box = Blizzard's base shifted left/up
                -- (captured point set); button = stacked under the box.
                local sbx2 = optionsList.SearchBox
                local sd2 = GetFFD(sbx2)
                if not sd2.pinHooked then
                    sd2.pinHooked = true
                    local function capture()
                        local numPts = sbx2:GetNumPoints()
                        if not numPts or numPts == 0 then
                            return false
                        end
                        local pts = {}
                        for idx = 1, numPts do
                            local point, relTo, relPoint, posX, posY = sbx2:GetPoint(idx)
                            if not point then
                                return false
                            end
                            pts[idx] = { point, relTo, relPoint, (posX or 0) - 10, (posY or 0) + 6 }
                        end
                        sd2.pin = pts
                        return true
                    end
                    local function reseat()
                        if not sd2.pin then
                            return
                        end
                        sd2.inPin = true
                        sbx2:ClearAllPoints()
                        for idx = 1, #sd2.pin do
                            local tbl = sd2.pin[idx]
                            sbx2:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                        sd2.inPin = false
                    end
                    if capture() then
                        reseat()
                    end
                    hooksecurefunc(sbx2, "SetPoint", function()
                        if sd2.inPin then
                            return
                        end
                        if not sd2.pin then
                            if capture() then
                                reseat()
                            end
                        else
                            reseat()
                        end
                    end)
                end
                local sBtn = optionsList.Search
                local bd2 = GetFFD(sBtn)
                if not bd2.pinHooked then
                    bd2.pinHooked = true
                    local function reseatBtn()
                        bd2.inPin = true
                        sBtn:ClearAllPoints()
                        sBtn:SetPoint("TOP", sbx2, "BOTTOM", 1, -3)
                        bd2.inPin = false
                    end
                    reseatBtn()
                    hooksecurefunc(sBtn, "SetPoint", function()
                        if bd2.inPin then
                            return
                        end
                        reseatBtn()
                    end)
                end
                -- Filter/sort dropdowns carry finder-specific keys that the
                -- generic controls sweep does not match.
                if optionsList.ClubFilterDropdown then
                    Skin.Dropdown(optionsList.ClubFilterDropdown)
                end
                if optionsList.SortByDropdown then
                    Skin.Dropdown(optionsList.SortByDropdown)
                end
                if optionsList.ClubSizeDropdown then
                    Skin.Dropdown(optionsList.ClubSizeDropdown)
                end
                Skin.EditBox(optionsList.SearchBox)
                Skin.Button(optionsList.Search)
                local buttonText = optionsList.Search.GetFontString and optionsList.Search:GetFontString()
                if buttonText then
                    Skin.White(buttonText)
                end
            end
            -- These views' top controls run 20px deeper than the chat view's band:
            -- a band extension parented to the FINDER (so it shows and hides with the view)
            -- with its own bottom separator, while the main band's separator hides so no
            -- line cuts mid-bar. The request-to-join dialog hangs off the finder.
            if finder and finder.RequestToJoinFrame then
                SkinGuildPopup(finder.RequestToJoinFrame)
            end
            if finder and not GetFFD(finder).bandExt then
                local fd2 = GetFFD(finder)
                fd2.bandExt = true
                -- The zone-band FFD entry on f (built further down; GetFFD returns
                -- the same table either way).
                local gz = GetFFD(win)
                local sbw = gz.sbw or 170
                local ext = finder:CreateTexture(nil, "BACKGROUND", nil, -4)
                ext:SetColorTexture(0, 0, 0, 0.10)
                ext:SetPoint("TOPLEFT", win, "TOPLEFT", sbw, -59)
                ext:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -59)
                ext:SetHeight(20)
                local extSep = finder:CreateTexture(nil, "ARTWORK")
                extSep:SetColorTexture(0.15, 0.15, 0.15, 1)
                extSep:SetHeight(gz.sepPx or 1)
                extSep:SetPoint("BOTTOMLEFT", ext, "BOTTOMLEFT", 0, 0)
                extSep:SetPoint("BOTTOMRIGHT", ext, "BOTTOMRIGHT", 0, 0)
                finder:HookScript("OnShow", function()
                    if gz.topSep then
                        gz.topSep:Hide()
                    end
                end)
                finder:HookScript("OnHide", function()
                    local a2 = _G.ClubFinderGuildFinderFrame
                    local b2 = _G.ClubFinderCommunityAndGuildFinderFrame
                    if gz.topSep and not ((a2 and a2:IsShown()) or (b2 and b2:IsShown())) then
                        gz.topSep:Show()
                    end
                end)
                if finder:IsShown() and gz.topSep then
                    gz.topSep:Hide()
                end
            end
        end

        -- Zone bands laid out like the bags window (secondary top bar below the
        -- shell's 25px title bar, bottom bar, sidebar column + 1px separator).
        -- All band art MUST live on OUR OWN child frame: as direct f regions the
        -- shell's region fade wipes the bands on every re-skin pass.
        local gzd = GetFFD(win)
        if not gzd.zoneBands then
            gzd.zoneBands = true
            -- Separator sizing: exactly one PHYSICAL pixel in this frame's own units,
            -- default pixel snapping. PP.mult is one physical pixel in UIParent units, so
            -- when the host's effective scale differs the raw mult is slightly over a pixel
            -- here and snapping rounds the line onto two rows.
            local PPz = CludesUI.PanelPP
            local pixel = (PPz and PPz.mult) or 1
            do
                local es = win:GetEffectiveScale()
                local uiScale = UIParent and UIParent:GetScale() or 1
                if es and es > 0 and uiScale > 0 then
                    pixel = pixel * uiScale / es
                end
            end
            local GUILD_SIDEBAR_W = 170 -- hardcoded sidebar column width
            local owner = CreateFrame("Frame", nil, win)
            owner:SetAllPoints(win)
            owner:SetFrameLevel(win:GetFrameLevel())
            gzd.zoneHost = owner
            -- Secondary top bar: starts AFTER the sidebar column (never over it).
            local topBand = owner:CreateTexture(nil, "BACKGROUND")
            topBand:SetColorTexture(0, 0, 0, 0.10)
            topBand:SetPoint("TOPLEFT", win, "TOPLEFT", GUILD_SIDEBAR_W, -25)
            topBand:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -25)
            topBand:SetHeight(34)
            local topSep = owner:CreateTexture(nil, "ARTWORK")
            topSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            topSep:SetHeight(pixel)
            topSep:SetPoint("BOTTOMLEFT", topBand, "BOTTOMLEFT", 0, 0)
            topSep:SetPoint("BOTTOMRIGHT", topBand, "BOTTOMRIGHT", 0, 0)
            gzd.topSep = topSep
            gzd.sbw = GUILD_SIDEBAR_W
            gzd.sepPx = pixel
            local botBand = owner:CreateTexture(nil, "BACKGROUND")
            botBand:SetColorTexture(0, 0, 0, 0.10)
            botBand:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
            botBand:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
            botBand:SetHeight(30)
            local botSep = owner:CreateTexture(nil, "ARTWORK")
            botSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            botSep:SetHeight(pixel)
            botSep:SetPoint("TOPLEFT", botBand, "TOPLEFT", 0, 0)
            botSep:SetPoint("TOPRIGHT", botBand, "TOPRIGHT", 0, 0)
            -- Sidebar wash + separator on OUR host with FIXED geometry (window left edge to
            -- GUILD_SIDEBAR_W, title bar to bottom band). Never anchor these to the list's
            -- ScrollBox: Blizzard rebuilds its rect on view churn, so the art vanishes
            -- whenever the box's anchors are momentarily invalid and pops back on relayout.
            local washTex = owner:CreateTexture(nil, "BACKGROUND")
            washTex:SetColorTexture(0, 0, 0, 0.07)
            washTex:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -25)
            washTex:SetPoint("BOTTOMRIGHT", win, "BOTTOMLEFT", GUILD_SIDEBAR_W, 30)
            local sideSep = owner:CreateTexture(nil, "ARTWORK")
            sideSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            sideSep:SetWidth(pixel)
            sideSep:SetPoint("TOPRIGHT", win, "TOPLEFT", GUILD_SIDEBAR_W, -25)
            sideSep:SetPoint("BOTTOMRIGHT", win, "BOTTOMLEFT", GUILD_SIDEBAR_W, 30)
        end

        -- Left community list: filigrees + bluemenu bg gone, flat entries. Cleared
        -- via SetTexture(""), NOT alpha: Blizzard's list repaints re-raise this
        -- art after our show pass and cover the sidebar wash until the next skin
        -- pass. A cleared texture file survives every repaint.
        local entries = win.CommunitiesList or _G.CommunitiesFrameCommunitiesList
        if entries then
            for _, keyName in ipairs({ "TopFiligree", "BottomFiligree", "Bg" }) do
                local part = entries[keyName]
                if part and part.SetTexture then
                    part:SetTexture("")
                end
            end
            if entries.FilligreeOverlay then
                local regionList = { entries.FilligreeOverlay:GetRegions() }
                for idx = 1, #regionList do
                    local region = regionList[idx]
                    if region and region.IsObjectType and region:IsObjectType("Texture") and region.SetTexture then
                        region:SetTexture("")
                    end
                end
                entries.FilligreeOverlay:SetAlpha(0)
            end
            if entries.InsetFrame then
                Skin.Inset(entries.InsetFrame)
            end
            Skin.FadeKeyedArt(entries)
            -- Entries re-skin from the ENTRY MIXIN's own setters: Blizzard
            -- re-inits pooled entries through these on every toggle/list build,
            -- paths that never fire ScrollBox Update, reverting the card art.
            if _G.CommunitiesListEntryMixin and not GetFFD(entries).entryHook then
                GetFFD(entries).entryHook = true
                local function reskinEntry(entryFrame)
                    if entryFrame and not (entryFrame.IsForbidden and entryFrame:IsForbidden()) then
                        SkinCommunityEntry(entryFrame)
                    end
                end
                for _, m in ipairs({ "SetClubInfo", "SetAddCommunity", "SetFindCommunity", "SetGuildFinder" }) do
                    if _G.CommunitiesListEntryMixin[m] then
                        hooksecurefunc(_G.CommunitiesListEntryMixin, m, reskinEntry)
                    end
                end
            end
            SkinCommunityEntry = Skin.WindowCallback("guild", SkinCommunityEntry)
            local scrollBar = entries.ScrollBox
            if scrollBar then
                if scrollBar.ForEachFrame then
                    pcall(scrollBar.ForEachFrame, scrollBar, SkinCommunityEntry)
                end
                if scrollBar.Update and not GetFFD(scrollBar).reHooked then
                    GetFFD(scrollBar).reHooked = true
                    hooksecurefunc(scrollBar, "Update", function()
                        if scrollBar.ForEachFrame then
                            pcall(scrollBar.ForEachFrame, scrollBar, SkinCommunityEntry)
                        end
                    end)
                end
            end
            -- Scrollbar flush with the sidebar's inner right edge (one-shot).
            local lsb = entries.ScrollBar
            if lsb and not GetFFD(lsb).seated then
                GetFFD(lsb).seated = true
                lsb:ClearAllPoints()
                lsb:SetPoint("TOPRIGHT", entries, "TOPRIGHT", 0, -8)
                lsb:SetPoint("BOTTOMRIGHT", entries, "BOTTOMRIGHT", 0, 8)
            end
        end

        local chat = win.Chat
        if chat then
            local ci = chat.ChatInsetFrame or chat.InsetFrame
            if ci then
                Skin.Inset(ci)
            end
        end
        -- Input skin ONLY: no anchor/position meddling. Pinning this box makes it
        -- stop rendering entirely, so it runs stock Blizzard geometry (height-only
        -- slim below is the sole exception). Blizzard re-raises the input's art on
        -- chat layout passes, so the art re-fades EVERY pass (our fill protected)
        -- and the box registers for restrips.
        if win.ChatEditBox then
            local editField = win.ChatEditBox
            Skin.EditBox(editField)
            local ebd = GetFFD(editField)
            local keepSet = {}
            if ebd.bg then
                keepSet[ebd.bg] = true
            end
            Skin.FadeRegions(editField, keepSet)
            for _, keyName in ipairs({ "Left", "Right", "Middle", "Mid" }) do
                local region = editField[keyName]
                if region and region.SetAlpha then
                    region:SetAlpha(0)
                end
            end
            Skin.Register(editField, true)
            -- Height-only slim: one-shot, no anchor writes.
            if not ebd.slimmed then
                local hh = editField:GetHeight()
                if hh and hh > 26 then
                    ebd.slimmed = true
                    editField:SetHeight(hh - 12)
                end
            end
        end

        local ml = win.MemberList
        if ml and ml.InsetFrame then
            Skin.Inset(ml.InsetFrame)
        end
        -- "N/M Online" count above the roster: white.
        if ml and ml.MemberCount and ml.MemberCount.SetTextColor then
            Skin.White(ml.MemberCount)
        end
        -- Member-list view dropdowns (guild + community): scaled down, seated 8px
        -- lower (one-shot; the label keeps its stock font size, the 0.85 scale is
        -- the only text shrink).
        for _, ddKey in ipairs({ "GuildMemberListDropdown", "CommunityMemberListDropdown" }) do
            local dd2 = win[ddKey]
            if dd2 then
                Skin.Dropdown(dd2)
                local gdd = GetFFD(dd2)
                if not gdd.scaled then
                    gdd.scaled = true
                    dd2:SetScale(0.85)
                    local point, relTo, relPoint, posX, posY = dd2:GetPoint(1)
                    if point then
                        dd2:ClearAllPoints()
                        dd2:SetPoint(point, relTo, relPoint, posX or 0, (posY or 0) - 8)
                    end
                end
            end
        end
        if ml and ml.ShowOfflineButton then
            SkinGuildCheck(ml.ShowOfflineButton)
        end
        SkinGuildDialogs(win)
        -- Ticket frame (community invite ticket pane): inset chrome off.
        local tkf = win.TicketFrame
        if tkf then
            Skin.FadeRegions(tkf)
            Skin.Register(tkf, true)
            if tkf.InsetFrame then
                Skin.Inset(tkf.InsetFrame)
                if tkf.InsetFrame.NineSlice then
                    Skin.FadeNineSlice(tkf.InsetFrame.NineSlice)
                end
            end
            for _, keyName in ipairs({ "AcceptButton", "DeclineButton" }) do
                local button = tkf[keyName]
                if button then
                    Skin.Button(button)
                    local buttonText = button.GetFontString and button:GetFontString()
                    if buttonText then
                        Skin.White(buttonText)
                    end
                end
            end
        end
        -- Roster click-to-sort column headers: flat plates, white labels, standard
        -- hover. Columns are pooled 3-slice buttons under ColumnDisplay that
        -- rebuild per club/view, so the pass re-runs (see the refresh hook below).
        local function SkinRosterColumns()
            local cd = ml and ml.ColumnDisplay
            if not cd then
                return
            end
            Skin.FadeRegions(cd)
            Skin.Register(cd, true)
            local children = { cd:GetChildren() }
            for idx = 1, #children do
                local colour = children[idx]
                if colour and colour.GetObjectType and colour:GetObjectType() == "Button" then
                    local d2 = GetFFD(colour)
                    if not d2.bg then
                        for _, k2 in ipairs({ "Left", "Middle", "Right" }) do
                            local t2 = colour[k2]
                            if t2 and t2.SetTexture then
                                t2:SetTexture("")
                            end
                        end
                        Skin.FadeRegions(colour)
                        local bg2 = SolidTex(
                            colour,
                            "BACKGROUND",
                            Theme.bgR + 0.015,
                            Theme.bgG + 0.015,
                            Theme.bgB + 0.015,
                            Theme.bgA
                        )
                        bg2:SetPoint("TOPLEFT", 1, -1)
                        bg2:SetPoint("BOTTOMRIGHT", -1, 1)
                        d2.bg = bg2
                        local hoverTex = SolidTex(colour, "HIGHLIGHT", 1, 1, 1, 0.1)
                        hoverTex:SetAllPoints(colour)
                        d2.hover = hoverTex
                        Skin.Register(colour, true)
                    end
                    local fs2 = colour.GetFontString and colour:GetFontString()
                    if fs2 then
                        Skin.White(fs2)
                    end
                end
            end
        end
        SkinRosterColumns = Skin.WindowCallback("guild", SkinRosterColumns)
        SkinRosterColumns()
        -- Re-skin roster columns on Blizzard's rebuild (per club / view change) via
        -- hooksecurefunc on the list refresh. NEVER HookScript the secure ColumnDisplay: an
        -- OnShow/OnHide there fires INSIDE the secure roster refresh triggered by a
        -- protected guild action (SetNote / SetGuildRankOrder) -> ADDON_ACTION_FORBIDDEN.
        -- hooksecurefunc post-hooks are taint-safe by design.
        if ml and ml.RefreshListDisplay and not GetFFD(ml).colRefreshHooked then
            GetFFD(ml).colRefreshHooked = true
            hooksecurefunc(ml, "RefreshListDisplay", Skin.Debounce(SkinRosterColumns))
        end
        -- NEVER re-anchor or resize the roster: CommunitiesMemberListEntryMixin
        -- sizes every row from GetMemberList():GetWidth(), and the list view reads
        -- ScrollBox:GetVisibleExtent() in the same pass that creates the row
        -- buttons, so an addon-written width or anchor is read back and taints it.
        -- Rows born in that pass stay tainted for the session: the protected
        -- actions the refresh triggers are blocked (SetNote / SetGuildRankOrder /
        -- whisper -> ADDON_ACTION_FORBIDDEN) and the row tooltip throws on the
        -- secret member fields (C_CreatureInfo.GetRaceInfo(memberInfo.race)).

        local maxMinBtn = win.MaximizeMinimizeFrame
        if maxMinBtn then
            CaretGlyph(maxMinBtn.MaximizeButton, true)
            CaretGlyph(maxMinBtn.MinimizeButton, false)
        end
        -- Zone bands belong to the full layout only (the minimized view has no
        -- sidebar column or top/bottom bars): hide the band host while minimized.
        -- The Maximize button shows only when minimized, so it is the state probe.
        if gzd.zoneHost then
            local function UpdateZoneBands()
                local minimized = maxMinBtn and maxMinBtn.MaximizeButton and maxMinBtn.MaximizeButton:IsShown()
                gzd.zoneHost:SetShown(not minimized)
            end
            UpdateZoneBands()
            if maxMinBtn and not gzd.mmHook then
                gzd.mmHook = true
                for _, button in ipairs({ maxMinBtn.MaximizeButton, maxMinBtn.MinimizeButton }) do
                    if button and button.HookScript then
                        button:HookScript("OnClick", function()
                            if C_Timer then
                                C_Timer.After(0, UpdateZoneBands)
                            else
                                UpdateZoneBands()
                            end
                        end)
                    end
                end
            end
        end
        -- Raise the chat input 7px ONLY when minimized. Its stock position is
        -- view-dependent, so a captured original bleeds across views: hook SetPoint
        -- and re-apply +7 the NEXT frame, relative to Blizzard's LIVE position
        -- (an immediate re-apply compounds across multi-point sets). Each pass
        -- reads the just-set stock, so it never stacks.
        local editField = win.ChatEditBox
        if editField and maxMinBtn and not GetFFD(editField).raiseHook then
            GetFFD(editField).raiseHook = true
            local applying, pending = false, false
            local function ApplyOffset()
                pending = false
                if not (maxMinBtn.MaximizeButton and maxMinBtn.MaximizeButton:IsShown()) then
                    return
                end -- maximized: leave stock
                local pointCount = editField:GetNumPoints() or 0
                local pts, success = {}, pointCount > 0
                for idx = 1, pointCount do
                    local point, relTo, relPoint, posX, posY = editField:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + 7 }
                end
                if success then
                    applying = true
                    editField:ClearAllPoints()
                    for idx = 1, #pts do
                        local tbl = pts[idx]
                        editField:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                    end
                    applying = false
                end
            end
            hooksecurefunc(editField, "SetPoint", function()
                if applying or pending then
                    return
                end
                pending = true
                if C_Timer then
                    C_Timer.After(0, ApplyOffset)
                else
                    ApplyOffset()
                end
            end)
            -- Initial apply (box is at its stock position at load).
            pending = true
            if C_Timer then
                C_Timer.After(0, ApplyOffset)
            else
                ApplyOffset()
            end
        end

        -- Perks (Guild Benefits) tab: parchment inset borders + section art
        -- gone, section titles in the house font, slim scrollbars, flat rows,
        -- and the reputation bar as a flat accent fill on a dark trough.
        local gb = win.GuildBenefitsFrame
        if gb then
            for _, keyName in ipairs({
                "InsetBorderLeft",
                "InsetBorderRight",
                "InsetBorderBottomRight",
                "InsetBorderBottomLeft",
                "InsetBorderTopRight",
                "InsetBorderTopLeft",
                "InsetBorderLeft2",
                "InsetBorderBottomLeft2",
                "InsetBorderTopLeft2",
            }) do
                local part = gb[keyName]
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
            local function SkinBenefitRow(row)
                if not row or row:IsForbidden() then
                    return
                end
                local regionData = GetFFD(row)
                if not regionData.bg then
                    local keepSet = {}
                    if row.Icon then
                        keepSet[row.Icon] = true
                    end
                    Skin.FadeRegions(row, keepSet)
                    local bgTex = row:CreateTexture(nil, "BACKGROUND", nil, -3)
                    bgTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
                    bgTex:SetPoint("TOPLEFT", 1, -1)
                    bgTex:SetPoint("BOTTOMRIGHT", -1, 1)
                    regionData.bg = bgTex
                    Skin.AddBorder(row)
                    if row.Icon then
                        Skin.SquareIcon(row.Icon, row)
                    end
                    Skin.Register(row, keepSet)
                end
                local regionList = { row:GetRegions() }
                for idx = 1, #regionList do
                    local region = regionList[idx]
                    if region and region.IsObjectType and region:IsObjectType("FontString") then
                        Skin.Font(region)
                        Skin.White(region)
                    end
                end
            end
            SkinBenefitRow = Skin.WindowCallback("guild", SkinBenefitRow)
            for _, sec in ipairs({ gb.Perks, gb.Rewards }) do
                if sec then
                    Skin.FadeRegions(sec)
                    Skin.Register(sec, true)
                    if sec.Bg and sec.Bg.SetAlpha then
                        sec.Bg:SetAlpha(0)
                    end
                    if sec.TitleText then
                        Skin.Font(sec.TitleText)
                        Skin.White(sec.TitleText)
                    end
                    if sec.ScrollBar then
                        Skin.ScrollBar(sec.ScrollBar)
                    end
                    local sbx3 = sec.ScrollBox
                    if sbx3 and sbx3.ForEachFrame then
                        pcall(sbx3.ForEachFrame, sbx3, SkinBenefitRow)
                        if sbx3.Update and not GetFFD(sbx3).rowHook then
                            GetFFD(sbx3).rowHook = true
                            hooksecurefunc(sbx3, "Update", function(tabBox)
                                pcall(tabBox.ForEachFrame, tabBox, SkinBenefitRow)
                            end)
                        end
                    end
                end
            end
            -- Reputation bar: the bar FRAME is taller than the visual fill, so the
            -- trough + border wrap the fill's MEASURED vertical band at full
            -- width. The fill cannot be the anchor -- its width IS the progress.
            -- Retries from the pane's OnShow until laid out.
            local function FlattenRepBar()
                local rep = gb.FactionFrame and gb.FactionFrame.Bar
                if not rep or GetFFD(rep).flat then
                    return
                end
                local prog = rep.Progress
                local rt, pt2 = rep:GetTop(), prog and prog:GetTop()
                local rb, progressBar = rep:GetBottom(), prog and prog:GetBottom()
                if not (rt and pt2 and rb and progressBar) then
                    return
                end
                local bd3 = GetFFD(rep)
                bd3.flat = true
                for _, keyName in ipairs({ "Middle", "Right", "Left", "BG" }) do
                    local part = rep[keyName]
                    if part and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
                if rep.Shadow and rep.Shadow.SetAlpha then
                    rep.Shadow:SetAlpha(0)
                end
                prog:SetTexture("Interface\\Buttons\\WHITE8X8")
                local fr2, fg2, fb2, fa2 = Skin.BarFillColor()
                prog:SetVertexColor(fr2, fg2, fb2, fa2)
                local troughTex = rep:CreateTexture(nil, "BACKGROUND", nil, -1)
                troughTex:SetColorTexture(0.12, 0.12, 0.12, 0.85)
                troughTex:SetPoint("TOPLEFT", rep, "TOPLEFT", 0, -(rt - pt2))
                troughTex:SetPoint("BOTTOMRIGHT", rep, "BOTTOMRIGHT", 0, progressBar - rb)
                bd3.bg = troughTex
                Skin.BorderRegion(rep, troughTex)
                -- "Guild Reputation" label + on-bar text in white house font.
                for _, host2 in ipairs({ gb.FactionFrame, rep }) do
                    if host2 and host2.GetRegions then
                        local regionList = { host2:GetRegions() }
                        for idx = 1, #regionList do
                            local region = regionList[idx]
                            if region and region.IsObjectType and region:IsObjectType("FontString") then
                                Skin.Font(region)
                                Skin.White(region)
                            end
                        end
                    end
                end
            end
            FlattenRepBar = Skin.WindowCallback("guild", FlattenRepBar)
            FlattenRepBar()
            if not GetFFD(gb).repHook then
                GetFFD(gb).repHook = true
                gb:HookScript("OnShow", Skin.Debounce(FlattenRepBar))
            end
        end

        -- Guild Info tab: inset borders + parchment gone, section titles in the
        -- house font, slim scrollbars, themed news-filter popout + checkboxes,
        -- and the per-row news header strips cleared as rows populate.
        local gdet = _G.CommunitiesFrameGuildDetailsFrame
        if gdet then
            for _, keyName in ipairs({
                "InsetBorderLeft",
                "InsetBorderRight",
                "InsetBorderBottomRight",
                "InsetBorderBottomLeft",
                "InsetBorderTopRight",
                "InsetBorderTopLeft",
                "InsetBorderLeft2",
                "InsetBorderBottomLeft2",
                "InsetBorderTopLeft2",
            }) do
                local part = gdet[keyName]
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
        end
        -- "View Log" button: white label, 2px smaller.
        local logBtn = win.GuildLogButton
        if logBtn then
            local lfs = logBtn.GetFontString and logBtn:GetFontString()
            if lfs then
                Skin.White(lfs)
                local labelData = GetFFD(lfs)
                if not labelData.shrunk then
                    local pth, sz, fl = lfs:GetFont()
                    if pth and sz then
                        labelData.shrunk = true
                        lfs:SetFont(pth, sz - 2, fl)
                    end
                end
            end
        end
        -- Guild log popup (old-style dialog: named Bg/corner pieces, corner X
        -- "<name>Close", bottom text button "<name>CloseButton", old scrollbar).
        local function SkinGuildLog()
            local guildLog = _G.CommunitiesGuildLogFrame
            if not guildLog or type(guildLog) ~= "table" or GetFFD(guildLog).logSkinned then
                return
            end
            GetFFD(guildLog).logSkinned = true
            local n = (guildLog.GetName and guildLog:GetName()) or "CommunitiesGuildLogFrame"
            -- TWO buttons can carry the CloseButton name (corner X + bottom text
            -- button; the global resolves to only one). Classify every button by
            -- label (text -> house button, blank -> house X) BEFORE the popup pass,
            -- so its own CloseButton call cannot glyph the text button.
            local function TreatClose(cand)
                if not cand or type(cand) ~= "table" or not cand.GetObjectType then
                    return
                end
                local cd = GetFFD(cand)
                if cd.closeTreated then
                    return
                end
                cd.closeTreated = true
                local buttonText = cand.GetFontString and cand:GetFontString()
                local btxt = buttonText and buttonText.GetText and buttonText:GetText()
                if btxt and btxt ~= "" then
                    Skin.Button(cand)
                    if buttonText then
                        Skin.White(buttonText)
                    end
                    -- Sentinel on CloseButton's guard key: blocks any later
                    -- WSkin.CloseButton on this frame. No hover hooks read it.
                    if not cd.x then
                        cd.x = true
                    end
                else
                    Skin.CloseButton(cand)
                end
            end
            TreatClose(guildLog.Close)
            TreatClose(guildLog.CloseButton)
            TreatClose(_G[n .. "Close"])
            TreatClose(_G[n .. "CloseButton"])
            local children = { guildLog:GetChildren() }
            for idx = 1, #children do
                local childFrame = children[idx]
                if
                    childFrame
                    and not Skin.IsForeignFrame(childFrame, guildLog)
                    and childFrame.GetObjectType
                    and childFrame:GetObjectType() == "Button"
                then
                    TreatClose(childFrame)
                end
            end
            SkinGuildPopup(guildLog)
            -- Inner container carries its own NineSlice chrome.
            local cont = guildLog.Container
            if cont then
                Skin.FadeRegions(cont)
                if cont.NineSlice then
                    Skin.FadeNineSlice(cont.NineSlice)
                end
                Skin.Register(cont, true)
            end
            local tt = guildLog.Title or guildLog.TitleText or _G[n .. "Title"] or _G[n .. "TitleText"]
            if tt and tt.SetTextColor then
                Skin.Font(tt)
                Skin.White(tt)
            end
            Skin.ScrollBarsIn(guildLog)
            -- Old-style scrollbar: arrows faded, thumb -> 4px house strip.
            local scrollBar = _G[n .. "ScrollFrameScrollBar"]
            if scrollBar and not GetFFD(scrollBar).slim then
                GetFFD(scrollBar).slim = true
                local sbn = (scrollBar.GetName and scrollBar:GetName()) or ""
                for _, suffix in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
                    local button = scrollBar[suffix] or _G[sbn .. suffix]
                    if button then
                        for _, g in ipairs({
                            "GetNormalTexture",
                            "GetPushedTexture",
                            "GetDisabledTexture",
                            "GetHighlightTexture",
                        }) do
                            local part = button[g] and button[g](button)
                            if part and part.SetAlpha then
                                part:SetAlpha(0)
                            end
                        end
                    end
                end
                local thumb = scrollBar.GetThumbTexture and scrollBar:GetThumbTexture()
                if thumb then
                    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
                    thumb:SetVertexColor(1, 1, 1, 0.3)
                    thumb:SetWidth(4)
                end
            end
        end
        SkinGuildLog = Skin.WindowCallback("guild", SkinGuildLog)
        SkinGuildLog()
        if logBtn and not GetFFD(logBtn).logHook then
            GetFFD(logBtn).logHook = true
            logBtn:HookScript("OnClick", SkinGuildLog)
        end
        -- "Add to Chat" button: house caret + white label.
        local atc = win.AddToChatButton
        if atc and not GetFFD(atc).atcSkinned then
            GetFFD(atc).atcSkinned = true
            -- The label may be the fontstring, a Text key, or an anonymous region:
            -- collect deduped, white them (color only, stock font kept), seat 2px
            -- lower (one-shot, all anchors preserved).
            local labels = {}
            local afs = atc.GetFontString and atc:GetFontString()
            if afs then
                labels[afs] = true
            end
            if atc.Text and atc.Text.SetTextColor then
                labels[atc.Text] = true
            end
            local regionList = { atc:GetRegions() }
            for idx = 1, #regionList do
                local region = regionList[idx]
                if region and region.IsObjectType and region:IsObjectType("FontString") then
                    labels[region] = true
                end
            end
            for fsr in pairs(labels) do
                Skin.White(fsr)
                local labelData = GetFFD(fsr)
                if not labelData.dropped then
                    local pointCount = fsr:GetNumPoints() or 0
                    local pts, success = {}, pointCount > 0
                    for idx = 1, pointCount do
                        local point, relTo, relPoint, posX, posY = fsr:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) - 2 }
                    end
                    if success then
                        labelData.dropped = true
                        fsr:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            fsr:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                end
            end
            local arrowTex = atc.Arrow
            if arrowTex then
                local texture = arrowTex
                if arrowTex.IsObjectType and not arrowTex:IsObjectType("Texture") then
                    texture = nil
                    if arrowTex.GetRegions then
                        local regions2 = { arrowTex:GetRegions() }
                        for idx = 1, #regions2 do
                            local region = regions2[idx]
                            if region and region.IsObjectType and region:IsObjectType("Texture") then
                                texture = region
                                break
                            end
                        end
                    end
                end
                if texture and texture.SetAtlas then
                    -- Blizzard repaints the arrow on hover/press state changes, so
                    -- self-guarding hooks keep the house caret in place.
                    local titleData = GetFFD(texture)
                    local function ApplyCaret()
                        if titleData.inSet then
                            return
                        end
                        titleData.inSet = true
                        texture:SetAtlas("Azerite-PointingArrow", false)
                        texture:SetSize(14, 10)
                        texture:SetVertexColor(1, 1, 1, 1)
                        titleData.inSet = false
                    end
                    if not titleData.hooked then
                        titleData.hooked = true
                        hooksecurefunc(texture, "SetAtlas", ApplyCaret)
                        hooksecurefunc(texture, "SetTexture", ApplyCaret)
                        hooksecurefunc(texture, "SetTexCoord", ApplyCaret)
                    end
                    ApplyCaret()
                end
            end
        end
        -- Settings + Invite buttons: white labels, 1px smaller text.
        local function SlimWhiteLabel(button)
            if not button then
                return
            end
            local lfs2 = button.GetFontString and button:GetFontString()
            if not lfs2 then
                return
            end
            Skin.White(lfs2)
            local ld2 = GetFFD(lfs2)
            if not ld2.shrunk then
                local pth, sz, fl = lfs2:GetFont()
                if pth and sz then
                    ld2.shrunk = true
                    lfs2:SetFont(pth, sz - 1, fl)
                end
            end
        end
        SlimWhiteLabel(win.CommunitiesControlFrame and win.CommunitiesControlFrame.CommunitiesSettingsButton)
        SlimWhiteLabel(win.InviteButton)
        local infoFrame = _G.CommunitiesFrameGuildDetailsFrameInfo
        local newsFrame = _G.CommunitiesFrameGuildDetailsFrameNews
        for _, subPanel in ipairs({ infoFrame, newsFrame }) do
            if subPanel then
                -- Keep our divider (stored as the pane's protected fill): Restrip
                -- honors protect keys, but a plain FadeRegions does not.
                local keepSub = {}
                local sd4 = FFD[subPanel]
                if sd4 and sd4.fill then
                    keepSub[sd4.fill] = true
                end
                Skin.FadeRegions(subPanel, keepSub)
                Skin.Register(subPanel, true)
                if subPanel.TitleText then
                    Skin.Font(subPanel.TitleText)
                    Skin.White(subPanel.TitleText)
                end
                if subPanel.ScrollBar then
                    Skin.ScrollBar(subPanel.ScrollBar)
                end
                if subPanel.DetailsFrame and subPanel.DetailsFrame.ScrollBar then
                    Skin.ScrollBar(subPanel.DetailsFrame.ScrollBar)
                end
            end
        end
        -- Info tab dividers: vertical between the info and news columns, plus a
        -- horizontal above Guild Information. The horizontal one is stored as the
        -- info pane's protected fill, since that pane is registered for restrips
        -- and would fade an unprotected anonymous region.
        if gdet and infoFrame and newsFrame and not GetFFD(gdet).dividers then
            GetFFD(gdet).dividers = true
            local mid = gdet:CreateTexture(nil, "OVERLAY")
            mid:SetColorTexture(1, 1, 1, 0.15)
            mid:SetWidth(1)
            mid:SetPoint("TOP", newsFrame, "TOPLEFT", -7, -4)
            mid:SetPoint("BOTTOM", newsFrame, "BOTTOMLEFT", -7, 4)
            local above = infoFrame:CreateTexture(nil, "OVERLAY")
            above:SetColorTexture(1, 1, 1, 0.15)
            above:SetHeight(1)
            above:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 14, -194)
            above:SetPoint("TOPRIGHT", infoFrame, "TOPRIGHT", -7, -194)
            GetFFD(infoFrame).fill = above
        end

        local filters = _G.CommunitiesGuildNewsFiltersFrame
        if filters and not GetFFD(filters).skinned then
            GetFFD(filters).skinned = true
            Skin.Panel(filters)
            local fcb = filters.CloseButton or _G.CommunitiesGuildNewsFiltersFrameCloseButton
            if fcb then
                Skin.CloseButton(fcb)
            end
            for _, keyName in ipairs({
                "GuildAchievement",
                "Achievement",
                "DungeonEncounter",
                "EpicItemLooted",
                "EpicItemCrafted",
                "EpicItemPurchased",
                "LegendaryItemLooted",
            }) do
                if filters[keyName] then
                    SkinGuildCheck(filters[keyName])
                end
            end
        end
        if type(_G.GuildNewsButton_SetNews) == "function" and not _guildNewsHook then
            _guildNewsHook = true
            hooksecurefunc("GuildNewsButton_SetNews", function(btnFrame)
                if btnFrame and btnFrame.header and btnFrame.header.SetAlpha then
                    btnFrame.header:SetAlpha(0)
                end
            end)
        end

        for _, keyName in ipairs({ "Inset", "LeftInset", "RightInset" }) do
            if win[keyName] then
                Skin.Inset(win[keyName])
            end
        end
        SkinGuildControls(win)
        local function RefreshGuild()
            if not win:IsVisible() then
                return
            end
            SkinGuildDialogs(win)
            SkinGuildLog()
            SkinGuildControls(win)
            SkinRosterColumns()
            -- State-dependent tab opacity remains Blizzard-driven. Do not branch
            -- on the enabled state: it can be secret under forced restrictions.
            for _, key in ipairs(GUILD_TAB_KEYS) do
                local tabBtn = win[key]
                if tabBtn then
                    tabBtn:SetAlphaFromBoolean(tabBtn:IsEnabled(), 1, 0.5)
                end
            end
            Skin.Restrip("guild")
            -- The guild tabs are display-mode buttons, not PanelTemplates tabs, so
            -- the engine's SetTab/UpdateTabs hooks never refresh their active
            -- visual; the reopen pass has to (O(skinned tabs), one pass per show).
            Skin.UpdateAllTabs()
        end
        status.refreshGuild = Skin.WindowCallback("guild", RefreshGuild)
        Skin.HookShow(win, Skin.Debounce(status.refreshGuild))
    end

    Skin_Guild = Skin.WindowCallback("guild", Skin_Guild)

    Skin.RegisterWindow({
        key = "guild",
        addons = { Blizzard_Communities = true },
        apply = Skin_Guild,
    })
end

-------------------------------------------------------------------------------
--  Calendar (CalendarFrame)
-------------------------------------------------------------------------------
-- Shift a frame up by dyUp px, preserving EVERY anchor point (one-shot): a
-- single-point reseat would width-collapse a multi-anchored frame.
local function CalReseat(widget, dyUp)
    if not widget then
        return
    end
    local skinData = GetFFD(widget)
    if skinData.reseated then
        return
    end
    local numPoints = widget:GetNumPoints() or 0
    if numPoints < 1 then
        return
    end
    local pts = {}
    for idx = 1, numPoints do
        local point, relTo, relPoint, posX, posY = widget:GetPoint(idx)
        if not point then
            return
        end
        pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + dyUp }
    end
    skinData.reseated = true
    widget:ClearAllPoints()
    for idx = 1, #pts do
        local tbl = pts[idx]
        widget:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
    end
end

do
    local _calendarHook = false
    local function SkinCalendarDays()
        for idx = 1, 42 do
            local day = _G["CalendarDayButton" .. idx]
            if day then
                local skinData = GetFFD(day)
                if not skinData.bg then
                    if day.SetNormalTexture then
                        day:SetNormalTexture("")
                    end
                    local nt = day.GetNormalTexture and day:GetNormalTexture()
                    if nt then
                        nt:SetAlpha(0)
                    end
                    local bgTex = day:CreateTexture(nil, "BACKGROUND", nil, -8)
                    bgTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
                    bgTex:SetAllPoints(day)
                    skinData.bg = bgTex
                    Skin.AddBorder(day)
                end
            end
        end
    end

    local function Skin_Calendar()
        local win = _G.CalendarFrame
        if not win then
            return
        end
        Skin.Shell("calendar", win)
        -- Drop the shell's black top-bar strip (clashes with month header row); shell stores it in the engine's own FFD.
        local ed = Skin.FFD and Skin.FFD[win]
        if ed and ed.topBar and ed.topBar.SetAlpha then
            ed.topBar:SetAlpha(0)
        end
        Skin.CommonChrome(win, "Calendar")
        if _G.CalendarCloseButton then
            Skin.CloseButton(_G.CalendarCloseButton)
        end
        if _G.CalendarPrevMonthButton then
            Skin.PageButton(_G.CalendarPrevMonthButton, "<", 16)
        end
        if _G.CalendarNextMonthButton then
            Skin.PageButton(_G.CalendarNextMonthButton, ">", 16)
        end
        SkinCalendarDays()
        Skin.ButtonsIn(win)
        Skin.ScrollBarsIn(win)
        Skin.FadeArtIn(win)

        -- Filter dropdown: left-align "Filters" label; it and the close button rise 10px (both sit low against the shell top bar).
        if win.FilterButton then
            LeftAlignFilterLabel(win.FilterButton)
            CalReseat(win.FilterButton, 10)
        end
        if _G.CalendarCloseButton then
            CalReseat(_G.CalendarCloseButton, 10)
        end

        -- Holiday view popup: style-aware shell backdrop (atlas/Modern flat, not a
        -- flat black panel), header art gone, no screen-dimming modal overlay, house close.
        local hf = _G.CalendarViewHolidayFrame
        if hf then
            local function SkinHoliday()
                Skin.Shell("calendar", hf)
                if hf.Border and hf.Border.SetAlpha then
                    hf.Border:SetAlpha(0)
                end
                if hf.Header then
                    Skin.FadeRegions(hf.Header)
                end
                local shade = _G.CalendarViewHolidayFrameModalOverlay
                if shade and shade.SetAlpha then
                    shade:SetAlpha(0)
                end
                -- Header text: white, shifted down 5px (one-shot).
                local ht = hf.HeaderText
                    or _G.CalendarViewHolidayFrameHeaderText
                    or (hf.Header and hf.Header.Text)
                if ht then
                    Skin.Font(ht)
                    Skin.White(ht)
                    CalReseat(ht, -5)
                end
                local creatureBtn = _G.CalendarViewHolidayCloseButton
                if creatureBtn then
                    Skin.CloseButton(creatureBtn)
                    -- Nudge the house X glyph up 6px (one-shot).
                    local creatureData = GetFFD(creatureBtn)
                    if creatureData.x and not creatureData.xNudged then
                        creatureData.xNudged = true
                        creatureData.x:SetPoint("CENTER", -2, 6)
                    end
                end
            end
            SkinHoliday()
            Skin.HookShow(hf, Skin.Debounce(SkinHoliday))
        end

        -- Create Event popup: STYLE-AWARE shell backdrop (a flat Panel would not
        -- match the other calendar popups), time/type dropdowns, title+invite
        -- inputs, top-right close, title down 5px, class-icon column right 3px,
        -- leftover Blizzard border sub-frame + divider hidden.
        local cef = _G.CalendarCreateEventFrame
        if cef then
            local function SkinCreateEvent()
                Skin.Shell("calendar", cef)
                if cef.Header then
                    Skin.FadeRegions(cef.Header)
                end
                -- Stray art: border sub-frame (Bg+edges, hidden via alpha inheritance) and the divider.
                if cef.Border and cef.Border.SetAlpha then
                    cef.Border:SetAlpha(0)
                end
                if _G.CalendarCreateEventDivider and _G.CalendarCreateEventDivider.SetAlpha then
                    _G.CalendarCreateEventDivider:SetAlpha(0)
                end
                -- Dropdowns (event type + hour/minute/AM-PM + difficulty when shown).
                for _, keyName in ipairs({
                    "EventTypeDropdown",
                    "HourDropdown",
                    "MinuteDropdown",
                    "AMPMDropdown",
                    "DifficultyOptionDropdown",
                }) do
                    if cef[keyName] then
                        Skin.Dropdown(cef[keyName])
                    end
                end
                if _G.CalendarCreateEventTitleEdit then
                    Skin.EditBox(_G.CalendarCreateEventTitleEdit)
                end
                if _G.CalendarCreateEventInviteEdit then
                    Skin.EditBox(_G.CalendarCreateEventInviteEdit)
                end
                -- Close button (top right): house X glyph nudged up 6px (one-shot).
                local cceCB = _G.CalendarCreateEventCloseButton
                if cceCB then
                    Skin.CloseButton(cceCB)
                    local creatureData = GetFFD(cceCB)
                    if creatureData.x and not creatureData.xNudged then
                        creatureData.xNudged = true
                        creatureData.x:SetPoint("CENTER", -2, 6)
                    end
                end
                -- Action buttons + lock checkbox.
                for _, keyName in ipairs({
                    "CalendarCreateEventCreateButton",
                    "CalendarCreateEventMassInviteButton",
                    "CalendarCreateEventInviteButton",
                    "CalendarCreateEventRaidInviteButton",
                }) do
                    if _G[keyName] then
                        Skin.Button(_G[keyName])
                    end
                end
                -- borderInset 4: frame is larger than its check graphic, so the border must hug the visible box, not the frame.
                if _G.CalendarCreateEventLockEventCheck then
                    Skin.Checkbox(_G.CalendarCreateEventLockEventCheck, { borderInset = 4 })
                end
                local il = _G.CalendarCreateEventInviteList
                if il and il.ScrollBar then
                    Skin.ScrollBar(il.ScrollBar)
                end
                -- Title down 5px (find the header's title FontString).
                local titleFS = (cef.Header and cef.Header.Text) or _G.CalendarCreateEventTitle
                if not titleFS and cef.Header and cef.Header.GetRegions then
                    local regionList = { cef.Header:GetRegions() }
                    for idx = 1, #regionList do
                        local region = regionList[idx]
                        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                            titleFS = region
                            break
                        end
                    end
                end
                if titleFS then
                    CalReseat(titleFS, -5)
                end
                -- Class-icon column: button 1 anchors to the container, the rest
                -- chain off it, so nudging the container right 3px moves the whole column (one-shot).
                local ccc = _G.CalendarClassButtonContainer
                if ccc and not GetFFD(ccc).nudgedRight then
                    local pointCount = ccc:GetNumPoints() or 0
                    local pts, success = {}, pointCount > 0
                    for idx = 1, pointCount do
                        local point, relTo, relPoint, posX, posY = ccc:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, (posX or 0) + 3, posY or 0 }
                    end
                    if success then
                        GetFFD(ccc).nudgedRight = true
                        ccc:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            ccc:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                end
            end
            SkinCreateEvent()
            Skin.HookShow(cef, Skin.Debounce(SkinCreateEvent))
        end

        -- Event picker popup (day with multiple events): style-aware shell
        -- backdrop, leftover Blizzard border/button-bar/close-border gone, house
        -- close + scrollbar, title down 8px.
        local popFrame = _G.CalendarEventPickerFrame
        if popFrame then
            local function SkinEventPicker()
                Skin.Shell("calendar", popFrame)
                if popFrame.Border and popFrame.Border.SetAlpha then
                    popFrame.Border:SetAlpha(0)
                end
                for _, n in ipairs({
                    "CalendarEventPickerFrameButtonBackground",
                    "CalendarEventPickerCloseButtonBorder",
                }) do
                    local part = _G[n]
                    if part and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
                if popFrame.Header then
                    Skin.FadeRegions(popFrame.Header)
                end
                -- Bottom text "Close" button, NOT a corner X: plain button + white label, no stray X glyph.
                local pcb = _G.CalendarEventPickerCloseButton
                if pcb then
                    Skin.Button(pcb)
                    local cfs = pcb.GetFontString and pcb:GetFontString()
                    if cfs then
                        Skin.White(cfs)
                    end
                end
                local scrollBar = popFrame.ScrollBar
                    or _G.CalendarEventPickerFrameScrollBar
                    or (popFrame.ScrollBox and popFrame.ScrollBox.ScrollBar)
                if scrollBar then
                    Skin.ScrollBar(scrollBar)
                end
                -- Title down 8px (header title FontString).
                local titleFS = (popFrame.Header and popFrame.Header.Text)
                    or _G.CalendarEventPickerFrameTitle
                    or popFrame.Title
                if not titleFS and popFrame.Header and popFrame.Header.GetRegions then
                    local regionList = { popFrame.Header:GetRegions() }
                    for idx = 1, #regionList do
                        local region = regionList[idx]
                        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                            titleFS = region
                            break
                        end
                    end
                end
                if titleFS then
                    CalReseat(titleFS, -8)
                end
            end
            SkinEventPicker()
            Skin.HookShow(popFrame, Skin.Debounce(SkinEventPicker))
        end

        if not _calendarHook and type(_G.CalendarFrame_Update) == "function" then
            _calendarHook = true
            hooksecurefunc(
                "CalendarFrame_Update",
                Skin.Debounce(function()
                    if win:IsVisible() then
                        SkinCalendarDays()
                        Skin.Restrip()
                    end
                end)
            )
        end
        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    SkinCalendarDays()
                    Skin.Restrip()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "calendar",
        addons = { Blizzard_Calendar = true },
        apply = Skin_Calendar,
    })
end

-------------------------------------------------------------------------------
--  Achievements (AchievementFrame)
-------------------------------------------------------------------------------
do
    -- White house-font text on a frame's direct FontString regions.
    local function AchWhiteTexts(owner)
        if not owner or not owner.GetRegions then
            return
        end
        local regionList = { owner:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region.IsObjectType and region:IsObjectType("FontString") then
                Skin.Font(region)
                Skin.White(region)
            end
        end
    end

    local function AchWhiteTextsIn(owner, nestDepth)
        nestDepth = nestDepth or 0
        if not owner or nestDepth > 5 or owner:IsForbidden() then
            return
        end
        if nestDepth > 0 and Skin.IsForeignFrame(owner) then
            return
        end
        AchWhiteTexts(owner)
        if not owner.GetChildren then
            return
        end
        local children = { owner:GetChildren() }
        for idx = 1, #children do
            AchWhiteTextsIn(children[idx], nestDepth + 1)
        end
    end

    -- Progress bar -> flat accent bar (the professions-window look): cap/trough
    -- art gone, accent fill, dark trough, 1px border, white labels.
    local function AchAccentBar(barFrame)
        if not barFrame or barFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(barFrame)
        local fillTex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
        if fillTex then
            skinData.fill = fillTex
        end
        local keepSet = {}
        if skinData.fill then
            keepSet[skinData.fill] = true
        end
        if skinData.bg then
            keepSet[skinData.bg] = true
        end
        Skin.FadeRegions(barFrame, keepSet)
        Skin.Register(barFrame, true)
        if barFrame.SetStatusBarTexture then
            barFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            Skin.ApplyBarFill(barFrame)
        end
        if not skinData.bg then
            local bgTex = barFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
            bgTex:SetColorTexture(0.12, 0.12, 0.12, 0.85)
            bgTex:SetAllPoints(barFrame)
            skinData.bg = bgTex
            Skin.AddBorder(barFrame)
        end
        local n = barFrame.GetName and barFrame:GetName()
        for _, key in ipairs({ "Title", "Label", "Text" }) do
            local fontStr = barFrame[key] or (n and _G[n .. key])
            if fontStr and fontStr.SetTextColor then
                Skin.Font(fontStr)
                Skin.White(fontStr)
                -- Bar text 3px lower (one-shot), as on professions bars: house font rides high on these.
                local regionData = GetFFD(fontStr)
                if not regionData.lowered then
                    local point, relTo, relPoint, posX, posY = fontStr:GetPoint(1)
                    if point then
                        local offsetY = -3
                        if barFrame and barFrame.GetParent then
                            local parent = barFrame:GetParent()
                            -- Under AchievementFrameAchievementsObjectives, bar is the
                            -- progress bar itself (not the holder): match parent name, needs no offset.
                            if
                                parent
                                and parent.GetName
                                and parent:GetName() == "AchievementFrameAchievementsObjectives"
                            then
                                offsetY = 0
                            end
                        end
                        regionData.lowered = true
                        fontStr:ClearAllPoints()
                        fontStr:SetPoint(point, relTo, relPoint, posX or 0, (posY or 0) + offsetY)
                    end
                end
            end
        end
    end

    -- Title tinted like the row art this pack strips: account-wide = blue,
    -- character = gold; no completion date = the dimmed take on the same hue.
    local function AchTitleColor(row)
        local fontStr = row.Label
        if not fontStr or not fontStr.SetTextColor then
            return
        end
        local done = row.DateCompleted and row.DateCompleted.IsShown and row.DateCompleted:IsShown()
        if row.accountWide then
            if done then
                fontStr:SetTextColor(0.35, 0.75, 1)
            else
                fontStr:SetTextColor(0.24, 0.46, 0.6)
            end
        else
            if done then
                fontStr:SetTextColor(1, 0.85, 0.35)
            else
                fontStr:SetTextColor(0.64, 0.56, 0.3)
            end
        end
    end

    -- Hold a texture permanently invisible against Blizzard's re-raises: a
    -- reentry-guarded SetAlpha post-hook forces it back to 0 (a plain SetAlpha(0)
    -- is reverted by the next row re-init on expand/select). Taint-safe (hooksecurefunc only).
    local function KillTex(t)
        if not t or not t.SetAlpha then
            return
        end
        t:SetAlpha(0)
        local titleData = GetFFD(t)
        if titleData.killed then
            return
        end
        titleData.killed = true
        hooksecurefunc(t, "SetAlpha", function(self)
            local dropdown = GetFFD(self)
            if dropdown.inKill then
                return
            end
            dropdown.inKill = true
            self:SetAlpha(0)
            dropdown.inKill = false
        end)
    end

    -- Lock a fontstring to the house font + a color, re-applied whenever Blizzard
    -- swaps its font object or recolors it (the achievement list reverts BOTH on
    -- expand/select). colorFn(fs) applies the color, nil = white. One-time hooks per string.
    local function LockAchText(fontStr, colorFn)
        if not fontStr or not fontStr.SetFont then
            return
        end
        local fieldData = GetFFD(fontStr)
        fieldData.colorFn = colorFn
        local function reapply()
            if fieldData.inLock then
                return
            end
            fieldData.inLock = true
            Skin.Font(fontStr)
            if fieldData.colorFn then
                fieldData.colorFn(fontStr)
            else
                Skin.White(fontStr)
            end
            fieldData.inLock = false
        end
        reapply()
        if not fieldData.textLocked then
            fieldData.textLocked = true
            if fontStr.SetFontObject then
                hooksecurefunc(fontStr, "SetFontObject", reapply)
            end
            hooksecurefunc(fontStr, "SetFont", reapply)
            if fontStr.SetTextColor then
                hooksecurefunc(fontStr, "SetTextColor", reapply)
            end
        end
    end

    -- Kill every Blizzard TEXTURE on the row (keyed + anon), sparing our bg+hover
    -- and all fontstrings. NineSlice is a child FRAME, not a direct region: kill it whole (alpha inherits to Center+edges).
    local function KillAchRowArt(row, skinData)
        local regionList = { row:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region ~= skinData.bg and region ~= skinData.hover and region.IsObjectType and region:IsObjectType("Texture") then
                KillTex(region)
            end
        end
        if row.NineSlice then
            KillTex(row.NineSlice)
        end
        if row.Icon and row.Icon.frame then
            KillTex(row.Icon.frame)
        end
        if row.Check then
            KillTex(row.Check)
        end
    end

    -- Achievement row (main + summary list): parchment/glow art gone, flat block +
    -- subtle hover, squared icon, white house-font text. Art and text must be
    -- LOCKED (KillTex/LockAchText); a per-pass re-fade loses the race against Blizzard's re-init on expand/select.
    local function SkinAchRow(row)
        if not row or row:IsForbidden() then
            return
        end
        local skinData = GetFFD(row)
        if not skinData.bg then
            local bgTex = row:CreateTexture(nil, "BACKGROUND", nil, -3)
            bgTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
            bgTex:SetPoint("TOPLEFT", 1, -1)
            bgTex:SetPoint("BOTTOMRIGHT", -1, 1)
            skinData.bg = bgTex
            Skin.AddBorder(row)
            local hoverTex = SolidTex(row, "HIGHLIGHT", 1, 1, 1, 0.08)
            hoverTex:SetAllPoints(row)
            skinData.hover = hoverTex
            Skin.Register(row, true)
            if row.Icon and row.Icon.texture then
                Skin.SquareIcon(row.Icon.texture, row.Icon)
            end
            -- Text locks: Label keeps its per-state color, the rest go white.
            -- HiddenDescription is the FULL description swapped in on expand
            -- (collapsed row shows truncated Description) and must be locked too, or it reverts on click.
            LockAchText(row.Label, function()
                AchTitleColor(row)
            end)
            LockAchText(row.Description, nil)
            LockAchText(row.HiddenDescription, nil)
            LockAchText(row.DateCompleted, nil)
            if row.Shield and row.Shield.Points then
                LockAchText(row.Shield.Points, nil)
            end
            if row.DisplayObjectives then
                hooksecurefunc(row, "DisplayObjectives", function(objectiveRow)
                    -- Expand rebuilds the row art: re-kill it and re-color the title
                    -- (completed state can flip on expand); font/color locks hold the
                    -- rest. Immediate + next-frame catches a deferred re-show.
                    local regionData = GetFFD(objectiveRow)
                    KillAchRowArt(objectiveRow, regionData)
                    AchTitleColor(objectiveRow)
                    if C_Timer then
                        C_Timer.After(0, function()
                            KillAchRowArt(objectiveRow, regionData)
                            AchTitleColor(objectiveRow)
                        end)
                    end
                    local success, of = pcall(objectiveRow.GetObjectiveFrame, objectiveRow)
                    if success and of and of.progressBars then
                        for _, button in pairs(of.progressBars) do
                            AchAccentBar(button)
                        end
                    end
                end)
            end
        end
        KillAchRowArt(row, skinData)
        AchTitleColor(row)
    end

    -- Category list row (left side): the clickable is the child's Button.
    local function SkinCategoryRow(childFrame)
        local btnFrame = childFrame and childFrame.Button
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(btnFrame)
        if not skinData.bg then
            local bgTex = btnFrame:CreateTexture(nil, "BACKGROUND", nil, -3)
            bgTex:SetColorTexture(Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
            bgTex:SetPoint("TOPLEFT", 1, -1)
            bgTex:SetPoint("BOTTOMRIGHT", -1, 1)
            skinData.bg = bgTex
            Skin.AddBorder(btnFrame)
            local hoverTex = SolidTex(btnFrame, "HIGHLIGHT", 1, 1, 1, 0.1)
            hoverTex:SetAllPoints(btnFrame)
            skinData.hover = hoverTex
            Skin.Register(btnFrame, true)
        end
        -- Pooled rows: re-fade the native art every pass (see SkinAchRow).
        if btnFrame.Background and btnFrame.Background.SetAlpha then
            btnFrame.Background:SetAlpha(0)
        end
        local keepSet = {}
        if skinData.bg then
            keepSet[skinData.bg] = true
        end
        if skinData.hover then
            keepSet[skinData.hover] = true
        end
        Skin.FadeRegions(btnFrame, keepSet)
        if btnFrame.Label then
            Skin.White(btnFrame.Label)
            -- Category labels sit low in the house font: raise 3px (one-shot).
            -- Label is pinned by BOTH edges, so EVERY anchor must survive the shift
            -- or the text collapses onto its remaining pin.
            local regionData = GetFFD(btnFrame.Label)
            if not regionData.raised then
                local fsn = btnFrame.Label
                local numPts = fsn:GetNumPoints()
                if numPts and numPts > 0 then
                    local pts, success = {}, true
                    for idx = 1, numPts do
                        local point, relTo, relPoint, posX, posY = fsn:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + 3 }
                    end
                    if success then
                        regionData.raised = true
                        fsn:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            fsn:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                end
            end
        end
    end

    -- Statistics row: art gone, subtle hover, white text.
    local function SkinStatRow(childFrame)
        if not childFrame or childFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(childFrame)
        if not skinData.statSkinned then
            skinData.statSkinned = true
            Skin.FadeRegions(childFrame)
            Skin.Register(childFrame, true)
            local hoverTex = SolidTex(childFrame, "HIGHLIGHT", 1, 1, 1, 0.08)
            hoverTex:SetAllPoints(childFrame)
            skinData.hover = hoverTex
        end
        AchWhiteTexts(childFrame)
    end

    -- Search result row (popout list): flat + hover, squared icon, white text.
    local function SkinResultRow(childFrame)
        if not childFrame or childFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(childFrame)
        if not skinData.bg then
            local bgTex = childFrame:CreateTexture(nil, "BACKGROUND", nil, -3)
            bgTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
            bgTex:SetAllPoints(childFrame)
            skinData.bg = bgTex
            local hoverTex = SolidTex(childFrame, "HIGHLIGHT", 1, 1, 1, 0.1)
            hoverTex:SetAllPoints(childFrame)
            skinData.hover = hoverTex
            Skin.Register(childFrame, true)
            if childFrame.Icon then
                Skin.SquareIcon(childFrame.Icon)
            end
        end
        -- Pooled rows: re-fade the native art every pass (see SkinAchRow).
        local keepSet = {}
        if skinData.bg then
            keepSet[skinData.bg] = true
        end
        if skinData.hover then
            keepSet[skinData.hover] = true
        end
        Skin.FadeRegions(childFrame, keepSet)
        AchWhiteTexts(childFrame)
    end

    -- Search preview button (dropdown under the search box).
    local function SkinPreviewBtn(btnFrame)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(btnFrame)
        if not skinData.bg then
            local glyphTex = btnFrame.icon or btnFrame.Icon
            local keepSet = glyphTex and { [glyphTex] = true } or nil
            Skin.FadeRegions(btnFrame, keepSet)
            local bgTex = btnFrame:CreateTexture(nil, "BACKGROUND", nil, -3)
            bgTex:SetColorTexture(0.05, 0.05, 0.05, 0.95)
            bgTex:SetAllPoints(btnFrame)
            skinData.bg = bgTex
            Skin.AddBorder(btnFrame)
            local hoverTex = SolidTex(btnFrame, "HIGHLIGHT", 1, 1, 1, 0.1)
            hoverTex:SetAllPoints(btnFrame)
            skinData.hover = hoverTex
            Skin.Register(btnFrame, keepSet or true)
            if glyphTex then
                Skin.SquareIcon(glyphTex, btnFrame)
            end
        end
        AchWhiteTexts(btnFrame)
    end

    local _achSummaryHook = false
    local _achCritHook = false
    local function Skin_Achievements()
        local win = _G.AchievementFrame
        if not win then
            return
        end
        -- Frame rect extends above the visible panel (floating points header), so
        -- the shell skips its border to avoid a line drawn across mid-air.
        Skin.Shell("achievements", win, { noBorder = true })
        Skin.CommonChrome(win, "AchievementFrame")

        -- Header banner: art gone, title+points in house font on a flat plate.
        -- Plate anchors to the TEXT (resizes with tab title), sits a frame level
        -- lower so it draws under the strings.
        local owner = win.Header or _G.AchievementFrameHeader
        if owner then
            Skin.FadeRegions(owner)
            Skin.Register(owner, true)
            local titleText = owner.Title or _G.AchievementFrameHeaderTitle
            local points = owner.Points or _G.AchievementFrameHeaderPoints
            if titleText then
                Skin.Font(titleText)
                Skin.White(titleText)
            end
            if points then
                Skin.Font(points)
                Skin.White(points)
            end
            local hd = GetFFD(owner)
            if not hd.plate and titleText and points then
                local backing = CreateFrame("Frame", nil, owner)
                backing:SetFrameLevel(math.max(0, owner:GetFrameLevel() - 1))
                backing:SetPoint("TOP", titleText, "TOP", 0, 9)
                backing:SetPoint("BOTTOM", points, "BOTTOM", 0, -9)
                backing:SetPoint("LEFT", titleText, "LEFT", -28, 0)
                backing:SetPoint("RIGHT", titleText, "RIGHT", 28, 0)
                local fillTex = SolidTex(backing, "BACKGROUND", 0, 0, 0, 1)
                fillTex:SetAllPoints(backing)
                hd.plateFill = fillTex
                Skin.AddBorder(backing)
                hd.plate = backing
            end
        end
        -- Plate fill per style: cui = #070604 opaque, Modern = #050505 at the
        -- user's Modern backdrop opacity. Re-tinted every show so style/opacity edits carry over.
        local function RetintHeaderPlate()
            local hd2 = owner and FFD[owner]
            local fillTex = hd2 and hd2.plateFill
            if not fillTex then
                return
            end
            if Skin.GetStyle("achievements") == "modern" then
                local _, _, _, menuArrow = Skin.GetModernBG()
                fillTex:SetColorTexture(0.0196, 0.0196, 0.0196, menuArrow or 1)
            else
                fillTex:SetColorTexture(0.0275, 0.0235, 0.0157, 1)
            end
        end
        RetintHeaderPlate()
        for _, label in ipairs({
            "AchievementFrameMetalBorderTop",
            "AchievementFrameMetalBorderBottom",
            "AchievementFrameMetalBorderLeft",
            "AchievementFrameMetalBorderRight",
            "AchievementFrameMetalBorderTopLeft",
            "AchievementFrameMetalBorderTopRight",
            "AchievementFrameMetalBorderBottomLeft",
            "AchievementFrameMetalBorderBottomRight",
            "AchievementFrameWoodBorderTopLeft",
            "AchievementFrameWoodBorderTopRight",
            "AchievementFrameWoodBorderBottomLeft",
            "AchievementFrameWoodBorderBottomRight",
            "AchievementFrameWaterMark",
            "AchievementFrameStatsBG",
        }) do
            local part = _G[label]
            if part and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        for _, label in ipairs({
            "AchievementFrameSummary",
            "AchievementFrameAchievements",
            "AchievementFrameAchievementsContainer",
            "AchievementFrameCategories",
            "AchievementFrameCategoriesContainer",
            "AchievementFrameStats",
            "AchievementFrameComparison",
        }) do
            local subPanel = _G[label]
            if subPanel then
                Skin.FadeRegions(subPanel)
                Skin.Register(subPanel, true)
            end
        end
        -- Every list pane wraps content in an anonymous inset child whose NineSlice
        -- is the box art, so fade any such child. Swept again on show: some panes only build theirs when first opened.
        local function SweepInsetChildren()
            for _, label in ipairs({
                "AchievementFrameSummary",
                "AchievementFrameStats",
                "AchievementFrameAchievements",
                "AchievementFrameCategories",
                "AchievementFrameComparison",
            }) do
                local subPanel = _G[label]
                if subPanel then
                    local children = { subPanel:GetChildren() }
                    for idx = 1, #children do
                        local child = children[idx]
                        if child and child.NineSlice and not Skin.IsForeignFrame(child, subPanel) then
                            Skin.FadeNineSlice(child.NineSlice)
                            Skin.FadeRegions(child)
                            Skin.Register(child, true)
                        end
                    end
                end
            end
        end
        SweepInsetChildren()

        -- Search box: tucked into the top bar's right side, filter dropdown left.
        local searchField = win.SearchBox
        if searchField then
            Skin.EditBox(searchField)
            local partData = GetFFD(searchField)
            if not partData.moved then
                partData.moved = true
                searchField:ClearAllPoints()
                searchField:SetPoint("TOPRIGHT", win, "TOPRIGHT", -28, -3)
                searchField:SetSize(150, 19)
            end
        end
        local filt = win.FilterDropdown or _G.AchievementFrameFilterDropdown
        if filt then
            Skin.Dropdown(filt)
            local fieldData = GetFFD(filt)
            if not fieldData.moved then
                fieldData.moved = true
                filt:ClearAllPoints()
                filt:SetPoint("TOPLEFT", win, "TOPLEFT", 26, -3)
            end
            -- Label pinned left (this dropdown only), clear of the arrow.
            local labelText = filt.Text or (filt.GetFontString and filt:GetFontString())
            if labelText and not fieldData.labLeft then
                fieldData.labLeft = true
                labelText:ClearAllPoints()
                labelText:SetPoint("LEFT", filt, "LEFT", 8, 0)
                labelText:SetPoint("RIGHT", filt, "RIGHT", -22, 0)
                if labelText.SetJustifyH then
                    labelText:SetJustifyH("LEFT")
                end
            end
        end

        -- Search preview popout + full results panel.
        local pv = win.SearchPreviewContainer
        if pv then
            Skin.FadeRegions(pv)
            Skin.Register(pv, true)
            for idx = 1, 5 do
                SkinPreviewBtn(pv["SearchPreview" .. idx])
            end
            SkinPreviewBtn(pv.ShowAllSearchResults)
        end
        local sr = win.SearchResults
        if sr then
            Skin.Panel(sr)
            local rb = sr.ScrollBox
            if rb and rb.ForEachFrame then
                pcall(rb.ForEachFrame, rb, SkinResultRow)
                if rb.Update and not GetFFD(rb).rowHook then
                    GetFFD(rb).rowHook = true
                    hooksecurefunc(rb, "Update", function(tabBox)
                        pcall(tabBox.ForEachFrame, tabBox, SkinResultRow)
                    end)
                end
            end
        end

        local sweepOnTab = Skin.Debounce(function()
            if win:IsVisible() then
                SweepInsetChildren()
                Skin.Restrip()
            end
        end)
        local achTabs = {}
        for idx = 1, 3 do
            local part = _G["AchievementFrameTab" .. idx]
            if part then
                Skin.Tab(part)
                achTabs[#achTabs + 1] = part
                if not GetFFD(part).sweepHook then
                    GetFFD(part).sweepHook = true
                    part:HookScript("OnClick", sweepOnTab)
                end
            end
        end
        Skin.NormalizeTabRow(achTabs)
        -- Comparison mode toggles tabs in this row: the normalize pass skips a
        -- hidden tab, then Blizzard seats it with stock anchors on show, landing on
        -- top of the tab our chain already placed. Re-chain synchronously whenever Blizzard moves/toggles any of them.
        do
            local fieldData = GetFFD(win)
            if not fieldData.tabNormHook then
                fieldData.tabNormHook = true
                local guard = false
                local function ReNorm()
                    if guard then
                        return
                    end
                    guard = true
                    Skin.NormalizeTabRow(achTabs)
                    guard = false
                end
                for _, tab in ipairs(achTabs) do
                    hooksecurefunc(tab, "SetPoint", ReNorm)
                    tab:HookScript("OnShow", ReNorm)
                    tab:HookScript("OnHide", ReNorm)
                end
            end
        end
        Skin.ScrollBarsIn(win)

        -- List rows are ScrollBox-pooled; restyle realized rows on every list update (cost scales with visible rows only).
        local function HookRows(hostFrame, func)
            local scrollBar = hostFrame and hostFrame.ScrollBox
            if not (scrollBar and scrollBar.ForEachFrame) then
                return
            end
            pcall(scrollBar.ForEachFrame, scrollBar, func)
            if scrollBar.Update and not GetFFD(scrollBar).rowHook then
                GetFFD(scrollBar).rowHook = true
                hooksecurefunc(scrollBar, "Update", function(tabBox)
                    pcall(tabBox.ForEachFrame, tabBox, func)
                end)
            end
        end
        HookRows(_G.AchievementFrameCategories, SkinCategoryRow)
        HookRows(_G.AchievementFrameAchievements, SkinAchRow)
        HookRows(_G.AchievementFrameStats, SkinStatRow)

        -- Category sidebar sits 10px lower as a unit: shift its ScrollBox once, preserving every anchor.
        local catBox = _G.AchievementFrameCategories and _G.AchievementFrameCategories.ScrollBox
        if catBox and not GetFFD(catBox).shifted then
            local numPts = catBox:GetNumPoints()
            if numPts and numPts > 0 then
                local pts, success = {}, true
                for idx = 1, numPts do
                    local point, relTo, relPoint, posX, posY = catBox:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) - 10 }
                end
                if success then
                    GetFFD(catBox).shifted = true
                    catBox:ClearAllPoints()
                    for idx = 1, #pts do
                        local tbl = pts[idx]
                        catBox:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                    end
                end
            end
        end

        -- Achievement list (non-summary pages) drops 10px the same way.
        local achBox = _G.AchievementFrameAchievements and _G.AchievementFrameAchievements.ScrollBox
        if achBox and not GetFFD(achBox).shifted then
            local numPts = achBox:GetNumPoints()
            if numPts and numPts > 0 then
                local pts, success = {}, true
                for idx = 1, numPts do
                    local point, relTo, relPoint, posX, posY = achBox:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) - 10 }
                end
                if success then
                    GetFFD(achBox).shifted = true
                    achBox:ClearAllPoints()
                    for idx = 1, #pts do
                        local tbl = pts[idx]
                        achBox:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                    end
                end
            end
        end

        -- Summary page: heading strips faint white, summary text white house font,
        -- recent-achievement cards through row skin, 12 category bars + total bar as flat accent bars.
        for _, tn in ipairs({
            "AchievementFrameSummaryAchievementsHeaderHeader",
            "AchievementFrameSummaryCategoriesHeaderTexture",
        }) do
            local part = _G[tn]
            if part and part.SetVertexColor then
                part:SetVertexColor(1, 1, 1, 0.25)
            end
        end
        for idx = 1, 12 do
            local barFrame = _G["AchievementFrameSummaryCategoriesCategory" .. idx]
            if barFrame then
                AchAccentBar(barFrame)
                local highlight = _G["AchievementFrameSummaryCategoriesCategory" .. idx .. "ButtonHighlight"]
                if highlight and highlight.SetAlpha then
                    highlight:SetAlpha(0)
                end
            end
        end
        AchAccentBar(_G.AchievementFrameSummaryCategoriesStatusBar)
        if _G.AchievementFrameSummary then
            AchWhiteTextsIn(_G.AchievementFrameSummary)
        end
        if not _achSummaryHook and type(_G.AchievementFrameSummary_UpdateAchievements) == "function" then
            _achSummaryHook = true
            hooksecurefunc(
                "AchievementFrameSummary_UpdateAchievements",
                Skin.Debounce(function()
                    local maxSum = _G.ACHIEVEMENTUI_MAX_SUMMARY_ACHIEVEMENTS or 4
                    for idx = 1, maxSum do
                        SkinAchRow(_G["AchievementFrameSummaryAchievement" .. idx])
                    end
                end)
            )
        end

        -- Comparison view: header art gone, both summary bars as accent bars, dual player/friend cards+stat rows through pooled-row skins.
        local comp = _G.AchievementFrameComparison
        if comp then
            for _, tn in ipairs({
                "AchievementFrameComparisonHeaderBG",
                "AchievementFrameComparisonHeaderPortrait",
                "AchievementFrameComparisonHeaderPortraitBg",
            }) do
                local part = _G[tn]
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
            local compHdr = _G.AchievementFrameComparisonHeader
            if compHdr then
                Skin.FadeRegions(compHdr)
                Skin.Register(compHdr, true)
                AchWhiteTexts(compHdr)
            end
            -- Compared character's name sits in the top bar, left of the search box.
            local compName = _G.AchievementFrameComparisonHeaderName
            if compName and win.SearchBox and not GetFFD(compName).moved then
                GetFFD(compName).moved = true
                compName:ClearAllPoints()
                compName:SetPoint("RIGHT", win.SearchBox, "LEFT", -10, 0)
            end
            -- Their points ride NEXT TO the name in the user's link color, retinted whenever Blizzard rewrites the value.
            local compPts = _G.AchievementFrameComparisonHeaderPoints
            if compPts and compName and not GetFFD(compPts).moved then
                GetFFD(compPts).moved = true
                compPts:ClearAllPoints()
                compPts:SetPoint("LEFT", compName, "RIGHT", 6, 0)
                local function TintComparePoints()
                    local lr, lg, lb = Skin.LinkColor()
                    compPts:SetTextColor(lr, lg, lb)
                end
                TintComparePoints()
                hooksecurefunc(compPts, "SetText", TintComparePoints)
                if compPts.SetFormattedText then
                    hooksecurefunc(compPts, "SetFormattedText", TintComparePoints)
                end
            end
            local function SkinCompareCard(cardFrame)
                if not cardFrame or cardFrame:IsForbidden() then
                    return
                end
                local cdd = GetFFD(cardFrame)
                if not cdd.bg then
                    local bgTex = cardFrame:CreateTexture(nil, "BACKGROUND", nil, -3)
                    bgTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
                    bgTex:SetPoint("TOPLEFT", 1, -1)
                    bgTex:SetPoint("BOTTOMRIGHT", -1, 1)
                    cdd.bg = bgTex
                    Skin.AddBorder(cardFrame)
                    Skin.Register(cardFrame, true)
                    if cardFrame.Icon and cardFrame.Icon.texture then
                        Skin.SquareIcon(cardFrame.Icon.texture, cardFrame.Icon)
                    end
                end
                -- Pooled: re-fade the native art + retint text every pass.
                for _, keyName in ipairs({ "Background", "TitleBar", "Glow", "Highlight" }) do
                    local part = cardFrame[keyName]
                    if part and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
                local keepSet = {}
                if cdd.bg then
                    keepSet[cdd.bg] = true
                end
                Skin.FadeRegions(cardFrame, keepSet)
                if cardFrame.Icon and cardFrame.Icon.frame and cardFrame.Icon.frame.SetAlpha then
                    cardFrame.Icon.frame:SetAlpha(0)
                end
                AchWhiteTexts(cardFrame)
                for _, key in ipairs({ "Label", "Description", "DateCompleted" }) do
                    local fontStr = cardFrame[key]
                    if fontStr and fontStr.SetTextColor then
                        Skin.Font(fontStr)
                        Skin.White(fontStr)
                    end
                end
            end
            local function SkinCompareRow(childFrame)
                if not childFrame then
                    return
                end
                SkinCompareCard(childFrame.Player)
                SkinCompareCard(childFrame.Friend)
            end
            local ac = comp.AchievementContainer
            if ac then
                if ac.ScrollBar then
                    Skin.ScrollBar(ac.ScrollBar)
                end
                local tabBox = ac.ScrollBox
                if tabBox and tabBox.ForEachFrame then
                    pcall(tabBox.ForEachFrame, tabBox, SkinCompareRow)
                    if tabBox.Update and not GetFFD(tabBox).rowHook then
                        GetFFD(tabBox).rowHook = true
                        hooksecurefunc(tabBox, "Update", function(b2)
                            pcall(b2.ForEachFrame, b2, SkinCompareRow)
                        end)
                    end
                end
            end
            local sc = comp.StatContainer
            if sc then
                if sc.ScrollBar then
                    Skin.ScrollBar(sc.ScrollBar)
                end
                local tabBox = sc.ScrollBox
                if tabBox and tabBox.ForEachFrame then
                    pcall(tabBox.ForEachFrame, tabBox, SkinStatRow)
                    if tabBox.Update and not GetFFD(tabBox).rowHook then
                        GetFFD(tabBox).rowHook = true
                        hooksecurefunc(tabBox, "Update", function(b2)
                            pcall(b2.ForEachFrame, b2, SkinStatRow)
                        end)
                    end
                end
            end
            local summ = comp.Summary
            if summ then
                Skin.FadeRegions(summ)
                Skin.Register(summ, true)
                for _, side in ipairs({ summ.Player, summ.Friend }) do
                    if side then
                        Skin.FadeRegions(side)
                        Skin.Register(side, true)
                        if side.StatusBar then
                            AchAccentBar(side.StatusBar)
                        end
                    end
                end
            end
        end

        -- Criteria lines default to dark parchment ink: recolor on display, completed = white, incomplete = gray.
        if not _achCritHook and type(_G.AchievementObjectives_DisplayCriteria) == "function" then
            _achCritHook = true
            hooksecurefunc("AchievementObjectives_DisplayCriteria", function(of, ident)
                if not (of and ident) or (of.IsForbidden and of:IsForbidden()) then
                    return
                end
                local num = GetAchievementNumCriteria and GetAchievementNumCriteria(ident)
                if not num then
                    return
                end
                local texts, metas = 0, 0
                local barFlag = _G.EVALUATION_TREE_FLAG_PROGRESS_BAR or 1
                for idx = 1, num do
                    local _, cType, completed, _, _, _, flags, assetID =
                        GetAchievementCriteriaInfo(ident, idx)
                    local fontStr
                    if assetID and cType == _G.CRITERIA_TYPE_ACHIEVEMENT then
                        metas = metas + 1
                        local success, m = pcall(of.GetMeta, of, metas)
                        fontStr = success and m and m.Label
                    elseif bit.band(flags or 0, barFlag) ~= barFlag then
                        texts = texts + 1
                        local success, c = pcall(of.GetCriteria, of, texts)
                        fontStr = success and c and c.Name
                    end
                    if fontStr and fontStr.SetTextColor then
                        -- Lines are (re)created in Blizzard's font on display: force house font too, not just color.
                        Skin.Font(fontStr)
                        if completed then
                            fontStr:SetTextColor(1, 1, 1)
                        else
                            fontStr:SetTextColor(0.65, 0.65, 0.65)
                        end
                    end
                end
            end)
        end

        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    -- Re-run realized-row passes: first population can land before any ScrollBox Update the hooks see.
                    HookRows(_G.AchievementFrameCategories, SkinCategoryRow)
                    HookRows(_G.AchievementFrameAchievements, SkinAchRow)
                    HookRows(_G.AchievementFrameStats, SkinStatRow)
                    if _G.AchievementFrameSummary then
                        AchWhiteTextsIn(_G.AchievementFrameSummary)
                    end
                    SweepInsetChildren()
                    RetintHeaderPlate()
                    Skin.Restrip()
                    Skin.UpdateAllTabs()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "achievements",
        addons = { Blizzard_AchievementUI = true },
        apply = Skin_Achievements,
    })
end

-------------------------------------------------------------------------------
--  Mail (MailFrame + OpenMailFrame)
-------------------------------------------------------------------------------
-- Labeled prev/next page button (mail inbox, merchant): house page-arrow
-- block, box 4px smaller (13px arrow re-centers), 3px left plus any per-button
-- nudge, native "Prev"/"Next" label hidden. That label is a font-string REGION,
-- not the designated GetFontString, so every font string fades; size/shift is one-shot, label fade re-runs per pass.
local function SkinLabeledPageButton(btnFrame, childFrame, extraX)
    if not btnFrame then
        return
    end
    Skin.PageButton(btnFrame, childFrame, 13)
    local progressData = GetFFD(btnFrame)
    if not progressData.adjusted then
        progressData.adjusted = true
        local wid, hgt = btnFrame:GetSize()
        if wid and hgt and wid > 4 and hgt > 4 then
            btnFrame:SetSize(wid - 4, hgt - 4)
        end
        local pointCount = btnFrame:GetNumPoints() or 0
        local pts, success = {}, pointCount > 0
        for idx = 1, pointCount do
            local point, relTo, relPoint, posX, posY = btnFrame:GetPoint(idx)
            if not point then
                success = false
                break
            end
            pts[idx] = { point, relTo, relPoint, (posX or 0) - 3 + (extraX or 0), posY or 0 }
        end
        if success then
            btnFrame:ClearAllPoints()
            for idx = 1, #pts do
                local tbl = pts[idx]
                btnFrame:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
            end
        end
    end
    -- Per-pass: hide label font strings AND plain texture regions -- merchant
    -- buttons carry box art as anonymous regions PageButton's Normal/Pushed/
    -- Highlight fade never touches. Our arrow/fill/hover spared by identity.
    local regionList = { btnFrame:GetRegions() }
    for idx = 1, #regionList do
        local region = regionList[idx]
        if
            region
            and region ~= progressData.arrow
            and region ~= progressData.bg
            and region ~= progressData.hover
            and region.IsObjectType
            and (region:IsObjectType("FontString") or region:IsObjectType("Texture"))
        then
            region:SetAlpha(0)
        end
    end
end

-- `quality` opts the button into the SQUARE rarity border instead of the plain
-- black one. OPT-IN because this helper is shared: the merchant grid passes it,
-- MAIL deliberately does not. Mail rows have no other rarity cue and Blizzard's
-- rounded ring is the only one they get, so flipping it there is a visual
-- change nobody asked for -- it is a one-word change if that is ever wanted.
local function SkinMailItemButton(button, quality)
    if not button or button:IsForbidden() then
        return
    end
    local nt = button.GetNormalTexture and button:GetNormalTexture()
    if nt and nt.SetAlpha then
        nt:SetAlpha(0)
    end
    local bn = button.GetName and button:GetName()
    local slot = bn and _G[bn .. "Slot"]
    if slot and slot.SetAlpha then
        slot:SetAlpha(0)
    end
    -- IconBorder is the item-quality color ring. Left to Blizzard without
    -- `quality`; with it, the ROUNDED ring is stripped and its color is read
    -- back onto a square border, so the tile keeps the rarity and loses the
    -- round art. Alpha 0 does not hide it from the read -- WSkin.RingQuality
    -- goes by shown state and vertex color.
    local glyphTex = button.Icon or button.icon or (bn and _G[bn .. "IconTexture"])
    if quality then
        local ring = button.IconBorder or (bn and _G[bn .. "IconBorder"])
        if ring and ring.SetAlpha then
            ring:SetAlpha(0)
        end
    end
    if glyphTex then
        Skin.SquareIcon(glyphTex, button, quality)
    end
end

do
    -- Inbox row: parchment gone, flat block, white sender/subject, squared icon.
    local function SkinMailRow(row)
        if not row or row:IsForbidden() then
            return
        end
        local skinData = GetFFD(row)
        if not skinData.bg then
            Skin.FadeRegions(row)
            local bgTex = row:CreateTexture(nil, "BACKGROUND", nil, -7)
            bgTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
            bgTex:SetPoint("TOPLEFT", 2, -1)
            bgTex:SetPoint("BOTTOMRIGHT", -2, 3)
            skinData.bg = bgTex
            Skin.AddBorder(row)
        end
        local label = row.GetName and row:GetName()
        if label then
            -- Sender and subject show other players' writing: font families, which
            -- draw the scripts the house font lacks
            local sender = _G[label .. "Sender"]
            if sender then
                Skin.FontFamily(sender)
                Skin.White(sender)
            end
            -- Subject is the item name for item mail: font only, no forced white, so Blizzard's item-quality color shows.
            local subject = _G[label .. "Subject"]
            if subject then
                Skin.FontFamily(subject)
            end
        end
        if row.Button then
            SkinMailItemButton(row.Button)
        end
    end

    -- Auction-house invoices and crafting-order mail are their own panels (not the
    -- letter body), drawn in InvoiceTextFontNormal: a dark brown meant for the
    -- stationery parchment this pack fades. Re-font and whiten them.
    local INVOICE_TEXT = {
        "OpenMailInvoiceItemLabel",
        "OpenMailInvoicePurchaser",
        "OpenMailInvoiceSalePrice",
        "OpenMailInvoiceDeposit",
        "OpenMailInvoiceHouseCut",
        "OpenMailInvoiceAmountReceived",
        "OpenMailInvoiceNotYetSent",
        "OpenMailInvoiceMoneyDelay",
    }
    local CONSORTIUM_TEXT = {
        "OpeningText",
        "CrafterText",
        "CommissionReceived",
        "CrafterNote",
        "ConsortiumNote",
    }
    -- Only money frames declaring an inline +/-/count font string (amounts live on child frames, see SkinMoneyFrameText).
    local INVOICE_MONEY = {
        "OpenMailDepositMoneyFrame",
        "OpenMailHouseCutMoneyFrame",
        "OpenMailSalePriceMoneyFrame",
    }

    local function SkinInvoiceFS(fontStr)
        if not fontStr or (fontStr.IsForbidden and fontStr:IsForbidden()) then
            return
        end
        Skin.Font(fontStr)
        Skin.White(fontStr)
    end

    -- +/- signs and stack count are unnamed font strings parented straight to the
    -- money frames, so sweeping direct regions gets those and nothing else. Amounts
    -- live on Gold/Silver/CopperButton children driven by SetNormalFontObject,
    -- re-applied every update by SetMoneyFrameColor: they deliberately keep
    -- Blizzard's number font (SetFont here is clobbered) and the house-cut/commission red.
    local function SkinMoneyFrameText(mf)
        if not mf or mf:IsForbidden() then
            return
        end
        local regionList = { mf:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region.IsObjectType and region:IsObjectType("FontString") then
                SkinInvoiceFS(region)
            end
        end
    end

    -- The invoice arithmetic rule is parchment art (thin line in a mostly
    -- transparent 256x32 box) and AMOUNT_RECEIVED anchors to that box. It cannot
    -- be recolored (a multiply keeps the orange) nor turned into a color texture
    -- (the box fills and resizing drags the anchor). Fade the art, keep the box as an invisible spacer, run our own rule through it.
    local function SkinArithmeticLine()
        local art = _G.OpenMailArithmeticLine
        if not art or art:IsForbidden() then
            return
        end
        art:SetAlpha(0)
        local skinData = GetFFD(art)
        if skinData.rule then
            return
        end
        local parent = art:GetParent()
        if not parent then
            return
        end
        skinData.rule = SolidTex(parent, "OVERLAY", Theme.brdR, Theme.brdG, Theme.brdB, Theme.brdA)
        skinData.rule:SetHeight(1)
        skinData.rule:SetPoint("LEFT", art, "LEFT", 0, 0)
        skinData.rule:SetPoint("RIGHT", art, "RIGHT", 0, 0)
    end

    local function SkinInvoiceText()
        for _, n in ipairs(INVOICE_TEXT) do
            SkinInvoiceFS(_G[n])
        end
        for _, n in ipairs(INVOICE_MONEY) do
            SkinMoneyFrameText(_G[n])
        end
        SkinArithmeticLine()
        local cm = _G.ConsortiumMailFrame
        if not cm or cm:IsForbidden() then
            return
        end
        for _, keyName in ipairs(CONSORTIUM_TEXT) do
            SkinInvoiceFS(cm[keyName])
        end
        local paid = cm.CommissionPaidDisplay
        if paid then
            SkinInvoiceFS(paid.CommissionPaidText)
            SkinMoneyFrameText(paid.MoneyDisplayFrame)
            -- Plain 1px color texture, so it themes in place like the rule above.
            if paid.Separator then
                paid.Separator:SetColorTexture(Theme.brdR, Theme.brdG, Theme.brdB, Theme.brdA)
            end
        end
    end

    -- Letter body: force readable white + skin font on the SimpleHTML elements. The
    -- body is another player's writing, so the font is a family (no shadow, as
    -- Blizzard's own mail font): the skin font draws what it has, the client's own
    -- faces the scripts it lacks. The colour goes on after the font.
    local function WhitenMailText()
        local html = _G.OpenMailBodyText
        if html and html.SetTextColor then
            local fp = Theme.fontPath
            local ff = Theme.fontFlag or ""
            for _, part in ipairs({ "P", "H1", "H2", "H3" }) do
                if fp and html.GetFont then
                    local success, _, sz = pcall(html.GetFont, html, part)
                    if success and not issecretvalue(sz) and type(sz) == "number" then
                        local fam = html.SetFontObject and CludesUI.GetFontFamily(fp, sz, ff, false)
                        if not (fam and pcall(html.SetFontObject, html, part, fam)) then
                            pcall(html.SetFont, html, part, fp, sz, ff)
                        end
                    end
                end
                pcall(html.SetTextColor, html, part, 1, 1, 1)
            end
        end
        -- The letter's subject and sender: font families (other players' writing)
        if _G.OpenMailSubject then
            Skin.FontFamily(_G.OpenMailSubject)
            Skin.White(_G.OpenMailSubject)
        end
        local sender = _G.OpenMailSender
        if sender and sender.Name then
            Skin.FontFamily(sender.Name)
            Skin.White(sender.Name)
        end
        SkinInvoiceText()
    end

    local function Skin_OpenMail()
        local win = _G.OpenMailFrame
        if not win then
            return
        end
        Skin.Shell("mail", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "OpenMailFrame")
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if _G.OpenMailFrameBg then
            _G.OpenMailFrameBg:SetAlpha(0)
        end
        if win.Inset then
            Skin.Inset(win.Inset)
        end
        Skin.FadeKeyedArt(win)
        for _, n in ipairs({
            "OpenStationeryBackgroundLeft",
            "OpenStationeryBackgroundRight",
            "OpenMailHorizontalBarLeft",
        }) do
            local part = _G[n]
            if part and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        for _, n in ipairs({
            "OpenMailReplyButton",
            "OpenMailDeleteButton",
            "OpenMailCancelButton",
            "OpenMailReportSpamButton",
        }) do
            local button = _G[n]
            if button then
                Skin.Button(button)
            end
        end
        SkinMailItemButton(_G.OpenMailLetterButton)
        SkinMailItemButton(_G.OpenMailMoneyButton)
        for idx = 1, 16 do
            SkinMailItemButton(_G["OpenMailAttachmentButton" .. idx])
        end
        WhitenMailText()
    end

    local _mailHook = false
    local function Skin_Mail()
        local win = _G.MailFrame
        if not win then
            return
        end
        Skin.Shell("mail", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "MailFrame")
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if _G.MailFrameBg then
            _G.MailFrameBg:SetAlpha(0)
        end
        if win.Inset then
            Skin.Inset(win.Inset)
        end

        -- Inbox
        if _G.InboxFrameBg then
            _G.InboxFrameBg:SetAlpha(0)
        end
        for idx = 1, 7 do
            SkinMailRow(_G["MailItem" .. idx])
        end
        -- MailItem1 is the chain root (2-7 anchor below it): lifting it lifts the whole inbox list. One-shot.
        local m1 = _G.MailItem1
        if m1 and not GetFFD(m1).raised then
            local pointCount = m1:GetNumPoints() or 0
            local pts, success = {}, pointCount > 0
            for idx = 1, pointCount do
                local point, relTo, relPoint, posX, posY = m1:GetPoint(idx)
                if not point then
                    success = false
                    break
                end
                pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + 20 }
            end
            if success then
                GetFFD(m1).raised = true
                m1:ClearAllPoints()
                for idx = 1, #pts do
                    local tbl = pts[idx]
                    m1:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                end
            end
        end
        if _G.OpenAllMail then
            Skin.Button(_G.OpenAllMail)
            Skin.WhiteButtonLabel(_G.OpenAllMail)
        end
        SkinLabeledPageButton(_G.InboxPrevPageButton, "<")
        SkinLabeledPageButton(_G.InboxNextPageButton, ">", 2) -- right arrow 2px back to the right
        if _G.InboxCurrentPage then
            Skin.Font(_G.InboxCurrentPage)
            Skin.White(_G.InboxCurrentPage)
        end

        -- Send Mail
        if _G.SendMailNameEditBox then
            Skin.EditBox(_G.SendMailNameEditBox)
        end
        if _G.SendMailSubjectEditBox then
            Skin.EditBox(_G.SendMailSubjectEditBox)
        end
        if _G.SendMailFrame then
            Skin.FadeRegions(_G.SendMailFrame)
            Skin.Register(_G.SendMailFrame, true)
        end
        if _G.SendMailMoneyInset then
            Skin.Inset(_G.SendMailMoneyInset)
        end
        if _G.SendMailMoneyBg then
            Skin.FadeRegions(_G.SendMailMoneyBg)
            Skin.Register(_G.SendMailMoneyBg, true)
        end
        if _G.SendMailMailButton then
            Skin.Button(_G.SendMailMailButton)
        end
        if _G.SendMailCancelButton then
            Skin.Button(_G.SendMailCancelButton)
        end
        for idx = 1, 16 do
            local a = _G["SendMailAttachment" .. idx]
            if a and not GetFFD(a).sock then
                local skinData = GetFFD(a)
                skinData.sock = true
                local nt = a.GetNormalTexture and a:GetNormalTexture()

                -- SendMailAttachment carries a static placeholder texture plus a
                -- dynamic icon texture Blizzard creates/updates on item placement.
                -- Fade everything up front so the placeholder cannot clip through;
                -- the hook below re-shows the real icon when an item is dropped in.
                Skin.FadeRegions(a)
                if nt and nt.SetAlpha then
                    nt:SetAlpha(0)
                end
                if a.IconBorder then
                    a.IconBorder:SetAlpha(0)
                end

                local bgTex = a:CreateTexture(nil, "BACKGROUND", nil, -8)
                bgTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
                bgTex:SetAllPoints(a)
                skinData.bg = bgTex
                Skin.AddBorder(a)

                -- A slot already holding an item on show (reopened mailbox) has its
                -- icon at ARTWORK/OVERLAY with a real texture: re-show it here, since
                -- the hook below only fires on later SetItemButtonTexture calls.
                local countFS = a.Count or (a.GetName and _G[a:GetName() .. "Count"])
                local countText = countFS and countFS.GetText and countFS:GetText()
                if countText and countText ~= "" and countText ~= "0" then
                    local regionList = { a:GetRegions() }
                    for jdx = 1, #regionList do
                        local region = regionList[jdx]
                        if region and region:IsObjectType("Texture") and region.GetDrawLayer and region.GetTexture then
                            local layer = ({ region:GetDrawLayer() })[1]
                            if (layer == "ARTWORK" or layer == "OVERLAY") and region:GetTexture() then
                                region:SetAlpha(1)
                                region:Show()
                                if region.SetTexCoord then
                                    region:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                end
                            end
                        end
                    end
                end

                -- On SetItemButtonTexture: show only the region that received the
                -- item texture; on clear, hide all icon textures.
                if a.SetItemButtonTexture and not skinData.texHook then
                    skinData.texHook = true
                    hooksecurefunc(a, "SetItemButtonTexture", function(self, texture)
                        -- Our themed bg is a direct region: sweeps below must never
                        -- fade it, or the slot loses its backdrop on set/clear.
                        if not texture then
                            local regionList = { self:GetRegions() }
                            for jdx = 1, #regionList do
                                local region = regionList[jdx]
                                if region and region ~= skinData.bg and region:IsObjectType("Texture") then
                                    region:SetAlpha(0)
                                end
                            end
                            return
                        end
                        local regionList = { self:GetRegions() }
                        for jdx = 1, #regionList do
                            local region = regionList[jdx]
                            if region and region ~= skinData.bg and region:IsObjectType("Texture") then
                                local match = (region.GetTexture and region:GetTexture() == texture)
                                    or (region.GetAtlas and region:GetAtlas() == texture)
                                if match then
                                    region:SetAlpha(1)
                                    region:Show()
                                    if region.SetTexCoord then
                                        region:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                    end
                                else
                                    region:SetAlpha(0)
                                end
                            end
                        end
                    end)
                end
            end
        end

        local mailTabs = {}
        for idx = 1, 2 do
            local tabBtn = _G["MailFrameTab" .. idx]
            if tabBtn then
                Skin.Tab(tabBtn)
                mailTabs[#mailTabs + 1] = tabBtn
            end
        end
        Skin.NormalizeTabRow(mailTabs)
        Skin.ScrollBarsIn(win)

        if not _mailHook then
            _mailHook = true
            if type(_G.InboxFrame_Update) == "function" then
                hooksecurefunc(
                    "InboxFrame_Update",
                    Skin.Debounce(function()
                        if win:IsVisible() then
                            for idx = 1, 7 do
                                SkinMailRow(_G["MailItem" .. idx])
                            end
                            Skin.Restrip()
                        end
                    end)
                )
            end
            if type(_G.OpenMail_Update) == "function" then
                hooksecurefunc(
                    "OpenMail_Update",
                    Skin.Debounce(function()
                        SkinMailItemButton(_G.OpenMailLetterButton)
                        for idx = 1, 16 do
                            SkinMailItemButton(_G["OpenMailAttachmentButton" .. idx])
                        end
                        WhitenMailText()
                    end)
                )
            end
        end

        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    for idx = 1, 7 do
                        SkinMailRow(_G["MailItem" .. idx])
                    end
                    Skin.Restrip()
                    Skin.UpdateAllTabs()
                end
            end)
        )
        Skin_OpenMail()
    end

    Skin.RegisterWindow({
        key = "mail",
        addons = { Blizzard_MailFrame = true },
        apply = Skin_Mail,
    })
end

-------------------------------------------------------------------------------
--  Catalyst / Item Interaction (ItemInteractionFrame)
--  Chrome only: the input slot's green "+" is its NormalAtlas, so the item
--  slots stay stock.
-------------------------------------------------------------------------------
do
    local function Skin_Catalyst()
        local win = _G.ItemInteractionFrame
        if not win then
            return
        end
        Skin.Shell("catalyst", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "ItemInteractionFrame")
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if win.Bg and win.Bg.SetAlpha then
            win.Bg:SetAlpha(0)
        end
        if _G.ItemInteractionFrameBg then
            _G.ItemInteractionFrameBg:SetAlpha(0)
        end
        if win.Inset then
            Skin.Inset(win.Inset)
        end
        if win.Background and win.Background.SetAlpha then
            win.Background:SetAlpha(0)
        end
        if win.Description then
            Skin.White(win.Description)
        end

        local subFrame = win.ButtonFrame
        if subFrame then
            for _, keyName in ipairs({ "BlackBorder", "ButtonBorder", "ButtonBottomBorder" }) do
                local part = subFrame[keyName]
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
            if subFrame.ActionButton then
                Skin.Button(subFrame.ActionButton)
            end
            if subFrame.MoneyFrameEdge then
                Skin.FadeRegions(subFrame.MoneyFrameEdge)
                Skin.Register(subFrame.MoneyFrameEdge, true)
            end
        end
        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    Skin.Restrip()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "catalyst",
        addons = { Blizzard_ItemInteractionUI = true },
        apply = Skin_Catalyst,
    })
end

-------------------------------------------------------------------------------
--  Gem Socketing (ItemSocketingFrame)
-------------------------------------------------------------------------------
do
    local function SkinSocket(btnFrame)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(btnFrame)
        -- Lock detection every pass: lock state changes per inspected item; LOCKED sockets keep ALL Blizzard art (closed ring + padlock).
        local isLocked = false
        local regionList = { btnFrame:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                local hay = Skin.TexHay(region)
                if hay and hay:find("lock", 1, true) then
                    isLocked = true
                    break
                end
            end
        end
        local kids = {}
        local children = { btnFrame:GetChildren() }
        for idx = 1, #children do
            local child = children[idx]
            if child and child.SetAlpha then
                kids[#kids + 1] = child
                if not isLocked and child.GetRegions then
                    local regions2 = { child:GetRegions() }
                    for jdx = 1, #regions2 do
                        local r2 = regions2[jdx]
                        if r2 and r2.IsObjectType and r2:IsObjectType("Texture") then
                            local hay2 = Skin.TexHay(r2)
                            if hay2 and hay2:find("lock", 1, true) then
                                isLocked = true
                                break
                            end
                        end
                    end
                end
            end
        end
        local nt = btnFrame.GetNormalTexture and btnFrame:GetNormalTexture()
        if isLocked then
            -- Un-stripped: the whole locked presentation stays Blizzard's.
            local regions2 = { btnFrame:GetRegions() }
            for idx = 1, #regions2 do
                local region = regions2[idx]
                if region and region.IsObjectType and region:IsObjectType("Texture") then
                    region:SetAlpha(1)
                end
            end
            for _, c in ipairs(kids) do
                c:SetAlpha(1)
            end
            if nt and nt.SetAlpha then
                nt:SetAlpha(1)
            end
        else
            -- Blizzard's socket presentation stays whole (icon/ring/border/bracket
            -- art); only decorative spark/shine CHILDREN dim, replaced by the house
            -- glow. Spared: the bracket frame and any child with a fileID-backed
            -- texture (the gem holder -- decor art is atlas/path-based).
            for _, c in ipairs(kids) do
                local spare = (c == btnFrame.BracketFrame)
                if not spare and c.GetRegions then
                    local regions2 = { c:GetRegions() }
                    for jdx = 1, #regions2 do
                        local r2 = regions2[jdx]
                        if r2 and r2.IsObjectType and r2:IsObjectType("Texture") and not Skin.TexHay(r2) then
                            local tx = r2.GetTexture and r2:GetTexture()
                            if type(tx) == "number" then
                                spare = true
                                break
                            end
                        end
                    end
                end
                c:SetAlpha(spare and 1 or 0)
            end
        end
        -- Side filigree flourishes stay off in every state; multi-piece and partly anonymous, so sweep by geometry too.
        for _, keyName in ipairs({ "LeftFiligree", "RightFiligree" }) do
            local part = btnFrame[keyName]
            if part and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        -- Flourishes are the only regions overhanging the button's sides, so
        -- anything protruding past the edges fades (rects only exist while shown; update-pass re-runs catch it).
        local bl, br2 = btnFrame:GetLeft(), btnFrame:GetRight()
        if bl and br2 then
            local regions2 = { btnFrame:GetRegions() }
            for idx = 1, #regions2 do
                local region = regions2[idx]
                if region and region.IsObjectType and region:IsObjectType("Texture") then
                    local rl, rr = region:GetLeft(), region:GetRight()
                    if rl and rr and (rl < bl - 6 or rr > br2 + 6) then
                        region:SetAlpha(0)
                    end
                end
            end
        end
        if skinData.sock then
            return
        end
        skinData.sock = true
        -- House Modern WoW glow (gold) on our own wrapper frame.
        if CludesUI.Glows and CludesUI.Glows.StartGlow then
            local gw = CreateFrame("Frame", nil, btnFrame)
            local w2, h2 = btnFrame:GetSize()
            if not w2 or w2 == 0 then
                w2, h2 = 36, 36
            end
            gw:SetSize(w2, h2)
            gw:SetPoint("CENTER")
            CludesUI.Glows.StartGlow(gw, 6, w2, 1, 0.91, 0.5, nil, h2)
            skinData.glow = gw
        end
    end

    local function Skin_Socket()
        local win = _G.ItemSocketingFrame
        if not win then
            return
        end
        Skin.Shell("socket", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "ItemSocketingFrame")
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if _G.ItemSocketingFrameBg then
            _G.ItemSocketingFrameBg:SetAlpha(0)
        end
        if win.Inset then
            Skin.Inset(win.Inset)
        end
        Skin.FadeKeyedArt(win)
        Skin.FadeArtIn(win)
        -- Tighter window: 40 narrower, 80 shorter than stock (one-shot).
        local fd5 = GetFFD(win)
        if not fd5.hCut then
            local ww, hh = win:GetSize()
            if ww and hh and hh > 140 and ww > 100 then
                fd5.hCut = true
                win:SetSize(ww - 40, hh - 80)
            end
        end
        -- Owned layout: a FIXED scrollable tooltip viewport between the title bar
        -- and a gem section at the bottom. Tooltip text keeps its native scroll-
        -- child anchors; only the scrollframe and gem container are positioned
        -- (absolute anchors, idempotent per update pass).
        local function LayoutSocketing()
            local sf2 = _G.ItemSocketingScrollFrame or win.ScrollFrame
            local c = win.SocketingContainer
            if sf2 then
                sf2:ClearAllPoints()
                sf2:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -32)
                sf2:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -32, 100)
            end
            if c then
                c:ClearAllPoints()
                c:SetPoint("BOTTOM", win, "BOTTOM", 0, 40)
            end
            -- Blizzard re-anchors only Socket1 each update; Socket2/3 chain off it,
            -- so pin Socket1 alone (pinning the others latches stale offsets).
            local fcx = win:GetCenter()
            local s1 = c and c.Socket1
            if fcx and s1 and s1:IsShown() then
                local scx = s1:GetCenter()
                if scx then
                    s1:ClearAllPoints()
                    s1:SetPoint("BOTTOM", win, "BOTTOM", scx - fcx, 40)
                end
            end
            -- Old-style scrollbar -> slim house strip (arrow buttons dark),
            -- seated 15px right of Blizzard's spot.
            local socketScrollBar = _G.ItemSocketingScrollFrameScrollBar or (sf2 and sf2.ScrollBar)
            if socketScrollBar and not GetFFD(socketScrollBar).slim then
                GetFFD(socketScrollBar).slim = true
                local numPts = socketScrollBar:GetNumPoints()
                if numPts and numPts > 0 then
                    local pts, success = {}, true
                    for idx = 1, numPts do
                        local point, relTo, relPoint, posX, posY = socketScrollBar:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, (posX or 0) + 15, posY or 0 }
                    end
                    if success then
                        socketScrollBar:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            socketScrollBar:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                end
                local sbrName = socketScrollBar.GetName and socketScrollBar:GetName() or ""
                for _, button in ipairs({
                    socketScrollBar.ScrollUpButton or _G[sbrName .. "ScrollUpButton"],
                    socketScrollBar.ScrollDownButton or _G[sbrName .. "ScrollDownButton"],
                }) do
                    if button then
                        for _, g in ipairs({
                            "GetNormalTexture",
                            "GetPushedTexture",
                            "GetDisabledTexture",
                            "GetHighlightTexture",
                        }) do
                            local part = button[g] and button[g](button)
                            if part and part.SetAlpha then
                                part:SetAlpha(0)
                            end
                        end
                    end
                end
                local thumb = socketScrollBar.GetThumbTexture and socketScrollBar:GetThumbTexture()
                if thumb then
                    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
                    thumb:SetVertexColor(1, 1, 1, 0.3)
                    thumb:SetWidth(4)
                end
            end
        end
        -- Skin every realized socket (art only; layout is separate).
        local function SkinSocketsArt()
            local c = win.SocketingContainer
            if not c then
                return
            end
            for _, keyName in ipairs({ "Socket1", "Socket2", "Socket3" }) do
                SkinSocket(c[keyName])
            end
            if c.SocketFrames then
                for _, sock in ipairs(c.SocketFrames) do
                    SkinSocket(sock)
                end
            end
            if c.ApplySocketsButton then
                Skin.Button(c.ApplySocketsButton)
            end
        end
        -- Full pass: reposition + reskin + restrip. Idempotent, safe to repeat.
        local function FullPass()
            if not win:IsVisible() then
                return
            end
            LayoutSocketing()
            SkinSocketsArt()
            Skin.Restrip()
        end

        LayoutSocketing()
        SkinSocketsArt()
        Skin.ScrollBarsIn(win)

        -- Blizzard repaints sockets on every item change. LAYOUT must run
        -- SYNCHRONOUSLY: Blizzard re-anchors sockets inside the update, so a
        -- debounced reposition renders a frame at Blizzard's spot then snaps (the
        -- gem-click bounce). The debounced FullPass ALSO re-layouts, covering the
        -- FIRST open where sockets are not laid out for the sync pass.
        if type(_G.ItemSocketingFrame_Update) == "function" and not GetFFD(win).updHook then
            GetFFD(win).updHook = true
            local deferred = Skin.Debounce(FullPass)
            hooksecurefunc("ItemSocketingFrame_Update", function()
                if not win:IsVisible() then
                    return
                end
                LayoutSocketing()
                deferred()
            end)
        end

        -- On (re)show, run the full pass now AND once sockets have realized: first
        -- open loads this LoD addon with the frame already showing, unbuilt.
        Skin.HookShow(
            win,
            Skin.Debounce(function()
                FullPass()
                if C_Timer then
                    C_Timer.After(0, FullPass)
                    C_Timer.After(0.1, FullPass)
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "socket",
        addons = { Blizzard_ItemSocketingUI = true },
        apply = Skin_Socket,
    })
end

-------------------------------------------------------------------------------
--  Reputation & Currency tabs (CharacterFrame sub-panes). Rides the charsheet
--  style key but touches ONLY content inside ReputationFrame/TokenFrame (page
--  chrome/backdrops belong to CharacterSheet). Taint: currency transfer log
--  toggle never restyled (breaks transfers); scrollbar work is texture-only.
-------------------------------------------------------------------------------
do
    local function RCWhiteTextsIn(owner)
        if not owner or not owner.GetRegions then
            return
        end
        local regionList = { owner:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region.IsObjectType and region:IsObjectType("FontString") then
                Skin.Font(region)
                Skin.White(region)
            end
        end
    end

    -- Collapse state comes from the row's element data; painted atlas names differ
    -- between rep/token lists and nesting levels, so they are only a fallback.
    local function RCCollapsedIn(tbl)
        if type(tbl) ~= "table" then
            return nil
        end
        if tbl.isCollapsed ~= nil then
            return tbl.isCollapsed and true or false
        end
        if tbl.isHeaderExpanded ~= nil then
            return (not tbl.isHeaderExpanded) and true or false
        end
        return nil
    end

    local function RCRowCollapsed(row)
        if not row.GetElementData then
            return nil
        end
        local success, dt = pcall(row.GetElementData, row)
        if not success or type(dt) ~= "table" then
            return nil
        end
        local c = RCCollapsedIn(dt)
        if c == nil then
            c = RCCollapsedIn(dt.factionData)
        end
        if c == nil then
            c = RCCollapsedIn(dt.data)
        end
        return c
    end

    local RC_STRIP_KEYS = { "Left", "Middle", "HighlightLeft", "HighlightMiddle", "HighlightRight" }
    local function SkinRCRow(childFrame, isCurrency)
        if not childFrame or childFrame:IsForbidden() then
            return
        end
        -- Currency (TokenFrame) rows stay 100% STOCK. ANY skinning, even the
        -- band-strip fade, taints warband currency transfer (forbidding the
        -- protected RequestCurrencyFromAccountCharacter) and blanks currency
        -- column headers. Reputation rows are fine.
        if isCurrency then
            return
        end
        local skinData = GetFFD(childFrame)
        -- Per-pass: pooled rows get re-initialized by Blizzard, so header band fades must re-assert on every list update.
        for _, keyName in ipairs(RC_STRIP_KEYS) do
            local part = childFrame[keyName]
            if part and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        -- Header +/- toggle: strip Blizzard's paint, drive the spellbook max/min
        -- glyph off the state it painted; per pass so the strip survives pooled-row repaints.
        local tcb = childFrame.ToggleCollapseButton
        if tcb then
            local buttonData = GetFFD(tcb)
            if not buttonData.glyph then
                local glyphTex = tcb:CreateTexture(nil, "OVERLAY")
                glyphTex:SetSize(16, 16)
                glyphTex:SetPoint("CENTER", tcb, "CENTER", 0, 0)
                buttonData.glyph = glyphTex
                -- Stock button is a tiny click target: pad the hit rect.
                tcb:SetHitRectInsets(-6, -6, -6, -6)
                local function classify(a)
                    if type(a) ~= "string" then
                        return nil
                    end
                    a = a:lower()
                    if a:find("expanded", 1, true) then
                        return true
                    end
                    if a:find("minus", 1, true) or a:find("collapse", 1, true) then
                        return true
                    end
                    if a:find("plus", 1, true) or a:find("expand", 1, true) then
                        return false
                    end
                    return nil
                end
                local function repaint()
                    local expanded
                    local collapsed = RCRowCollapsed(childFrame)
                    if collapsed ~= nil then
                        expanded = not collapsed
                    end
                    for _, g in ipairs({
                        "GetNormalTexture",
                        "GetPushedTexture",
                        "GetHighlightTexture",
                        "GetDisabledTexture",
                    }) do
                        local part = tcb[g] and tcb[g](tcb)
                        if part then
                            if expanded == nil and part.GetAtlas then
                                expanded = classify(part:GetAtlas())
                            end
                            part:SetAlpha(0)
                        end
                    end
                    local regionList = { tcb:GetRegions() }
                    for idx = 1, #regionList do
                        local region = regionList[idx]
                        if region and region ~= glyphTex and region.IsObjectType and region:IsObjectType("Texture") then
                            if expanded == nil and region.GetAtlas then
                                expanded = classify(region:GetAtlas())
                            end
                            region:SetAlpha(0)
                        end
                    end
                    if expanded == nil then
                        expanded = true
                    end
                    glyphTex:SetAtlas(
                        expanded and "UI-QuestTrackerButton-Secondary-Collapse"
                            or "UI-QuestTrackerButton-Secondary-Expand",
                        false
                    )
                    glyphTex:SetDesaturated(true)
                    glyphTex:SetVertexColor(1, 1, 1, tcb:IsMouseOver() and 1 or 0.75)
                end
                buttonData.repaint = repaint
                if tcb.RefreshIcon then
                    hooksecurefunc(tcb, "RefreshIcon", repaint)
                end
                tcb:HookScript("OnClick", repaint)
                tcb:HookScript("OnEnter", function()
                    glyphTex:SetVertexColor(1, 1, 1, 1)
                end)
                tcb:HookScript("OnLeave", function()
                    glyphTex:SetVertexColor(1, 1, 1, 0.75)
                end)
                repaint()
            else
                buttonData.repaint()
            end
        end
        -- Rep-style header rows carry the boxed +/- directly in the Right texture
        -- slot (Options_ListExpand atlases): hide that art and drive the spellbook
        -- max/min glyph in its place (rows with a ToggleCollapseButton get theirs
        -- from the handler above). Per pass, since collapse toggles rebuild rows
        -- without always re-setting the atlas.
        local chev = childFrame.Right
        if chev and chev.GetAtlas then
            local cd = GetFFD(chev)
            if not cd.styleRight then
                cd.styleRight = function()
                    local a = chev:GetAtlas()
                    local isExpandArt = a == "Options_ListExpand_Right"
                        or a == "Options_ListExpand_Right_Expanded"
                    chev:SetAlpha(0)
                    if not isExpandArt or childFrame.ToggleCollapseButton then
                        if cd.glyph then
                            cd.glyph:Hide()
                        end
                        return
                    end
                    local g = cd.glyph
                    if not g then
                        g = childFrame:CreateTexture(nil, "OVERLAY")
                        g:SetSize(16, 16)
                        g:SetPoint("CENTER", chev, "CENTER", 0, 0)
                        cd.glyph = g
                    end
                    local collapsed = RCRowCollapsed(childFrame)
                    if collapsed == nil then
                        collapsed = a == "Options_ListExpand_Right"
                    end
                    g:SetAtlas(
                        collapsed and "UI-QuestTrackerButton-Secondary-Expand"
                            or "UI-QuestTrackerButton-Secondary-Collapse",
                        false
                    )
                    g:SetDesaturated(true)
                    g:SetVertexColor(1, 1, 1, 0.75)
                    g:Show()
                end
                hooksecurefunc(chev, "SetAtlas", cd.styleRight)
            end
            cd.styleRight()
        end
        if skinData.rcSkinned then
            return
        end
        skinData.rcSkinned = true
        -- Header rows (those carrying the band art) get a subtle house plate and a
        -- white hover in place of the faded highlight band.
        if childFrame.Middle and not skinData.plate then
            local backing = SolidTex(childFrame, "BACKGROUND", 1, 1, 1, 0.05)
            backing:SetAllPoints(childFrame)
            skinData.plate = backing
            local hoverTex = SolidTex(childFrame, "HIGHLIGHT", 1, 1, 1, 0.05)
            hoverTex:SetAllPoints(childFrame)
            skinData.hover = hoverTex
        end
        RCWhiteTextsIn(childFrame)
        local contentFrame = childFrame.Content
        if contentFrame then
            RCWhiteTextsIn(contentFrame)
            local glyphTex = contentFrame.CurrencyIcon
            if glyphTex then
                Skin.SquareIcon(glyphTex)
            end
            local rb = contentFrame.ReputationBar
            if rb and rb.GetStatusBarTexture then
                local keepSet = {}
                local fillTex = rb:GetStatusBarTexture()
                if fillTex then
                    keepSet[fillTex] = true
                end
                Skin.FadeRegions(rb, keepSet)
                rb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                local regionData = GetFFD(rb)
                if not regionData.bg then
                    local troughTex = rb:CreateTexture(nil, "BACKGROUND", nil, -1)
                    troughTex:SetColorTexture(0.12, 0.12, 0.12, 0.85)
                    troughTex:SetAllPoints(rb)
                    regionData.bg = troughTex
                    Skin.AddBorder(rb)
                end
                RCWhiteTextsIn(rb)
            end
        end
    end

    local function HookRCScrollBox(tabBox, isCurrency)
        if not tabBox or not tabBox.ForEachFrame then
            return
        end
        local skin = function(row)
            SkinRCRow(row, isCurrency)
        end
        pcall(tabBox.ForEachFrame, tabBox, skin)
        local skinData = GetFFD(tabBox)
        if tabBox.Update and not skinData.rowHook then
            skinData.rowHook = true
            hooksecurefunc(tabBox, "Update", function(button)
                pcall(button.ForEachFrame, button, skin)
            end)
        end
    end

    local function Skin_RepCurrency()
        -- The character sheet's Blizz Default keeps Blizzard's whole sheet,
        -- these tabs included.
        if mod.CharSheetStock and mod.CharSheetStock() then
            return
        end
        local rep = _G.ReputationFrame
        -- WoW Forever keeps the list, its filter and the detail pane Blizzard's on
        -- the sheet's backdrop, like that client's other character tabs (Skills,
        -- PvP, Currency); only the list's scroll bar takes the house style, as
        -- the Currency and stats lists' do.
        if rep and CludesUI.IS_FOREVER then
            if rep.ScrollBar then
                Skin.ScrollBar(rep.ScrollBar)
            end
        elseif rep then
            if rep.filterDropdown then
                Skin.Dropdown(rep.filterDropdown)
            end
            Skin.ScrollBarsIn(rep)
            HookRCScrollBox(rep.ScrollBox)
            local repDetail = rep.ReputationDetailFrame
            if repDetail then
                SkinGuildPopup(repDetail)
                for _, keyName in ipairs({
                    "AtWarCheckbox",
                    "MakeInactiveCheckbox",
                    "WatchFactionCheckbox",
                }) do
                    if repDetail[keyName] then
                        SkinGuildCheck(repDetail[keyName])
                    end
                end
                if repDetail.ViewRenownButton then
                    Skin.Button(repDetail.ViewRenownButton)
                end
                if repDetail.ScrollingDescriptionScrollBar then
                    Skin.ScrollBar(repDetail.ScrollingDescriptionScrollBar)
                end
            end
        end

        local tok = _G.TokenFrame
        if tok then
            if tok.filterDropdown then
                Skin.Dropdown(tok.filterDropdown)
            end
            Skin.ScrollBarsIn(tok)
            HookRCScrollBox(tok.ScrollBox, true) -- currency rows: band-fade only, no collapse/content skin (taints transfer)
            -- NOTHING IN THE CURRENCY-TRANSFER PATH GETS SKINNED: not the entry
            -- buttons (tok.CurrencyTransferLogToggleButton, pop.CurrencyTransferToggleButton),
            -- not the CurrencyTransferMenu window. Any write taints the protected
            -- RequestCurrencyFromAccountCharacter() -> ADDON_ACTION_FORBIDDEN for
            -- warband transfers. READ BEFORE RE-SKINNING: the failure hides itself
            -- (first transfer of a session succeeds, only later ones are forbidden,
            -- so testing once proves nothing). A no-write external-shell menu would
            -- work but needs a per-frame driver for one dialog -- not worth it. Leave stock.
            local pop = _G.TokenFramePopup
            if pop then
                -- Currency Options popup. Deliberately NOT SkinGuildPopup: that flat
                -- 0.05 slab reads as a dead grey box next to the character panel.
                -- The style-aware shell on the CHARSHEET key follows the panel's own
                -- setting (atlas+black overlay on "cui", flat user color on
                -- "modern") and swaps live. noTopBar keeps the backdrop/atlas frame
                -- but drops the 25px title strip, a hard bar across something this small.
                Skin.Shell("charsheet", pop, { noTopBar = true })
                if pop.NineSlice then
                    Skin.FadeNineSlice(pop.NineSlice)
                end
                -- Chrome in child FRAMES ("BG"/"Border" wrappers), invisible to the shell's own region fade.
                for _, keyName in ipairs({ "BG", "Border" }) do
                    local piece = pop[keyName]
                    if piece then
                        if piece.IsObjectType and piece:IsObjectType("Texture") then
                            piece:SetAlpha(0)
                        else
                            Skin.FadeRegions(piece)
                            if piece.NineSlice then
                                Skin.FadeNineSlice(piece.NineSlice)
                            end
                            Skin.Register(piece, true)
                        end
                    end
                end
                local regionList = { pop:GetRegions() }
                for idx = 1, #regionList do
                    local region = regionList[idx]
                    if region and region.IsObjectType and region:IsObjectType("FontString") then
                        Skin.Font(region)
                        Skin.White(region)
                    end
                end
                if pop.CloseButton then
                    Skin.CloseButton(pop.CloseButton)
                end
                local pcb = pop["$parent.CloseButton"]
                if pcb then
                    Skin.CloseButton(pcb)
                end
                -- "Unused"/"Show on Backpack": plain square treatment KEEPING
                -- Blizzard's checkmark art, as the calendar lock-event check does --
                -- NOT SkinGuildCheck, which replaces it with a solid block.
                -- borderInset 4 hugs the visible box (frame is larger than its check graphic).
                for _, keyName in ipairs({ "InactiveCheckbox", "BackpackCheckbox" }) do
                    if pop[keyName] then
                        Skin.Checkbox(pop[keyName], { borderInset = 4 })
                    end
                end
                -- pop.CurrencyTransferToggleButton stays 100% stock (see the
                -- transfer-path note above). The popup around it is skinned.
            end
        end
    end

    Skin.RegisterWindow({
        key = "charsheet",
        apply = Skin_RepCurrency,
    })
    -- Second pass for clients where TokenFrame/TokenFramePopup arrive with the
    -- load-on-demand Blizzard_TokenUI rather than at login. Idempotent.
    Skin.RegisterWindow({
        key = "charsheet",
        addons = { Blizzard_TokenUI = true },
        apply = Skin_RepCurrency,
    })
end

-------------------------------------------------------------------------------
--  Housing Dashboard. Chrome only by request: shell backdrop/border, top bar,
--  title, close button. Dashboard CONTENT (house info, catalog, initiatives) stays 100% stock.
-------------------------------------------------------------------------------
do
    local function Skin_Housing()
        local win = _G.HousingDashboardFrame
        if not win then
            return
        end
        Skin.Shell("housing", win)
        Skin.RemovePortrait(win)
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or win.TitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end
        local creatureBtn = win.CloseButton or (win.GetName and _G[(win:GetName() or "") .. "CloseButton"])
        if creatureBtn then
            Skin.CloseButton(creatureBtn)
        end
        -- Only top tab row, house finder button, and neighborhood dropdown are touched; everything else stays stock.
        local details = win.HouseInfoContent
        if details then
            -- Finder button + house dropdown 8px lower (one-shot, anchors kept).
            local function DropInfoControl(ctrl)
                if not ctrl then
                    return
                end
                local cd2 = GetFFD(ctrl)
                if cd2.dropped8 then
                    return
                end
                local pointCount = ctrl:GetNumPoints() or 0
                local pts, success = {}, pointCount > 0
                for idx = 1, pointCount do
                    local point, relTo, relPoint, posX, posY = ctrl:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) - 8 }
                end
                if not success then
                    return
                end
                cd2.dropped8 = true
                ctrl:ClearAllPoints()
                for idx = 1, #pts do
                    local tbl = pts[idx]
                    ctrl:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                end
            end
            if details.HouseFinderButton then
                Skin.Button(details.HouseFinderButton)
                local hfs = details.HouseFinderButton.GetFontString
                    and details.HouseFinderButton:GetFontString()
                if hfs then
                    Skin.White(hfs)
                end
            end
            if details.HouseDropdown then
                Skin.Dropdown(details.HouseDropdown)
                local hdd = GetFFD(details.HouseDropdown)
                if not hdd.scaled then
                    hdd.scaled = true
                    details.HouseDropdown:SetScale(0.86)
                end
                DropInfoControl(details.HouseDropdown)
            end
            local castFrame = details.ContentFrame
            if castFrame and castFrame.TabSystem then
                Skin.TabSystem(castFrame.TabSystem, { darkActive = true })
                -- 1px up: accent underline rides the tabs' bottom edge, clipped at the stock seat.
                local tsd = GetFFD(castFrame.TabSystem)
                if not tsd.lifted then
                    local pointCount = castFrame.TabSystem:GetNumPoints() or 0
                    local pts, success = {}, pointCount > 0
                    for idx = 1, pointCount do
                        local point, relTo, relPoint, posX, posY = castFrame.TabSystem:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + 1 }
                    end
                    if success then
                        tsd.lifted = true
                        castFrame.TabSystem:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            castFrame.TabSystem:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                end
                -- Blizzard rebuilds these tabs; restyle new ones as they appear.
                if castFrame.UpdateTabs and not GetFFD(castFrame).tabHook then
                    GetFFD(castFrame).tabHook = true
                    hooksecurefunc(castFrame, "UpdateTabs", function(cf2)
                        if cf2.TabSystem then
                            Skin.TabSystem(cf2.TabSystem, { darkActive = true })
                        end
                    end)
                end
            end
        end
        local cat = win.CatalogContent
        if cat then
            local searchField = cat.SearchBox
            local filterDropdown = cat.Filters and cat.Filters.FilterDropdown
            if searchField then
                Skin.EditBox(searchField)
            end
            if filterDropdown then
                Skin.Dropdown(filterDropdown)
                -- Left-aligned label (this dropdown only, not engine wide).
                local labelText = filterDropdown.Text or (filterDropdown.GetFontString and filterDropdown:GetFontString())
                local fdData = GetFFD(filterDropdown)
                if labelText and not fdData.labLeft then
                    fdData.labLeft = true
                    labelText:ClearAllPoints()
                    labelText:SetPoint("LEFT", filterDropdown, "LEFT", 8, 0)
                    labelText:SetPoint("RIGHT", filterDropdown, "RIGHT", -22, 0)
                    if labelText.SetJustifyH then
                        labelText:SetJustifyH("LEFT")
                    end
                end
            end
            -- Search box matches filter dropdown height (one-shot; retries on catalog show until laid out).
            if searchField and filterDropdown then
                local function MatchSearchHeight()
                    if GetFFD(searchField).hMatched then
                        return
                    end
                    local dh = filterDropdown:GetHeight()
                    if dh and dh > 0 then
                        GetFFD(searchField).hMatched = true
                        searchField:SetHeight(dh)
                    end
                end
                MatchSearchHeight()
                if not GetFFD(cat).hHook then
                    GetFFD(cat).hHook = true
                    cat:HookScript("OnShow", MatchSearchHeight)
                end
            end
        end
    end

    Skin.RegisterWindow({
        key = "housing",
        addons = { Blizzard_HousingDashboard = true },
        apply = Skin_Housing,
    })
end

-------------------------------------------------------------------------------
--  Profession Crafting window (recipe list, schematic form, specializations,
--  crafting orders): shell chrome, tabs, lists, buttons, rank bar, gear slots.
--  Reagent slot art stays stock. Visual-only throughout.
-------------------------------------------------------------------------------
local function SkinProfMaxMin(btnFrame, atlas)
    if not btnFrame or GetFFD(btnFrame).mm then
        return
    end
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then
        return
    end
    GetFFD(btnFrame).mm = true
    local regionList = { btnFrame:GetRegions() }
    for idx = 1, #regionList do
        local region = regionList[idx]
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
    for _, g in ipairs({
        "GetNormalTexture",
        "GetPushedTexture",
        "GetHighlightTexture",
        "GetDisabledTexture",
    }) do
        local part = btnFrame[g] and btnFrame[g](btnFrame)
        if part and part.SetAlpha then
            part:SetAlpha(0)
        end
    end
    local glyphTex = btnFrame:CreateTexture(nil, "OVERLAY")
    glyphTex:SetSize(16, 16)
    glyphTex:SetPoint("CENTER", btnFrame, "CENTER", -2, 0)
    glyphTex:SetAtlas(atlas, false)
    glyphTex:SetDesaturated(true)
    glyphTex:SetVertexColor(1, 1, 1, 0.75)
    btnFrame:HookScript("OnEnter", function()
        glyphTex:SetVertexColor(1, 1, 1, 1)
    end)
    btnFrame:HookScript("OnLeave", function()
        glyphTex:SetVertexColor(1, 1, 1, 0.75)
    end)
end

do
    -- Profession rank bar (crafting page + order view): house trough+border behind Blizzard's own fill (fill itself is kept).
    local function ProfFlatBar(barFrame)
        if not barFrame then
            return
        end
        local skinData = GetFFD(barFrame)
        if skinData.flat then
            return
        end
        skinData.flat = true
        for _, keyName in ipairs({ "Border", "Background" }) do
            local part = barFrame[keyName]
            if part and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        if not skinData.bg then
            local troughTex = barFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
            troughTex:SetColorTexture(0.12, 0.12, 0.12, 0.85)
            -- The bar FRAME matches the band's size, only its origin is off, and
            -- the Fill's fixed top-left corner IS the band origin: frame size + fill origin = the exact band (right 8px cut off).
            local wid, hgt = barFrame:GetSize()
            if barFrame.Fill and wid and wid > 8 and hgt and hgt > 0 then
                troughTex:SetSize(wid - 8, hgt)
                troughTex:SetPoint("TOPLEFT", barFrame.Fill, "TOPLEFT", 0, 0)
            else
                troughTex:SetAllPoints(barFrame)
            end
            skinData.bg = troughTex
            Skin.BorderRegion(barFrame, troughTex)
        end
        local rankText = barFrame.Rank and barFrame.Rank.Text
        if rankText then
            Skin.Font(rankText)
            Skin.White(rankText)
        end
        -- Expansion picker: stock arrow art stripped, house dropdown arrow with standard 5% hover wash.
        local edb = barFrame.ExpansionDropdownButton
        if edb and not GetFFD(edb).arrow then
            local ed = GetFFD(edb)
            ed.arrow = true
            local regionList = { edb:GetRegions() }
            for idx = 1, #regionList do
                local region = regionList[idx]
                if region and region.IsObjectType and region:IsObjectType("Texture") then
                    region:SetAlpha(0)
                end
            end
            for _, g in ipairs({
                "GetNormalTexture",
                "GetPushedTexture",
                "GetHighlightTexture",
                "GetDisabledTexture",
            }) do
                local part = edb[g] and edb[g](edb)
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
            local ar = edb:CreateTexture(nil, "OVERLAY")
            ar:SetAtlas("Azerite-PointingArrow", false)
            ar:SetSize(14, 10)
            ar:SetPoint("CENTER", edb, "CENTER", 0, 0)
            ed.caret = ar
            local hoverTex = edb:CreateTexture(nil, "HIGHLIGHT")
            hoverTex:SetColorTexture(1, 1, 1, 0.05)
            hoverTex:SetAllPoints(edb)
        end
    end

    local function SkinSchematic(form)
        if not form or form:IsForbidden() then
            return
        end
        local skinData = GetFFD(form)
        if skinData.schem then
            return
        end
        skinData.schem = true
        Skin.FadeRegions(form)
        Skin.Register(form, true)
        if form.Background then
            form.Background:SetAlpha(0)
        end
        if form.MinimalBackground then
            form.MinimalBackground:SetAlpha(0)
        end
        if not skinData.bg then
            local bgTex = SolidTex(form, "BACKGROUND", 0, 0, 0, 0.25, -6)
            bgTex:SetAllPoints(form)
            skinData.bg = bgTex
        end
        for _, keyName in ipairs({ "TrackRecipeCheckbox", "AllocateBestQualityCheckbox" }) do
            if form[keyName] then
                SkinGuildCheck(form[keyName])
            end
        end
        local qd = form.QualityDialog
        if qd then
            SkinGuildPopup(qd)
            if qd.ClosePanelButton then
                Skin.CloseButton(qd.ClosePanelButton)
            end
            if qd.AcceptButton then
                Skin.Button(qd.AcceptButton)
            end
            if qd.CancelButton then
                Skin.Button(qd.CancelButton)
            end
        end
    end

    local function SkinOutputLog(log)
        if not log or GetFFD(log).outLog then
            return
        end
        GetFFD(log).outLog = true
        SkinGuildPopup(log)
        if log.ClosePanelButton then
            Skin.CloseButton(log.ClosePanelButton)
        end
        Skin.ScrollBarsIn(log)
    end

    local PROF_GEAR_SLOTS = {
        "Prof0ToolSlot",
        "Prof0Gear0Slot",
        "Prof0Gear1Slot",
        "Prof1ToolSlot",
        "Prof1Gear0Slot",
        "Prof1Gear1Slot",
        "CookingToolSlot",
        "CookingGear0Slot",
        "FishingToolSlot",
        "FishingGear0Slot",
        "FishingGear1Slot",
    }
    local function SkinProfGearSlot(btnFrame)
        if not btnFrame then
            return
        end
        local skinData = GetFFD(btnFrame)
        if skinData.slot then
            return
        end
        skinData.slot = true
        local glyphTex = btnFrame.icon or btnFrame.Icon
        local keepSet = {}
        if glyphTex then
            keepSet[glyphTex] = true
        end
        if btnFrame.IconBorder then
            keepSet[btnFrame.IconBorder] = true
        end
        Skin.FadeRegions(btnFrame, keepSet)
        for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
            local part = btnFrame[getter] and btnFrame[getter](btnFrame)
            if part and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        if glyphTex then
            Skin.SquareIcon(glyphTex, btnFrame)
        end
        -- 2px smaller than stock (top-right tool/gear icons).
        if not InCombatLockdown() then
            local wid, hgt = btnFrame:GetSize()
            if wid and wid > 4 and hgt and hgt > 4 then
                btnFrame:SetSize(wid - 2, hgt - 2)
            end
        end
    end

    -- Sortable column header over crafting orders (roster-columns look: 3-slice art gone, raised plate, border-free, white labels, 10% hover).
    local function SkinOrderColumns(cd)
        if not cd then
            return
        end
        Skin.FadeRegions(cd)
        Skin.Register(cd, true)
        local children = { cd:GetChildren() }
        for idx = 1, #children do
            local colour = children[idx]
            if colour and colour.GetObjectType and colour:GetObjectType() == "Button" then
                local d2 = GetFFD(colour)
                if not d2.bg then
                    for _, k2 in ipairs({ "Left", "Middle", "Right" }) do
                        local t2 = colour[k2]
                        if t2 and t2.SetTexture then
                            t2:SetTexture("")
                        end
                    end
                    Skin.FadeRegions(colour)
                    local bg2 = SolidTex(
                        colour,
                        "BACKGROUND",
                        Theme.bgR + 0.015,
                        Theme.bgG + 0.015,
                        Theme.bgB + 0.015,
                        Theme.bgA
                    )
                    bg2:SetPoint("TOPLEFT", 1, -1)
                    bg2:SetPoint("BOTTOMRIGHT", -1, 1)
                    d2.bg = bg2
                    local hoverTex = SolidTex(colour, "HIGHLIGHT", 1, 1, 1, 0.1)
                    hoverTex:SetAllPoints(colour)
                    d2.hover = hoverTex
                    Skin.Register(colour, true)
                end
                local fs2 = colour.GetFontString and colour:GetFontString()
                if fs2 then
                    Skin.White(fs2)
                end
            end
        end
    end

    local function SkinOrderView(shade)
        if not shade then
            return
        end
        for _, keyName in ipairs({ "CreateButton", "StartRecraftButton", "CompleteOrderButton" }) do
            if shade[keyName] then
                Skin.Button(shade[keyName])
            end
        end
        ProfFlatBar(shade.RankBar)
        SkinOutputLog(shade.CraftingOutputLog)
        local oi = shade.OrderInfo
        if oi then
            Skin.FadeRegions(oi)
            Skin.Register(oi, true)
            for _, keyName in ipairs({
                "BackButton",
                "StartOrderButton",
                "DeclineOrderButton",
                "ReleaseOrderButton",
            }) do
                if oi[keyName] then
                    Skin.Button(oi[keyName])
                end
            end
        end
        local optionsData = shade.OrderDetails
        if optionsData then
            -- Preserve the quality-tier icon (pentagon next to recipe name): a
            -- direct OVERLAY region of OrderDetails the blanket fade would zero.
            -- The keep set must ALSO go into the restrip registry -- the show hook
            -- re-fades registered frames, and a bare `true` there would zero it again.
            local keepSet = optionsData.MinimumQualityIcon and { [optionsData.MinimumQualityIcon] = true } or nil
            Skin.FadeRegions(optionsData, keepSet)
            Skin.Register(optionsData, keepSet)
            if optionsData.Background then
                optionsData.Background:SetAlpha(0)
            end
            SkinSchematic(optionsData.SchematicForm)
        end
        local dropdown = shade.DeclineOrderDialog
        if dropdown then
            SkinGuildPopup(dropdown)
            if dropdown.ConfirmButton then
                Skin.Button(dropdown.ConfirmButton)
            end
            if dropdown.CancelButton then
                Skin.Button(dropdown.CancelButton)
            end
        end
    end

    local function Skin_Professions()
        local win = _G.ProfessionsFrame
        if not win then
            return
        end
        Skin.Shell("professions", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win)
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or win.TitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end
        if win.CloseButton then
            Skin.CloseButton(win.CloseButton)
        end
        local maxMinBtn = win.MaximizeMinimize
        if maxMinBtn then
            SkinProfMaxMin(maxMinBtn.MinimizeButton, "UI-QuestTrackerButton-Secondary-Collapse")
            SkinProfMaxMin(maxMinBtn.MaximizeButton, "UI-QuestTrackerButton-Secondary-Expand")
        end
        if win.TabSystem then
            Skin.TabSystem(win.TabSystem)
        end

        local cp = win.CraftingPage
        if cp then
            for _, keyName in ipairs({ "CreateButton", "CreateAllButton", "ViewGuildCraftersButton" }) do
                if cp[keyName] then
                    Skin.Button(cp[keyName])
                end
            end
            if cp.MinimizedSearchBox then
                Skin.EditBox(cp.MinimizedSearchBox)
            end
            ProfFlatBar(cp.RankBar)
            SkinSchematic(cp.SchematicForm)
            SkinOutputLog(cp.CraftingOutputLog)
            local rl = cp.RecipeList
            if rl then
                Skin.FadeRegions(rl)
                Skin.Register(rl, true)
                if rl.BackgroundNineSlice then
                    Skin.FadeNineSlice(rl.BackgroundNineSlice)
                end
                local skinData = GetFFD(rl)
                if not skinData.bg then
                    local bgTex = SolidTex(rl, "BACKGROUND", 0, 0, 0, 0.25, -6)
                    bgTex:SetAllPoints(rl)
                    skinData.bg = bgTex
                end
                -- Sidebar filter dropdown: 2px taller, label left-aligned (this dropdown only, not engine-wide).
                local filterDropdown = rl.FilterDropdown
                if filterDropdown then
                    local fieldData = GetFFD(filterDropdown)
                    if not fieldData.hTuned then
                        local h0 = filterDropdown:GetHeight()
                        if h0 and h0 > 0 then
                            fieldData.hTuned = true
                            filterDropdown:SetHeight(h0 + 2)
                            -- Nudged up 1px (one-shot, all points preserved).
                            local pts = {}
                            local success = true
                            for idx = 1, filterDropdown:GetNumPoints() do
                                local point, relTo, relPoint, posX, posY = filterDropdown:GetPoint(idx)
                                if not point then
                                    success = false
                                    break
                                end
                                pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + 1 }
                            end
                            if success and #pts > 0 then
                                filterDropdown:ClearAllPoints()
                                for idx = 1, #pts do
                                    local tbl = pts[idx]
                                    filterDropdown:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                                end
                            end
                        end
                    end
                    local labelText = filterDropdown.Text or (filterDropdown.GetFontString and filterDropdown:GetFontString())
                    if labelText and not fieldData.labLeft then
                        fieldData.labLeft = true
                        labelText:ClearAllPoints()
                        labelText:SetPoint("LEFT", filterDropdown, "LEFT", 8, 0)
                        labelText:SetPoint("RIGHT", filterDropdown, "RIGHT", -22, 0)
                        if labelText.SetJustifyH then
                            labelText:SetJustifyH("LEFT")
                        end
                    end
                    -- Active-filter reset X (house glyph).
                    SkinFilterResetX(filterDropdown.ResetButton, filterDropdown)
                end
            end
            for _, keyName in ipairs(PROF_GEAR_SLOTS) do
                SkinProfGearSlot(cp[keyName])
            end
        end

        local sp = win.SpecPage
        if sp then
            for _, keyName in ipairs({
                "ViewTreeButton",
                "UnlockTabButton",
                "ApplyButton",
                "ViewPreviewButton",
                "BackToFullTreeButton",
                "BackToPreviewButton",
            }) do
                if sp[keyName] then
                    Skin.Button(sp[keyName])
                    Skin.WhiteButtonLabel(sp[keyName])
                end
            end
            if sp.PanelFooter then
                Skin.FadeRegions(sp.PanelFooter)
            end
            local treeView = sp.TreeView
            if treeView then
                -- Tree background art is content: keep it dimmed (talents look).
                local keepSet = {}
                if treeView.Background then
                    keepSet[treeView.Background] = true
                end
                Skin.FadeRegions(treeView, keepSet)
                if treeView.Background then
                    treeView.Background:SetAlpha(0.75)
                end
                -- Tree art bleeds past the center divider: clamp its right edge to the detail pane's left edge.
                local dv0 = sp.DetailedView
                if treeView.Background and dv0 and not GetFFD(treeView).bgClamped then
                    GetFFD(treeView).bgClamped = true
                    treeView.Background:ClearAllPoints()
                    treeView.Background:SetPoint("TOPLEFT", treeView, "TOPLEFT", 0, 0)
                    treeView.Background:SetPoint("BOTTOMRIGHT", dv0, "BOTTOMLEFT", 0, 0)
                end
            end
            local dv = sp.DetailedView
            if dv then
                Skin.FadeRegions(dv)
                Skin.Register(dv, true)
                for _, keyName in ipairs({ "UnlockPathButton", "SpendPointsButton" }) do
                    if dv[keyName] then
                        Skin.Button(dv[keyName])
                        Skin.WhiteButtonLabel(dv[keyName])
                    end
                end
            end
            -- Spec tabs are pooled and rebuilt; skin now and on every rebuild.
            local function SkinSpecTabs(sp2)
                if sp2.tabsPool then
                    for tabBtn in sp2.tabsPool:EnumerateActive() do
                        Skin.Tab(tabBtn, { darkActive = true })
                    end
                end
            end
            if sp.UpdateTabs and not GetFFD(sp).tabHook then
                GetFFD(sp).tabHook = true
                hooksecurefunc(sp, "UpdateTabs", SkinSpecTabs)
            end
            SkinSpecTabs(sp)
        end

        local op = win.OrdersPage
        if op then
            local subFrame = op.BrowseFrame
            if subFrame then
                -- Order-type tabs populate LAZILY (some not created until you click
                -- through types), so a one-time pass leaves later ones unstyled;
                -- WSkin.Tab is guarded, so re-runs skin only NEW tabs.
                local ORDER_TAB_KEYS = {
                    "PublicOrdersButton",
                    "NpcOrdersButton",
                    "GuildOrdersButton",
                    "PersonalOrdersButton",
                }
                local function SkinOrderTabs()
                    for _, keyName in ipairs(ORDER_TAB_KEYS) do
                        local button = subFrame[keyName]
                        if button then
                            Skin.Tab(button, { darkActive = true })
                        end
                    end
                end
                SkinOrderTabs()
                if C_Timer then
                    C_Timer.After(0, SkinOrderTabs)
                end
                -- Re-skin AND repaint selection on every order-type switch. These
                -- tabs carry no tabID and BrowseFrame is no TabSystem, so the
                -- engine's PanelTemplates/TabSystem hooks only repaint incidentally.
                -- A per-tab OnClick hook does NOT survive: InitOrderTypeTabs()
                -- re-SetScript's each tab's OnClick on PLAYER_ENTERING_WORLD/
                -- PLAYER_GUILD_UPDATE, wiping the hook and freezing the underline.
                -- Hook the authoritative SETTER instead: a method hook survives
                -- SetScript and catches programmatic switches (leave-guild fallback
                -- to Public); hooksecurefunc runs after the original so isSelected is current.
                if op.SetCraftingOrderType and not GetFFD(op).orderTypeHook then
                    GetFFD(op).orderTypeHook = true
                    hooksecurefunc(op, "SetCraftingOrderType", SkinOrderTabs)
                end
                -- Tab row starts where the sort header starts: shift the chain root
                -- right by the measured delta (one-shot; other three chain off it).
                -- Rects exist only once laid out, so retry on show.
                local firstTab = subFrame.PublicOrdersButton
                local function AlignOrderTabs()
                    if GetFFD(subFrame).tabsAligned or not firstTab then
                        return
                    end
                    local ol2 = subFrame.OrderList
                    local tl = firstTab.GetLeft and firstTab:GetLeft()
                    local ll = ol2 and ol2.GetLeft and ol2:GetLeft()
                    if not tl or not ll then
                        return
                    end
                    local dx = math.floor((ll - tl) + 0.5)
                    if dx == 0 then
                        GetFFD(subFrame).tabsAligned = true
                        return
                    end
                    local pts, success = {}, true
                    for idx = 1, firstTab:GetNumPoints() do
                        local point, relTo, relPoint, posX, posY = firstTab:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, (posX or 0) + dx, posY or 0 }
                    end
                    if success and #pts > 0 then
                        GetFFD(subFrame).tabsAligned = true
                        firstTab:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            firstTab:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                end
                AlignOrderTabs()
                if not GetFFD(subFrame).alignHook then
                    GetFFD(subFrame).alignHook = true
                    subFrame:HookScript("OnShow", function()
                        SkinOrderTabs()
                        if C_Timer then
                            C_Timer.After(0, function()
                                SkinOrderTabs()
                                AlignOrderTabs()
                            end)
                        else
                            AlignOrderTabs()
                        end
                    end)
                end
                local searchBar = subFrame.SearchBox or subFrame.searchBox
                if subFrame.SearchButton then
                    Skin.Button(subFrame.SearchButton)
                    local sfs = subFrame.SearchButton.GetFontString and subFrame.SearchButton:GetFontString()
                    if sfs then
                        Skin.White(sfs)
                    end
                    local sbtn = subFrame.SearchButton
                    local partData = GetFFD(sbtn)
                    if not partData.shrunk then
                        local wid, hgt = sbtn:GetSize()
                        if wid and wid > 2 and hgt and hgt > 2 then
                            partData.shrunk = true
                            sbtn:SetSize(wid - 1, hgt - 1)
                        end
                    end
                    -- Left edge flush with the search box's left, Y unchanged; retried on show until the search bar lays out.
                    local function AlignSearchBtn()
                        if not searchBar or GetFFD(sbtn).leftAligned then
                            return
                        end
                        local bl, sl = sbtn:GetLeft(), searchBar:GetLeft()
                        if not bl or not sl then
                            return
                        end
                        local dx = sl - bl
                        if math.abs(dx) < 0.5 then
                            GetFFD(sbtn).leftAligned = true
                            return
                        end
                        local pointCount = sbtn:GetNumPoints() or 0
                        local pts, success = {}, pointCount > 0
                        for idx = 1, pointCount do
                            local point, relTo, relPoint, posX, posY = sbtn:GetPoint(idx)
                            if not point then
                                success = false
                                break
                            end
                            pts[idx] = { point, relTo, relPoint, (posX or 0) + dx, posY or 0 }
                        end
                        if success then
                            GetFFD(sbtn).leftAligned = true
                            sbtn:ClearAllPoints()
                            for idx = 1, #pts do
                                local tbl = pts[idx]
                                sbtn:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                            end
                        end
                    end
                    AlignSearchBtn()
                    if not GetFFD(sbtn).alignHook then
                        GetFFD(sbtn).alignHook = true
                        subFrame:HookScript("OnShow", function()
                            if C_Timer then
                                C_Timer.After(0, AlignSearchBtn)
                            else
                                AlignSearchBtn()
                            end
                        end)
                    end
                end
                if subFrame.FavoritesSearchButton then
                    -- Keep the star art: Icon key survives the strip, state textures restored after.
                    local fav = subFrame.FavoritesSearchButton
                    Skin.Button(fav, { "Icon" })
                    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
                        local part = fav[getter] and fav[getter](fav)
                        if part and part.SetAlpha then
                            part:SetAlpha(1)
                        end
                    end
                    -- 10px right of the search box (direct anchor, no rects needed).
                    if searchBar and not GetFFD(fav).reseated then
                        GetFFD(fav).reseated = true
                        fav:ClearAllPoints()
                        fav:SetPoint("LEFT", searchBar, "RIGHT", 10, 0)
                    end
                end
                if subFrame.BackButton then
                    Skin.Button(subFrame.BackButton)
                end
                local ord = subFrame.OrdersRemainingDisplay
                if ord then
                    Skin.FadeRegions(ord)
                    Skin.Register(ord, true)
                    -- Top-right, pinned via SetPoint post-hook so Blizzard's browse layout cannot reseat it.
                    local optionsData = GetFFD(ord)
                    if not optionsData.pinned then
                        optionsData.pinned = true
                        local function Pin()
                            if optionsData.inPin then
                                return
                            end
                            optionsData.inPin = true
                            ord:ClearAllPoints()
                            ord:SetPoint("TOPRIGHT", win, "TOPRIGHT", -20, -35)
                            optionsData.inPin = false
                        end
                        hooksecurefunc(ord, "SetPoint", function()
                            if not optionsData.inPin then
                                Pin()
                            end
                        end)
                        Pin()
                    end
                    -- Trailing count in accent: display-time recolor, skipped if text already carries a color code.
                    local fontStr
                    local regionList = { ord:GetRegions() }
                    for idx = 1, #regionList do
                        local region = regionList[idx]
                        if region and region.IsObjectType and region:IsObjectType("FontString") then
                            fontStr = region
                            break
                        end
                    end
                    if fontStr and not GetFFD(fontStr).accentNum then
                        local fsd = GetFFD(fontStr)
                        fsd.accentNum = true
                        Skin.Font(fontStr)
                        Skin.White(fontStr)
                        local function Recolor()
                            if fsd.inSet then
                                return
                            end
                            local txt = fontStr:GetText()
                            if type(txt) ~= "string" or txt == "" then
                                return
                            end
                            if txt:find("|c", 1, true) then
                                return
                            end
                            local ACC = CludesUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }
                            local hex = string.format(
                                "%02x%02x%02x",
                                (ACC.r or 0) * 255,
                                (ACC.g or 0) * 255,
                                (ACC.b or 0) * 255
                            )
                            local new, n = txt:gsub("(%d+%s*)$", "|cff" .. hex .. "%1|r")
                            if n > 0 then
                                fsd.inSet = true
                                fontStr:SetText(new)
                                fsd.inSet = false
                            end
                        end
                        hooksecurefunc(fontStr, "SetText", Recolor)
                        hooksecurefunc(fontStr, "SetFormattedText", Recolor)
                        Recolor()
                    end
                end
                local brl = subFrame.RecipeList
                if brl then
                    Skin.FadeRegions(brl)
                    Skin.Register(brl, true)
                    if brl.BackgroundNineSlice then
                        Skin.FadeNineSlice(brl.BackgroundNineSlice)
                    end
                end
                local optionsList = subFrame.OrderList
                if optionsList then
                    Skin.FadeRegions(optionsList)
                    Skin.Register(optionsList, true)
                    if optionsList.BackgroundNineSlice then
                        Skin.FadeNineSlice(optionsList.BackgroundNineSlice)
                    end
                    -- Sort header: AH-style near-black strip over HeaderContainer
                    -- (this list uses HeaderContainer, not the older ColumnDisplay);
                    -- SortHeaderBar also strips each column's 3-slice art and whites
                    -- its label. Column SET changes per order-type, and Blizzard
                    -- rebuilds header buttons IN PLACE via the table builder WITHOUT
                    -- re-showing the container, so an OnShow hook never catches fresh
                    -- columns. Re-run from the table rebuild (SetupTable) and list
                    -- refresh, the same signals AH sort headers ride.
                    if optionsList.HeaderContainer then
                        local function ReskinHeaders()
                            Skin.SortHeaderBar(optionsList)
                        end
                        ReskinHeaders()
                        local headerContainer = optionsList.HeaderContainer
                        if not GetFFD(headerContainer).showHooked then
                            GetFFD(headerContainer).showHooked = true
                            headerContainer:HookScript("OnShow", Skin.Debounce(ReskinHeaders))
                        end
                        -- Column-rebuild triggers: SetupTable (order-type switch /
                        -- view rebuild) and scroll refresh. Hook whichever exist;
                        -- guarded, idempotent, deferred a frame so new column rects exist.
                        for _, pair in ipairs({
                            { subFrame, "SetupTable" },
                            { optionsList, "SetupTable" },
                            { optionsList, "RefreshScrollFrame" },
                        }) do
                            local owner, method = pair[1], pair[2]
                            if owner and type(owner[method]) == "function" then
                                local hd = GetFFD(owner)
                                local flag = "hdrHook_" .. method
                                if not hd[flag] then
                                    hd[flag] = true
                                    hooksecurefunc(owner, method, Skin.Debounce(ReskinHeaders))
                                end
                            end
                        end
                        -- Guaranteed trigger regardless of Blizzard method names:
                        -- order-type tabs are what the user clicks to repopulate
                        -- the column set. Re-skin a frame after each click.
                        for _, keyName in ipairs(ORDER_TAB_KEYS) do
                            local tabFrame = subFrame[keyName]
                            if tabFrame and not GetFFD(tabFrame).hdrReskin then
                                GetFFD(tabFrame).hdrReskin = true
                                tabFrame:HookScript("OnClick", Skin.Debounce(ReskinHeaders))
                            end
                        end
                    end
                    -- Legacy ColumnDisplay fallback (no-op when the list uses HeaderContainer instead).
                    local ocd = optionsList.ColumnDisplay
                    if ocd then
                        SkinOrderColumns(ocd)
                        if not GetFFD(ocd).showHooked then
                            GetFFD(ocd).showHooked = true
                            ocd:HookScript(
                                "OnShow",
                                Skin.Debounce(function()
                                    SkinOrderColumns(ocd)
                                end)
                            )
                        end
                    end
                end
            end
            SkinOrderView(op.OrderView)
        end

        Skin.ScrollBarsIn(win)
        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    Skin.Restrip()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "professions",
        addons = { Blizzard_Professions = true },
        apply = Skin_Professions,
    })
end

-------------------------------------------------------------------------------
--  World Map & Quest Log: flat window chrome, nav bar strip, quest log panel,
--  details/campaign/events/legend panes, side tabs. Deliberately HANDS-OFF:
--  QuestMapFrame's own scripts (Objective Tracker taint path), the session-sync
--  command button, map overlay buttons (tracking/pin/floor) and pooled quest
--  rows stay stock. Visual-only throughout.
-------------------------------------------------------------------------------
do
    -- Quest log side tabs: guild sidebar-tab treatment (squared icon on a
    -- black-bordered box, 10% hover, 0.12-0.88 icon crop per pass, half alpha when disabled, no active overlay).
    local function SkinMapSideTab(tabBtn)
        if not tabBtn or tabBtn:IsForbidden() then
            return
        end
        SquareTabIcon(tabBtn)
        local glyphTex = tabBtn.Icon
        local titleData = GetFFD(tabBtn)
        if glyphTex and not titleData.box then
            local tabBox = CreateFrame("Frame", nil, tabBtn)
            tabBox:SetPoint("TOPLEFT", glyphTex, "TOPLEFT", -5, 5)
            tabBox:SetPoint("BOTTOMRIGHT", glyphTex, "BOTTOMRIGHT", 5, -5)
            tabBox:SetFrameLevel(math.max(0, tabBtn:GetFrameLevel() - 2))
            local fillTex = SolidTex(tabBox, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
            fillTex:SetAllPoints(tabBox)
            Skin.AddBorder(tabBox, 0, 0, 0, 1)
            titleData.box = tabBox
            titleData.bg = fillTex
            local hoverTex = SolidTex(tabBtn, "HIGHLIGHT", 1, 1, 1, 0.1)
            hoverTex:SetPoint("TOPLEFT", tabBox, "TOPLEFT", 0, 0)
            hoverTex:SetPoint("BOTTOMRIGHT", tabBox, "BOTTOMRIGHT", 0, 0)
            titleData.hover = hoverTex
        end
        -- Tighter icon zoom than the standard crop (re-applied per pass;
        -- SquareTabIcon resets it to the 0.08 standard above).
        if glyphTex and glyphTex.SetTexCoord then
            glyphTex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        end
        local enabled = not tabBtn.IsEnabled or tabBtn:IsEnabled()
        tabBtn:SetAlpha(enabled and 1 or 0.5)
    end

    -- Quest log collapsible header rows (rep-tab treatment: band art gone, house
    -- plate+hover, white text). Blizzard's +/- stays (small square texture, told
    -- apart from wide band art by width). Pooled rows, so everything re-asserts per pass.
    local function SkinQuestHeader(btnFrame, kind)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        local withCard = kind == "campaign"
        local skinData = GetFFD(btnFrame)
        local regionList = { btnFrame:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if
                region
                and region ~= skinData.plate
                and region ~= skinData.hover
                and region ~= skinData.card
                and region ~= skinData.divider
                and region.IsObjectType
                and region:IsObjectType("Texture")
            then
                local wid = region:GetWidth()
                if wid and not issecretvalue(wid) and wid > 40 then
                    region:SetAlpha(0)
                end
            end
        end
        -- Campaign card: guild-sidebar tile sheet behind the big header, bottom edge 6px up for breathing room above the first quest title.
        if withCard and not skinData.card then
            local cardFrame = btnFrame:CreateTexture(nil, "BACKGROUND", nil, -5)
            cardFrame:SetAtlas("Ui-Dialog-New-Background")
            cardFrame:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", 0, 0)
            cardFrame:SetPoint("BOTTOMRIGHT", btnFrame, "BOTTOMRIGHT", 0, 6)
            cardFrame:SetAlpha(0.5)
            skinData.card = cardFrame
        end
        -- Divider above section headers, separating the campaign block from regular quest sections.
        if kind == "header" and not skinData.divider then
            local div = btnFrame:CreateTexture(nil, "OVERLAY")
            div:SetColorTexture(1, 1, 1, 0.15)
            local PPd = CludesUI and CludesUI.PanelPP
            if PPd and PPd.DisablePixelSnap then
                PPd.DisablePixelSnap(div)
                div:SetHeight(PPd.mult or 1)
            else
                div:SetHeight(1)
            end
            div:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", 0, 12)
            div:SetPoint("TOPRIGHT", btnFrame, "TOPRIGHT", 0, 12)
            skinData.divider = div
        end
        local highlight = btnFrame.GetHighlightTexture and btnFrame:GetHighlightTexture()
        if highlight and highlight ~= skinData.hover then
            highlight:SetAlpha(0)
        end
        local bt = btnFrame.ButtonText or (btnFrame.GetName and btnFrame:GetName() and _G[btnFrame:GetName() .. "ButtonText"])
        if bt and bt.SetTextColor then
            Skin.White(bt)
        end
        if btnFrame.Text and btnFrame.Text.SetTextColor then
            Skin.White(btnFrame.Text)
        end
        -- Blizzard recolors the label gray on hover: re-white after its enter/leave handlers.
        if not skinData.hoverTextHook then
            skinData.hoverTextHook = true
            local function ReWhite()
                local bt2 = btnFrame.ButtonText
                    or (btnFrame.GetName and btnFrame:GetName() and _G[btnFrame:GetName() .. "ButtonText"])
                if bt2 and bt2.SetTextColor then
                    Skin.White(bt2)
                end
                if btnFrame.Text and btnFrame.Text.SetTextColor then
                    Skin.White(btnFrame.Text)
                end
            end
            btnFrame:HookScript("OnEnter", ReWhite)
            btnFrame:HookScript("OnLeave", ReWhite)
        end
        if not skinData.plate then
            skinData.plate = SolidTex(btnFrame, "BACKGROUND", 1, 1, 1, 0.05)
            local hoverTex = SolidTex(btnFrame, "HIGHLIGHT", 1, 1, 1, 0.05)
            if withCard then
                -- Dialog-sheet art has soft edges, so washes sit 3px inside to
                -- match its visible card; bottom follows the card's raised edge (6px) plus the inset.
                skinData.plate:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", 3, -3)
                skinData.plate:SetPoint("BOTTOMRIGHT", btnFrame, "BOTTOMRIGHT", -3, 9)
                hoverTex:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", 3, -3)
                hoverTex:SetPoint("BOTTOMRIGHT", btnFrame, "BOTTOMRIGHT", -3, 9)
            else
                skinData.plate:SetAllPoints(btnFrame)
                hoverTex:SetAllPoints(btnFrame)
            end
            skinData.hover = hoverTex
        end
    end

    local function Skin_WorldMap()
        local win = _G.WorldMapFrame
        if not win then
            return
        end
        -- Style-aware shell like every other window: canvas covers the middle, but
        -- quest log flank/top bar/borders show it, and the cui/Modern swap follows the style dropdown.
        Skin.Shell("worldmap", win)

        Skin.RemovePortrait(win)
        local subFrame = win.BorderFrame
        if subFrame then
            Skin.RemovePortrait(subFrame)
            Skin.FadeRegions(subFrame)
            Skin.Register(subFrame, true)
            if subFrame.NineSlice then
                Skin.FadeNineSlice(subFrame.NineSlice)
            end
            if subFrame.PortraitContainer then
                Skin.FadeRegions(subFrame.PortraitContainer)
                Skin.Register(subFrame.PortraitContainer, true)
            end
            if _G.WorldMapFramePortrait and _G.WorldMapFramePortrait.SetAlpha then
                _G.WorldMapFramePortrait:SetAlpha(0)
            end
            if subFrame.CloseButton then
                Skin.CloseButton(subFrame.CloseButton)
            end
            local maxMinBtn = subFrame.MaximizeMinimizeFrame
            if maxMinBtn then
                SkinProfMaxMin(maxMinBtn.MinimizeButton, "UI-QuestTrackerButton-Secondary-Collapse")
                SkinProfMaxMin(maxMinBtn.MaximizeButton, "UI-QuestTrackerButton-Secondary-Expand")
            end
            local titleText = (subFrame.TitleContainer and subFrame.TitleContainer.TitleText) or subFrame.TitleText
            if titleText then
                Skin.Font(titleText)
                Skin.White(titleText)
            end
        end

        -- Breadcrumb nav bar. Keep Blizzard's NATIVE crumb layout: re-widthing or
        -- re-anchoring crumbs (as the Adventure Guide restyle does) flings the
        -- map's text off-window, since the map nav has a home button, an overflow
        -- button, and arrow-shaped crumb geometry the chain logic breaks. Art only:
        -- flatten, one 20% black bar, white text, house carets.
        local navBar = win.NavBar
        if navBar then
            local navData = GetFFD(navBar)
            -- One crumb (home + navList): native art faded, subtle hover, white
            -- text, and the Adventure Guide caret treatment (aspect-correct arrow,
            -- Blizzard's caret re-faded on hover so it cannot resurface from
            -- OnEnter). No width/anchor changes.
            local function SkinMapCrumb(btnFrame)
                if not btnFrame or btnFrame:IsForbidden() then
                    return
                end
                local skinData = GetFFD(btnFrame)
                if not skinData.mapNav then
                    skinData.mapNav = true
                    for _, g in ipairs({
                        "GetNormalTexture",
                        "GetHighlightTexture",
                        "GetPushedTexture",
                        "GetDisabledTexture",
                    }) do
                        local func = btnFrame[g]
                        local part = func and func(btnFrame)
                        if part and part.SetAlpha then
                            part:SetAlpha(0)
                        end
                    end
                    Skin.FadeRegions(btnFrame)
                    local hoverTex = SolidTex(btnFrame, "HIGHLIGHT", 1, 1, 1, 0.1)
                    hoverTex:SetPoint("TOPLEFT", 2, -3)
                    hoverTex:SetPoint("BOTTOMRIGHT", -2, 3)
                    skinData.hover = hoverTex
                    Skin.Register(btnFrame, true)
                    -- Rewinding (clicking an earlier crumb) hides later ones, so
                    -- re-anchor the capped bar to the new last crumb.
                    btnFrame:HookScript("OnClick", function()
                        if navData.reflow then
                            navData.reflow()
                        end
                    end)
                end
                if btnFrame.text then
                    Skin.White(btnFrame.text)
                end
                local menuArrow = btnFrame.MenuArrowButton
                if menuArrow then
                    local mountDisplay = GetFFD(menuArrow)
                    if not mountDisplay.arrow then
                        local arrowTex = menuArrow:CreateTexture(nil, "OVERLAY")
                        arrowTex:SetAtlas("Azerite-PointingArrow")
                        arrowTex:SetSize(12, 8.5) -- native 62x44 aspect
                        arrowTex:SetPoint("CENTER")
                        mountDisplay.arrow = arrowTex
                    end
                    -- Fade ALL native caret art, keeping our arrow; re-run on hover
                    -- so Blizzard's caret cannot resurface from OnEnter.
                    local function FadeArrowArt()
                        local keepSet = { [mountDisplay.arrow] = true }
                        Skin.FadeRegions(menuArrow, keepSet)
                        for _, g in ipairs({
                            "GetNormalTexture",
                            "GetPushedTexture",
                            "GetHighlightTexture",
                            "GetDisabledTexture",
                        }) do
                            local func = menuArrow[g]
                            local part = func and func(menuArrow)
                            if part and not keepSet[part] and part.SetAlpha then
                                part:SetAlpha(0)
                            end
                        end
                        if menuArrow.Art and menuArrow.Art.SetAlpha then
                            menuArrow.Art:SetAlpha(0)
                        end
                    end
                    FadeArrowArt()
                    if not mountDisplay.hoverHooked then
                        mountDisplay.hoverHooked = true
                        menuArrow:HookScript("OnEnter", FadeArrowArt)
                        menuArrow:HookScript("OnLeave", FadeArrowArt)
                    end
                end
            end
            local function RefreshMapNav()
                -- Move the whole bar 4px lower WITHOUT collapsing its width: the nav
                -- has MORE THAN ONE point (TOPLEFT + a right edge), so re-applying
                -- only point 1 shrinks the bar to one crumb and forces every parent
                -- into overflow. Preserve EVERY original point, each -4 in y.
                if navData.origPts == nil then
                    local numPoints = navBar:GetNumPoints() or 0
                    local pts, success = {}, numPoints > 0
                    for idx = 1, numPoints do
                        local point, relTo, relPoint, posX, posY = navBar:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) - 4 }
                    end
                    if success then
                        navData.origPts = pts
                    end
                end
                if navData.origPts then
                    navBar:ClearAllPoints()
                    for idx = 1, #navData.origPts do
                        local tbl = navData.origPts[idx]
                        navBar:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                    end
                end
                for _, keyName in ipairs({
                    "InsetBorderBottomLeft",
                    "InsetBorderBottomRight",
                    "InsetBorderBottom",
                    "InsetBorderLeft",
                    "InsetBorderRight",
                }) do
                    local part = navBar[keyName]
                    if part and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
                local keepSet = navData.bg and { [navData.bg] = true } or nil
                Skin.FadeRegions(navBar, keepSet)
                Skin.Register(navBar, true)
                if navBar.overlay then
                    Skin.FadeRegions(navBar.overlay)
                    local nt = navBar.overlay.GetNormalTexture and navBar.overlay:GetNormalTexture()
                    if nt and nt.SetAlpha then
                        nt:SetAlpha(0)
                    end
                    if navBar.overlay.SetAlpha then
                        navBar.overlay:SetAlpha(0)
                    end
                    Skin.Register(navBar.overlay, true)
                end
                if navBar.homeButton then
                    SkinMapCrumb(navBar.homeButton)
                end
                if navBar.navList then
                    for idx = 1, #navBar.navList do
                        SkinMapCrumb(navBar.navList[idx])
                    end
                end
                -- 20% black bar: left edge on the nav, right edge 8px past the LAST
                -- crumb (capped, never spanning the whole frame).
                if not navData.bg then
                    local barFrame = navBar:CreateTexture(nil, "BACKGROUND", nil, -6)
                    barFrame:SetColorTexture(0, 0, 0, 0.2)
                    navData.bg = barFrame
                end
                local last = (navBar.navList and #navBar.navList > 0 and navBar.navList[#navBar.navList])
                    or navBar.homeButton
                navData.bg:ClearAllPoints()
                navData.bg:SetPoint("TOPLEFT", navBar, "TOPLEFT", 0, 0)
                navData.bg:SetPoint("BOTTOMLEFT", navBar, "BOTTOMLEFT", 0, 0)
                if last then
                    navData.bg:SetPoint("RIGHT", last, "RIGHT", 8, 0)
                else
                    navData.bg:SetPoint("RIGHT", navBar, "RIGHT", 0, 0)
                end
                -- Overflow ("...") button: flatten, aspect-correct arrow, hover,
                -- Blizzard's art re-faded on hover.
                local ovf = navBar.overflowButton
                if ovf then
                    local optionsData = GetFFD(ovf)
                    if not optionsData.mapOvf then
                        optionsData.mapOvf = true
                        local arrowTex = ovf:CreateTexture(nil, "OVERLAY")
                        arrowTex:SetAtlas("Azerite-PointingArrow")
                        arrowTex:SetSize(12, 8.5)
                        arrowTex:SetPoint("CENTER")
                        optionsData.arrow = arrowTex
                        optionsData.hover = SolidTex(ovf, "HIGHLIGHT", 1, 1, 1, 0.1)
                        optionsData.hover:SetAllPoints(ovf)
                    end
                    local function FadeOvfArt()
                        local keepSet = { [optionsData.arrow] = true }
                        if optionsData.hover then
                            keepSet[optionsData.hover] = true
                        end
                        Skin.FadeRegions(ovf, keepSet)
                        for _, g in ipairs({
                            "GetNormalTexture",
                            "GetPushedTexture",
                            "GetHighlightTexture",
                            "GetDisabledTexture",
                        }) do
                            local func = ovf[g]
                            local part = func and func(ovf)
                            if part and not keepSet[part] and part.SetAlpha then
                                part:SetAlpha(0)
                            end
                        end
                    end
                    FadeOvfArt()
                    if not optionsData.hoverHooked then
                        optionsData.hoverHooked = true
                        ovf:HookScript("OnEnter", FadeOvfArt)
                        ovf:HookScript("OnLeave", FadeOvfArt)
                    end
                end
            end
            navData.reflow = RefreshMapNav
            RefreshMapNav()
            if not navData.addBtnHook and type(_G.NavBar_AddButton) == "function" then
                navData.addBtnHook = true
                hooksecurefunc("NavBar_AddButton", function(barFrame)
                    if barFrame == navBar then
                        RefreshMapNav()
                    end
                end)
            end
        end

        local spt = win.SidePanelToggle
        if spt then
            if spt.CloseButton then
                Skin.PageButton(spt.CloseButton, "<")
            end
            if spt.OpenButton then
                Skin.PageButton(spt.OpenButton, ">")
            end
        end

        ---------------------------------------------------------------------------
        --  Quest log panel
        ---------------------------------------------------------------------------
        local questMap = _G.QuestMapFrame
        if questMap then
            if questMap.VerticalSeparator then
                questMap.VerticalSeparator:SetAlpha(0)
            end
            if questMap.Background then
                questMap.Background:SetAlpha(0)
            end

            local questScroll = _G.QuestScrollFrame
            if questScroll then
                for _, keyName in ipairs({ "Edge", "Background", "Center" }) do
                    local part = questScroll[keyName]
                    if part and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
                if questScroll.BorderFrame then
                    questScroll.BorderFrame:SetAlpha(0)
                end
                if questScroll.Contents and questScroll.Contents.Separator then
                    questScroll.Contents.Separator:SetAlpha(0)
                end
                local sh = questScroll.Contents and questScroll.Contents.StoryHeader
                if sh then
                    if sh.TopFiligree then
                        sh.TopFiligree:SetAlpha(0)
                    end
                    if sh.Divider then
                        sh.Divider:SetAlpha(0)
                    end
                end
                if questScroll.SearchBox then
                    Skin.EditBox(questScroll.SearchBox)
                end
                if questScroll.ScrollBar then
                    Skin.ScrollBar(questScroll.ScrollBar)
                end
                -- Collapsible section headers: pooled, re-skinned on every quest
                -- log update.
                local function SkinQuestHeaders()
                    for _, poolKey in ipairs({
                        "headerFramePool",
                        "campaignHeaderFramePool",
                        "campaignHeaderMinimalFramePool",
                    }) do
                        local pool = questScroll[poolKey]
                        if pool and pool.EnumerateActive then
                            local kind = (poolKey == "campaignHeaderFramePool" and "campaign")
                                or (poolKey == "headerFramePool" and "header")
                                or "minimal"
                            pcall(function()
                                for btnFrame in pool:EnumerateActive() do
                                    SkinQuestHeader(btnFrame, kind)
                                end
                            end)
                        end
                    end
                    -- ONE divider only: the topmost regular header marks the
                    -- campaign/regular boundary, all others hide theirs.
                    local hp = questScroll.headerFramePool
                    if hp and hp.EnumerateActive then
                        pcall(function()
                            local topBtn, topY
                            for btnFrame in hp:EnumerateActive() do
                                local t = btnFrame.GetTop and btnFrame:GetTop()
                                if t and not issecretvalue(t) and (not topY or t > topY) then
                                    topY = t
                                    topBtn = btnFrame
                                end
                            end
                            if topBtn then
                                for btnFrame in hp:EnumerateActive() do
                                    local bd2 = FFD[btnFrame]
                                    local div = bd2 and bd2.divider
                                    if div then
                                        div:SetShown(btnFrame == topBtn)
                                    end
                                end
                            end
                        end)
                    end
                end
                SkinQuestHeaders()
                if type(_G.QuestLogQuests_Update) == "function" and not GetFFD(questScroll).qhHook then
                    GetFFD(questScroll).qhHook = true
                    hooksecurefunc("QuestLogQuests_Update", SkinQuestHeaders)
                end
            end

            -- Midnight nests the details frame under QuestsFrame; older layouts had
            -- it directly on QuestMapFrame, so both paths are checked.
            local repDetail = questMap.DetailsFrame or (questMap.QuestsFrame and questMap.QuestsFrame.DetailsFrame)
            if repDetail then
                if repDetail.BorderFrame then
                    repDetail.BorderFrame:SetAlpha(0)
                end
                if repDetail.SealMaterialBG then
                    repDetail.SealMaterialBG:SetAlpha(0)
                end
                Skin.FadeRegions(repDetail)
                Skin.Register(repDetail, true)
                if repDetail.BackFrame then
                    Skin.FadeRegions(repDetail.BackFrame)
                    Skin.Register(repDetail.BackFrame, true)
                    if repDetail.BackFrame.BackButton then
                        Skin.Button(repDetail.BackFrame.BackButton)
                    end
                end
                for _, keyName in ipairs({ "AbandonButton", "ShareButton", "TrackButton" }) do
                    local button = repDetail[keyName]
                    if button then
                        Skin.FadeRegions(button)
                        Skin.Button(button)
                    end
                end
                local rfc = repDetail.RewardsFrameContainer
                if rfc and rfc.RewardsFrame then
                    Skin.FadeRegions(rfc.RewardsFrame)
                    Skin.Register(rfc.RewardsFrame, true)
                    -- Rewards backdrop: solid #050505 base + the guild sidebar card
                    -- texture over it, full size. Stored under protected keys so a
                    -- Restrip never fades them.
                    local regionData = GetFFD(rfc)
                    if not regionData.bg then
                        local base = rfc:CreateTexture(nil, "BACKGROUND", nil, -7)
                        base:SetColorTexture(0.0196, 0.0196, 0.0196, 1) -- #050505 @ 100%
                        base:SetAllPoints(rfc)
                        regionData.bg = base
                        local cardFrame = rfc:CreateTexture(nil, "BACKGROUND", nil, -6)
                        cardFrame:SetAtlas("Ui-Dialog-New-Background")
                        cardFrame:SetTexCoord(0, 1, 0, 1)
                        cardFrame:SetAlpha(0.5)
                        cardFrame:SetAllPoints(rfc)
                        regionData.fill = cardFrame
                    end
                end
                -- Quest detail text: section headers (title / description /
                -- objectives / rewards) = quest yellow; body text + pooled
                -- objective lines = white. Re-applied per map quest display.
                local function StyleQuestText()
                    for _, n in ipairs({
                        "QuestInfoTitleHeader",
                        "QuestInfoDescriptionHeader",
                        "QuestInfoObjectivesHeader",
                    }) do
                        local fontStr = _G[n]
                        if fontStr and fontStr.SetTextColor then
                            fontStr:SetTextColor(1, 0.82, 0)
                        end
                    end
                    local objectiveRow = _G.QuestInfoRewardsFrame
                    if objectiveRow then
                        WhitenTextIn(objectiveRow) -- catch nested spell/effect + SimpleHTML reward blurbs
                        if objectiveRow.Header and objectiveRow.Header.SetTextColor then
                            objectiveRow.Header:SetTextColor(1, 0.82, 0)
                        end
                    end
                    -- Reward tiles in the MAP / quest log. Blizzard ships a SECOND
                    -- rewards frame for this panel -- MapQuestInfoRewardsFrame,
                    -- built from the Small item button template -- so the quest
                    -- pack's work on QuestInfoRewardsFrame never reaches here and
                    -- every reward in the log stayed stock. Both are walked because
                    -- which one the map populates has moved between builds.
                    --
                    -- Same treatment as the NPC window: drop the QuestItemBorder
                    -- plate, white the name, square the icon, and give it back the
                    -- rarity as a SQUARE border rather than Blizzard's rounded one.
                    for _, rf in ipairs({ _G.MapQuestInfoRewardsFrame, objectiveRow }) do
                        if rf and rf.RewardButtons then
                            for _, btnFrame in ipairs(rf.RewardButtons) do
                                Skin.QuestRewardTile(btnFrame)
                            end
                        end
                        if rf then
                            -- Same as the NPC window: strip the rings, THEN square.
                            -- Squaring alone left the gold coin wearing its border
                            -- while the currency tiles beside it were clean.
                            for _, keyName in ipairs({
                                "MoneyFrame",
                                "XPFrame",
                                "HonorFrame",
                                "SkillPointFrame",
                                "PlayerTitleFrame",
                            }) do
                                local subPanel = rf[keyName]
                                if subPanel then
                                    for _, ak in ipairs({
                                        "NameFrame",
                                        "IconBorder",
                                        "IconOverlay",
                                        "IconOverlay2",
                                        "IconBorder2",
                                        "Border",
                                    }) do
                                        local part = subPanel[ak]
                                        if
                                            part
                                            and part.SetAlpha
                                            and part.IsObjectType
                                            and part:IsObjectType("Texture")
                                        then
                                            part:SetAlpha(0)
                                        end
                                    end
                                    if subPanel.Icon then
                                        Skin.SquareIcon(subPanel.Icon, nil)
                                    elseif subPanel.GetRegions then
                                        local regs = { subPanel:GetRegions() }
                                        for ri = 1, #regs do
                                            local region = regs[ri]
                                            if
                                                region
                                                and region.IsObjectType
                                                and region:IsObjectType("Texture")
                                                and region:GetAlpha() > 0
                                            then
                                                Skin.SquareIcon(region, nil)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    for _, n in ipairs({
                        "QuestInfoDescriptionText",
                        "QuestInfoObjectivesText",
                        "QuestInfoGroupSize",
                    }) do
                        local fontStr = _G[n]
                        if fontStr and fontStr.SetTextColor then
                            fontStr:SetTextColor(1, 1, 1)
                        end
                    end
                    local of = _G.QuestInfoObjectivesFrame
                    if of and of.Objectives then
                        for _, object in ipairs(of.Objectives) do
                            if object and object.SetTextColor then
                                object:SetTextColor(1, 1, 1)
                            end
                        end
                    end
                end
                if not GetFFD(repDetail).questTextHook and type(_G.QuestInfo_Display) == "function" then
                    GetFFD(repDetail).questTextHook = true
                    hooksecurefunc("QuestInfo_Display", function(_, parentFrame)
                        -- MAP only (parent chain reaches QuestMapFrame):
                        -- QuestInfo_Display also drives the NPC quest window, which
                        -- must not be touched.
                        if not parentFrame then
                            return
                        end
                        local p, isMap = parentFrame, false
                        for _i = 1, 8 do
                            if p == questMap then
                                isMap = true
                                break
                            end
                            p = p.GetParent and p:GetParent()
                            if not p then
                                break
                            end
                        end
                        if not isMap then
                            return
                        end
                        StyleQuestText()
                        -- Re-assert next frame: Blizzard colors objectives after this call.
                        if C_Timer then
                            C_Timer.After(0, StyleQuestText)
                        end
                    end)
                end
                if questMap:IsShown() then
                    StyleQuestText()
                end
            end
            local dsf = _G.QuestMapDetailsScrollFrame
            if dsf and dsf.ScrollBar then
                Skin.ScrollBar(dsf.ScrollBar)
            end

            local co = questMap.QuestsFrame and questMap.QuestsFrame.CampaignOverview
            if co then
                if co.BorderFrame then
                    co.BorderFrame:SetAlpha(0)
                end
                Skin.FadeRegions(co)
                Skin.Register(co, true)
                if co.ScrollFrame and co.ScrollFrame.ScrollBar then
                    Skin.ScrollBar(co.ScrollFrame.ScrollBar)
                end
            end

            if questMap.QuestSessionManagement then
                Skin.FadeRegions(questMap.QuestSessionManagement)
                Skin.Register(questMap.QuestSessionManagement, true)
            end

            -- 11.1 side tabs (quests / events / map legend)
            for _, keyName in ipairs({ "QuestsTab", "EventsTab", "MapLegendTab" }) do
                SkinMapSideTab(questMap[keyName])
            end
            -- Chain seat: box edge flush with the window edge (measured once on the
            -- first laid-out show), gaps 8px tighter down the chain.
            local function SeatSideTabs()
                local gd2 = GetFFD(questMap)
                if gd2.sideSeated then
                    return
                end
                local qt = questMap.QuestsTab
                local glyphTex = qt and qt.Icon
                local qmR = questMap.GetRight and questMap:GetRight()
                local iL = glyphTex and glyphTex.GetLeft and glyphTex:GetLeft()
                if not qmR or not iL then
                    return
                end
                gd2.sideSeated = true
                local dx = math.floor((qmR - (iL - 5)) + 0.5) + 2
                if dx ~= 0 then
                    local pointCount = qt:GetNumPoints() or 0
                    local pts, success = {}, pointCount > 0
                    for idx = 1, pointCount do
                        local point, relTo, relPoint, posX, posY = qt:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, (posX or 0) + dx, posY or 0 }
                    end
                    if success then
                        qt:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            qt:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                end
                for _, k2 in ipairs({ "EventsTab", "MapLegendTab" }) do
                    local tabFrame = questMap[k2]
                    if tabFrame then
                        local td2 = GetFFD(tabFrame)
                        if not td2.gapAdj then
                            local point, relTo, relPoint, posX, posY = tabFrame:GetPoint(1)
                            if point then
                                td2.gapAdj = true
                                tabFrame:ClearAllPoints()
                                tabFrame:SetPoint(point, relTo, relPoint, posX or 0, (posY or 0) + 8)
                            end
                        end
                    end
                end
            end
            SeatSideTabs()
            if not GetFFD(questMap).sideSeatHook then
                GetFFD(questMap).sideSeatHook = true
                questMap:HookScript("OnShow", function()
                    if C_Timer then
                        C_Timer.After(0, SeatSideTabs)
                    else
                        SeatSideTabs()
                    end
                end)
            end

            local ev = questMap.EventsFrame
            if ev then
                -- Direct region fade also kills this pane's stray yellow box texture.
                Skin.FadeRegions(ev)
                Skin.Register(ev, true)
                if ev.TitleText then
                    Skin.Font(ev.TitleText)
                    Skin.White(ev.TitleText)
                end
                if ev.BorderFrame then
                    ev.BorderFrame:SetAlpha(0)
                end
                if ev.ScrollBox and ev.ScrollBox.Background then
                    ev.ScrollBox.Background:SetAlpha(0)
                end
                if ev.ScrollBar then
                    Skin.ScrollBar(ev.ScrollBar)
                end
                -- Row styling via the acquired-frame callback: headers get the
                -- house plate + white label, event tiles the flat white hover.
                if
                    ev.ScrollBox
                    and _G.ScrollUtil
                    and _G.ScrollUtil.AddAcquiredFrameCallback
                    and not GetFFD(ev).rowCb
                then
                    GetFFD(ev).rowCb = true
                    local function StyleEventRow(_, row, elementData)
                        if not row or type(elementData) ~= "table" then
                            return
                        end
                        local et = elementData.data and elementData.data.entryType
                        local regionData = GetFFD(row)
                        if et == 1 or et == 3 then
                            if row.Background and row.Background.SetAlpha then
                                row.Background:SetAlpha(0)
                            end
                            if not regionData.plate then
                                regionData.plate = SolidTex(row, "BACKGROUND", 1, 1, 1, 0.05)
                                regionData.plate:SetAllPoints(row)
                            end
                            if row.Label and row.Label.SetTextColor then
                                Skin.White(row.Label)
                            end
                        else
                            if row.Highlight and row.Highlight.SetColorTexture then
                                row.Highlight:SetColorTexture(1, 1, 1, 0.1)
                                row.Highlight:SetAllPoints(row)
                            end
                        end
                    end
                    pcall(_G.ScrollUtil.AddAcquiredFrameCallback, ev.ScrollBox, StyleEventRow, ev, true)
                end
            end

            local ml = questMap.MapLegend
            if ml then
                if ml.TitleText then
                    Skin.Font(ml.TitleText)
                    Skin.White(ml.TitleText)
                end
                if ml.BorderFrame then
                    ml.BorderFrame:SetAlpha(0)
                end
                local mls = ml.ScrollFrame
                if mls then
                    if mls.Background then
                        mls.Background:SetAlpha(0)
                    end
                    if mls.Center then
                        mls.Center:SetAlpha(0)
                    end
                    if mls.ScrollBar then
                        Skin.ScrollBar(mls.ScrollBar)
                    end
                end
            end
        end

        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    Skin.Restrip()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "worldmap",
        addons = { Blizzard_WorldMap = true },
        apply = Skin_WorldMap,
    })
end

-------------------------------------------------------------------------------
--  Micro Menu & Bags. The glyph IS the button's Normal/Pushed/Disabled atlas,
--  so it is never hidden: raised plate goes, bevel ring cropped off, a flat
--  box frames it. Micro buttons are SECURE, so every visual write is
--  combat-guarded. Blizzard container frames are skipped entirely when the
--  CludesUI Bags addon is active (they never show).
-------------------------------------------------------------------------------
do
    local MICRO_BUTTONS = {
        "CharacterMicroButton",
        "ProfessionMicroButton",
        "PlayerSpellsMicroButton",
        "AchievementMicroButton",
        "QuestLogMicroButton",
        "GuildMicroButton",
        "LFDMicroButton",
        "CollectionsMicroButton",
        "EJMicroButton",
        "StoreMicroButton",
        "MainMenuMicroButton",
        "HelpMicroButton",
        "HousingMicroButton",
    }
    -- WoW Forever keeps several micro buttons retail folded away or renamed (spellbook
    -- and talents split out, socials and PvP as their own buttons). Add them so the
    -- Forever pass skins the whole row; missing/forbidden buttons are skipped per-button.
    if CludesUI.IS_FOREVER then
        for _, n in ipairs({
            "SpellbookMicroButton",
            "TalentMicroButton",
            "SocialsMicroButton",
            "PVPMicroButton",
            "LegacyMicroButton",
        }) do
            MICRO_BUTTONS[#MICRO_BUTTONS + 1] = n
        end
    end
    local MICRO_DECO =
        { "Background", "PushedBackground", "FlashBorder", "Shadow", "PushedShadow", "Border", "Backdrop" }
    local MICRO_TRIM = 0.08
    local MICRO_INSET = 1
    local MICRO_GAP = 2
    local MICRO_BG_A = 0.45

    local function TrimMicroTex(texture, tabBox)
        if not texture or not texture.SetTexCoord then
            return
        end
        if texture.SetDrawLayer then
            texture:SetDrawLayer("ARTWORK")
        end
        if MICRO_TRIM > 0 then
            texture:SetTexCoord(MICRO_TRIM, 1 - MICRO_TRIM, MICRO_TRIM, 1 - MICRO_TRIM)
        end
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", tabBox, "TOPLEFT", MICRO_INSET, -MICRO_INSET)
        texture:SetPoint("BOTTOMRIGHT", tabBox, "BOTTOMRIGHT", -MICRO_INSET, MICRO_INSET)
    end

    local function SkinMicroButtonInner(btnFrame)
        for _, keyName in ipairs(MICRO_DECO) do
            local region = btnFrame[keyName]
            if region and region.SetAlpha then
                region:SetAlpha(0)
            end
        end
        local skinData = GetFFD(btnFrame)
        if not skinData.box then
            local tabBox = CreateFrame("Frame", nil, btnFrame)
            tabBox:SetPoint("TOPLEFT", MICRO_GAP, -MICRO_GAP)
            tabBox:SetPoint("BOTTOMRIGHT", -MICRO_GAP, MICRO_GAP)
            local bgTex = btnFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
            bgTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, MICRO_BG_A)
            bgTex:SetPoint("TOPLEFT", tabBox, "TOPLEFT", 0, 0)
            bgTex:SetPoint("BOTTOMRIGHT", tabBox, "BOTTOMRIGHT", 0, 0)
            Skin.AddBorder(tabBox)
            skinData.box, skinData.bg = tabBox, bgTex
            local highlight = btnFrame.GetHighlightTexture and btnFrame:GetHighlightTexture()
            if highlight and highlight.SetColorTexture then
                highlight:SetColorTexture(1, 1, 1, 0.1)
                if highlight.SetTexCoord then
                    highlight:SetTexCoord(0, 1, 0, 1)
                end
                highlight:ClearAllPoints()
                highlight:SetPoint("TOPLEFT", tabBox, "TOPLEFT", 0, 0)
                highlight:SetPoint("BOTTOMRIGHT", tabBox, "BOTTOMRIGHT", 0, 0)
            end
        end
        if btnFrame.GetNormalTexture then
            TrimMicroTex(btnFrame:GetNormalTexture(), skinData.box)
        end
        if btnFrame.GetPushedTexture then
            TrimMicroTex(btnFrame:GetPushedTexture(), skinData.box)
        end
        if btnFrame.GetDisabledTexture then
            TrimMicroTex(btnFrame:GetDisabledTexture(), skinData.box)
        end
        if btnFrame.Portrait then
            TrimMicroTex(btnFrame.Portrait, skinData.box)
        end
    end

    -- Named wrapper so the hot UpdateMicroButtons path allocates no closure per call (13 buttons x every fire = real GC churn otherwise).
    local function SkinMicroButton(btnFrame)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        pcall(SkinMicroButtonInner, btnFrame)
    end

    local _microHook = false
    local function Skin_MicroMenu()
        if InCombatLockdown() then
            return
        end
        for _, label in ipairs(MICRO_BUTTONS) do
            SkinMicroButton(_G[label])
        end
        -- WoW Forever's MicroMenu keeps a Blizzard container strip (BackgroundArt +
        -- BorderArt); on retail the CludesUI Bags addon hides the container, so it
        -- never shows. Fade that art so the flat buttons do not sit inside an ornate
        -- frame. Alpha only -- never :Hide() the Edit-Mode-owned container.
        if CludesUI.IS_FOREVER and _G.MicroMenu then
            local maxMinBtn = _G.MicroMenu
            if maxMinBtn.BackgroundArt and maxMinBtn.BackgroundArt.SetAlpha then
                maxMinBtn.BackgroundArt:SetAlpha(0)
            end
            if maxMinBtn.BorderArt and maxMinBtn.BorderArt.SetAlpha then
                maxMinBtn.BorderArt:SetAlpha(0)
            end
        end
        if not _microHook and _G.UpdateMicroButtons then
            _microHook = true
            -- UpdateMicroButtons fires several times per frame on routine events:
            -- debounce collapses each burst into ONE repaint instead of re-trimming all 13 buttons per fire.
            local repaint = Skin.Debounce(function()
                if InCombatLockdown() then
                    return
                end
                for _, label in ipairs(MICRO_BUTTONS) do
                    SkinMicroButton(_G[label])
                end
            end)
            hooksecurefunc("UpdateMicroButtons", repaint)
        end
    end

    -- Registered on both clients. On WoW Forever this also covers the legacy micro
    -- buttons appended to MICRO_BUTTONS above, so the whole row matches the house look.
    Skin.RegisterWindow({
        key = "micromenu",
        apply = function()
            -- Micro buttons are secure: if this runs mid-combat (reload during a fight), defer the pass to end of combat.
            if InCombatLockdown() then
                mod.CombatQueue.Defer("MicroMenuSkin", function()
                    pcall(Skin_MicroMenu)
                end)
                return
            end
            pcall(Skin_MicroMenu)
        end,
    })
end

-------------------------------------------------------------------------------
--  Dressing Room (DressUpFrame). Chrome + action buttons; the 3D model scene
--  and custom-set detail panel stay stock content.
-------------------------------------------------------------------------------
do
    local _dressHooked = false
    local function Skin_DressUp()
        local win = _G.DressUpFrame
        if not win then
            return
        end
        Skin.Shell("dressup", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "DressUpFrame")
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        for _, keyName in ipairs({ "Bg", "Background" }) do
            if win[keyName] and win[keyName].SetAlpha then
                win[keyName]:SetAlpha(0)
            end
        end
        -- Window backdrop is the global DressUpFrameBg, not a parentKey.
        if _G.DressUpFrameBg and _G.DressUpFrameBg.SetAlpha then
            _G.DressUpFrameBg:SetAlpha(0)
        end
        -- Model sits inside DressUpFrameInset, which carries its OWN backdrop (Bg)/border (NineSlice), separate from the window's.
        local inset = win.Inset or _G.DressUpFrameInset
        if inset then
            Skin.Inset(inset)
        end
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or _G.DressUpFrameTitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end
        -- 3D model area's backdrop+border sit on CHILD frames the shell's region
        -- fade cannot reach (textures directly on the window only). Fade the flat
        -- model background and model scene's own textures/border; the model renders via actors, so it stays.
        if win.ModelBackground and win.ModelBackground.SetAlpha then
            win.ModelBackground:SetAlpha(0)
        end
        local ms = win.ModelScene
        if ms then
            Skin.FadeRegions(ms)
            if ms.NineSlice then
                Skin.FadeNineSlice(ms.NineSlice)
            end
            Skin.Register(ms, true)
        end
        -- Max/Min button: spellbook-style +/- glyph (collapse/expand chevrons).
        local maxMinBtn = win.MaximizeMinimizeFrame
        if maxMinBtn then
            SkinProfMaxMin(maxMinBtn.MinimizeButton, "UI-QuestTrackerButton-Secondary-Collapse")
            SkinProfMaxMin(maxMinBtn.MaximizeButton, "UI-QuestTrackerButton-Secondary-Expand")
        end
        -- Action buttons: flat treatment + white labels. Reset/Cancel are globals, Link/Toggle are parentKeys.
        local function SkinBtn(button)
            if button then
                Skin.Button(button)
                Skin.WhiteButtonLabel(button)
            end
        end
        SkinBtn(_G.DressUpFrameResetButton)
        SkinBtn(_G.DressUpFrameCancelButton)
        SkinBtn(win.LinkButton)
        -- ToggleCustomSetDetailsButton (opens the appearance list) stays fully
        -- stock. Saved-outfit dropdown 10% smaller and 4px down (child save button
        -- rides along), save button 3px taller. Blizzard re-anchors the dropdown
        -- per view (minimize/maximize), so re-apply the offset on every SetPoint (reentry-guarded), not once.
        local dropdown = win.CustomSetDropdown or _G.DressUpFrameCustomSetDropdown
        if dropdown then
            Skin.Dropdown(dropdown)
            local ddd = GetFFD(dropdown)
            if not ddd.scaled then
                ddd.scaled = true
                dropdown:SetScale(0.9)
            end
            if not ddd.shiftHook then
                ddd.shiftHook = true
                local guard = false
                hooksecurefunc(dropdown, "SetPoint", function(self)
                    if guard then
                        return
                    end
                    guard = true
                    local point, relTo, relPoint, posX, posY = self:GetPoint(1)
                    if point then
                        self:ClearAllPoints()
                        self:SetPoint(point, relTo, relPoint, posX or 0, (posY or 0) - 4)
                    end
                    guard = false
                end)
                local point, relTo, relPoint, posX, posY = dropdown:GetPoint(1)
                if point then
                    dropdown:SetPoint(point, relTo, relPoint, posX or 0, posY or 0)
                end
            end
            local scrollBar = dropdown.SaveButton
            if scrollBar then
                SkinBtn(scrollBar)
                local sbd = GetFFD(scrollBar)
                if not sbd.heightBumped and scrollBar.GetHeight then
                    sbd.heightBumped = true
                    scrollBar:SetHeight(scrollBar:GetHeight() + 3)
                end
            end
        end
        -- Outfit selection list: fade its framed chrome, theme the scrollbar.
        local ssp = win.SetSelectionPanel
        if ssp then
            if ssp.NineSlice then
                Skin.FadeNineSlice(ssp.NineSlice)
            end
            if ssp.Bg and ssp.Bg.SetAlpha then
                ssp.Bg:SetAlpha(0)
            end
            Skin.ScrollBarsIn(ssp)
        end
        -- Custom-set details panel: replace ONLY its border. Fade OVERLAY/BORDER
        -- layer art but spare the named black/class backdrops by identity, then
        -- seat a themed border sized to the backdrop so it hugs content, not the padded frame edge.
        local dp = win.CustomSetDetailsPanel
        if dp then
            local dropdown = GetFFD(dp)
            if not dropdown.bordered then
                dropdown.bordered = true
                local keepSet = {}
                if dp.BlackBackground then
                    keepSet[dp.BlackBackground] = true
                end
                if dp.ClassBackground then
                    keepSet[dp.ClassBackground] = true
                end
                local regionList = { dp:GetRegions() }
                for idx = 1, #regionList do
                    local region = regionList[idx]
                    if region and not keepSet[region] and region.IsObjectType and region:IsObjectType("Texture") then
                        local layer = region:GetDrawLayer()
                        if layer == "OVERLAY" or layer == "BORDER" then
                            region:SetAlpha(0)
                        end
                    end
                end
                if dp.NineSlice then
                    Skin.FadeNineSlice(dp.NineSlice)
                end
                local bgTex = dp.BlackBackground or dp.ClassBackground
                if bgTex then
                    local owner = CreateFrame("Frame", nil, dp)
                    owner:SetAllPoints(bgTex)
                    dropdown.borderHost = owner
                    Skin.AddBorder(owner)
                end
            end
            Skin.ScrollBarsIn(dp)
        end
        -- Blizzard re-shows window chrome (NineSlice/Bg/model backdrop) on every open, so re-run the FULL skin on show, not just a Restrip.
        if not _dressHooked then
            _dressHooked = true
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_DressUp()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "dressup",
        apply = Skin_DressUp,
    })
end

-------------------------------------------------------------------------------
--  Transmogrifier (TransmogFrame). Chrome + action controls; the model,
--  transmog slot buttons and embedded appearance list stay stock content.
-------------------------------------------------------------------------------
do
    local _transmogHooked = false
    local function Skin_Transmog()
        local win = _G.TransmogFrame
        if not win then
            return
        end
        Skin.Shell("transmog", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "TransmogFrame") -- close + paging + controls
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if win.Inset then
            Skin.Inset(win.Inset)
        end
        for _, keyName in ipairs({ "Bg", "Background" }) do
            if win[keyName] and win[keyName].SetAlpha then
                win[keyName]:SetAlpha(0)
            end
        end
        if _G.TransmogFrameBg and _G.TransmogFrameBg.SetAlpha then
            _G.TransmogFrameBg:SetAlpha(0)
        end
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or _G.TransmogFrameTitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end
        if win.ApplyButton then
            Skin.Button(win.ApplyButton)
            Skin.WhiteButtonLabel(win.ApplyButton)
        end
        local optionsData = win.OutfitDropdown
        if optionsData then
            Skin.Dropdown(optionsData)
            if optionsData.SaveButton then
                Skin.Button(optionsData.SaveButton)
                Skin.WhiteButtonLabel(optionsData.SaveButton)
            end
        end
        -- Save Outfit button: flat treatment, but the label mirrors the native
        -- enabled/disabled state (white when clickable, gray when not); a plain
        -- WhiteButtonLabel would leave a disabled button reading as active.
        local oc = win.OutfitCollection
        if oc and oc.SaveOutfitButton then
            local button = oc.SaveOutfitButton
            Skin.Button(button)
            -- Borderless + 2px shorter (this button only).
            local PPb = CludesUI.PP
            if PPb and PPb.GetBorders and PPb.HideBorder and PPb.GetBorders(button) then
                PPb.HideBorder(button)
            end
            local bd0 = GetFFD(button)
            if not bd0.slimmed then
                bd0.slimmed = true
                local hgt = button:GetHeight()
                if hgt and hgt > 2 then
                    button:SetHeight(hgt - 2)
                end
            end
            local labelText = button.Text or (button.GetFontString and button:GetFontString())
            if labelText then
                local function reflect()
                    if button:IsEnabled() then
                        Skin.White(labelText)
                    else
                        labelText:SetTextColor(0.5, 0.5, 0.5)
                    end
                end
                local buttonData = GetFFD(button)
                if not buttonData.stateHook then
                    buttonData.stateHook = true
                    button:HookScript("OnEnable", reflect)
                    button:HookScript("OnDisable", reflect)
                end
                reflect()
            end
        end
        -- Right-side appearance browser: flatten the tab headers (standard
        -- lighter-active look), left-align the Sources filter label on the items
        -- and sets views, and raise the header row above stock.
        local wc = win.WardrobeCollection
        if wc then
            if wc.TabHeaders then
                local children = { wc.TabHeaders:GetChildren() }
                for idx = 1, #children do
                    local tabBtn = children[idx]
                    if tabBtn and tabBtn.GetObjectType and tabBtn:GetObjectType() == "Button" then
                        Skin.Tab(tabBtn)
                        -- Blizzard's active-line effect is a SelectedHighlight
                        -- CHILD frame that the tab region sweep cannot reach;
                        -- container alpha suppresses it and its textures.
                        if tabBtn.SelectedHighlight and tabBtn.SelectedHighlight.SetAlpha then
                            tabBtn.SelectedHighlight:SetAlpha(0)
                        end
                    end
                end
                local th = wc.TabHeaders
                if not GetFFD(th).raised then
                    local pointCount = th:GetNumPoints() or 0
                    local pts, success = {}, pointCount > 0
                    for idx = 1, pointCount do
                        local point, relTo, relPoint, posX, posY = th:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + 6 }
                    end
                    if success then
                        GetFFD(th).raised = true
                        th:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            th:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                end
            end
            local tc = wc.TabContent
            if tc then
                for _, keyName in ipairs({ "ItemsFrame", "SetsFrame" }) do
                    local subPanel = tc[keyName]
                    if subPanel and subPanel.FilterButton then
                        LeftAlignFilterLabel(subPanel.FilterButton)
                    end
                end
                local csf = tc.CustomSetsFrame
                if csf and csf.NewCustomSetButton then
                    Skin.Button(csf.NewCustomSetButton)
                    Skin.WhiteButtonLabel(csf.NewCustomSetButton)
                end
                local sif = tc.SituationsFrame
                if sif and sif.DefaultsButton then
                    Skin.Button(sif.DefaultsButton)
                    Skin.WhiteButtonLabel(sif.DefaultsButton)
                end
                -- Swap Blizzard's content border for the themed one. Frame rect runs
                -- a few px past the visible list, but its Background region spans
                -- the true content area, so the border seats on a host pinned to that.
                local buttonData = tc.Border
                if buttonData then
                    if buttonData.IsObjectType and buttonData:IsObjectType("Texture") then
                        buttonData:SetAlpha(0)
                    else
                        Skin.FadeRegions(buttonData)
                        Skin.Register(buttonData, true)
                        if buttonData.SetAlpha then
                            buttonData:SetAlpha(0)
                        end
                    end
                end
                local tcd = GetFFD(tc)
                if not tcd.borderHost then
                    local owner = CreateFrame("Frame", nil, tc)
                    owner:SetAllPoints(tc.Background or tc)
                    tcd.borderHost = owner
                    Skin.AddBorder(owner)
                end
            end
        end
        -- Blizzard re-shows the window chrome on open (as with DressUpFrame), so
        -- re-run the full skin on show.
        if not _transmogHooked then
            _transmogHooked = true
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_Transmog()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "transmog",
        addons = { Blizzard_Transmog = true },
        apply = Skin_Transmog,
    })
end

-------------------------------------------------------------------------------
--  Merchant (MerchantFrame). Shell + tabs + item tiles as flat cards (mail-row
--  treatment); repair/sell-junk icon buttons and the buyback money display stay stock content.
-------------------------------------------------------------------------------
do
    -- Hide Blizzard's native pagination and 10-slot grid permanently, via the
    -- achievements-pack Kill pattern: a reentry-safe hooksecurefunc re-hiding on
    -- every Blizzard Show (MerchantFrame_Update re-Shows tiles each pass), NEVER a
    -- method overwrite on a Blizzard frame table. Registry lives on WSkin so re-runs of Skin_Merchant cannot double-hook.
    local function KillFrameShow(widget)
        if not widget then
            return
        end
        local killed = Skin._merchantKilledShow
        if not killed then
            killed = setmetatable({}, { __mode = "k" })
            Skin._merchantKilledShow = killed
        end
        if killed[widget] then
            widget:Hide()
            return
        end
        killed[widget] = true
        widget:Hide()
        hooksecurefunc(widget, "Show", function(self)
            self:Hide()
        end)
    end

    local function HideNativeMerchantGrid()
        for idx = 1, 12 do
            local entry = _G["MerchantItem" .. idx]
            if entry then
                entry:SetAlpha(0)
                KillFrameShow(entry)
            end
        end

        local controls = {
            _G.MerchantPrevPageButton,
            _G.MerchantNextPageButton,
            _G.MerchantPageText,
        }
        for _, ctrl in ipairs(controls) do
            KillFrameShow(ctrl)
        end
    end

    -- Build the ScrollFrame (once).
    local function CreateMerchantScrollList(parent)
        local scrollFrame =
            CreateFrame("ScrollFrame", "WSkinMerchantScrollFrame", parent, "UIPanelScrollFrameTemplate")
        -- Fits inside MerchantFrame, leaving room for repair/buyback buttons.
        scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -70)
        scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -32, 80)

        local childFrame = CreateFrame("Frame", "WSkinMerchantScrollChild", scrollFrame)
        childFrame:SetPoint("TOPLEFT")
        childFrame:SetPoint("TOPRIGHT")
        childFrame:SetSize(1, 1)
        scrollFrame:SetScrollChild(childFrame)

        scrollFrame.rows = {}
        return scrollFrame, childFrame
    end

    -- Same as the default UI's version, with frameName pointed at our own buttons.
    function CUI_MerchantFrame_UpdateAltCurrency(index, indexOnPage, canAfford, prefixText)
        local itemCount = GetMerchantItemCostInfo(index)
        local frameName = (prefixText or "CUI_MerchantItem") .. indexOnPage .. "AltCurrencyFrame"
        local usedCurrencies = 0
        local width = 0

        -- update Alt Currency Frame with itemValues
        if itemCount > 0 then
            for idx = 1, MAX_ITEM_COST do
                local itemTexture, itemValue, itemLink = GetMerchantItemCostItem(index, idx)
                if itemTexture then
                    usedCurrencies = usedCurrencies + 1
                    local btnFrame = _G[frameName .. "Item" .. usedCurrencies]
                    btnFrame.index = index
                    btnFrame.item = idx
                    btnFrame.itemLink = itemLink
                    AltCurrencyFrame_Update(
                        frameName .. "Item" .. usedCurrencies,
                        itemTexture,
                        itemValue,
                        canAfford
                    )
                    width = width + btnFrame:GetWidth()
                    if usedCurrencies > 1 then
                        -- button spacing;
                        width = width + 4
                    end
                    btnFrame:Show()
                end
            end
            for idx = usedCurrencies + 1, MAX_ITEM_COST do
                _G[frameName .. "Item" .. idx]:Hide()
            end
        else
            for idx = 1, MAX_ITEM_COST do
                _G[frameName .. "Item" .. idx]:Hide()
            end
        end
        return width
    end

    local function SkinMerchantListItem(entry)
        if not entry or entry:IsForbidden() then
            return
        end

        entry.bg = entry.bg or entry:CreateTexture(nil, "BACKGROUND", nil, -7)
        entry.bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
        entry.bg:SetPoint("TOPLEFT", 0, 0)
        entry.bg:SetPoint("BOTTOMRIGHT", 0, 0)
        Skin.AddBorder(entry)

        entry.SlotTexture:SetSize(entry:GetHeight(), entry:GetHeight())
        entry.SlotTexture:ClearAllPoints()
        entry.SlotTexture:SetPoint("LEFT", entry, "LEFT", 0, 0)
        entry.SlotTexture:SetTexCoord(0, 1, 0, 1)

        entry.highlight = entry.highlight or entry.ItemButton:CreateTexture(nil, "HIGHLIGHT")
        entry.highlight:SetColorTexture(1, 1, 1, 0.1)
        entry.highlight:SetAllPoints(entry.bg)

        -- Buy button spans the whole row in list mode.
        entry.ItemButton:SetSize(entry:GetWidth(), entry:GetHeight())
        entry.ItemButton.PushedTexture:SetTexture(nil)
        entry.ItemButton.NormalTexture:SetTexture(nil)
        entry.ItemButton.HighlightTexture:SetTexture(entry.highlight)

        -- Quality ring: STRIPPED, not repositioned onto the icon as it used to be.
        -- It is ROUNDED, and in list mode it was being stretched to the full icon
        -- square, so the round art was at its most obvious here.
        --
        -- The rarity comes back as a SQUARE border reading that same ring. Anchored
        -- to SlotTexture because THAT is the icon in list mode -- the row repurposes
        -- Blizzard's empty-slot art (`row.SlotTexture:SetTexture(texture)` in
        -- UpdateCustomMerchantList) rather than using the item button's own icon.
        --
        -- Registered against the ItemButton, so the color is read from
        -- ItemButton.IconBorder and the repaint hook lands on the frame Blizzard
        -- actually calls SetItemButtonQuality on.
        entry.ItemButton.IconBorder:SetAlpha(0)
        Skin.QualityBorder(entry.ItemButton, entry.SlotTexture)
        entry.ItemButton.IconOverlay:ClearAllPoints()
        entry.ItemButton.IconOverlay:SetPoint("CENTER", entry.SlotTexture, "CENTER", 0, 0)
        entry.ItemButton.IconOverlay:SetSize(entry.SlotTexture:GetWidth(), entry.SlotTexture:GetHeight())

        -- Quest item overlay, repositioned onto the icon.
        entry.ItemButton.IconQuestTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG)
        entry.ItemButton.IconQuestTexture:ClearAllPoints()
        entry.ItemButton.IconQuestTexture:SetPoint("CENTER", entry.SlotTexture, "CENTER", 0, 0)
        entry.ItemButton.IconQuestTexture:SetSize(entry.SlotTexture:GetWidth(), entry.SlotTexture:GetHeight())

        -- Item stack: bottom right of the icon.
        entry.ItemButton.Count:ClearAllPoints()
        entry.ItemButton.Count:SetPoint("BOTTOMRIGHT", entry.SlotTexture, "BOTTOMRIGHT", -2, 2)

        -- Item stock: top left of the icon.
        entry.ItemButton.Stock:ClearAllPoints()
        entry.ItemButton.Stock:SetPoint("TOPLEFT", entry.SlotTexture, "TOPLEFT", 2, -2)

        -- Item name. Its position is set dynamically in UpdateCustomMerchantList so
        -- it never collides with the money or alt-currency frame; overlong text is
        -- truncated with an ellipsis.
        _G[entry:GetName() .. "NameFrame"]:Hide()
        entry.Name:ClearAllPoints()
        entry.Name:SetPoint("LEFT", entry.SlotTexture, "RIGHT", 10, 0)
        entry.Name:SetMaxLines(1)
        entry.Name:SetJustifyH("LEFT")
    end

    local function UpdateCustomMerchantList(scrollFrame, childFrame)
        local isBuyback = MerchantFrame.selectedTab == 2
        local numItems = isBuyback and GetNumBuybackItems() or GetMerchantNumItems()

        local rowHeight = (CludesUIDB and CludesUIDB.merchantListRowHeight) or 32
        local rowSpacing = 4
        local playerMoney = GetMoney()
        local MAX_MONEY_DISPLAY_WIDTH = 120

        for idx = 1, numItems do
            local row = scrollFrame.rows[idx]
            if not row then
                row = CreateFrame("Button", "CUI_MerchantItem" .. idx, childFrame, "MerchantItemTemplate")
                row:SetSize(scrollFrame:GetWidth(), rowHeight)
                if idx == 1 then
                    row:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, 0)
                else
                    row:SetPoint("TOPLEFT", scrollFrame.rows[idx - 1], "BOTTOMLEFT", 0, -rowSpacing)
                end

                SkinMerchantListItem(row)
                scrollFrame.rows[idx] = row
            end

            local label, texture, price, quantity, numAvailable, isPurchasable, isUsable, extendedCost, isBound, isQuestStartItem

            if isBuyback then
                label, texture, price, quantity, numAvailable, isUsable, isBound = GetBuybackItemInfo(idx)
                isPurchasable = true -- buyback items are always purchasable
            else
                local details = C_MerchantFrame.GetItemInfo(idx)
                if details then
                    if details.currencyID then
                        label, texture, numAvailable = CurrencyContainerUtil.GetCurrencyContainerInfo(
                            details.currencyID,
                            details.numAvailable,
                            details.name,
                            details.texture,
                            nil
                        )
                    else
                        label, texture, numAvailable = details.name, details.texture, details.numAvailable
                    end

                    price, quantity, isPurchasable, isUsable, extendedCost, isQuestStartItem =
                        details.price,
                        details.stackCount,
                        details.isPurchasable,
                        details.isUsable,
                        details.hasExtendedCost,
                        details.isQuestStartItem
                end
            end

            if label then
                local itemLink = isBuyback and GetBuybackItemLink(idx) or GetMerchantItemLink(idx)

                row.Name:SetText(label)
                row.SlotTexture:SetTexture(texture)

                row.ItemButton:SetID(idx)
                row.ItemButton.link = itemLink
                row.ItemButton.name = label
                row.ItemButton.texture = texture
                row.ItemButton.price = ((extendedCost and (price > 0)) or not extendedCost) and price or nil
                row.ItemButton.extendedCost = (extendedCost and type(price) == "number") or nil
                row.ItemButton.hasItem = true
                row.ItemButton.showNonrefundablePrompt = not C_MerchantFrame.IsMerchantItemRefundable(idx)

                -- Text color and reagent quality overlay.
                MerchantFrameItem_UpdateQuality(row, row.ItemButton.link, isBound)

                SetItemButtonCount(row.ItemButton, quantity)
                SetItemButtonStock(row.ItemButton, numAvailable)

                if isQuestStartItem then
                    row.ItemButton.IconQuestTexture:Show()
                else
                    row.ItemButton.IconQuestTexture:Hide()
                end

                -- Money & currency cost.
                local moneyFrame = _G["CUI_MerchantItem" .. idx .. "MoneyFrame"]
                local altCurrencyFrame = _G["CUI_MerchantItem" .. idx .. "AltCurrencyFrame"]
                local canAfford = true
                if isBuyback then
                    canAfford = playerMoney >= price
                else
                    canAfford = CanAffordMerchantItem(idx)
                end

                -- Reset dynamic anchors to prevent layout conflicts.
                row.Name:ClearAllPoints()
                row.Name:SetPoint("LEFT", row.SlotTexture, "RIGHT", 10, 0)
                moneyFrame:ClearAllPoints()
                altCurrencyFrame:ClearAllPoints()

                if extendedCost and (price <= 0) then
                    -- Case 1: Alt currency only
                    local altCurrencyWidth = CUI_MerchantFrame_UpdateAltCurrency(idx, idx, canAfford)
                    altCurrencyFrame:SetWidth(altCurrencyWidth)

                    altCurrencyFrame:SetPoint("RIGHT", row, "RIGHT", -10, 0)

                    altCurrencyFrame:Show()
                    moneyFrame:Hide()

                    row.Name:SetPoint("RIGHT", altCurrencyFrame, "LEFT", -10, 0)
                elseif extendedCost and (price > 0) then
                    -- Case 2: Both Money and Alt currency
                    local altCurrencyWidth = CUI_MerchantFrame_UpdateAltCurrency(idx, idx, canAfford)
                    altCurrencyFrame:SetWidth(altCurrencyWidth)

                    MoneyFrame_SetMaxDisplayWidth(moneyFrame, MAX_MONEY_DISPLAY_WIDTH - altCurrencyWidth)
                    MoneyFrame_Update(moneyFrame:GetName(), price)

                    local color = (canAfford == false) and "gray" or nil
                    SetMoneyFrameColor(moneyFrame:GetName(), color)

                    -- altCurrencyWidth can be 0 (no alt-currency cost) even when
                    -- hasExtendedCost is true: fall back to the case 3 anchors.
                    if altCurrencyWidth > 0 then
                        -- Both exist: anchor money to alt currency.
                        altCurrencyFrame:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                        moneyFrame:SetPoint("RIGHT", altCurrencyFrame, "LEFT", -5, 0)
                        row.Name:SetPoint("RIGHT", altCurrencyFrame, "LEFT", -10, 0)
                        altCurrencyFrame:Show()
                    else
                        -- Money only: fall back to case 3.
                        moneyFrame:SetPoint("RIGHT", row, "RIGHT", 3, 0)
                        row.Name:SetPoint("RIGHT", moneyFrame, "LEFT", -10, 0)
                        altCurrencyFrame:Hide()
                    end
                    moneyFrame:Show()
                else
                    -- Case 3: Money only
                    MoneyFrame_SetMaxDisplayWidth(moneyFrame, MAX_MONEY_DISPLAY_WIDTH)
                    MoneyFrame_Update(moneyFrame:GetName(), price)

                    local color = (canAfford == false) and "gray" or nil
                    SetMoneyFrameColor(moneyFrame:GetName(), color)

                    moneyFrame:SetPoint("RIGHT", row, "RIGHT", 3, 0)

                    altCurrencyFrame:Hide()
                    moneyFrame:Show()

                    row.Name:SetPoint("RIGHT", moneyFrame, "LEFT", -10, 0)
                end

                local merchantItemID = GetMerchantItemID(idx)
                local isHeirloom = merchantItemID and C_Heirloom.IsItemHeirloom(merchantItemID)
                local isKnownHeirloom = isHeirloom and C_Heirloom.PlayerHasHeirloom(merchantItemID)

                local redTint = (not isUsable and not isHeirloom) or (not isBuyback and not isPurchasable)

                -- Fade if not usable / affordable / an already-known heirloom.
                row.SlotTexture:SetDesaturated(not isBuyback and isKnownHeirloom)
                if not isBuyback and (numAvailable == 0 or isKnownHeirloom) then
                    if redTint then
                        row.SlotTexture:SetVertexColor(0.5, 0, 0)
                    else
                        row.SlotTexture:SetVertexColor(0.5, 0.5, 0.5)
                    end
                elseif redTint then
                    row.SlotTexture:SetVertexColor(1, 0, 0)
                else
                    row.SlotTexture:SetVertexColor(1, 1, 1)
                end

                row:Show()
            else
                row:Hide()
            end
        end

        for idx = numItems + 1, #scrollFrame.rows do
            scrollFrame.rows[idx]:Hide()
        end
    end

    -- Options toggle entry point: re-sync row height.
    CludesUI._Merchant_RefreshRowHeight = function()
        local win = _G.MerchantFrame
        if not win then
            return
        end
        if not CludesUIDB.merchantShowAsList or not (win.wSkinScrollFrame and win.wSkinScrollChild) then
            return
        end

        local rowHeight = (CludesUIDB and CludesUIDB.merchantListRowHeight) or 32
        -- Rows are cached, so resize each existing one; rows created later pick up
        -- the new height by default.
        for _, row in ipairs(win.wSkinScrollFrame.rows or {}) do
            row:SetHeight(rowHeight)
            SkinMerchantListItem(row)
        end

        -- Force a full update when changed while the merchant frame is open.
        if win:IsVisible() then
            UpdateCustomMerchantList(win.wSkinScrollFrame, win.wSkinScrollChild)
        end
    end

    -- Vendor item tile: parchment gone, flat card, white name, squared icon.
    local function SkinMerchantTile(entry)
        if not entry or entry:IsForbidden() then
            return
        end
        local skinData = GetFFD(entry)
        if not skinData.bg then
            Skin.FadeRegions(entry)
            local bgTex = entry:CreateTexture(nil, "BACKGROUND", nil, -7)
            bgTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
            bgTex:SetPoint("TOPLEFT", 2, -1)
            bgTex:SetPoint("BOTTOMRIGHT", -2, 1)
            skinData.bg = bgTex
            Skin.AddBorder(entry)
        end
        local label = entry.GetName and entry:GetName()
        -- Blizzard repaints the slot/tile art per page flip; re-fade each pass,
        -- sparing our card fill.
        local keepSet = { [skinData.bg] = true }
        Skin.FadeRegions(entry, keepSet)
        local nameFS = entry.Name or (label and _G[label .. "Name"])
        if nameFS then
            -- Font AND color untouched, so Blizzard's item-quality coloring holds;
            -- only the 2-line wrap/truncate is applied.
            if nameFS.SetWordWrap then
                nameFS:SetWordWrap(true)
            end
            if nameFS.SetMaxLines then
                nameFS:SetMaxLines(2)
            end
        end
        local btnFrame = entry.ItemButton or (label and _G[label .. "ItemButton"])
        -- true: vendor tiles take the square RARITY border. Mail, which shares this
        -- helper, keeps Blizzard's rounded ring.
        if btnFrame then
            SkinMailItemButton(btnFrame, true)
        end

        -- CENTRE THE ICON IN THE ROW.
        --
        -- MerchantItemTemplate is 44px tall and anchors its ItemButton TOPLEFT to
        -- the row, but the button is only ~37px -- so the icon sits against the top
        -- with a 7px gap underneath, about 3-4px high of centre. Blizzard's slot
        -- and name-plate art hid that; the flat card this pack draws spans the full
        -- row, so the icon reads as top-heavy against it.
        --
        -- Re-anchored to LEFT rather than nudged by a fixed offset, so it stays
        -- centred whatever height the row ends up. Done ONCE -- the tiles are
        -- re-skinned on every page flip and re-anchoring per pass is pointless.
        if btnFrame and btnFrame.SetPoint then
            local buttonData = GetFFD(btnFrame)
            if not buttonData.rowCentred then
                buttonData.rowCentred = true
                btnFrame:ClearAllPoints()
                btnFrame:SetPoint("LEFT", entry, "LEFT", 0, 0)
            end
        end
    end

    -- Lift a tile's currency display 6px above Blizzard's seat. Blizzard re-anchors
    -- these inside MerchantFrame_Update (depends on price vs extended cost), wiping
    -- a one-shot capture per update: hook SetPoint and re-apply relative to the
    -- LIVE just-set position, SYNCHRONOUSLY (deferring a frame renders at
    -- Blizzard's spot then visibly shifts). Single-anchor, so the reentry guard alone prevents a double-lift.
    local function LiftMerchantCurrency(found)
        if not found or GetFFD(found).liftHook then
            return
        end
        GetFFD(found).liftHook = true
        local applying = false
        local function Apply()
            if applying then
                return
            end
            local pointCount = found:GetNumPoints() or 0
            local pts, success = {}, pointCount > 0
            for idx = 1, pointCount do
                local point, relTo, relPoint, posX, posY = found:GetPoint(idx)
                if not point then
                    success = false
                    break
                end
                pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + 6 }
            end
            if success then
                applying = true
                found:ClearAllPoints()
                for idx = 1, #pts do
                    local tbl = pts[idx]
                    found:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                end
                applying = false
            end
        end
        hooksecurefunc(found, "SetPoint", Apply)
        Apply()
    end

    -- Bottom-left icon buttons (repair item/repair all/guild repair/sell junk):
    -- pictured icon is the button's FIRST texture region, cropped from a shared
    -- sheet, so texcoords MUST be kept (never SquareIcon). Fade the box art
    -- around it, seat flat fill + themed border + white hover.
    local function SkinMerchantIconButton(btnFrame)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(btnFrame)
        local glyphTex = btnFrame.Icon or select(1, btnFrame:GetRegions())
        if not skinData.bg then
            local fillTex = btnFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
            fillTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
            fillTex:SetAllPoints(btnFrame)
            skinData.bg = fillTex
            local hover = btnFrame:CreateTexture(nil, "HIGHLIGHT")
            hover:SetColorTexture(1, 1, 1, 0.1)
            hover:SetAllPoints(btnFrame)
            skinData.hover = hover
            if glyphTex and glyphTex.ClearAllPoints then
                glyphTex:ClearAllPoints()
                glyphTex:SetPoint("TOPLEFT", 1, -1)
                glyphTex:SetPoint("BOTTOMRIGHT", -1, 1)
            end
        end
        for _, g in ipairs({
            "GetNormalTexture",
            "GetPushedTexture",
            "GetDisabledTexture",
            "GetHighlightTexture",
        }) do
            local part = btnFrame[g] and btnFrame[g](btnFrame)
            if part and part ~= glyphTex and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        local regionList = { btnFrame:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if
                region
                and region ~= glyphTex
                and region ~= skinData.bg
                and region ~= skinData.hover
                and region.IsObjectType
                and region:IsObjectType("Texture")
            then
                region:SetAlpha(0)
            end
        end
    end

    -------------------------------------------------------------------------------
    --  Expand Vendor UI (Merchant card): the sell tab shows a grid of the chosen columns x
    --  rows (CludesUIDB.merchantCols / merchantRows) instead of Blizzard's
    --  2 x 5 page. Nothing is built or hooked until the setting is first on
    --  (EnsureExpand). Blizzard's native 10-tile page stays Blizzard's and is only
    --  hidden while the grid is up (the buyback tab keeps it); tiles of the same
    --  template take its place, filled with MerchantFrame_UpdateMerchantInfo's
    --  logic. The frame widens and grows to hold the grid, and the pager steps one
    --  grid-full at a time. The native 2 x 5 size is Blizzard's own layout, so it
    --  needs none of this. Excluded with Show As List.
    --  "Hidden" means parked under a hidden holder rather than Hide(): the native
    --  tiles stay shown to Blizzard and to addons that decorate them (price
    --  displays, overlays), so they are already current when the grid comes down.
    -------------------------------------------------------------------------------
    local EX_COL_STEP, EX_ROW_STEP = 165, 52 -- tile 153 wide + Blizzard's 12 gap; 44 tall + 8 gap
    local EX_LEFT, EX_TOP = 11, -72 -- MerchantItem1's seat after the skin's 3px shift
    local EX_NATIVE_PER_PAGE = 10
    local EX_NATIVE_COLS, EX_NATIVE_ROWS = 2, 5
    local EX_MAX_COLS, EX_MAX_ROWS = 6, 10
    local EX_FRAME_PAD = 6 -- native 336 wide = 2 columns + 6
    local EX_PREFIX = "CUI_MerchantPage"
    local MAX_MONEY_DISPLAY_WIDTH_EX = 120
    -- buttons: the grid tiles' item buttons (a split open on one of them is the grid's).
    local exState = { page = 1, tiles = {}, buttons = {}, cols = EX_NATIVE_COLS, perPage = 0 }

    local function ExGrid()
        local saved = CludesUIDB
        local cols = math.floor(tonumber(saved and saved.merchantCols) or EX_NATIVE_COLS)
        local rowList = math.floor(tonumber(saved and saved.merchantRows) or EX_NATIVE_ROWS)
        return math.min(EX_MAX_COLS, math.max(EX_NATIVE_COLS, cols)),
            math.min(EX_MAX_ROWS, math.max(EX_NATIVE_ROWS, rowList))
    end

    local function ExpandOn()
        local saved = CludesUIDB
        if
            not saved
            or saved.merchantExpand ~= true
            or saved.merchantShowAsList
            or saved.reskinMerchant == false
        then
            return false
        end
        local cols, rowList = ExGrid()
        return cols ~= EX_NATIVE_COLS or rowList ~= EX_NATIVE_ROWS
    end

    local function ExpandActive()
        local win = _G.MerchantFrame
        return (ExpandOn() and win and (win.selectedTab or 1) == 1) and true or false
    end
    CludesUI._Merchant_ExpandActive = ExpandActive
    CludesUI._Merchant_ExpandPerPage = function()
        return exState.perPage
    end

    local function EX_NumPages()
        return math.max(1, math.ceil(GetMerchantNumItems() / math.max(1, exState.perPage)))
    end

    local function EX_Place(t, idx)
        local win = _G.MerchantFrame
        local colour = (idx - 1) % exState.cols
        local row = math.floor((idx - 1) / exState.cols)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", win, "TOPLEFT", EX_LEFT + colour * EX_COL_STEP, EX_TOP - row * EX_ROW_STEP)
    end

    local function EX_GetTile(idx)
        local tbl = exState.tiles[idx]
        if tbl then
            return tbl
        end
        local win = _G.MerchantFrame
        tbl = CreateFrame("Frame", EX_PREFIX .. idx, win, "MerchantItemTemplate")
        EX_Place(tbl, idx)
        SkinMerchantTile(tbl)
        LiftMerchantCurrency(_G[EX_PREFIX .. idx .. "MoneyFrame"])
        LiftMerchantCurrency(_G[EX_PREFIX .. idx .. "AltCurrencyFrame"])
        exState.tiles[idx] = tbl
        exState.buttons[tbl.ItemButton] = true
        return tbl
    end

    local function EX_FillTile(tile, slot, index, numItems)
        local btnFrame = tile.ItemButton
        local money = _G[EX_PREFIX .. slot .. "MoneyFrame"]
        local alt = _G[EX_PREFIX .. slot .. "AltCurrencyFrame"]
        local details = index <= numItems and C_MerchantFrame.GetItemInfo(index) or nil
        if not details then
            btnFrame.price = nil
            btnFrame.hasItem = nil
            btnFrame.name = nil
            btnFrame:SetID(0)
            tile:Hide()
            return
        end

        local itemName, texture, numAvailable = details.name, details.texture, details.numAvailable
        if details.currencyID then
            itemName, texture, numAvailable = CurrencyContainerUtil.GetCurrencyContainerInfo(
                details.currencyID,
                details.numAvailable,
                details.name,
                details.texture,
                nil
            )
        end

        local canAfford = CanAffordMerchantItem(index)
        local link = GetMerchantItemLink(index)
        tile.Name:SetText(itemName)
        SetItemButtonCount(btnFrame, details.stackCount)
        SetItemButtonStock(btnFrame, numAvailable)
        SetItemButtonTexture(btnFrame, texture)

        btnFrame.name = itemName
        btnFrame.link = link
        btnFrame.texture = texture
        if details.hasExtendedCost and details.price <= 0 then
            btnFrame.price = nil
            btnFrame.extendedCost = true
            CUI_MerchantFrame_UpdateAltCurrency(index, slot, canAfford, EX_PREFIX)
            alt:ClearAllPoints()
            alt:SetPoint("BOTTOMLEFT", EX_PREFIX .. slot .. "NameFrame", "BOTTOMLEFT", 0, 31)
            money:Hide()
            alt:Show()
        elseif details.hasExtendedCost then
            btnFrame.price = details.price
            btnFrame.extendedCost = true
            local altWidth = CUI_MerchantFrame_UpdateAltCurrency(index, slot, canAfford, EX_PREFIX)
            MoneyFrame_SetMaxDisplayWidth(money, MAX_MONEY_DISPLAY_WIDTH_EX - altWidth)
            MoneyFrame_Update(money:GetName(), details.price)
            SetMoneyFrameColor(money:GetName(), canAfford == false and "gray" or nil)
            alt:ClearAllPoints()
            alt:SetPoint("LEFT", money:GetName(), "RIGHT", -14, 0)
            alt:Show()
            money:Show()
        else
            btnFrame.price = details.price
            btnFrame.extendedCost = nil
            MoneyFrame_SetMaxDisplayWidth(money, MAX_MONEY_DISPLAY_WIDTH_EX)
            MoneyFrame_Update(money:GetName(), details.price)
            SetMoneyFrameColor(money:GetName(), canAfford == false and "gray" or nil)
            alt:Hide()
            money:Show()
        end

        if details.isQuestStartItem then
            btnFrame.IconQuestTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG)
            btnFrame.IconQuestTexture:Show()
        else
            btnFrame.IconQuestTexture:Hide()
        end
        MerchantFrameItem_UpdateQuality(tile, link)

        local itemId = GetMerchantItemID(index)
        local isHeirloom = itemId and C_Heirloom.IsItemHeirloom(itemId)
        local isKnownHeirloom = isHeirloom and C_Heirloom.PlayerHasHeirloom(itemId)
        btnFrame.showNonrefundablePrompt = not C_MerchantFrame.IsMerchantItemRefundable(index)
        btnFrame.hasItem = true
        btnFrame:SetID(index)
        btnFrame:Show()
        tile:Show()

        local tintRed = not details.isPurchasable or (not details.isUsable and not isHeirloom)
        SetItemButtonDesaturated(btnFrame, isKnownHeirloom)
        local red, green, blue = 1, 1, 1
        if numAvailable == 0 or isKnownHeirloom then
            if tintRed then
                red, green, blue = 0.5, 0, 0
            else
                red, green, blue = 0.5, 0.5, 0.5
            end
        elseif tintRed then
            red, green, blue = 0.9, 0, 0
        end
        SetItemButtonTextureVertexColor(btnFrame, red, green, blue)
        SetItemButtonNormalTextureVertexColor(btnFrame, red, green, blue)
    end

    local EX_Update

    local function EX_Flip(dir)
        local want = math.min(math.max(exState.page + dir, 1), EX_NumPages())
        if want == exState.page then
            return
        end
        -- A split open on one of the grid's tiles would act on whatever now holds its
        -- index. Close it through the shared helpers; with a key still held in it, skip
        -- the flip rather than leave the split on the wrong item. A split on anything
        -- else (a bag slot) is not the grid's to close.
        local ssf = StackSplitFrame
        local ownerFrame = ssf and ssf:IsShown() and ssf.owner
        if ownerFrame and exState.buttons[ownerFrame] then
            if not CludesUI.StackSplitFor(ownerFrame) then
                return
            end
            CludesUI.TakeStackSplit()
        end
        exState.page = want
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        EX_Update()
    end

    local function EX_MakePageButton(win, kind, glyphTex, anchorPoint, posX)
        local button = CreateFrame("Button", nil, win)
        button:SetSize(32, 32)
        button:SetPoint("CENTER", win, anchorPoint, posX, 96)
        button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Up")
        button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Down")
        button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Disabled")
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        button:SetScript("OnClick", function()
            EX_Flip(kind == "Prev" and -1 or 1)
        end)
        SkinLabeledPageButton(button, glyphTex, glyphTex == ">" and 2 or nil)
        return button
    end

    local function EX_UpdatePager(win, numPages)
        if not exState.prev then
            exState.prev = EX_MakePageButton(win, "Prev", "<", "BOTTOMLEFT", 25)
            exState.next = EX_MakePageButton(win, "Next", ">", "BOTTOMRIGHT", -26)
            exState.text = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            exState.text:SetPoint("BOTTOM", win, "BOTTOM", 0, 86)
            Skin.Font(exState.text)
            Skin.White(exState.text)
        end
        local show = numPages > 1
        exState.prev:SetShown(show)
        exState.next:SetShown(show)
        exState.text:SetShown(show)
        if not show then
            return
        end
        exState.prev:SetEnabled(exState.page > 1)
        exState.next:SetEnabled(exState.page < numPages)
        exState.text:SetFormattedText("%d / %d", exState.page, numPages)
    end

    -- Move the native page under the hidden holder (park) or back to its parent.
    local function EX_ParkNative(park)
        for idx = 1, EX_NATIVE_PER_PAGE do
            local n = _G["MerchantItem" .. idx]
            if n then
                local parked = n:GetParent() == exState.holder
                if park and not parked then
                    exState.nativeParent = exState.nativeParent or n:GetParent()
                    n:SetParent(exState.holder)
                elseif not park and parked then
                    n:SetParent(exState.nativeParent)
                end
            end
        end
    end

    local function EX_Deactivate(win)
        if not exState.active then
            return
        end
        exState.active = false
        for idx = 1, #exState.tiles do
            exState.tiles[idx]:Hide()
        end
        if exState.prev then
            exState.prev:Hide()
            exState.next:Hide()
            exState.text:Hide()
        end
        if exState.nativeW and win:GetWidth() ~= exState.nativeW then
            win:SetWidth(exState.nativeW)
        end
        if exState.nativeH and win:GetHeight() ~= exState.nativeH then
            win:SetHeight(exState.nativeH)
        end
        local bb = _G.MerchantBuyBackItem
        if bb and exState.bbPoint then
            local pt = exState.bbPoint
            bb:ClearAllPoints()
            bb:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
        end
        EX_ParkNative(false)
        -- Switched off on the sell tab: show the pager the way Blizzard decides it.
        -- Blizzard keeps its text and enabled state current while it is hidden.
        if
            not ExpandOn()
            and win:IsShown()
            and (win.selectedTab or 1) == 1
            and GetMerchantNumItems() > MERCHANT_ITEMS_PER_PAGE
        then
            for _, c in ipairs(exState.pager) do
                c:Show()
            end
        end
        -- Item levels went to the grid's tiles while it was up.
        if CludesUIDB.merchantShowItemLevel then
            CludesUI._Merchant_RefreshItemLevels()
        end
    end

    EX_Update = function()
        local win = _G.MerchantFrame
        if not win or not exState.hooked then
            return
        end
        if not ExpandActive() then
            EX_Deactivate(win)
            return
        end
        if not win:IsShown() then
            return
        end

        exState.active = true
        local cols, rowList = ExGrid()
        exState.perPage = cols * rowList
        if not exState.nativeW then
            exState.nativeW, exState.nativeH = win:GetWidth(), win:GetHeight()
        end
        -- The most-recent-buyback slot hangs off MerchantItem10, which is parked and
        -- stays at row 5; keep its native offset from the Sell All Junk button, which
        -- rides the frame's bottom edge, so it follows the grid.
        local bb, junk = _G.MerchantBuyBackItem, _G.MerchantSellAllJunkButton
        if bb and junk then
            if not exState.bbPoint and bb:GetNumPoints() > 0 and bb:GetLeft() and junk:GetLeft() then
                local point, relTo, relPoint, posX, posY = bb:GetPoint(1)
                exState.bbPoint = { point, relTo, relPoint, posX or 0, posY or 0 }
                exState.bbDX = bb:GetLeft() - junk:GetLeft()
                exState.bbDY = bb:GetTop() - junk:GetTop()
            end
            if exState.bbDX then
                bb:ClearAllPoints()
                bb:SetPoint("TOPLEFT", junk, "TOPLEFT", exState.bbDX, exState.bbDY)
            end
        end
        local wid = cols * EX_COL_STEP + EX_FRAME_PAD
        local hgt = exState.nativeH + (rowList - EX_NATIVE_ROWS) * EX_ROW_STEP
        if win:GetWidth() ~= wid then
            win:SetWidth(wid)
        end
        if win:GetHeight() ~= hgt then
            win:SetHeight(hgt)
        end
        EX_ParkNative(true)
        for _, c in ipairs(exState.pager) do
            c:Hide()
        end

        if exState.cols ~= cols then
            exState.cols = cols
            for idx = 1, #exState.tiles do
                EX_Place(exState.tiles[idx], idx)
            end
        end

        local numItems = GetMerchantNumItems()
        local numPages = EX_NumPages()
        if exState.page > numPages then
            exState.page = numPages
        end
        local base = (exState.page - 1) * exState.perPage
        for idx = 1, exState.perPage do
            EX_FillTile(EX_GetTile(idx), idx, base + idx, numItems)
        end
        for idx = exState.perPage + 1, #exState.tiles do
            exState.tiles[idx]:Hide()
        end
        EX_UpdatePager(win, numPages)

        -- Item levels read each button's ID, which a flip just changed.
        if CludesUIDB.merchantShowItemLevel then
            CludesUI._Merchant_RefreshItemLevels()
        end
        -- Bulk Buy closes its window once its tile shows another item; it checks on
        -- MerchantFrame_Update, which a flip does not run.
        if CludesUI._Merchant_BulkBuyRepaint then
            CludesUI._Merchant_BulkBuyRepaint()
        end
    end
    -- GET_ITEM_INFO_RECEIVED comes in a burst while a vendor's items load: one refill
    -- per frame. Built here, at load, so no skin callback wraps it.
    exState.updateSoon = Skin.Debounce(EX_Update)

    local function EnsureExpand()
        if exState.hooked then
            return
        end
        local win = _G.MerchantFrame
        if not win then
            return
        end
        exState.hooked = true
        exState.holder = CreateFrame("Frame", nil, win)
        exState.holder:Hide()
        -- Blizzard re-Shows the native pager on every update; keep it down while
        -- the grid is up (hidden, not parked: Blizzard's wheel handler pages
        -- through a shown pager). Show hooks only, no method overwrites.
        local function HideIfActive(self)
            if ExpandActive() then
                self:Hide()
            end
        end
        exState.pager = { _G.MerchantPrevPageButton, _G.MerchantNextPageButton, _G.MerchantPageText }
        for _, c in ipairs(exState.pager) do
            hooksecurefunc(c, "Show", HideIfActive)
        end
        hooksecurefunc("MerchantFrame_Update", EX_Update)
        -- Fires when an uncached item resolves; the native pass would only refill its own tiles.
        hooksecurefunc("MerchantFrame_UpdateItemQualityBorders", exState.updateSoon)
        win:HookScript("OnShow", function()
            exState.page = 1
        end)
        win:HookScript("OnMouseWheel", function(_, delta)
            if ExpandActive() then
                EX_Flip(delta > 0 and -1 or 1)
            end
        end)
    end

    -- Options entry point (toggle, columns, rows).
    CludesUI._Merchant_RefreshExpand = function()
        local win = _G.MerchantFrame
        if not win or not win:IsShown() then
            return
        end -- the next show picks it up
        if ExpandOn() then
            EnsureExpand()
        end
        EX_Update()
    end

    local _merchantHooked = false
    local function Skin_Merchant()
        local win = _G.MerchantFrame
        if not win then
            return
        end
        Skin.Shell("merchant", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "MerchantFrame") -- close + FilterDropdown
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if win.Inset then
            Skin.Inset(win.Inset)
        end
        if _G.MerchantFrameBg then
            _G.MerchantFrameBg:SetAlpha(0)
        end
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or _G.MerchantNameText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end

        -- Money / alt-currency wells along the bottom.
        for _, n in ipairs({ "MerchantMoneyInset", "MerchantExtraCurrencyInset" }) do
            if _G[n] then
                Skin.Inset(_G[n])
            end
        end
        for _, n in ipairs({ "MerchantMoneyBg", "MerchantExtraCurrencyBg" }) do
            local part = _G[n]
            if part then
                Skin.FadeRegions(part)
                Skin.Register(part, true)
            end
        end

        if CludesUIDB.merchantShowAsList then
            HideNativeMerchantGrid()

            if not win.wSkinScrollFrame then
                local scrollFrame, childFrame = CreateMerchantScrollList(win)
                win.wSkinScrollFrame = scrollFrame
                win.wSkinScrollChild = childFrame
            end
        else
            -- Item tiles (10 merchant, buyback page reuses up to 12) plus the most-recent-buyback slot on the merchant tab.
            for idx = 1, 12 do
                SkinMerchantTile(_G["MerchantItem" .. idx])
            end
            SkinMerchantTile(_G.MerchantBuyBackItem)
            -- Main grid 3px lower: MerchantItem1 is the chain root, so one shift
            -- moves the grid (MerchantBuyBackItem anchors separately and stays put). One-shot, all points preserved.
            local it1 = _G.MerchantItem1
            if it1 and not GetFFD(it1).shifted then
                local pointCount = it1:GetNumPoints() or 0
                local pts, success = {}, pointCount > 0
                for idx = 1, pointCount do
                    local point, relTo, relPoint, posX, posY = it1:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) - 3 }
                end
                if success then
                    GetFFD(it1).shifted = true
                    it1:ClearAllPoints()
                    for idx = 1, #pts do
                        local tbl = pts[idx]
                        it1:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                    end
                end
            end
            -- Currency text/icons ride 10px higher on every tile (not the buyback slot).
            for idx = 1, 12 do
                LiftMerchantCurrency(_G["MerchantItem" .. idx .. "MoneyFrame"])
                LiftMerchantCurrency(_G["MerchantItem" .. idx .. "AltCurrencyFrame"])
            end

            SkinLabeledPageButton(_G.MerchantPrevPageButton, "<")
            SkinLabeledPageButton(_G.MerchantNextPageButton, ">", 2)
        end

        -- Bottom-left icon buttons (guild repair only exists in a guild).
        for _, n in ipairs({
            "MerchantRepairItemButton",
            "MerchantRepairAllButton",
            "MerchantGuildBankRepairButton",
            "MerchantSellAllJunkButton",
        }) do
            SkinMerchantIconButton(_G[n])
        end
        if _G.MerchantPageText then
            Skin.Font(_G.MerchantPageText)
            Skin.White(_G.MerchantPageText)
        end

        -- Tabs
        local mTabs = {}
        for idx = 1, 2 do
            local tabBtn = _G["MerchantFrameTab" .. idx]
            if tabBtn then
                Skin.Tab(tabBtn)
                mTabs[#mTabs + 1] = tabBtn
            end
        end
        Skin.NormalizeTabRow(mTabs)

        if ExpandOn() then
            EnsureExpand()
            EX_Update()
        end

        if not _merchantHooked then
            _merchantHooked = true
            -- Blizzard re-textures tiles on every page flip/tab swap/vendor open, so re-run the (idempotent) tile pass on its repaint.
            if type(_G.MerchantFrame_Update) == "function" then
                hooksecurefunc(
                    "MerchantFrame_Update",
                    Skin.Debounce(function()
                        if win:IsVisible() then
                            if CludesUIDB.merchantShowAsList and win.wSkinScrollFrame then
                                UpdateCustomMerchantList(win.wSkinScrollFrame, win.wSkinScrollChild)
                            else
                                for idx = 1, 12 do
                                    SkinMerchantTile(_G["MerchantItem" .. idx])
                                end
                                SkinMerchantTile(_G.MerchantBuyBackItem)
                            end
                        end
                    end)
                )
            end
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_Merchant()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "merchant",
        apply = Skin_Merchant,
    })
end

-------------------------------------------------------------------------------
--  Merchant item-level overlay (QoL, independent of the Merchant reskin). Item
--  level top-left of each vendor tile for weapons/armor when
--  CludesUIDB.merchantShowItemLevel is set. Buttons carry their merchant
--  slot index as their ID (set by MerchantFrame_Update), so the link resolves
--  straight from GetMerchantItemLink.
-------------------------------------------------------------------------------
do
    local MERCHANT_ILVL_WEAPON = Enum.ItemClass.Weapon
    local MERCHANT_ILVL_ARMOR = Enum.ItemClass.Armor

    local function UpdateMerchantItemLevels()
        local win = _G.MerchantFrame
        if not win then
            return
        end
        local show = CludesUIDB and CludesUIDB.merchantShowItemLevel == true
        local onSellTab = (win.selectedTab or 1) == 1
        local numItems
        local prefixText = "MerchantItem"
        if CludesUIDB.merchantShowAsList then
            -- GetNumBuybackItems is irrelevant: text only shows on the sell tab.
            numItems = GetMerchantNumItems()
            prefixText = "CUI_MerchantItem"
        elseif CludesUI._Merchant_ExpandActive() then
            numItems = CludesUI._Merchant_ExpandPerPage()
            prefixText = "CUI_MerchantPage"
        else
            numItems = 12
        end
        local render = show and onSellTab and win:IsVisible()
        for idx = 1, numItems do
            local btnFrame = _G[prefixText .. idx .. "ItemButton"]
            if btnFrame then
                -- FontString ref lives in the engine FFD, NEVER on Blizzard's button
                -- table. Read without creating, so the disabled path costs one weak-table lookup per slot.
                local fieldData = FFD[btnFrame]
                local fontStr = fieldData and fieldData.merchantILvl
                if not render then
                    if fontStr then
                        fontStr:SetText("")
                    end
                else
                    if not fontStr then
                        fontStr = btnFrame:CreateFontString(nil, "OVERLAY", nil, 7)
                        if CludesUIDB.merchantShowAsList then
                            fontStr:SetPoint(
                                "TOPLEFT",
                                _G["CUI_MerchantItem" .. idx .. "SlotTexture"],
                                "TOPLEFT",
                                1,
                                -1
                            )
                        else
                            fontStr:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", 1, -1)
                        end
                        local filePath = (CludesUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                        local flag = (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE"
                        fontStr:SetFont(filePath, 12, flag)
                        GetFFD(btnFrame).merchantILvl = fontStr
                    end
                    fontStr:SetText("")
                    local index = btnFrame:GetID()
                    local link = index and index > 0 and GetMerchantItemLink(index)
                    if link then
                        local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
                        if classID == MERCHANT_ILVL_WEAPON or classID == MERCHANT_ILVL_ARMOR then
                            local ilvl = C_Item.GetDetailedItemLevelInfo(link)
                            if ilvl and ilvl > 0 then
                                fontStr:SetText(ilvl)
                                local quality = select(3, C_Item.GetItemInfo(link))
                                local color = CludesUI.GetItemLevelColor(link, quality)
                                fontStr:SetTextColor(color.r or 1, color.g or 1, color.b or 1, 1)
                            end
                        end
                    end
                end
            end
        end
    end

    local _merchantILvlHooked = false
    local function EnsureMerchantILvlHook()
        if _merchantILvlHooked then
            return
        end
        _merchantILvlHooked = true
        if type(_G.MerchantFrame_Update) == "function" then
            hooksecurefunc("MerchantFrame_Update", Skin.Debounce(UpdateMerchantItemLevels))
        end
    end

    -- The MerchantFrame_Update hook renders item levels: installed once the toggle
    -- is on and left in place (cheap -- only fires while a merchant is up, and the
    -- updater no-ops when off). Must NOT be gated on MerchantFrame:IsVisible():
    -- MERCHANT_SHOW fires BEFORE Blizzard shows the frame, so IsVisible() is false
    -- and the hook would never install. GET_ITEM_INFO_RECEIVED fires on every
    -- item-cache resolve suite-wide, so it is registered ONLY while a merchant is
    -- open (explicit flag, not visibility) AND the toggle is on.
    local mILvlBoot = CreateFrame("Frame")
    local _merchantOpen = false
    local function SyncMerchantILvlEvents()
        local on = CludesUIDB and CludesUIDB.merchantShowItemLevel == true
        if on then
            EnsureMerchantILvlHook()
        end
        if on and _merchantOpen then
            mILvlBoot:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        else
            mILvlBoot:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        end
    end

    -- Options toggle entry point: re-sync listeners, then render or clear.
    CludesUI._Merchant_RefreshItemLevels = function()
        SyncMerchantILvlEvents()
        UpdateMerchantItemLevels()
    end

    mILvlBoot:RegisterEvent("MERCHANT_SHOW")
    mILvlBoot:RegisterEvent("MERCHANT_CLOSED")
    mILvlBoot:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" then
            _merchantOpen = true
            SyncMerchantILvlEvents()
            UpdateMerchantItemLevels()
        elseif event == "MERCHANT_CLOSED" then
            _merchantOpen = false
            SyncMerchantILvlEvents()
        else -- GET_ITEM_INFO_RECEIVED: an item's data resolved while shopping
            UpdateMerchantItemLevels()
        end
    end)
end

-------------------------------------------------------------------------------
--  Class / Profession Trainer (ClassTrainerFrame, Blizzard_TrainerUI). Flat
--  chrome, squared skill-row icons, flat train button. Native availability
--  text color is KEPT (green/red/gray), never forced white, as with rarity.
-------------------------------------------------------------------------------
do
    -- One skill row: squared icon, font-only text (Blizzard's availability color
    -- kept), box art off, flat selection + hover washes.
    local function SkinTrainerRow(row)
        if not row or row:IsForbidden() then
            return
        end
        if row.icon then
            Skin.SquareIcon(row.icon, row)
        end
        if row.name then
            Skin.Font(row.name)
        end
        if row.subText then
            Skin.Font(row.subText)
        end
        local nt = row.GetNormalTexture and row:GetNormalTexture()
        if nt and nt.SetAlpha then
            nt:SetAlpha(0)
        end
        if row.disabledBG and row.disabledBG.SetAlpha then
            row.disabledBG:SetAlpha(0)
        end
        if row.selectedTex and row.selectedTex.SetColorTexture then
            row.selectedTex:SetColorTexture(1, 1, 1, 0.15)
        end
        local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
        if highlight and highlight.SetColorTexture then
            highlight:SetColorTexture(1, 1, 1, 0.1)
        end
    end

    local _trainerHooked = false
    local function Skin_Trainer()
        local win = _G.ClassTrainerFrame
        if not win then
            return
        end
        Skin.Shell("trainer", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "ClassTrainerFrame") -- close + FilterDropdown + scrollbar
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if _G.ClassTrainerFrameBg then
            _G.ClassTrainerFrameBg:SetAlpha(0)
        end
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or _G.ClassTrainerFrameTitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end
        -- Insets: top content panel (Bg+NineSlice carry leftover Blizzard chrome) and bottom well.
        local topInset = _G.ClassTrainerFrameInset or win.Inset
        if topInset then
            Skin.Inset(topInset)
        end
        local inset = win.BottomInset or _G.ClassTrainerFrameBottomInset
        if inset then
            Skin.Inset(inset)
        end
        if win.FilterDropdown then
            LeftAlignFilterLabel(win.FilterDropdown)
        end
        local tabFrame = _G.ClassTrainerTrainButton
        if tabFrame then
            Skin.Button(tabFrame)
            local tfs = tabFrame.GetFontString and tabFrame:GetFontString()
            if tfs then
                Skin.White(tfs)
            end
        end
        -- Top "current profession" tab: strip Blizzard chrome (bg+NineSlice), keep
        -- the profession icon, wash the guild sidebar card texture over the WHOLE
        -- tab at 50%, border the icon tight. NOT restrip-registered (would fade the icon+card being kept).
        local step = _G.ClassTrainerFrameSkillStepButton
        if step then
            local sdt = GetFFD(step)
            local glyphTex = step.icon or step.Icon
            if step.NineSlice then
                Skin.FadeNineSlice(step.NineSlice)
            end
            local keepSet = {}
            if glyphTex then
                keepSet[glyphTex] = true
            end
            if sdt.tabTex then
                keepSet[sdt.tabTex] = true
            end
            Skin.FadeRegions(step, keepSet)
            -- Full window width, 15px taller (measured one-shot keeping the current top; retried on show until rects exist).
            if not sdt.resized then
                local st, ft, hgt = step:GetTop(), win:GetTop(), step:GetHeight()
                if st and ft and hgt then
                    sdt.resized = true
                    local dy = (st - ft) + 5 -- 5px up
                    step:ClearAllPoints()
                    step:SetPoint("TOPLEFT", win, "TOPLEFT", 0, dy)
                    step:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, dy)
                    step:SetHeight(hgt + 15)
                end
            end
            -- Full-tab background: the guild sidebar card atlas at 50%.
            if not sdt.tabTex then
                local part = step:CreateTexture(nil, "BACKGROUND", nil, -2)
                part:SetAtlas("Ui-Dialog-New-Background")
                part:SetTexCoord(0, 1, 0, 1)
                part:SetVertexColor(1, 1, 1, 1)
                part:SetAlpha(0.5)
                part:SetAllPoints(step)
                sdt.tabTex = part
            end
            -- Profession icon: squared with a 1px border hugging its edges.
            if glyphTex then
                Skin.SquareIcon(glyphTex, step)
            end
            if step.selectedTex and step.selectedTex.SetColorTexture then
                step.selectedTex:SetColorTexture(1, 1, 1, 0.15)
            end
            local shl = _G.ClassTrainerFrameSkillStepButtonHighlight
            if shl and shl.SetColorTexture then
                shl:SetColorTexture(1, 1, 1, 0.1)
            end
        end
        -- Skill rank status bar (profession trainers only).
        local sbar = _G.ClassTrainerStatusBar
        if sbar then
            Skin.FadeRegions(sbar)
            Skin.ApplyBarFill(sbar)
            if sbar.rankText then
                Skin.Font(sbar.rankText)
                Skin.White(sbar.rankText)
            end
        end
        local scrollBar = win.ScrollBox
        if scrollBar then
            if scrollBar.ForEachFrame and scrollBar:IsVisible() then
                scrollBar:ForEachFrame(SkinTrainerRow)
            end
            if not GetFFD(scrollBar).rowHook then
                GetFFD(scrollBar).rowHook = true
                hooksecurefunc(
                    scrollBar,
                    "Update",
                    Skin.Debounce(function()
                        if scrollBar.ForEachFrame and scrollBar:IsVisible() then
                            scrollBar:ForEachFrame(SkinTrainerRow)
                        end
                    end)
                )
            end
        end

        if not _trainerHooked then
            _trainerHooked = true
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_Trainer()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "trainer",
        addons = { Blizzard_TrainerUI = true },
        apply = Skin_Trainer,
    })
end

-------------------------------------------------------------------------------
--  Delves Companion (Blizzard_DelvesCompanionConfiguration LoD addon):
--  portrait frame with three option slots (combat role + two trinkets), a
--  "Show Abilities" button, and the paginated ability-list popout. Both frames
--  live in the same addon and share the "delves" winKey.
-------------------------------------------------------------------------------
do
    -- One pooled option-slot flyout button: drop the gold border, square the icon.
    local function SkinDelvesOptionButton(btnFrame)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        if btnFrame.Border and btnFrame.Border.SetAlpha then
            btnFrame.Border:SetAlpha(0)
        end
        local glyphTex = btnFrame.Icon or btnFrame.icon
        if glyphTex then
            Skin.SquareIcon(glyphTex, btnFrame)
        end
    end

    -- One option slot's flyout list (the popout shown when the slot is clicked):
    -- flat panel + slim scrollbar + squared icons on its pooled buttons.
    local function SkinDelvesOptionSlot(slot)
        if not slot or slot:IsForbidden() then
            return
        end
        local entries = slot.OptionsList
        if not entries then
            return
        end
        Skin.Panel(entries)
        Skin.ScrollBarsIn(entries)
        local scrollBar = entries.ScrollBox
        if scrollBar then
            if scrollBar.ForEachFrame and scrollBar:IsVisible() then
                pcall(scrollBar.ForEachFrame, scrollBar, SkinDelvesOptionButton)
            end
            if scrollBar.Update and not GetFFD(scrollBar).rowHook then
                GetFFD(scrollBar).rowHook = true
                hooksecurefunc(scrollBar, "Update", function(tabBox)
                    if tabBox.ForEachFrame then
                        pcall(tabBox.ForEachFrame, tabBox, SkinDelvesOptionButton)
                    end
                end)
            end
        end
    end

    local _delvesAbilityHooked = false
    local function Skin_DelvesCompanion()
        local win = _G.DelvesCompanionConfigurationFrame
        if win then
            Skin.Shell("delves", win)
            Skin.RemovePortrait(win)
            Skin.CommonChrome(win)
            if win.NineSlice then
                Skin.FadeNineSlice(win.NineSlice)
            end
            if win.Bg and win.Bg.SetAlpha then
                win.Bg:SetAlpha(0)
            end
            -- Leftover Blizzard border sub-frame: our atlas border replaces it, alpha 0 inherits to all its edge children.
            if win.Border and win.Border.SetAlpha then
                win.Border:SetAlpha(0)
            end
            -- Brann's portrait and XP ring poke above the window top and natively
            -- draw OVER the dialog border. Our atlas border rides a child frame at
            -- +6, so lift them past it or the border line cuts across the art (level badge already sits at 100).
            local overBorder = win:GetFrameLevel() + 7
            if win.CompanionPortraitFrame and win.CompanionPortraitFrame.SetFrameLevel then
                win.CompanionPortraitFrame:SetFrameLevel(overBorder)
            end
            if win.CompanionExperienceRingFrame and win.CompanionExperienceRingFrame.SetFrameLevel then
                win.CompanionExperienceRingFrame:SetFrameLevel(overBorder + 1)
            end
            -- Close button natively anchors to the corner of the now-alpha-0
            -- DialogBorder sub-frame, leaving the X flush with the window edge.
            -- Seat it like every other shell: centered on the 25px top bar with right spacing.
            local creatureBtn = win.CloseButton
            if creatureBtn and not GetFFD(creatureBtn).reseated then
                GetFFD(creatureBtn).reseated = true
                creatureBtn:ClearAllPoints()
                creatureBtn:SetPoint("CENTER", win, "TOPRIGHT", -14, -12)
            end
            local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or win.TitleText
            if titleText then
                Skin.Font(titleText)
                Skin.White(titleText)
            end
            local ab = win.CompanionConfigShowAbilitiesButton
            if ab then
                Skin.Button(ab)
                local labelText = ab.GetFontString and ab:GetFontString()
                if labelText then
                    Skin.White(labelText)
                end
            end
            SkinDelvesOptionSlot(win.CompanionCombatRoleSlot)
            SkinDelvesOptionSlot(win.CompanionUtilityTrinketSlot)
            SkinDelvesOptionSlot(win.CompanionCombatTrinketSlot)
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_DelvesCompanion()
                    end
                end)
            )
        end

        -- Companion ability list popout (same addon), opened from Show Abilities.
        local al = _G.DelvesCompanionAbilityListFrame
        if al then
            Skin.Shell("delves", al)
            Skin.RemovePortrait(al)
            Skin.CommonChrome(al)
            if al.NineSlice then
                Skin.FadeNineSlice(al.NineSlice)
            end
            if al.Border and al.Border.SetAlpha then
                al.Border:SetAlpha(0)
            end
            local atitle = (al.TitleContainer and al.TitleContainer.TitleText) or al.TitleText
            if atitle then
                Skin.Font(atitle)
                Skin.White(atitle)
            end
            if al.DelvesCompanionRoleDropdown then
                Skin.Dropdown(al.DelvesCompanionRoleDropdown)
            end
            local pc = al.DelvesCompanionAbilityListPagingControls
            if pc then
                if pc.PrevPageButton then
                    Skin.PageButton(pc.PrevPageButton, "<", 13)
                end
                if pc.NextPageButton then
                    Skin.PageButton(pc.NextPageButton, ">", 13)
                end
            end
            -- Ability tiles repaint on page flips: square their icons each rebuild.
            if not _delvesAbilityHooked and al.UpdatePaginatedButtonDisplay then
                _delvesAbilityHooked = true
                hooksecurefunc(al, "UpdatePaginatedButtonDisplay", function(self)
                    if not self.buttons then
                        return
                    end
                    for _, button in next, self.buttons do
                        local glyphTex = button.Icon or button.icon
                        if glyphTex then
                            Skin.SquareIcon(glyphTex, button)
                        end
                    end
                end)
            end
            Skin.HookShow(
                al,
                Skin.Debounce(function()
                    if al:IsVisible() then
                        Skin_DelvesCompanion()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "delves",
        addons = { Blizzard_DelvesCompanionConfiguration = true },
        apply = Skin_DelvesCompanion,
    })
end

-------------------------------------------------------------------------------
--  Gossip (GossipFrame) -- NPC dialog window. Base UI, always loaded.
-------------------------------------------------------------------------------
do
    local function SkinGossipOption(btnFrame)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        -- Recolor ONLY: gossip text keeps Blizzard's native font (color-only widget font policy). Never WSkin.Font here.
        if btnFrame.GreetingText then
            Skin.White(btnFrame.GreetingText)
            RecolorDarkText(btnFrame.GreetingText)
        end
        local fontStr = btnFrame.GetFontString and btnFrame:GetFontString()
        if fontStr then
            Skin.White(fontStr)
            RecolorDarkText(fontStr)
        end
        -- The NPC greeting body is a FontString nested inside the element (neither
        -- the named GreetingText field nor the button label), so it slips past both
        -- checks above and renders black on the dark panel. Whiten every FontString
        -- in the row subtree and rewrite embedded link colors; the debounced
        -- ScrollBox.Update hook re-asserts this after each Blizzard recolor.
        WhitenTextIn(btnFrame)
    end

    local _gossipHooked = false
    local function Skin_Gossip()
        local win = _G.GossipFrame
        if not win then
            return
        end
        Skin.Shell("gossip", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "GossipFrame") -- close + scrollbar
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if _G.GossipFrameBg then
            _G.GossipFrameBg:SetAlpha(0)
        end
        -- QuestLog atlas washed over the frame at 50%: sublevel -6 sits above the
        -- shell backdrop (-8/-7) and below the title bar (-5)+content. Stored under the protected "fill" key so a Restrip never fades it.
        if not GetFFD(win).fill then
            local qbg = win:CreateTexture(nil, "BACKGROUND", nil, -6)
            qbg:SetAtlas("QuestLog-main-background", false)
            qbg:SetAllPoints(win)
            qbg:SetAlpha(0.5)
            GetFFD(win).fill = qbg
        end
        -- NPC scene/parchment background is re-textured per NPC, so self-guard the fade against its SetAtlas/SetTexture repaints.
        local bgTex = win.Background
        if bgTex and bgTex.SetAlpha then
            bgTex:SetAlpha(0)
            if not GetFFD(bgTex).atlasHook then
                GetFFD(bgTex).atlasHook = true
                hooksecurefunc(bgTex, "SetAtlas", function()
                    bgTex:SetAlpha(0)
                end)
                if bgTex.SetTexture then
                    hooksecurefunc(bgTex, "SetTexture", function()
                        bgTex:SetAlpha(0)
                    end)
                end
            end
        end
        local inset = win.Inset or _G.GossipFrameInset
        if inset then
            Skin.Inset(inset)
        end
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or _G.GossipFrameTitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end
        local gp = win.GreetingPanel
        if gp then
            if gp.GoodbyeButton then
                Skin.Button(gp.GoodbyeButton)
                local gfs = gp.GoodbyeButton.GetFontString and gp.GoodbyeButton:GetFontString()
                if gfs then
                    Skin.White(gfs)
                end
            end
            local scrollBar = gp.ScrollBox
            if scrollBar then
                if scrollBar.ForEachFrame and scrollBar:IsVisible() then
                    scrollBar:ForEachFrame(SkinGossipOption)
                end
                if not GetFFD(scrollBar).rowHook then
                    GetFFD(scrollBar).rowHook = true
                    hooksecurefunc(
                        scrollBar,
                        "Update",
                        Skin.Debounce(function()
                            if scrollBar.ForEachFrame and scrollBar:IsVisible() then
                                scrollBar:ForEachFrame(SkinGossipOption)
                            end
                        end)
                    )
                end
            end
        end
        -- Friendship rep bar (some NPCs): thin black notches, white text.
        local fsb = win.FriendshipStatusBar
        if fsb then
            for idx = 1, 4 do
                local notch = fsb["Notch" .. idx]
                if notch and notch.SetColorTexture then
                    notch:SetColorTexture(0, 0, 0, 1)
                end
            end
            local ft = fsb.Text or (fsb.GetFontString and fsb:GetFontString())
            if ft then
                Skin.Font(ft)
                Skin.White(ft)
            end
        end

        if not _gossipHooked then
            _gossipHooked = true
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_Gossip()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "gossip",
        apply = Skin_Gossip,
    })
end

-------------------------------------------------------------------------------
--  Quest (QuestFrame): the NPC quest dialog (detail/progress/reward/greeting
--  panels). Base UI, always loaded. Matches the gossip window: dark shell,
--  faded parchment, yellow headers+white body, flat action buttons. Helpers
--  are NESTED to keep the file's chunk-local count under the Lua 5.1 cap.
-------------------------------------------------------------------------------
do
    local _questHooked = false
    local function Skin_Quest()
        local win = _G.QuestFrame
        if not win then
            return
        end
        Skin.Shell("quest", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "QuestFrame") -- close button + centered title
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if win.Inset then
            Skin.Inset(win.Inset)
        end

        -- Title bar / NPC name.
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or _G.QuestFrameTitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end
        if _G.QuestFrameNpcNameText then
            Skin.Font(_G.QuestFrameNpcNameText)
            Skin.White(_G.QuestFrameNpcNameText)
        end

        -- Panels + scroll frames: fade every parchment texture (FadeRegions alphas
        -- Textures only, never FontStrings, so body text survives), register for restrip, slim the scrollbars.
        for _, pn in ipairs({
            "QuestFrameDetailPanel",
            "QuestFrameProgressPanel",
            "QuestFrameRewardPanel",
            "QuestFrameGreetingPanel",
        }) do
            local p = _G[pn]
            if p then
                Skin.FadeRegions(p)
                Skin.Register(p, true)
                if p.NineSlice then
                    Skin.FadeNineSlice(p.NineSlice)
                end
            end
        end
        for _, sn in ipairs({
            "QuestDetailScrollFrame",
            "QuestProgressScrollFrame",
            "QuestRewardScrollFrame",
            "QuestGreetingScrollFrame",
            "QuestDetailScrollChildFrame",
            "QuestRewardScrollChildFrame",
        }) do
            local cfg = _G[sn]
            if cfg then
                Skin.FadeRegions(cfg)
                Skin.Register(cfg, true)
                if cfg.ScrollBar then
                    Skin.ScrollBar(cfg.ScrollBar)
                end
            end
        end
        -- Quest scroll viewport up 40px, 30px taller. CalReseat preserves every
        -- anchor point (no width collapse) and is idempotent; height bump needs its
        -- own FFD guard since SetHeight is cumulative and the skin re-runs on every show.
        for _, sn in ipairs({
            "QuestDetailScrollFrame",
            "QuestProgressScrollFrame",
            "QuestRewardScrollFrame",
            "QuestGreetingScrollFrame",
        }) do
            local s = _G[sn]
            if s then
                CalReseat(s, 40)
                local skinData = GetFFD(s)
                if not skinData.heightBumped and s.GetHeight and s.SetHeight then
                    local hgt = s:GetHeight()
                    if hgt and hgt > 0 then
                        skinData.heightBumped = true
                        s:SetHeight(hgt + 30)
                    end
                end
            end
        end

        -- Action buttons: flat block + state-aware label (color-only, keeps Blizz font).
        for _, bn in ipairs({
            "QuestFrameAcceptButton",
            "QuestFrameDeclineButton",
            "QuestFrameCompleteButton",
            "QuestFrameGoodbyeButton",
            "QuestFrameCompleteQuestButton",
            "QuestFrameCancelButton",
            "QuestFrameGreetingGoodbyeButton",
        }) do
            local button = _G[bn]
            if button then
                Skin.Button(button)
                Skin.StateButtonLabel(button)
            end
        end

        -- Shared QuestInfo body/header coloring (detail+reward panels). QuestInfo*
        -- frames are GLOBAL and reparent between the NPC window and the map, so
        -- only recolor when displayed into THIS window; the world-map pack owns the map case (colors match either way).
        local function StyleQuestNPCText()
            for _, n in ipairs({
                "QuestInfoTitleHeader",
                "QuestInfoDescriptionHeader",
                "QuestInfoObjectivesHeader",
            }) do
                local fontStr = _G[n]
                if fontStr and fontStr.SetTextColor then
                    fontStr:SetTextColor(1, 0.82, 0)
                end
            end
            local objectiveRow = _G.QuestInfoRewardsFrame
            for _, n in ipairs({
                "QuestInfoDescriptionText",
                "QuestInfoObjectivesText",
                "QuestInfoGroupSize",
                "QuestInfoRewardText",
                "QuestInfoQuestType",
            }) do
                local fontStr = _G[n]
                if fontStr and fontStr.SetTextColor then
                    fontStr:SetTextColor(1, 1, 1)
                end
            end
            if objectiveRow then
                WhitenTextIn(objectiveRow) -- nested spell/effect + SimpleHTML blurbs the fields below miss
                for _, keyName in ipairs({
                    "ItemChooseText",
                    "ItemReceiveText",
                    "PlayerTitleText",
                    "SpellLearnText",
                }) do
                    local fontStr = objectiveRow[keyName]
                    if fontStr and fontStr.SetTextColor then
                        fontStr:SetTextColor(1, 1, 1)
                    end
                end
                if objectiveRow.XPFrame and objectiveRow.XPFrame.ReceiveText and objectiveRow.XPFrame.ReceiveText.SetTextColor then
                    objectiveRow.XPFrame.ReceiveText:SetTextColor(1, 1, 1)
                end
                -- Reward item tiles: drop the parchment name plate, white the name,
                -- square the icon. SquareIcon carries its own masked-texture guard
                -- (SetTexCoord on a masked texture is a hard Lua error), so a
                -- reward that Blizzard masks is left native rather than skipped
                -- by a test here.
                --
                -- Blizzard's own rings are stripped -- IconBorder is a ROUNDED
                -- quality ring, and leaving it on defeats the square crop
                -- underneath, which is why these tiles kept looking unchanged.
                --
                -- The rarity it carried comes back as a SQUARE border: the tile
                -- gets WSkin.QualityBorder (via SquareIcon's `quality` flag), which
                -- reads the color back off that same stripped ring and repaints
                -- whenever SetItemButtonQuality touches the button. Alpha 0 does
                -- not affect the read -- the ring's SHOWN state and vertex color
                -- are what carry the quality.
                if objectiveRow.RewardButtons then
                    for _, btnFrame in ipairs(objectiveRow.RewardButtons) do
                        Skin.QuestRewardTile(btnFrame)
                    end
                end

                -- REWARD BUTTONS ARE CREATED LAZILY, and populated AFTER creation.
                -- QuestInfo_GetRewardButton builds RewardButtons[index] the first
                -- time an index is needed, so a quest with an extra tile ("This
                -- quest may have additional rewards") produces a button after this
                -- pass has already run.
                --
                -- Hooked on QuestInfo_Display rather than on the accessor. The
                -- accessor hands the button back BEFORE Blizzard fills it in, so
                -- skinning there lands too early: the rarity border stuck (it
                -- repaints itself off SetItemButtonQuality) but the name plate came
                -- straight back when the tile was populated. Display runs the whole
                -- build, so by the time it returns every tile exists AND is filled.
                --
                -- Both frames are walked because which one is populated has moved
                -- between builds. Installed once.
                if not Skin.__questRewardHook and type(_G.QuestInfo_Display) == "function" then
                    Skin.__questRewardHook = true
                    hooksecurefunc("QuestInfo_Display", function()
                        Skin.QuestRewardTiles(_G.QuestInfoRewardsFrame)
                        Skin.QuestRewardTiles(_G.MapQuestInfoRewardsFrame)
                    end)
                end
                -- The single "you will also receive" tiles (money, XP, honor and
                -- the currency rows) are separate frames from RewardButtons.
                -- Money / XP / honor tiles get the SAME treatment as the item
                -- reward tiles: strip the rings, then square. Squaring alone left
                -- the gold coin wearing its border while the currency tiles beside
                -- it were clean.
                --
                -- The icon is .Icon on most of these; the money tile names it
                -- differently on some builds, so fall back to the frame's own
                -- texture regions and square whichever one is not the plate art.
                for _, keyName in ipairs({
                    "MoneyFrame",
                    "XPFrame",
                    "HonorFrame",
                    "SkillPointFrame",
                    "PlayerTitleFrame",
                }) do
                    local subPanel = objectiveRow[keyName]
                    if subPanel then
                        for _, ak in ipairs({
                            "NameFrame",
                            "IconBorder",
                            "IconOverlay",
                            "IconOverlay2",
                            "IconBorder2",
                            "Border",
                        }) do
                            local part = subPanel[ak]
                            if part and part.SetAlpha and part.IsObjectType and part:IsObjectType("Texture") then
                                part:SetAlpha(0)
                            end
                        end
                        if subPanel.Icon then
                            Skin.SquareIcon(subPanel.Icon, nil)
                        elseif subPanel.GetRegions then
                            local regs = { subPanel:GetRegions() }
                            for ri = 1, #regs do
                                local region = regs[ri]
                                if
                                    region
                                    and region.IsObjectType
                                    and region:IsObjectType("Texture")
                                    and region:GetAlpha() > 0
                                then
                                    Skin.SquareIcon(region, nil)
                                end
                            end
                        end
                    end
                end
                if objectiveRow.Header and objectiveRow.Header.SetTextColor then
                    objectiveRow.Header:SetTextColor(1, 0.82, 0)
                end
            end
            local of = _G.QuestInfoObjectivesFrame
            if of and of.Objectives then
                for _, object in ipairs(of.Objectives) do
                    if object and object.SetTextColor then
                        object:SetTextColor(1, 1, 1)
                    end
                end
            end
        end

        -- One greeting-panel quest title button: keep the icon, white the text.
        -- Available quests bake a |cff000000 code into the string that SetTextColor cannot override, so rewrite it to white in place.
        local function SkinQuestGreetingButton(btnFrame)
            if not btnFrame or btnFrame:IsForbidden() then
                return
            end
            if btnFrame.Icon and btnFrame.Icon.SetDrawLayer then
                btnFrame.Icon:SetDrawLayer("ARTWORK")
            end
            local fontStr = btnFrame.GetFontString and btnFrame:GetFontString()
            if fontStr then
                Skin.Font(fontStr)
                Skin.White(fontStr)
                local txt = fontStr.GetText and fontStr:GetText()
                if txt and txt:find("|cff000000", 1, true) then
                    fontStr:SetText((txt:gsub("|cff000000", "|cffffffff")))
                end
            end
        end
        -- Greeting text + section labels + quest title buttons. Blizzard re-applies the
        -- dark parchment material color in the greeting panel's OnShow AFTER our skin, so
        -- re-white on every show (hooked below), not once here. The greeting paragraph's
        -- global is the bare "GreetingText" (QuestFrame.xml), NOT QuestGreetingText.
        local function StyleQuestGreeting()
            if _G.GreetingText then
                Skin.White(_G.GreetingText)
                RecolorDarkText(_G.GreetingText)
            end
            for _, n in ipairs({ "CurrentQuestsText", "AvailableQuestsText" }) do
                local fontStr = _G[n]
                if fontStr then
                    Skin.White(fontStr)
                    RecolorDarkText(fontStr)
                end
            end
            local gp = _G.QuestFrameGreetingPanel
            if gp and gp.titleButtonPool then
                for btnFrame in gp.titleButtonPool:EnumerateActive() do
                    SkinQuestGreetingButton(btnFrame)
                end
            end
        end

        if _G.GreetingText then
            Skin.Font(_G.GreetingText)
        end
        for _, n in ipairs({ "CurrentQuestsText", "AvailableQuestsText" }) do
            local fontStr = _G[n]
            if fontStr then
                Skin.Font(fontStr)
            end
        end
        if _G.QuestGreetingFrameHorizontalBreak and _G.QuestGreetingFrameHorizontalBreak.SetAlpha then
            _G.QuestGreetingFrameHorizontalBreak:SetAlpha(0)
        end
        StyleQuestGreeting()

        -- Progress panel static text.
        if _G.QuestProgressTitleText then
            Skin.Font(_G.QuestProgressTitleText)
            _G.QuestProgressTitleText:SetTextColor(1, 0.82, 0)
        end
        if _G.QuestProgressText then
            Skin.Font(_G.QuestProgressText)
            Skin.White(_G.QuestProgressText)
        end

        if not _questHooked then
            _questHooked = true
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_Quest()
                    end
                end)
            )
            -- Greeting rows repopulate on QUEST_GREETING / QUEST_LOG_UPDATE.
            local gp = _G.QuestFrameGreetingPanel
            if gp then
                gp:HookScript("OnShow", Skin.Debounce(StyleQuestGreeting))
            end
            if type(_G.QuestFrameGreetingPanel_OnShow) == "function" then
                hooksecurefunc("QuestFrameGreetingPanel_OnShow", function()
                    StyleQuestGreeting()
                    if C_Timer then
                        C_Timer.After(0, StyleQuestGreeting)
                    end
                end)
            end
            -- Body text: Blizzard re-colors on each display, so re-assert in the
            -- hook and again next frame (objectives are colored after this).
            if type(_G.QuestInfo_Display) == "function" then
                hooksecurefunc("QuestInfo_Display", function(_, parentFrame)
                    if not parentFrame then
                        return
                    end
                    local p, isQuest = parentFrame, false
                    for _i = 1, 8 do
                        if p == win then
                            isQuest = true
                            break
                        end
                        p = p.GetParent and p:GetParent()
                        if not p then
                            break
                        end
                    end
                    if not isQuest then
                        return
                    end
                    StyleQuestNPCText()
                    if C_Timer then
                        C_Timer.After(0, StyleQuestNPCText)
                    end
                end)
            end
            if type(_G.QuestFrameProgressItems_Update) == "function" then
                hooksecurefunc("QuestFrameProgressItems_Update", function()
                    local ri = _G.QuestProgressRequiredItemsText
                    if ri and ri.SetTextColor then
                        ri:SetTextColor(1, 0.82, 0)
                    end
                    local rm = _G.QuestProgressRequiredMoneyText
                    if rm and rm.SetTextColor then
                        rm:SetTextColor(1, 1, 1)
                    end
                end)
            end
        end
        StyleQuestNPCText()
    end

    Skin.RegisterWindow({
        key = "quest",
        apply = Skin_Quest,
    })
end

-------------------------------------------------------------------------------
--  Inspect Recipe (InspectRecipeFrame, Blizzard_Professions): the small recipe
--  preview from a linked recipe / inspected crafter.
-------------------------------------------------------------------------------
do
    local _inspectRecipeHooked = false
    local function Skin_InspectRecipe()
        local win = _G.InspectRecipeFrame
        if not win then
            return
        end
        Skin.Shell("inspectrecipe", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "InspectRecipeFrame")
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or _G.InspectRecipeFrameTitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end
        -- Recipe background/art stays stock; form chrome only.
        local scrollFrame = win.SchematicForm
        if scrollFrame and scrollFrame.NineSlice then
            Skin.FadeNineSlice(scrollFrame.NineSlice)
        end
        if not _inspectRecipeHooked then
            _inspectRecipeHooked = true
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_InspectRecipe()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "inspectrecipe",
        addons = { Blizzard_Professions = true },
        apply = Skin_InspectRecipe,
    })
end

-------------------------------------------------------------------------------
--  Auction House (AuctionHouseFrame, Blizzard_AuctionHouseUI): shell, tabs,
--  search bar, category rail, list panels + column headers, buy/sell inputs +
--  action buttons, token panel, buy dialog, multisell progress. List item
--  icons and item-display buttons stay stock content. Visual-only throughout
--  (alpha/FFD); the commerce paths are NEVER touched.
-------------------------------------------------------------------------------
do
    local _ahHooked = false
    local function Skin_AuctionHouse()
        local win = _G.AuctionHouseFrame
        if not win then
            return
        end
        Skin.Shell("auctionhouse", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win) -- close button, SearchBox/FilterButton, scrollbars
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        for _, keyName in ipairs({ "MoneyFrameBorder", "MoneyFrameInset" }) do
            local part = win[keyName]
            if part then
                Skin.FadeRegions(part)
                if part.NineSlice then
                    Skin.FadeNineSlice(part.NineSlice)
                end
                Skin.Register(part, true)
            end
        end

        local function WhiteBtn(button)
            if button then
                Skin.Button(button)
                Skin.WhiteButtonLabel(button)
            end
        end
        -- State-driven action buttons (bid/buyout/cancel): label mirrors the native
        -- enabled/disabled state instead of reading white while disabled.
        local function StateBtn(button)
            if button then
                Skin.Button(button)
                Skin.StateButtonLabel(button)
            end
        end
        -- Money edit box: the classic template's box art is GLOBAL-suffixed
        -- (<name>Left/Middle/Right), which the engine's keyed fade misses, so it sits over our fill and reads unskinned.
        local function MoneyBox(editField)
            if not editField then
                return
            end
            Skin.EditBox(editField)
            local n = editField.GetName and editField:GetName()
            if n then
                for _, suf in ipairs({ "Left", "Middle", "Right" }) do
                    local part = _G[n .. suf]
                    if part and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
            end
        end
        local function MoneyInputs(mi)
            if not mi then
                return
            end
            MoneyBox(mi.GoldBox)
            MoneyBox(mi.SilverBox)
        end
        -- Click-to-sort column headers, guild-roster treatment: 3-slice art
        -- cleared, flat plate, white label, standard hover. Headers pool/rebuild per list refresh, re-runs from RefreshScrollFrame hook.
        local function Headers(entries)
            local headerContainer = entries and entries.HeaderContainer
            if not headerContainer then
                return
            end
            -- Top-anchored views (browse, all-auctions, bids, sell lists) seat their
            -- header row against the STATIC wash top, never a moving target, so a
            -- hidden list refreshing mid-view-swap cannot mis-seat. Item-detail
            -- views keep Blizzard's stock header position below their item display.
            -- Measured, epsilon-gated, converges. Lists may carry a washRef override
            -- (sell tab: 50/50 right-half wash); default is the rail wash.
            local wash2 = GetFFD(entries).washRef or GetFFD(win).wash
            if GetFFD(entries).seatTop and wash2 and wash2.GetTop then
                local wt0, ht0 = wash2:GetTop(), headerContainer:GetTop()
                if wt0 and ht0 and math.abs((wt0 - 2) - ht0) > 0.5 then
                    local dy0 = (wt0 - 2) - ht0
                    local pointCount = headerContainer:GetNumPoints() or 0
                    local pts, success = {}, pointCount > 0
                    for idx = 1, pointCount do
                        local point, relTo, relPoint, posX, posY = headerContainer:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + dy0 }
                    end
                    if success then
                        headerContainer:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            headerContainer:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                end
            end
            -- Per-list sort strip: rides THIS list's header row (2px above),
            -- spanning the wash's width. Parented to the list, so shows/hides with its own view: no shared strip, no cross-view state.
            local partData = GetFFD(entries)
            if not partData.strip then
                local sTex = entries:CreateTexture(nil, "BACKGROUND", nil, 1)
                sTex:SetColorTexture(0.02, 0.02, 0.02, 0.5)
                sTex:SetHeight(24)
                partData.strip = sTex
                -- Also stored under a PROTECTED key: the strip is a region OF the
                -- list, so the list's restrip registration would fade our own strip
                -- on every global Restrip pass.
                partData.fill = sTex
            end
            -- Re-assert alpha: any fade pass that caught the strip zeroed the region
            -- alpha (the color's own 50% lives in SetColorTexture).
            partData.strip:SetAlpha(1)
            -- Seat-top views ride the header row. Detail views anchor to the LIST
            -- TOP instead: their "top bar" row sits there, while their
            -- HeaderContainer can be vestigial and parked far down the list
            -- (commodities view), dragging the strip down with it.
            local anchorTo, ay = headerContainer, 2
            if not GetFFD(entries).seatTop then
                anchorTo, ay = entries, 0
            end
            local wl0 = wash2 and wash2.GetLeft and wash2:GetLeft()
            local wr0 = wash2 and wash2.GetRight and wash2:GetRight()
            local al0 = anchorTo:GetLeft()
            if wl0 and wr0 and al0 then
                partData.strip:ClearAllPoints()
                partData.strip:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", wl0 - al0, ay)
                partData.strip:SetPoint("TOPRIGHT", anchorTo, "TOPLEFT", wr0 - al0, ay)
            end
            local children = { headerContainer:GetChildren() }
            for idx = 1, #children do
                local colour = children[idx]
                if colour and colour.GetObjectType and colour:GetObjectType() == "Button" then
                    local hd = GetFFD(colour)
                    if not hd.bg then
                        for _, k2 in ipairs({ "Left", "Middle", "Right" }) do
                            local t2 = colour[k2]
                            if t2 and t2.SetTexture then
                                t2:SetTexture("")
                            end
                        end
                        Skin.FadeRegions(colour)
                        -- Invisible plate: the full-width sort strip is the row's
                        -- ONE background (a filled plate would STACK on the 50%
                        -- strip and read darker wherever a column sits). The
                        -- texture stays only as the skinned-guard + keep marker.
                        local bgTex = SolidTex(colour, "BACKGROUND", 0.02, 0.02, 0.02, 0)
                        bgTex:SetPoint("TOPLEFT", 1, -1)
                        bgTex:SetPoint("BOTTOMRIGHT", -1, 1)
                        hd.bg = bgTex
                        local hoverTex = SolidTex(colour, "HIGHLIGHT", 1, 1, 1, 0.1)
                        hoverTex:SetAllPoints(colour)
                        hd.hover = hoverTex
                        Skin.Register(colour, true)
                    end
                    local fontStr = colour.GetFontString and colour:GetFontString()
                    if fontStr then
                        Skin.White(fontStr)
                    end
                    -- Hover wash spans the full sort-strip height (the button is
                    -- shorter): re-seat against the strip's live rect each pass.
                    -- Visual only; the hit rect stays Blizzard's.
                    local strip = GetFFD(entries).strip
                    if hd.hover and strip and strip.GetTop then
                        local st, sbot = strip:GetTop(), strip:GetBottom()
                        local ct, cbot = colour:GetTop(), colour:GetBottom()
                        if st and sbot and ct and cbot then
                            hd.hover:ClearAllPoints()
                            hd.hover:SetPoint("TOPLEFT", colour, "TOPLEFT", 0, st - ct)
                            hd.hover:SetPoint("BOTTOMRIGHT", colour, "BOTTOMRIGHT", 0, sbot - cbot)
                        end
                    end
                end
            end
        end
        -- Refresh corner: the house refresh glyph; quantity goes white.
        local function SkinRefresh(rf)
            if not rf then
                return
            end
            if rf.TotalQuantity then
                Skin.White(rf.TotalQuantity)
            end
            Skin.RefreshGlyph(rf.RefreshButton)
        end
        -- List panel: framed chrome off, slim scrollbar, headers when present.
        -- seatTop: top-anchored views seat header row at the wash top; item-detail views keep stock header position.
        local function List(entries, hasHeader, seatTop)
            if not entries then
                return
            end
            local labelData = GetFFD(entries)
            labelData.seatTop = seatTop and true or nil
            -- Spare our own strip: it is a region of this list, and an unspared
            -- fade here (every skin pass) blanks the sort bar.
            Skin.FadeRegions(entries, labelData.strip and { [labelData.strip] = true } or nil)
            if entries.NineSlice then
                Skin.FadeNineSlice(entries.NineSlice)
            end
            Skin.Register(entries, true)
            Skin.ScrollBarsIn(entries)
            SkinRefresh(entries.RefreshFrame)
            if hasHeader then
                Headers(entries)
                if entries.RefreshScrollFrame and not GetFFD(entries).hdrHook then
                    GetFFD(entries).hdrHook = true
                    hooksecurefunc(entries, "RefreshScrollFrame", function(l)
                        Headers(l)
                    end)
                end
                -- The strip's anchors need live rects: a pass run while the view was hidden
                -- leaves it unanchored (invisible), so re-run on the list's own show.
                if not GetFFD(entries).hdrShowHook then
                    GetFFD(entries).hdrShowHook = true
                    entries:HookScript(
                        "OnShow",
                        Skin.Debounce(function()
                            Headers(entries)
                        end)
                    )
                end
            end
        end
        -- Item display plate (buy/sell/auctions detail): chrome off; the item
        -- button stays stock content.
        local function ItemDisplay(owner)
            local idp = owner and owner.ItemDisplay
            if not idp then
                return
            end
            Skin.FadeRegions(idp)
            if idp.NineSlice then
                Skin.FadeNineSlice(idp.NineSlice)
            end
            Skin.Register(idp, true)
        end
        -- Sell panel: inputs, duration dropdown, post button, buyout checkbox.
        -- Sell-tab inputs run 5px shorter (scoped here, SellFrame only serves the two sell views).
        local function SlimInput(editField)
            if not editField or GetFFD(editField).slimmed then
                return
            end
            GetFFD(editField).slimmed = true
            local hgt = editField:GetHeight()
            if hgt and hgt > 5 then
                editField:SetHeight(hgt - 5)
            end
        end
        local function SellFrame(scrollFrame)
            if not scrollFrame then
                return
            end
            Skin.FadeRegions(scrollFrame)
            Skin.Register(scrollFrame, true)
            ItemDisplay(scrollFrame)
            if scrollFrame.QuantityInput then
                if scrollFrame.QuantityInput.InputBox then
                    Skin.EditBox(scrollFrame.QuantityInput.InputBox)
                    SlimInput(scrollFrame.QuantityInput.InputBox)
                end
                WhiteBtn(scrollFrame.QuantityInput.MaxButton)
            end
            for _, pk in ipairs({ "PriceInput", "SecondaryPriceInput" }) do
                local mi = scrollFrame[pk] and scrollFrame[pk].MoneyInputFrame
                if mi then
                    MoneyInputs(mi)
                    SlimInput(mi.GoldBox)
                    SlimInput(mi.SilverBox)
                end
            end
            if scrollFrame.Duration and scrollFrame.Duration.Dropdown then
                Skin.Dropdown(scrollFrame.Duration.Dropdown)
            end
            WhiteBtn(scrollFrame.PostButton)
            local bmc = scrollFrame.BuyoutModeCheckButton
            if bmc then
                Skin.Checkbox(bmc)
                -- Do NOT resize this checkbox: an explicit resize inside Blizzard's
                -- sell-form layout pass makes box + label vanish once an item is
                -- placed. Label rides 6px right (one-shot, points preserved).
                local labelText = bmc.Text or (bmc.GetFontString and bmc:GetFontString())
                if labelText and not GetFFD(labelText).shifted then
                    local pointCount = labelText:GetNumPoints() or 0
                    local pts, success = {}, pointCount > 0
                    for idx = 1, pointCount do
                        local point, relTo, relPoint, posX, posY = labelText:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, (posX or 0) + 6, posY or 0 }
                    end
                    if success then
                        GetFFD(labelText).shifted = true
                        labelText:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            labelText:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                end
            end
        end

        -- Search bar: search button white; favorites star keeps its art (professions
        -- favorites-button treatment). Filter dropdown matches search button's
        -- height, label pinned left, active-filter clear X is the house glyph lifted above the dropdown's border strips.
        local scrollBar = win.SearchBar
        if scrollBar then
            WhiteBtn(scrollBar.SearchButton)
            -- Favorites button: the star is its Icon key here (the professions
            -- version keeps it in the Normal texture, hence no restore). Favoriting
            -- re-raises the button's state art, so every non-Icon texture gets a
            -- self-guarding fade, re-hidden the moment Blizzard re-textures/shows it.
            local fsb = scrollBar.FavoritesSearchButton
            if fsb then
                Skin.Button(fsb, { "Icon" })
                local fd2 = GetFFD(fsb)
                if not fd2.favPinned then
                    fd2.favPinned = true
                    local regionList = { fsb:GetRegions() }
                    for idx = 1, #regionList do
                        local region = regionList[idx]
                        if
                            region
                            and region ~= fsb.Icon
                            and region ~= fd2.bg
                            and region ~= fd2.hover
                            and region.IsObjectType
                            and region:IsObjectType("Texture")
                        then
                            region:SetAlpha(0)
                            for _, m in ipairs({ "SetAtlas", "SetTexture", "Show" }) do
                                if type(region[m]) == "function" then
                                    hooksecurefunc(region, m, function(rr)
                                        rr:SetAlpha(0)
                                    end)
                                end
                            end
                        end
                    end
                end
            end
            local foundBottom = scrollBar.FilterButton
            if foundBottom then
                LeftAlignFilterLabel(foundBottom)
                local sbtn = scrollBar.SearchButton
                local hgt = sbtn and sbtn.GetHeight and sbtn:GetHeight()
                if hgt and hgt > 0 and foundBottom.SetHeight then
                    foundBottom:SetHeight(hgt)
                end
                SkinFilterResetX(foundBottom.ClearFiltersButton, foundBottom)
            end
        end

        -- Category rail: framed chrome off; pooled buttons restyle from the setup
        -- hook below (white selection/hover washes, never accent). Rail's TOP edge drops 10px (bottom stays), chained buttons pull 1px into each other.
        local cats = win.CategoriesList
        if cats then
            Skin.FadeRegions(cats)
            if cats.NineSlice then
                Skin.FadeNineSlice(cats.NineSlice)
            end
            Skin.Register(cats, true)
            Skin.ScrollBarsIn(cats)
            if not GetFFD(cats).topShift then
                local pointCount = cats:GetNumPoints() or 0
                local pts, success = {}, pointCount > 0
                for idx = 1, pointCount do
                    local point, relTo, relPoint, posX, posY = cats:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) - (point:find("TOP", 1, true) and 10 or 0) }
                end
                if success then
                    GetFFD(cats).topShift = true
                    cats:ClearAllPoints()
                    for idx = 1, #pts do
                        local tbl = pts[idx]
                        cats:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                    end
                end
            end
        end
        -- Rail row spacing -1: the rail is a ScrollBox, so spacing lives in the
        -- scroll view's PADDING (per-button anchor surgery is a no-op, the view
        -- recomputes positions). Official padding setter, pcall-isolated, then a full update relays out the visible rows. One-shot.
        local function TightenCatButtons()
            if not cats or GetFFD(cats).spacingSet then
                return
            end
            local tabBox = cats.ScrollBox
            local view = tabBox and tabBox.GetView and tabBox:GetView()
            if not (view and view.SetPadding) then
                return
            end
            GetFFD(cats).spacingSet = true
            pcall(function()
                local top, bottom, left, right = 0, 0, 0, 0
                local pad = view.GetPadding and view:GetPadding()
                if pad then
                    top = (pad.GetTop and pad:GetTop()) or 0
                    bottom = (pad.GetBottom and pad:GetBottom()) or 0
                    left = (pad.GetLeft and pad:GetLeft()) or 0
                    right = (pad.GetRight and pad:GetRight()) or 0
                end
                view:SetPadding(top, bottom, left, right, -1)
                if tabBox.FullUpdate then
                    tabBox:FullUpdate(true)
                end
            end)
        end
        TightenCatButtons()

        -- Zone lines, guild-window treatment: 1-physical-px 0.15 separators at the
        -- top seam (below search row), rail's right edge and bottom seam, plus a 2%
        -- white wash over the results region. All on OUR OWN host frame (direct f
        -- regions are wiped by the shell's region fade on every re-skin pass); the
        -- vertical line and wash anchor to CategoriesList (a stable container) so they track the rail.
        local frameData = GetFFD(win)
        if not frameData.zoneLines and cats then
            frameData.zoneLines = true
            local pixel = 1
            do
                local PPx = CludesUI.PP
                local es = win:GetEffectiveScale()
                if PPx and PPx.perfect and es and es > 0 then
                    pixel = PPx.perfect / es
                end
            end
            local owner = CreateFrame("Frame", nil, win)
            owner:SetAllPoints(win)
            owner:SetFrameLevel(win:GetFrameLevel())
            frameData.zoneHost = owner
            local topSep = owner:CreateTexture(nil, "ARTWORK")
            topSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            topSep:SetHeight(pixel)
            topSep:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -77)
            topSep:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -77)
            local botSep = owner:CreateTexture(nil, "ARTWORK")
            botSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            botSep:SetHeight(pixel)
            botSep:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 30)
            botSep:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 30)
            -- RAIL-based wash+divider (buy+auctions tabs: left sidebar column), on
            -- their own sub-host so the SELL tab (no rail, 50/50 split) can swap in
            -- its own set; visibility driven from the displayMode sync below.
            local railHost = CreateFrame("Frame", nil, owner)
            railHost:SetAllPoints(owner)
            railHost:SetFrameLevel(owner:GetFrameLevel())
            frameData.railHost = railHost
            -- The wash (and everything anchored to it) rides the rail's top, which
            -- sits 10px lower for the link shift, so lift the zone's top back up and keep the results area flush with the top divider.
            local washTex = railHost:CreateTexture(nil, "BACKGROUND")
            washTex:SetColorTexture(1, 1, 1, 0.02)
            washTex:SetPoint("TOPLEFT", cats, "TOPRIGHT", 2 + pixel, 5)
            washTex:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 30 + pixel)
            -- The sort strip is PER LIST (created in Headers, riding each list's own
            -- header row): a single shared moving strip bleeds across views, since
            -- hidden lists refreshing while another view lowered it would seat against the wrong position.
            frameData.zonePx = pixel -- one physical pixel, for wash-edge math
            frameData.wash = washTex -- header seats + strip widths measure this
            -- Left border of the washed region: flush with the WASH's top AND
            -- bottom (rail frame runs lower than the wash, so its bottom corner is the wrong anchor).
            local sideSep = railHost:CreateTexture(nil, "ARTWORK")
            sideSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            sideSep:SetWidth(pixel)
            sideSep:SetPoint("TOPLEFT", washTex, "TOPLEFT", -pixel, 0)
            sideSep:SetPoint("BOTTOMLEFT", washTex, "BOTTOMLEFT", -pixel, 0)
            -- SELL-tab zone: 50/50 split, center divider, wash over the right half
            -- only. Hidden until the displayMode sync shows it.
            local sellHost = CreateFrame("Frame", nil, owner)
            sellHost:SetAllPoints(owner)
            sellHost:SetFrameLevel(owner:GetFrameLevel())
            sellHost:Hide()
            frameData.sellHost = sellHost
            local sellWash = sellHost:CreateTexture(nil, "BACKGROUND")
            sellWash:SetColorTexture(1, 1, 1, 0.02)
            sellWash:SetPoint("TOPLEFT", win, "TOP", pixel - 30, -77 - pixel)
            sellWash:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 30 + pixel)
            frameData.sellWash = sellWash
            local sellSep = sellHost:CreateTexture(nil, "ARTWORK")
            sellSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            sellSep:SetWidth(pixel)
            sellSep:SetPoint("TOPLEFT", sellWash, "TOPLEFT", -pixel, 0)
            sellSep:SetPoint("BOTTOMLEFT", sellWash, "BOTTOMLEFT", -pixel, 0)
        end

        -- Bottom clamp: rail+list frames natively run BELOW the bottom divider, so
        -- pull each element's bottom edge up to the seam. Measured, guarded
        -- one-shot per element, re-attempted every pass until rects exist. Elements
        -- with a BOTTOM anchor get it raised; pure height-sized ones shrink instead.
        local function ClampBottom(part)
            if not part or GetFFD(part).botClamped then
                return
            end
            local foundBottom, eb2 = win:GetBottom(), part:GetBottom()
            if not (foundBottom and eb2) then
                return
            end
            local dy = (foundBottom + 30 + (frameData.zonePx or 1)) - eb2
            if dy < 0.5 then
                GetFFD(part).botClamped = true
                return
            end
            local pointCount = part:GetNumPoints() or 0
            local pts, success, touched = {}, pointCount > 0, false
            for idx = 1, pointCount do
                local point, relTo, relPoint, posX, posY = part:GetPoint(idx)
                if not point then
                    success = false
                    break
                end
                local isBottom = point:find("BOTTOM", 1, true) and true or false
                if isBottom then
                    touched = true
                end
                pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + (isBottom and dy or 0) }
            end
            if success and touched then
                GetFFD(part).botClamped = true
                part:ClearAllPoints()
                for idx = 1, #pts do
                    local t2 = pts[idx]
                    part:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5])
                end
            elseif success then
                local hgt = part:GetHeight()
                if hgt and hgt > dy then
                    GetFFD(part).botClamped = true
                    part:SetHeight(hgt - dy)
                end
            end
        end
        ClampBottom(cats)

        -- Browse results (Buy tab).
        local br = win.BrowseResultsFrame
        if br then
            List(br.ItemList, true, true)
        end
        if br then
            ClampBottom(br.ItemList)
        end

        -- Commodities buy view.
        local cbf = win.CommoditiesBuyFrame
        if cbf then
            WhiteBtn(cbf.BackButton)
            -- Back button 3px lower (one-shot, all points preserved).
            if cbf.BackButton and not GetFFD(cbf.BackButton).dropped then
                local bb = cbf.BackButton
                local pointCount = bb:GetNumPoints() or 0
                local pts, success = {}, pointCount > 0
                for idx = 1, pointCount do
                    local point, relTo, relPoint, posX, posY = bb:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) - 3 }
                end
                if success then
                    GetFFD(bb).dropped = true
                    bb:ClearAllPoints()
                    for idx = 1, #pts do
                        local tbl = pts[idx]
                        bb:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                    end
                end
            end
            -- Commodities uses the SIDE-BY-SIDE layout (buy panel left, price list
            -- right, NO sort captions), so no header/strip (a wash-wide strip would
            -- cut across the buy panel). Only item-buy (display above, headered list below) gets the strip.
            List(cbf.ItemList, false)
            local buttonData = cbf.BuyDisplay
            if buttonData then
                Skin.FadeRegions(buttonData)
                Skin.Register(buttonData, true)
                ItemDisplay(buttonData)
                local qib = buttonData.QuantityInput and buttonData.QuantityInput.InputBox
                if qib then
                    Skin.EditBox(qib)
                    if not GetFFD(qib).slimmed then
                        GetFFD(qib).slimmed = true
                        local hgt = qib:GetHeight()
                        if hgt and hgt > 5 then
                            qib:SetHeight(hgt - 5)
                        end
                    end
                end
                StateBtn(buttonData.BuyButton)
            end
        end

        -- Single-item buy view.
        local ibf = win.ItemBuyFrame
        if ibf then
            WhiteBtn(ibf.BackButton)
            if ibf.BuyoutFrame then
                StateBtn(ibf.BuyoutFrame.BuyoutButton)
            end
            if ibf.BidFrame then
                StateBtn(ibf.BidFrame.BidButton)
                -- Bid button rides 20px right on the bottom bar (one-shot).
                local bb = ibf.BidFrame.BidButton
                if bb and not GetFFD(bb).shiftedX then
                    local pointCount = bb:GetNumPoints() or 0
                    local pts, success = {}, pointCount > 0
                    for idx = 1, pointCount do
                        local point, relTo, relPoint, posX, posY = bb:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        pts[idx] = { point, relTo, relPoint, (posX or 0) + 20, posY or 0 }
                    end
                    if success then
                        GetFFD(bb).shiftedX = true
                        bb:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            bb:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                end
            end
            ItemDisplay(ibf)
            List(ibf.ItemList, true)
        end
        local function ReFadeMoney()
            for _, n in ipairs({
                "AuctionHouseFrameGold",
                "AuctionHouseFrameSilver",
                "BidAmountGold",
                "BidAmountSilver",
            }) do
                MoneyBox(_G[n])
            end
        end
        ReFadeMoney()
        -- Bid views initialize their money-box art on THEIR show, and sub-view
        -- swaps never re-fire the window's OnShow (the re-skin driver), so re-fade
        -- from the views' own OnShow.
        for _, host2 in ipairs({ ibf, win.AuctionsFrame or _G.AuctionHouseFrameAuctionsFrame }) do
            if host2 and not GetFFD(host2).moneyHook then
                GetFFD(host2).moneyHook = true
                host2:HookScript("OnShow", Skin.Debounce(ReFadeMoney))
                if host2.BidFrame and host2.BidFrame.HookScript then
                    host2.BidFrame:HookScript("OnShow", Skin.Debounce(ReFadeMoney))
                end
            end
        end

        -- Sell tab.
        SellFrame(win.ItemSellFrame)
        SellFrame(win.CommoditiesSellFrame)
        List(win.ItemSellList, true, true)
        List(win.CommoditiesSellList, true, true)
        -- Sell lists measure against the sell tab's 50/50 wash, not the rail one.
        if win.ItemSellList then
            GetFFD(win.ItemSellList).washRef = frameData.sellWash
        end
        if win.CommoditiesSellList then
            GetFFD(win.CommoditiesSellList).washRef = frameData.sellWash
        end
        local tsf = win.WoWTokenSellFrame
        if tsf then
            Skin.FadeRegions(tsf)
            Skin.Register(tsf, true)
            ItemDisplay(tsf)
            WhiteBtn(tsf.PostButton)
            if tsf.DummyItemList then
                Skin.FadeRegions(tsf.DummyItemList)
                Skin.Register(tsf.DummyItemList, true)
                Skin.ScrollBarsIn(tsf)
            end
        end

        -- My auctions tab.
        local auctionsFrame = win.AuctionsFrame or _G.AuctionHouseFrameAuctionsFrame
        if auctionsFrame then
            Skin.FadeRegions(auctionsFrame)
            Skin.Register(auctionsFrame, true)
            ItemDisplay(auctionsFrame)
            -- Selected-item spot: the guild-sidebar tile sheet behind it.
            local idp = auctionsFrame.ItemDisplay
            if idp then
                local importData = GetFFD(idp)
                if not importData.card then
                    local cardFrame = idp:CreateTexture(nil, "BACKGROUND", nil, -5)
                    cardFrame:SetAtlas("Ui-Dialog-New-Background")
                    cardFrame:SetPoint("TOPLEFT", idp, "TOPLEFT", 0, 0)
                    cardFrame:SetPoint("BOTTOMRIGHT", idp, "BOTTOMRIGHT", 0, 0)
                    cardFrame:SetAlpha(0.5)
                    importData.card = cardFrame
                end
            end
            if auctionsFrame.BuyoutFrame then
                StateBtn(auctionsFrame.BuyoutFrame.BuyoutButton)
            end
            if auctionsFrame.BidFrame then
                StateBtn(auctionsFrame.BidFrame.BidButton)
            end
            StateBtn(auctionsFrame.CancelAuctionButton)
            List(auctionsFrame.CommoditiesList, true)
            List(auctionsFrame.ItemList, true)
            List(auctionsFrame.SummaryList, false)
            List(auctionsFrame.AllAuctionsList, true, true)
            List(auctionsFrame.BidsList, true, true)
            -- Auctions sidebar (SummaryList): its rows are a SEPARATE ScrollBox
            -- pool that the buy tab's category-rail setup hook never touches, so
            -- they get the same tile treatment here (flat card + border, white
            -- label, washes spanning the full tile).
            local sum = auctionsFrame.SummaryList
            local summaryScroll = sum and sum.ScrollBox
            if summaryScroll and not GetFFD(sum).rowHook then
                GetFFD(sum).rowHook = true
                local function SkinSummaryRow(row)
                    if not row or (row.IsForbidden and row:IsForbidden()) then
                        return
                    end
                    -- Rows run narrower than the column: match the box width,
                    -- re-asserted per Update pass once the view lays out.
                    local bw = summaryScroll.GetWidth and summaryScroll:GetWidth()
                    if bw and bw > 1 and row.GetWidth and math.abs((row:GetWidth() or 0) - bw) > 1 then
                        row:SetWidth(bw)
                    end
                    local regionData = GetFFD(row)
                    if not regionData.bg then
                        local bgTex = row:CreateTexture(nil, "BACKGROUND", nil, -3)
                        bgTex:SetColorTexture(Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
                        bgTex:SetPoint("TOPLEFT", 1, -1)
                        bgTex:SetPoint("BOTTOMRIGHT", -1, 1)
                        regionData.bg = bgTex
                        Skin.AddBorder(row)
                        -- NEVER restrip-register content rows: a global Restrip
                        -- (any window's show pass, e.g. opening bags during the
                        -- sell flow) would fade the item ICON and the
                        -- hover/selection washes. The Update hook is their upkeep.
                    end
                    if row.HighlightTexture then
                        row.HighlightTexture:SetColorTexture(1, 1, 1, 0.1)
                        row.HighlightTexture:ClearAllPoints()
                        row.HighlightTexture:SetAllPoints(row)
                    end
                    if row.SelectedHighlight then
                        row.SelectedHighlight:SetColorTexture(1, 1, 1, 0.15)
                        row.SelectedHighlight:ClearAllPoints()
                        row.SelectedHighlight:SetAllPoints(row)
                    end
                    if row.Text then
                        Skin.White(row.Text)
                    end
                end
                hooksecurefunc(
                    summaryScroll,
                    "Update",
                    Skin.Debounce(function()
                        if summaryScroll.ForEachFrame and summaryScroll:IsVisible() then
                            summaryScroll:ForEachFrame(SkinSummaryRow)
                        end
                    end)
                )
                -- Initial pass only once the box has a view: ForEachFrame on an
                -- uninitialized ScrollBox errors inside Blizzard's code at addon
                -- load. The Update hook covers everything after init.
                if summaryScroll.ForEachFrame and summaryScroll.GetView and summaryScroll:GetView() then
                    pcall(summaryScroll.ForEachFrame, summaryScroll, SkinSummaryRow)
                end
            end
            -- Measured seats (rects exist only once the auctions view lays out, so
            -- each is a guarded one-shot retried from af's OnShow): SummaryList
            -- column matches the buy rail's exact edges (sidebar tiles line up
            -- between tabs); main lists span the full washed region and sit lower.
            local function SeatSummary()
                if not sum or GetFFD(sum).seated then
                    return
                end
                local cl2, cr2 = cats and cats:GetLeft(), cats and cats:GetRight()
                local sl2, sr2 = sum:GetLeft(), sum:GetRight()
                if not (cl2 and cr2 and sl2 and sr2) then
                    return
                end
                GetFFD(sum).seated = true
                local dxL, dxR = cl2 - sl2, cr2 - sr2
                local pointCount = sum:GetNumPoints() or 0
                local pts, success = {}, pointCount > 0
                for idx = 1, pointCount do
                    local point, relTo, relPoint, posX, posY = sum:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    local dx = point:find("RIGHT", 1, true) and dxR or dxL
                    pts[idx] = { point, relTo, relPoint, (posX or 0) + dx, posY or 0 }
                end
                if success then
                    sum:ClearAllPoints()
                    for idx = 1, #pts do
                        local t2 = pts[idx]
                        sum:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5])
                    end
                end
            end
            local function SeatMainList(l)
                if not l or GetFFD(l).seated then
                    return
                end
                local fr2 = win:GetRight()
                local cr2 = cats and cats:GetRight()
                local ll2, lr2 = l:GetLeft(), l:GetRight()
                if not (fr2 and cr2 and ll2 and lr2) then
                    return
                end
                GetFFD(l).seated = true
                local dxL = (cr2 + 2 + (frameData.zonePx or 1)) - ll2
                local dxR = fr2 - lr2
                local pointCount = l:GetNumPoints() or 0
                local pts, success = {}, pointCount > 0
                for idx = 1, pointCount do
                    local point, relTo, relPoint, posX, posY = l:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    local dx = point:find("RIGHT", 1, true) and dxR or dxL
                    pts[idx] = { point, relTo, relPoint, (posX or 0) + dx, (posY or 0) - 7 }
                end
                if success then
                    l:ClearAllPoints()
                    for idx = 1, #pts do
                        local t2 = pts[idx]
                        l:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5])
                    end
                end
            end
            -- Item rows' white backing spans the full washed width: (a) the
            -- ScrollBox reserves a right gutter, so stretch it to the list's right
            -- edge (slim scrollbar overlays fine); (b) row backing/hover textures
            -- are sized to TABLE COLUMNS, not the row, so stretch every row-level
            -- texture to the row (cell content on child frames untouched). Rows pool, so this runs per Update.
            local function WidenRows(l)
                local listScroll = l and l.ScrollBox
                if not listScroll then
                    return
                end
                if not GetFFD(listScroll).widened then
                    local lr3, br3 = l:GetRight(), listScroll:GetRight()
                    if lr3 and br3 and lr3 > br3 then
                        GetFFD(listScroll).widened = true
                        local pointCount = listScroll:GetNumPoints() or 0
                        local pts, success = {}, pointCount > 0
                        for idx = 1, pointCount do
                            local point, relTo, relPoint, posX, posY = listScroll:GetPoint(idx)
                            if not point then
                                success = false
                                break
                            end
                            pts[idx] = {
                                point,
                                relTo,
                                relPoint,
                                (posX or 0) + (point:find("RIGHT", 1, true) and (lr3 - br3) or 0),
                                posY or 0,
                            }
                        end
                        if success then
                            listScroll:ClearAllPoints()
                            for idx = 1, #pts do
                                local t2 = pts[idx]
                                listScroll:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5])
                            end
                        end
                    end
                end
                if not GetFFD(listScroll).rowStretch then
                    GetFFD(listScroll).rowStretch = true
                    local function StretchRow(row)
                        if not row or (row.IsForbidden and row:IsForbidden()) then
                            return
                        end
                        if GetFFD(row).stretched then
                            return
                        end
                        GetFFD(row).stretched = true
                        local regionList = { row:GetRegions() }
                        for idx = 1, #regionList do
                            local region = regionList[idx]
                            if region and region.IsObjectType and region:IsObjectType("Texture") then
                                region:ClearAllPoints()
                                region:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
                                region:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
                            end
                        end
                    end
                    hooksecurefunc(
                        listScroll,
                        "Update",
                        Skin.Debounce(function()
                            if listScroll.ForEachFrame and listScroll:IsVisible() then
                                listScroll:ForEachFrame(StretchRow)
                            end
                        end)
                    )
                    -- Same uninitialized-ScrollBox guard as the summary rows.
                    if listScroll.ForEachFrame and listScroll.GetView and listScroll:GetView() then
                        pcall(listScroll.ForEachFrame, listScroll, StretchRow)
                    end
                end
            end
            local function SeatAuctionsTab()
                SeatSummary()
                SeatMainList(auctionsFrame.AllAuctionsList)
                SeatMainList(auctionsFrame.BidsList)
                WidenRows(auctionsFrame.AllAuctionsList)
                WidenRows(auctionsFrame.BidsList)
                -- These also run past the bottom divider (the seat drops them
                -- further). Deferred a frame: clamping against same-frame stale
                -- rects mis-measures right after the seats moved anchors. Summary
                -- ScrollBox also stretches to the reseated list's edges here since widening the LIST doesn't move its own stock anchors.
                local function clamp()
                    ClampBottom(auctionsFrame.AllAuctionsList)
                    ClampBottom(auctionsFrame.BidsList)
                    ClampBottom(auctionsFrame.SummaryList)
                    if sum and summaryScroll and not GetFFD(summaryScroll).stretched then
                        local ll2, lr2 = sum:GetLeft(), sum:GetRight()
                        local bl2, br2 = summaryScroll:GetLeft(), summaryScroll:GetRight()
                        if ll2 and lr2 and bl2 and br2 then
                            GetFFD(summaryScroll).stretched = true
                            local pointCount = summaryScroll:GetNumPoints() or 0
                            local pts, success = {}, pointCount > 0
                            for idx = 1, pointCount do
                                local point, relTo, relPoint, posX, posY = summaryScroll:GetPoint(idx)
                                if not point then
                                    success = false
                                    break
                                end
                                local dx = point:find("RIGHT", 1, true) and (lr2 - br2) or (ll2 - bl2)
                                pts[idx] = { point, relTo, relPoint, (posX or 0) + dx, posY or 0 }
                            end
                            if success then
                                summaryScroll:ClearAllPoints()
                                for idx = 1, #pts do
                                    local t2 = pts[idx]
                                    summaryScroll:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5])
                                end
                            end
                        end
                    end
                end
                if C_Timer then
                    C_Timer.After(0, clamp)
                else
                    clamp()
                end
            end
            SeatAuctionsTab()
            if not GetFFD(auctionsFrame).seatHook then
                GetFFD(auctionsFrame).seatHook = true
                auctionsFrame:HookScript("OnShow", Skin.Debounce(SeatAuctionsTab))
            end
            -- Sub-tabs: dark-active (spellbook look), 1px lower. Only the chain
            -- root moves; NormalizeTabRow re-chains the rest off it.
            local afTabs = {}
            for _, n in ipairs({
                "AuctionHouseFrameAuctionsFrameAuctionsTab",
                "AuctionHouseFrameAuctionsFrameBidsTab",
            }) do
                local t = _G[n]
                if t then
                    Skin.Tab(t, { darkActive = true })
                    afTabs[#afTabs + 1] = t
                end
            end
            local root = afTabs[1]
            if root and not GetFFD(root).dropped then
                local pointCount = root:GetNumPoints() or 0
                local pts, success = {}, pointCount > 0
                for idx = 1, pointCount do
                    local point, relTo, relPoint, posX, posY = root:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) - 1 }
                end
                if success then
                    GetFFD(root).dropped = true
                    root:ClearAllPoints()
                    for idx = 1, #pts do
                        local t2 = pts[idx]
                        root:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5])
                    end
                end
            end
            Skin.NormalizeTabRow(afTabs)
        end

        -- WoW Token results panel.
        local tr = win.WoWTokenResults
        if tr then
            Skin.FadeRegions(tr)
            Skin.Register(tr, true)
            WhiteBtn(tr.Buyout)
            Skin.ScrollBarsIn(tr)
            local titleData = tr.TokenDisplay
            if titleData then
                Skin.FadeRegions(titleData)
                if titleData.NineSlice then
                    Skin.FadeNineSlice(titleData.NineSlice)
                end
                Skin.Register(titleData, true)
            end
            local tut = tr.GameTimeTutorial
            if tut then
                if tut.NineSlice then
                    Skin.FadeNineSlice(tut.NineSlice)
                end
                if tut.Bg and tut.Bg.SetAlpha then
                    tut.Bg:SetAlpha(0)
                end
                if tut.CloseButton then
                    Skin.CloseButton(tut.CloseButton)
                end
                if tut.RightDisplay then
                    WhiteBtn(tut.RightDisplay.StoreButton)
                    if tut.RightDisplay.Label then
                        Skin.White(tut.RightDisplay.Label)
                    end
                end
                if tut.LeftDisplay and tut.LeftDisplay.Label then
                    Skin.White(tut.LeftDisplay.Label)
                end
            end
        end

        -- Confirm-purchase dialog: its border is a CHILD frame (Bg/edge pieces),
        -- out of reach of the panel's own region fade, so suppress it wholesale.
        local guildDialog = win.BuyDialog
        if guildDialog then
            Skin.Panel(guildDialog)
            if guildDialog.Border then
                Skin.FadeNineSlice(guildDialog.Border)
                Skin.Register(guildDialog.Border, true)
            end
            WhiteBtn(guildDialog.BuyNowButton)
            WhiteBtn(guildDialog.CancelButton)
        end

        -- Multisell progress popup: house bar (flat fill on a dark trough).
        local ms = _G.AuctionHouseMultisellProgressFrame
        if ms then
            Skin.FadeRegions(ms)
            Skin.Register(ms, true)
            local progressBar = ms.ProgressBar
            if progressBar then
                local progressData = GetFFD(progressBar)
                local fillTex = progressBar.GetStatusBarTexture and progressBar:GetStatusBarTexture()
                local regionList = { progressBar:GetRegions() }
                for idx = 1, #regionList do
                    local region = regionList[idx]
                    if
                        region
                        and region ~= fillTex
                        and region ~= progressData.bg
                        and region.IsObjectType
                        and region:IsObjectType("Texture")
                        and region:GetDrawLayer() ~= "HIGHLIGHT"
                    then
                        region:SetAlpha(0)
                    end
                end
                if progressBar.SetStatusBarTexture then
                    progressBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                    Skin.ApplyBarFill(progressBar)
                end
                if not progressData.bg then
                    local troughTex = progressBar:CreateTexture(nil, "BACKGROUND", nil, -1)
                    troughTex:SetColorTexture(0.12, 0.12, 0.12, 0.85)
                    troughTex:SetAllPoints(progressBar)
                    progressData.bg = troughTex
                end
                if progressBar.Text then
                    Skin.White(progressBar.Text)
                end
            end
        end

        -- Bottom tabs (Buy / Sell / My Auctions). The AH has NO PanelTemplates /
        -- selectedTabID tab state -- selection IS its displayMode -- so the
        -- engine's checks all miss and no tab reads as active. Sync the FFD
        -- selection override from the display mode instead (tab.displayMode
        -- compared by reference), refreshed on every SetDisplayMode.
        -- Reassert Buy's own anchor before chaining Sell/Auctions off it below --
        -- another addon can leave it repositioned after closing its own AH skin.
        if _G.AuctionHouseFrameBuyTab then
            _G.AuctionHouseFrameBuyTab:ClearAllPoints()
            _G.AuctionHouseFrameBuyTab:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 20, -28)
        end
        local ahTabs = {}
        for _, n in ipairs({
            "AuctionHouseFrameBuyTab",
            "AuctionHouseFrameSellTab",
            "AuctionHouseFrameAuctionsTab",
        }) do
            local t = _G[n]
            if t then
                Skin.Tab(t)
                ahTabs[#ahTabs + 1] = t
            end
        end
        Skin.NormalizeTabRow(ahTabs)
        local function SyncTabSel()
            if type(win.GetDisplayMode) ~= "function" then
                return
            end
            local success, dm = pcall(win.GetDisplayMode, win)
            if not success or dm == nil then
                return
            end
            local any = false
            for _, tab in ipairs(ahTabs) do
                if tab.displayMode ~= nil then
                    any = true
                    GetFFD(tab).selOverride = (tab.displayMode == dm)
                end
            end
            if any then
                Skin.UpdateAllTabs()
            end
            -- Zone swap: rail wash/divider on buy + auctions, the 50/50 center set
            -- on sell. Placing an item flips displayMode to a sell SUB-mode
            -- (item-sell / commodities-sell) that no longer equals the tab's own
            -- mode, so any visible sell view also counts as "on the sell tab",
            -- keeping its underline lit through the sub-modes.
            local sellTab = _G.AuctionHouseFrameSellTab
            local isSell = sellTab and sellTab.displayMode ~= nil and sellTab.displayMode == dm
            if not isSell then
                for _, keyName in ipairs({ "ItemSellFrame", "CommoditiesSellFrame", "WoWTokenSellFrame" }) do
                    local v = win[keyName]
                    if v and v:IsShown() then
                        isSell = true
                        break
                    end
                end
            end
            if frameData.railHost then
                frameData.railHost:SetShown(not isSell)
            end
            if frameData.sellHost then
                frameData.sellHost:SetShown(isSell and true or false)
            end
            if isSell and sellTab and not GetFFD(sellTab).selOverride then
                GetFFD(sellTab).selOverride = true
                Skin.UpdateAllTabs()
            end
        end
        if type(win.SetDisplayMode) == "function" and not frameData.dmHook then
            frameData.dmHook = true
            hooksecurefunc(win, "SetDisplayMode", Skin.Debounce(SyncTabSel))
        end
        SyncTabSel()

        if not _ahHooked then
            _ahHooked = true
            -- Pooled category rail buttons: the standard sidebar tile (flat card +
            -- border + white label, achievements-rail treatment) with Blizzard's
            -- selected/highlight textures recolored to the house white washes.
            -- Re-runs from Blizzard's setup function since the rows pool.
            if type(_G.AuctionHouseFilterButton_SetUp) == "function" then
                hooksecurefunc("AuctionHouseFilterButton_SetUp", function(btnFrame)
                    if not btnFrame or btnFrame:IsForbidden() then
                        return
                    end
                    local skinData = GetFFD(btnFrame)
                    if not skinData.bg then
                        local bgTex = btnFrame:CreateTexture(nil, "BACKGROUND", nil, -3)
                        bgTex:SetColorTexture(Theme.bgR + 0.015, Theme.bgG + 0.015, Theme.bgB + 0.015, Theme.bgA)
                        bgTex:SetPoint("TOPLEFT", 1, -1)
                        bgTex:SetPoint("BOTTOMRIGHT", -1, 1)
                        skinData.bg = bgTex
                        Skin.AddBorder(btnFrame)
                        -- No restrip registration: it would fade the recolored
                        -- selection/hover washes on any global Restrip pass. The
                        -- SetUp hook is these buttons' upkeep.
                    end
                    if btnFrame.NormalTexture then
                        btnFrame.NormalTexture:SetAlpha(0)
                    end
                    -- Selection/hover washes span the FULL tile; Blizzard sizes
                    -- them to the old art, short of the button edges.
                    if btnFrame.SelectedTexture then
                        btnFrame.SelectedTexture:SetColorTexture(1, 1, 1, 0.15)
                        btnFrame.SelectedTexture:ClearAllPoints()
                        btnFrame.SelectedTexture:SetAllPoints(btnFrame)
                    end
                    if btnFrame.HighlightTexture then
                        btnFrame.HighlightTexture:SetColorTexture(1, 1, 1, 0.1)
                        btnFrame.HighlightTexture:ClearAllPoints()
                        btnFrame.HighlightTexture:SetAllPoints(btnFrame)
                    end
                    local fontStr = btnFrame.Text or (btnFrame.GetFontString and btnFrame:GetFontString())
                    if fontStr then
                        Skin.White(fontStr)
                    end
                end)
                hooksecurefunc("AuctionHouseFilterButton_SetUp", Skin.Debounce(TightenCatButtons))
            end
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_AuctionHouse()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "auctionhouse",
        addons = { Blizzard_AuctionHouseUI = true },
        apply = Skin_AuctionHouse,
    })
end

-------------------------------------------------------------------------------
--  Macros (MacroFrame, Blizzard_MacroUI). Shell + tabs + action buttons +
--  text/icon wells; the icon grid and selected-macro icon stay stock content.
-------------------------------------------------------------------------------
do
    -- Icon grid slot art at 50%: every texture but the icon, hover and selection.
    -- Runs per grid button on each ScrollBox Update (every frame while scrolling),
    -- so it walks GetRegions' returns directly instead of building a table.
    local function DimSlotArt(btnFrame, ...)
        for idx = 1, select("#", ...) do
            local region = (select(idx, ...))
            if
                region
                and region ~= btnFrame.Icon
                and region ~= btnFrame.Highlight
                and region ~= btnFrame.SelectedTexture
                and region.IsObjectType
                and region:IsObjectType("Texture")
            then
                region:SetAlpha(0.5)
            end
        end
    end
    local function DimSlot(btnFrame)
        DimSlotArt(btnFrame, btnFrame:GetRegions())
    end

    -- Name-and-icon picker popup (IconSelectorPopupFrameTemplate): house panel,
    -- themed name input + buttons + type dropdown, white texts, icon grid slot art
    -- at 50% (matching the main selector grid). Used by the Macro popup and the
    -- Equipment Manager popup: backdrop(p) lays the frame's own backdrop, reskin
    -- is the caller's entry point, re-run on every show (HookShow is once per frame).
    local function Skin_IconSelectorPopup(p, backdrop, reskin)
        backdrop(p)
        if p.NineSlice then
            Skin.FadeNineSlice(p.NineSlice)
        end
        if p.Bg and p.Bg.SetAlpha then
            p.Bg:SetAlpha(0)
        end
        local bb = p.BorderBox
        if bb then
            Skin.FadeRegions(bb)
            if bb.NineSlice then
                Skin.FadeNineSlice(bb.NineSlice)
            end
            Skin.Register(bb, true)
            local editField = bb.IconSelectorEditBox
            if editField then
                Skin.EditBox(editField)
                local n = editField.GetName and editField:GetName()
                if n then
                    for _, suf in ipairs({ "Left", "Middle", "Right" }) do
                        local part = _G[n .. suf]
                        if part and part.SetAlpha then
                            part:SetAlpha(0)
                        end
                    end
                end
            end
            for _, keyName in ipairs({ "OkayButton", "CancelButton" }) do
                local button = bb[keyName]
                if button then
                    Skin.Button(button)
                    Skin.WhiteButtonLabel(button)
                end
            end
            for _, keyName in ipairs({ "IconTypeDropdown", "IconFilterDropdown" }) do
                if bb[keyName] then
                    Skin.Dropdown(bb[keyName])
                end
            end
            for _, keyName in ipairs({ "EditBoxHeaderText", "IconSelectionText", "SelectedIconText" }) do
                local fontStr = bb[keyName]
                if fontStr then
                    Skin.Font(fontStr)
                    Skin.White(fontStr)
                end
            end
        end
        local grid = p.IconSelector
        local gBox = grid and (grid.ScrollBox or (grid.ForEachFrame and grid))
        if grid then
            Skin.FadeRegions(grid)
            Skin.Register(grid, true)
            Skin.ScrollBarsIn(p)
        end
        if gBox then
            local foundData = GetFFD(p)
            if not foundData.iconDim then
                foundData.iconDim = function()
                    if gBox.ForEachFrame and gBox:IsVisible() then
                        gBox:ForEachFrame(DimSlot)
                    end
                end
                hooksecurefunc(gBox, "Update", Skin.Debounce(foundData.iconDim))
            end
            if gBox.GetView and gBox:GetView() then
                pcall(foundData.iconDim)
            end
        end
        -- Built only while the frame has no show hook (HookShow keeps the first).
        if not GetFFD(p).showHook then
            Skin.HookShow(
                p,
                Skin.Debounce(function()
                    if p:IsVisible() then
                        reskin()
                    end
                end)
            )
        end
    end

    -- Macro popup (MacroPopupFrame): uses the shared icon selector popup skin.
    local function Skin_MacroPopup()
        local p = _G.MacroPopupFrame
        if not p then
            return
        end
        Skin_IconSelectorPopup(p, Skin.Panel, Skin_MacroPopup)
    end

    local _macroHooked = false
    local function Skin_Macros()
        local win = _G.MacroFrame
        if not win then
            return
        end
        Skin.Shell("macros", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "MacroFrame")
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if win.Inset then
            Skin.Inset(win.Inset)
        end
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or _G.MacroFrameTitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end

        for _, n in ipairs({
            "MacroSaveButton",
            "MacroCancelButton",
            "MacroDeleteButton",
            "MacroNewButton",
            "MacroExitButton",
            "MacroEditButton",
        }) do
            local button = _G[n]
            if button then
                Skin.Button(button)
                Skin.WhiteButtonLabel(button)
            end
        end

        local mTabs = {}
        for idx = 1, 2 do
            local t = _G["MacroFrameTab" .. idx]
            if t then
                Skin.Tab(t, { darkActive = true })
                mTabs[#mTabs + 1] = t
            end
        end
        -- Left-align the row: the chain root reseats so its left edge sits 12px
        -- from the window's left (measured one-shot, rect-gated, retried by the
        -- show re-run). Tab2 chains off it via the seam normalization.
        local mt1 = mTabs[1]
        if mt1 and not GetFFD(mt1).leftAligned then
            local fl, tl = win:GetLeft(), mt1:GetLeft()
            if fl and tl then
                local dx = (fl + 12) - tl
                local pointCount = mt1:GetNumPoints() or 0
                local pts, success = {}, pointCount > 0
                for idx = 1, pointCount do
                    local point, relTo, relPoint, posX, posY = mt1:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    pts[idx] = { point, relTo, relPoint, (posX or 0) + dx, posY or 0 }
                end
                if success then
                    GetFFD(mt1).leftAligned = true
                    mt1:ClearAllPoints()
                    for idx = 1, #pts do
                        local t2 = pts[idx]
                        mt1:SetPoint(t2[1], t2[2], t2[3], t2[4], t2[5])
                    end
                end
            end
        end
        Skin.NormalizeTabRow(mTabs)

        -- Icon selector grid panel: framed chrome off, slim scrollbar; the icon
        -- buttons themselves stay stock.
        local sel = win.MacroSelector
        if sel then
            local seld = GetFFD(sel)
            Skin.FadeRegions(sel)
            if sel.ScrollBox then
                Skin.FadeRegions(sel.ScrollBox)
                Skin.Register(sel.ScrollBox, true)
            end
            Skin.Register(sel, true)
            Skin.ScrollBarsIn(sel)
            -- Grid buttons are pooled: halve each slot's backdrop art (every
            -- texture that is not the icon, hover or selection), re-asserted per
            -- Update. Absolute alpha, so it never compounds.
            local sBox = sel.ScrollBox
            if sBox then
                if not seld.iconDim then
                    seld.iconDim = function()
                        if sBox.ForEachFrame and sBox:IsVisible() then
                            sBox:ForEachFrame(DimSlot)
                        end
                    end
                    hooksecurefunc(sBox, "Update", Skin.Debounce(seld.iconDim))
                end
                if sBox.GetView and sBox:GetView() then
                    pcall(seld.iconDim)
                end
            end
        end

        -- Macro body text well: input-style near-black fill + themed border.
        local tabFrame = _G.MacroFrameTextBackground
        if tabFrame then
            local titleData = GetFFD(tabFrame)
            Skin.FadeRegions(tabFrame)
            if tabFrame.NineSlice then
                Skin.FadeNineSlice(tabFrame.NineSlice)
            end
            Skin.Register(tabFrame, true)
            if not titleData.bg then
                local fillTex = tabFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
                fillTex:SetColorTexture(0.02, 0.02, 0.02, 1)
                fillTex:SetAllPoints(tabFrame)
                titleData.bg = fillTex
                Skin.AddBorder(tabFrame)
            end
        end
        if _G.MacroFrameSelectedMacroName then
            Skin.Font(_G.MacroFrameSelectedMacroName)
            Skin.White(_G.MacroFrameSelectedMacroName)
        end
        if _G.MacroFrameCharLimitText then
            Skin.White(_G.MacroFrameCharLimitText)
        end
        if _G.MacroFrameScrollFrame then
            Skin.ScrollBarsIn(_G.MacroFrameScrollFrame)
        end

        -- Layout nudges (one-shot, points preserved): the selected-macro cluster
        -- between the icon grid and the text well rides up 7px, shifting ONLY
        -- members anchored OUTSIDE the cluster so chained ones cannot double-move;
        -- the text well rises 3px (its scrollframe/input ride inside).
        local function ShiftOnce(part, dx, dy, cluster)
            if not part or GetFFD(part).nudged then
                return
            end
            local pointCount = part:GetNumPoints() or 0
            local pts, success = {}, pointCount > 0
            for idx = 1, pointCount do
                local point, relTo, relPoint, posX, posY = part:GetPoint(idx)
                if not point then
                    success = false
                    break
                end
                if cluster and relTo and cluster[relTo] then
                    return
                end -- chained inside: rides its root
                pts[idx] = { point, relTo, relPoint, (posX or 0) + dx, (posY or 0) + dy }
            end
            if success then
                GetFFD(part).nudged = true
                part:ClearAllPoints()
                for idx = 1, #pts do
                    local tbl = pts[idx]
                    part:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                end
            end
        end
        local cluster = {}
        for _, part in ipairs({
            _G.MacroFrameSelectedMacroButton,
            _G.MacroFrameSelectedMacroName,
            _G.MacroEditButton,
            _G.MacroFrameEnterMacroText,
        }) do
            if part then
                cluster[part] = true
            end
        end
        for part in pairs(cluster) do
            ShiftOnce(part, 0, 7, cluster)
        end
        ShiftOnce(tabFrame, 0, 3)
        -- Save +1 / Cancel +5 from stock. Pair-guarded: if Cancel chains off Save
        -- it rides along instead of double-shifting.
        local scPair = {}
        if _G.MacroSaveButton then
            scPair[_G.MacroSaveButton] = true
        end
        if _G.MacroCancelButton then
            scPair[_G.MacroCancelButton] = true
        end
        ShiftOnce(_G.MacroSaveButton, 0, 1, scPair)
        ShiftOnce(_G.MacroCancelButton, 0, 5, scPair)

        Skin_MacroPopup()

        if not _macroHooked then
            _macroHooked = true
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_Macros()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "macros",
        addons = { Blizzard_MacroUI = true },
        apply = Skin_Macros,
    })

    -- Equipment Manager popup (GearManagerPopupFrame, built with PaperDollFrame at load)
    -- wears the sheet's own shell under the sheet's "charsheet" key, so it follows that
    -- card's on/off, style and Modern swap. Blizzard Default keeps the stock popup, like
    -- the sheet itself, and so does WoW Forever. The sheet skin raises the popup's icon
    -- grid a strata above the shell (PreSkinCharacterSheet).
    local GEAR_SHELL_OPTS = { noTopBar = true }
    local function GearPopupBackdrop(win)
        Skin.Shell("charsheet", win, GEAR_SHELL_OPTS)
    end
    local function Skin_GearPopup()
        if CludesUI.IS_FOREVER or mod.CharSheetStock() then
            return
        end
        local p = _G.GearManagerPopupFrame
        if not p then
            return
        end
        Skin_IconSelectorPopup(p, GearPopupBackdrop, Skin_GearPopup)
    end

    Skin.RegisterWindow({
        key = "charsheet",
        apply = Skin_GearPopup,
    })
end

-------------------------------------------------------------------------------
--  Blizzard Options (SettingsPanel). Chrome only: shell, close X, search,
--  bottom buttons, top tabs, category rail, list scrollbars. Per-setting
--  controls (checkboxes, sliders, dropdowns in the list) stay stock -- that
--  surface is huge and taint-adjacent. SettingsPanel.CloseButton is the bottom
--  TEXT button, so CommonChrome (which would X-glyph any .CloseButton) is NOT
--  used here; the pieces run individually.
-------------------------------------------------------------------------------
do
    local _settingsHooked = false
    local function Skin_Settings()
        local win = _G.SettingsPanel
        if not win then
            return
        end
        Skin.Shell("settings", win)
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if win.Bg and win.Bg.SetAlpha then
            win.Bg:SetAlpha(0)
        end
        if win.ClosePanelButton then
            Skin.CloseButton(win.ClosePanelButton)
        end
        if win.SearchBox then
            Skin.EditBox(win.SearchBox)
        end
        for _, keyName in ipairs({ "ApplyButton", "CloseButton" }) do
            local button = win[keyName]
            if button then
                Skin.Button(button)
                Skin.WhiteButtonLabel(button)
            end
        end
        local sTabs = {}
        for _, keyName in ipairs({ "GameTab", "AddOnsTab" }) do
            local t = win[keyName]
            if t then
                Skin.Tab(t, { darkActive = true })
                sTabs[#sTabs + 1] = t
            end
        end
        Skin.NormalizeTabRow(sTabs)
        -- These tabs repaint their state art on hover/click, so pin every Blizzard
        -- texture with self-guarding fades, sparing our pieces by identity.
        -- Selection is not exposed the standard way either, so drive the FFD override from clicks plus isSelected when Blizzard provides it.
        local function SyncSettingsTabs(clicked)
            for _, tab in ipairs(sTabs) do
                local titleData = GetFFD(tab)
                if clicked then
                    titleData.selOverride = (tab == clicked)
                elseif tab.isSelected ~= nil then
                    titleData.selOverride = tab.isSelected and true or false
                elseif titleData.selOverride == nil then
                    titleData.selOverride = (tab == sTabs[1]) -- Game tab default
                end
            end
            Skin.UpdateAllTabs()
        end
        for _, tab in ipairs(sTabs) do
            local titleData = GetFFD(tab)
            if not titleData.pinned then
                titleData.pinned = true
                local regionList = { tab:GetRegions() }
                for idx = 1, #regionList do
                    local region = regionList[idx]
                    if
                        region
                        and region ~= titleData.bg
                        and region ~= titleData.activeHL
                        and region ~= titleData.underline
                        and region.IsObjectType
                        and region:IsObjectType("Texture")
                    then
                        region:SetAlpha(0)
                        for _, m in ipairs({ "SetAtlas", "SetTexture", "Show" }) do
                            if type(region[m]) == "function" then
                                hooksecurefunc(region, m, function(rr)
                                    rr:SetAlpha(0)
                                end)
                            end
                        end
                    end
                end
                tab:HookScript("OnClick", function(self)
                    SyncSettingsTabs(self)
                end)
            end
        end
        -- Every selection path funnels through SetCurrentCategory as a NAMED method
        -- call (reopen reset, tab clicks, rail clicks, OpenToCategory), and the
        -- category's categorySet maps 1:1 onto the tabs. OnTabSelected is NOT
        -- hookable here: the tabsGroup captured it by REFERENCE at OnLoad, so a
        -- method wrapper never runs. Click-only tracking is also insufficient -- a reopen silently resets the panel to Game and strands the override.
        local fieldData = GetFFD(win)
        if not fieldData.catSelHooked then
            fieldData.catSelHooked = true
            hooksecurefunc(win, "SetCurrentCategory", function(_, category)
                local cs = category and category.categorySet
                if cs == nil then
                    return
                end
                for _, tab in ipairs(sTabs) do
                    GetFFD(tab).selOverride = (tab.categorySet == cs)
                end
                Skin.UpdateAllTabs()
            end)
        end
        SyncSettingsTabs()

        -- Category rail: chrome off; pooled rows lose only their backdrop art
        -- (select/hover washes stay Blizzard's).
        local categoryList = win.CategoryList
        if categoryList then
            Skin.FadeRegions(categoryList)
            if categoryList.NineSlice then
                Skin.FadeNineSlice(categoryList.NineSlice)
            end
            Skin.Register(categoryList, true)
            Skin.ScrollBarsIn(categoryList)
            local clBox = categoryList.ScrollBox
            if clBox then
                local cld = GetFFD(categoryList)
                if not cld.fadeRows then
                    -- Box captured in the closure: Debounce invokes with NO args, so taking it as a parameter would leave it nil.
                    cld.fadeRows = function()
                        if clBox.ForEachFrame and clBox:IsVisible() then
                            clBox:ForEachFrame(function(childFrame)
                                if childFrame.Background and childFrame.Background.SetAlpha then
                                    childFrame.Background:SetAlpha(0)
                                end
                            end)
                        end
                    end
                    hooksecurefunc(clBox, "Update", Skin.Debounce(cld.fadeRows))
                end
                -- Run on EVERY skin pass: the box populates at login and the first
                -- open fires no Update, so hook-only fading leaves the first view stock until a tab swap forces a rebuild.
                if clBox.GetView and clBox:GetView() then
                    pcall(cld.fadeRows)
                end
            end
        end

        -- Settings list container: chrome off, defaults button, slim scrollbar.
        local ct = win.Container
        if ct then
            Skin.FadeRegions(ct)
            Skin.Register(ct, true)
            local sl = ct.SettingsList
            if sl then
                Skin.FadeRegions(sl)
                if sl.NineSlice then
                    Skin.FadeNineSlice(sl.NineSlice)
                end
                Skin.Register(sl, true)
                Skin.ScrollBarsIn(sl)
                local heading = sl.Header
                if heading then
                    if heading.DefaultsButton then
                        Skin.Button(heading.DefaultsButton)
                        Skin.WhiteButtonLabel(heading.DefaultsButton)
                    end
                    if heading.Title then
                        Skin.Font(heading.Title)
                        Skin.White(heading.Title)
                    end
                end
            end
        end

        if not _settingsHooked then
            _settingsHooked = true
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_Settings()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "settings",
        apply = Skin_Settings,
    })
end

-------------------------------------------------------------------------------
--  AddOn List (AddonList). Shell + buttons + dropdown/search + force-load
--  checkbox; pooled rows get the house checkbox and white title from
--  Blizzard's row initializer.
-------------------------------------------------------------------------------
do
    local _addonListHooked = false
    local function Skin_AddonList()
        local win = _G.AddonList
        if not win then
            return
        end
        Skin.Shell("addonlist", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "AddonList") -- close X, SearchBox, Dropdown, scrollbar
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if win.Inset then
            Skin.Inset(win.Inset)
        end
        -- NO text coloring anywhere in this window: Blizzard owns every label color (title, buttons, checkbox labels, row texts).
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or _G.AddonListTitleText
        if titleText then
            Skin.Font(titleText)
        end
        for _, keyName in ipairs({ "EnableAllButton", "DisableAllButton", "OkayButton", "CancelButton" }) do
            local button = win[keyName]
            if button then
                Skin.Button(button)
            end
        end
        if win.ForceLoad then
            Skin.Checkbox(win.ForceLoad, { stockCheck = true })
            -- Tight border: the standard checkbox border spans the whole button, ~2px outside the dark box, so re-border a host pinned to the fill instead.
            local fld = GetFFD(win.ForceLoad)
            if not fld.tightBorder and fld.bg then
                fld.tightBorder = true
                local PPb = CludesUI.PP
                if PPb and PPb.GetBorders and PPb.HideBorder and PPb.GetBorders(win.ForceLoad) then
                    PPb.HideBorder(win.ForceLoad)
                end
                local owner = CreateFrame("Frame", nil, win.ForceLoad)
                owner:SetAllPoints(fld.bg)
                owner:SetFrameLevel(win.ForceLoad:GetFrameLevel())
                Skin.AddBorder(owner)
            end
        end

        -- Bottom bar: shell top bar's exact black 0.5 over the button row, on its own child frame so the shell's region fades never touch it.
        local ald = GetFFD(win)
        if not ald.botBar then
            local bhost = CreateFrame("Frame", nil, win)
            bhost:SetAllPoints(win)
            bhost:SetFrameLevel(win:GetFrameLevel())
            local barFrame = bhost:CreateTexture(nil, "BACKGROUND", nil, -5)
            barFrame:SetColorTexture(0, 0, 0, 0.5)
            barFrame:SetPoint("BOTTOMLEFT")
            barFrame:SetPoint("BOTTOMRIGHT")
            barFrame:SetHeight(30)
            ald.botBar = barFrame
        end
        -- The addon list must stop at the bar's top edge (measured one-shot,
        -- rect-gated, retried by the show re-run).
        local abox = win.ScrollBox
        if abox and not GetFFD(abox).botClamped then
            local foundBottom, bb2 = win:GetBottom(), abox:GetBottom()
            if foundBottom and bb2 then
                local dy = (foundBottom + 30) - bb2
                if dy > 0.5 then
                    local pointCount = abox:GetNumPoints() or 0
                    local pts, success, touched = {}, pointCount > 0, false
                    for idx = 1, pointCount do
                        local point, relTo, relPoint, posX, posY = abox:GetPoint(idx)
                        if not point then
                            success = false
                            break
                        end
                        local isBottom = point:find("BOTTOM", 1, true) and true or false
                        if isBottom then
                            touched = true
                        end
                        pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + (isBottom and dy or 0) }
                    end
                    if success and touched then
                        GetFFD(abox).botClamped = true
                        abox:ClearAllPoints()
                        for idx = 1, #pts do
                            local tbl = pts[idx]
                            abox:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                        end
                    end
                else
                    GetFFD(abox).botClamped = true
                end
            end
        end

        if not _addonListHooked then
            _addonListHooked = true
            -- Pooled rows: house checkbox only. ALL row text colors (title, status,
            -- reload, load-button label) stay Blizzard's.
            if type(_G.AddonList_InitAddon) == "function" then
                hooksecurefunc("AddonList_InitAddon", function(record)
                    if not record or (record.IsForbidden and record:IsForbidden()) then
                        return
                    end
                    if record.Enabled then
                        Skin.Checkbox(record.Enabled, { stockCheck = true })
                    end
                    if record.LoadAddonButton and not GetFFD(record.LoadAddonButton).skinned then
                        Skin.Button(record.LoadAddonButton)
                    end
                end)
            end
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_AddonList()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "addonlist",
        apply = Skin_AddonList,
    })
end

-------------------------------------------------------------------------------
--  Crafting Orders, customer side (ProfessionsCustomerOrdersFrame,
--  Blizzard_ProfessionsCustomerOrders). Near-identical layout to the auction
--  house, so it replicates the AH treatments: zone lines+wash on the browse
--  view, tile rail, AH search bar, per-list sort strips with full-height
--  hovers, refresh glyph, state-aware action buttons, global-suffix money boxes.
-------------------------------------------------------------------------------
do
    local _craftHooked = false
    local function Skin_CraftOrders()
        local win = _G.ProfessionsCustomerOrdersFrame
        if not win then
            return
        end
        Skin.Shell("craftorders", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win)
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        for _, keyName in ipairs({ "MoneyFrameBorder", "MoneyFrameInset" }) do
            local part = win[keyName]
            if part then
                Skin.FadeRegions(part)
                if part.NineSlice then
                    Skin.FadeNineSlice(part.NineSlice)
                end
                Skin.Register(part, true)
            end
        end

        local function WhiteBtn(button)
            if button then
                Skin.Button(button)
                Skin.WhiteButtonLabel(button)
            end
        end
        local function StateBtn(button)
            if button then
                Skin.Button(button)
                Skin.StateButtonLabel(button)
            end
        end
        local function MoneyBox(editField)
            if not editField then
                return
            end
            Skin.EditBox(editField)
            local n = editField.GetName and editField:GetName()
            if n then
                for _, suf in ipairs({ "Left", "Middle", "Right" }) do
                    local part = _G[n .. suf]
                    if part and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
            end
            -- Tip gold/silver inputs run 6px shorter (one-shot).
            if not GetFFD(editField).slimmed then
                GetFFD(editField).slimmed = true
                local hgt = editField:GetHeight()
                if hgt and hgt > 6 then
                    editField:SetHeight(hgt - 6)
                end
            end
        end
        -- AH sort headers: invisible plates over a 50% near-black strip riding the
        -- header row. Strip spans the LIST's width here (no shared per-list wash
        -- rect). White labels, hover stretched to the strip, strip spared from our fades via identity + the fill key.
        local function Headers(entries)
            local headerContainer = entries and entries.HeaderContainer
            if not headerContainer then
                return
            end
            local partData = GetFFD(entries)
            if not partData.strip then
                local sTex = entries:CreateTexture(nil, "BACKGROUND", nil, 1)
                sTex:SetColorTexture(0.02, 0.02, 0.02, 0.5)
                sTex:SetHeight(24)
                partData.strip = sTex
                partData.fill = sTex
            end
            partData.strip:SetAlpha(1)
            local ll0, lr0 = entries:GetLeft(), entries:GetRight()
            local hl0 = headerContainer:GetLeft()
            if ll0 and lr0 and hl0 then
                partData.strip:ClearAllPoints()
                partData.strip:SetPoint("TOPLEFT", headerContainer, "TOPLEFT", ll0 - hl0, 2)
                partData.strip:SetPoint("TOPRIGHT", headerContainer, "TOPLEFT", lr0 - hl0, 2)
            end
            local children = { headerContainer:GetChildren() }
            for idx = 1, #children do
                local colour = children[idx]
                if colour and colour.GetObjectType and colour:GetObjectType() == "Button" then
                    local hd = GetFFD(colour)
                    if not hd.bg then
                        for _, k2 in ipairs({ "Left", "Middle", "Right" }) do
                            local t2 = colour[k2]
                            if t2 and t2.SetTexture then
                                t2:SetTexture("")
                            end
                        end
                        Skin.FadeRegions(colour)
                        local bgTex = SolidTex(colour, "BACKGROUND", 0.02, 0.02, 0.02, 0)
                        bgTex:SetPoint("TOPLEFT", 1, -1)
                        bgTex:SetPoint("BOTTOMRIGHT", -1, 1)
                        hd.bg = bgTex
                        local hoverTex = SolidTex(colour, "HIGHLIGHT", 1, 1, 1, 0.1)
                        hoverTex:SetAllPoints(colour)
                        hd.hover = hoverTex
                    end
                    local fontStr = colour.GetFontString and colour:GetFontString()
                    if fontStr then
                        Skin.White(fontStr)
                    end
                    local strip = partData.strip
                    if hd.hover and strip and strip.GetTop then
                        local st, sbot = strip:GetTop(), strip:GetBottom()
                        local ct, cbot = colour:GetTop(), colour:GetBottom()
                        if st and sbot and ct and cbot then
                            hd.hover:ClearAllPoints()
                            hd.hover:SetPoint("TOPLEFT", colour, "TOPLEFT", 0, st - ct)
                            hd.hover:SetPoint("BOTTOMRIGHT", colour, "BOTTOMRIGHT", 0, sbot - cbot)
                        end
                    end
                end
            end
        end
        local function List(entries)
            if not entries then
                return
            end
            local labelData = GetFFD(entries)
            Skin.FadeRegions(entries, labelData.strip and { [labelData.strip] = true } or nil)
            if entries.NineSlice then
                Skin.FadeNineSlice(entries.NineSlice)
            end
            Skin.Register(entries, true)
            Skin.ScrollBarsIn(entries)
            Headers(entries)
            if not labelData.hdrShowHook then
                labelData.hdrShowHook = true
                entries:HookScript(
                    "OnShow",
                    Skin.Debounce(function()
                        Headers(entries)
                    end)
                )
            end
        end

        local frameData = GetFFD(win)
        local browse = win.BrowseOrders
        -- Zone lines (AH treatment): top/bottom seams on the window; rail-edge
        -- divider+2% wash are parented to the BROWSE view so they vanish with it (my-orders+form have no rail).
        if not frameData.zoneLines and browse and browse.CategoryList then
            frameData.zoneLines = true
            local pixel = 1
            do
                local PPx = CludesUI.PP
                local es = win:GetEffectiveScale()
                if PPx and PPx.perfect and es and es > 0 then
                    pixel = PPx.perfect / es
                end
            end
            frameData.zonePx = pixel
            local owner = CreateFrame("Frame", nil, win)
            owner:SetAllPoints(win)
            owner:SetFrameLevel(win:GetFrameLevel())
            local topSep = owner:CreateTexture(nil, "ARTWORK")
            topSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            topSep:SetHeight(pixel)
            topSep:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -77)
            topSep:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -77)
            frameData.topSep = topSep
            local botSep = owner:CreateTexture(nil, "ARTWORK")
            botSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            botSep:SetHeight(pixel)
            botSep:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 30)
            botSep:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 30)
            local railHost = CreateFrame("Frame", nil, browse)
            railHost:SetAllPoints(browse)
            railHost:SetFrameLevel(browse:GetFrameLevel())
            local cl2 = browse.CategoryList
            local washTex = railHost:CreateTexture(nil, "BACKGROUND")
            washTex:SetColorTexture(1, 1, 1, 0.02)
            washTex:SetPoint("TOPLEFT", cl2, "TOPRIGHT", pixel, 2) -- 2px wider than the AH gap; top 3px lower
            washTex:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 30 + pixel)
            frameData.wash = washTex
            local sideSep = railHost:CreateTexture(nil, "ARTWORK")
            sideSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            sideSep:SetWidth(pixel)
            sideSep:SetPoint("TOPLEFT", washTex, "TOPLEFT", -pixel, 0)
            sideSep:SetPoint("BOTTOMLEFT", washTex, "BOTTOMLEFT", -pixel, 0)
            -- FORM zone: split-section wash on the right + vertical divider,
            -- mirroring the AH sell tab, seated a few px right of the recipe favorite star. Hidden until the order form shows.
            local formHost = CreateFrame("Frame", nil, owner)
            formHost:SetAllPoints(owner)
            formHost:SetFrameLevel(owner:GetFrameLevel())
            formHost:Hide()
            frameData.formHost = formHost
            local formWash = formHost:CreateTexture(nil, "BACKGROUND")
            formWash:SetColorTexture(1, 1, 1, 0.02)
            -- TOPLEFT is seated later (needs the panel rect); center keeps it valid.
            formWash:SetPoint("TOPLEFT", win, "TOP", 0, -77 - pixel)
            formWash:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 30 + pixel)
            frameData.formWash = formWash
            local formSep = formHost:CreateTexture(nil, "ARTWORK")
            formSep:SetColorTexture(0.15, 0.15, 0.15, 1)
            formSep:SetWidth(pixel)
            formSep:SetPoint("TOPLEFT", formWash, "TOPLEFT", -pixel, 0)
            formSep:SetPoint("BOTTOMLEFT", formWash, "BOTTOMLEFT", -pixel, 0)
        end
        -- Rail 2px wider: left edge out only, so the divider and wash anchored off
        -- the right edge do not move. One-shot, points preserved.
        local cl0 = browse and browse.CategoryList
        if cl0 and not GetFFD(cl0).widened then
            local pointCount = cl0:GetNumPoints() or 0
            local pts, success = {}, pointCount > 0
            for idx = 1, pointCount do
                local point, relTo, relPoint, posX, posY = cl0:GetPoint(idx)
                if not point then
                    success = false
                    break
                end
                pts[idx] = { point, relTo, relPoint, (posX or 0) - (point:find("LEFT", 1, true) and 2 or 0), posY or 0 }
            end
            if success then
                GetFFD(cl0).widened = true
                cl0:ClearAllPoints()
                for idx = 1, #pts do
                    local tbl = pts[idx]
                    cl0:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                end
            end
        end
        -- Top divider rides the ACTIVE view's top bar: browse wash top on Browse,
        -- My Orders list header top on My Orders (browse wash is hidden there, its
        -- rect is stale). Re-measured every pass while that anchor is visible (a
        -- one-shot could latch a stale early measurement), frame-anchored at full width so it holds across tab swaps.
        if frameData.topSep then
            local ft = win:GetTop()
            local topY, off
            if frameData.wash and frameData.wash:IsVisible() then
                topY, off = frameData.wash:GetTop(), 4 -- +4px wash visual-flush offset
            else
                local mo0 = win.MyOrdersPage
                local headerContainer = mo0 and mo0:IsVisible() and mo0.OrderList and mo0.OrderList.HeaderContainer
                local hct = headerContainer and headerContainer:GetTop()
                if hct then
                    topY, off = hct + 2, 0
                end -- +2 = the header strip's own lift above hc
            end
            if ft and topY then
                local posY = (topY - ft) + (frameData.zonePx or 1) + off
                frameData.topSep:ClearAllPoints()
                frameData.topSep:SetPoint("TOPLEFT", win, "TOPLEFT", 0, posY)
                frameData.topSep:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, posY)
            end
        end

        -- Seat the form split divider a few px right of the recipe favorite star.
        -- One-shot, retried per pass until the form has laid out (its OnShow hook re-runs this).
        do
            local rp = win.Form and win.Form.RightPanelBackground
            if frameData.formWash and frameData.topSep and rp and not frameData.formSeated then
                local rl, flx = rp:GetLeft(), win:GetLeft()
                if rl and flx then
                    frameData.formSeated = true
                    -- Top rides the top divider's bottom edge (flush, live); X is
                    -- the panel boundary + 6 (topSep BOTTOMLEFT X == frame left).
                    frameData.formWash:ClearAllPoints()
                    frameData.formWash:SetPoint("TOPLEFT", frameData.topSep, "BOTTOMLEFT", (rl - flx) + 6, 0)
                    frameData.formWash:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 30 + (frameData.zonePx or 1))
                end
            end
        end

        if browse then
            -- Re-run on tab show so the top divider re-seats to the browse wash
            -- when switching back from My Orders; bottom-tab switches do not
            -- otherwise re-trigger the skin.
            if not frameData.browseShowHook then
                frameData.browseShowHook = true
                browse:HookScript(
                    "OnShow",
                    Skin.Debounce(function()
                        Skin_CraftOrders()
                    end)
                )
            end
            -- Search bar: AH treatment verbatim.
            local scrollBar = browse.SearchBar
            if scrollBar then
                WhiteBtn(scrollBar.SearchButton)
                if scrollBar.FavoritesSearchButton then
                    Skin.Button(scrollBar.FavoritesSearchButton, { "Icon" })
                    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
                        local part = scrollBar.FavoritesSearchButton[getter]
                            and scrollBar.FavoritesSearchButton[getter](scrollBar.FavoritesSearchButton)
                        if part and part.SetAlpha then
                            part:SetAlpha(1)
                        end
                    end
                end
                local foundBottom = scrollBar.FilterDropdown or scrollBar.FilterButton
                if foundBottom then
                    LeftAlignFilterLabel(foundBottom)
                    local sbtn = scrollBar.SearchButton
                    local hgt = sbtn and sbtn.GetHeight and sbtn:GetHeight()
                    if hgt and hgt > 0 and foundBottom.SetHeight then
                        foundBottom:SetHeight(hgt)
                    end
                    SkinFilterResetX(foundBottom.ResetButton or foundBottom.ClearFiltersButton, foundBottom)
                end
            end
            -- Category rail: chrome off + pooled rows as sidebar tiles (AH rail
            -- treatment). NOT restrip-registered; the Update hook is upkeep.
            local categoryList = browse.CategoryList
            if categoryList then
                Skin.FadeRegions(categoryList)
                if categoryList.NineSlice then
                    Skin.FadeNineSlice(categoryList.NineSlice)
                end
                Skin.Register(categoryList, true)
                Skin.ScrollBarsIn(categoryList)
                -- Rail row spacing -1 via the scroll view's padding (AH rail
                -- treatment); per-row anchor surgery is a no-op on ScrollBox rows.
                if not GetFFD(categoryList).spacingSet then
                    local box0 = categoryList.ScrollBox
                    local view0 = box0 and box0.GetView and box0:GetView()
                    if view0 and view0.SetPadding then
                        GetFFD(categoryList).spacingSet = true
                        pcall(function()
                            local top, bottom, left, right = 0, 0, 0, 0
                            local pad = view0.GetPadding and view0:GetPadding()
                            if pad then
                                top = (pad.GetTop and pad:GetTop()) or 0
                                bottom = (pad.GetBottom and pad:GetBottom()) or 0
                                left = (pad.GetLeft and pad:GetLeft()) or 0
                                right = (pad.GetRight and pad:GetRight()) or 0
                            end
                            view0:SetPadding(top, bottom, left, right, -1)
                            if box0.FullUpdate then
                                box0:FullUpdate(true)
                            end
                        end)
                    end
                end
                local clBox = categoryList.ScrollBox
                if clBox and not GetFFD(categoryList).rowHook then
                    GetFFD(categoryList).rowHook = true
                    local function SkinRailRow(row)
                        if not row or (row.IsForbidden and row:IsForbidden()) then
                            return
                        end
                        local regionData = GetFFD(row)
                        if not regionData.bg then
                            local bgTex = row:CreateTexture(nil, "BACKGROUND", nil, -3)
                            bgTex:SetColorTexture(
                                Theme.bgR + 0.015,
                                Theme.bgG + 0.015,
                                Theme.bgB + 0.015,
                                Theme.bgA
                            )
                            bgTex:SetPoint("TOPLEFT", 1, -1)
                            bgTex:SetPoint("BOTTOMRIGHT", -1, 1)
                            regionData.bg = bgTex
                            Skin.AddBorder(row)
                        end
                        for _, keyName in ipairs({ "NormalTexture", "SelectedTexture", "SelectedHighlight" }) do
                            local part = row[keyName]
                            if part then
                                if keyName == "NormalTexture" then
                                    part:SetAlpha(0)
                                else
                                    part:SetColorTexture(1, 1, 1, 0.15)
                                    part:ClearAllPoints()
                                    part:SetAllPoints(row)
                                end
                            end
                        end
                        if row.HighlightTexture then
                            row.HighlightTexture:SetColorTexture(1, 1, 1, 0.1)
                            row.HighlightTexture:ClearAllPoints()
                            row.HighlightTexture:SetAllPoints(row)
                        end
                        local fontStr = row.Text or (row.GetFontString and row:GetFontString())
                        if fontStr then
                            Skin.White(fontStr)
                        end
                    end
                    local function SkinRailRows()
                        if clBox.ForEachFrame and clBox:IsVisible() then
                            clBox:ForEachFrame(SkinRailRow)
                        end
                    end
                    GetFFD(categoryList).railRows = SkinRailRows
                    hooksecurefunc(clBox, "Update", Skin.Debounce(SkinRailRows))
                end
                local rr = GetFFD(categoryList).railRows
                if rr and clBox and clBox.GetView and clBox:GetView() then
                    pcall(rr)
                end
            end
            -- Results list; headers rebuild via SetupTable.
            List(browse.RecipeList)
            if browse.SetupTable and not GetFFD(browse).tableHook then
                GetFFD(browse).tableHook = true
                hooksecurefunc(
                    browse,
                    "SetupTable",
                    Skin.Debounce(function()
                        Headers(browse.RecipeList)
                    end)
                )
            end
        end

        -- Order form (item-detail equivalent).
        local form = win.Form
        if form then
            -- Toggle the form split zone with the form and re-run the skin on show,
            -- so the divider seats once the panels have laid out.
            if not frameData.formShowHook then
                frameData.formShowHook = true
                local function SyncFormZone()
                    if frameData.formHost then
                        frameData.formHost:SetShown(form:IsShown() and true or false)
                    end
                end
                form:HookScript(
                    "OnShow",
                    Skin.Debounce(function()
                        SyncFormZone()
                        Skin_CraftOrders()
                    end)
                )
                form:HookScript("OnHide", SyncFormZone)
                SyncFormZone()
            end
            WhiteBtn(form.BackButton)
            for _, keyName in ipairs({ "RecipeHeader", "LeftPanelBackground", "RightPanelBackground" }) do
                local part = form[keyName]
                if part then
                    if part.IsObjectType and part:IsObjectType("Texture") then
                        part:SetAlpha(0)
                    else
                        Skin.FadeRegions(part)
                        Skin.Register(part, true)
                    end
                end
            end
            if form.TrackRecipeCheckbox and form.TrackRecipeCheckbox.Checkbox then
                Skin.Checkbox(form.TrackRecipeCheckbox.Checkbox, { borderInset = 2 })
            end
            if form.AllocateBestQualityCheckbox then
                Skin.Checkbox(form.AllocateBestQualityCheckbox)
            end
            local ddRecip = form.OrderRecipientDropdown
            local tgtRecip = form.OrderRecipientTarget
            if tgtRecip then
                Skin.EditBox(tgtRecip)
            end
            if ddRecip then
                Skin.Dropdown(ddRecip)
            end
            -- Recipient dropdown + its "To:" target input drop 10px. Shift the target ONLY
            -- when it is not anchored to the dropdown, or it has already followed.
            local function ShiftDown10(found)
                if not found or GetFFD(found).shift10 then
                    return
                end
                local pointCount = found:GetNumPoints() or 0
                local pts, success = {}, pointCount > 0
                for idx = 1, pointCount do
                    local point, relTo, relPoint, posX, posY = found:GetPoint(idx)
                    if not point then
                        success = false
                        break
                    end
                    pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) - 10 }
                end
                if success then
                    GetFFD(found).shift10 = true
                    found:ClearAllPoints()
                    for idx = 1, #pts do
                        local tbl = pts[idx]
                        found:SetPoint(tbl[1], tbl[2], tbl[3], tbl[4], tbl[5])
                    end
                end
            end
            ShiftDown10(ddRecip)
            if tgtRecip then
                local anchoredToDD = false
                for idx = 1, (tgtRecip:GetNumPoints() or 0) do
                    local _, relTo = tgtRecip:GetPoint(idx)
                    if relTo == ddRecip then
                        anchoredToDD = true
                        break
                    end
                end
                if not anchoredToDD then
                    ShiftDown10(tgtRecip)
                end
            end
            if form.MinimumQuality and form.MinimumQuality.Dropdown then
                Skin.Dropdown(form.MinimumQuality.Dropdown)
            end
            local pay = form.PaymentContainer
            if pay then
                if pay.NoteEditBox then
                    Skin.FadeRegions(pay.NoteEditBox)
                    Skin.Register(pay.NoteEditBox, true)
                    -- 50% black backing on the actual scrolling field: NoteEditBox
                    -- is only a wrapper and its bounds do not cover the visible
                    -- box. Protected "bg" key, so a Restrip never fades it.
                    local seb = pay.NoteEditBox.ScrollingEditBox
                    local sbox = seb and seb.ScrollBox
                    if sbox and not GetFFD(sbox).bg then
                        local bgTex = sbox:CreateTexture(nil, "BACKGROUND", nil, -7)
                        bgTex:SetColorTexture(0, 0, 0, 0.5)
                        bgTex:SetAllPoints(sbox)
                        GetFFD(sbox).bg = bgTex
                    end
                end
                if pay.TipMoneyInputFrame then
                    MoneyBox(pay.TipMoneyInputFrame.GoldBox)
                    MoneyBox(pay.TipMoneyInputFrame.SilverBox)
                end
                if pay.DurationDropdown then
                    Skin.Dropdown(pay.DurationDropdown)
                end
                StateBtn(pay.ListOrderButton)
                StateBtn(pay.CancelOrderButton)
            end
            local cls = form.CurrentListings
            if cls then
                Skin.Panel(cls)
                if cls.CloseButton then
                    Skin.CloseButton(cls.CloseButton)
                end
                List(cls.OrderList)
            end
            local qd = form.QualityDialog
            if qd then
                Skin.Panel(qd)
                if qd.Bg and qd.Bg.SetAlpha then
                    qd.Bg:SetAlpha(0)
                end
                if qd.ClosePanelButton then
                    Skin.CloseButton(qd.ClosePanelButton)
                end
                WhiteBtn(qd.AcceptButton)
                WhiteBtn(qd.CancelButton)
                for idx = 1, 3 do
                    local c = qd["Container" .. idx]
                    if c and c.EditBox then
                        Skin.EditBox(c.EditBox)
                    end
                end
            end
        end

        -- My orders page.
        local mo = win.MyOrdersPage
        if mo then
            -- Re-run on tab show so the top divider re-seats to this list's top;
            -- nothing else re-triggers the skin on a bottom-tab switch.
            if not frameData.moShowHook then
                frameData.moShowHook = true
                mo:HookScript(
                    "OnShow",
                    Skin.Debounce(function()
                        Skin_CraftOrders()
                    end)
                )
            end
            Skin.RefreshGlyph(mo.RefreshButton)
            List(mo.OrderList)
        end

        -- Bottom tabs (frame.Tabs table, AH-style). These carry NONE of the
        -- standard selection fields, so the engine's TabIsSelected() never matches
        -- and neither tab shows active. Selection here is purely which content page
        -- is shown, so sync the FFD override from BrowseOrders/MyOrdersPage
        -- visibility (mirroring the AH's displayMode SyncTabSel); runs every pass, re-triggered by the browse/mo OnShow hooks on every tab switch.
        local coTabs = {}
        if type(win.Tabs) == "table" then
            for _, tab in ipairs(win.Tabs) do
                if tab then
                    Skin.Tab(tab)
                    coTabs[#coTabs + 1] = tab
                end
            end
        end
        Skin.NormalizeTabRow(coTabs)
        for _, tab in ipairs(coTabs) do
            local label = tab.GetName and tab:GetName()
            if label and label:find("BrowseTab", 1, true) then
                GetFFD(tab).selOverride = (win.BrowseOrders and win.BrowseOrders:IsShown()) and true or false
            elseif label and label:find("OrdersTab", 1, true) then
                GetFFD(tab).selOverride = (win.MyOrdersPage and win.MyOrdersPage:IsShown()) and true or false
            end
        end
        Skin.UpdateAllTabs()

        if not _craftHooked then
            _craftHooked = true
            Skin.HookShow(
                win,
                Skin.Debounce(function()
                    if win:IsVisible() then
                        Skin_CraftOrders()
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "craftorders",
        addons = { Blizzard_ProfessionsCustomerOrders = true },
        apply = Skin_CraftOrders,
    })
end

-------------------------------------------------------------------------------
--  Item Upgrades (ItemUpgradeFrame, Blizzard_ItemUpgradeUI). Flat shell,
--  squared upgrade slot, flat upgrade-track dropdown and action button, bottom
--  currency strip stripped of its plate art.
-------------------------------------------------------------------------------
do
    local function Skin_ItemUpgrade()
        local win = _G.ItemUpgradeFrame
        if not win then
            return
        end
        -- bottomBar: the art kill below strips the plate behind the foot currency
        -- strip, so the shell's bottom band puts that footer back in the same
        -- black 0.5 as the title bar.
        Skin.Shell("itemupgrade", win, { bottomBar = true })
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "ItemUpgradeFrame") -- close, ItemInfo.Dropdown, scrollbars
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if _G.ItemUpgradeFrameBg then
            _G.ItemUpgradeFrameBg:SetAlpha(0)
        end
        -- The backplates (TopBG/BottomBG) repaint to the SLOTTED ITEM'S QUALITY
        -- COLOR on every item change (the purple wash an epic leaves), re-showing
        -- art a plain SetAlpha(0) had hidden. Clear the window's art OUTRIGHT
        -- (SetTexture/SetAtlas "") so a re-tint has nothing to paint. Only DIRECT
        -- regions of the window are touched (content lives on child frames), our own shell textures spared.
        local fieldData = GetFFD(win)
        local keepArt = {}
        -- bottomBar is load-bearing here TWICE: KillArt clears every direct region
        -- of the window, and FadeBottomPlates fades any texture in the bottom 60px spanning over half the width -- exactly our own bottom band's shape.
        for _, keyName in ipairs({ "bg", "bgOverlay", "modernBg", "topBar", "bottomBar", "rightShade" }) do
            if fieldData[keyName] then
                keepArt[fieldData[keyName]] = true
            end
        end
        local function KillArt(region)
            if not region or keepArt[region] or not region.IsObjectType or not region:IsObjectType("Texture") then
                return
            end
            if region.SetAtlas then
                region:SetAtlas("")
            end
            if region.SetTexture then
                region:SetTexture("")
            end
            region:SetAlpha(0)
        end
        local regionList = { win:GetRegions() }
        for idx = 1, #regionList do
            KillArt(regionList[idx])
        end
        -- ItemUpgradeBg is its own keyed piece, so name it explicitly rather than leaving it to the region walk above.
        for _, keyName in ipairs({
            "Bg",
            "TopBG",
            "BottomBG",
            "Background",
            "TopTileStreaks",
            "ItemUpgradeBg",
        }) do
            KillArt(win[keyName])
        end
        -- The nine-slice is part of the quality-tinted chrome too, so its pieces are CLEARED rather than just alpha'd.
        if win.NineSlice then
            local regions2 = { win.NineSlice:GetRegions() }
            for idx = 1, #regions2 do
                KillArt(regions2[idx])
            end
        end
        if win.Inset then
            Skin.Inset(win.Inset)
        end
        Skin.FadeKeyedArt(win)
        Skin.FadeArtIn(win)

        local titleText = (win.TitleContainer and win.TitleContainer.TitleText)
            or win.TitleText
            or _G.ItemUpgradeFrameTitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end

        -- Upgrade slot: gold frame off, icon squared inside a flat well so an EMPTY slot still reads as a slot.
        local ib = win.UpgradeItemButton
        if ib then
            for _, keyName in ipairs({
                "ButtonFrame",
                "Border",
                "IconBorder",
                "SlotBackground",
                "EmptySlot",
                "EmptyBackground",
            }) do
                local part = ib[keyName]
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
            local ibd = GetFFD(ib)
            if not ibd.slotBg then
                local well = SolidTex(ib, "BACKGROUND", 0.02, 0.02, 0.02, 0.9)
                well:SetAllPoints(ib)
                ibd.slotBg = well
                Skin.AddBorder(ib)
            end
            local glyphTex = ib.Icon or ib.icon or ib.IconTexture
            if glyphTex and glyphTex.SetTexCoord then
                Skin.SquareIcon(glyphTex)
            end
        end

        -- Upgrade-track selector + any other pane art on the info block.
        local details = win.ItemInfo
        if details then
            if details.Dropdown then
                Skin.Dropdown(details.Dropdown)
            end
            for _, keyName in ipairs({ "Bg", "Background", "Divider", "PillarLeft", "PillarRight" }) do
                local part = details[keyName]
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
        end

        -- Bottom currency strip: NO plate of our own, amounts sit flat on the
        -- shell. Plate art is NOT keyed off the currencies container: it lives in
        -- its own wrapper frame, ItemUpgradeFramePlayerCurrenciesBorder, with
        -- Left/Middle/Right as CHILDREN. Fade the wrapper's whole subtree (textures
        -- only, so amounts survive) and register for repaint re-fades; a named
        -- `container.BorderLeft` lookup would miss the narrow end caps.
        local function FadeArtTree(owner, nestDepth)
            nestDepth = nestDepth or 0
            if not owner or nestDepth > 3 or owner:IsForbidden() then
                return
            end
            -- Provenance gate: another addon parented into this window keeps its
            -- whole subtree. depth > 0, so an explicit root call always runs.
            if nestDepth > 0 and Skin.IsForeignFrame(owner) then
                return
            end
            if owner.IsObjectType and owner:IsObjectType("Texture") then
                if owner.SetAlpha then
                    owner:SetAlpha(0)
                end
                return
            end
            Skin.FadeRegions(owner)
            if owner.NineSlice then
                Skin.FadeNineSlice(owner.NineSlice)
            end
            Skin.Register(owner, true)
            if not owner.GetChildren then
                return
            end
            local children = { owner:GetChildren() }
            for idx = 1, #children do
                FadeArtTree(children[idx], nestDepth + 1)
            end
        end
        local pc = win.PlayerCurrencies or _G.ItemUpgradeFramePlayerCurrencies
        FadeArtTree(_G.ItemUpgradeFramePlayerCurrenciesBorder or (pc and pc.Border))
        -- Belt and braces: the pieces carry globals of their own too.
        for _, n in ipairs({
            "ItemUpgradeFramePlayerCurrenciesBorderLeft",
            "ItemUpgradeFramePlayerCurrenciesBorderMiddle",
            "ItemUpgradeFramePlayerCurrenciesBorderRight",
        }) do
            local part = _G[n]
            if part and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        if pc then
            if pc.NineSlice then
                Skin.FadeNineSlice(pc.NineSlice)
            end
            for _, keyName in ipairs({ "Background", "Bg", "BG" }) do
                local part = pc[keyName]
                if part and part.SetAlpha then
                    part:SetAlpha(0)
                end
            end
        end
        for _, keyName in ipairs({ "BottomInset", "MoneyInset", "MoneyFrameInset", "MoneyFrameBorder" }) do
            local part = win[keyName] or _G["ItemUpgradeFrame" .. keyName]
            if part then
                if part.IsObjectType and part:IsObjectType("Texture") then
                    part:SetAlpha(0)
                else
                    Skin.Inset(part)
                end
            end
        end

        -- Geometry sweep for the bottom plate, whoever owns it: names for this bar
        -- move between builds, so match on SHAPE -- any TEXTURE in the bottom 60px
        -- spanning more than half the window width is backing art (currency icons
        -- are far narrower, amounts are FontStrings, so both survive). Needs live rects, so it lands on show/update passes, not login.
        local function Num(v)
            if v == nil then
                return nil
            end
            if issecretvalue and issecretvalue(v) then
                return nil
            end
            return v
        end
        local function FadeBottomPlates(owner, nestDepth)
            nestDepth = nestDepth or 0
            if not owner or nestDepth > 5 or owner:IsForbidden() then
                return
            end
            -- Provenance gate, doubly important here: the match below is a pure
            -- GEOMETRY heuristic (bottom 60px, over half the window wide) that
            -- would blank an addon's own bar parented into this frame.
            if nestDepth > 0 and Skin.IsForeignFrame(owner) then
                return
            end
            local foundBottom, fw = Num(win:GetBottom()), Num(win:GetWidth())
            if not foundBottom or not fw then
                return
            end
            if owner.GetRegions then
                local regions2 = { owner:GetRegions() }
                for idx = 1, #regions2 do
                    local region = regions2[idx]
                    if
                        region
                        and not keepArt[region]
                        and region.IsObjectType
                        and region:IsObjectType("Texture")
                        and (region:GetAlpha() or 0) > 0
                    then
                        local rt, objectiveRow = Num(region:GetTop()), Num(region:GetWidth())
                        if rt and objectiveRow and rt < foundBottom + 60 and objectiveRow > fw * 0.5 then
                            region:SetAlpha(0)
                        end
                    end
                end
            end
            if not owner.GetChildren then
                return
            end
            local children = { owner:GetChildren() }
            for idx = 1, #children do
                FadeBottomPlates(children[idx], nestDepth + 1)
            end
        end
        FadeBottomPlates(win)

        -- Action buttons: Upgrade button mirrors its enabled/disabled state -- it
        -- spends currency, so a permanently white label would read as active while unaffordable.
        Skin.ButtonsIn(win)
        for _, keyName in ipairs({ "UpgradeButton", "ConfirmButton" }) do
            local button = win[keyName]
            if button then
                Skin.Button(button)
                Skin.StateButtonLabel(button)
            end
        end

        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    Skin_ItemUpgrade()
                    Skin.Restrip()
                end
            end)
        )
        -- The quality repaint fires on item CHANGE, not on show, so OnShow alone
        -- leaves the first slotted item wearing Blizzard's backdrop until reopen.
        -- Listen for the upgrade events instead (debounced, registration pcall'd since the event set shifts between builds).
        if not fieldData.evt then
            local eventFrame = CreateFrame("Frame")
            fieldData.evt = eventFrame
            -- Gated on visibility, NO global WSkin.Restrip(): fires on every item
            -- change, Skin_ItemUpgrade already re-clears this window's art, and the global sweep allocates a table per registered frame suite-wide.
            eventFrame:SetScript(
                "OnEvent",
                Skin.Debounce(function()
                    local uf = _G.ItemUpgradeFrame
                    if uf and uf:IsVisible() then
                        Skin_ItemUpgrade()
                    end
                end)
            )
            for _, event in ipairs({
                "ITEM_UPGRADE_MASTER_OPENED",
                "ITEM_UPGRADE_MASTER_UPDATE",
                "ITEM_UPGRADE_MASTER_SET_ITEM",
                "ITEM_UPGRADE_MASTER_CLOSED",
                "ITEM_INTERACTION_ITEM_SELECTION_UPDATED",
            }) do
                pcall(eventFrame.RegisterEvent, eventFrame, event)
            end
        end
    end

    Skin.RegisterWindow({
        key = "itemupgrade",
        addons = { Blizzard_ItemUpgradeUI = true },
        apply = Skin_ItemUpgrade,
    })
end

-------------------------------------------------------------------------------
--  Loot window (LootFrame). Base UI, always loaded. Portrait frame:
--  TitleContainer + NineSlice + the LootFrameTitleText global. Rows KEEP their
--  item quality colors -- names and rarity subtext are re-fonted, never
--  re-colored (same rule the merchant and trainer packs use).
-------------------------------------------------------------------------------
do
    local lootSkinned = false
    local LOOT_WHITE = { r = 1, g = 1, b = 1 }
    local lootQualityRGB = { r = 1, g = 1, b = 1 }

    -- The best quality among the slots still holding loot (a looted slot reads type None);
    -- nil with none left or no loot at all (the Edit Mode preview).
    local function BestLootQuality()
        local best
        for idx = 1, GetNumLootItems() do
            if GetLootSlotType(idx) ~= Enum.LootSlotType.None then
                local q = select(5, GetLootSlotInfo(idx))
                if q and (not best or q > best) then
                    best = q
                end
            end
        end
        return best
    end

    -- Quality mode's color for a best quality: Uncommon and up in their quality color, else (Poor
    -- or Common only, or no loot) the Quality swatch's own color. Refills one table, read at once.
    local function LootQualityColor(best)
        if not best or best < Enum.ItemQuality.Uncommon then
            return CludesUIDB.lootWindowBorderQualityColor or LOOT_WHITE
        end
        lootQualityRGB.r, lootQualityRGB.g, lootQualityRGB.b = C_Item.GetItemQualityColor(best)
        return lootQualityRGB
    end

    -- The window border's picked color, for Poor/Common icons under Icon Borders. nil while the border is Default.
    local function LootWindowColor()
        local saved = CludesUIDB
        if not (saved and saved.lootWindowBorderTexture) then
            return nil
        end
        local mode = saved.lootWindowBorderColorMode or "custom"
        if mode == "accent" then
            return CludesUI.CLUDES_GREEN
        end
        if mode == "class" then
            local _, class = UnitClass("player")
            return class and RAID_CLASS_COLORS[class]
        end
        if mode == "quality" then
            return saved.lootWindowBorderQualityColor or LOOT_WHITE
        end
        return saved.lootWindowBorderColor or LOOT_WHITE
    end

    -- Quality mode follows the loot as it is taken: Blizzard hides a looted row with no list
    -- update, so a frame of ours repaints the border when a cleared slot changes the best quality.
    -- Registered only while the window shows in Quality mode; the loot's close lets it go.
    local ApplyLootBorder
    local lootQualityWatch, lootPaintedBest
    local function SyncLootQualityWatch(on)
        if on then
            if not lootQualityWatch then
                lootQualityWatch = CreateFrame("Frame")
                lootQualityWatch:SetScript("OnEvent", function(self, event)
                    if event == "LOOT_CLOSED" then
                        self:UnregisterAllEvents()
                    elseif _G.LootFrame and BestLootQuality() ~= lootPaintedBest then
                        ApplyLootBorder(_G.LootFrame)
                    end
                end)
            end
            lootQualityWatch:RegisterEvent("LOOT_SLOT_CLEARED")
            lootQualityWatch:RegisterEvent("LOOT_CLOSED")
        elseif lootQualityWatch then
            lootQualityWatch:UnregisterAllEvents()
        end
    end

    -- The Loot Window card's border style. Unset keeps the shell's window border untouched.
    ApplyLootBorder = function(win)
        local skinData = GetFFD(win)
        local saved = CludesUIDB
        if saved and saved.lootWindowBorderTexture then
            if skinData.atlasBorderFrame then
                skinData.atlasBorderFrame:Hide()
            end
            local quality = saved.lootWindowBorderColorMode == "quality"
            local override
            if quality then
                lootPaintedBest = BestLootQuality()
                override = LootQualityColor(lootPaintedBest)
            end
            if CludesUI._applyBlizzardConfiguredBorder then
                CludesUI._applyBlizzardConfiguredBorder(win, "lootWindow", 1, override)
            end
            SyncLootQualityWatch(quality and win:IsShown())
            skinData.lootBorderOn = true
        elseif skinData.lootBorderOn then
            if skinData.atlasBorderFrame then
                skinData.atlasBorderFrame:Show()
            end
            if CludesUI._hideBlizzardConfiguredBorder then
                CludesUI._hideBlizzardConfiguredBorder(win)
            end
            SyncLootQualityWatch(false)
            skinData.lootBorderOn = nil
        end
    end

    local function Skin_Loot()
        local win = _G.LootFrame
        if not win then
            return
        end
        lootSkinned = true
        Skin.Shell("loot", win)
        Skin.RemovePortrait(win)
        Skin.CommonChrome(win, "LootFrame")
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        if _G.LootFrameBg then
            _G.LootFrameBg:SetAlpha(0)
        end
        if win.Bg and win.Bg.SetAlpha then
            win.Bg:SetAlpha(0)
        end
        if win.Inset then
            Skin.Inset(win.Inset)
        end
        Skin.FadeKeyedArt(win)
        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or _G.LootFrameTitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end
        Skin.ScrollBarsIn(win)

        -- One loot row: squared icon, plate art off, flat hover. Fonts only on the
        -- text so quality coloring survives.
        local function SkinLootRow(row)
            if not row or row:IsForbidden() then
                return
            end
            local entry = row.Item or row
            local glyphTex = entry.icon
                or entry.Icon
                or entry.IconTexture
                or (entry.GetNormalTexture and entry:GetNormalTexture())
            if glyphTex and glyphTex.SetTexCoord then
                -- SquareIcon WITHOUT its BorderRegion (those lines are neither
                -- recolorable nor pixel-snapped); the border here is our own.
                Skin.SquareIcon(glyphTex)
                -- Action-bar 5.5% zoom on top of the engine's 8% square crop, so
                -- loot icons read at the bars' zoom. LOCAL to loot rows; SquareIcon
                -- stays at 8% everywhere else. Re-asserted whenever Blizzard
                -- re-textures the icon: per-slot repopulation writes the texture
                -- directly without a ScrollBox Update, so a one-shot SetTexCoord can be overwritten. Post-hook only, args untouched.
                glyphTex:SetTexCoord(0.135, 0.865, 0.135, 0.865)
                local icd = GetFFD(glyphTex)
                if not icd.coordHook and glyphTex.SetTexture then
                    icd.coordHook = true
                    hooksecurefunc(glyphTex, "SetTexture", function(self)
                        self:SetTexCoord(0.135, 0.865, 0.135, 0.865)
                    end)
                end

                -- Blizzard's slot frame (button's NormalTexture) draws a ring that
                -- swallowed the zoom visually; the roll-popup pack already hides its
                -- equivalent. Guarded against the icon fallback above, which can BE the normal texture on some templates.
                local nt = entry.GetNormalTexture and entry:GetNormalTexture()
                if nt and nt ~= glyphTex and nt.SetAlpha then
                    nt:SetAlpha(0)
                end

                -- 1px physical, pixel-perfect, quality-colored icon border. Strips
                -- live on a HOST FRAME of ours (child of the row, anchored to the
                -- icon) via PP.CreateBorder (integer physical thickness,
                -- snap-immune), so NOTHING is written onto Blizzard frames -- all state sits in FFD and PP's own registry.
                local PPb = CludesUI and (CludesUI.PanelPP or CludesUI.PP)
                local importData = GetFFD(entry)
                if not importData.qBorder and PPb and PPb.CreateBorder and entry.CreateTexture then
                    local owner = CreateFrame("Frame", nil, entry)
                    owner:SetPoint("TOPLEFT", glyphTex, "TOPLEFT", 0, 0)
                    owner:SetPoint("BOTTOMRIGHT", glyphTex, "BOTTOMRIGHT", 0, 0)
                    owner:SetFrameLevel(entry:GetFrameLevel() + 2)
                    PPb.CreateBorder(owner, 0, 0, 0, 1, 1, "OVERLAY", 7)
                    importData.qBorder = owner
                end
                -- Quality color read from Blizzard's own ring: vertex-colored per
                -- quality and HIDDEN for poor/common drops, so hidden/absent maps
                -- to black as wanted. Re-read every pass (pooled rows change item
                -- between opens); the ring is hidden again after reading.
                if importData.qBorder and PPb and PPb.SetBorderColor then
                    local ring = entry.IconBorder
                    local qr, qg, qb = 0, 0, 0
                    local isQuality = false
                    if ring and ring.IsShown and ring:IsShown() and ring.GetVertexColor then
                        local rr, rg, rb = ring:GetVertexColor()
                        -- Uncommon and up only: poor/common rings are achromatic
                        -- (gray/white) while every quality from green up is saturated, so a
                        -- chroma test filters them with no item-quality lookup.
                        if rr and (math.max(rr, rg, rb) - math.min(rr, rg, rb)) > 0.1 then
                            qr, qg, qb = rr, rg, rb
                            isQuality = true
                        end
                        ring:SetAlpha(0)
                    end
                    -- Loot Window card's Icon Borders: the picked style and size, still in the quality color.
                    local saved = CludesUIDB
                    if saved and saved.lootIconBorder then
                        -- Poor/common take the window border's color (black while that border is Default).
                        if not isQuality then
                            local wc = LootWindowColor()
                            if wc then
                                qr, qg, qb = wc.r, wc.g, wc.b
                            end
                        end
                        local texture = saved.lootIconBorderTexture or "solid"
                        local key = saved.lootIconBorderThickness
                        local size = key and (CludesUI.BORDER_STEP_OF_LABEL[key] or 1) or 1
                        CludesUI.ApplyBorderStyle(
                            importData.qBorder,
                            size,
                            qr,
                            qg,
                            qb,
                            1,
                            texture,
                            saved.lootIconBorderOffsetX,
                            saved.lootIconBorderOffsetY,
                            nil,
                            nil,
                            "blizzardSkin",
                            key or "thin",
                            nil,
                            CludesUI.BorderPx(saved.lootIconBorderThicknessPx, size, texture)
                        )
                        importData.qStyled = true
                    elseif importData.qStyled then
                        CludesUI.HideBorderStyle(importData.qBorder)
                        importData.qBorder:Show()
                        CludesUI.PP.UpdateBorder(importData.qBorder, 1, qr, qg, qb, 1)
                        CludesUI.PP.ShowBorder(importData.qBorder)
                        importData.qStyled = nil
                    else
                        PPb.SetBorderColor(importData.qBorder, qr, qg, qb, 1)
                    end
                end
            end
            for _, owner in ipairs({ row, entry }) do
                for _, keyName in ipairs({ "NameFrame", "Background", "Bg" }) do
                    local part = owner[keyName]
                    if part and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
                -- Card STROKE textures ring the row card: BorderFrame carries
                -- Looting_ItemCard_Stroke_Normal, HighlightNameFrame / PushedNameFrame the
                -- ClickState variant Blizzard drives to 0.7 alpha on hover/click.
                -- State-driven alpha overwrites a plain SetAlpha(0), so clear the ART
                -- instead (a state driver can animate nothing). Re-cleared every pass
                -- in case a pooled row re-applies its template atlas; the 5% highlight backdrop is the replacement hover cue.
                for _, keyName in ipairs({ "BorderFrame", "PushedNameFrame", "HighlightNameFrame" }) do
                    local part = owner[keyName]
                    if part and part.SetAlpha then
                        if part.SetAtlas then
                            part:SetAtlas("")
                        end
                        if part.SetTexture then
                            part:SetTexture("")
                        end
                        part:SetAlpha(0)
                    end
                end
                -- The stack count KEEPS Blizzard's font: it is an outlined NUMBER
                -- font drawn over the icon, and the panel face reads unreadable on a bright icon. Everything else is re-fonted.
                local countFS = owner.Count
                    or owner.count
                    or (owner.GetName and owner:GetName() and _G[owner:GetName() .. "Count"])
                if owner.GetRegions then
                    local regionList = { owner:GetRegions() }
                    for idx = 1, #regionList do
                        local region = regionList[idx]
                        if region and region ~= countFS and region.IsObjectType and region:IsObjectType("FontString") then
                            Skin.Font(region)
                        end
                    end
                end
                local highlight = owner.GetHighlightTexture and owner:GetHighlightTexture()
                if highlight and highlight.SetColorTexture then
                    if owner == entry then
                        -- Item tile hover: flat white backdrop over the whole tile
                        -- instead of Blizzard's hover ring. BLEND explicitly
                        -- (highlights default to ADD, reading as a glow), re-asserted
                        -- via SetAtlas/SetTexture post-hooks since per-slot repopulation re-arts the highlight with no ScrollBox Update.
                        local hld = GetFFD(highlight)
                        local function flat(self)
                            self:SetColorTexture(1, 1, 1, 0.08)
                            self:SetBlendMode("BLEND")
                        end
                        flat(highlight)
                        highlight:SetTexCoord(0, 1, 0, 1)
                        -- Anchored to the ROW, not the item button: the backdrop
                        -- lifts the whole card, of which the icon slot is only a
                        -- corner. Texture stays in the item's highlight slot, so it still shows exactly while hovered.
                        highlight:ClearAllPoints()
                        highlight:SetAllPoints(row)
                        if not hld.flatHook then
                            hld.flatHook = true
                            hooksecurefunc(highlight, "SetAtlas", flat)
                            hooksecurefunc(highlight, "SetTexture", flat)
                        end
                    else
                        highlight:SetColorTexture(1, 1, 1, 0.1)
                    end
                end
            end
        end

        local tabBox = win.ScrollBox
        -- Item list 5px lower, ONCE per session: Skin_Loot re-runs on every open,
        -- and an unguarded relative shift walks the box down 5px per loot.
        if tabBox and tabBox.GetNumPoints then
            local partData = GetFFD(tabBox)
            if not partData.shifted then
                partData.shifted = true
                local numPoints = tabBox:GetNumPoints()
                local pts = {}
                for idx = 1, numPoints do
                    pts[idx] = { tabBox:GetPoint(idx) }
                end
                if numPoints > 0 then
                    tabBox:ClearAllPoints()
                    for idx = 1, numPoints do
                        local pt = pts[idx]
                        tabBox:SetPoint(pt[1], pt[2], pt[3], pt[4] or 0, (pt[5] or 0) - 5)
                    end
                end
            end
        end
        if tabBox and tabBox.ForEachFrame then
            pcall(tabBox.ForEachFrame, tabBox, SkinLootRow)
            local buttonData = GetFFD(tabBox)
            if tabBox.Update and not buttonData.rowHook then
                buttonData.rowHook = true
                hooksecurefunc(tabBox, "Update", function(button)
                    pcall(button.ForEachFrame, button, SkinLootRow)
                end)
            end
        end

        ApplyLootBorder(win)

        Skin.HookShow(
            win,
            Skin.Debounce(function()
                if win:IsVisible() then
                    Skin_Loot()
                    Skin.Restrip()
                end
            end)
        )
    end

    CludesUI._Loot_RefreshBorder = function()
        local win = _G.LootFrame
        if not (lootSkinned and win) then
            return
        end
        -- Open: a full pass also restyles the icon borders. Closed: the next open does that.
        if win:IsShown() then
            Skin_Loot()
        else
            ApplyLootBorder(win)
        end
    end

    Skin.RegisterWindow({
        key = "loot",
        apply = Skin_Loot,
    })
end

-------------------------------------------------------------------------------
--  Loot toasts (the "You received" alert popups). NOT a window: alert frames
--  are POOLED and recycled, so there is no single frame to skin at login.
--  Frames are reached through the alert subsystems' object pools and re-skinned
--  whenever a toast fires (idempotent + FFD-guarded).
-------------------------------------------------------------------------------
do
    local function Skin_LootToast()
        -- Native size/layout of the money toast template, captured from the first
        -- money toast seen; item toasts are resized/re-anchored to match (frame
        -- size, icon size, icon inset, icon-to-text gap, text centering). Offsets stored in FRAME UNITS (effective scale divided out at capture).
        local moneyToastH, moneyToastW, moneyIconH
        local moneyIconL, moneyIconCy, moneyTextGap, moneyTextCy

        -- The reference is PERSISTED (CludesUIDB.lootToastMoneyRef): sessions see
        -- item toasts long before any gold toast, and the fallback sizing is visibly
        -- off. One gold toast ever seen seeds every later session, and the live
        -- capture keeps refreshing it, so a template change self-corrects on the
        -- next gold drop. A CACHE, not a setting -- NOT in the profile-export allowlist.
        do
            local c = CludesUIDB and CludesUIDB.lootToastMoneyRef
            if type(c) == "table" then
                moneyToastH, moneyToastW, moneyIconH = c.h, c.w, c.iconH
                moneyIconL, moneyIconCy = c.iconL, c.iconCy
                moneyTextGap, moneyTextCy = c.textGap, c.textCy
            end
        end

        -- Flatten the toast's ornate art to a house panel. Only frames that look like a loot toast are touched; other alert styles are left alone.
        local function SkinToast(t)
            if not t or type(t) ~= "table" or not t.IsForbidden or t:IsForbidden() then
                return
            end
            -- Shape test: a text label is the reliable marker (this template
            -- carries .Background+.ItemName). Icon must NOT be required -- its key varies, and gating on it misses the loot toast entirely.
            local labelText = t.ItemName or t.Label or t.Title
            if not (type(labelText) == "table" and labelText.GetText) then
                return
            end
            local glyphTex = t.Icon or t.icon or (t.lootItem and t.lootItem.Icon)
            local skinData = GetFFD(t)
            if not skinData.bg then
                -- Full style-aware shell so a toast follows the window setting:
                -- modern_blizz atlas+black overlay on "cui", flat user color on
                -- "modern", swapping live. No top bar (toast has no title row), but the atlas frame IS kept for its soft edge vignette.
                Skin.Shell("loottoast", t, { noTopBar = true })
            end
            -- Decorative art off, icon kept. SetAlpha(0) is NOT enough: a toast
            -- fades in through an ANIMATION that drives alpha every frame and wins
            -- over our write. Clear the TEXTURE instead (an animation can animate
            -- nothing). Re-run per toast: Blizzard's setup re-applies atlases every time a pooled frame is reused.
            local keepSet = {}
            if glyphTex then
                keepSet[glyphTex] = true
            end
            -- Every texture the shell owns, or the art kill below would wipe our
            -- own backdrop along with Blizzard's.
            for _, keyName in ipairs({ "bg", "bgOverlay", "modernBg", "topBar", "bottomBar", "selBar" }) do
                if skinData[keyName] then
                    keepSet[skinData[keyName]] = true
                end
            end
            -- Frames of OURS hanging off the toast (shell atlas border, PP border
            -- container): the recursion below would clear their textures too.
            local PPt = CludesUI and (CludesUI.PanelPP or CludesUI.PP)
            local ourBorder = PPt and PPt.GetBorders and PPt.GetBorders(t)
            local function KillArt(owner, nestDepth)
                nestDepth = nestDepth or 0
                if not owner or nestDepth > 2 or not owner.IsForbidden or owner:IsForbidden() then
                    return
                end
                if owner == skinData.atlasBorderFrame or owner == ourBorder then
                    return
                end
                -- Provenance gate: this clears textures OUTRIGHT (SetAtlas /
                -- SetTexture "" then alpha 0), unrecoverable for a foreign frame.
                if nestDepth > 0 and Skin.IsForeignFrame(owner) then
                    return
                end
                if owner.GetRegions then
                    local regionList = { owner:GetRegions() }
                    for idx = 1, #regionList do
                        local region = regionList[idx]
                        if region and not keepSet[region] and region.IsObjectType and region:IsObjectType("Texture") then
                            if region.SetAtlas then
                                region:SetAtlas("")
                            end
                            if region.SetTexture then
                                region:SetTexture("")
                            end
                            region:SetAlpha(0)
                        end
                    end
                end
                if not owner.GetChildren then
                    return
                end
                local children = { owner:GetChildren() }
                for idx = 1, #children do
                    KillArt(children[idx], nestDepth + 1)
                end
            end
            KillArt(t)
            if glyphTex and glyphTex.SetTexCoord then
                Skin.SquareIcon(glyphTex, t)
            end

            -- User scale (options slider), both toast types. MUST run before the
            -- pixel-grid strip solve below, so onePx reflects the final scale.
            local sc = (CludesUIDB and CludesUIDB.lootToastScale) or 1
            if t.SetScale and t.GetScale and t:GetScale() ~= sc then
                t:SetScale(sc)
            end

            -- Tighter ITEM toasts, sized to the money toast. Money frame (.Amount)
            -- keeps its native tighter template and is the height reference; item
            -- toasts adopt it once a money toast has been seen (-16px fallback
            -- until then) and lose 6px of icon. Bases captured on first sight, shrink re-asserted every pass since Blizzard repaints a pooled frame on reuse.
            local isMoney = t.Amount ~= nil
            if not skinData.baseH and t.GetHeight then
                local hgt = t:GetHeight()
                if hgt and hgt > 16 then
                    skinData.baseH = hgt
                end
            end
            if not skinData.baseW and t.GetWidth then
                local wid = t:GetWidth()
                if wid and wid > 50 then
                    skinData.baseW = wid
                end
            end
            if isMoney then
                -- Live values always win over the cached seed: money frames are
                -- never resized by us, so these reads are the native template.
                if skinData.baseH then
                    moneyToastH = skinData.baseH
                end
                if skinData.baseW then
                    moneyToastW = skinData.baseW
                end
                if glyphTex and glyphTex.GetHeight then
                    local ih = glyphTex:GetHeight()
                    if ih and ih > 6 then
                        moneyIconH = ih
                    end
                end
                -- "You received" header 2px down, matching the item toast nudge.
                local heading = t.Label
                if heading and heading.GetPoint and heading.ClearAllPoints then
                    if not skinData.hdrPt then
                        local point, relTo, relPoint, posX, posY = heading:GetPoint(1)
                        if point then
                            skinData.hdrPt = { point, relTo, relPoint, posX or 0, posY or 0 }
                        end
                    end
                    if skinData.hdrPt then
                        heading:ClearAllPoints()
                        heading:SetPoint(skinData.hdrPt[1], skinData.hdrPt[2], skinData.hdrPt[3], skinData.hdrPt[4], skinData.hdrPt[5] - 2)
                    end
                end
                if glyphTex and glyphTex.GetLeft and t.GetLeft then
                    local es = (t.GetEffectiveScale and t:GetEffectiveScale()) or 1
                    local il, tl = glyphTex:GetLeft(), t:GetLeft()
                    local _, icy = glyphTex:GetCenter()
                    local _, tcy = t:GetCenter()
                    if il and tl and icy and tcy and es > 0 then
                        moneyIconL = (il - tl) / es
                        moneyIconCy = (icy - tcy) / es
                        local amt = t.Amount
                        if amt and amt.GetLeft and glyphTex.GetRight then
                            local al, ir = amt:GetLeft(), glyphTex:GetRight()
                            local _, acy = amt:GetCenter()
                            if al and ir then
                                moneyTextGap = (al - ir) / es
                            end
                            if acy then
                                moneyTextCy = (acy - icy) / es
                            end
                        end
                    end
                end
                -- Refresh the persisted reference with whatever was readable.
                if moneyToastH then
                    if not CludesUIDB then
                        CludesUIDB = {}
                    end
                    CludesUIDB.lootToastMoneyRef = {
                        h = moneyToastH,
                        w = moneyToastW,
                        iconH = moneyIconH,
                        iconL = moneyIconL,
                        iconCy = moneyIconCy,
                        textGap = moneyTextGap,
                        textCy = moneyTextCy,
                    }
                end
            else
                if skinData.baseH and t.SetHeight then
                    local target = moneyToastH or (skinData.baseH - 16)
                    if target < skinData.baseH then
                        t:SetHeight(target)
                    end
                end
                if skinData.baseW and moneyToastW and t.SetWidth and moneyToastW ~= skinData.baseW then
                    t:SetWidth(moneyToastW)
                end
                if glyphTex and glyphTex.GetSize and glyphTex.SetSize then
                    if not skinData.iconBaseW then
                        local iw, ih = glyphTex:GetSize()
                        if iw and ih and iw > 6 and ih > 6 then
                            skinData.iconBaseW, skinData.iconBaseH = iw, ih
                        end
                    end
                    if skinData.iconBaseW then
                        local target = moneyIconH or (skinData.iconBaseH - 6)
                        if target < skinData.iconBaseH then
                            glyphTex:SetSize(target, target)
                        end
                    end
                end
                -- Mirror the money toast's internal layout: icon inset from the left
                -- edge, vertically centered like the coin; name text at the
                -- coin-to-amount gap, right edge kept so long names truncate
                -- instead of overflowing. Re-asserted per pass. On top of the
                -- mirrored offsets: icon 10px further left, item name 21px total (10 on the icon anchor, 11 off the gap), header 7px left.
                if moneyIconL and glyphTex and glyphTex.ClearAllPoints then
                    glyphTex:ClearAllPoints()
                    glyphTex:SetPoint("LEFT", t, "LEFT", moneyIconL - 10, moneyIconCy or 0)
                    local nameFS = t.ItemName or (t.lootItem and t.lootItem.ItemName)
                    if nameFS and nameFS.ClearAllPoints and moneyTextGap then
                        nameFS:ClearAllPoints()
                        nameFS:SetPoint("LEFT", glyphTex, "RIGHT", moneyTextGap - 11, moneyTextCy or 0)
                        nameFS:SetPoint("RIGHT", t, "RIGHT", -8, moneyTextCy or 0)
                        if nameFS.SetJustifyH then
                            nameFS:SetJustifyH("LEFT")
                        end
                    end
                    local heading = t.Label
                    if heading and heading ~= nameFS and heading.GetPoint and heading.ClearAllPoints then
                        -- Base anchor captured once pre-shift, re-applied with the
                        -- offsets each pass (net 7px left, 2px down); if the header
                        -- rides the icon we moved left, compensate so the net horizontal shift stays put.
                        if not skinData.hdrPt then
                            local point, relTo, relPoint, posX, posY = heading:GetPoint(1)
                            if point then
                                skinData.hdrPt = { point, relTo, relPoint, posX or 0, posY or 0 }
                            end
                        end
                        if skinData.hdrPt then
                            local dx = (skinData.hdrPt[2] == glyphTex) and 3 or -7
                            heading:ClearAllPoints()
                            heading:SetPoint(
                                skinData.hdrPt[1],
                                skinData.hdrPt[2],
                                skinData.hdrPt[3],
                                skinData.hdrPt[4] + dx,
                                skinData.hdrPt[5] - 2
                            )
                        end
                    end
                end
            end

            -- Rarity strip (item toasts default ON, money toasts opt-in). Icon's
            -- quality ring went out with the rest of the art, so this carries
            -- rarity in the tabs' accent-bar language. Color comes from the item
            -- NAME's own text color, already quality-set by Blizzard: no item
            -- lookup, correct for currency and gear alike. Re-read every pass since pooled frames are reused for other drops.
            if not skinData.selBar then
                -- The bar lives on its OWN host frame, not the toast: the shell's
                -- atlas border is a CHILD FRAME (frameLevel +6) and child frames
                -- draw over every parent texture regardless of layer, so a bar painted on the toast itself sits under the border art.
                local owner = CreateFrame("Frame", nil, t)
                owner:SetAllPoints(t)
                skinData.selBarHost = owner
                local barFrame = owner:CreateTexture(nil, "OVERLAY", nil, 7)
                -- Tab-underline pixel treatment: unsnapped, so a thin strip cannot
                -- round away at fractional scales.
                local Pix = CludesUI and CludesUI.PanelPP
                if Pix and Pix.DisablePixelSnap then
                    Pix.DisablePixelSnap(barFrame)
                end
                skinData.selBar = barFrame
            end
            -- Above the atlas border, re-asserted per pass (the border frame's
            -- level derives from the toast's, which pooling can reflow).
            if skinData.selBarHost then
                local abf = skinData.atlasBorderFrame
                local lvl = (abf and abf.GetFrameLevel and abf:GetFrameLevel()) or (t:GetFrameLevel() + 6)
                skinData.selBarHost:SetFrameLevel(lvl + 1)
            end
            -- Full-height rail flush with the frame's left edge. Alignment is
            -- solved on the PHYSICAL pixel grid: frame edges sit at fractional
            -- physical coordinates, so the strip's left/top/bottom snap to the
            -- nearest pixel column/row (position-class epsilon round, ties up --
            -- the house convention) and its width is a whole number of physical
            -- pixels. An unsnapped quad N physical px thick at a whole-pixel
            -- position rasterizes exactly N columns, flush with the shell's
            -- snapped fill: no seam, no drift. Re-solved every pass so scale
            -- changes and frame moves re-align it; falls back to plain corner anchors when the frame has no rect yet.
            local PPx = CludesUI and CludesUI.PP
            local esc = t.GetEffectiveScale and t:GetEffectiveScale()
            local onePx = (PPx and PPx.perfect and esc and esc > 0) and (PPx.perfect / esc) or 1
            local function snap(v)
                return math.floor(v / onePx + 0.5 + 0.001) * onePx
            end
            local l, button, wid, hgt = t:GetRect()
            skinData.selBar:ClearAllPoints()
            if l and button and hgt and hgt > 0 then
                local dx = snap(l) - l
                skinData.selBar:SetPoint("TOPLEFT", t, "TOPLEFT", dx, snap(button + hgt) - (button + hgt))
                skinData.selBar:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", dx, snap(button) - button)
            else
                skinData.selBar:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
                skinData.selBar:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
            end
            -- One physical pixel narrower than the ~3px base.
            skinData.selBar:SetWidth(math.max(1, math.floor(3 / onePx + 0.5) - 1) * onePx)
            -- Item toasts default ON (lootToastQualityStrip ~= false); money toasts
            -- are opt-in (lootToastQualityStripMoney) since gold has no rarity to signal, and their strip takes the header's gold color.
            local stripOn
            if isMoney then
                stripOn = CludesUIDB and CludesUIDB.lootToastQualityStripMoney == true
            else
                stripOn = not CludesUIDB or CludesUIDB.lootToastQualityStrip ~= false
            end
            skinData.selBar:SetShown(stripOn)
            if stripOn then
                local qr, qg, qb = labelText:GetTextColor()
                if qr then
                    skinData.selBar:SetColorTexture(qr, qg, qb, 0.9)
                end
            end
            -- Count is deliberately absent: stack numbers sit over the icon in an
            -- outlined number font and stay Blizzard's, same as the loot rows.
            for _, keyName in ipairs({ "Label", "Title", "ItemName", "SubTitle" }) do
                local fontStr = t[keyName]
                if fontStr and fontStr.GetFont then
                    Skin.Font(fontStr)
                end -- quality colors kept
            end
            Skin.Register(t, keepSet)
            return true
        end

        -- Toast frames already found, so repeat passes never re-walk UIParent.
        -- Weak-keyed: a pool frame that goes away takes its entry with it.
        local known = setmetatable({}, { __mode = "k" })

        -- deep = also walk UIParent's children looking for NEW toast frames. Only
        -- the first pass of a burst needs that; the follow-ups re-skin what is
        -- already known, which is a handful of frames.
        local function SweepAlerts(deep)
            for win in pairs(known) do
                SkinToast(win)
            end
            local auctionsFrame = _G.AlertFrame
            if not auctionsFrame then
                return
            end
            local subs = auctionsFrame.alertFrameSubSystems
            if type(subs) == "table" then
                for _, sys in ipairs(subs) do
                    local pool = sys and sys.alertFramePool
                    if pool and pool.EnumerateActive then
                        local success, iter = pcall(pool.EnumerateActive, pool)
                        if success and iter then
                            for widget in iter do
                                SkinToast(widget)
                            end
                        end
                    end
                end
            end
            if auctionsFrame.GetChildren then
                local children = { auctionsFrame:GetChildren() }
                for idx = 1, #children do
                    SkinToast(children[idx])
                end
            end
            -- The loot toast is parented to UIPARENT, not AlertFrame, and is
            -- anonymous (FULLSCREEN_DIALOG, carrying .Background+.ItemName), so
            -- walking AlertFrame alone never reaches it. Scan UIParent's children
            -- too, narrowed to SHOWN FULLSCREEN_DIALOG frames to stay cheap.
            --
            -- The PROVENANCE GATE IS LOAD-BEARING here more than anywhere else:
            -- this is the only sweep walking UIParent rather than inside a
            -- Blizzard window, and SkinToast's shape test is broad (any
            -- .ItemName/.Label/.Title that can GetText). Plenty of ADDON dialogs
            -- sit at FULLSCREEN_DIALOG with a .Title, ours included; without the gate this sweep silently blanks other addons' windows.
            --
            -- SECRECY: this walks EVERY UIParent child, so it meets frames this
            -- addon did not create, and a widget fed secret data hands back SECRET
            -- values from ordinary getters (comparing one throws in addon code).
            -- Nothing secret-aspected is ever a loot toast, so secret == skip.
            -- Both reads resolve into locals BEFORE any comparison -- a getter
            -- called mid-`and`-chain throws on the spot instead of skipping.
            local up = _G.UIParent
            if deep and up and up.GetChildren then
                local isSecret = issecretvalue
                local children = { up:GetChildren() }
                for idx = 1, #children do
                    local childFrame = children[idx]
                    if childFrame and childFrame.GetFrameStrata and childFrame.IsForbidden and not childFrame:IsForbidden() then
                        local strata, isShown = childFrame:GetFrameStrata(), childFrame:IsShown()
                        if
                            not (isSecret and (isSecret(strata) or isSecret(isShown)))
                            and isShown
                            and strata == "FULLSCREEN_DIALOG"
                            and not Skin.IsForeignFrame(childFrame, up)
                        then
                            if SkinToast(childFrame) then
                                known[childFrame] = true
                            end
                        end
                    end
                end
            end
        end

        -- Options entry point: re-sweep so a strip toggle lands on a toast that is
        -- already on screen (the next one would pick it up regardless).
        CludesUI._LootToast_Refresh = function()
            SweepAlerts(true)
        end

        local skinData = GetFFD(_G.AlertFrame or UIParent)
        if skinData.toastEvt then
            return
        end
        local eventFrame = CreateFrame("Frame")
        skinData.toastEvt = eventFrame
        -- Toasts are handed out by the pool, set up, then animated in over a few
        -- tenths of a second, and the setup can land AFTER the first pass. Sweep
        -- immediately and again across the animation window; only the FIRST pass walks UIParent, the rest re-skin the frames it found.
        local function Shallow()
            SweepAlerts(false)
        end
        local sweep = Skin.Debounce(function()
            SweepAlerts(true)
            if C_Timer then
                C_Timer.After(0.05, Shallow)
                C_Timer.After(0.2, Shallow)
                C_Timer.After(0.5, Shallow)
            end
        end)
        eventFrame:SetScript("OnEvent", sweep)
        -- Toast events ONLY. Never CURRENCY_DISPLAY_UPDATE: it fires on every
        -- currency change (quest turn-ins, vendoring, combat drops), far more often
        -- than a toast appears, and each fire costs a full sweep for nothing.
        -- TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED is the "You Collected"
        -- appearance toast (NewCosmeticAlertFrameSystem). SweepAlerts already
        -- REACHED that frame -- it walks every alertFrameSubSystems pool, and the
        -- toast passes SkinToast's shape test via .Label/.Icon -- but nothing woke
        -- the sweep while one was on screen, so it lived and died stock.
        -- TRANSMOG_COLLECTION_SOURCE_ADDED is the same toast on the Trading Post
        -- path (AlertFrames.lua routes both into the same system).
        for _, event in ipairs({
            "SHOW_LOOT_TOAST",
            "SHOW_LOOT_TOAST_UPGRADE",
            "SHOW_PVP_FACTION_LOOT_TOAST",
            "SHOW_RATED_PVP_REWARD_TOAST",
            "LOOT_ITEM_ROLL_WON",
            "TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED",
            "TRANSMOG_COLLECTION_SOURCE_ADDED",
        }) do
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        end
        SweepAlerts(true)
    end

    Skin.RegisterWindow({
        key = "loottoast",
        apply = Skin_LootToast,
    })
end

-------------------------------------------------------------------------------
--  Social UI (12.1 friends window: SocialUIFrame, Blizzard_SocialUI).
--
--  CHROME ONLY: window shell, border, title, close button, Battle.net bar, and
--  the per-tab controls (search box, filter dropdown, action button).
--  Deliberately 100% stock: side tab icons (LargeSideTabButtonTemplate), every
--  ScrollBox/ScrollBar/pooled list row (friend/ally/quick-join content is owned by the friends module).
--
--  ENUMERATIVE on purpose: NO CommonChrome/ControlsIn/ButtonsIn/ScrollBarsIn
--  sweeps anywhere, since those walk the frame tree into list content and the tab strip. Every target below is named.
--
--  Helpers and constants hang off SP, inside this pack's own do...end block
--  (see the note at the top of the file on the 200-local limit).
-------------------------------------------------------------------------------
do
    local SP = {
        CONTENT_KEYS = {
            "FriendsList",
            "RecentAlliesList",
            "QuickJoinFrame",
            "FriendRequestsList",
            "RecruitAFriendFrame",
            "RaidFrame",
        },

        -- Blizzard ships the search box at 20 tall, filter dropdown at 30; both meet in the middle so the filter row reads as one strip.
        CONTROL_H = 26,
        FILTER_PAD = 10, -- left inset of the (now left-aligned) Filter label

        -- Hamburger is a 34px plate around a native-size atlas: shrink the plate, shrink the glyph less.
        MENU_BTN_SZ = 28,
        MENU_ICON_SZ = 16,
        MENU_ICON_Y = -1, -- glyph nudged down inside the plate

        -- Filter dropdown's right edge, measured from the window's right edge:
        -- content frames sit at BOTTOMRIGHT -2, FilterBar spans them, dropdown
        -- inset RIGHT -10 inside that. WSkin.Dropdown/Button fill SetAllPoints, so frame edges are the visual edges.
        DD_RIGHT_INSET = 12,

        -- SearchBar sits at LEFT+15 inside FilterBar, and FilterBar shares a left
        -- edge with the Battle.net bar's ControlsContainer, so reusing 15 lines the
        -- status dropdown up with the search box exactly (Blizzard ships it at 65).
        STATUS_X = 15,
    }

    -- Geometry only, split out from the skin pass: these frames inherit
    -- UserScaledFrameTemplate, and TextSizeManager re-derives their size from the
    -- baseHeight KeyValue whenever text scale changes, so a one-shot resize silently reverts. Re-applied every pass.
    function SP.LayoutFilterBar(castFrame)
        local foundBottom = castFrame.FilterBar
        if not foundBottom then
            return
        end

        local scrollBar = foundBottom.SearchBar
        if scrollBar and scrollBar.SetHeight then
            scrollBar:SetHeight(SP.CONTROL_H)
        end

        local dropdown = foundBottom.SearchFilterDropdown
        if dropdown then
            if dropdown.SetHeight then
                dropdown:SetHeight(SP.CONTROL_H)
            end
            -- Blizzard anchors the label to TOP with no left point, which centers
            -- it regardless of its LEFT justification. Re-anchor to the left edge.
            local txt = dropdown.Text
            if txt then
                txt:ClearAllPoints()
                txt:SetPoint("LEFT", dropdown, "LEFT", SP.FILTER_PAD, 0)
                txt:SetJustifyH("LEFT")
            end
        end
    end

    -- Right-align the Battle.net bar's hamburger with the filter dropdown below
    -- it. They live in different containers (content frame stretches to the
    -- window's right edge, ControlsContainer only spans the 413px Battle.net bar),
    -- so there is no shared inset: offset must be measured and RE-measured whenever the window width changes (side windows resize it).
    function SP.AlignMenuButton(win)
        local cc = win.BattleNetBar and win.BattleNetBar.ControlsContainer
        local btnFrame = cc and cc.BattleNetMenuButton
        if not btnFrame then
            return
        end

        local ccRight, winRight = cc:GetRight(), win:GetRight()
        if not ccRight or not winRight then
            return
        end
        if issecretvalue(ccRight) or issecretvalue(winRight) then
            return
        end

        -- Keep the vertical anchor on ControlsContainer (stays centered in the
        -- bar), shift only x: anchoring straight to the window would drag the button to the window's vertical center.
        local dx = (winRight - SP.DD_RIGHT_INSET) - ccRight
        btnFrame:ClearAllPoints()
        btnFrame:SetPoint("RIGHT", cc, "RIGHT", dx, 0)
    end

    function SP.SkinContentFrame(castFrame)
        if not castFrame or castFrame:IsForbidden() then
            return
        end

        -- Geometry runs every pass; the skinning below only once.
        SP.LayoutFilterBar(castFrame)

        local skinData = GetFFD(castFrame)
        if skinData.socialContent then
            return
        end
        skinData.socialContent = true

        -- Blizzard's perks-divider art brackets the list area: flatten it so the shell reads clean (content frame's OWN regions, not the ScrollBox's).
        if castFrame.TopDivider then
            castFrame.TopDivider:SetAlpha(0)
        end
        if castFrame.BottomDivider then
            castFrame.BottomDivider:SetAlpha(0)
        end

        local foundBottom = castFrame.FilterBar
        if foundBottom then
            if foundBottom.SearchBar then
                Skin.EditBox(foundBottom.SearchBar)
            end
            if foundBottom.SearchFilterDropdown then
                Skin.Dropdown(foundBottom.SearchFilterDropdown)
            end
        end

        if castFrame.ActionButton then
            Skin.Button(castFrame.ActionButton)
            Skin.WhiteButtonLabel(castFrame.ActionButton)
        end

        -- cf.ScrollBox / cf.ScrollBar / cf.LoadingSpinner: intentionally stock.
    end

    function SP.Apply()
        local win = _G.SocialUIFrame
        if not win then
            return
        end
        -- The Friends List stock styles (Style page) keep Blizzard's whole Social
        -- window, its frame included; the Window Skins card is blocked meanwhile.
        local found = CludesUI._ModuleNS and CludesUI._ModuleNS.CludesUIFriends
        if found and found.FR_Style and found.FR_Style() ~= "cui" then
            return
        end

        Skin.Shell("socialui", win)
        Skin.RemovePortrait(win)
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end

        -- Window-level art.
        if win.TopFade then
            win.TopFade:SetAlpha(0)
        end
        if win.BottomFade then
            win.BottomFade:SetAlpha(0)
        end
        if win.TopTileStreaks then
            win.TopTileStreaks:SetAlpha(0)
        end
        if win.Bg then
            win.Bg:SetAlpha(0)
        end

        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or win.TitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
        end

        local creatureBtn = win.CloseButton
            or (win.TitleContainer and win.TitleContainer.CloseButton)
            or (win.GetName and _G[(win:GetName() or "") .. "CloseButton"])
        if creatureBtn then
            Skin.CloseButton(creatureBtn)
        end

        -- Battle.net bar: flatten the plate art, skin status dropdown and the square menu button (icon KEPT, only thing identifying it).
        local barFrame = win.BattleNetBar
        if barFrame then
            if barFrame.Background then
                barFrame.Background:SetAlpha(0)
            end
            local cc = barFrame.ControlsContainer
            if cc then
                if cc.BattleNetBackground then
                    cc.BattleNetBackground:SetAlpha(0)
                end

                local osd = cc.OnlineStatusDropdown
                if osd then
                    Skin.Dropdown(osd)
                    -- Blizzard anchors this at LEFT+65. ControlsContainer shares a
                    -- left edge with the content frame's FilterBar, so matching SearchBar's own LEFT inset lines the two up exactly.
                    osd:ClearAllPoints()
                    osd:SetPoint("LEFT", cc, "LEFT", SP.STATUS_X, 0)
                end

                local menuBtn = cc.BattleNetMenuButton
                if menuBtn then
                    Skin.Button(menuBtn, { "Icon" })
                    menuBtn:SetSize(SP.MENU_BTN_SZ, SP.MENU_BTN_SZ)
                    -- The glyph is useAtlasSize in XML, so it ignores the button
                    -- and needs an explicit size to grow inside the smaller plate.
                    if menuBtn.Icon then
                        menuBtn.Icon:SetSize(SP.MENU_ICON_SZ, SP.MENU_ICON_SZ)
                        -- Re-seat off the XML's bare CENTER. AdjustPointsOffset (the
                        -- mixin's press feedback) shifts whatever points are current, so it keeps working against this one.
                        menuBtn.Icon:ClearAllPoints()
                        menuBtn.Icon:SetPoint("CENTER", menuBtn, "CENTER", 0, SP.MENU_ICON_Y)
                        -- Strip the atlas's gold tint to match the chrome. One-shot
                        -- is enough: the mixin only nudges the icon's OFFSET on mouse down/up, never its color.
                        menuBtn.Icon:SetDesaturated(true)
                        menuBtn.Icon:SetVertexColor(1, 1, 1)
                    end
                end

                local tag = cc.PersonalBattleTagDisplay
                if tag and tag.DisplayText then
                    Skin.White(tag.DisplayText)
                end
            end
        end

        local function SkinContentFrames()
            for _, key in ipairs(SP.CONTENT_KEYS) do
                SP.SkinContentFrame(win[key])
            end
            SP.AlignMenuButton(win)
        end
        SkinContentFrames()

        -- Content frames exist only for tabs the client supports, and the set can
        -- change when a social system is toggled server-side, so re-run on show
        -- (SkinContentFrame is idempotent per frame).
        Skin.HookShow(win, function()
            SkinContentFrames()
            -- First open: window has not laid out yet, GetRight returns nil and alignment no-ops; re-run once it has.
            C_Timer.After(0, function()
                SP.AlignMenuButton(win)
            end)
        end)

        -- NO SetWidth/SetSize hooks here. SocialUIFrame is UIPanel-managed and
        -- resizes itself via SetUIPanelAttribute+UpdateUIPanelPositions when a side
        -- window opens; hooking its sizers puts our code inside the panel
        -- manager's own path, tainting it and killing ToggleUIPanel (the Friends
        -- keybind silently dies). Realigning on show is enough -- only a side window moves the right edge, and that reshows the frame anyway.
    end

    Skin.RegisterWindow({
        key = "socialui",
        -- Gates the whole pack to clients that ship the Social UI: where the addon
        -- does not exist, IsAddOnLoaded is false and apply never runs.
        addons = { Blizzard_SocialUI = true },
        apply = SP.Apply,
    })
end

---------
--  Loot rolls, group invites and the ready check.
--
--  Four small packs sharing one block: lootroll (group loot roll popups:
--  need/greed/DE/pass), loothistory ("Loot Rolls" window, GroupLootHistoryFrame),
--  groupinvite ("You have been invited to a group", both invite dialogs),
--  readycheck (the ready prompt + the initiator's response list).
--
--  Helpers and constants hang off LP, inside this block's do...end (see the
--  note at the top of the file on the 200-local limit).
-------------------------------------------------------------------------------
do
    local LP = {
        FLAT = "Interface\\Buttons\\WHITE8X8",

        -- Plate / border art that lives one level down from a frame's own regions,
        -- so the shell's region fade never reaches it.
        ART_KEYS = {
            "NameFrame",
            "Border",
            "BorderFrame",
            "Background",
            "Bg",
            "Decoration",
            "Frame",
            "Backdrop",
        },
        ICON_ART_KEYS = { "IconBorder", "NormalTexture", "Border", "IconQuestTexture" },
        ROW_ART_KEYS = {
            "NameFrame",
            "BorderFrame",
            "HighlightNameFrame",
            "PushedNameFrame",
            "IconQuestTexture",
        },
        INVITE_BTN_KEYS = { "AcceptButton", "DeclineButton", "AcknowledgeButton" },

        -- Progress fills that are a TEXTURE rather than a StatusBar (the loot
        -- history roll timer is one) cannot go through WSkin.ApplyBarFill, which
        -- drives SetStatusBarColor. Same behaviour, one shared looks callback.
        vertexFills = setmetatable({}, { __mode = "k" }),
    }

    -- Popup shell: full window treatment minus the title row. Style-aware backdrop
    -- (modern_blizz atlas on "cui", flat user color on "modern", swapping live)
    -- plus WSkin.AtlasBorder, the same soft-edged frame the Loot Rolls window and
    -- loot toasts carry. Only the 25px title bar is skipped (none of these frames
    -- has a title). Idempotent: Shell re-runs its region fade every call but builds textures once, so re-calling doubles as repaint catch-up.
    function LP.Shell(winKey, widget)
        Skin.Shell(winKey, widget, { noTopBar = true })
    end

    -- Alpha a list of named art keys. TEXTURES ONLY, and the type test is
    -- load-bearing: several of these names are a Texture on one template and a
    -- FRAME on another ("Border" is a NineSlice on portrait windows), and
    -- SetAlpha(0) on a frame takes its whole subtree (on the invite dialog that blanks the role icon and the buttons).
    function LP.FadeKeys(widget, keyList)
        if not widget then
            return
        end
        for idx = 1, #keyList do
            local part = widget[keyList[idx]]
            if part and part.IsObjectType then
                if part:IsObjectType("Texture") then
                    part:SetAlpha(0)
                elseif part.TopEdge or part.TopLeftCorner then
                    -- The frame IS a NineSlice (pure border art), so fading it
                    -- whole is right. ONLY this shape: WSkin.FadeNineSlice ends by
                    -- alpha-ing the frame handed to it, blanking the subtree of anything that merely CONTAINS one.
                    Skin.FadeNineSlice(part)
                end
            end
        end
    end

    -- Re-font a frame's own FontString regions, leaving their COLOR alone: item
    -- names and roll results are quality/state colored by Blizzard, never
    -- overwritten. `skip` is a stack COUNT -- an outlined number font drawn over an icon, unreadable in the panel face.
    function LP.FontRegions(widget, skip)
        if not widget or not widget.GetRegions then
            return
        end
        local regionList = { widget:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region ~= skip and region.IsObjectType and region:IsObjectType("FontString") then
                Skin.Font(region)
            end
        end
    end

    function LP.ApplyVertexFill(texture)
        if not texture or not texture.SetVertexColor then
            return
        end
        LP.vertexFills[texture] = true
        local red, green, blue, a = Skin.BarFillColor()
        texture:SetVertexColor(red, green, blue, a)
    end
    Skin.OnLooksChanged(function()
        local red, green, blue, a = Skin.BarFillColor()
        for texture in pairs(LP.vertexFills) do
            if texture.SetVertexColor then
                texture:SetVertexColor(red, green, blue, a)
            end
        end
    end)

    -- Run fn(frame) as soon as a named Blizzard frame exists: immediately if it
    -- already does, otherwise on the ADDON_LOADED that creates it. Which dialogs
    -- are base UI vs load-on-demand has moved between expansions, so none is assumed present at login.
    function LP.WhenFrameExists(label, func)
        if _G[label] then
            func(_G[label])
            return
        end
        local eventFrame = CreateFrame("Frame")
        eventFrame:RegisterEvent("ADDON_LOADED")
        eventFrame:SetScript("OnEvent", function(self)
            local found = _G[label]
            if found then
                self:UnregisterAllEvents()
                func(found)
            end
        end)
    end

    -- Any StatusBar -> flat fill in the user's bar-fill color over a near-black trough. Re-asserted every pass since Blizzard re-applies the bar's own art on reuse.
    function LP.Bar(barFrame)
        if not barFrame or barFrame:IsForbidden() or not barFrame.SetStatusBarTexture then
            return
        end
        local skinData = GetFFD(barFrame)
        barFrame:SetStatusBarTexture(LP.FLAT)
        local fillTex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
        if fillTex and fillTex ~= skinData.fill then
            skinData.fill = fillTex
            -- Fade the bar's frame art, never the fill itself: GetRegions() on a
            -- StatusBar includes the fill, so an unguarded FadeRegions blanks it.
            Skin.FadeRegions(barFrame, { [fillTex] = true })
            Skin.Register(barFrame, { [fillTex] = true })
        end
        if not skinData.bg then
            local bgTex = SolidTex(barFrame, "BACKGROUND", 0, 0, 0, 0.55)
            bgTex:SetAllPoints(barFrame)
            skinData.bg = bgTex
        end
        Skin.ApplyBarFill(barFrame)
    end

    -------------------------------------------------------------------------------
    --  Loot roll popups (GroupLootFrame1..N inside GroupLootContainer). The
    --  CONTAINER is deliberately UNTOUCHED: a bottom managed column frame whose
    --  position belongs to the shared frame placer (CludesUI.SetFramePlacer:
    --  the Shifter's saved spot, else the Cooldown Manager's, else Blizzard's own
    --  column spot); writing its layout flags from here taints the managed-layout
    --  pass.
    -------------------------------------------------------------------------------
    function LP.SkinRollFrame(win)
        if not win or win:IsForbidden() then
            return
        end
        LP.Shell("lootroll", win)
        LP.FadeKeys(win, LP.ART_KEYS)

        -- Item icon: squared + a 1px RARITY-colored frame.
        -- Roll BUTTONS (dice/coin/transmog/pass) KEEP Blizzard's glyphs: they are the popup's identity and no house equivalent reads as fast.
        local owner = win.IconFrame or win.Item
        local glyphTex = (owner and (owner.Icon or owner.icon)) or win.Icon
        if owner then
            LP.FadeKeys(owner, LP.ICON_ART_KEYS)
            local nt = owner.GetNormalTexture and owner:GetNormalTexture()
            if nt and nt.SetAlpha then
                nt:SetAlpha(0)
            end
        end
        -- The ONE surface with no ring to read. GroupLootFrame_OnShow does not use
        -- SetItemButtonQuality at all: it picks an ATLAS whose NAME encodes the
        -- quality (GetAtlasDataForLootBorderItemQuality), so there is no vertex
        -- color anywhere to recover. The roll API hands over the quality directly,
        -- which is both cheaper and exact -- and the frame is re-skinned on every
        -- START_LOOT_ROLL and container update, so a pooled frame taking a new
        -- item repaints without needing the SetItemButtonQuality hook.
        --
        -- Bordered only if the crop actually happened: SquareIcon leaves a MASKED
        -- icon native, and a square border round a masked shape is the same
        -- mistake as a square crop.
        if glyphTex and glyphTex.SetTexCoord and Skin.SquareIcon(glyphTex, nil) then
            local qr, qg, qb = 0, 0, 0
            if win.rollID and type(_G.GetLootRollItemInfo) == "function" then
                local _, _, _, quality = GetLootRollItemInfo(win.rollID)
                if type(quality) == "number" then
                    local cr, cg, creatureBtn
                    if C_Item and C_Item.GetItemQualityColor then
                        cr, cg, creatureBtn = C_Item.GetItemQualityColor(quality)
                    elseif GetItemQualityColor then
                        cr, cg, creatureBtn = GetItemQualityColor(quality)
                    end
                    -- Same uncommon-and-up rule the other surfaces get from
                    -- WSkin.RingQuality, applied to the same chroma test so a
                    -- common drop looks identical across all of them.
                    if type(cr) == "number" and (math.max(cr, cg, creatureBtn) - math.min(cr, cg, creatureBtn)) > 0.1 then
                        qr, qg, qb = cr, cg, creatureBtn
                    end
                end
            end
            Skin.QualityBorder(owner or win, glyphTex, qr, qg, qb)
        end

        -- Blizzard parks both timers one frame level BELOW the window so the
        -- window's own art frames them (GroupLootFrame_OnLoad; BonusRollFrame_OnLoad
        -- for the Bonus Roll's, which lives on PromptFrame). The shell backdrop is
        -- drawn on the window, so under it a bar all but vanishes: each rides one
        -- level above the window instead (the roll buttons' level).
        local level = win:GetFrameLevel() + 1
        local timer = win.Timer or win.Bar or win.StatusBar
        if timer and not timer:IsForbidden() then
            LP.Bar(timer)
            timer:SetFrameLevel(level)
        end
        local prompt = win.PromptFrame
        local ptimer = prompt and prompt.Timer
        if ptimer and not ptimer:IsForbidden() then
            LP.Bar(ptimer)
            ptimer:SetFrameLevel(level)
        end

        -- Name keeps its item-quality color; only the face changes.
        if win.Name then
            Skin.Font(win.Name)
        end
    end

    function LP.SkinAllRolls()
        local c = _G.GroupLootContainer
        local maxN = (c and c.maxIndex) or 4
        if type(maxN) ~= "number" or maxN < 4 then
            maxN = 4
        end
        for idx = 1, maxN do
            LP.SkinRollFrame(_G["GroupLootFrame" .. idx])
        end
        if c and type(c.rollFrames) == "table" then
            for _, rf in pairs(c.rollFrames) do
                LP.SkinRollFrame(rf)
            end
        end
    end

    function LP.ApplyLootRoll()
        -- Every hook lands on the NEXT frame, never inside Blizzard's own call:
        -- GroupLootContainer_Update runs as part of the managed-layout pass, and creating textures from inside it puts our code in that stack.
        local resweep = Skin.Debounce(LP.SkinAllRolls)

        if type(_G.GroupLootContainer_AddFrame) == "function" then
            hooksecurefunc("GroupLootContainer_AddFrame", resweep)
        end
        if type(_G.GroupLootContainer_Update) == "function" then
            hooksecurefunc("GroupLootContainer_Update", resweep)
        end
        -- No script hook on the container itself: it only shows inside
        -- GroupLootContainer_Update (hooked above), and code run from its OnShow
        -- would leave the rest of that update, the managed-layout pass, under our taint.

        -- Fallback for clients where those two globals have gone: the roll event itself is what puts a frame on screen.
        local eventFrame = CreateFrame("Frame")
        eventFrame:RegisterEvent("START_LOOT_ROLL")
        eventFrame:SetScript("OnEvent", resweep)

        LP.SkinAllRolls()
    end

    Skin.RegisterWindow({
        key = "lootroll",
        apply = LP.ApplyLootRoll,
    })

    -------------------------------------------------------------------------------
    --  The Loot Rolls window (GroupLootHistoryFrame).
    --
    --  DOCTRINE: a skin must NEVER be the thing that triggers a ScrollBox-backed
    --  frame's FIRST layout. Touching this window's geometry from the load pass
    --  poisons ScrollBox.updateLock, which ScrollBoxListMixin:Update reads on its
    --  first line; from then on every Update taints its own execution and
    --  re-stamps the lock, invisible to taintLog since no global is involved. The
    --  cure is purely TIMING: arm the frame's first OnShow and skin there.
    --
    --  ENUMERATIVE on purpose: no CommonChrome, no ControlsIn/ButtonsIn sweeps -- those walk the whole tree, and the tree here is pooled loot rows.
    -------------------------------------------------------------------------------
    function LP.SkinHistoryRow(row)
        if not row or row:IsForbidden() then
            return
        end

        -- Housing drops ride a wooden frame overlay that fights the flat look.
        -- Checked every pass (pooled rows change item between shows), read via WSkin.TexHay, which is secret-value safe.
        local shade = row.IconOverlay
        if shade then
            local hay = Skin.TexHay(shade)
            shade:SetAlpha((hay and hay:find("housing-item-wood-frame", 1, true)) and 0 or 1)
        end

        local skinData = GetFFD(row)
        if skinData.rowSkinned then
            return
        end
        skinData.rowSkinned = true

        if row.BackgroundArtFrame then
            Skin.FadeRegions(row.BackgroundArtFrame)
            Skin.Register(row.BackgroundArtFrame, true)
            local washTex = SolidTex(row.BackgroundArtFrame, "BACKGROUND", 1, 1, 1, 0.02)
            washTex:SetAllPoints(row.BackgroundArtFrame)
            GetFFD(row.BackgroundArtFrame).bg = washTex
        end
        LP.FadeKeys(row, LP.ROW_ART_KEYS)

        local entry = row.Item
        if entry then
            LP.FadeKeys(entry, LP.ICON_ART_KEYS)
            local nt = entry.GetNormalTexture and entry:GetNormalTexture()
            if nt and nt.SetAlpha then
                nt:SetAlpha(0)
            end
            local glyphTex = entry.icon or entry.Icon
            if glyphTex and glyphTex.SetTexCoord then
                Skin.SquareIcon(glyphTex, entry)
            end
        end

        -- Item name and winner line: face only. Colors stay Blizzard's (quality on the name, green on "won/passed" state).
        local countFS = row.Count or row.count or (entry and (entry.Count or entry.count))
        LP.FontRegions(row, countFS)
        for _, keyName in ipairs({ "Text", "PlayerName", "Name", "RollResult" }) do
            local fontStr = row[keyName]
            if fontStr and fontStr ~= countFS and fontStr.GetFont then
                Skin.Font(fontStr)
            end
        end
    end

    function LP.SkinHistoryRows(win)
        local tabBox = win.ScrollBox
        if not (tabBox and tabBox.ForEachFrame) then
            return
        end
        pcall(tabBox.ForEachFrame, tabBox, LP.SkinHistoryRow)
        local buttonData = GetFFD(tabBox)
        if tabBox.Update and not buttonData.rowHook then
            buttonData.rowHook = true
            hooksecurefunc(tabBox, "Update", function(button)
                pcall(button.ForEachFrame, button, LP.SkinHistoryRow)
            end)
        end
    end

    -- The resize grab at the window's foot: Blizzard's gold grip flattened to three house rules.
    function LP.SkinResizeGrip(rb)
        if not rb or rb:IsForbidden() then
            return
        end
        local skinData = GetFFD(rb)
        if skinData.grip then
            return
        end
        skinData.grip = true
        -- Blizzard parks the grip BELOW the window's bottom edge where it is
        -- effectively invisible, so pull it 2px inside the frame. It is a wide flat
        -- grab-BAR (32x12): keep it horizontally CENTERED like the native design,
        -- grow it proportionally so the aspect ratio holds. Guarded one-time, so repeat skin passes cannot re-shift it.
        local owner = rb:GetParent()
        if owner then
            rb:ClearAllPoints()
            rb:SetPoint("BOTTOM", owner, "BOTTOM", 0, 2)
        end
        local w0, h0 = rb:GetSize()
        if w0 and w0 > 0 and h0 and h0 > 0 then
            rb:SetSize(w0 + 8, h0 * ((w0 + 8) / w0))
        end
        for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
            local func = rb[getter]
            local part = func and func(rb)
            if part and part.SetAlpha then
                part:SetAlpha(0)
            end
        end
        Skin.FadeRegions(rb)
        -- Grip glyph scaled with the bigger button (18/15/12, not 10/7/4). NOT an
        -- atlas: three hand-drawn WHITE8X8 lines, hover brightening the glyph
        -- (0.3->0.8) rather than washing the button with a highlight block.
        -- PIXEL-PERFECT: each line is EXACTLY one physical pixel thick with pixel
        -- snapping OFF (an unsnapped quad N physical px thick rasterizes exactly N
        -- rows at ANY fractional position, so lines never blur or vanish as the
        -- window moves), spacing ENTIRELY in physical pixels (1px lines, 3px gap,
        -- 4px pitch) so the glyph renders identically at every UI scale.
        local lines = {}
        local PPx = CludesUI and CludesUI.PP
        local esc = rb.GetEffectiveScale and rb:GetEffectiveScale()
        local onePx = (PPx and PPx.perfect and esc and esc > 0) and (PPx.perfect / esc) or 1
        local pitch = onePx * 4
        local wid = 18
        for idx = 1, 3 do
            local line = SolidTex(rb, "OVERLAY", 1, 1, 1, 1)
            if PPx and PPx.DisablePixelSnap then
                PPx.DisablePixelSnap(line)
            end
            line:SetAlpha(0.3)
            line:SetSize(wid, onePx)
            line:SetPoint("CENTER", rb, "CENTER", 0, pitch * (2 - idx))
            lines[idx] = line
            wid = wid - 3
        end
        rb:HookScript("OnEnter", function()
            for idx = 1, #lines do
                lines[idx]:SetAlpha(0.8)
            end
        end)
        rb:HookScript("OnLeave", function()
            for idx = 1, #lines do
                lines[idx]:SetAlpha(0.3)
            end
        end)
    end

    function LP.ApplyHistory()
        local win = _G.GroupLootHistoryFrame
        if not win or win:IsForbidden() then
            return
        end

        Skin.Shell("loothistory", win)

        local skinData = GetFFD(win)
        if skinData.histSkinned then
            LP.SkinHistoryRows(win)
            return
        end
        skinData.histSkinned = true

        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        LP.FadeKeys(win, { "Bg", "Background", "Border" })
        Skin.FadeKeyedArt(win)

        local close = win.ClosePanelButton
            or win.CloseButton
            or (win.TitleContainer and win.TitleContainer.CloseButton)
        if close then
            Skin.CloseButton(close)
        end

        local titleText = (win.TitleContainer and win.TitleContainer.TitleText) or win.TitleText
        if titleText then
            Skin.Font(titleText)
            Skin.White(titleText)
            -- Centered on the shell's top bar, not the frame: portrait template anchors the title relative to art just removed.
            if skinData.topBar and titleText.ClearAllPoints then
                titleText:ClearAllPoints()
                titleText:SetPoint("CENTER", skinData.topBar, "CENTER", 0, 0)
                if titleText.SetJustifyH then
                    titleText:SetJustifyH("CENTER")
                end
            end
        end

        if win.EncounterDropdown then
            Skin.Dropdown(win.EncounterDropdown)
        end

        -- Roll timer. Its Fill is a TEXTURE, not a status bar, so it needs the vertex-color path and has to survive the frame's own region fade.
        local timer = win.Timer
        if timer then
            local titleData = GetFFD(timer)
            local fillTex = timer.Fill
            local keepSet = fillTex and { [fillTex] = true } or nil
            Skin.FadeRegions(timer, keepSet)
            Skin.Register(timer, keepSet)
            -- No backdrop, no border: just the colored fill over the window. Bar
            -- rides the encounter dropdown's WIDTH (left/right edges pinned to it)
            -- with template height and vertical gap taken from the live layout (runs on first OnShow, so the frame is laid out).
            if not titleData.skinned then
                titleData.skinned = true
                local dropdown = win.EncounterDropdown
                if dropdown and dropdown.GetBottom and timer.GetTop then
                    local gap = 6
                    local ddBottom, tTop = dropdown:GetBottom(), timer:GetTop()
                    if ddBottom and tTop then
                        gap = ddBottom - tTop
                    end
                    local hgt = timer:GetHeight()
                    -- 2px overhang each side: the FILL is left-anchored 2px inside
                    -- the frame with a matching right-side track inset, so the
                    -- frame overhangs the dropdown by exactly that inset and the fill lands flush with its edges.
                    timer:ClearAllPoints()
                    timer:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", -2, -gap)
                    timer:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 2, -gap)
                    if hgt and hgt > 0 then
                        timer:SetHeight(hgt)
                    end
                end
            end
            if fillTex then
                titleData.fill = fillTex
                fillTex:SetTexture(LP.FLAT)
                LP.ApplyVertexFill(fillTex)
            end
        end

        -- WowTrimScrollBar, not MinimalScrollBar: trough and arrow caps live on
        -- child frames WSkin.ScrollBar never reaches, so the engine's deep-fading variant is the right primitive.
        local scrollBar = win.ScrollBar
        if scrollBar then
            if mod.ASkin and mod.ASkin.ScrollBar then
                mod.ASkin.ScrollBar(scrollBar)
            else
                Skin.ScrollBar(scrollBar)
            end
        end

        LP.SkinResizeGrip(win.ResizeButton)
        LP.SkinHistoryRows(win)
    end

    Skin.RegisterWindow({
        key = "loothistory",
        apply = function()
            LP.WhenFrameExists("GroupLootHistoryFrame", function(win)
                Skin.HookShow(win, LP.ApplyHistory)
                -- Should never be up at login, but if it is, skinning now is the
                -- same post-hoc moment the OnShow path gives.
                if win:IsShown() then
                    LP.ApplyHistory()
                end
            end)
        end,
    })

    -- Blizzard's button label is auto-sized: the box is exactly the string width,
    -- so it carries no slack. At a fractional effective scale the stored width can
    -- land a float hair UNDER the string it holds (Accept 46.499996 for a 46.5px
    -- string, Decline a clean 48.0) and WoW breaks the last glyph onto a second
    -- line. Which strings land on an unlucky value follows the typeface, not the
    -- word length, so the global font swap decides who is hit. Pinning the label to
    -- the button gives it 118px instead of 47: centered text looks identical and
    -- can no longer wrap. One-shot per label.
    function LP.PinButtonLabel(button)
        if not button or (button.IsForbidden and button:IsForbidden()) then
            return
        end
        local fontStr = button.Text or (button.GetFontString and button:GetFontString())
        if not fontStr then
            return
        end
        local skinData = GetFFD(fontStr)
        if skinData.labelPinned then
            return
        end
        skinData.labelPinned = true
        fontStr:ClearAllPoints()
        fontStr:SetPoint("LEFT", button, "LEFT", 2, 0)
        fontStr:SetPoint("RIGHT", button, "RIGHT", -2, 0)
        if fontStr.SetWordWrap then
            fontStr:SetWordWrap(false)
        end
    end

    -------------------------------------------------------------------------------
    --  Group invite popups. Two frames, one setting, because they are one thing to
    --  the player: LFGListInviteDialog (premade-group leader accepted your
    --  application: group title, activity, your role, Accept/Decline) and
    --  LFGInvitePopup (invited to a group finder party, with role checks).
    --
    --  CUI_BlizzardSkin_Dialogs.lua also skins LFGListInviteDialog, gated on
    --  CludesUIDB.reskinQueuePopup (a plain truthiness test, unlike the Queue
    --  Popup's `~= false`, so it only runs for users who toggled the option ON).
    --  When it does, it lays a flat BACKGROUND texture at sublevel 0 over this
    --  shell's backdrop (-8/-7/-6). WSkin.Shell's region fade clears it: this
    --  OnShow hook installs later so it runs second, and the older skin is one-shot.
    -------------------------------------------------------------------------------
    function LP.SkinInvite(found, roleChecks)
        if not found or found:IsForbidden() then
            return
        end
        local skinData = GetFFD(found)

        -- The role glyph ("Your Role: Damage") is a REGION OF THE DIALOG, in the
        -- same region list as the border art the shell blanket-fades, so without
        -- this it disappears with the frame. Found by INSPECTING each texture, not
        -- by key name: the holding key has moved between templates (RoleIcon/Icon/
        -- an anonymous region) and a wrong guess fails silently. Survivors are
        -- parked on two of WSkin's PROTECT_KEYS slots (caret/arrow, unused here),
        -- the engine's supported "keep this texture" list, honored by both Shell's initial fade and every later Restrip pass.
        if not skinData.caret then
            skinData.caret = found.RoleIcon or found.Icon or found.PortraitTexture
            if found.GetRegions then
                local regionList = { found:GetRegions() }
                for idx = 1, #regionList do
                    local region = regionList[idx]
                    if region and region ~= skinData.caret and region.IsObjectType and region:IsObjectType("Texture") then
                        local hay = Skin.TexHay(region)
                        if
                            hay
                            and (
                                Skin.TexIsIcon(hay)
                                or hay:find("role", 1, true)
                                or hay:find("icon", 1, true)
                            )
                        then
                            if not skinData.caret then
                                skinData.caret = region
                            elseif not skinData.arrow then
                                skinData.arrow = region
                            end
                        end
                    end
                end
            end
        end

        LP.Shell("groupinvite", found)

        if found.NineSlice then
            Skin.FadeNineSlice(found.NineSlice)
        end
        LP.FadeKeys(found, { "Bg", "BG", "Background", "Border" })
        Skin.FadeKeyedArt(found)

        for _, keyName in ipairs(LP.INVITE_BTN_KEYS) do
            local button = found[keyName]
            if button then
                Skin.Button(button)
                Skin.StateButtonLabel(button)
                LP.PinButtonLabel(button)
            end
        end
        -- Templates naming their buttons globally rather than off the frame (LFGInvitePopupAcceptButton / ...DeclineButton).
        local n = found.GetName and found:GetName()
        if n then
            for _, keyName in ipairs(LP.INVITE_BTN_KEYS) do
                local button = _G[n .. keyName]
                if button then
                    Skin.Button(button)
                    Skin.StateButtonLabel(button)
                    LP.PinButtonLabel(button)
                end
            end
        end
        -- Any 3-slice the two lists missed. Depth-capped and foreign-frame gated by the primitive itself.
        Skin.ButtonsIn(found)

        if roleChecks then
            for _, role in ipairs({ "Tank", "Healer", "DPS" }) do
                local rb = _G["LFGInvitePopupRoleButton" .. role] or found[role .. "Button"]
                local creatureBtn = rb and (rb.checkButton or rb.CheckButton)
                if creatureBtn then
                    Skin.Checkbox(creatureBtn, { borderInset = 4 })
                end
            end
        end

        -- The group's title and the inviter's name are other players' writing: a font
        -- family, set before the region walk (which keeps a string's family).
        if found.GroupName then
            Skin.FontFamily(found.GroupName)
        end
        if n and _G[n .. "Text"] then
            Skin.FontFamily(_G[n .. "Text"])
        end
        LP.FontRegions(found)
    end

    Skin.RegisterWindow({
        key = "groupinvite",
        apply = function()
            local function Wire(label, roleChecks)
                LP.WhenFrameExists(label, function(found)
                    local function applyFn()
                        LP.SkinInvite(found, roleChecks)
                    end
                    Skin.HookShow(found, applyFn)
                    if found:IsShown() then
                        applyFn()
                    end
                end)
            end
            Wire("LFGListInviteDialog", false)
            Wire("LFGInvitePopup", true)
        end,
    })

    -------------------------------------------------------------------------------
    --  Ready check. Two frames, one setting -- and the names are actively
    --  misleading, so read Blizzard_FrameXML/Mainline/ReadyCheck.xml before
    --  touching this. ReadyCheckListenerFrame is NOT a listener and NOT a response
    --  list: it is a CHILD of ReadyCheckFrame, setAllPoints to it, and it owns
    --  every visible piece of the popup -- Bg, NineSlice, TitleContainer,
    --  PortraitContainer, ReadyCheckFrameText, and both Yes/No buttons.
    --  ReadyCheckFrame itself is an empty 323x100 container with no art at all.
    --
    --  ShowReadyCheck() then does this:
    --
    --      if UnitIsUnit("player", initiator) then ReadyCheckListenerFrame:Hide()
    --      else                                    ReadyCheckListenerFrame:Show()
    --
    --  So the person who STARTED the check is shown the bare outer frame and
    --  nothing else. Anything drawn on ReadyCheckFrame is a block only they see.
    --  The shell therefore belongs on the listener, never on the outer frame.
    --
    --  The portrait is ReadyCheckPortrait, inside the listener's PortraitContainer
    --  -- one level down from the listener's own regions, so the shell's blanket
    --  region fade never reaches it and it needs no protection slot.
    --
    --  Both frames are skinned from their own OnShow, never from the login pass:
    --  a skin must never be what triggers a frame's first layout.
    -------------------------------------------------------------------------------
    LP.RC_PAD = 24 -- side padding kept clear of the message
    LP.RC_MAX_GROW = 2 -- hard ceiling: never wider than twice Blizzard's own width
    LP.RC_TEXT_Y = -30 -- message top offset (Blizzard's -37; see FitReadyCheck)
    LP.RC_BTN_GAP = 12 -- gap between Ready and Not Ready
    LP.RC_BTN_Y = 16 -- button row off the panel bottom (Blizzard's own value)

    -- Capture a region's offset from the frame's TOP anchor (center-x delta, top
    -- delta, half width) so it can be re-anchored later without guessing Blizzard's
    -- own points. The half width is what lets a GROUP of regions be re-centered
    -- from stored numbers alone, with no second measuring pass.
    -- Returns nil while the layout has no usable geometry yet -- the caller then
    -- skips this pass and captures on the next show, rather than freezing garbage.
    function LP.CaptureTopOffset(regionFrame, found)
        local rl, rr, rt = regionFrame:GetLeft(), regionFrame:GetRight(), regionFrame:GetTop()
        local fl, fRight, ft = found:GetLeft(), found:GetRight(), found:GetTop()
        if not (rl and rr and rt and fl and fRight and ft) then
            return nil
        end
        for _, val in ipairs({ rl, rr, rt, fl, fRight, ft }) do
            if issecretvalue(val) then
                return nil
            end
        end
        return ((rl + rr) / 2) - ((fl + fRight) / 2), rt - ft, (rr - rl) / 2
    end

    -- Geometry pass, run on every show and whenever the portrait is toggled.
    --
    --  1. WIDTH. Blizzard sizes this popup for a bare name, so on most realms
    --     "<name>-<realm> has initiated a ready check." wraps mid-sentence. The
    --     message is measured and the frame grown to fit it on one line -- always
    --     recomputed from the ORIGINAL width, so a long name cannot leave the popup
    --     permanently wide, and capped so a pathological one wraps instead of
    --     running off the screen.
    --  2. CENTERING, and ONLY with the portrait hidden. Blizzard insets message,
    --     title and buttons to clear the glyph; with it up that inset is load-
    --     bearing (centering the message runs it under the artwork), with it hidden
    --     it is a lopsided hole on the left. So all three keep Blizzard's own offset
    --     while the glyph is up and go dead center once it is gone.
    function LP.FitReadyCheck()
        local found = _G.ReadyCheckFrame
        if not found or found:IsForbidden() then
            return
        end
        local skinData = FFD[found]
        local fontStr = skinData and skinData.rcText
        if not fontStr then
            return
        end

        if not skinData.rcBaseW then
            local wid = found:GetWidth()
            if not wid or wid <= 0 or issecretvalue(wid) then
                return
            end
            skinData.rcBaseW = wid
        end

        if not skinData.rcTextDX then
            local dx, dy = LP.CaptureTopOffset(fontStr, found)
            if not dy then
                return
            end
            skinData.rcTextDX, skinData.rcTextDY = dx, dy
        end
        -- Own guard, not folded into the one above: a title whose geometry is not
        -- ready yet would otherwise never be captured once the message succeeded.
        -- A true offset of 0 still guards correctly -- 0 is truthy in Lua.
        if skinData.rcTitle and not skinData.rcTitleDX then
            skinData.rcTitleDX, skinData.rcTitleDY = LP.CaptureTopOffset(skinData.rcTitle, found)
        end
        local need = fontStr.GetStringWidth and fontStr:GetStringWidth()
        if not need or issecretvalue(need) then
            return
        end

        -- EVERYTHING is centered, because the portrait is gone (SkinReadyCheckList
        -- removes it). Blizzard insets the title, message and button row to the
        -- right to clear a glyph that is no longer drawn, and left alone that reads
        -- as a lopsided hole down the left side of the panel. No inset is reserved
        -- in the wrap box either -- the full width is usable now.
        local pad = LP.RC_PAD * 2
        local want = math.max(skinData.rcBaseW, math.min(need + pad, skinData.rcBaseW * LP.RC_MAX_GROW))
        -- A protected frame anchored to the popup makes it protected too, and in
        -- combat its SetWidth is then blocked: it keeps the width it has, and the
        -- message wraps inside that.
        local locked = InCombatLockdown()
        if locked then
            local p = found:IsProtected()
            locked = issecretvalue(p) or p
        end
        if locked then
            local wid = found:GetWidth()
            want = (wid and not issecretvalue(wid) and wid > 0) and wid or skinData.rcBaseW
        else
            found:SetWidth(want)
        end
        fontStr:SetWidth(want - pad)
        fontStr:ClearAllPoints()
        -- RC_TEXT_Y, not Blizzard's -37: a long "<Name>-<Realm> has initiated a
        -- ready check." wraps to TWO lines and the second one runs into the button
        -- row. The message moves UP rather than the buttons moving down -- the
        -- buttons sit RC_BTN_Y off the bottom edge and have no room to give.
        fontStr:SetPoint("TOP", found, "TOP", 0, LP.RC_TEXT_Y)

        if skinData.rcTitle and skinData.rcTitleDY then
            skinData.rcTitle:ClearAllPoints()
            skinData.rcTitle:SetPoint("TOP", found, "TOP", 0, skinData.rcTitleDY)
        end

        -- Anchored symmetrically about the panel's BOTTOM rather than replayed from
        -- Blizzard's own offsets. Blizzard puts Ready at BOTTOMRIGHT->BOTTOM x=+11
        -- and Not Ready at BOTTOMLEFT->BOTTOM x=+22, which sits the pair's midpoint
        -- ~16px right of center -- the same portrait inset the text carries, and the
        -- most visible one, because a shifted pair shows as unequal margins on each
        -- side. Half the gap from the middle each keeps the gap even AND centers the
        -- row, and it tracks the SetWidth above for free.
        local yes, no = skinData.rcBtns and skinData.rcBtns[1], skinData.rcBtns and skinData.rcBtns[2]
        if yes and no then
            local half = LP.RC_BTN_GAP / 2
            yes:ClearAllPoints()
            yes:SetPoint("BOTTOMRIGHT", found, "BOTTOM", -half, LP.RC_BTN_Y)
            no:ClearAllPoints()
            no:SetPoint("BOTTOMLEFT", found, "BOTTOM", half, LP.RC_BTN_Y)
        end
    end

    function LP.SkinReadyCheck(found)
        if not found or found:IsForbidden() then
            return
        end
        local skinData = GetFFD(found)

        -- NO SHELL ON THIS FRAME. ReadyCheckFrame is a bare 323x100 container: the
        -- background, NineSlice, TitleContainer, portrait, message and BOTH buttons
        -- are all children of ReadyCheckListenerFrame, which is setAllPoints to it.
        -- ShowReadyCheck() HIDES that child for the initiator, so Blizzard shows the
        -- person who started the check a completely artless frame. A backdrop here
        -- is therefore a black block that ONLY the initiator ever sees -- the rest
        -- of the group has the listener's own skin covering it.
        --
        -- The listener carries the shell instead (LP.SkinReadyCheckList). This stays
        -- as the fallback for a template that ever drops the child and puts the art
        -- back on the outer frame.
        if not _G.ReadyCheckListenerFrame then
            LP.Shell("readycheck", found)
        end

        if found.NineSlice then
            Skin.FadeNineSlice(found.NineSlice)
        end
        LP.FadeKeys(found, LP.ART_KEYS)
        Skin.FadeKeyedArt(found)

        -- Yes/No are UIPanelButtons named off the frame on some templates and
        -- globally (ReadyCheckFrameYesButton) on others; both paths are cheap and idempotent.
        local n = found.GetName and found:GetName()
        local btns = skinData.rcBtns or {}
        for _, keyName in ipairs({ "YesButton", "NoButton" }) do
            local button = found[keyName] or (n and _G[n .. keyName])
            if button then
                Skin.Button(button)
                Skin.StateButtonLabel(button)
                if not skinData.rcBtns then
                    btns[#btns + 1] = button
                end
            end
        end
        skinData.rcBtns = btns
        Skin.ButtonsIn(found)

        -- The message names the player who started the check: a font family, set
        -- before the region walk (which keeps a string's family).
        if n and _G[n .. "Text"] then
            Skin.FontFamily(_G[n .. "Text"])
        end
        LP.FontRegions(found)

        -- Message + title for the geometry pass below. Resolved here, where the
        -- frame is in hand, and parked on FFD so the pass itself needs no lookups.
        --
        -- The title is looked up on the LISTENER first. TitleContainer is a child
        -- of that frame, not of this one, and its TitleText is an unnamed parentKey
        -- -- so every lookup rooted at ReadyCheckFrame (fr.TitleContainer,
        -- fr.TitleText, _G.ReadyCheckFrameTitleText) misses, silently, and the
        -- title simply never gets positioned. The fr.* paths stay as the fallback
        -- for a template that moves it back out.
        local owner = _G.ReadyCheckListenerFrame or found
        skinData.rcText = skinData.rcText or (n and _G[n .. "Text"]) or found.Text
        skinData.rcTitle = skinData.rcTitle
            or (owner.TitleContainer and owner.TitleContainer.TitleText)
            or owner.TitleText
            or (found.TitleContainer and found.TitleContainer.TitleText)
            or found.TitleText
            or (n and _G[n .. "TitleText"])

        -- A second ready check started while the first is still up re-uses a SHOWN
        -- frame, so OnShow never fires and the width would keep the previous name's
        -- measurement. The message being written is the reliable signal.
        if skinData.rcText and not skinData.rcTextHooked then
            skinData.rcTextHooked = true
            for _, setter in ipairs({ "SetText", "SetFormattedText" }) do
                if skinData.rcText[setter] then
                    hooksecurefunc(skinData.rcText, setter, LP.FitReadyCheck)
                end
            end
        end

        -- Last, and after the re-font: the message is measured here, so it has to
        -- be carrying its final face and size.
        LP.FitReadyCheck()
    end

    -- The prompt's BODY, despite the name -- see the block comment above. This is
    -- the frame that actually carries the popup's art, so it is the one that gets
    -- the shell. It is shown to everyone EXCEPT the initiator, which is precisely
    -- what keeps the skin off the initiator's screen.
    function LP.SkinReadyCheckList(found)
        if not found or found:IsForbidden() then
            return
        end

        -- Keeps its title row, so no noTopBar here: the black strip is what the
        -- title then sits on (WSkin.CommonChrome re-centers it there).
        Skin.Shell("readycheck", found)

        if found.NineSlice then
            Skin.FadeNineSlice(found.NineSlice)
        end
        LP.FadeKeys(found, LP.ART_KEYS)
        Skin.FadeKeyedArt(found)

        -- Header art lives on the title container, one level down from the frame's
        -- own regions, so the shell fade never reaches it. Textures only -- the
        -- title FontString is a region of the same container.
        local tc = found.TitleContainer
        if tc then
            Skin.FadeRegions(tc)
            Skin.Register(tc, true)
            LP.FontRegions(tc)
        end

        -- Portrait REMOVED, and with no option to bring it back. Blizzard's corner
        -- portrait is a PortraitFrameTemplate device: drawn half outside the panel
        -- and relying on the ornate ring art to nest into. Once the shell strips
        -- that art the circle just floats off the left edge. Nothing is lost -- the
        -- initiator's name is already in the message text -- and FitReadyCheck
        -- centers the panel's contents on the strength of it being gone.
        Skin.RemovePortrait(found)

        -- Title and message explicitly whitened: both are GameFontNormal, so they
        -- come up Blizzard gold against the shell instead of matching every other
        -- skinned window.
        local titleText = found.TitleContainer and found.TitleContainer.TitleText
        if titleText then
            Skin.White(titleText)
        end
        local body = _G.ReadyCheckFrameText
        if body then
            Skin.White(body)
        end

        Skin.CommonChrome(found)
        -- The message (a region of this frame) names the player who started the
        -- check: its font family before the region walk.
        if body then
            Skin.FontFamily(body)
        end
        LP.FontRegions(found)

        -- The geometry pass keys off ReadyCheckFrame, and its capture needs the
        -- message laid out -- which it now is, on the frame that actually owns it.
        LP.FitReadyCheck()
    end

    Skin.RegisterWindow({
        key = "readycheck",
        apply = function()
            local function Wire(label, func)
                LP.WhenFrameExists(label, function(found)
                    local function applyFn()
                        func(found)
                    end
                    Skin.HookShow(found, applyFn)
                    -- A ready check running through a reload puts one of these on
                    -- screen before we ever see an OnShow.
                    if found:IsShown() then
                        applyFn()
                    end
                end)
            end
            Wire("ReadyCheckFrame", LP.SkinReadyCheck)
            Wire("ReadyCheckListenerFrame", LP.SkinReadyCheckList)
        end,
    })

    -------------------------------------------------------------------------------
    --  BNet toast (BNToastFrame): a friend coming online or going offline, plus
    --  broadcasts and club invites. Alert-system driven like the loot toasts, but a
    --  SINGLETON rather than a pool instance, so it takes a plain window
    --  registration instead of their pool sweep. TAINT: clicking it opens a
    --  Battle.net whisper, whose target is a SECRET string, so nothing here writes a
    --  Lua field onto the frame.
    -------------------------------------------------------------------------------
    function LP.SkinBNetToast(win)
        if not win or win:IsForbidden() then
            return
        end
        local glyphTex = win.IconTexture

        -- The Blizzard art is a BACKDROP (BACKDROP_TOAST_12_12), and
        -- BackdropTemplateMixin lays its pieces out as ordinary regions ON THE
        -- FRAME via NineSliceUtil, so the shell fade reaches them. No SetBackdrop
        -- call is needed, and none is made: that would re-enter Blizzard code.
        -- No top bar, same as the loot toast -- there is no title row to sit on.
        Skin.Shell("bnettoast", win, { noTopBar = true })

        -- The shell faded every region including the toast-type icon. Bring it
        -- back and keep it out of later restrip passes. It is NOT squared:
        -- IconTexture is a SetTexCoord crop out of one sheet, re-picked per toast
        -- type, and WSkin.SquareIcon would overwrite those coordinates.
        if glyphTex then
            glyphTex:SetAlpha(1)
            Skin.Register(win, { [glyphTex] = true })
        end

        -- Blizzard flair burst. SetAlpha(0) is not enough: the texture carries its
        -- OWN alpha animation, which drives alpha every frame and wins over our
        -- write (same shape as the loot toast art). Clear the texture instead.
        local glow = win.glow
        if glow then
            if glow.SetAtlas then
                glow:SetAtlas("")
            end
            if glow.SetTexture then
                glow:SetTexture("")
            end
            glow:SetAlpha(0)
        end

        -- Font only, never color: ShowToast recolors these per toast type (account
        -- name blue, status grey, some of it as an inline color code), and the
        -- stock colors read correctly on the dark shell. Font families: the lines
        -- show a friend's names and broadcast, in any script.
        for _, keyName in ipairs({ "TopLine", "MiddleLine", "BottomLine", "DoubleLine" }) do
            Skin.FontFamily(win[keyName])
        end

        if win.CloseButton then
            Skin.CloseButton(win.CloseButton)
        end

        -- Hover panel for a truncated broadcast. Inherits TooltipBackdropTemplate,
        -- so the house panel replaces a real tooltip backdrop.
        local tipText = win.TooltipFrame
        if tipText then
            Skin.Panel(tipText)
            if tipText.NineSlice then
                Skin.FadeNineSlice(tipText.NineSlice)
            end
            if tipText.Text then
                Skin.FontFamily(tipText.Text)
            end
        end
    end

    Skin.RegisterWindow({
        key = "bnettoast",
        apply = function()
            LP.WhenFrameExists("BNToastFrame", function(win)
                local pass = Skin.Debounce(function()
                    LP.SkinBNetToast(win)
                end)
                -- Blizzard repaints nothing on the frame between toasts, but the
                -- pass is idempotent and one debounced call per toast is cheap
                -- insurance against a future template change.
                Skin.HookShow(win, pass)
                LP.SkinBNetToast(win)
            end)
        end,
    })
end

-------------------------------------------------------------------------------
--  Queue frames, ready popups and choice windows.
--
--  Five packs sharing one block: queuestatus (the panel the LFG eye shows on
--  hover), readycheck, pvpscoreboard, delvepicker (the Delves TIER PICKER --
--  a DIFFERENT frame from the "delves" companion window further up) and
--  playerchoice (the Abundance / "how will you aid" weekly choice windows).
--
--  Helpers and constants hang off HP, inside this block's do...end (see the
--  note at the top of the file on the 200-local limit).
--
--  WIDGET TREES ARE OFF LIMITS. The delve picker's "Map Properties" row
--  (.DelveModifiersWidgetContainer) and its scenic backdrop
--  (.DelveBackgroundWidgetContainer) are UIWidgetContainerTemplate frames.
--  Widget values are SECRET inside instanced content, and an insecure write
--  anywhere in that tree resurfaces later as "attempt to compare a secret
--  number value" out of LayoutFrame when a widget set is laid out. Both
--  subtrees stay fully native, and HP.IsWidget fails CLOSED -- a probe that
--  throws counts as a widget -- so an unrecognised container is skipped rather
--  than skinned.
-------------------------------------------------------------------------------
do
    local HP = {
        FLAT = "Interface\\Buttons\\WHITE8X8",

        -- Plate / frame art living one level down from a frame's own regions,
        -- where the shell's region fade never reaches it.
        ART_KEYS = {
            "Background",
            "Bg",
            "BG",
            "Border",
            "BorderFrame",
            "Backdrop",
            "Decoration",
            "DividingLine",
            "Divider",
            "bottomArt",
            "background",
        },

        -- The scoreboard's inset is eight separately-named corner/edge tiles
        -- rather than a NineSlice, so FadeRegions cannot recognise them as a set.
        INSET_KEYS = {
            "InsetBorderTopLeft",
            "InsetBorderTopRight",
            "InsetBorderBottomLeft",
            "InsetBorderBottomRight",
            "InsetBorderTop",
            "InsetBorderBottom",
            "InsetBorderLeft",
            "InsetBorderRight",
        },

        -- Keys whose presence anywhere in a frame's parent chain marks it as part
        -- of a UI widget set. Same probe list the quest tracker's guard uses.
        WIDGET_KEYS = {
            "OnAcquireWidget",
            "widgetPools",
            "widgetSetID",
            "widgetContainer",
            "widgetType",
        },

        -- NineSlicePanelTemplate's eight EDGE pieces. Center is deliberately absent:
        -- on DialogBorderTemplate the middle is a separate tiled .Bg parchment that
        -- we keep, so fading a "center" here would blank the panel.
        NINESLICE_PIECES = {
            "TopLeftCorner",
            "TopRightCorner",
            "BottomLeftCorner",
            "BottomRightCorner",
            "TopEdge",
            "BottomEdge",
            "LeftEdge",
            "RightEdge",
        },

        -- Every ring/plate stacked on a reward tile's icon. All of these defeat a
        -- square crop: IconBorder is Blizzard's ROUNDED quality ring, the overlays
        -- are the same shape, and NameFrame is the parchment plate behind the name.
        -- One inset for every close button we own, so the X sits in the same
        -- place regardless of how far a window's rect overhangs its panel.
        -- Inset of the close button from the frame's top-right, INSIDE
        -- WSkin.AtlasBorder's drawn line. Two dials because the atlas's padding is
        -- not square: sharing one number moved the X down as far as it moved it
        -- left, and it was already sitting too low.
        --   X: larger = further LEFT (further from the right edge)
        --   Y: larger = further DOWN
        CLOSE_INSET_X = -2,
        CLOSE_INSET_Y = -3,

        REWARD_ART = {
            "IconBorder",
            "IconOverlay",
            "IconOverlay2",
            "IconBorder2",
            "NameFrame",
        },
    }

    -- Plain indexed read, passed BY ARGUMENT to pcall. The obvious spelling here is
    -- pcall(function() return t[k] end), but that allocates a fresh closure per
    -- probe -- up to 25 of them per IsWidget call, on a path that runs for every
    -- option of every choice window.
    function HP.RawGet(tbl, keyName)
        return tbl[keyName]
    end

    -- Children as a TABLE, taken ONCE, and pcall-able by argument. Never
    -- select(i, f:GetChildren()) in a loop: that rebuilds the entire vararg every
    -- iteration, which is O(n^2) and has caused a real CPU complaint here before.
    function HP.Kids(win)
        return { win:GetChildren() }
    end

    -- Same idea for REGIONS, and it is the only way to reach art that Blizzard
    -- declared inline with no name and no parentKey -- the trade window's enchant
    -- glyph being the case that forced it. pcall-able by argument for the usual
    -- reason: a field access on a forbidden or widget-backed frame can throw.
    function HP.Regions(win)
        return { win:GetRegions() }
    end

    -- Fail-CLOSED widget test: walks up to `depth` parents looking for any widget
    -- marker. Every read is pcall'd because a widget frame fed secret data can
    -- throw from an ordinary field access, and a probe that THROWS counts as a
    -- widget. Cheap: the chains here are 3-5 deep and each pass is per-show.
    function HP.IsWidget(widget, nestDepth)
        local current, hops = widget, 0
        while current and hops <= (nestDepth or 5) do
            for idx = 1, #HP.WIDGET_KEYS do
                local success, val = pcall(HP.RawGet, current, HP.WIDGET_KEYS[idx])
                if not success then
                    return true
                end
                if val ~= nil then
                    return true
                end
            end
            local ok2, parent = pcall(current.GetParent, current)
            if not ok2 then
                return true
            end
            current = parent
            hops = hops + 1
        end
        return false
    end

    -- Popup/window shell. Idempotent: Shell re-runs its region fade every call but
    -- builds its textures once, so re-calling doubles as repaint catch-up.
    function HP.Shell(winKey, widget, options)
        if not widget or widget:IsForbidden() then
            return
        end
        Skin.Shell(winKey, widget, options)
    end

    -- Alpha a list of named art keys. TEXTURES ONLY, and the type test is
    -- load-bearing: several of these names are a Texture on one template and a
    -- FRAME on another ("Border" is a NineSlice on portrait windows), and
    -- SetAlpha(0) on a frame takes its whole subtree with it.
    function HP.FadeKeys(widget, keyList)
        if not widget then
            return
        end
        for idx = 1, #keyList do
            local part = widget[keyList[idx]]
            if part and part.IsObjectType then
                if part:IsObjectType("Texture") then
                    part:SetAlpha(0)
                elseif part.TopEdge or part.TopLeftCorner then
                    Skin.FadeNineSlice(part)
                end
            end
        end
    end

    -- Re-font a frame's own FontString regions. `white` also forces the color;
    -- without it the existing color is kept (quality/faction coloring is content).
    function HP.FontRegions(widget, white)
        if not widget or not widget.GetRegions then
            return
        end
        local regionList = { widget:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region.IsObjectType and region:IsObjectType("FontString") then
                if white then
                    Skin.White(region)
                else
                    Skin.Font(region)
                end
            end
        end
    end

    -- Run fn(frame) as soon as a named Blizzard frame exists: immediately if it
    -- already does, otherwise on the ADDON_LOADED that creates it. Which of these
    -- dialogs are base UI vs load-on-demand has moved between expansions, so none
    -- is assumed present at login.
    function HP.WhenFrameExists(label, func)
        if _G[label] then
            func(_G[label])
            return
        end
        local eventFrame = CreateFrame("Frame")
        eventFrame:RegisterEvent("ADDON_LOADED")
        eventFrame:SetScript("OnEvent", function(self)
            local found = _G[label]
            if found then
                self:UnregisterAllEvents()
                func(found)
            end
        end)
    end

    -- Skin again on each re-show. One debounced pass per frame, early-outing while
    -- hidden so a hide/show burst costs nothing.
    --
    -- Deliberately does NOT run fn() itself: every caller already makes one
    -- explicit pass before wiring this up, and running it here too made the first
    -- pass happen TWICE for every window (caught by the header-row GetChildren
    -- counter, which saw two walks for one apply).
    function HP.OnShow(widget, func)
        if not widget then
            return
        end
        local skinData = GetFFD(widget)
        if skinData.hpShow then
            return
        end
        skinData.hpShow = true
        widget:HookScript(
            "OnShow",
            Skin.Debounce(function()
                if widget:IsVisible() then
                    func()
                end
            end)
        )
    end

    -- Post-hook a mixin method on a frame instance, once.
    function HP.HookMethod(widget, method, func)
        if not widget or type(widget[method]) ~= "function" then
            return false
        end
        local skinData = GetFFD(widget)
        skinData.hpHooks = skinData.hpHooks or {}
        if skinData.hpHooks[method] then
            return true
        end
        skinData.hpHooks[method] = true
        hooksecurefunc(widget, method, func)
        return true
    end

    -- Any StatusBar -> flat fill in the user's bar-fill color over a near-black
    -- trough. Re-asserted every pass: Blizzard re-applies a bar's own art on reuse.
    function HP.Bar(barFrame)
        if not barFrame or barFrame:IsForbidden() or not barFrame.SetStatusBarTexture then
            return
        end
        local skinData = GetFFD(barFrame)
        barFrame:SetStatusBarTexture(HP.FLAT)
        local fillTex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
        if fillTex and fillTex ~= skinData.fill then
            skinData.fill = fillTex
            -- GetRegions() on a StatusBar includes the fill, so an unguarded
            -- FadeRegions blanks the very thing we just installed.
            Skin.FadeRegions(barFrame, { [fillTex] = true })
            Skin.Register(barFrame, { [fillTex] = true })
        end
        if not skinData.bg then
            local bgTex = SolidTex(barFrame, "BACKGROUND", 0, 0, 0, 0.55)
            bgTex:SetAllPoints(barFrame)
            skinData.bg = bgTex
        end
        Skin.ApplyBarFill(barFrame)
    end

    -- Close button: skinned AND re-anchored to one house position.
    --
    -- Blizzard anchors each window's X to that window's own rect, and those rects
    -- overhang the VISIBLE panel by different amounts per frame (PlayerChoice pins
    -- it at a bare TOPRIGHT, the delve picker insets it), so the X lands a
    -- different distance from the panel edge in every window. Re-anchoring to a
    -- fixed inset is what makes them agree.
    --
    -- One-shot per button: Blizzard re-runs its own SetPoint on some layouts, but
    -- re-applying every pass would fight a window that legitimately moves its X.
    function HP.CloseButton(widget, btnFrame)
        if not widget or not btnFrame or btnFrame:IsForbidden() then
            return
        end
        Skin.CloseButton(btnFrame)
        -- Blizzard's close button carries its own .Border texture, which survives
        -- WSkin.CloseButton and rings the X with leftover frame art. Confirmed by a
        -- /framestack over the X: PlayerChoiceFrame.CloseButton.Border drawing at
        -- level 510, right under the cursor. Cleared, not alpha'd -- these buttons
        -- get re-textured per texture kit.
        for _, keyName in ipairs({ "Border", "BorderArt", "Background", "Bg" }) do
            local part = btnFrame[keyName]
            if part and part.IsObjectType and part:IsObjectType("Texture") then
                if part.SetAtlas then
                    part:SetAtlas("")
                end
                if part.SetTexture then
                    part:SetTexture("")
                end
                part:SetAlpha(0)
            end
        end

        -- Pin to the FRAME's TOPRIGHT at +3,+3 on every PlayerChoice layout.
        --
        -- Two /framestacks settled this. The 4-option window anchors its X at
        -- TOPRIGHT +3,+3 and looks right; the 3-option window anchors the SAME
        -- button to the SAME point at -9,-9 and sits wrong. Blizzard varies the
        -- OFFSET per layout, not the reference -- so the frame was always the
        -- correct thing to anchor to, and copying the good layout's numbers is what
        -- makes them agree.
        --
        -- Two earlier attempts failed for instructive reasons, both recorded so
        -- they are not retried: a flat -4,-4 off the frame (wrong constant, put the
        -- X off the panel), and anchoring to NineSlice (that layout HAS no
        -- NineSlice -- it uses BorderOverlay -- so the re-anchor silently skipped
        -- and Blizzard's -9,-9 stood).
        -- Inset inside OUR OWN atlas border.
        --
        -- A /framestack on the panel's visible corner named it: the border there is
        -- WSkin.AtlasBorder's AdventureMap_TopBorder texture, anchored 0,0 to the
        -- frame rect. So the panel edge IS the frame edge -- the drawn line just
        -- sits inside the atlas's transparent padding. Every Blizzard frame chased
        -- before this (NineSlice, BorderOverlay, the frame at Blizzard's own
        -- offsets) was irrelevant, because none of them draws that corner.
        --
        -- CLOSE_INSET_X/Y are the tunables: how far in from the frame the atlas's
        -- line falls on each axis. -4 was tried and left the X outside the line.
        -- RE-ASSERTED EVERY PASS, not one-shot. PlayerChoiceFrame re-anchors its
        -- own close button during setup, so a single application at skin time is
        -- silently overwritten and the X never moves at all -- which is exactly the
        -- symptom: not "wrong offset", but "no change whatsoever". Pass() runs on
        -- show and on both SetupOptions paths, i.e. precisely when Blizzard
        -- re-lays it out.
        if btnFrame.SetPoint then
            btnFrame:ClearAllPoints()
            btnFrame:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -HP.CLOSE_INSET_X, -HP.CLOSE_INSET_Y)
        end
    end

    -- Button + label, with Blizzard's own frame art removed FIRST.
    --
    -- WSkin.Button strips the old Left/Middle/Right texture trio, but modern
    -- UIPanelButtonTemplate draws its frame as a NINESLICE instead -- which
    -- survives, so the house border lands on top of Blizzard's and every button
    -- reads as double-bordered. Fading the NineSlice is what makes it single.
    function HP.Button(button)
        if not button or button:IsForbidden() then
            return
        end
        -- ONCE PER BUTTON. SkinChoiceOption reaches the same button by two routes
        -- (the OptionButtonsContainer child walk AND the named-key loop), and each
        -- skin pass lays another border -- which is the actual double border, not
        -- Blizzard's art surviving.
        local skinData = GetFFD(button)
        if skinData.hpButton then
            return
        end
        skinData.hpButton = true
        -- UIPanelButtonTemplate frames itself with Left/Middle/Right textures
        -- (UI-Panel-Button-Up), NOT a NineSlice. Cleared explicitly so a stray
        -- reapply cannot bring Blizzard's frame back under ours.
        for _, keyName in ipairs({ "Left", "Middle", "Right" }) do
            local part = button[keyName]
            if part and part.SetTexture then
                if part.SetAtlas then
                    part:SetAtlas("")
                end
                part:SetTexture("")
                part:SetAlpha(0)
            end
        end
        if button.NineSlice then
            Skin.FadeNineSlice(button.NineSlice)
        end
        Skin.Button(button)
        Skin.WhiteButtonLabel(button)
    end

    -- Square an icon and give it the house border. Masked icons are left native by
    -- WSkin.SquareIcon itself (SetTexCoord on a masked texture is a hard error).
    --
    -- Pass a parent ONLY for item icons. Atlas glyph art (role icons, faction
    -- marks) must not come through here at all: SetTexCoord fights the atlas's own
    -- coordinates, and the border boxes empty slots.
    function HP.Icon(glyphTex, parent)
        if not glyphTex then
            return
        end
        Skin.SquareIcon(glyphTex, parent or glyphTex:GetParent())
    end

    -- One reward tile: square the icon, strip every ring stacked on it, and put
    -- the rarity back as a SQUARE border.
    --
    -- Keeping .IconBorder was a deliberate call at first, on the grounds that it
    -- carries item QUALITY -- and it was wrong. It is a ROUNDED ring, so it is
    -- exactly the "border" that kept coming back in screenshot after screenshot,
    -- and it defeats the square crop underneath it. NameFrame (the parchment
    -- plate) goes for the same reason.
    --
    -- Dropping the rarity cue ENTIRELY was the follow-on call, and that was wrong
    -- too (reversed 2026-08-14 on maintainer request): "quality still reads from the
    -- tooltip" meant hovering every tile to see what mattered. The ring stays
    -- stripped, but it is now the SOURCE the square border reads its color from,
    -- so the rarity is back without the rounded art coming with it.
    function HP.SkinRewardTile(btnFrame)
        if not btnFrame then
            return
        end
        for idx = 1, #HP.REWARD_ART do
            local part = btnFrame[HP.REWARD_ART[idx]]
            if part and part.SetAlpha and part.IsObjectType and part:IsObjectType("Texture") then
                part:SetAlpha(0)
            end
        end
        if btnFrame.Name and btnFrame.Name.SetTextColor then
            btnFrame.Name:SetTextColor(1, 1, 1)
        end
        Skin.SquareIcon(btnFrame.Icon, btnFrame, true)
    end

    -- Square the icons of a ScrollBox's currently-materialised rows.
    --
    -- NO border is added and Blizzard's is stripped: passing a parent to SquareIcon
    -- draws an CUI border, and .IconBorder is a rounded quality ring. Between them
    -- that is two borders on something that was asked to be a square icon.
    --
    -- ForEachFrame is the ScrollBox's own API for "the rows that exist right now".
    -- Preferred over walking children because a WowScrollBoxList keeps its rows
    -- under a ScrollTarget child, so GetChildren on the box returns the scaffolding
    -- rather than the rows.
    function HP.SquareRewards(scrollBar)
        if not scrollBar then
            return
        end
        local function Square(row)
            if row and row.Icon then
                HP.SkinRewardTile(row)
            end
        end
        if
            type(scrollBar.ForEachFrame) == "function" and pcall(scrollBar.ForEachFrame, scrollBar, Square)
        then
            return
        end
        local okKids, kids = pcall(HP.Kids, scrollBar)
        if not okKids then
            return
        end
        for idx = 1, #kids do
            local childFrame = kids[idx]
            if childFrame and childFrame.Icon then
                Square(childFrame)
            elseif childFrame then
                -- One level deeper: the ScrollTarget holding the pooled rows.
                local okInner, inner = pcall(HP.Kids, childFrame)
                if okInner then
                    for jdx = 1, #inner do
                        Square(inner[jdx])
                    end
                end
            end
        end
    end

    -------------------------------------------------------------------------------
    --  Queue status panel (QueueStatusFrame): what the minimap LFG eye shows on
    --  hover. Inherits TooltipBackdropTemplate, so the shell replaces a genuine
    --  tooltip backdrop rather than a window frame.
    --
    --  Entries are POOLED (statusEntriesPool of QueueStatusEntryTemplate) and
    --  rebuilt by QueueStatusFrameMixin:Update, so the skin hangs off that hook
    --  and walks only the ACTIVE entries -- typically one or two.
    -------------------------------------------------------------------------------
    -- Role icons are left FULLY NATIVE. They are ATLAS textures
    -- (UI-LFG-RoleIcon-Generic), so the square-icon treatment was wrong twice over:
    -- SetTexCoord fights the atlas's own coordinates, and the house border it draws
    -- boxed every role glyph -- including ones with no art for the current queue
    -- type, which showed up as an empty square floating in the panel corner.
    -- Only the COUNT gets house text.
    function HP.SkinRoleCount(rc)
        if not rc then
            return
        end
        if rc.Count then
            Skin.White(rc.Count)
        end
    end

    function HP.SkinQueueEntry(record)
        if not record or record:IsForbidden() then
            return
        end
        -- Title stays accent-colored by Blizzard for eligibility state; the rest
        -- goes white so the panel reads as one block of house text. The title can
        -- be a premade group's name: a font family.
        if record.Title then
            Skin.FontFamily(record.Title)
        end
        for _, keyName in ipairs({ "Status", "SubTitle", "TimeInQueue", "AverageWait", "ExtraText" }) do
            local fontStr = record[keyName]
            if fontStr then
                Skin.White(fontStr)
            end
        end
        -- RoleIcon1/2/3 are deliberately untouched, same reason as SkinRoleCount:
        -- atlas art, and bordering them boxes empty slots.
        for _, keyName in ipairs({ "TanksFound", "HealersFound", "DamagersFound" }) do
            HP.SkinRoleCount(record[keyName])
        end
        -- Assigned spec badge: Blizzard draws it as a circle (CircleMask) inside a
        -- minimap tracking border. The mask makes SetTexCoord illegal, so the icon
        -- is left native and only the brass border goes.
        local specInfo = record.AssignedSpec
        if specInfo and specInfo.Border then
            specInfo.Border:SetAlpha(0)
        end
        -- Separator between stacked entries -> thin house rule.
        local sep = record.EntrySeparator
        if sep and sep.SetColorTexture then
            sep:SetColorTexture(1, 1, 1, 0.12)
            if sep.SetAtlas then
                sep:SetAtlas("")
            end
        end
    end

    function HP.ApplyQueueStatus()
        local win = _G.QueueStatusFrame
        if not win or win:IsForbidden() then
            return
        end
        HP.Shell("queuestatus", win, { noTopBar = true })
        if win.NineSlice then
            Skin.FadeNineSlice(win.NineSlice)
        end
        HP.FadeKeys(win, HP.ART_KEYS)

        local function Pass()
            local pool = win.statusEntriesPool
            if not (pool and pool.EnumerateActive) then
                return
            end
            local success, iter = pcall(pool.EnumerateActive, pool)
            if not success or not iter then
                return
            end
            for record in iter do
                HP.SkinQueueEntry(record)
            end
        end
        Pass()
        -- Update rebuilds the entry list; it is the only thing that changes what
        -- is on screen, so nothing else needs polling.
        HP.HookMethod(
            win,
            "Update",
            Skin.Debounce(function()
                if win:IsVisible() then
                    Pass()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "queuestatus",
        addons = { Blizzard_QueueStatusFrame = true },
        apply = function()
            HP.WhenFrameExists("QueueStatusFrame", function()
                HP.ApplyQueueStatus()
            end)
        end,
    })

    -------------------------------------------------------------------------------
    --  Delves difficulty picker (DelvesDifficultyPickerFrame,
    --  Blizzard_DelvesDifficultyPicker): the tier picker with the reward list.
    --
    --  NOT the "delves" pack further up -- that one is the companion
    --  configuration window in Blizzard_DelvesCompanionConfiguration.
    --
    --  The "Map Properties" icon row and the scenic backdrop are
    --  UIWidgetContainerTemplate frames. They are named here only to be SKIPPED;
    --  nothing in this function may write into either subtree.
    -------------------------------------------------------------------------------
    function HP.ApplyDelvePicker()
        local win = _G.DelvesDifficultyPickerFrame
        if not win or win:IsForbidden() then
            return
        end

        local function Pass()
            -- FOUR TARGETED CHANGES, by maintainer call. The full window shell was
            -- built, shown to him and REJECTED, so there is deliberately no
            -- HP.Shell, no region fade and no font pass here: Blizzard's
            -- background, title, scenario label, description, scenic art, reward
            -- text and challenge grid all stay exactly as shipped.
            --   1. ornate dialog border -> CUI's window border
            --   2. close button        -> CUI's X
            --   3. tier dropdown + Enter button
            --   4. "Chance to receive" icons squared
            -- Resist re-adding anything else here; the restraint IS the request.

            -- DialogBorderTemplate is a NineSlicePanelTemplate plus a tiled .Bg
            -- parchment. Only the eight border PIECES are faded, never the Border
            -- FRAME itself: WSkin.FadeNineSlice alphas the container too, which
            -- would take .Bg with it and leave the panel see-through.
            local brd = win.Border
            if brd then
                for idx = 1, #HP.NINESLICE_PIECES do
                    local part = brd[HP.NINESLICE_PIECES[idx]]
                    if part and part.SetAlpha then
                        part:SetAlpha(0)
                    end
                end
                Skin.AtlasBorder(win)
            end
            HP.CloseButton(win, win.CloseButton)

            if win.Dropdown then
                Skin.Dropdown(win.Dropdown)
            end
            if win.EnterDelveButton then
                HP.Button(win.EnterDelveButton)
            end

            local rc = win.DelveRewardsContainerFrame
            if rc and not HP.IsWidget(rc, 2) then
                HP.SquareRewards(rc.ScrollBox)
            end
            -- .DelveModifiersWidgetContainer / .DelveBackgroundWidgetContainer:
            -- deliberately untouched, see the block header.
        end

        Pass()
        HP.OnShow(win, Pass)
        -- Switching tier re-lays the reward list.
        HP.HookMethod(
            win,
            "CheckAndSetDisplayMode",
            Skin.Debounce(function()
                if win:IsVisible() then
                    Pass()
                end
            end)
        )
        -- Scrolling ACQUIRES fresh row frames from the pool, so squaring only on
        -- show would leave anything scrolled into view uncropped.
        local rc0 = win.DelveRewardsContainerFrame
        if rc0 and rc0.ScrollBox then
            HP.HookMethod(
                rc0.ScrollBox,
                "Update",
                Skin.Debounce(function()
                    if win:IsVisible() then
                        HP.SquareRewards(rc0.ScrollBox)
                    end
                end)
            )
        end
    end

    Skin.RegisterWindow({
        key = "delvepicker",
        addons = { Blizzard_DelvesDifficultyPicker = true },
        apply = function()
            HP.WhenFrameExists("DelvesDifficultyPickerFrame", function()
                HP.ApplyDelvePicker()
            end)
        end,
    })

    -------------------------------------------------------------------------------
    --  Player choice windows (PlayerChoiceFrame, Blizzard_PlayerChoice): the
    --  Abundance harvest picker and the weekly "how will you aid ..." windows are
    --  the same frame with two different option layouts --
    --  PlayerChoiceNormalOptionTemplate (columns) and
    --  PlayerChoiceNormalOptionGridTemplate (the grid variant).
    --
    --  Blizzard drives this frame's art from a TEXTURE KIT chosen per choice, so
    --  every option is re-textured on each SetupOptions pass and a one-shot skin
    --  would survive exactly one window. Both setup paths are hooked.
    --
    --  Option ARTWORK (the scene image on each card) is content and stays; only
    --  the parchment plate, header and button chrome are replaced.
    -------------------------------------------------------------------------------
    -- The reputation / progress bars on a choice option ("Friendly", "Revered" on
    -- the weekly cartel picker) are UI WIDGETS: PlayerChoiceBaseOptionTemplate owns
    -- a .WidgetContainer inheriting UIWidgetContainerTemplate, and each option calls
    -- RegisterForWidgetSet on it. They can NEVER be skinned in place -- that is the
    -- secret-value rule, and it is why HP.IsWidget already refuses to descend into
    -- them. Instead they are handed to the HUD cover system, which draws an
    -- CUI-owned bar anchored over Blizzard's without writing to it.
    --
    -- Handed over rather than discovered: the cover system's own sweep only walks
    -- UIParent's direct children, and these containers are two levels inside a
    -- window.
    function HP.AdoptOptionWidgets(opt)
        local adopt = CludesUI._HUDWidgetAdopt
        if type(adopt) ~= "function" then
            return
        end
        for _, keyName in ipairs({ "WidgetContainer" }) do
            local okC, wc = pcall(HP.RawGet, opt, keyName)
            if okC and wc then
                adopt(wc)
            end
        end
    end

    function HP.SkinChoiceOption(opt)
        if not opt then
            return
        end
        -- BEFORE the widget test: this option's own frame is ordinary, only its
        -- WidgetContainer child is a widget tree, and the container is exactly what
        -- we want to register.
        HP.AdoptOptionWidgets(opt)
        -- IsWidget FIRST, before any unguarded call on the frame. Every read it
        -- makes is pcall'd, so a frame whose field access throws is classified as a
        -- widget and skipped; calling opt:IsForbidden() ahead of it would throw on
        -- that same frame and take the whole pass down with it.
        if HP.IsWidget(opt, 2) then
            return
        end
        local okF, forbidden = pcall(opt.IsForbidden, opt)
        if not okF or forbidden then
            return
        end
        HP.FadeKeys(opt, HP.ART_KEYS)
        if opt.NineSlice then
            Skin.FadeNineSlice(opt.NineSlice)
        end

        -- Header plate + title.
        local heading = opt.Header
        if heading then
            HP.FadeKeys(heading, HP.ART_KEYS)
            if heading.Text then
                Skin.White(heading.Text)
            end
            HP.FontRegions(heading, true)
        end
        if opt.OptionText then
            Skin.White(opt.OptionText)
        end
        if opt.Title then
            Skin.White(opt.Title)
        end

        -- Body text frames keep Blizzard's inline coloring (the requirement lines
        -- are red/green on purpose), so re-font without recoloring.
        local tf = opt.OptionButtonsContainer or opt.Text
        if tf then
            HP.FontRegions(tf)
        end

        -- Choice buttons ("Harvest", "Choose Quest", ...).
        -- The container's children are WRAPPER frames, not the buttons: the real
        -- one is a level deeper at <wrapper>.Button. A /framestack over a
        -- "Work for ..." button showed
        -- OptionButtonsContainer.<wrapper>.Button.Middle still drawing, because a
        -- walk that only tested the wrappers for GetObjectType()=="Button" found
        -- nothing and skinned nothing. What looked like a double border was
        -- Blizzard's own button art, never touched.
        local bc = opt.OptionButtonsContainer
        if bc and bc.GetChildren then
            local kids = { bc:GetChildren() }
            for idx = 1, #kids do
                local wid = kids[idx]
                if wid then
                    if wid.GetObjectType and wid:GetObjectType() == "Button" then
                        HP.Button(wid)
                    end
                    local okB, inner = pcall(HP.RawGet, wid, "Button")
                    if okB and inner and inner.GetObjectType and inner:GetObjectType() == "Button" then
                        HP.Button(inner)
                    end
                end
            end
        end
        for _, keyName in ipairs({ "OptionButton", "Button", "ConfirmationButton" }) do
            local button = opt[keyName]
            if button and button.GetObjectType and button:GetObjectType() == "Button" then
                HP.Button(button)
            end
        end

        -- Reward icons (item / currency rows under each option).
        local rewards = opt.Rewards or opt.RewardsFrame
        if rewards and rewards.GetChildren then
            local kids = { rewards:GetChildren() }
            for idx = 1, #kids do
                local region = kids[idx]
                if region and not region:IsForbidden() then
                    HP.Icon(region.Icon, region)
                    if region.Name then
                        Skin.Font(region.Name)
                    end
                end
            end
        end
    end

    function HP.ApplyPlayerChoice()
        local win = _G.PlayerChoiceFrame
        if not win or win:IsForbidden() then
            return
        end

        local function Pass()
            HP.Shell("playerchoice", win)
            HP.FadeKeys(win, HP.ART_KEYS)
            if win.NineSlice then
                Skin.FadeNineSlice(win.NineSlice)
            end
            -- Close button: skinned AND re-stripped every pass. PlayerChoice drives
            -- its art from a per-choice TEXTURE KIT, so Blizzard re-applies the
            -- button's own textures when the window is set up -- a one-shot skin
            -- gets painted over on the next choice. The Border key is a separate
            -- frame on UIPanelCloseButton and survives a plain region fade.
            HP.CloseButton(win, win.CloseButton)
            if win.Title then
                Skin.White(win.Title)
            end
            if win.Header then
                HP.FadeKeys(win.Header, HP.ART_KEYS)
                HP.FontRegions(win.Header, true)
            end
            -- PlayerChoiceFrame owns a WidgetContainer of its own, above the
            -- options; same cover treatment as the per-option ones.
            HP.AdoptOptionWidgets(win)

            -- Options come from `optionPools`, a FramePoolCollection -- NOT a
            -- parentArray. The first build looked for f.Options and then fell back
            -- to walking children for an .OptionButtonsContainer key that does not
            -- exist, so it found NOTHING: no option was ever skinned and, worse, no
            -- option WidgetContainer was ever handed to the cover system, which is
            -- why the reputation bars stayed stock.
            local pools = win.optionPools
            local done = false
            if pools then
                -- EnumerateActive covers every pool in the collection, so both the
                -- column and grid option templates are picked up in one pass.
                if type(pools.EnumerateActive) == "function" then
                    local okE, iter = pcall(pools.EnumerateActive, pools)
                    if okE and iter then
                        for opt in iter do
                            HP.SkinChoiceOption(opt)
                        end
                        done = true
                    end
                end
                if
                    not done
                    and type(pools.EnumerateActiveByTemplate) == "function"
                    and win.optionFrameTemplate
                then
                    local okT, iter2 = pcall(pools.EnumerateActiveByTemplate, pools, win.optionFrameTemplate)
                    if okT and iter2 then
                        for opt in iter2 do
                            HP.SkinChoiceOption(opt)
                        end
                        done = true
                    end
                end
            end
            if not done and win.GetChildren then
                -- Last resort: an option is any child carrying a WidgetContainer.
                local kids = { win:GetChildren() }
                for idx = 1, #kids do
                    local childFrame = kids[idx]
                    local okW, wc = pcall(HP.RawGet, childFrame, "WidgetContainer")
                    if okW and wc then
                        HP.SkinChoiceOption(childFrame)
                    end
                end
            end
        end

        Pass()
        HP.OnShow(win, Pass)
        -- Both layout paths re-texture every option from the texture kit, so both
        -- must re-skin. Debounced: SetupOptions and AlignOptionHeights can fire
        -- several times for one window.
        local restrip = Skin.Debounce(function()
            if win:IsVisible() then
                Pass()
            end
        end)
        HP.HookMethod(win, "SetupOptions", restrip)
        HP.HookMethod(win, "SetupOptionsAsGrid", restrip)
        HP.HookMethod(win, "SetupFrame", restrip)
    end

    Skin.RegisterWindow({
        key = "playerchoice",
        addons = { Blizzard_PlayerChoice = true },
        apply = function()
            HP.WhenFrameExists("PlayerChoiceFrame", function()
                HP.ApplyPlayerChoice()
            end)
        end,
    })

    -------------------------------------------------------------------------------
    --  Stack split popup (StackSplitFrame): the quantity box that opens over the
    --  merchant window on a shift-click / right-click buy.
    --
    --  Registered under the MERCHANT key rather than one of its own -- it is the
    --  merchant window's own popup as far as the user is concerned, and a second
    --  registration on an existing key is the same shape charsheet and
    --  professionsbook already use.
    --
    --  Blizzard swaps between two BACKGROUND textures depending on whether the item
    --  is sold singly or in bundles (SingleItem vs MultiItem, chosen in ChooseFrameType), and
    --  re-shows whichever it picked on each open. Both are faded every pass rather
    --  than once, or the first multi-digit split brings the brass money-frame art
    --  back on a window that has already been skinned.
    -------------------------------------------------------------------------------
    function HP.ApplyStackSplit()
        local win = _G.StackSplitFrame
        if not win or win:IsForbidden() then
            return
        end

        local function Pass()
            HP.Shell("merchant", win, { noTopBar = true })
            HP.FadeKeys(win, HP.ART_KEYS)
            if win.SingleItemSplitBackground then
                win.SingleItemSplitBackground:SetAlpha(0)
            end
            if win.MultiItemSplitBackground then
                win.MultiItemSplitBackground:SetAlpha(0)
            end
            if win.NineSlice then
                Skin.FadeNineSlice(win.NineSlice)
            end

            -- GIVE THE COUNT ITS FIELD BACK.
            --
            -- StackSplitFrame has NO EditBox -- the count is a FontString and the
            -- frame takes digits through enableKeyboard/OnKeyDown. What made it
            -- READ as a typeable field in Blizzard's version was
            -- SingleItemSplitBackground, the money-frame plate behind the number,
            -- and this pack fades that (correctly -- it is stock art). Fading it
            -- without replacing it left the count floating between two arrows with
            -- nothing to say it accepts input.
            --
            -- So the plate comes back in the house style: flat panel + 1px edge,
            -- sized to the text rather than to the old art, which was far wider
            -- than the number it framed.
            if win.StackSplitText and win.LeftButton and win.RightButton then
                local skinData = GetFFD(win)
                if not skinData.splitField then
                    -- SPANS THE GAP BETWEEN THE ARROWS, not the text.
                    --
                    -- Anchoring to StackSplitText gave a box that hugged the digit:
                    -- the string is justifyH="RIGHT" and anchored to the frame's
                    -- RIGHT at x=-50, so its rect is narrow and sits off-centre
                    -- (right edge lands at CENTER+36 while the arrows are at
                    -- CENTER-59 and CENTER+64). A field has to be the whole gap.
                    --
                    -- Anchored to the BUTTONS rather than hardcoding those offsets,
                    -- so it still fits if Blizzard moves them, and the LEFT/RIGHT
                    -- anchors centre it vertically on the arrow row for free.
                    -- SEARCH-BOX LOOK, matched to WSkin.EditBox: a near-black
                    -- 0.02 fill under the THEMED grey border, not the flat black
                    -- edge the item tiles use. Black reads as an outline drawn
                    -- round a number; the grey edge is what makes a rectangle look
                    -- like something you can type into. Aesthetic only -- the frame
                    -- already takes digits through enableKeyboard, so there is no
                    -- EditBox to build.
                    local bgTex = win:CreateTexture(nil, "BACKGROUND", nil, -6)
                    bgTex:SetColorTexture(0.02, 0.02, 0.02, 1)
                    bgTex:SetPoint("LEFT", win.LeftButton, "RIGHT", 5, 0)
                    bgTex:SetPoint("RIGHT", win.RightButton, "LEFT", -5, 0)
                    bgTex:SetHeight(22)
                    skinData.splitField = bgTex
                    Skin.QualityBorder(win, bgTex, Theme.brdR or 0.2, Theme.brdG or 0.2, Theme.brdB or 0.2)

                    if win.StackSplitText.SetJustifyH then
                        win.StackSplitText:SetJustifyH("CENTER")
                    end
                end
                -- A bundle shows two lines, the stacks over the total; Blizzard's
                -- anchors for them already straddle the arrow row. A single count
                -- goes in the MIDDLE of the field: stock right-justifies it against
                -- an offset that only made sense with the old money-frame plate, and
                -- ChooseFrameType puts that anchor back on every open.
                if win.isMultiStack then
                    skinData.splitField:SetHeight(44)
                else
                    skinData.splitField:SetHeight(22)
                    win.StackSplitText:ClearAllPoints()
                    win.StackSplitText:SetPoint("CENTER", skinData.splitField, "CENTER", 0, 0)
                end
            end

            if win.StackSplitText then
                Skin.White(win.StackSplitText)
            end
            if win.StackItemCountText then
                Skin.White(win.StackItemCountText)
            end
            for _, keyName in ipairs({ "OkayButton", "CancelButton" }) do
                local button = win[keyName]
                if button then
                    HP.Button(button)
                end
            end
            -- The two arrows are plain Buttons carrying Normal/Pushed/Disabled
            -- money-frame textures rather than a template, so WSkin.Button has
            -- nothing to strip. Recolor the art in place: white at rest, dimmed
            -- when disabled, which keeps the disabled state readable.
            for _, keyName in ipairs({ "LeftButton", "RightButton" }) do
                local button = win[keyName]
                if button then
                    for _, getter in ipairs({
                        "GetNormalTexture",
                        "GetPushedTexture",
                        "GetDisabledTexture",
                        "GetHighlightTexture",
                    }) do
                        local part = button[getter] and button[getter](button)
                        if part and part.SetVertexColor then
                            part:SetVertexColor(1, 1, 1)
                        end
                    end
                    local dis = button.GetDisabledTexture and button:GetDisabledTexture()
                    if dis and dis.SetVertexColor then
                        dis:SetVertexColor(0.4, 0.4, 0.4)
                    end
                end
            end
        end

        Pass()
        -- Every open runs ChooseFrameType (both clients open the box only through
        -- OpenStackSplitFrame), and so does a shift-click on another item while the
        -- box is up, which fires no OnShow. It swaps the two backdrops, resizes the
        -- frame and re-anchors the count, so the pass follows it, one frame later.
        HP.HookMethod(
            win,
            "ChooseFrameType",
            Skin.Debounce(function()
                if win:IsVisible() then
                    Pass()
                end
            end)
        )
    end

    Skin.RegisterWindow({
        key = "merchant",
        apply = function()
            HP.WhenFrameExists("StackSplitFrame", function()
                HP.ApplyStackSplit()
            end)
        end,
    })

    -------------------------------------------------------------------------------
    --  Trade window (TradeFrame).
    --
    --  A ButtonFrameTemplate window of two mirrored halves -- theirs on the left,
    --  yours on the right -- each with 6 item slots plus one ENCHANT slot, its own
    --  insets, and a money row. Yours is editable (MoneyInputFrameTemplate, three
    --  edit boxes); theirs is read-only.
    --
    --  BOTH PORTRAITS GO, as on every other window pack. Two are in play:
    --    - TradeFrame's ButtonFrameTemplate CORNER portrait is removed as always.
    --      It is drawn half outside the panel and floats free once the frame art
    --      is gone.
    --    - TradeFrame.RecipientOverlay.portrait -- the trade partner's face -- is
    --      removed by HP.TradeHidePortrait. Blizzard anchors that overlay above
    --      the frame's top edge and lets its metal corner atlas bridge the
    --      overhang, so with the atlas gone there is nowhere for it to sit that
    --      does not read as pasted onto the title row; the partner's name is
    --      already in the header.
    -------------------------------------------------------------------------------

    -- Frame art that is NOT reachable through the shell's own region fade: the
    -- divider between the two halves and the recipient's tinted backdrop are
    -- globals parented to TradeFrame, not regions of it.
    -- THE CURRENCY ROW: STRIP BLIZZARD'S SURROUND, ADD NOTHING.
    --
    -- Two different things got conflated when this was "stripped" the first time:
    --   - DRAWING an CUI box on the row -- that was the reskin attempt, it is gone
    --     and stays gone;
    --   - FADING Blizzard's own surround (the money insets and the gold-edged
    --     recipient box) -- that is just stray chrome removal, and pulling it out
    --     left an outlined panel and a gold box sitting on a dark window.
    -- The second is back. The three g/s/c boxes keep their bevels because they are
    -- forbidden and genuinely cannot be touched; everything AROUND them can be,
    -- and is.

    -- Frame art that is NOT reachable through the shell's own region fade: the
    -- divider between the two halves and the recipient's tinted backdrop are
    -- globals parented to TradeFrame, not regions of it.
    HP.TRADE_EDGE = {
        "TradeRecipientBotLeftCorner",
        "TradeRecipientLeftBorder",
        "TradeRecipientBG",
        -- Named in a /framestack over the live window, not in the source dump's
        -- layout: the frame's own backdrop, still drawn under everything.
        "TradeFrameBg",
        -- The recipient's money surround, a ThinGoldEdgeTemplate FRAME (not a
        -- texture). Pulled out with the currency work and that was wrong: it is
        -- not part of skinning the row, it is a gold-edged box sitting on a dark
        -- panel, and dropping it put Blizzard's gold outline back on the top
        -- right. Fading the frame is safe -- it holds the edge art only, and the
        -- money AMOUNT lives in TradeRecipientMoneyFrame, a sibling.
        "TradeRecipientMoneyBg",
    }

    -- Hoisted rather than written inline in the pass: both of these run on EVERY
    -- window open, and a table literal in the loop header builds a fresh table
    -- each time for no reason.
    HP.TRADE_TEXTS = {
        -- The two names first: HP.TradeTexts gives them font families
        "TradeFramePlayerNameText",
        "TradeFrameRecipientNameText",
        "TradeFramePlayerEnchantText",
        "TradeFrameRecipientEnchantText",
    }
    HP.TRADE_PORTRAIT_KEYS = { "portrait", "portraitFrame" }

    HP.TRADE_INSETS = {
        -- ButtonFrameTemplate's own panel. Its bottom edge sits at y=+26, right
        -- above the Trade/Cancel row, and it is what drew the stray line across
        -- the bottom of the window -- it is `$parentInset` on the TEMPLATE, so it
        -- is not in the Trade* naming scheme and was missed on the first pass.
        "TradeFrameInset",
        "TradeRecipientItemsInset",
        "TradeRecipientEnchantInset",
        "TradePlayerItemsInset",
        "TradePlayerEnchantInset",
        -- The money surrounds. Their ART is faded like every other inset; nothing
        -- is DRAWN in their place -- that is the line between removing Blizzard's
        -- chrome and reskinning a row that cannot be reskinned.
        "TradePlayerInputMoneyInset",
        "TradeRecipientMoneyInset",
    }

    -- A flat dark panel with a 1px black edge, built once per host and anchored to
    -- `region`. The house look for a BOX -- the same weight as a squared icon's
    -- edge, which is what these name plates were asked to match.
    function HP.TradeBox(owner, regionFrame, inset)
        if not owner or not regionFrame then
            return
        end
        -- IsForbidden on BOTH, and it is not belt-and-braces. This CREATES a
        -- texture on `host` and anchors it to `region`, and either call THROWS on a
        -- forbidden object rather than no-opping. The pack is pcall-isolated at the
        -- window level, so one throw here takes out every remaining step of the
        -- pass -- the buttons, the close button and the portrait all run after the
        -- money row -- and the result reads as a half-skinned window rather than an
        -- obvious failure. That is exactly how this shipped broken once.
        --
        -- WSkin.EditBox, which this replaced for the money row, carries the same
        -- guard and was quietly skipping the object; dropping to a raw
        -- CreateTexture is what turned a silent skip into an error.
        if owner.IsForbidden and owner:IsForbidden() then
            return
        end
        if regionFrame.IsForbidden and regionFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(owner)
        if not skinData.tradeBox then
            local bgTex = owner:CreateTexture(nil, "BACKGROUND", nil, -6)
            bgTex:SetColorTexture(0.04, 0.04, 0.04, 0.9)
            skinData.tradeBox = bgTex
        end
        local idx = inset or 0
        skinData.tradeBox:ClearAllPoints()
        skinData.tradeBox:SetPoint("TOPLEFT", regionFrame, "TOPLEFT", idx, -idx)
        skinData.tradeBox:SetPoint("BOTTOMRIGHT", regionFrame, "BOTTOMRIGHT", -idx, idx)
        -- Explicit BLACK through the quality helper: it is the 1px pixel-snapped
        -- edge, and unlike BorderRegion it hands back a frame so the box can be
        -- re-anchored or hidden later.
        Skin.QualityBorder(owner, skinData.tradeBox, 0, 0, 0)
    end

    -- One trade slot: an empty-slot backdrop, a NAME PLATE, a name string and a
    -- standard ItemButton.
    function HP.SkinTradeSlot(slot)
        if not slot or slot:IsForbidden() then
            return
        end
        local n = slot.GetName and slot:GetName()
        -- The 64x64 empty-slot socket art, faded: with the panel's own frame art
        -- gone it reads as a stray bevel behind a square icon.
        local st = slot.SlotTexture or (n and _G[n .. "SlotTexture"])
        if st and st.SetAlpha then
            st:SetAlpha(0)
        end

        -- THE NAME PLATE. UI-QuestItemNameFrame, 124x64 of rounded parchment art
        -- around a 37px row -- most of what still read as Blizzard on this window,
        -- because it has NO parentKey and is only reachable as $parentNameFrame.
        -- Replaced with the same flat box + 1px edge the icons carry.
        local nameFrame = n and _G[n .. "NameFrame"]
        -- Guarded HERE, where it is first touched. SkinTradeSlot alphas this before
        -- handing it to TradeBox, so a forbidden plate throws on the SetAlpha and
        -- takes the remaining slots with it -- TradeBox's own guard never gets a
        -- look in.
        if nameFrame and nameFrame.IsForbidden and nameFrame:IsForbidden() then
            nameFrame = nil
        end
        if nameFrame then
            nameFrame:SetAlpha(0)
            -- Inset vertically: the art is 64 tall around a 37px row, so tracking
            -- its rect exactly would draw a box half again as tall as the slot.
            HP.TradeBox(slot, nameFrame, 14)
        end

        -- Name keeps Blizzard's item-quality COLOR -- that is content, not chrome.
        local nameFS = slot.Name or (n and _G[n .. "Name"])
        if nameFS then
            Skin.Font(nameFS)
        end

        -- THE ENCHANT GLYPH. Slot 7 on each side carries an extra texture that has
        -- NO NAME and NO parentKey -- a bare 62x62 UI-TradeFrame-EnchantIcon
        -- declared inline on TradeRecipientItem7/TradePlayerItem7 -- so no
        -- key-based sweep can ever reach it. At 62px over a 37px slot it hangs well
        -- outside the squared box and is the reason the enchant rows read as chunky
        -- next to the clean slots above.
        --
        -- Found by walking the slot's REGIONS, which is the only way to see an
        -- anonymous one, and everything we own is spared by object identity rather
        -- than by name. The row keeps its "Will not be traded" caption, so nothing
        -- is lost by dropping the glyph.
        local skinData = GetFFD(slot)
        local okR, regs = pcall(HP.Regions, slot)
        if okR and regs then
            for idx = 1, #regs do
                local region = regs[idx]
                if
                    region
                    and region ~= skinData.tradeBox
                    and region.IsObjectType
                    and region:IsObjectType("Texture")
                    and region.SetAlpha
                    and not (region.IsForbidden and region:IsForbidden())
                then
                    region:SetAlpha(0)
                end
            end
        end

        local btnFrame = slot.ItemButton or (n and _G[n .. "ItemButton"])
        -- true: square icon plus the square RARITY border, the same call the
        -- merchant grid makes. Reused rather than reimplemented -- this is a
        -- file-scope local declared far above, so it is in scope here.
        if btnFrame then
            SkinMailItemButton(btnFrame, true)
        end
    end

    -- REMOVED ENTIRELY, on request, after several rounds of trying to make it sit
    -- well. Both portraits on this window now go:
    --   - TradeFrame's ButtonFrameTemplate CORNER portrait, via WSkin.RemovePortrait
    --     in the shell phase, as on every other window;
    --   - TradeFrame.RecipientOverlay, the trade partner's face, here.
    --
    -- Blizzard anchors that overlay 7px ABOVE the frame's top edge and lets its
    -- metal corner atlas bridge the overhang, so with the atlas gone there is
    -- nowhere for it to sit that does not read as pasted onto the title row. The
    -- name is already in the header; the picture was not earning its place.
    --
    -- ALPHA, never Hide: house rule is that Blizzard frames are not shown or
    -- hidden, only made invisible.
    function HP.TradeHidePortrait()
        local win = _G.TradeFrame
        local shade = win and win.RecipientOverlay
        if not shade or (shade.IsForbidden and shade:IsForbidden()) then
            return
        end
        for _, keyName in ipairs(HP.TRADE_PORTRAIT_KEYS) do
            local part = shade[keyName]
            if part and part.SetAlpha and not (part.IsForbidden and part:IsForbidden()) then
                part:SetAlpha(0)
            end
        end
    end

    function HP.ApplyTrade()
        local win = _G.TradeFrame
        if not win or win:IsForbidden() then
            return
        end

        -- PHASE-ISOLATED, and this window earned it. The engine pcalls each WINDOW,
        -- so one throw anywhere in a pass takes out every step after it -- which
        -- happened twice in two rounds here, both times a FORBIDDEN object (every
        -- method on one throws), and both times the symptom was a half-skinned
        -- window with nothing obvious to point at rather than a clean failure.
        --
        -- Each phase below runs in its own pcall, so a bad object costs THAT phase
        -- and nothing after it. Built ONCE and kept in FFD: the pass re-runs on
        -- every window open, and rebuilding the closures each time is needless
        -- churn.
        local fieldData = GetFFD(win)
        if not fieldData.tradePhases then
            fieldData.tradeFailed = {}
            fieldData.tradePhases = {
                function()
                    HP.Shell("trade", win)
                    -- The metal frame. NineSlice is a CHILD FRAME, not a region,
                    -- so the shell's region fade never reaches it -- a /framestack
                    -- over the live window found it still drawing
                    -- !UI-Frame-Metal-EdgeLeft at level 500, on top of everything.
                    if win.NineSlice then
                        Skin.FadeNineSlice(win.NineSlice)
                    end
                    -- The CORNER portrait only. The recipient's is its own phase
                    -- and is deliberately not part of this.
                    Skin.RemovePortrait(win)
                    if win.TitleContainer then
                        HP.FontRegions(win.TitleContainer, true)
                    end
                end,
                function()
                    HP.TradeEdges()
                end,
                function()
                    HP.TradeSlots()
                end,
                function()
                    HP.TradeTexts()
                end,
                function()
                    HP.Button(_G.TradeFrameTradeButton)
                    HP.Button(_G.TradeFrameCancelButton)
                    HP.CloseButton(win, win.CloseButton or _G.TradeFrameCloseButton)
                end,
                function()
                    HP.TradeHidePortrait()
                end,
                -- Behavior, not chrome, but it rides the phase list for the
                -- same crash isolation. No-op after its first run.
                function()
                    HP.TradeAlertFix()
                end,
            }
        end

        local function Pass()
            local ph, failed = fieldData.tradePhases, fieldData.tradeFailed
            for idx = 1, #ph do
                local success, err = pcall(ph[idx])
                -- Reported ONCE per phase. A forbidden object stays forbidden, and
                -- an error thrown on every window open is spam rather than a
                -- diagnostic -- but swallowing it entirely would hide a real bug,
                -- so the first one still goes through the normal error handler.
                if not success and err and not failed[idx] then
                    failed[idx] = true
                    geterrorhandler()(err)
                end
            end
        end

        Pass()
        -- Re-run on show: the slots are repopulated per trade, and Blizzard
        -- re-textures an ItemButton every time its slot changes hands.
        HP.OnShow(win, Pass)
    end

    function HP.TradeEdges()
        for idx = 1, #HP.TRADE_EDGE do
            local part = _G[HP.TRADE_EDGE[idx]]
            -- Per-ITEM guard, not just per-phase. One forbidden texture must
            -- not stop the rest of the list -- phase isolation would still
            -- leave the other three pieces of divider art up.
            if part and part.SetAlpha and not (part.IsForbidden and part:IsForbidden()) then
                part:SetAlpha(0)
            end
        end
        for idx = 1, #HP.TRADE_INSETS do
            local ins = _G[HP.TRADE_INSETS[idx]]
            if ins then
                Skin.Inset(ins)
            end
        end
    end

    -- 7 slots a side: 6 items and the enchant slot, which is slot 7 on both halves
    -- rather than a separately named frame.
    function HP.TradeSlots()
        for idx = 1, 7 do
            HP.SkinTradeSlot(_G["TradePlayerItem" .. idx])
            HP.SkinTradeSlot(_G["TradeRecipientItem" .. idx])
        end
    end

    -- THE CHANGE GLOW FOLLOWS THE ITEM. A drag between trade slots is a REMOVE
    -- then an ADD (OnDragStart and OnReceiveDrag both call ClickTradeButton), so
    -- two slots change and TradeFrame_AlertItemIfChanged lights the wrong one:
    -- the emptied slot alerts, and the filled one stays silent while its itemKey
    -- is nil -- Blizzard skips a slot's first item, and the enchant slot behind
    -- "Will not be traded" is almost always in that state. Latched per side: a
    -- slot going empty arms its side, the next slot on that side to gain an item
    -- consumes the latch. side -> the Alert frame left glowing on the empty slot.
    HP.tradeVacated = {}

    -- Named so the state above can be dropped between trades. Slot 7 is the
    -- enchant slot on both halves.
    HP.TRADE_ALERT_BUTTONS = {}
    for idx = 1, 7 do
        HP.TRADE_ALERT_BUTTONS[#HP.TRADE_ALERT_BUTTONS + 1] = "TradePlayerItem" .. idx .. "ItemButton"
        HP.TRADE_ALERT_BUTTONS[#HP.TRADE_ALERT_BUTTONS + 1] = "TradeRecipientItem" .. idx .. "ItemButton"
    end

    -- Stop() alone lands the alpha at 0 only if the group is still running;
    -- zeroing it too covers a stop between steps, which is when this is called.
    function HP.TradeAlertStop(alert)
        if not alert or (alert.IsForbidden and alert:IsForbidden()) then
            return
        end
        if alert.ItemIconAlertAnim then
            alert.ItemIconAlertAnim:Stop()
        end
        if alert.LoopFlipbook then
            alert.LoopFlipbook:SetAlpha(0)
        end
    end

    -- Which half a button is on, read off its name: the two halves use otherwise
    -- identical templates and share this one alert function, and a partner
    -- rearranging their offer must not steal the glow off yours.
    function HP.TradeButtonSide(btnFrame)
        local n = btnFrame and btnFrame.GetName and btnFrame:GetName()
        if not n then
            return
        end
        if n:find("TradePlayerItem", 1, true) == 1 then
            return "player"
        end
        if n:find("TradeRecipientItem", 1, true) == 1 then
            return "recipient"
        end
    end

    -- Only a MOVE is redirected: an item that leaves the offer for good never gets
    -- its latch consumed, so its removal glow survives. That is a CHANGE warning,
    -- not the accept state (TradeHighlightPlayer/Recipient, left stock below).
    -- Blizzard's oldItemKey is gone by the time a post-hook runs, hence the shadow
    -- flag -- which also makes a button's FIRST sighting quiet, so a /reload
    -- mid-trade initializes instead of alerting on all fourteen slots.
    function HP.OnTradeItemAlert(btnFrame, itemId)
        if not btnFrame or (btnFrame.IsForbidden and btnFrame:IsForbidden()) then
            return
        end
        local side = HP.TradeButtonSide(btnFrame)
        if not side then
            return
        end
        local skinData = GetFFD(btnFrame)
        local had = skinData.tradeHadItem
        -- Blizzard's own emptiness test: an empty slot reports 0, not nil.
        local has = (itemId or 0) > 0
        skinData.tradeHadItem = has
        if had and not has then
            HP.tradeVacated[side] = btnFrame.Alert
        elseif has and not had then
            local source = HP.tradeVacated[side]
            if not source then
                return
            end
            HP.tradeVacated[side] = nil
            -- Source first: dropping an item back where it came from makes src and
            -- the destination the same frame, so the restart has to win.
            HP.TradeAlertStop(source)
            local alert = btnFrame.Alert
            if alert and alert.ItemIconAlertAnim and not (alert.IsForbidden and alert:IsForbidden()) then
                alert.ItemIconAlertAnim:Restart()
            end
        end
    end

    -- Dropped with the window. A trade cancelled with items still in its slots
    -- would otherwise leave them flagged as filled, and the next trade's first
    -- update would read as an emptying and arm the latch against nothing.
    function HP.TradeAlertReset()
        wipe(HP.tradeVacated)
        for idx = 1, #HP.TRADE_ALERT_BUTTONS do
            local btnFrame = _G[HP.TRADE_ALERT_BUTTONS[idx]]
            if btnFrame then
                GetFFD(btnFrame).tradeHadItem = nil
            end
        end
    end

    -- Once per session, from the pack because this window has no other owner.
    function HP.TradeAlertFix()
        if HP.tradeAlertHooked then
            return
        end
        if type(_G.TradeFrame_AlertItemIfChanged) ~= "function" then
            return
        end
        HP.tradeAlertHooked = true
        hooksecurefunc("TradeFrame_AlertItemIfChanged", function(btnFrame, itemId)
            -- Inside Blizzard's event handler: a throw would surface as an error
            -- in their update, not ours.
            pcall(HP.OnTradeItemAlert, btnFrame, itemId)
        end)
        local win = _G.TradeFrame
        if win and not win:IsForbidden() then
            win:HookScript("OnHide", function()
                pcall(HP.TradeAlertReset)
            end)
        end
    end

    -- Both player names and both "Will not be traded" enchant captions. White,
    -- because they sit on the panel rather than on an item.
    -- The two names take font families (a player's name, in any script).
    function HP.TradeTexts()
        for idx, n in ipairs(HP.TRADE_TEXTS) do
            local fontStr = _G[n]
            if fontStr then
                if idx <= 2 then
                    Skin.FontFamily(fontStr)
                else
                    Skin.Font(fontStr)
                end
                Skin.White(fontStr)
            end
        end
    end

    -- THE CURRENCY ROW IS LEFT ENTIRELY ALONE -- there is no HP.TradeMoney.
    --
    -- Nothing in it can be touched. Settled with /cuitrade against the live client
    -- after five rounds:
    --
    --   TradePlayerInputMoneyFrame            FORBIDDEN
    --   TradePlayerInputMoneyFrameGold        FORBIDDEN
    --   TradePlayerInputMoneyFrameGoldMiddle  FORBIDDEN  <- the bevel ART itself
    --   TradeFramePlayerInputMoneyFrame*      MISSING
    --
    -- Every method on a forbidden object throws, so the frame, the three edit boxes
    -- and the textures drawing their bevels are all out of reach. The
    -- `TradeFramePlayerInputMoneyFrame...` names read off a /framestack are not
    -- globals at all, which is what most of those rounds were chasing.
    --
    -- The inset behind the row was the one reachable object, and boxing it just put
    -- an CUI border around three Blizzard boxes -- rejected on sight. It still gets
    -- its art faded via HP.TRADE_INSETS like every other inset, and that is all.
    --
    -- Do not try again unless /cuitrade starts reporting something reachable.

    -- THE ACCEPT HIGHLIGHT IS LEFT ENTIRELY ALONE.
    --
    -- Two attempts, both worse than stock. Squaring it to a 1px outline lost the
    -- green wash that IS the signal; replacing the wash with a flat fill across the
    -- highlight frame tinted the whole column, because these frames sit ABOVE the
    -- item slots -- so the green landed on top of every slot instead of framing the
    -- area the way Blizzard's edge glow does.
    --
    -- It is a transient state indicator that was already legible, and it is the one
    -- thing on this window that has to read instantly. Left stock deliberately: do
    -- not re-skin it without a way to see the result first.

    Skin.RegisterWindow({
        key = "trade",
        apply = function()
            HP.WhenFrameExists("TradeFrame", function()
                HP.ApplyTrade()
            end)
        end,
    })

    -------------------------------------------------------------------------------
    --  NO SECURE TRANSFER DIALOG PACK -- it cannot be skinned.
    --
    --  "Are you sure you want to accept this trade?" (SecureTransferDialog) looks
    --  ordinary in a /framestack, but Blizzard_SecureTransferUI.toc carries
    --  `## UseSecureEnvironment: 1`, so every frame that addon creates is FORBIDDEN
    --  to other addons -- same mechanism as ForbiddenNamePlate. A pack was written
    --  for it and did precisely nothing: the standard `f:IsForbidden()` guard at
    --  the top returned immediately, silently, with no error and nothing in the
    --  frame stack to show for it.
    --
    --  CHECK THE .TOC FIRST. `UseSecureEnvironment: 1` is visible before a line of
    --  code is written and settles the question outright -- cheaper than a
    --  framestack, and far cheaper than a pack plus an options card.
    -------------------------------------------------------------------------------
end

-------------------------------------------------------------------------------
--  Battleground flag carriers (ArenaEnemyMatchFrame1..5, Blizzard_Deprecated_
--  ArenaUI): Blizzard's old arena frames, which now show only in battlegrounds,
--  for the carriers of flags and orbs. Each one is a SECURE unit button in a
--  right-side MANAGED column, so this pack is visual-only: no script hook on
--  the buttons or their container (code run in their show path would leave
--  the managed-layout pass under our taint), and never a Show, Hide, SetPoint
--  or SetSize on a frame of theirs. Built once at login. Moving the column is
--  the Shifter's (an Unlock Mode mover written in the restricted environment).
--
--  Dressed as the house unit frames are: the bar pair flat inside one 1px
--  black border with a 1px line at the bars' seam, health in the carrier's
--  class colour and power in its power colour (both from the Colors page),
--  and the spec icon square at the bars' end in place of Blizzard's class
--  circle and round badge (both at alpha 0). Blizzard paints the health bar
--  its default green on every value change and update and the power bar its
--  type's colour on every power update; ours goes back on after those writes
--  only, so the grey of a carrier out of sight or offline stays. In instanced
--  PvP the class token is secret: it goes to C_ClassColor and the colour to
--  SetStatusBarColor, both of which take secrets, and is never compared.
--
--  Kept as Blizzard draws them: the faction icon, the cast bar's fill (its
--  atlas carries the cast type, uninterruptible included, and that type is
--  secret in combat) and the heal prediction segments.
-------------------------------------------------------------------------------
do
    local FC = {
        FLAT = "Interface\\Buttons\\WHITE8X8",
        -- Blizzard's frame art, the black wash behind its bars, the class circle
        -- and the spec icon's badge and ring.
        ART = { "Texture", "Background", "ClassPortrait", "SpecPortrait", "SpecBorder" },
        BAR_TEXTS = {
            "HealthBarText",
            "HealthBarTextLeft",
            "HealthBarTextRight",
            "ManaBarText",
            "ManaBarTextLeft",
            "ManaBarTextRight",
        },
    }

    -- ok, r, g, b: unit's class colour from the Colors page, or Blizzard's shade
    -- of it while the class token is secret. ok is plain; r, g, b may be secret,
    -- so they only ever go to a setter.
    function FC.ClassRGB(unitToken)
        local _, token = UnitClass(unitToken)
        if type(token) ~= "string" then
            return false
        end
        if not issecretvalue(token) then
            local color = CludesUI.GetClassColor(token)
            return true, color.r, color.g, color.b
        end
        local success, red, green, blue = CludesUI.GetClassColorForRestrictedUnit(unitToken, token)
        if success then
            return true, red, green, blue
        end
        local color = C_ClassColor.GetClassColor(token)
        if color then
            return true, color.r, color.g, color.b
        end
        return false
    end

    -- Every colour write on a health bar of ours: Blizzard's default green is
    -- taken over by the class colour, any other write is kept.
    function FC.HealthColor(barFrame, red, green, blue)
        local skinData = FFD[barFrame]
        if not skinData or skinData.fcPaint then
            return
        end
        if issecretvalue(red) or issecretvalue(green) or issecretvalue(blue) then
            return
        end
        if red ~= 0 or green ~= 1 or blue ~= 0 then
            return
        end
        local success, cr, cg, creatureBtn = FC.ClassRGB(skinData.fcUnit)
        if not success then
            return
        end
        skinData.fcPaint = true
        barFrame:SetStatusBarColor(cr, cg, creatureBtn)
        skinData.fcPaint = false
    end

    -- The pre-10.0 power-type update these frames still use puts Blizzard's bar
    -- texture back on every call, and the type's colour (white under the atlas
    -- some types draw with). A power bar of ours goes flat again after it, in the
    -- power colour from the Colors page, or the colour the atlas carried for a
    -- type the page has none for.
    function FC.ManaType(barFrame)
        local skinData = barFrame and FFD[barFrame]
        if not (skinData and skinData.fcMana) then
            return
        end
        barFrame:SetStatusBarTexture(FC.FLAT)
        if barFrame.lockColor then
            return
        end
        local token = barFrame.powerToken
        if type(token) ~= "string" or issecretvalue(token) then
            return
        end
        local color = CludesUI.GetPowerColor(token)
        if not color then
            color = PowerBarColor and PowerBarColor[token]
            if not (color and color.atlas) then
                return
            end
        end
        barFrame:SetStatusBarColor(color.r, color.g, color.b)
    end

    -- A bar of ours: flat fill. unit is the class colour's source for a health
    -- bar (a pet's is its owner); nil marks the power bar.
    function FC.Bar(barFrame, unitToken)
        if not barFrame or barFrame:IsForbidden() then
            return
        end
        local skinData = GetFFD(barFrame)
        if skinData.fcBar then
            return
        end
        skinData.fcBar = true
        if not unitToken then
            skinData.fcMana = true
            FC.ManaType(barFrame)
            return
        end
        skinData.fcUnit = unitToken
        barFrame:SetStatusBarTexture(FC.FLAT)
        hooksecurefunc(barFrame, "SetStatusBarColor", FC.HealthColor)
        FC.HealthColor(barFrame, barFrame:GetStatusBarColor())
    end

    -- The frame round a bar pair: a backing of ours under the bars at the
    -- button's own level (the house fill for the CludesUI style, the Modern
    -- colour for Modern; the shell registry swaps them live), and on a frame of
    -- ours above the bars a 1px black border over their outer pixel. seam: the
    -- bars touch, so a 1px line marks where.
    function FC.Frame(ownerFrame, top, bottom, seam)
        local skinData = GetFFD(ownerFrame)
        if skinData.fcEdge then
            return skinData.fcEdge
        end
        local Pix = CludesUI.PP
        local back = CreateFrame("Frame", nil, ownerFrame)
        back:SetPoint("TOPLEFT", top, "TOPLEFT")
        back:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT")
        back:SetFrameLevel(ownerFrame:GetFrameLevel())
        local bgTex = SolidTex(back, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA, -8)
        bgTex:SetAllPoints(back)
        Skin.AdoptShell("flagcarrier", back, bgTex)
        local edge = CreateFrame("Frame", nil, ownerFrame)
        edge:SetAllPoints(back)
        edge:SetFrameLevel(math.max(top:GetFrameLevel(), bottom:GetFrameLevel()) + 1)
        Pix.CreateBorder(edge, 0, 0, 0, 1, 1, "OVERLAY", 7)
        if seam then
            local line = CreateFrame("Frame", nil, edge)
            line:SetAllPoints(bottom)
            Pix.CreateBorder(line, 0, 0, 0, 1, 1, "OVERLAY", 7)
            local c = Pix.GetBorders(line)
            if c then
                c._hideBottom, c._hideLeft, c._hideRight = true, true, true
                Pix.SetBorderSize(line, 1)
            end
        end
        skinData.fcEdge = edge
        return edge
    end

    -- The spec icon, square and joined to the bar pair's right edge, following
    -- Blizzard's spec texture (now at alpha 0) whatever writes it: a carrier with
    -- no spec shows none.
    function FC.PaintSpec(tabBox, texture, file)
        if type(file) == "nil" then
            tabBox:Hide()
            return
        end
        texture:SetTexture(file)
        tabBox:Show()
    end

    function FC.SpecIcon(ownerFrame, edge, specInfo, size)
        local skinData = GetFFD(ownerFrame)
        if skinData.fcSpec then
            return
        end
        local Pix = CludesUI.PP
        local tabBox = CreateFrame("Frame", nil, ownerFrame)
        tabBox:SetSize(size, size)
        tabBox:SetPoint("TOPLEFT", edge, "TOPRIGHT")
        tabBox:SetFrameLevel(edge:GetFrameLevel())
        local texture = tabBox:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints(tabBox)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- The bar pair's right edge is the icon's left one.
        Pix.CreateBorder(tabBox, 0, 0, 0, 1, 1, "OVERLAY", 7)
        local c = Pix.GetBorders(tabBox)
        if c then
            c._hideLeft = true
            Pix.SetBorderSize(tabBox, 1)
        end
        skinData.fcSpec = tabBox
        hooksecurefunc(specInfo, "SetTexture", function(_, file)
            FC.PaintSpec(tabBox, texture, file)
        end)
        FC.PaintSpec(tabBox, texture, specInfo:GetTexture())
    end

    -- The trinket slot shows all the time, often empty: its icon is cropped
    -- square, and its border shows only while Blizzard has an icon in it. The
    -- border sits over the slot's cooldown swipe.
    function FC.Trinket(cc)
        if not (cc and cc.Icon) then
            return
        end
        local skinData = GetFFD(cc)
        if skinData.fcEdge then
            return
        end
        Skin.SquareIcon(cc.Icon)
        local edge = CreateFrame("Frame", nil, cc)
        edge:SetAllPoints(cc)
        edge:SetFrameLevel(cc:GetFrameLevel() + 3)
        CludesUI.PP.CreateBorder(edge, 0, 0, 0, 1, 1, "OVERLAY", 7)
        skinData.fcEdge = edge
        hooksecurefunc(cc.Icon, "SetTexture", function(_, file)
            edge:SetShown(type(file) ~= "nil")
        end)
        edge:SetShown(type(cc.Icon:GetTexture()) ~= "nil")
    end

    function FC.SkinPet(pet, unitToken)
        if not pet or pet:IsForbidden() then
            return
        end
        local label = pet:GetName()
        if not label then
            return
        end
        local art = _G[label .. "Texture"]
        if art then
            art:SetAlpha(0)
        end
        local hb, mb = _G[label .. "HealthBar"], _G[label .. "ManaBar"]
        FC.Bar(hb, unitToken)
        FC.Bar(mb)
        -- A gap parts the pet's bars already.
        if hb and mb then
            FC.Frame(pet, hb, mb)
        end
    end

    function FC.SkinFrame(win)
        if not win or win:IsForbidden() then
            return
        end
        local label = win:GetName()
        local skinData = GetFFD(win)
        if not label or skinData.fcSkinned then
            return
        end
        skinData.fcSkinned = true
        local unitToken = "arena" .. win:GetID()

        for _, suffix in ipairs(FC.ART) do
            local part = _G[label .. suffix]
            if part then
                part:SetAlpha(0)
            end
        end
        local hb, mb = _G[label .. "HealthBar"], _G[label .. "ManaBar"]
        FC.Bar(hb, unitToken)
        FC.Bar(mb)
        if hb and mb then
            local edge = FC.Frame(win, hb, mb, true)
            local specInfo = _G[label .. "SpecPortrait"]
            if specInfo then
                FC.SpecIcon(win, edge, specInfo, hb:GetHeight() + mb:GetHeight())
            end
        end

        -- Name white like the windows' titles; the bar texts keep their color. A
        -- player's name, in any script: a font family.
        local nameFS = _G[label .. "Name"]
        if nameFS then
            Skin.FontFamily(nameFS)
            Skin.White(nameFS)
        end
        for _, suffix in ipairs(FC.BAR_TEXTS) do
            Skin.Font(_G[label .. suffix])
        end

        FC.Trinket(win.CC)
        local cast = win.CastingBar
        if cast and not cast:IsForbidden() then
            CludesUI.PP.CreateBorder(cast, 0, 0, 0, 1, 1, "OVERLAY", 7)
            if cast.Icon then
                Skin.SquareIcon(cast.Icon, cast)
            end
            if cast.Text then
                Skin.Font(cast.Text)
            end
        end

        FC.SkinPet(win.petFrame, unitToken)
    end

    function FC.Apply()
        for idx = 1, (MAX_ARENA_ENEMIES or 5) do
            FC.SkinFrame(_G["ArenaEnemyMatchFrame" .. idx])
        end
        if not FC.hooked and UnitFrameManaBar_UpdateTypeOld then
            FC.hooked = true
            hooksecurefunc("UnitFrameManaBar_UpdateTypeOld", FC.ManaType)
        end
    end

    Skin.RegisterWindow({
        key = "flagcarrier",
        -- Loaded with the game on both clients; a client without it never runs the pack.
        addons = { Blizzard_Deprecated_ArenaUI = true },
        apply = FC.Apply,
    })
end
