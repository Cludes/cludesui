if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBlizzardSkin_GroupFinder.lua
--  Dark, minimal reskin of Blizzard's Group Finder window (PVEFrame): Dungeon
--  Finder, Premade Groups (LFGList), Raid Finder, and the Mythic+ panel, themed
--  to match the rest of CludesUI (CharacterSheet / Bags house style).
--
--  Scope: this file owns the PVEFrame WINDOW and everything docked inside it
--  (shell, bottom tabs, left category rail, the LFD / RaidFinder / LFGList /
--  Challenges panels and their widgets). Transient floating popups (the ready
--  dialog, the premade invite/application dialogs, the role-check popup) are
--  owned by the separate "Reskin Queue Popup" feature and are NOT touched here.
--
--  Taint / secret-value safety (read before editing):
--   - All per-frame skin state lives in an EXTERNAL weak-keyed table (FFD), never
--     as custom keys on Blizzard frame tables. (CLAUDE.md hard rule.)
--   - Visual-only: we SetAlpha(0) native textures and lay our own layers under
--     them. We NEVER Hide/Show/SetParent a Blizzard frame and never recurse
--     EnableMouse over the frame tree.
--   - Post-hooks only (hooksecurefunc) on globals/methods; HookScript (never
--     SetScript) on secure frames. The original secure handler always runs first.
--   - We NEVER read per-result/per-member search data. In Midnight the browse/
--     apply phase makes GetSearchResultInfo (and member/leader info) SECRET, and
--     reading it throws. We only restyle row regions, never inspect their data.
--   - The whole skin is gated on CludesUIDB.reskinLFGMenu; when off, no hooks
--     are installed and the file costs nothing.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
local CUI = CludesUI
local issecretvalue = issecretvalue or function()
    return false
end

-- Shared primitives from the window engine (loads before this file).
local Skin = mod.WSkin
-- Our per-frame state lives in our OWN weak table: the engine's uses the same
-- generic keys (border, skinned, bg, x ...) for its own skins, so a shared
-- table would let whichever skinner runs second silently no-op on a frame both
-- touch. The engine's table is read for one key only: the Modern backdrop
-- AdoptShell files there (modernBg).
local FFD, GetFFD = CludesUI.NewFrameData()
local EngineFFD = Skin.FFD
local Theme, ResolveTheme = Skin.Theme, Skin.ResolveTheme
local SolidTex, FadeRegions = Skin.SolidTex, Skin.FadeRegions

-------------------------------------------------------------------------------
--  Enable gate. Independent toggle, default on (not tied to any master reskin).
-------------------------------------------------------------------------------
local function SkinEnabled()
    return (not CludesUIDB or CludesUIDB.reskinLFGMenu ~= false)
        and not (CludesUI.BlizzWindowSkinsKilled and CludesUI.BlizzWindowSkinsKilled())
end

-- Unlike WSkin.AddBorder: OVERLAY/7 strips at the default container level.
local function AddBorder(widget, red, green, blue, a)
    if GetFFD(widget).border then
        return
    end
    local Pix = CUI and (CUI.PanelPP or CUI.PP)
    if Pix and Pix.CreateBorder then
        Pix.CreateBorder(
            widget,
            red or Theme.brdR,
            green or Theme.brdG,
            blue or Theme.brdB,
            a or Theme.brdA,
            1,
            "OVERLAY",
            7
        )
        GetFFD(widget).border = true
    end
end

-- Frames we have skinned; re-flattened whenever Blizzard repaints (tab switch,
-- category click). Strong refs are fine: these are all permanent frames.
local _restrip = {}
local function Register(widget, keep)
    if widget then
        _restrip[widget] = keep or true
    end
end
local function StripAgain()
    for widget, keep in pairs(_restrip) do
        if widget and not widget:IsForbidden() then
            local keyName = (type(keep) == "table") and keep or nil
            local skinData = FFD[widget]
            -- Protect every texture we created ourselves: the backdrop pieces,
            -- the hover highlight, and state bars. Without this the re-strip
            -- pass zeroes our own hover/selection art along with Blizzard's.
            if skinData then
                keyName = keyName or {}
                if skinData.bg then
                    keyName[skinData.bg] = true
                end
                if skinData.bgOverlay then
                    keyName[skinData.bgOverlay] = true
                end
                if skinData.topBar then
                    keyName[skinData.topBar] = true
                end
                if skinData.hover then
                    keyName[skinData.hover] = true
                end
                if skinData.selWash then
                    keyName[skinData.selWash] = true
                end
                if skinData.leftWash then
                    keyName[skinData.leftWash] = true
                end
                if skinData.leftSep then
                    keyName[skinData.leftSep] = true
                end
            end
            -- AdoptShell's Modern flat backdrop (the style's only background)
            -- lives in the ENGINE's table.
            local ed = EngineFFD[widget]
            if ed and ed.modernBg then
                keyName = keyName or {}
                keyName[ed.modernBg] = true
            end
            FadeRegions(widget, keyName)
        end
    end
end

-------------------------------------------------------------------------------
--  Primitive skinners
-------------------------------------------------------------------------------

-- Cover-fit modern_blizz atlas backdrop (matches CharacterSheet). Used for the
-- PVEFrame shell only.
local BG_ASPECT = 561 / 433
local function SkinAtlasPanel(widget)
    if not widget or widget:IsForbidden() then
        return
    end
    local skinData = GetFFD(widget)
    local keep = {}
    if skinData.bg then
        keep[skinData.bg] = true
    end
    if skinData.bgOverlay then
        keep[skinData.bgOverlay] = true
    end
    if skinData.topBar then
        keep[skinData.topBar] = true
    end
    if skinData.leftWash then
        keep[skinData.leftWash] = true
    end
    if skinData.leftSep then
        keep[skinData.leftSep] = true
    end
    local ed = EngineFFD[widget]
    if ed and ed.modernBg then
        keep[ed.modernBg] = true
    end
    FadeRegions(widget, keep)
    Register(widget, true)
    if not skinData.bg then
        local backdrop = widget:CreateTexture(nil, "BACKGROUND", nil, -8)
        backdrop:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
        backdrop:SetAllPoints(widget)
        skinData.bg = backdrop
        local overlayFrame = widget:CreateTexture(nil, "BACKGROUND", nil, -7)
        overlayFrame:SetColorTexture(0, 0, 0, 0.62)
        overlayFrame:SetAllPoints(widget)
        skinData.bgOverlay = overlayFrame

        -- Black top bar behind the window title, matching the engine shell's
        -- strip. Sits above both style backdrops (-8/-7/-6) and below content.
        local topBar = widget:CreateTexture(nil, "BACKGROUND", nil, -5)
        topBar:SetColorTexture(0, 0, 0, 0.5)
        topBar:SetPoint("TOPLEFT")
        topBar:SetPoint("TOPRIGHT")
        topBar:SetHeight(25)
        skinData.topBar = topBar

        local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
        local BASE_U, BASE_V = BASE_R - BASE_L, BASE_B - BASE_T
        local function UpdateBgTexCoords()
            local fw, fh = widget:GetSize()
            -- Secrecy test BEFORE the zero check: that check is itself a
            -- comparison and throws on a secret size. Matches the engine.
            if issecretvalue and (issecretvalue(fw) or issecretvalue(fh)) then
                return
            end
            if fw == 0 or fh == 0 then
                return
            end
            local fa = fw / fh
            if fa > BG_ASPECT then
                local visV = BASE_V * (BG_ASPECT / fa)
                local trimV = (BASE_V - visV) / 2
                backdrop:SetTexCoord(BASE_L, BASE_R, BASE_T + trimV, BASE_B - trimV)
            else
                local visU = BASE_U * (fa / BG_ASPECT)
                local trimU = (BASE_U - visU) / 2
                backdrop:SetTexCoord(BASE_L + trimU, BASE_R - trimU, BASE_T, BASE_B)
            end
        end
        -- One script hook instead of three setter hooks; also fires for
        -- anchor-driven resizes (same shape as WSkin.Shell).
        widget:HookScript("OnSizeChanged", UpdateBgTexCoords)
        UpdateBgTexCoords()
    end
    -- Window border: the shared atlas frame border every other reskinned
    -- window uses (1px line fallback if the engine is unavailable).
    if mod.WSkin and mod.WSkin.AtlasBorder then
        mod.WSkin.AtlasBorder(widget)
    else
        AddBorder(widget)
    end
    -- Register with the window-style system so the Modern flat backdrop can
    -- live-swap in for the atlas when the user picks Modern for this window.
    if mod.WSkin and mod.WSkin.AdoptShell then
        mod.WSkin.AdoptShell("lfg", widget, skinData.bg, skinData.bgOverlay)
    end
end

-- Flat solid panel. opts.noBg = strip only (let the parent backdrop show through);
-- opts.inset = darker nested fill; opts.noBorder = skip border.
local function SkinFinderPanel(widget, options)
    if not widget or widget:IsForbidden() then
        return
    end
    options = options or {}
    local skinData = GetFFD(widget)
    local keep = {}
    if skinData.bg then
        keep[skinData.bg] = true
    end
    FadeRegions(widget, keep)
    Register(widget, true)
    if not skinData.bg and not options.noBg then
        local red, green, blue, a = Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA
        if options.inset then
            red, green, blue, a = Theme.insetR, Theme.insetG, Theme.insetB, Theme.insetA
        end
        local backdrop = widget:CreateTexture(nil, "BACKGROUND", nil, -7)
        backdrop:SetColorTexture(red, green, blue, a)
        backdrop:SetAllPoints(widget)
        skinData.bg = backdrop
    end
    if not options.noBorder then
        AddBorder(widget)
    end
end

-- Strip an InsetFrameTemplate child (its Bg + rounded box) so it blends into the
-- panel backdrop instead of showing a nested box.
local function FadeInset(insetPx)
    if not insetPx or insetPx:IsForbidden() then
        return
    end
    FadeRegions(insetPx)
    if insetPx.Bg then
        insetPx.Bg:SetAlpha(0)
    end
    if insetPx.NineSlice then
        FadeRegions(insetPx.NineSlice)
    end
    Register(insetPx, true)
end

-- Generic action button -> flat dark block with hover. keepKeys preserves named
-- regions (e.g. {"Icon"}); never reads any data.
local function SkinButton(button, keepKeys)
    if not button or button:IsForbidden() then
        return
    end
    local skinData = GetFFD(button)
    if skinData.skinned then
        return
    end
    skinData.skinned = true

    local keep = {}
    if keepKeys then
        for _, keyName in ipairs(keepKeys) do
            local region = button[keyName]
            if region then
                keep[region] = true
            end
        end
    end
    FadeRegions(button, keep)
    for _, getter in ipairs({
        "GetNormalTexture",
        "GetPushedTexture",
        "GetDisabledTexture",
        "GetHighlightTexture",
    }) do
        local func = button[getter]
        local t = func and func(button)
        if t and not keep[t] then
            t:SetAlpha(0)
        end
    end
    for _, keyName in ipairs({ "Left", "Middle", "Right", "LeftSeparator", "RightSeparator" }) do
        local region = button[keyName]
        if region and not keep[region] and region.SetAlpha then
            region:SetAlpha(0)
        end
    end

    local fillTex = SolidTex(button, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
    fillTex:SetAllPoints(button)
    skinData.bg = fillTex
    AddBorder(button)

    local hover = SolidTex(button, "HIGHLIGHT", 1, 1, 1, 0.1)
    hover:SetAllPoints(button)
    skinData.hover = hover

    -- Button labels keep Blizzard's font (no-font widget policy).
    Register(button, keep)
end

-- Seat a button 5px higher (one-shot: captured original anchors + fixed lift,
-- so repeated skin passes never compound it). Handles multi-point anchoring by
-- lifting every point, not just the first.
local function LiftButton(button)
    if not button or button:IsForbidden() then
        return
    end
    local skinData = GetFFD(button)
    if skinData.lifted then
        return
    end
    local num = button:GetNumPoints() or 0
    if num < 1 then
        return
    end
    local pts = {}
    for idx = 1, num do
        local point, relTo, relPoint, posX, posY = button:GetPoint(idx)
        if not point then
            return
        end
        pts[idx] = { point, relTo, relPoint, posX or 0, (posY or 0) + 5 }
    end
    skinData.lifted = true
    button:ClearAllPoints()
    for idx = 1, #pts do
        local anchor = pts[idx]
        button:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
    end
end

-- Search / input box -> flat block, keep the magnifier + clear button art.
local function SkinEditBox(editField)
    if not editField or editField:IsForbidden() then
        return
    end
    local skinData = GetFFD(editField)
    if skinData.bg then
        return
    end
    FadeRegions(editField)
    for _, keyName in ipairs({ "Left", "Right", "Middle" }) do
        local region = editField[keyName]
        if region and region.SetAlpha then
            region:SetAlpha(0)
        end
    end
    local fillTex = SolidTex(editField, "BACKGROUND", 0.02, 0.02, 0.02, 1)
    fillTex:SetAllPoints(editField)
    skinData.bg = fillTex
    AddBorder(editField, 0.25, 0.25, 0.25, 1)
end

-- Checkbox -> the guild-roster "Show Offline Members" treatment: strip ALL
-- native art (regions + state textures) and drop a dedicated 14x14 bordered
-- box on the left, with a green tick when checked and a soft wash on
-- hover-or-checked. State is driven off the Blizzard checkbox via hooks so it
-- always mirrors the real value (no writing to the Blizzard frame's table).
local function SkinCheckbox(checkBtn)
    if not checkBtn or checkBtn:IsForbidden() then
        return
    end
    local skinData = GetFFD(checkBtn)
    if skinData.skinned then
        return
    end
    skinData.skinned = true
    local regionList = { checkBtn:GetRegions() }
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
        local t = checkBtn[g] and checkBtn[g](checkBtn)
        if t and t.SetTexture then
            t:SetTexture("")
        end
    end
    local boxF = CreateFrame("Frame", nil, checkBtn)
    boxF:SetSize(14, 14)
    boxF:SetPoint("LEFT", checkBtn, "LEFT", 4, 0)
    local fillTex = SolidTex(boxF, "BACKGROUND", 0.02, 0.02, 0.02, 1)
    fillTex:SetAllPoints(boxF)
    skinData.bg = fillTex
    AddBorder(boxF, 0.25, 0.25, 0.25, 1)
    local tickTex = boxF:CreateTexture(nil, "OVERLAY")
    tickTex:SetPoint("TOPLEFT", 3, -3)
    tickTex:SetPoint("BOTTOMRIGHT", -3, 3)
    tickTex:SetColorTexture(Theme.accR, Theme.accG, Theme.accB, 1)
    local washTex = SolidTex(boxF, "ARTWORK", 1, 1, 1, 0.1)
    washTex:SetAllPoints(boxF)
    washTex:Hide()
    local hovering = false
    local function updateState()
        local checked = checkBtn:GetChecked()
        if issecretvalue(checked) then
            -- LFGList apply-phase data can make the checked state SECRET, and
            -- boolean-testing it throws. Bind the tick straight off the secret
            -- via the boolean-accepting alpha setter; the wash tracks hover
            -- only while the state is unreadable.
            if tickTex.SetAlphaFromBoolean then
                tickTex:Show()
                tickTex:SetAlphaFromBoolean(checked, 1, 0)
            end
            washTex:SetShown(hovering)
            return
        end
        checked = checked and true or false
        tickTex:SetAlpha(1)
        tickTex:SetShown(checked)
        washTex:SetShown(hovering or checked)
    end
    checkBtn:HookScript("OnEnter", function()
        hovering = true
        updateState()
    end)
    checkBtn:HookScript("OnLeave", function()
        hovering = false
        updateState()
    end)
    checkBtn:HookScript("OnClick", updateState)
    hooksecurefunc(checkBtn, "SetChecked", updateState)
    updateState()
end

-- Modern dropdown / selector -> flat block. Heavily nil-guarded because the
-- dropdown template changes shape across builds; a mismatch simply no-ops.
local function SkinDropdown(dropdown)
    if not dropdown or dropdown:IsForbidden() then
        return
    end
    local skinData = GetFFD(dropdown)
    if skinData.skinned then
        return
    end
    skinData.skinned = true
    FadeRegions(dropdown)
    -- Legacy UIDropDownMenu textures, if present.
    local name = dropdown.GetName and dropdown:GetName()
    if name then
        for _, suffix in ipairs({ "Left", "Middle", "Right" }) do
            local region = _G[name .. suffix]
            if region and region.SetAlpha then
                region:SetAlpha(0)
            end
        end
    end
    if dropdown.Background then
        dropdown.Background:SetAlpha(0)
    end
    if dropdown.Texture then
        dropdown.Texture:SetAlpha(0)
    end
    local fillTex = SolidTex(dropdown, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
    fillTex:SetAllPoints(dropdown)
    skinData.bg = fillTex
    AddBorder(dropdown, 0.25, 0.25, 0.25, 1)
    -- Slight lighten on hover.
    local hover = SolidTex(dropdown, "HIGHLIGHT", 1, 1, 1, 0.05)
    hover:SetAllPoints(dropdown)
    skinData.hover = hover
    -- Our own arrow on the right (Blizzard's is faded with the rest).
    -- Sized to the atlas's native 62x44 aspect.
    local arrowTex = dropdown:CreateTexture(nil, "OVERLAY")
    arrowTex:SetAtlas("Azerite-PointingArrow")
    arrowTex:SetSize(14, 10)
    arrowTex:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)
    skinData.arrow = arrowTex
end

-- MinimalScrollBar -> strip track/arrows; the thumb becomes a slim 5px white
-- strip centered in the thumb's hit area (the house scrollbar look).
local function SkinScrollBar(scrollBar)
    if not scrollBar or scrollBar:IsForbidden() then
        return
    end
    local skinData = GetFFD(scrollBar)
    if skinData.skinned then
        return
    end
    skinData.skinned = true
    for _, keyName in ipairs({ "Back", "Forward" }) do
        local b = scrollBar[keyName]
        if b then
            FadeRegions(b)
            if b.Texture then
                b.Texture:SetAlpha(0)
            end
        end
    end
    local track = scrollBar.Track
    if track then
        FadeRegions(track)
    end
    local knob = (track and track.Thumb) or (scrollBar.GetThumb and scrollBar:GetThumb())
    if knob and not GetFFD(knob).bg then
        FadeRegions(knob)
        local t = SolidTex(knob, "ARTWORK", 1, 1, 1, 0.3)
        t:SetPoint("TOP", knob, "TOP", 0, 0)
        t:SetPoint("BOTTOM", knob, "BOTTOM", 0, 0)
        t:SetWidth(4)
        GetFFD(knob).bg = t
    end
end

-- Close (X) button -> strip art, draw the house close glyph (the engine's).
local SkinCloseButton = Skin.CloseButton

-- PVEFrame bottom tab -> CharacterSheet tab pattern (bg + accent underline when
-- active). Visuals driven by UpdateTabVisuals (reads PVEFrame.selectedTab).
local function SkinTab(tabBtn)
    if not tabBtn or tabBtn:IsForbidden() then
        return
    end
    local skinData = GetFFD(tabBtn)
    if skinData.bg then
        return
    end
    local regionList = { tabBtn:GetRegions() }
    for jdx = 1, #regionList do
        local region = regionList[jdx]
        if region and region:IsObjectType("Texture") then
            region:SetTexture("")
            if region.SetAtlas then
                region:SetAtlas("")
            end
        end
    end
    for _, keyName in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
        if tabBtn[keyName] then
            tabBtn[keyName]:SetTexture("")
        end
    end
    local highlight = tabBtn.GetHighlightTexture and tabBtn:GetHighlightTexture()
    if highlight then
        highlight:SetTexture("")
    end

    skinData.bg = SolidTex(tabBtn, "BACKGROUND", 0.068, 0.056, 0.052, 1)
    skinData.bg:SetAllPoints()

    local activeHL = tabBtn:CreateTexture(nil, "ARTWORK", nil, -6)
    activeHL:SetAllPoints()
    activeHL:SetColorTexture(1, 1, 1, 0.02)
    activeHL:SetBlendMode("ADD")
    activeHL:Hide()
    skinData.activeHL = activeHL

    local blizLabel = tabBtn.GetFontString and tabBtn:GetFontString()
    local labelText = (blizLabel and blizLabel:GetText()) or ""
    if blizLabel then
        blizLabel:SetTextColor(0, 0, 0, 0)
    end
    if tabBtn.SetPushedTextOffset then
        tabBtn:SetPushedTextOffset(0, 0)
    end

    local label = tabBtn:CreateFontString(nil, "OVERLAY")
    label:SetFont(Theme.fontPath, 11, "")
    label:SetPoint("CENTER", tabBtn, "CENTER", 0, 0)
    label:SetText(labelText)
    skinData.label = label
    hooksecurefunc(tabBtn, "SetText", function(_, newText)
        if newText and skinData.label then
            skinData.label:SetText(newText)
        end
    end)

    local underlineTex = tabBtn:CreateTexture(nil, "OVERLAY", nil, 6)
    if CUI and CUI.PanelPP and CUI.PanelPP.DisablePixelSnap then
        CUI.PanelPP.DisablePixelSnap(underlineTex)
        underlineTex:SetHeight(CUI.PanelPP.mult or 1)
    else
        underlineTex:SetHeight(1)
    end
    underlineTex:SetPoint("BOTTOMLEFT", tabBtn, "BOTTOMLEFT", 0, 0)
    underlineTex:SetPoint("BOTTOMRIGHT", tabBtn, "BOTTOMRIGHT", 0, 0)
    -- Color + visibility follow the Blizzard Window Skins "Global Options"
    -- accent-bar setting; the window-skin engine recolors registered
    -- underlines on option edits and accent changes.
    local wsk = mod.WSkin
    if wsk and wsk.AccentBarColor then
        local ur, ug, ub = wsk.AccentBarColor()
        underlineTex:SetColorTexture(ur, ug, ub, 1)
        if wsk.RegisterAccentUnderline then
            wsk.RegisterAccentUnderline(underlineTex)
        end
    else
        underlineTex:SetColorTexture(Theme.accR, Theme.accG, Theme.accB, 1)
        CUI.RegAccent({ type = "solid", obj = underlineTex, a = 1 })
    end
    underlineTex:Hide()
    skinData.underline = underlineTex
end

local _gfLooksHooked = false
-- The left rail zone (wash + divider) belongs only to tabs that HAVE a left
-- category rail: Dungeons & Raids (GroupFinderFrame) and PvP (PVPUIFrame). It
-- is anchored to PVEFrame, so without this it persists onto the Mythic+ tab
-- (which has no rail). Gate its visibility on a rail-owning frame being shown.
local function UpdateRailZone()
    local skinData = PVEFrame and FFD[PVEFrame]
    if not skinData then
        return
    end
    local show = (GroupFinderFrame and GroupFinderFrame:IsShown())
        or (_G.PVPUIFrame and _G.PVPUIFrame:IsShown())
        or false
    if skinData.leftWash then
        skinData.leftWash:SetShown(show and true or false)
    end
    if skinData.leftSep then
        skinData.leftSep:SetShown(show and true or false)
    end
end

local function UpdateTabVisuals()
    if not PVEFrame then
        return
    end
    UpdateRailZone()
    local sel = PVEFrame.selectedTab or 1
    local barsOn = not (mod.WSkin and mod.WSkin.AccentBarShown) or mod.WSkin.AccentBarShown()
    for idx = 1, 4 do
        local tabBtn = _G["PVEFrameTab" .. idx]
        local skinData = tabBtn and FFD[tabBtn]
        if skinData then
            local isActive = (sel == idx)
            if skinData.label then
                skinData.label:SetTextColor(1, 1, 1, isActive and 1 or 0.5)
            end
            if skinData.underline then
                skinData.underline:SetShown(isActive and barsOn)
            end
            if skinData.activeHL then
                skinData.activeHL:SetShown(isActive)
            end
        end
    end
    if not _gfLooksHooked and mod.WSkin and mod.WSkin.OnLooksChanged then
        _gfLooksHooked = true
        mod.WSkin.OnLooksChanged(UpdateTabVisuals)
    end
end

-- Left category rail buttons use the parentKey form GroupFinderFrame.groupButtonN
-- in modern clients; fall back to the older global name if absent.
local function CategoryButton(idx)
    return (GroupFinderFrame and GroupFinderFrame["groupButton" .. idx])
        or _G["GroupFinderFrameGroupButton" .. idx]
end

-- Left category rail button (GroupFinderGroupButtonTemplate): keep the icon,
-- flatten the rest, add a selected-state accent border. opts.keepRing spares
-- the icon's ring border (PvP rail keeps it per user; D&R strips it).
-- Re-apply a rail button's converted anchors from its stored spec. Chained
-- buttons hang off the previous button; the chain root pins to the rail wash.
local function ApplyRailAnchors(button)
    local skinData = FFD[button]
    local a = skinData and skinData.railAnchors
    if not a then
        return
    end
    button:ClearAllPoints()
    if a.rel then
        button:SetPoint("TOPLEFT", a.rel, "BOTTOMLEFT", 0, a.y)
        button:SetPoint("TOPRIGHT", a.rel, "BOTTOMRIGHT", 0, a.y)
    else
        button:SetPoint("TOPLEFT", a.wash, "TOPLEFT", 0, a.y)
        button:SetPoint("TOPRIGHT", a.wash, "TOPRIGHT", 0, a.y)
    end
end

local function SkinCategoryButton(button, options)
    if not button or button:IsForbidden() then
        return
    end
    local skinData = GetFFD(button)
    skinData.isRail = true
    -- Full-width cards: pin both side edges to the rail-column wash so every
    -- card runs edge-to-edge (offset guesses always left a gap against the
    -- stock insets). One-shot per button, retries until laid out. The chain
    -- root keeps its exact vertical seat; chained buttons keep their vertical
    -- gap (closed 10px) and ride the 12px-taller previous button down.
    if not skinData.railWide then
        local hgt = button:GetHeight()
        local pd = PVEFrame and FFD[PVEFrame]
        local washTex = pd and pd.leftWash
        if hgt and hgt > 10 and washTex and button:GetTop() and washTex:GetTop() then
            skinData.railWide = true
            button:SetHeight(hgt + 12)
            local point, relTo, relPoint, posX, posY = button:GetPoint(1)
            if point and relTo and FFD[relTo] and FFD[relTo].isRail then
                skinData.railAnchors = { rel = relTo, y = (posY or 0) + 10 }
            else
                skinData.railAnchors = { wash = washTex, y = button:GetTop() - washTex:GetTop() }
            end
            ApplyRailAnchors(button)
            -- Blizzard re-anchors these buttons from its own layout passes
            -- (the PvP rail re-seats on every show), stomping a one-shot
            -- conversion: re-assert ours synchronously, reentry-guarded.
            hooksecurefunc(button, "SetPoint", function()
                if skinData.inPin then
                    return
                end
                skinData.inPin = true
                ApplyRailAnchors(button)
                skinData.inPin = false
            end)
        end
    end
    -- Icon (and its ring, so the border keeps hugging it) 10px smaller and
    -- shifted 3px right; the BUTTON keeps its stock size. Outside the skinned
    -- guard so it retries per pass until the icon has a laid-out size.
    local icon0 = button.icon or button.Icon
    if icon0 and not GetFFD(icon0).shrunk then
        local wid, hgt = icon0:GetSize()
        if wid and hgt and wid > 10 and hgt > 10 then
            GetFFD(icon0).shrunk = true
            icon0:SetSize(wid - 10, hgt - 10)
            local np = icon0:GetNumPoints() or 0
            local pts, success = {}, np > 0
            for idx = 1, np do
                local point, relTo, relPoint, posX, posY = icon0:GetPoint(idx)
                if not point then
                    success = false
                    break
                end
                pts[idx] = { point, relTo, relPoint, (posX or 0) + 3, posY or 0 }
            end
            if success then
                icon0:ClearAllPoints()
                for idx = 1, #pts do
                    local anchor = pts[idx]
                    icon0:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
                end
            end
            local ring0 = button.ring or button.Ring
            if ring0 and ring0.GetSize then
                local rw, rh = ring0:GetSize()
                if rw and rh and rw > 10 and rh > 10 then
                    ring0:SetSize(rw - 10, rh - 10)
                end
            end
        end
    end
    if skinData.skinned then
        return
    end
    skinData.skinned = true

    local keep = {}
    -- D&R buttons use lowercase keys (icon/ring); the PvP queue buttons use
    -- capitalized ones (Icon/Ring). Same template family otherwise.
    local iconTex = button.icon or button.Icon
    if iconTex then
        keep[iconTex] = true
    end
    if button.bgGlow then
        button.bgGlow:SetAlpha(0)
    end
    local ring = button.ring or button.Ring
    if ring then
        if options and options.keepRing then
            keep[ring] = true
        else
            ring:SetAlpha(0)
        end
    end
    FadeRegions(button, keep)
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then
        highlight:SetAlpha(0)
    end

    -- Card look matches the Guild & Communities sidebar entries: the same dialog-sheet
    -- card atlas at half strength, pulled in 2px top and bottom so stacked tabs never
    -- sit flush. No border -- the card art carries its own soft edge. The stock
    -- template clips child regions to the button rect, which swallows any card overhang
    -- -- unclip so the art can reach the edges.
    if button.SetClipsChildren then
        button:SetClipsChildren(false)
    end
    local cardFrame = button:CreateTexture(nil, "BACKGROUND")
    cardFrame:SetAtlas("Ui-Dialog-New-Background")
    cardFrame:SetAlpha(0.5)
    -- Horizontal overhang compensates for the atlas's baked-in transparent
    -- margins (and the rail column's own inset from the window edge) so the
    -- VISIBLE art reads edge-to-edge (user-measured offsets).
    cardFrame:SetPoint("TOPLEFT", button, "TOPLEFT", -6, -2)
    cardFrame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, 2)
    skinData.bg = cardFrame

    -- Hover + active wash: subtle white clamped 3px inside the card rect
    -- (the card atlas bakes in soft transparent edges, so a wash on the full
    -- rect reads bigger than the visible art).
    local hover = SolidTex(button, "HIGHLIGHT", 1, 1, 1, 0.05)
    hover:SetPoint("TOPLEFT", cardFrame, "TOPLEFT", 3, -3)
    hover:SetPoint("BOTTOMRIGHT", cardFrame, "BOTTOMRIGHT", -3, 3)
    skinData.hover = hover

    -- Held on while this category is selected.
    local selWash = SolidTex(button, "ARTWORK", 1, 1, 1, 0.05)
    selWash:SetPoint("TOPLEFT", cardFrame, "TOPLEFT", 3, -3)
    selWash:SetPoint("BOTTOMRIGHT", cardFrame, "BOTTOMRIGHT", -3, 3)
    selWash:Hide()
    skinData.selWash = selWash

    -- Re-derive the selection visuals after Blizzard's own click handler has
    -- processed the category change.
    if options and options.onSelect then
        button:HookScript("OnClick", options.onSelect)
    end

    -- Category button labels keep Blizzard's font (no-font widget policy).
    Register(button, keep)
end

-- Latest selection captured from Blizzard's own select call (authoritative
-- when available; the frame state fields proved unreliable in Midnight).
local _gfSelIndex
local _pvpSel

-- Resolve the selected rail entry from the strongest available signal:
-- captured select-call arg > CheckButton checked state > Blizzard's own
-- selection glow (we alpha-0 it, but Blizzard still Show/Hides it; only
-- trusted when exactly one is shown, i.e. it behaves like a selection) >
-- legacy holder-frame selection fields. Returns an index or a button.
local function ResolveRailSelection(getBtn, captured, holderFrame)
    if captured ~= nil then
        return captured
    end
    for idx = 1, 4 do
        local widget = getBtn(idx)
        if widget and widget.GetChecked then
            local c = widget:GetChecked()
            -- Secret checked state is unreadable; fall through to the next
            -- signal in the cascade instead of boolean-testing it.
            if not issecretvalue(c) and c then
                return idx
            end
        end
    end
    local glowSel, glowCount = nil, 0
    for idx = 1, 4 do
        local b = getBtn(idx)
        local g = b and (b.bgGlow or b.bg or b.SelectedTexture)
        if g and g.IsShown and g:IsShown() then
            glowCount = glowCount + 1
            glowSel = idx
        end
    end
    if glowCount == 1 then
        return glowSel
    end
    return holderFrame and (holderFrame.selection or holderFrame.selectionIndex) or nil
end

local function UpdateCategorySelection()
    local sel = ResolveRailSelection(CategoryButton, _gfSelIndex, _G.GroupFinderFrame)
    for idx = 1, 4 do
        local button = CategoryButton(idx)
        local skinData = button and FFD[button]
        if skinData and skinData.selWash then
            skinData.selWash:SetShown((sel == idx or sel == button) and true or false)
        end
    end
end

-------------------------------------------------------------------------------
--  Frame-specific skins
-------------------------------------------------------------------------------

local function Skin_PVEFrame()
    if not PVEFrame then
        return
    end
    SkinAtlasPanel(PVEFrame)

    -- Portrait (top-left eye icon) lives in a child container the frame-level
    -- strip does not reach.
    local pc = PVEFrame.PortraitContainer
    if pc then
        FadeRegions(pc)
        Register(pc, true)
    end
    if PVEFrame.portrait and PVEFrame.portrait.SetAlpha then
        PVEFrame.portrait:SetAlpha(0)
    end
    if PVEFramePortrait and PVEFramePortrait.SetAlpha then
        PVEFramePortrait:SetAlpha(0)
    end
    if PVEFrame.shadows then
        FadeRegions(PVEFrame.shadows)
        Register(PVEFrame.shadows, true)
    end

    local closeBtn = PVEFrame.CloseButton or _G.PVEFrameCloseButton
    if closeBtn then
        SkinCloseButton(closeBtn)
    end

    -- Left column inset: strip its art so the shell backdrop shows through.
    local leftInset = PVEFrame.Inset or _G["PVEFrameLeftInset"]
    if leftInset then
        SkinFinderPanel(leftInset, { noBg = true, noBorder = true })
    end

    -- Rail zone: 10% black wash over the LEFT sidebar column + a
    -- 1-physical-px divider on its right edge, between the rail tabs and the
    -- content. Rides the left inset's rect (the definitive rail column).
    local skinData = GetFFD(PVEFrame)
    if not skinData.leftWash then
        local pixel = 1
        local PPx = CUI and CUI.PP
        local es = PVEFrame:GetEffectiveScale()
        if PPx and PPx.perfect and es and es > 0 then
            pixel = PPx.perfect / es
        end
        local washTex = PVEFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        washTex:SetColorTexture(0, 0, 0, 0.1)
        if leftInset then
            washTex:SetAllPoints(leftInset)
        else
            washTex:SetPoint("TOPLEFT", PVEFrame, "TOPLEFT", 7, -62)
            washTex:SetPoint("BOTTOMRIGHT", PVEFrame, "BOTTOMLEFT", 206, 7)
        end
        skinData.leftWash = washTex
        local sep = PVEFrame:CreateTexture(nil, "ARTWORK")
        sep:SetColorTexture(0.15, 0.15, 0.15, 1)
        sep:SetWidth(pixel)
        sep:SetPoint("TOPLEFT", washTex, "TOPRIGHT", 0, 0)
        sep:SetPoint("BOTTOMLEFT", washTex, "BOTTOMRIGHT", 0, 0)
        skinData.leftSep = sep
    end

    local pveTabs = {}
    for idx = 1, 4 do
        local tabBtn = _G["PVEFrameTab" .. idx]
        if tabBtn then
            SkinTab(tabBtn)
            pveTabs[#pveTabs + 1] = tabBtn
        end
    end
    if mod.WSkin and mod.WSkin.NormalizeTabRow then
        mod.WSkin.NormalizeTabRow(pveTabs)
    end
    UpdateTabVisuals()
end

local function Skin_GroupFinder()
    for idx = 1, 4 do
        local gb = CategoryButton(idx)
        if gb then
            SkinCategoryButton(gb, { keepRing = true, onSelect = UpdateCategorySelection })
        end
    end
    UpdateCategorySelection()

    -- Dungeon Finder (LFD)
    if LFDParentFrame then
        SkinFinderPanel(LFDParentFrame, { noBg = true, noBorder = true })
    end
    if _G.LFDParentFrameInset then
        FadeInset(_G.LFDParentFrameInset)
    end
    if LFDQueueFrame then
        SkinFinderPanel(LFDQueueFrame, { noBg = true, noBorder = true })
    end
    if LFDQueueFrameRandomScrollFrame then
        SkinFinderPanel(LFDQueueFrameRandomScrollFrame, { noBg = true, noBorder = true })
    end
    if LFDQueueFrameFindGroupButton then
        SkinButton(LFDQueueFrameFindGroupButton)
        LiftButton(LFDQueueFrameFindGroupButton)
    end
    if _G.LFDQueueFrameTypeDropdown then
        SkinDropdown(_G.LFDQueueFrameTypeDropdown)
    end
    local lfdSB = _G["LFDQueueFrameRandomScrollFrameScrollBar"]
        or (LFDQueueFrameRandomScrollFrame and LFDQueueFrameRandomScrollFrame.ScrollBar)
    if lfdSB then
        SkinScrollBar(lfdSB)
    end
    if _G.LFDQueueFrameSpecific and _G.LFDQueueFrameSpecific.ScrollBar then
        SkinScrollBar(_G.LFDQueueFrameSpecific.ScrollBar)
    end
end

-- Premade Groups category buttons (Dungeons / Raids / Arenas / ...): the base
-- button skin plus a white selection wash held on while that category is the
-- active pick, matching the left sidebar rail's active state.
local function SkinLFGCategoryButton(button)
    if not button or button:IsForbidden() then
        return
    end
    SkinButton(button)
    local skinData = GetFFD(button)
    if not skinData.selWash then
        -- ARTWORK below the button label (sublevel -1) and above the fill.
        local selWash = SolidTex(button, "ARTWORK", 1, 1, 1, 0.05, -1)
        selWash:SetAllPoints(button)
        selWash:Hide()
        skinData.selWash = selWash
    end
    -- Match the sidebar rail: hover + active both 0.05 white.
    if skinData.hover then
        skinData.hover:SetColorTexture(1, 1, 1, 0.05)
    end
end

-- Is this category button the active pick? Blizzard's authoritative state is
-- CategorySelection.selectedCategory (+ selectedFilters), matched against each
-- button's own categoryID/filters. This is why SelectedTexture:IsShown() failed
-- for the first button: Blizzard HIDES that texture in the AddButton rebuild
-- and re-derives selection from the ID, and the first category is auto-selected
-- by default (never passing through the click hook).
local function IsLFGCategorySelected(checkSkin, button)
    return checkSkin.selectedCategory ~= nil
        and button.categoryID == checkSkin.selectedCategory
        and button.filters == checkSkin.selectedFilters
end

local function UpdateLFGCategorySelection()
    local CS = LFGListFrame and LFGListFrame.CategorySelection
    if not (CS and CS.CategoryButtons) then
        return
    end
    for _, button in ipairs(CS.CategoryButtons) do
        local skinData = FFD[button]
        if skinData and skinData.selWash then
            skinData.selWash:SetShown(IsLFGCategorySelected(CS, button) and true or false)
        end
    end
end

local function Skin_LFGList()
    if not LFGListFrame then
        return
    end

    local CS = LFGListFrame.CategorySelection
    if CS then
        SkinFinderPanel(CS, { noBg = true, noBorder = true })
        if CS.Inset then
            FadeInset(CS.Inset)
        end
        if CS.CategoryButtons then
            for _, btn in ipairs(CS.CategoryButtons) do
                SkinLFGCategoryButton(btn)
            end
            UpdateLFGCategorySelection()
        end
        -- Blizzard rebuilds every category button through AddButton on the
        -- initial show AND on every selection change (SelectButton ->
        -- UpdateCategoryButtons -> AddButton per button), so this is the one
        -- hook that catches the default selection and every click alike.
        if LFGListCategorySelection_AddButton and not GetFFD(CS).addBtnHook then
            GetFFD(CS).addBtnHook = true
            hooksecurefunc("LFGListCategorySelection_AddButton", function(checkSkin, btnIndex, categoryID, filters)
                local widget = checkSkin and checkSkin.CategoryButtons and checkSkin.CategoryButtons[btnIndex]
                if not widget or widget:IsForbidden() then
                    return
                end
                SkinLFGCategoryButton(widget)
                local skinData = FFD[widget]
                if skinData and skinData.selWash then
                    local sel = (checkSkin.selectedCategory == categoryID) and (checkSkin.selectedFilters == filters)
                    skinData.selWash:SetShown(sel and true or false)
                end
            end)
        end
        if CS.FindGroupButton then
            SkinButton(CS.FindGroupButton)
            LiftButton(CS.FindGroupButton)
        end
        if CS.StartGroupButton then
            SkinButton(CS.StartGroupButton)
            LiftButton(CS.StartGroupButton)
        end
    end

    local SP = LFGListFrame.SearchPanel
    if SP then
        SkinFinderPanel(SP, { noBg = true, noBorder = true })
        if SP.ResultsInset then
            FadeInset(SP.ResultsInset)
        end
        if SP.SearchBox then
            SkinEditBox(SP.SearchBox)
        end
        if SP.FilterButton then
            SkinButton(SP.FilterButton)
        end
        if SP.RefreshButton then
            Skin.RefreshGlyph(SP.RefreshButton)
        end
        if SP.BackButton then
            SkinButton(SP.BackButton)
        end
        if SP.BackToGroupButton then
            SkinButton(SP.BackToGroupButton)
        end
        if SP.SignUpButton then
            SkinButton(SP.SignUpButton)
        end
        if SP.ScrollBar then
            SkinScrollBar(SP.ScrollBar)
        end
        -- The active-filter X, as on every other filter dropdown: it straddles
        -- the filter button's top edge, above the button's border.
        local reset = SP.FilterButton and SP.FilterButton.ResetButton
        if reset then
            Skin.FilterResetX(reset, SP.FilterButton)
        end
    end

    local EC = LFGListFrame.EntryCreation
    if EC then
        SkinFinderPanel(EC, { noBg = true, noBorder = true })
        if EC.Inset then
            FadeInset(EC.Inset)
        end
        if EC.CancelButton then
            SkinButton(EC.CancelButton)
        end
        if EC.ListGroupButton then
            SkinButton(EC.ListGroupButton)
        end
        if EC.Name then
            SkinEditBox(EC.Name)
        end
        if EC.Description then
            SkinEditBox(EC.Description)
        end
        for _, keyName in ipairs({ "GroupDropdown", "ActivityDropdown", "PlayStyleDropdown" }) do
            if EC[keyName] then
                SkinDropdown(EC[keyName])
            end
        end
        for _, keyName in ipairs({ "ItemLevel", "MythicPlusRating", "PVPRating", "PvpItemLevel", "VoiceChat" }) do
            local req = EC[keyName]
            if req then
                if req.EditBox then
                    SkinEditBox(req.EditBox)
                end
                if req.CheckButton then
                    SkinCheckbox(req.CheckButton)
                end
            end
        end
        for _, keyName in ipairs({ "PrivateGroup", "CrossFactionGroup" }) do
            if EC[keyName] and EC[keyName].CheckButton then
                SkinCheckbox(EC[keyName].CheckButton)
            end
        end
    end

    -- The applicant viewer stays Blizzard's, like the search result rows: its
    -- updates run secret-value compares in Blizzard's code, and with this skin
    -- applied they error for raid leaders ("compare a secret number"; which
    -- write carries the taint is not pinned down). The viewer sits in
    -- PVEFrame's protected tree, so IsProtected() is true here and the block
    -- below does not run.
    local AV = LFGListFrame.ApplicationViewer
    if AV and not AV:IsProtected() then
        SkinFinderPanel(AV, { noBg = true, noBorder = true })
        if AV.Inset then
            FadeInset(AV.Inset)
        end
        if AV.RefreshButton then
            Skin.RefreshGlyph(AV.RefreshButton)
        end
        if AV.RemoveEntryButton then
            SkinButton(AV.RemoveEntryButton)
        end
        if AV.EditButton then
            SkinButton(AV.EditButton)
        end
        if AV.BrowseGroupsButton then
            SkinButton(AV.BrowseGroupsButton)
        end
        if AV.AutoAcceptButton then
            SkinCheckbox(AV.AutoAcceptButton)
        end
        for _, keyName in ipairs({
            "NameColumnHeader",
            "RoleColumnHeader",
            "ItemLevelColumnHeader",
            "RatingColumnHeader",
        }) do
            if AV[keyName] then
                SkinButton(AV[keyName])
            end
        end
        if AV.ScrollBar then
            SkinScrollBar(AV.ScrollBar)
        end
        if AV.InfoBackground then
            AV.InfoBackground:SetAlpha(0)
        end
    end

    -- Search result rows are left FULLY stock. We used to skin the per-row
    -- CancelButton (shown while you're applied/queued to that group), but that
    -- made the queued-state button read wrong, so it stays Blizzard's. We never
    -- read row data (secret in Midnight) or blanket-strip the row either.
end

-- Raid Finder leftover art. Blizzard re-raises the role inset's backdrop from
-- a path that fires when the panel shows (none of our restrip hooks cover that
-- transition), so this runs from both the skin pass AND an OnShow refade.
local _rbGuard = false
local function FadeRaidFinderArt()
    local ri = _G.RaidFinderFrameRoleInset
    if ri then
        FadeInset(ri)
        -- Explicit by key too: survives the case where Bg is not a direct
        -- region the sweep reaches.
        if ri.Bg and ri.Bg.SetAlpha then
            ri.Bg:SetAlpha(0)
        end
    end
    if _G.RaidFinderFrameBottomInset then
        FadeInset(_G.RaidFinderFrameBottomInset)
    end
    -- Role background (orange gradient behind the role buttons): Blizzard's
    -- rewards updaters (RaidFinderQueueFrameRewards_UpdateFrame and the shared
    -- LFGRewardsFrame_UpdateFrame) re-raise this art on every rewards/role/raid
    -- update, which is why one-shot fades never stuck. This helper is hooked to
    -- those updaters below, AND the art image itself is cleared so nothing
    -- shows even if a raise path slips through.
    local rb = _G.RaidFinderFrameRoleBackground
    if rb and rb.SetAlpha then
        _rbGuard = true
        rb:SetAlpha(0)
        _rbGuard = false
        if rb.SetTexture then
            rb:SetTexture("")
        end
        if rb.SetAtlas then
            rb:SetAtlas("")
        end
        local regionData = GetFFD(rb)
        if not regionData.alphaGuarded then
            regionData.alphaGuarded = true
            hooksecurefunc(rb, "SetAlpha", function(t)
                if _rbGuard then
                    return
                end
                _rbGuard = true
                t:SetAlpha(0)
                _rbGuard = false
            end)
        end
    end
    -- Questpaper scenic art behind the rewards list: re-textured by the same updaters.
    local qb = _G.RaidFinderQueueFrameBackground
    if qb and qb.SetAlpha then
        qb:SetAlpha(0)
    end
end

local _rfShowHooked = false
local function Skin_RaidFinder()
    if RaidFinderFrame then
        SkinFinderPanel(RaidFinderFrame, { noBg = true, noBorder = true })
    end
    FadeRaidFinderArt()
    if RaidFinderFrame and not _rfShowHooked then
        _rfShowHooked = true
        RaidFinderFrame:HookScript("OnShow", FadeRaidFinderArt)
    end
    if RaidFinderQueueFrame then
        SkinFinderPanel(RaidFinderQueueFrame, { noBg = true, noBorder = true })
    end
    if RaidFinderFrameFindRaidButton then
        SkinButton(RaidFinderFrameFindRaidButton)
        LiftButton(RaidFinderFrameFindRaidButton)
    end
    if _G.RaidFinderQueueFrameSelectionDropdown then
        SkinDropdown(_G.RaidFinderQueueFrameSelectionDropdown)
    end
    local rfSB = (_G.RaidFinderQueueFrameScrollFrame and _G.RaidFinderQueueFrameScrollFrame.ScrollBar)
        or _G.RaidFinderQueueFrameScrollFrameScrollBar
    if rfSB then
        SkinScrollBar(rfSB)
    end
end

-------------------------------------------------------------------------------
--  Reward tiles (Dungeon Finder + Raid Finder) and the M+ dungeon icon row.
-------------------------------------------------------------------------------

-- Rings and plates stacked on a LargeItemButtonTemplate icon. The same list the
-- quest reward tiles use, and for the same reason: IconBorder is a ROUNDED
-- quality ring drawn OVER the icon, so it defeats the square crop underneath
-- it, and NameFrame is the parchment plate behind the label.
local REWARD_ART = { "IconBorder", "IconOverlay", "IconOverlay2", "IconBorder2", "NameFrame" }

-- Rarity color for one reward tile, or nil for "no rarity" (border draws black).
-- Derived from the LFG reward API rather than the IconBorder ring: these tiles
-- never get SetItemButtonQuality, so the ring carries no color; the tile's
-- SetID(rewardIndex) + .dungeonID / .shortageIndex identify the reward.
local function RewardQualityColor(button)
    local did, si = button.dungeonID, button.shortageIndex
    local ident = button.GetID and button:GetID()
    if type(did) ~= "number" or type(ident) ~= "number" or ident <= 0 then
        return
    end
    -- `_` is declared LOCAL rather than left to fall through to the global of
    -- that name: this runs inside Blizzard's own call stack from a hook, and a
    -- stray global write from there is exactly the kind of thing this file's
    -- taint rules exist to avoid.
    local success, _, numItems, rewardType, rewardID, quality
    if si ~= nil then
        if type(GetLFGDungeonShortageRewardInfo) ~= "function" then
            return
        end
        success, _, _, numItems, _, rewardType, rewardID, quality =
            pcall(GetLFGDungeonShortageRewardInfo, did, si, ident)
    else
        if type(GetLFGDungeonRewardInfo) ~= "function" then
            return
        end
        success, _, _, numItems, _, rewardType, rewardID, quality = pcall(GetLFGDungeonRewardInfo, did, ident)
    end
    if not success then
        return
    end
    -- Currency CONTAINERS carry their own quality, not the raw currency's.
    -- Blizzard remaps it one line before it fills the tile, so a skin that
    -- skips this paints a bag of gold with the wrong rarity.
    if
        rewardType == "currency"
        and rewardID ~= nil
        and C_CurrencyInfo
        and C_CurrencyInfo.IsCurrencyContainer
        and CurrencyContainerUtil
    then
        local okC, isC = pcall(C_CurrencyInfo.IsCurrencyContainer, rewardID, numItems)
        if okC and isC then
            local okQ, _, _, _, q =
                pcall(CurrencyContainerUtil.GetCurrencyContainerInfo, rewardID, numItems, nil, nil, quality)
            if okQ then
                quality = q
            end
        end
    end
    if quality == nil or issecretvalue(quality) or type(quality) ~= "number" then
        return
    end
    local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if not (colour and colour.r) then
        return
    end
    -- Achromatic qualities (poor grey, common white) are not a cue -- they read
    -- as a colored border that happens to be grey. Same chroma test the engine
    -- applies when it reads a ring, so the two surfaces agree on what counts.
    local hi = math.max(colour.r, colour.g, colour.b)
    local lo = math.min(colour.r, colour.g, colour.b)
    if (hi - lo) <= 0.1 then
        return
    end
    return colour.r, colour.g, colour.b
end

-- One reward tile, treated exactly like a quest reward: strip the rings and the
-- parchment plate, square the icon, put the rarity back as a SQUARE border.
local function SkinRewardTile(button)
    if not button or button:IsForbidden() then
        return
    end
    for idx = 1, #REWARD_ART do
        local t = button[REWARD_ART[idx]]
        if t and t.SetAlpha and t.IsObjectType and t:IsObjectType("Texture") then
            t:SetAlpha(0)
        end
    end
    if button.Name and button.Name.SetTextColor then
        button.Name:SetTextColor(1, 1, 1)
    end
    local wsk = mod.WSkin
    if not (wsk and wsk.SquareIcon and button.Icon) then
        return
    end
    local red, green, blue = RewardQualityColor(button)
    if red then
        -- Crop first, and only border what actually cropped: SquareIcon leaves a
        -- masked icon fully native, and a square border round something the mask
        -- renders as a different shape is worse than no border.
        if wsk.SquareIcon(button.Icon, nil) and wsk.QualityBorder then
            wsk.QualityBorder(button, button.Icon, red, green, blue)
        end
    else
        -- No rarity worth showing: let the engine draw its black edge.
        wsk.SquareIcon(button.Icon, button, true)
    end
end

-- Every tile in one rewards panel. Shared by the Dungeon Finder and the Raid
-- Finder: RaidFinderQueueFrameRewards_UpdateFrame delegates to
-- LFGRewardsFrame_UpdateFrame with its own child frame, so hooking the shared
-- updater covers both panels in one place.
--
-- The item rows are GLOBALS ($parentItem1..n), created on demand and counted by
-- parentFrame.numRewardFrames; MoneyReward is a parentKey. Both inherit
-- LargeItemButtonTemplate, so both take the same treatment -- the gold row is
-- the one in the screenshot.
local function SkinRewardsFrame(parentFrame)
    if not parentFrame or parentFrame:IsForbidden() then
        return
    end
    local name = parentFrame.GetName and parentFrame:GetName()
    local num = parentFrame.numRewardFrames
    if name and type(num) == "number" then
        for idx = 1, num do
            SkinRewardTile(_G[name .. "Item" .. idx])
        end
    end
    SkinRewardTile(parentFrame.MoneyReward)
end

-- The M+ dungeon icon row. The template draws a ROUNDED DungeonIconFrame atlas
-- over the icon as an unnamed BORDER-layer region, so cropping alone shows no
-- change: FadeRegions (icon kept) is the only way to reach it.
local _iconKeep = {}
local function SquareDungeonIcons()
    local castFrame = _G.ChallengesFrame
    local icons = castFrame and castFrame.DungeonIcons
    if type(icons) ~= "table" then
        return
    end
    for idx = 1, #icons do
        local frame = icons[idx]
        if frame and not frame:IsForbidden() and frame.Icon then
            wipe(_iconKeep)
            _iconKeep[frame.Icon] = true
            FadeRegions(frame, _iconKeep)
            frame.Icon:ClearAllPoints()
            frame.Icon:SetAllPoints(frame)
            local wsk = mod.WSkin
            if wsk and wsk.SquareIcon then
                if wsk.SquareIcon(frame.Icon, nil) and wsk.QualityBorder then
                    wsk.QualityBorder(frame, frame.Icon, 0, 0, 0)
                end
            elseif frame.Icon.SetTexCoord then
                frame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        end
    end
end

local _challengesHooked = false

local function Skin_Challenges()
    if not _G.ChallengesFrame then
        return
    end
    local castFrame = _G.ChallengesFrame
    -- ChallengesFrameMixin:Update rebuilds the icon row on show and on every
    -- C_MythicPlus data refresh (icons created after the panel-skin pass would
    -- otherwise stay round), so square from the updater.
    if not _challengesHooked and type(castFrame.Update) == "function" then
        _challengesHooked = true
        hooksecurefunc(castFrame, "Update", function()
            if SkinEnabled() then
                SquareDungeonIcons()
            end
        end)
    end
    SkinFinderPanel(castFrame, { noBg = true, noBorder = true })
    -- The M+ main-area scenic backdrop (ChallengesFrame.Background + an anon
    -- BG texture) defeated every ALPHA approach we tried -- Blizzard re-raises
    -- their alpha from paths we never caught. Disabling the whole BACKGROUND
    -- draw LAYER kills them regardless of alpha (Blizzard would have to
    -- re-ENABLE the layer to bring them back, which it doesn't). Re-asserted
    -- each pass as a belt-and-braces against a future re-enable.
    if castFrame.DisableDrawLayer then
        castFrame:DisableDrawLayer("BACKGROUND")
    end
    if _G.ChallengesFrameInset then
        FadeInset(_G.ChallengesFrameInset)
    end
    local kf = _G.ChallengesKeystoneFrame
    if kf then
        SkinFinderPanel(kf, { inset = true })
        if kf.StartButton then
            SkinButton(kf.StartButton)
        end
        if kf.CloseButton then
            SkinCloseButton(kf.CloseButton)
        end
    end
    SquareDungeonIcons()
end

-- PvP tab (PVPUIFrame, Blizzard_PVPUI -- separate LoD addon): the D&R
-- treatment mirrored. Category rail buttons share SkinCategoryButton; panels
-- stripped so the shell backdrop shows through.
local function PVPCategoryButton(idx)
    return _G.PVPQueueFrame and _G.PVPQueueFrame["CategoryButton" .. idx]
end

local function UpdatePVPCategorySelection()
    local sel = ResolveRailSelection(PVPCategoryButton, _pvpSel, _G.PVPQueueFrame)
    for idx = 1, 4 do
        local button = PVPCategoryButton(idx)
        local skinData = button and FFD[button]
        if skinData and skinData.selWash then
            skinData.selWash:SetShown((sel == idx or sel == button) and true or false)
        end
    end
end

local function Skin_PVP()
    local pvp = _G.PVPUIFrame
    if not pvp then
        return
    end
    -- The PvP rail lays out late: at Blizzard_PVPUI load (and even inside the
    -- tab-switch hooks) the category buttons can still report no geometry, so
    -- the one-shot full-width conversion has nothing to measure and skips --
    -- leaving stock anchors that hang the card overhang off the rail edge.
    -- Re-run one frame after the window shows, when layout is real.
    if not GetFFD(pvp).showHook then
        GetFFD(pvp).showHook = true
        pvp:HookScript("OnShow", function()
            C_Timer.After(0, function()
                if pvp:IsShown() and SkinEnabled() then
                    Skin_PVP()
                end
            end)
        end)
    end
    SkinFinderPanel(pvp, { noBg = true, noBorder = true })
    local pq = _G.PVPQueueFrame
    if pq then
        SkinFinderPanel(pq, { noBg = true, noBorder = true })
        for idx = 1, 4 do
            local b = PVPCategoryButton(idx)
            if b then
                SkinCategoryButton(b, { keepRing = true, onSelect = UpdatePVPCategorySelection })
            end
        end
        UpdatePVPCategorySelection()
    end
    -- Casual (Honor) panel.
    local hf = _G.HonorFrame
    if hf then
        SkinFinderPanel(hf, { noBg = true, noBorder = true })
        local insetPx = hf.Inset or _G.HonorFrameInset
        if insetPx then
            FadeInset(insetPx)
        end
        if hf.QueueButton then
            SkinButton(hf.QueueButton)
            LiftButton(hf.QueueButton)
        end
        if hf.TypeDropdown then
            SkinDropdown(hf.TypeDropdown)
        end
        local sfr = hf.SpecificScrollBox or hf.SpecificFrame
        local scrollBar = (sfr and sfr.ScrollBar) or hf.ScrollBar
        if scrollBar then
            SkinScrollBar(scrollBar)
        end
        if hf.BonusFrame then
            SkinFinderPanel(hf.BonusFrame, { noBg = true, noBorder = true })
        end
    end
    -- Rated (Conquest) panel.
    local castFrame = _G.ConquestFrame
    if castFrame then
        SkinFinderPanel(castFrame, { noBg = true, noBorder = true })
        local insetPx = castFrame.Inset or _G.ConquestFrameInset
        if insetPx then
            FadeInset(insetPx)
        end
        if castFrame.JoinButton then
            SkinButton(castFrame.JoinButton)
            LiftButton(castFrame.JoinButton)
        end
    end
    -- Training Grounds panel (PvP practice queue; mirrors the Honor panel).
    local tg = _G.TrainingGroundsFrame
    if tg then
        SkinFinderPanel(tg, { noBg = true, noBorder = true })
        local insetPx = tg.Inset or _G.TrainingGroundsFrameInset
        if insetPx then
            FadeInset(insetPx)
        end
        if tg.QueueButton then
            SkinButton(tg.QueueButton)
            LiftButton(tg.QueueButton)
        end
        if tg.TypeDropdown then
            SkinDropdown(tg.TypeDropdown)
        end
        local specInfo = tg.SpecificTrainingGroundList
        if specInfo then
            SkinFinderPanel(specInfo, { noBg = true, noBorder = true })
            local scrollBar = specInfo.ScrollBar or (specInfo.ScrollBox and specInfo.ScrollBox.ScrollBar)
            if scrollBar then
                SkinScrollBar(scrollBar)
            end
        end
        local bonus = tg.BonusTrainingGroundList
        if bonus then
            SkinFinderPanel(bonus, { noBg = true, noBorder = true })
            -- Leftover scenic art the panel sweep does not reach by region.
            if bonus.ShadowOverlay and bonus.ShadowOverlay.SetAlpha then
                bonus.ShadowOverlay:SetAlpha(0)
            end
            if bonus.WorldBattlesTexture and bonus.WorldBattlesTexture.SetAlpha then
                bonus.WorldBattlesTexture:SetAlpha(0)
            end
            if bonus.RandomTrainingGroundButton then
                SkinButton(bonus.RandomTrainingGroundButton)
            end
        end
    end
end

-- Selection/repaint hooks for the PvP tab; installable only once its addon
-- has loaded (the globals don't exist before Blizzard_PVPUI).
local _pvpHooksInstalled = false
local function InstallPVPHooks()
    if _pvpHooksInstalled then
        return
    end
    _pvpHooksInstalled = true
    if _G.PVPQueueFrame_SelectButton then
        hooksecurefunc("PVPQueueFrame_SelectButton", function(sel)
            -- Arg is an index on some builds, the button itself on others.
            if type(sel) == "number" or type(sel) == "table" then
                _pvpSel = sel
            end
            StripAgain()
            UpdatePVPCategorySelection()
        end)
    end
    if _G.PVPQueueFrame_ShowFrame then
        hooksecurefunc("PVPQueueFrame_ShowFrame", StripAgain)
    end
end

-- Full pass + re-strip; safe to call repeatedly (idempotent skinners).
local function RefreshAll()
    if not SkinEnabled() then
        return
    end
    Skin_PVEFrame()
    Skin_GroupFinder()
    Skin_LFGList()
    Skin_RaidFinder()
    Skin_Challenges()
    Skin_PVP()
    StripAgain()
end

-------------------------------------------------------------------------------
--  Hook installation. Repaint hooks keep the skin stable across tab switches
--  and category navigation; installed once.
-------------------------------------------------------------------------------
local _hooksInstalled = false
local function InstallHooks()
    if _hooksInstalled or not PVEFrame then
        return
    end
    _hooksInstalled = true
    -- Deferred so this runs on its own tick, after the click that opened the
    -- frame has finished, instead of inside that same execution chain.
    hooksecurefunc(PVEFrame, "Show", function()
        C_Timer.After(0, RefreshAll)
    end)
    if PVEFrame_ShowFrame then
        hooksecurefunc("PVEFrame_ShowFrame", function()
            C_Timer.After(0, function()
                RefreshAll()
                UpdateTabVisuals()
            end)
        end)
    end
    if PVEFrame_TabOnClick then
        hooksecurefunc("PVEFrame_TabOnClick", function()
            RefreshAll()
            UpdateTabVisuals()
        end)
    end
    if GroupFinderFrame_SelectGroupButton then
        hooksecurefunc("GroupFinderFrame_SelectGroupButton", function(index)
            if type(index) == "number" then
                _gfSelIndex = index
            end
            StripAgain()
            UpdateCategorySelection()
        end)
    end
    if GroupFinderFrameGroupButton_OnClick then
        hooksecurefunc("GroupFinderFrameGroupButton_OnClick", function()
            StripAgain()
            UpdateCategorySelection()
        end)
    end
    if LFGListCategorySelectionButton_OnClick then
        -- Selection wash is driven by the AddButton rebuild hook (fires on
        -- every pick); here we only re-flatten art after the click.
        hooksecurefunc("LFGListCategorySelectionButton_OnClick", StripAgain)
    end
    -- Blizzard's rewards updaters re-apply the questpaper background (LFD /
    -- Raid Finder / Scenario) and the Raid Finder role-row gradient on every
    -- rewards/role/raid update; one-shot fades never stick against them, so
    -- re-fade from the updaters themselves.
    if LFGRewardsFrame_UpdateFrame then
        hooksecurefunc("LFGRewardsFrame_UpdateFrame", function(parentFrame, _, background)
            if background and not issecretvalue(background) and background.SetAlpha then
                background:SetAlpha(0)
            end
            -- Reward tiles are re-filled from scratch on every one of these
            -- passes (SetItemButtonTexture re-shows the rings), so the skin has
            -- to ride the updater rather than being applied once when the panel
            -- is built.
            SkinRewardsFrame(parentFrame)
        end)
    end
    if RaidFinderQueueFrameRewards_UpdateFrame then
        hooksecurefunc("RaidFinderQueueFrameRewards_UpdateFrame", FadeRaidFinderArt)
    end
end

-------------------------------------------------------------------------------
--  QoL features. Independent of the skin toggle (a user may want either without
--  the dark style). Each self-gates on its own DB flag and costs nothing when
--  off. All reads here are of the addon's own data, the player's own character
--  data, or clean control APIs -- never per-result/member search data.
-------------------------------------------------------------------------------

-- REMEMBER SIGN-UP ROLES ------------------------------------------------------
-- Persists the Tank/Healer/DPS checkboxes you last applied with and restores
-- them when the sign-up dialog opens (intersected with the roles your spec can
-- actually fill, so it never checks an impossible role). Pure clean widget
-- state; reads/writes no search-result data.
local _restoringRoles = false

local function RememberRolesOn()
    return CludesUIDB and CludesUIDB.lfgRememberRoles == true
end

local function SaveAppRoles(dialog)
    if not (RememberRolesOn() and dialog and CludesUIDB) then
        return
    end
    local function chk(button)
        local c = button and button.CheckButton and button.CheckButton:GetChecked()
        if issecretvalue(c) then
            return nil
        end
        return c and true or false
    end
    local tank, healer, damager = chk(dialog.TankButton), chk(dialog.HealerButton), chk(dialog.DamagerButton)
    -- Any secret checked state means we cannot read what the user picked;
    -- keep the previous save rather than writing wrong roles.
    if tank == nil or healer == nil or damager == nil then
        return
    end
    CludesUIDB.lfgSavedRoles = {
        tank = tank,
        healer = healer,
        damager = damager,
    }
end

local function RestoreAppRoles(dialog)
    if _restoringRoles then
        return
    end
    if not (RememberRolesOn() and dialog and CludesUIDB and CludesUIDB.lfgSavedRoles) then
        return
    end
    if InCombatLockdown() then
        return
    end
    _restoringRoles = true
    pcall(function()
        local saved = CludesUIDB.lfgSavedRoles
        local function applyFn(button, wanted)
            local checkBtn = button and button.CheckButton
            if checkBtn and checkBtn:IsEnabled() then
                checkBtn:SetChecked(wanted and true or false)
            end
        end
        applyFn(dialog.TankButton, saved.tank)
        applyFn(dialog.HealerButton, saved.healer)
        applyFn(dialog.DamagerButton, saved.damager)
        -- Re-run Blizzard's role update so the Sign Up button reflects our
        -- restored selection. The reentry guard stops our own hook recursing.
        if LFGListApplicationDialog_UpdateRoles then
            LFGListApplicationDialog_UpdateRoles(dialog)
        end
    end)
    _restoringRoles = false
end

-- Install the role save/restore hooks once, only on first enable.
local _roleHooksInstalled = false
local function InstallRememberRolesHooks()
    if _roleHooksInstalled then
        return
    end
    local dialog = _G.LFGListApplicationDialog
    if not (dialog and LFGListApplicationDialog_UpdateRoles) then
        return
    end
    _roleHooksInstalled = true
    -- The dialog opens as: UpdateRoles(self) -> StaticPopupSpecial_Show(self)
    -- (which fires OnShow plus any Quick Signup auto-accept). The open-sequence
    -- UpdateRoles is the only one that runs while the dialog is still HIDDEN, so
    -- restoring there (a) applies BEFORE the dialog shows / auto-signs-up, and
    -- (b) never fights a user role click (clicks fire UpdateRoles while shown).
    hooksecurefunc("LFGListApplicationDialog_UpdateRoles", function(dlg)
        if _restoringRoles or not dlg then
            return
        end
        if dlg:IsShown() then
            return
        end
        RestoreAppRoles(dlg)
    end)
    for _, key in ipairs({ "TankButton", "HealerButton", "DamagerButton" }) do
        local button = dialog[key]
        local checkBtn = button and button.CheckButton
        if checkBtn then
            checkBtn:HookScript("OnClick", function()
                SaveAppRoles(dialog)
            end)
        end
    end
end

-- CHARACTER / PVEFRAME OVERLAP ------------------------------------------------ Stock
-- Blizzard has no docking relationship between CharacterFrame and PVEFrame (Dungeons &
-- Raids); both anchor near the same default screen position, so opening one while the
-- other is open overlaps them. Any addon that docks its own panel to PVEFrame's edge
-- is unaware of CharacterFrame, so that panel gets partially covered by CharacterFrame
-- in turn. PVEFrame is PROTECTED (it parents the LFGList
-- applicant viewer, which throws on tainted secret-value comparisons -- see
-- CludesUIQoL_Shifter.lua's SecureSetPoint), so it is never repositioned here;
-- CharacterFrame is not protected, so it docks beside PVEFrame instead. Reading
-- PVEFrame's position does not taint it -- only writing to it would. Independent of
-- reskinLFGMenu: a positioning fix, not part of the skin.
local PVE_DOCK_MARGIN = 4

local function CharacterFrameIsUserPinned()
    return CludesUIDB and CludesUIDB.shifterPositions and CludesUIDB.shifterPositions["CharacterFrame"] ~= nil
end

-- Third-party panels known to dock themselves beside PVEFrame with no awareness of
-- CharacterFrame (a Mythic+ profile panel, confirmed via /fstack). Checked by
-- name -- cheap and reliable -- instead of scanning every frame in the UI: that
-- approach kept missing the actual frame, once matched CharacterFrame's own child and
-- produced a circular anchor, and was slow enough on its own to cause a visible hitch.
-- Add another name here if a different addon is reported doing the same thing.
local KNOWN_PVE_COMPANIONS = { "RaiderIO_ProfileTooltip" }

local function FindOutermostFrame(pveFrame, side)
    local outFrame = pveFrame
    local pveScale = pveFrame:GetEffectiveScale() or 1
    local outerEdge = ((side == "right" and pveFrame:GetRight() or pveFrame:GetLeft()) or 0) * pveScale
    local pveTop, pveBottom = pveFrame:GetTop(), pveFrame:GetBottom()
    if not pveTop or not pveBottom then
        return outFrame, outerEdge
    end
    local topAbs, bottomAbs = pveTop * pveScale, pveBottom * pveScale

    for _, name in ipairs(KNOWN_PVE_COMPANIONS) do
        local checkBox = _G[name]
        if checkBox and checkBox:IsVisible() then
            local fLeft, fRight = checkBox:GetLeft(), checkBox:GetRight()
            local fTop, fBottom = checkBox:GetTop(), checkBox:GetBottom()
            if fLeft and fRight and fTop and fBottom then
                local fScale = checkBox:GetEffectiveScale() or 1
                local fLeftAbs, fRightAbs = fLeft * fScale, fRight * fScale
                local fTopAbs, fBottomAbs = fTop * fScale, fBottom * fScale
                if fTopAbs > bottomAbs and fBottomAbs < topAbs then
                    if side == "right" and fRightAbs > outerEdge then
                        outFrame, outerEdge = checkBox, fRightAbs
                    elseif side == "left" and fLeftAbs < outerEdge then
                        outFrame, outerEdge = checkBox, fLeftAbs
                    end
                end
            end
        end
    end
    return outFrame, outerEdge
end

-- Guards our own SetPoint call below from re-triggering itself through the
-- hooksecurefunc on CharacterFrame's own SetPoint (needed so a Shifter
-- scale change, which always ends by re-applying position, re-docks too).
local _dockingCharacterFrame = false

local function DockCharacter()
    if _dockingCharacterFrame then
        return
    end
    local castFrame = _G.CharacterFrame
    local pveFrame = PVEFrame
    if not castFrame or not pveFrame then
        return
    end
    if not castFrame:IsShown() or not pveFrame:IsShown() then
        return
    end
    -- No pin check here: PVEFrame is protected, so it can never get even the
    -- strata-only fallback Shifter gives its other managed windows (that
    -- write would taint it -- see CludesUIQoL_Shifter.lua). Repositioning
    -- CharacterFrame is the only way PVEFrame is ever kept from being buried
    -- under it, so this must run even when the user has Shifter-scaled or
    -- -pinned CharacterFrame -- their chosen SCALE is untouched, only the
    -- anchor point moves.

    local checkSkin = castFrame:GetEffectiveScale() or 1
    local ues = UIParent:GetEffectiveScale() or 1
    local wAbs = (castFrame:GetWidth() or 0) * checkSkin
    local leftFrame, leftEdgeAbs = FindOutermostFrame(pveFrame, "left")
    local rightFrame, rightEdgeAbs = FindOutermostFrame(pveFrame, "right")
    local leftRoom = leftEdgeAbs
    local rightRoom = (GetScreenWidth() or 0) * ues - rightEdgeAbs
    local dockLeft = leftRoom >= wAbs + PVE_DOCK_MARGIN * checkSkin or leftRoom >= rightRoom

    local targetPoint, targetRel, targetRelPoint, targetX, targetY, expectedEdgeAbs
    if dockLeft then
        targetPoint, targetRel, targetRelPoint, targetX, targetY =
            "TOPRIGHT", leftFrame, "TOPLEFT", -PVE_DOCK_MARGIN, 0
        expectedEdgeAbs = leftEdgeAbs - PVE_DOCK_MARGIN * checkSkin
    else
        targetPoint, targetRel, targetRelPoint, targetX, targetY =
            "TOPLEFT", rightFrame, "TOPRIGHT", PVE_DOCK_MARGIN, 0
        expectedEdgeAbs = rightEdgeAbs + PVE_DOCK_MARGIN * checkSkin
    end

    -- PVEFrame's own internal layout re-anchors it (and a docked companion) repeatedly
    -- while it settles, and Shifter re-applies CharacterFrame's own saved/temp position
    -- on every scale step -- both re-trigger this constantly. Skip the write only when
    -- CharacterFrame's ACTUAL current edge already matches where we'd put it -- not by
    -- reading GetPoint() back (SetClampedToScreen can silently rewrite the stored
    -- anchor once it adjusts a frame to fit on screen) and not by caching our own last
    -- decision (Shifter's scale step can reposition CharacterFrame away from our dock
    -- via ITS OWN saved-position math without leftFrame/rightFrame/ dockLeft ever
    -- changing, which a decision-only cache can't detect).
    local curEdgeAbs = (dockLeft and (castFrame:GetRight() or 0) or (castFrame:GetLeft() or 0)) * checkSkin
    if math.abs(curEdgeAbs - expectedEdgeAbs) < 1 then
        return
    end

    _dockingCharacterFrame = true
    -- Shifter installs its own hooksecurefunc(CharacterFrame, "SetPoint", ...) (on
    -- every frame it manages, independent of the docking-companions system) that
    -- re-applies a saved/temp Shifter position on every SetPoint call. Once a scale
    -- action has saved ANY position for CharacterFrame, that hook fires synchronously
    -- right after ours and snaps it straight back -- undoing this dock entirely.
    -- _shIgnoreSP is the exact flag Shifter sets around its OWN writes for the same
    -- reason; set it here too so our write isn't immediately reverted. This hook can
    -- itself fire NESTED inside a SetPoint call Shifter's own ApplyPosition made (with
    -- the flag already true) -- restore the PRIOR value rather than hardcoding false,
    -- or we'd clear it while still nested inside that call, letting Shifter's own
    -- SetPoint hook see it false and recurse.
    local shifterFFD = CludesUI._GetFFD(castFrame)
    local prevIgnoreSP = shifterFFD and shifterFFD._shIgnoreSP
    if shifterFFD then
        shifterFFD._shIgnoreSP = true
    end
    castFrame:ClearAllPoints()
    castFrame:SetPoint(targetPoint, targetRel, targetRelPoint, targetX, targetY)
    if shifterFFD then
        shifterFFD._shIgnoreSP = prevIgnoreSP
    end
    _dockingCharacterFrame = false
end

-- Blizzard's native anchor, captured before we ever dock, so it can be
-- restored once PVEFrame is no longer there to dock beside.
local _defaultCharacterPoint

local function CaptureDefaultCharacterPoint()
    if _defaultCharacterPoint or not _G.CharacterFrame then
        return
    end
    local anchorPoint, relativeTo, relativePoint, posX, posY = _G.CharacterFrame:GetPoint(1)
    if anchorPoint then
        _defaultCharacterPoint = { anchorPoint, relativeTo, relativePoint, posX, posY }
    end
end

local function RestoreDefaultCharacterPoint()
    if not _defaultCharacterPoint or not _G.CharacterFrame then
        return
    end
    if CharacterFrameIsUserPinned() then
        return
    end
    _G.CharacterFrame:ClearAllPoints()
    _G.CharacterFrame:SetPoint(unpack(_defaultCharacterPoint))
end

local _pveDockHooksInstalled = false
local function InstallPVEDockHooks()
    if _pveDockHooksInstalled or not PVEFrame or not _G.CharacterFrame then
        return
    end
    _pveDockHooksInstalled = true

    CaptureDefaultCharacterPoint()

    -- Direct everywhere: DockCharacterFrame already no-ops safely if either frame isn't
    -- shown yet, so there's no unsettled-state risk to defer for, and
    -- FindOutermostFrame is cheap now (named lookups, not a frame scan). Deferring a
    -- SetPoint-triggered re-dock to next frame (e.g. if Blizzard's layout system
    -- repositions CharacterFrame again after it's already rendering) is exactly what
    -- shows one frame at the wrong position before snapping into place. Blizzard's
    -- panel manager treats CharacterFrame and PVEFrame as one managed group and
    -- repositions CharacterFrame itself whenever PVEFrame opens; the SetPoint hook
    -- below re-docks it, and the dock's own re-entry guard (plus Shifter's) keeps
    -- that from looping. No field is written on CharacterFrame: the managed-frame
    -- opt-out flag is read only by the HUD's managed frame system, never for panels.
    _G.CharacterFrame:HookScript("OnShow", DockCharacter)
    hooksecurefunc(_G.CharacterFrame, "SetPoint", DockCharacter)

    PVEFrame:HookScript("OnShow", DockCharacter)
    hooksecurefunc(PVEFrame, "SetPoint", DockCharacter)
    PVEFrame:HookScript("OnHide", function()
        if _G.CharacterFrame and _G.CharacterFrame:IsShown() then
            RestoreDefaultCharacterPoint()
        end
    end)
end

-- INIT. Idempotent + existence-guarded; safe to call on PLAYER_LOGIN and again on
-- Blizzard_GroupFinder load (frames/globals only exist after that addon). Each
-- feature's hooks are installed ONLY when that feature is enabled, so a disabled
-- feature attaches no hooks and creates no frames.
CludesUI._GroupFinder_InitQoL = function()
    if RememberRolesOn() then
        InstallRememberRolesHooks()
    end
    InstallPVEDockHooks()
end

-- Called by the options toggle when a QoL flag flips: installs that feature's
-- hooks lazily on first enable. No reload needed.
CludesUI._GroupFinder_RefreshQoL = function()
    if RememberRolesOn() then
        InstallRememberRolesHooks()
    end
end

-------------------------------------------------------------------------------
--  Boot orchestration. PVEFrame lives in Blizzard_GroupFinder (load-on-demand);
--  ChallengesFrame in Blizzard_ChallengesUI. Skin on each addon's ADDON_LOADED,
--  install repaint hooks once, and sweep at login.
-------------------------------------------------------------------------------
local function DoSkinPass()
    if not Theme.bgR then
        ResolveTheme()
    end
    RefreshAll()
    InstallHooks()
end

local ON_ADDON = {
    Blizzard_GroupFinder = function()
        DoSkinPass()
    end,
    Blizzard_ChallengesUI = function()
        if not SkinEnabled() then
            return
        end
        if not Theme.bgR then
            ResolveTheme()
        end
        Skin_Challenges()
        StripAgain()
    end,
    Blizzard_PVPUI = function()
        if not SkinEnabled() then
            return
        end
        if not Theme.bgR then
            ResolveTheme()
        end
        Skin_PVP()
        InstallPVPHooks()
        StripAgain()
    end,
}

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, evt, name)
    if evt == "PLAYER_LOGIN" then
        ResolveTheme()
        if SkinEnabled() then
            DoSkinPass()
        end
        if CludesUI._GroupFinder_InitQoL then
            CludesUI._GroupFinder_InitQoL()
        end
    elseif evt == "ADDON_LOADED" then
        local func = ON_ADDON[name]
        if func and SkinEnabled() then
            func()
        end
        -- QoL init also needs Blizzard_GroupFinder to exist; (re)try on its load.
        if name == "Blizzard_GroupFinder" and CludesUI._GroupFinder_InitQoL then
            CludesUI._GroupFinder_InitQoL()
        end
    end
end)
