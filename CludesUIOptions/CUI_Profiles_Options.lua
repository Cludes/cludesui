if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_Profiles_Options.lua -- Global Settings > Profiles (and its Presets
--  subpage). It registers nothing: the Global Settings module
--  (CUI__General_Options.lua) dispatches its builder.
-------------------------------------------------------------------------------
local PanelPx = CUI.PanelPP

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame. The profiles root is kept for the session
-- (PROFILES_ROOT owns it), so everything built on it is pooled.
local CreateFrame = CUI._Pool.CreateFrame
local PoolKept, PoolBegin, PoolManaged = CUI._Pool.Kept, CUI._Pool.Begin, CUI._Pool.Managed
local PoolGen, PoolIsIdle = CUI._Pool.Gen, CUI._Pool.IsIdle
local PROFILES_ROOT = {}

-- A deferred callback's frame is still in the dress it had when the callback
-- was scheduled (gen = PoolGen(obj) then): a rebuild dresses the same pooled
-- frames again, so a callback from before it must leave them alone.
local function SameDress(obj, gen) return PoolGen(obj) == gen and not PoolIsIdle(obj) end

---------------------------------------------------------------------------
--  Profiles page
---------------------------------------------------------------------------

-- The UI scale an imported string is measured against: the player's pixel
-- perfect scale when they set one, else the game's. Two scales count as the
-- same within 2%.
local function MyScale() return CludesUIDB and CludesUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1 end
local function Pct(scale) return math.floor(scale * 100 + 0.5) end
local function ScalesDiffer(a, b) return math.abs(a - b) > 0.02 end

-- The red warning for a decoded string made on a different UI scale or
-- resolution (nil when both match). skipScale: the player already took the
-- string's scale, so only the resolution can still be off.
local function BuildScaleWarning(bundle, skipScale)
    local meta = bundle and bundle.meta
    if not meta then return nil end
    local lines = {}
    local mine, theirs = MyScale(), meta.cuiScale or meta.uiScale
    if not skipScale and theirs and ScalesDiffer(mine, theirs) then
        lines[#lines + 1] =
            CUI.Lf("UI Scale Issue: Profile was made at %1$d%%, yours is %2$d%%", Pct(theirs), Pct(mine))
    end
    local w, h = GetPhysicalScreenSize()
    w, h = w and math.floor(w) or 0, h and math.floor(h) or 0
    local madeW, madeH = meta.screenW or 0, meta.screenH or 0
    if madeW > 0 and madeH > 0 and (w ~= madeW or h ~= madeH) then
        lines[#lines + 1] = CUI.Lf(
            "Resolution Issue: Profile was made at %1$dx%2$d, yours is %3$dx%4$d",
            madeW,
            madeH,
            w,
            h
        )
    end
    if #lines == 0 then return nil end
    return CUI.L("WARNING: Frame positions may be off.") .. "\n" .. table.concat(lines, "\n")
end

-- Between choosing a string or preset and the import options: a string that
-- carries another UI scale asks once whether to take it. cont(takeScale)
-- always runs (Escape and a click outside count as Keep Mine), so the page
-- change can never stall; with true the options page drops its scale line.
local function MaybeConfirmUIScale(bundle, cont)
    local data = bundle and bundle.data
    local theirs = data and type(data.uiScale) == "number" and data.uiScale or nil
    local mine = MyScale()
    if not theirs or not ScalesDiffer(mine, theirs) then
        cont(false)
        return
    end
    CUI:ShowConfirmPopup({
        title = CUI.L("UI Scale Mismatch"),
        message = CUI.Lf(
            "This profile was made at %1$d%% UI scale; yours is %2$d%%. Change your UI scale to match the imported profile? This will show all profiles at this scale as UI Scale is not a per-profile setting, but can be changed at any time back to your original value.",
            Pct(theirs),
            Pct(mine)
        ),
        confirmText = CUI.L("Match Scale"),
        cancelText = CUI.L("Keep Mine"),
        onConfirm = function() cont(true) end,
        onCancel = function() cont(false) end,
    })
end

-- Profile import/export module lists: shared row geometry.
local SIDE_PAD, ROW_H_A, CHK_SZ, STATUS_W = 26, 48, 18, 70
local INCLUDE_CENTER_X = -(SIDE_PAD + STATUS_W + 30 + CHK_SZ / 2)

-- The one-line description under each module's name in the Import and
-- Export lists.
local ADDON_DESCS = {
    CludesUIActionBars = "Modern action bars built for performance and clarity.",
    CludesUINameplates = "Clean, lightweight nameplates with endless customization.",
    CludesUIUnitFrames = "Simple unit frames with a modern visual style.",
    CludesUICooldownManager = "A CDM replacement focused on performance, customizations and alerts.",
    CludesUIResourceBars = "Custom Resource Bars with thresholds, hash lines and more.",
    CludesUIRaidFrames = "Incredibly light performance, modern raid and party frames with endless flexibility.",
    CludesUIAuraBuffReminders = "Simple raid buff, auras, consumables and talent reminders.",
    CludesUIQoL = "Lightweight quality of life tools and enhancements.",
    CludesUIDragonRiding = "Skyriding HUD with speed, vigor and second wind tracking.",
    CludesUIBlizzardSkin = "Clean and beautiful visual refreshes for Blizzard UI elements.",
    CludesUIFriends = "A modern friends list with built-in organization tools.",
    CludesUIMythicTimer = "Mythic+ timer, targeted spell bars, and standalone cast bars.",
    CludesUIQuestTracker = "A clean, updated reskin of Blizzard's Objective Tracker.",
    CludesUIMinimap = "A new age minimap with clean styling and square layout options.",
    CludesUIDamageMeters = "Lightweight damage meters with simple but powerful customization.",
    CludesUIChat = "Modern chat enhancements with useful utilities.",
    CludesUIBags = "A beautiful visual refresh of Blizzard Bags with intuitive organization.",
    CludesUIQuickdraw = "Hold a key to open a menu of actions; point or scroll to choose, release to fire.",
}

-- A texture drawn at its exact size (no snapping to the pixel grid).
local function Unsnapped(texture)
    if texture.SetSnapToPixelGrid then
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
end

-- A checkbox: the dark rounded box, its border and the accent tick (shown
-- while on). exact draws box and tick off the pixel grid (the module rows).
-- Returns box, tick, border, background.
local function CheckBox(parent, exact)
    local EG = CUI.CLUDES_GREEN
    local boxFrame = CreateFrame("Frame", nil, parent)
    boxFrame:SetSize(CHK_SZ, CHK_SZ)
    local bg = boxFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.114, 0.106, 0.099, 1)
    if exact then Unsnapped(bg) end
    local border = CUI.MakeRoundedBorder(boxFrame, 0.224, 0.215, 0.207, 0.6, bg)
    local tick = boxFrame:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 3, -3)
    tick:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -3, 3)
    tick:SetColorTexture(EG.r, EG.g, EG.b, 1)
    CUI.RoundBody(boxFrame, tick, 1)
    if exact then Unsnapped(tick) end
    return boxFrame, tick, border, bg
end

-- A module list row's look per state: name and description alpha, the tick,
-- the box's alpha. Included rows also tint the box's border green.
local ROW_LOOK = {
    blocked = { name = 0.30, desc = 0.15, tick = false, box = 0.3 },
    included = { name = 0.9, desc = 0.30, tick = true, box = 1 },
    skipped = { name = 0.50, desc = 0.20, tick = false, box = 1 },
}

-- One module-list checkbox row. o: active (clickable), inactiveText +
-- inactiveColor {r,g,b,a}, visuals (repaint list), onToggle(apply) after
-- the value flips, linked() -> members, own key, display map, linkedTip(list),
-- blockedTip (hover text on inactive rows; nil = silent).
local function BuildAddonListRow(scrollChild, i, entry, fullWidth, o)
    local EG = CUI.CLUDES_GREEN
    local lineFrame = CreateFrame("Frame", nil, scrollChild)
    lineFrame:SetSize(fullWidth, ROW_H_A)
    lineFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_H_A)
    -- Alternate rows a shade darker.
    local rowBg = lineFrame:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    rowBg:SetColorTexture(0, 0, 0, (i % 2 == 0) and 0.12 or 0.06)

    local nameFs = CUI.MakeFont(lineFrame, 13, nil, 1, 1, 1, 0.9)
    nameFs:SetPoint("TOPLEFT", lineFrame, "TOPLEFT", SIDE_PAD, -10)
    nameFs:SetPoint("RIGHT", lineFrame, "RIGHT", -(CHK_SZ + STATUS_W + SIDE_PAD * 2 + 20), 0)
    nameFs:SetJustifyH("LEFT")
    nameFs:SetWordWrap(false)
    nameFs:SetText(CUI.L(entry.display))

    local descFs = CUI.MakeFont(lineFrame, 11, nil, 1, 1, 1, 0.30)
    descFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -5)
    descFs:SetPoint("RIGHT", nameFs, "RIGHT", 0, 0)
    descFs:SetJustifyH("LEFT")
    descFs:SetWordWrap(false)
    descFs:SetText(CUI.L(entry.desc))

    local statusFs = CUI.MakeFont(lineFrame, 11, nil, 1, 1, 1, 0.40)
    statusFs:SetPoint("RIGHT", lineFrame, "RIGHT", -SIDE_PAD, 0)
    statusFs:SetJustifyH("RIGHT")

    -- The box sits under the Include column header.
    local boxFrame, tick, boxBorder, boxBg = CheckBox(lineFrame, true)
    boxFrame:SetPoint("CENTER", lineFrame, "RIGHT", INCLUDE_CENTER_X, 0)

    local function PaintRowState()
        local state = not o.active and "blocked" or (entry.getVal() and "included" or "skipped")
        local look = ROW_LOOK[state]
        nameFs:SetAlpha(look.name)
        descFs:SetAlpha(look.desc)
        tick:SetShown(look.tick)
        boxBg:SetAlpha(look.box)
        if state == "blocked" then
            local color = o.inactiveColor
            statusFs:SetText(o.inactiveText)
            statusFs:SetTextColor(color[1], color[2], color[3], color[4])
        elseif state == "included" then
            boxBorder:SetColor(EG.r, EG.g, EG.b, 0.15)
            statusFs:SetText(CUI.L("Ready"))
            statusFs:SetTextColor(0.196, 0.737, 0.325, 1)
        else
            boxBorder:SetColor(0.224, 0.215, 0.207, 0.6)
            statusFs:SetText(CUI.L("Skipped"))
            statusFs:SetTextColor(1, 1, 1, 0.35)
        end
    end
    PaintRowState()
    o.visuals[#o.visuals + 1] = PaintRowState

    local hoverTex = lineFrame:CreateTexture(nil, "ARTWORK")
    hoverTex:SetAllPoints()
    hoverTex:SetColorTexture(1, 1, 1, 0.05)
    hoverTex:Hide()

    if not o.active then
        -- Inactive: the row swallows the mouse, and explains itself if it can.
        local blockFrame = CreateFrame("Frame", nil, lineFrame)
        blockFrame:SetAllPoints()
        blockFrame:SetFrameLevel(lineFrame:GetFrameLevel() + 5)
        blockFrame:EnableMouse(true)
        local tip = o.blockedTip
        blockFrame:SetScript("OnEnter", function()
            if tip then
                hoverTex:Show()
                CUI.ShowWidgetTooltip(lineFrame, tip)
            end
        end)
        blockFrame:SetScript("OnLeave", function()
            if tip then
                hoverTex:Hide()
                CUI.HideWidgetTooltip()
            end
        end)
        return
    end
    local clickBtn = CreateFrame("Button", nil, lineFrame)
    clickBtn:SetAllPoints(lineFrame)
    clickBtn:SetFrameLevel(lineFrame:GetFrameLevel() + 2)
    clickBtn:SetScript("OnClick", function()
        entry.setVal(not entry.getVal())
        o.onToggle(PaintRowState)
    end)
    clickBtn:SetScript("OnEnter", function()
        hoverTex:Show()
        if not entry.getVal() then nameFs:SetAlpha(0.75) end
        -- The modules this one carries along (nothing couples while layout is off).
        local members, own, display = o.linked()
        if not members then return end
        local names = {}
        for moduleFolder in pairs(members) do
            if moduleFolder ~= own then
                names[#names + 1] = CUI.L(display[moduleFolder] or moduleFolder)
            end
        end
        if #names > 0 then
            table.sort(names)
            CUI.ShowWidgetTooltip(lineFrame, o.linkedTip(table.concat(names, ", ")))
        end
    end)
    clickBtn:SetScript("OnLeave", function()
        hoverTex:Hide()
        if not entry.getVal() then nameFs:SetAlpha(0.50) end
        CUI.HideWidgetTooltip()
    end)
end

-- Done-style button hover: label and border alpha fade 0.7 -> 1 over 0.1s.
-- Returns reset(), which snaps the fade back to idle.
local function MakeAccentFade(button, caption, brd)
    local EG = CUI.CLUDES_GREEN
    local lerp = CUI.lerp
    local FADE = 0.1
    local t, goal = 0, 0
    local function Paint(at)
        local a = lerp(0.7, 1, at)
        caption:SetTextColor(EG.r, EG.g, EG.b, a)
        brd:SetColor(EG.r, EG.g, EG.b, a)
    end
    local function Step(self, elapsed)
        local rising = goal == 1
        t = t + (rising and 1 or -1) * (elapsed / FADE)
        if (rising and t >= 1) or (not rising and t <= 0) then
            t = goal
            self:SetScript("OnUpdate", nil)
        end
        Paint(t)
    end
    local function Toward(g)
        return function(self)
            goal = g
            self:SetScript("OnUpdate", Step)
        end
    end
    button:SetScript("OnEnter", Toward(1))
    button:SetScript("OnLeave", Toward(0))
    return function()
        t, goal = 0, 0
        Paint(0)
    end
end
-- The current specialization's ID (nil while the client has none yet).
local function CurrentSpecID()
    local si = C_SpecializationInfo.GetSpecialization() or 0
    return si and si > 0 and C_SpecializationInfo.GetSpecializationInfo(si) or nil
end

-- Switches to a stored profile and refreshes every module (budgeted: a manual
-- switch, sliced by the watchdog). afterSwitch runs between the two. A profile
-- that brings another font, window skins or style only takes full effect after
-- a reload, so that asks for one; returns true when it asked.
local function SwitchProfileAndAsk(label, profile, afterSwitch)
    local font = CUI.ProfileChangesFont(profile)
    local skins = CUI.ProfileChangesWindowSkins(profile)
    local style = CUI.ProfileChangesStyle(profile)
    CUI.SwitchProfile(label)
    if afterSwitch then afterSwitch() end
    CUI.RefreshAllAddons(true)
    if not (font or skins or style) then return false end
    CUI:ShowConfirmPopup({
        title = CUI.L("Reload Required"),
        message = font and CUI.L("Font changed. A UI reload is needed to apply the new font.")
            or skins and CUI.L(
                "Window skins changed for this profile. A UI reload is needed to apply them."
            )
            or CUI.L("Style changed for this profile. A UI reload is needed to apply it."),
        confirmText = CUI.L("Reload Now"),
        cancelText = CUI.L("Later"),
        reload = true,
    })
    return true
end

-- A profile's keybind popup: built on its first open and kept across page
-- builds; each open points it at that profile (ShowProfileKeybindPopup).
local profileKeybindPopup

function _G._CUI_BuildProfilesPage(pageName, parent, yOffset)
    local W = CUI.Widgets
    local y = yOffset
    local _, h
    local FONT = CUI.EXPRESSWAY
    local EG = CUI.CLUDES_GREEN
    local MEDIA = "Interface\\AddOns\\CludesUI\\media\\"

    -- Safety net: the active profile follows the current spec's assignment
    -- (spec info can be missing at login, so it may not have switched then).
    do
        local sid = CurrentSpecID()
        local assigned = sid and CUI.GetSpecProfile(sid)
        if assigned and assigned ~= CUI.GetActiveProfileName() then
            local _, profileList = CUI.GetProfileList()
            if profileList and profileList[assigned] then
                SwitchProfileAndAsk(assigned, profileList[assigned])
            end
        end
    end

    if parent then parent._showRowDivider = false end

    -- Built on the scroll frame itself, not its scroll child.
    local scrollFrame = CUI._scrollFrame
    if not scrollFrame then return 0 end

    -- One root for the session: each build dresses it again, and its previous
    -- contents reset to new first (the reset hides whatever they showed).
    local root = PoolKept(PROFILES_ROOT, "root", "Frame", scrollFrame)
    root:SetAllPoints(scrollFrame)
    root:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
    CUI._profilesRoot = root

    -- Three pages over the root, one shown at a time: the profiles list, the
    -- import options and the paste box.
    local function Page(shown)
        local page = CreateFrame("Frame", nil, root)
        page:SetAllPoints(root)
        page:SetFrameLevel(root:GetFrameLevel())
        if not shown then page:Hide() end
        return page
    end
    local mainPage, importView, pastePage = Page(true), Page(false), Page(false)
    parent = mainPage
    y = -10

    -- Plain buttons: the wide button's colours with the dropdowns' white
    -- border (rest and hover alpha).
    local PROF_BTN_COLOURS = { unpack(CUI.WB_COLOURS, 1, 24) }
    for i, value in ipairs({ 1, 1, 1, CUI.DD_BRD_A, 1, 1, 1, CUI.DD_BRD_HA }) do
        PROF_BTN_COLOURS[8 + i] = value
    end
    -- Accent buttons: background, hover background, border, hover border and
    -- text, each the accent at a strength and alpha; white hover text.
    local ACCENT_BTN_COLOURS = {}
    for _, step in ipairs({ { 0.15, 0.85 }, { 0.22, 0.95 }, { 1, 0.35 }, { 1, 0.65 }, { 1, 0.90 } }) do
        local m = step[1]
        for _, value in ipairs({ EG.r * m, EG.g * m, EG.b * m, step[2] }) do
            ACCENT_BTN_COLOURS[#ACCENT_BTN_COLOURS + 1] = value
        end
    end
    for _ = 1, 4 do
        ACCENT_BTN_COLOURS[#ACCENT_BTN_COLOURS + 1] = 1
    end

    _, h = W:Spacer(parent, y, 10)
    y = y - h

    -- A dropdown button (the profile and spec pickers): label clipped to one
    -- line left of the arrow; hover paints it with the dropdown colours.
    local function MakeDropdown(parentFrame, w, ddH, getLabel)
        local button = CreateFrame("Button", nil, parentFrame)
        PanelPx.Size(button, w, ddH)
        button:SetFrameLevel(parentFrame:GetFrameLevel() + 2)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_A)
        local brd = CUI.MakeRoundedBorder(button, 1, 1, 1, CUI.DD_BRD_A, bg)
        -- The resting alpha is the text colour's, the channel the hover
        -- colours write, so a hover and leave land back on it.
        local caption = CUI.MakeFont(button, 13, nil, 1, 1, 1, CUI.DD_TXT_A)
        caption:SetJustifyH("LEFT")
        caption:SetWordWrap(false)
        caption:SetMaxLines(1)
        caption:SetPoint("LEFT", button, "LEFT", 12, 0)
        local arrow = CUI.MakeDropdownArrow(button, 12, PanelPx)
        caption:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
        caption:SetText(getLabel())
        -- RD_DD_COLOURS: background, hover background, border, hover border,
        -- text, hover text (four values each).
        local cfg = CUI.RD_DD_COLOURS
        local function Paint(hot)
            local o = hot and 4 or 0
            caption:SetTextColor(cfg[17 + o], cfg[18 + o], cfg[19 + o], cfg[20 + o])
            brd:SetColor(cfg[9 + o], cfg[10 + o], cfg[11 + o], cfg[12 + o])
            bg:SetColorTexture(cfg[1 + o], cfg[2 + o], cfg[3 + o], cfg[4 + o])
        end
        button:SetScript("OnEnter", function() Paint(true) end)
        button:SetScript("OnLeave", function() Paint(false) end)
        button._getLabel = getLabel
        return button, caption, bg, brd, Paint
    end

    -- One menu per dropdown button, kept with the button: a build that dresses
    -- the button again dresses its menu again too. A press outside both closes it.
    local function MakeDropdownMenu(anchor, w)
        local dropMenu = PoolKept(anchor, "profilesMenu", "Frame", UIParent)
        dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        dropMenu:SetFrameLevel(200)
        dropMenu:SetClampedToScreen(true)
        dropMenu:SetSize(w, 4)
        dropMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        dropMenu:Hide()
        local bg = dropMenu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, 0.98)
        CUI.MakeRoundedBorder(dropMenu, 1, 1, 1, CUI.DD_BRD_A, bg, nil, true)
        local function WatchOutside(m)
            local away = not anchor:IsMouseOver() and not m:IsMouseOver()
            if away and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
                m:Hide()
            end
        end
        dropMenu:SetScript("OnShow", function(self)
            -- On UIParent, drawn at the panel's scale.
            self:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
            self:SetScript("OnUpdate", WatchOutside)
        end)
        dropMenu:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
        return dropMenu
    end

    -- Hoisted so the import callback can update it
    local ddLabel
    -- After a profile was deleted, renamed or added: the dropdown shows the
    -- active one and every page rebuilds.
    local function ShowProfileChange()
        ddLabel:SetText(CUI.GetActiveProfileName())
        CUI:InvalidatePageCache()
        CUI:RefreshPage(true)
    end

    -------------------------------------------------------------------
    --  Shared helpers
    -------------------------------------------------------------------

    local ShowImportPage -- forward declaration (defined after import page builder)

    -- The keybind popup (made on first use, then kept): a screen dimmer that
    -- closes it on a click outside, the profile's keybind button, a hint line.
    local function BuildKeybindPopup()
        local shade = CreateFrame("Frame", nil, UIParent)
        shade:SetFrameStrata("FULLSCREEN_DIALOG")
        shade:SetFrameLevel(100)
        shade:SetAllPoints(UIParent)
        shade:EnableMouse(true)
        shade:EnableMouseWheel(true)
        shade:SetScript("OnMouseWheel", function() end)
        shade:Hide()
        local dimTex = shade:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints()
        dimTex:SetColorTexture(0, 0, 0, 0.25)

        local dialog = CreateFrame("Frame", nil, shade)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(shade:GetFrameLevel() + 10)
        dialog:SetSize(320, 130)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        dialog:EnableMouse(true)
        dialog:SetClampedToScreen(true)
        dialog._dimmer = shade
        shade:SetScript("OnMouseDown", function()
            if not dialog:IsMouseOver() then shade:Hide() end
        end)

        local popBg = dialog:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints()
        popBg:SetColorTexture(0.062, 0.070, 0.082, 0.97)
        CUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.20, popBg)
        local title = CUI.MakeFont(dialog, 14, nil, 1, 1, 1)
        title:SetPoint("TOP", dialog, "TOP", 0, -14)
        dialog._title = title

        -- Reads and writes the profile the popup was last opened for.
        local kbBtn, kbRefresh = CUI.BuildKeybindButton(dialog, {
            w = 160,
            h = 30,
            font = 13,
            get = function() return CUI.GetProfileKeybind(dialog._profileName) end,
            set = function(value) CUI.SetProfileKeybind(dialog._profileName, value) end,
        })
        kbBtn:SetPoint("CENTER", dialog, "CENTER", 0, -2)
        dialog._kbRefresh = kbRefresh
        local hint = CUI.MakeFont(dialog, 10, nil, 1, 1, 1, 0.35)
        hint:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 12)
        hint:SetText(CUI.L("Left-click to set  |  Right-click to unbind  |  Esc to close"))

        -- kbBtn's own OnHide cancels a capture in progress.
        dialog:SetScript("OnHide", function()
            if dialog._dimmer then dialog._dimmer:Hide() end
        end)
        -- It sits on UIParent, so it closes with the panel, which closes as
        -- combat starts: a screen-wide dimmer and an armed key capture never
        -- stay up into combat.
        CUI:RegisterOnHide(function()
            if shade:IsShown() then shade:Hide() end
        end)
        CUI.PopupTakeKeys(dialog, shade)
        -- Escape closes it, unless the button is capturing (it then owns the keys).
        dialog:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then return end
            local close = key == "ESCAPE" and not kbBtn:IsKeyboardEnabled()
            self:SetPropagateKeyboardInput(not close)
            if close then shade:Hide() end
        end)
        return dialog
    end

    local function ShowProfileKeybindPopup(profileName)
        local dialog = profileKeybindPopup
        if not dialog then
            dialog = BuildKeybindPopup()
            profileKeybindPopup = dialog
        elseif dialog._dimmer:IsShown() then
            -- Still open: closed first, cancelling a capture in progress.
            dialog._dimmer:Hide()
        end
        dialog._profileName = profileName
        dialog._title:SetText(CUI.Lf("Keybind: %1$s", profileName))
        dialog._kbRefresh()
        dialog:Show()
        dialog._dimmer:Show()
    end

    -- A button's border flashes red, fading back to its resting white over 0.7s.
    local function BuildErrorFlash(button, brd)
        local flashFrame = CreateFrame("Frame", nil, button)
        flashFrame:Hide()
        local lerp = CUI.lerp
        local DUR = 0.7
        local elapsed = 0
        local function Paint(t)
            brd:SetColor(lerp(0.9, 1, t), lerp(0.15, 1, t), lerp(0.15, 1, t), lerp(0.7, CUI.DD_BRD_A, t))
        end
        flashFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= DUR then
                self:Hide()
                brd:SetColor(1, 1, 1, CUI.DD_BRD_A)
                return
            end
            Paint(elapsed / DUR)
        end)
        return function()
            elapsed = 0
            Paint(0)
            flashFrame:Show()
        end
    end

    -- A subpage starting over: what it held goes (pooled frames reset to be
    -- dressed again; on a page that is no pool host, children dropped).
    local function ClearPage(page)
        if PoolManaged(page) then
            PoolBegin(page)
            return
        end
        for _, child in ipairs({ page:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end
    end

    -- A subpage's header: the Back button at its top left (back to the
    -- profiles list) and its centred title. Returns the button's height.
    local function SubpageHeader(page, pad, top, title)
        local BACK_W, BACK_H = 80, 32
        local backBtn = CreateFrame("Button", nil, page)
        PanelPx.Size(backBtn, BACK_W, BACK_H)
        PanelPx.Point(backBtn, "TOPLEFT", page, "TOPLEFT", pad, top)
        backBtn:SetFrameLevel(page:GetFrameLevel() + 2)
        local backBg = backBtn:CreateTexture(nil, "BACKGROUND")
        backBg:SetAllPoints()
        backBg:SetColorTexture(0.062, 0.070, 0.082, 0.50)
        local backBrd = CUI.MakeRoundedBorder(backBtn, 1, 1, 1, 0.12, backBg)
        local backIcon = backBtn:CreateTexture(nil, "ARTWORK")
        backIcon:SetSize(14, 14)
        PanelPx.Point(backIcon, "LEFT", backBtn, "LEFT", 10, 0)
        backIcon:SetTexture(MEDIA .. "icons\\cui-arrow-left.png")
        backIcon:SetVertexColor(EG.r, EG.g, EG.b)
        backIcon:SetAlpha(0.6)
        Unsnapped(backIcon)
        local backLbl = CUI.MakeFont(backBtn, 12, nil, 1, 1, 1, 0.55)
        PanelPx.Point(backLbl, "LEFT", backIcon, "RIGHT", 6, 0)
        backLbl:SetText(CUI.L("Back"))
        local function Paint(hot)
            if hot then
                backBg:SetColorTexture(0.100, 0.110, 0.124, 0.50)
            else
                backBg:SetColorTexture(0.062, 0.070, 0.082, 0.50)
            end
            backBrd:SetColor(1, 1, 1, hot and 0.22 or 0.12)
            backIcon:SetAlpha(hot and 0.85 or 0.6)
            backLbl:SetAlpha(hot and 0.85 or 0.55)
        end
        backBtn:SetScript("OnEnter", function() Paint(true) end)
        backBtn:SetScript("OnLeave", function() Paint(false) end)
        backBtn:SetScript("OnClick", function()
            page:Hide()
            mainPage:Show()
        end)
        local titleFs = CUI.MakeFont(page, 16, nil, 1, 1, 1, 0.95)
        PanelPx.Point(titleFs, "TOP", page, "TOP", 0, top - BACK_H / 2 + 8)
        titleFs:SetText(title)
        titleFs:SetJustifyH("CENTER")
        return BACK_H
    end

    -- The module list card of the Import and Export sections: a rounded card
    -- the height of the whole section (its footer included), a header with
    -- the title, the description and Select All / Deselect All, the column
    -- titles, and the module rows scrolling under them. cfg: title, desc,
    -- items, footerH, pickable(item) (what Select All picks), refreshAll()
    -- (every row and the count), visuals, row(item) -> that row's
    -- BuildAddonListRow options. Returns the y below the list.
    local function ModuleListCard(host, pad, top, fullWidth, cfg)
        local HDR_H, COL_HDR_H, SCROLL_MAX_H = 72, 28, 285
        local items = cfg.items
        local contentH = #items * ROW_H_A
        local scrollH = math.min(contentH, SCROLL_MAX_H)
        local y = top

        local card = CreateFrame("Frame", nil, host)
        card:SetFrameLevel(host:GetFrameLevel())
        PanelPx.Size(card, fullWidth, HDR_H + COL_HDR_H + scrollH + 8 + cfg.footerH)
        PanelPx.Point(card, "TOPLEFT", host, "TOPLEFT", pad, y)
        card:EnableMouse(false)
        CUI.MakeRoundedCard(card, 0.10, 0.50)

        local hdrFrame = CreateFrame("Frame", nil, host)
        PanelPx.Size(hdrFrame, fullWidth, HDR_H)
        PanelPx.Point(hdrFrame, "TOPLEFT", host, "TOPLEFT", pad, y)
        local hdrTitle = CUI.MakeFont(hdrFrame, 14, nil, 1, 1, 1, 0.9)
        PanelPx.Point(hdrTitle, "TOPLEFT", hdrFrame, "TOPLEFT", SIDE_PAD, -20)
        hdrTitle:SetText(CUI.L(cfg.title))
        hdrTitle:SetJustifyH("LEFT")
        local hdrDesc = CUI.MakeFont(hdrFrame, 11, nil, 1, 1, 1, 0.35)
        PanelPx.Point(hdrDesc, "TOPLEFT", hdrTitle, "BOTTOMLEFT", 0, -9)
        PanelPx.Point(hdrDesc, "RIGHT", hdrFrame, "RIGHT", -(160 + SIDE_PAD), 0)
        hdrDesc:SetText(CUI.L(cfg.desc))
        hdrDesc:SetJustifyH("LEFT")
        hdrDesc:SetWordWrap(true)
        local hdrDiv = hdrFrame:CreateTexture(nil, "ARTWORK")
        hdrDiv:SetColorTexture(1, 1, 1, 0.10)
        hdrDiv:SetHeight(1)
        PanelPx.Point(hdrDiv, "BOTTOMLEFT", hdrFrame, "BOTTOMLEFT", SIDE_PAD, 0)
        PanelPx.Point(hdrDiv, "BOTTOMRIGHT", hdrFrame, "BOTTOMRIGHT", -SIDE_PAD, 0)
        Unsnapped(hdrDiv)

        -- Select All (accent while everything pickable is in) | Deselect All.
        local LINK_GAP = 12
        local function Link(text)
            local button = CreateFrame("Button", nil, hdrFrame)
            button:SetFrameLevel(hdrFrame:GetFrameLevel() + 2)
            local caption = button:CreateFontString(nil, "OVERLAY")
            caption:SetFont(FONT, 12, CUI.GetFontOutlineFlag())
            caption:SetText(CUI.L(text))
            caption:SetTextColor(1, 1, 1, 0.40)
            caption:SetPoint("CENTER")
            button:SetSize(caption:GetStringWidth() + 4, 18)
            return button, caption
        end
        local selAllBtn, selAllLbl = Link("Select All")
        selAllBtn:SetPoint("RIGHT", hdrFrame, "RIGHT", -(STATUS_W + LINK_GAP + SIDE_PAD), 0)
        selAllBtn:SetPoint("TOP", hdrDesc, "TOP", 0, 0)
        local function AllIn()
            for _, entry in ipairs(items) do
                if cfg.pickable(entry) and not entry.getVal() then return false end
            end
            return true
        end
        local function PaintSelectAll(hot)
            if AllIn() then
                selAllLbl:SetTextColor(EG.r, EG.g, EG.b, hot and 1 or 0.7)
            else
                selAllLbl:SetTextColor(1, 1, 1, hot and 0.80 or 0.40)
            end
        end
        local function Refresh()
            cfg.refreshAll()
            PaintSelectAll(false)
        end
        selAllBtn:SetScript("OnEnter", function() PaintSelectAll(true) end)
        selAllBtn:SetScript("OnLeave", function() PaintSelectAll(false) end)
        selAllBtn:SetScript("OnClick", function()
            for _, entry in ipairs(items) do
                if cfg.pickable(entry) then entry.setVal(true) end
            end
            Refresh()
        end)
        PaintSelectAll(false)
        local linkDiv = hdrFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        linkDiv:SetColorTexture(1, 1, 1, 0.15)
        Unsnapped(linkDiv)
        PanelPx.Point(linkDiv, "LEFT", selAllBtn, "RIGHT", LINK_GAP / 2, 0)
        linkDiv:SetWidth(1)
        linkDiv:SetHeight(10)
        local deselBtn, deselLbl = Link("Deselect All")
        PanelPx.Point(deselBtn, "LEFT", selAllBtn, "RIGHT", LINK_GAP, 0)
        deselBtn:SetScript("OnEnter", function() deselLbl:SetTextColor(1, 1, 1, 0.80) end)
        deselBtn:SetScript("OnLeave", function() deselLbl:SetTextColor(1, 1, 1, 0.40) end)
        deselBtn:SetScript("OnClick", function()
            for _, entry in ipairs(items) do
                entry.setVal(false)
            end
            Refresh()
        end)
        y = y - HDR_H

        -- Column titles over the name, the Include box and the status.
        local colHdrFrame = CreateFrame("Frame", nil, host)
        PanelPx.Size(colHdrFrame, fullWidth, COL_HDR_H)
        PanelPx.Point(colHdrFrame, "TOPLEFT", host, "TOPLEFT", pad, y)
        for _, col in ipairs({
            { "Addon", "LEFT", "LEFT", SIDE_PAD },
            { "Status", "RIGHT", "RIGHT", -SIDE_PAD },
            { "Include", "CENTER", "RIGHT", INCLUDE_CENTER_X },
        }) do
            local fs = CUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
            PanelPx.Point(fs, col[2], colHdrFrame, col[3], col[4], 0)
            fs:SetText(CUI.L(col[1]))
            fs:SetJustifyH(col[2])
        end
        y = y - COL_HDR_H

        -- The rows, clipped to SCROLL_MAX_H and wheel-scrolled a row at a time.
        local scrollClip = CreateFrame("Frame", nil, host)
        PanelPx.Size(scrollClip, fullWidth, scrollH)
        PanelPx.Point(scrollClip, "TOPLEFT", host, "TOPLEFT", pad, y)
        scrollClip:SetClipsChildren(true)
        local scroller = CreateFrame("ScrollFrame", nil, scrollClip)
        scroller:SetAllPoints()
        local scrollChild = CreateFrame("Frame", nil, scroller)
        scrollChild:SetSize(fullWidth, contentH)
        scroller:SetScrollChild(scrollChild)
        local offset = 0
        scrollClip:EnableMouseWheel(true)
        scrollClip:SetScript("OnMouseWheel", function(_, delta)
            if CUI._ShiftWheelScale(delta) then return end
            offset = math.max(0, math.min(math.max(0, contentH - scrollH), offset - delta * ROW_H_A))
            scroller:SetVerticalScroll(offset)
        end)
        for i, entry in ipairs(items) do
            local o = cfg.row(entry)
            o.visuals = cfg.visuals
            -- Linked modules toggle together, so every row repaints.
            o.onToggle = Refresh
            BuildAddonListRow(scrollChild, i, entry, fullWidth, o)
        end
        return y - scrollH
    end

    -- A section footer under a module list: its frame and top rule.
    local function FooterBar(host, pad, top, fullWidth, height)
        local footer = CreateFrame("Frame", nil, host)
        PanelPx.Size(footer, fullWidth, height)
        PanelPx.Point(footer, "TOPLEFT", host, "TOPLEFT", pad, top)
        local rule = footer:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 1, 1, 0.10)
        rule:SetHeight(1)
        PanelPx.Point(rule, "TOPLEFT", footer, "TOPLEFT", SIDE_PAD, 0)
        PanelPx.Point(rule, "TOPRIGHT", footer, "TOPRIGHT", -SIDE_PAD, 0)
        Unsnapped(rule)
        return footer
    end

    -- A Done-style button: accent border and text on the dark background (the
    -- caller adds MakeAccentFade for the hover). Returns button, label, border.
    local function AccentButton(host, w, h, text, fontSize)
        local button = CreateFrame("Button", nil, host)
        PanelPx.Size(button, w, h)
        button:SetFrameLevel(host:GetFrameLevel() + 2)
        local DB = CUI.DARK_BG
        local bg = CUI.SolidTex(button, "BACKGROUND", DB.r, DB.g, DB.b, 0.92)
        bg:SetAllPoints()
        local brd = CUI.MakeRoundedBorder(button, EG.r, EG.g, EG.b, 0.7, bg)
        local caption = CUI.MakeFont(button, fontSize or 12, nil, EG.r, EG.g, EG.b)
        caption:SetAlpha(0.7)
        caption:SetPoint("CENTER")
        caption:SetText(CUI.L(text))
        return button, caption, brd
    end

    -- The "Include:" checkbox dropdown left of a footer's button. rows: label,
    -- sum (its word in the summary), tip, get(), set(refresh, ddBtn); a row
    -- with enabled == false shows dimmed with offTip and takes no clicks. The
    -- button reads Everything, Nothing Extra or the list of what is in.
    -- Returns the dropdown button and its summary refresh.
    local function IncludeDropdown(footer, nextTo, h, rows)
        local dropdownBtn, ddLabelFS = MakeDropdown(footer, 190, h, function() return "" end)
        PanelPx.Point(dropdownBtn, "RIGHT", nextTo, "LEFT", -12, 0)
        local incLbl = CUI.MakeFont(footer, 12, nil, 1, 1, 1, 0.6)
        PanelPx.Point(incLbl, "RIGHT", dropdownBtn, "LEFT", -8, 0)
        incLbl:SetText(CUI.L("Include:"))

        local function On(def) return def.enabled ~= false and def.get() end
        local function RefreshSummary()
            local parts, total = {}, 0
            for _, def in ipairs(rows) do
                if def.enabled ~= false then
                    total = total + 1
                    if def.get() then parts[#parts + 1] = CUI.L(def.sum) end
                end
            end
            if #parts == 0 then
                ddLabelFS:SetText(CUI.L("Nothing Extra"))
            elseif #parts == total then
                ddLabelFS:SetText(CUI.L("Everything"))
            else
                ddLabelFS:SetText(table.concat(parts, ", "))
            end
        end

        local dropMenu = MakeDropdownMenu(dropdownBtn, 240)
        dropMenu:SetSize(240, #rows * 26 + 8)
        local marks = {}
        local function RefreshMenu()
            for i, def in ipairs(rows) do
                marks[i]:SetShown(On(def))
            end
        end
        local function RefreshAll()
            RefreshMenu()
            RefreshSummary()
        end
        for i, def in ipairs(rows) do
            local row = CreateFrame("Button", nil, dropMenu)
            row:SetHeight(26)
            row:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 4, -(4 + (i - 1) * 26))
            row:SetPoint("RIGHT", dropMenu, "RIGHT", -4, 0)
            row:SetFrameLevel(dropMenu:GetFrameLevel() + 1)
            local highlight = row:CreateTexture(nil, "ARTWORK")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 1)
            highlight:SetAlpha(0)
            local boxFrame, tick = CheckBox(row)
            boxFrame:SetPoint("LEFT", row, "LEFT", 6, 0)
            marks[i] = tick
            local caption = CUI.MakeFont(row, 12, nil, 1, 1, 1, 0.7)
            caption:SetPoint("LEFT", boxFrame, "RIGHT", 8, 0)
            caption:SetText(CUI.L(def.label))
            local live = def.enabled ~= false
            if not live then row:SetAlpha(0.35) end
            row:SetScript("OnEnter", function()
                if live then highlight:SetAlpha(0.05) end
                CUI.ShowWidgetTooltip(row, CUI.L(live and def.tip or def.offTip))
            end)
            row:SetScript("OnLeave", function()
                if live then highlight:SetAlpha(0) end
                CUI.HideWidgetTooltip()
            end)
            if live then
                row:SetScript("OnClick", function()
                    def.set(RefreshAll, dropdownBtn)
                    RefreshAll()
                end)
            end
        end
        -- HookScript: MakeDropdownMenu owns OnShow (scale, outside-click close).
        dropMenu:HookScript("OnShow", RefreshMenu)
        dropdownBtn:SetScript("OnClick", function()
            RefreshSummary()
            if dropMenu:IsShown() then
                dropMenu:Hide()
            else
                RefreshMenu()
                dropMenu:Show()
            end
        end)
        RefreshSummary()
        return dropdownBtn, RefreshSummary
    end

    -------------------------------------------------------------------
    --  IMPORT PAGE BUILDER (shared by presets + import profile)
    -------------------------------------------------------------------
    ShowImportPage = function(
        exportString,
        bundle,
        defaultName,
        editModeString,
        editModeLayoutName,
        applyImportedScale
    )
        ClearPage(importView)

        -- Optional Blizzard Edit Mode layout to apply alongside this import (preset path only; the manual paste path leaves these nil).
        importView._editModeString = editModeString
        importView._editModeLayoutName = editModeLayoutName

        local scaleWarnText = BuildScaleWarning(bundle, applyImportedScale)
        local includedAddons = {}
        if bundle and bundle.data and bundle.data.addons then
            for moduleFolder in pairs(bundle.data.addons) do
                includedAddons[moduleFolder] = true
            end
        end

        -- Spec->profile assignments in the string gate the "Auto Assign to Specs" toggle (and grow the footer by one stacked row); without
        -- them the footer stays a compact single row.
        local hasSpecAssign = bundle
            and bundle.data
            and type(bundle.data.assignedSpecs) == "table"
            and #bundle.data.assignedSpecs > 0

        -- Does the string carry a UI scale? The adopt/keep decision was already made by MaybeConfirmUIScale before this page
        -- (applyImportedScale); this flag only gates the commit marker.
        local hasUIScale = bundle and bundle.data and type(bundle.data.uiScale) == "number"

        local ADDON_DB_MAP_LOCAL = CUI.VisibleProfileAddons(CUI._ADDON_DB_MAP)
        local PAD = CUI.CONTENT_PAD
        local fullWidth = importView:GetWidth() - PAD * 2
        -- The optional Auto Assign toggle stacks below the count row.
        local nFooterStack = (hasSpecAssign and 1 or 0)
        local FOOTER_H = 50 + nFooterStack * 24

        local itemY = -30

        local BACK_H = SubpageHeader(
            importView,
            PAD,
            itemY,
            CUI.Lf("Importing %1$s", (defaultName or CUI.L("Profile")))
        )

        itemY = itemY - BACK_H - 8

        if scaleWarnText then
            local warnFs = CUI.MakeFont(importView, 13, nil, 0.9, 0.2, 0.2, 0.85)
            PanelPx.Point(warnFs, "TOP", importView, "TOP", 0, itemY)
            PanelPx.Point(warnFs, "LEFT", importView, "LEFT", PAD, 0)
            PanelPx.Point(warnFs, "RIGHT", importView, "RIGHT", -PAD, 0)
            warnFs:SetText(scaleWarnText)
            warnFs:SetJustifyH("CENTER")
            warnFs:SetWordWrap(true)
            itemY = itemY - 48
        end

        local inputBox
        do
            local INPUT_H = 30
            local INPUT_W = 300
            local nameLabel = CUI.MakeFont(importView, 12, nil, 1, 1, 1, 0.45)
            PanelPx.Point(nameLabel, "TOPLEFT", importView, "TOPLEFT", PAD, itemY)
            nameLabel:SetText(CUI.L("Profile Name"))
            nameLabel:SetJustifyH("LEFT")

            itemY = itemY - 22

            local inputFrame = CreateFrame("Frame", nil, importView)
            PanelPx.Size(inputFrame, INPUT_W, INPUT_H)
            PanelPx.Point(inputFrame, "TOPLEFT", importView, "TOPLEFT", PAD, itemY)
            local iBg = inputFrame:CreateTexture(nil, "BACKGROUND")
            iBg:SetAllPoints()
            iBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_A)
            local inputBrd = CUI.MakeRoundedBorder(inputFrame, 1, 1, 1, CUI.DD_BRD_A, iBg)
            importView._nameFlash = BuildErrorFlash(inputFrame, inputBrd)

            inputBox = CreateFrame("EditBox", nil, inputFrame)
            inputBox:SetPoint("TOPLEFT", 12, -1)
            inputBox:SetPoint("BOTTOMRIGHT", -12, 1)
            inputBox:SetFont(FONT, 12, CUI.GetFontOutlineFlag())
            inputBox:SetTextColor(1, 1, 1, 0.9)
            inputBox:SetAutoFocus(false)
            inputBox:SetMaxLetters(30)
            if defaultName then inputBox:SetText(defaultName) end

            local placeholder = inputBox:CreateFontString(nil, "ARTWORK")
            placeholder:SetFont(FONT, 12, CUI.GetFontOutlineFlag())
            placeholder:SetTextColor(1, 1, 1, 0.25)
            placeholder:SetPoint("LEFT", inputBox, "LEFT", 0, 0)
            placeholder:SetText(CUI.L("Profile name..."))

            inputBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then
                    placeholder:Show()
                else
                    placeholder:Hide()
                end
                if importView._nameError then importView._nameError:Hide() end
            end)
            inputBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            inputBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

            itemY = itemY - INPUT_H - 14
        end

        -- Import Addons section (mirrors per-addon export layout)
        local selectedImports = {}
        local includeLayoutImport = true -- "Include layout" toggle (default on)
        -- "Include Overrides" is all-or-nothing: the exporter's COMPLETE
        -- override system (values + groups + custom unlock modes + BM forks) either replaces yours wholesale or none of it comes. Offered
        -- only when the string carries override data; ON for full strings (or subsets exported with Overrides included), OFF otherwise.
        local stringHasOverrides = false
        do
            local d = bundle and bundle.data
            if d then
                stringHasOverrides = d.specOverrides ~= nil
                    or d.condOverrides ~= nil
                    or d.specOverrideGroups ~= nil
                    or d.condOverrideGroups ~= nil
                    or d.specUnlockOverrides ~= nil
                    or d.condUnlockOverrides ~= nil
                    or d.specBmOverrides ~= nil
                    or d.condBmOverrides ~= nil
                    or d.specDmOverrides ~= nil
                    or d.condDmOverrides ~= nil
            end
        end
        local includeOverridesImport = stringHasOverrides
                and (bundle.data.overridesIncluded == true or (bundle.data.partialImport ~= true and bundle.data.overridesExcluded ~= true))
            or false
        -- "Include Window Skins": the exporter's Blizz UI Enhanced account-global bundle (Window Skins + Tooltips, Menus & Popups).
        -- Default OFF and confirmation-gated -- it overwrites the recipient's settings across ALL profiles. Grayed out when string has none.
        local stringHasBlizzSkin = (bundle and bundle.data and type(bundle.data.blizzSkinGlobals) == "table")
            or false
        local includeWindowSkinsImport = false
        -- "Global Settings": the exporter's global appearance (fonts, custom colours, dark mode, accent, number format) and UI scale. Presence = deliberate
        -- include; this toggle is the recipient's opt-out. ON when carried, inert when the string has none.
        local stringHasGlobals = false
        do
            local d = bundle and bundle.data
            if d then
                stringHasGlobals = d.fonts ~= nil
                    or d.customColors ~= nil
                    or d.darkMode ~= nil
                    or d.cuiAccent ~= nil
                    or d.uiScale ~= nil
                    or d.numberFormat ~= nil
            end
        end
        local includeGlobalsImport = stringHasGlobals
        local autoAssignImport = false -- "Auto Assign to Specs" toggle (default off)
        local importVisuals = {}
        local importCountFs
        local importComponents -- canon folder -> { component member set }, set below
        local importCanImport = {}
        local CANON_DISPLAY = {} -- canon folder -> display name (for the linked tooltip)

        local addonItems = {}
        for _, entry in ipairs(ADDON_DB_MAP_LOCAL) do
            local moduleFolder = entry.folder
            -- Payload keys are CANONICAL (suite folder names); selectedImports is keyed by canon so it matches the payload + the strip loop
            -- in both suite and standalone builds. "loaded"/"desc" stay on the LOCAL folder so only this build's installed module is checkable.
            local canon = entry.canon or moduleFolder
            local loaded = CUI.IsModuleAddonLoaded(moduleFolder)
            local inPayload = includedAddons[canon] or false
            local canImport = loaded and inPayload
            importCanImport[canon] = canImport
            CANON_DISPLAY[canon] = entry.display
            addonItems[#addonItems + 1] = {
                folder = moduleFolder,
                canon = canon,
                display = entry.display,
                desc = ADDON_DESCS[moduleFolder] or "",
                loaded = loaded,
                inPayload = inPayload,
                canImport = canImport,
                getVal = function() return selectedImports[canon] or false end,
                -- Hard-couple: (un)checking a module sets its whole connected component (anchor/size-match links), importable members only.
                setVal = function(value)
                    -- Layout OFF: relationships aren't imported, so skip the hard-couple and let each linked module be picked alone.
                    local members = includeLayoutImport and importComponents and importComponents[canon]
                    if members then
                        for f in pairs(members) do
                            if importCanImport[f] then selectedImports[f] = value or nil end
                        end
                    else
                        selectedImports[canon] = value or nil
                    end
                end,
            }
            if canImport then selectedImports[canon] = true end
        end

        -- Module connectivity from the payload's layout + meta (both CANONICAL, matching selectedImports' keyspace). Drives the hard-couple
        -- above and the "linked" row affordance. stale={} -- sender already pruned dead edges.
        do
            local ul = bundle and bundle.data and bundle.data.unlockLayout
            local meta = bundle and bundle.data and bundle.data.unlockLayoutMeta
            importComponents = CUI.BuildModuleComponents(
                ul,
                CUI.BuildImportKeyToFolder(ul, meta and meta.keyToFolder)
            )
        end

        local function RefreshImportCount()
            if not importCountFs then return end
            local count = 0
            for _ in pairs(selectedImports) do
                count = count + 1
            end
            importCountFs:SetText(CUI.Lf("Import will include %1$s of %2$s addons.", count, #addonItems))
        end

        local function RefreshAllImportVisuals()
            for _, fn in ipairs(importVisuals) do
                fn()
            end
            RefreshImportCount()
        end

        itemY = ModuleListCard(importView, PAD, itemY, fullWidth, {
            title = "Import Addons",
            desc = "Choose which addons to import. Any addons not included will use your active profile's settings in the new profile.",
            items = addonItems,
            footerH = FOOTER_H,
            pickable = function(entry) return entry.canImport end,
            refreshAll = RefreshAllImportVisuals,
            visuals = importVisuals,
            -- Not in the string (red) or not loaded here (dim).
            row = function(entry)
                return {
                    active = entry.canImport,
                    inactiveText = entry.inPayload and CUI.L("Not Loaded") or CUI.L("Not Included"),
                    inactiveColor = entry.inPayload and { 1, 1, 1, 0.25 } or { 0.9, 0.2, 0.2, 0.7 },
                    linked = function()
                        return includeLayoutImport and importComponents and importComponents[entry.canon],
                            entry.canon,
                            CANON_DISPLAY
                    end,
                    linkedTip = function(list)
                        return CUI.Lf(
                            "Linked by Anchor/Width/Height Matching to: %1$s. These import together.",
                            list
                        )
                    end,
                }
            end,
        })

        -- Footer
        itemY = itemY - 8
        local footerFrame = FooterBar(importView, PAD, itemY, fullWidth, FOOTER_H)

        importCountFs = CUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.40)
        -- With Auto Assign present the footer has two rows, so the count sits on the upper one; otherwise it stays vertically centered.
        if nFooterStack > 0 then
            PanelPx.Point(importCountFs, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, -16)
        else
            PanelPx.Point(importCountFs, "LEFT", footerFrame, "LEFT", SIDE_PAD, 0)
        end
        importCountFs:SetJustifyH("LEFT")
        RefreshImportCount()

        -- Overrides / Unlock Mode Layout / Global Settings / Window Skins live in the "Include:" dropdown beside the Import button; only
        -- Auto Assign stays inline, stacked below the count row.

        -- "Auto Assign to Specs": shown only when the string carries spec->profile assignments. Off (default) leaves the recipient's
        -- assignments alone; On points each exported spec at the new profile.
        if hasSpecAssign then
            local aaBtn = CreateFrame("Button", nil, footerFrame)
            aaBtn:SetSize(180, 24)
            PanelPx.Point(aaBtn, "TOPLEFT", importCountFs, "BOTTOMLEFT", 0, -8)
            local boxFrame, mark = CheckBox(aaBtn)
            boxFrame:SetPoint("LEFT", aaBtn, "LEFT", 0, 0)
            local caption = CUI.MakeFont(aaBtn, 12, nil, 1, 1, 1, 0.6)
            caption:SetPoint("LEFT", boxFrame, "RIGHT", 6, 0)
            caption:SetText(CUI.L("Auto Assign to Specs"))
            local function vis() mark:SetShown(autoAssignImport) end
            vis()
            aaBtn:SetScript("OnClick", function()
                autoAssignImport = not autoAssignImport
                vis()
            end)
            aaBtn:SetScript(
                "OnEnter",
                function()
                    CUI.ShowWidgetTooltip(
                        aaBtn,
                        CUI.L(
                            "Assign this profile to the same specializations it was assigned to on export. Off = your current spec assignments stay as they are."
                        )
                    )
                end
            )
            aaBtn:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        end

        local IMP_BTN_H = 30
        local importBtn, impLbl, impBrd = AccentButton(footerFrame, 180, IMP_BTN_H, "Import Selected Addons")
        PanelPx.Point(importBtn, "RIGHT", footerFrame, "RIGHT", -SIDE_PAD, 0)

        -- Include: the same four extras as the export footer. Those the string
        -- has no data for stay dimmed; Window Skins asks before turning on.
        local rowDefs = {
            {
                label = "Overrides",
                sum = "Overrides",
                enabled = stringHasOverrides,
                offTip = "This profile string does not carry any override data.",
                tip = "Import the sharer's complete override setup: spec and conditional override values, groups, their custom layouts, and Buff Manager overrides. This replaces ALL of your own overrides. Off = keep yours untouched.",
                get = function() return includeOverridesImport end,
                set = function() includeOverridesImport = not includeOverridesImport end,
            },
            {
                label = "Edit Layout Positions",
                sum = "Layout",
                enabled = true,
                tip = "Import the anchor & size-match relationships from this profile. Off = keep your own layout; only the selected modules' own positions/settings come in.",
                get = function() return includeLayoutImport end,
                set = function() includeLayoutImport = not includeLayoutImport end,
            },
            {
                label = "Global Settings",
                sum = "Globals",
                enabled = stringHasGlobals,
                offTip = "This profile string does not carry any global settings.",
                tip = "Apply the sharer's fonts, custom colors, dark mode, accent color and UI scale. Off = keep your own global look and scale; only the selected modules' settings come in.",
                get = function() return includeGlobalsImport end,
                set = function() includeGlobalsImport = not includeGlobalsImport end,
            },
            {
                label = "Window & Tooltip Skins",
                sum = "Window Skins",
                enabled = stringHasBlizzSkin,
                offTip = "This profile string does not carry any Window & Tooltip Skins settings.",
                tip = "Apply the sharer's Window Styling settings (its General and Tooltips & Menus pages). These are account-wide and will overwrite yours across ALL profiles. Off = keep your own.",
                get = function() return includeWindowSkinsImport end,
                set = function(refresh, dropdownBtn)
                    if includeWindowSkinsImport then
                        includeWindowSkinsImport = false
                        return
                    end
                    -- The answer is for this build of the import page: a build
                    -- that dresses the dropdown again before it comes drops it.
                    local ddGen = PoolGen(dropdownBtn)
                    CUI:ShowConfirmPopup({
                        title = CUI.L("Overwrite Window & Tooltip Settings?"),
                        message = CUI.L(
                            "This will replace YOUR Window Styling settings (its General and Tooltips & Menus pages) with the sharer's, across ALL of your profiles. Your current settings on those two tabs cannot be recovered afterward."
                        ),
                        confirmText = CUI.L("OK"),
                        cancelText = CUI.L("Cancel"),
                        onConfirm = function()
                            if not SameDress(dropdownBtn, ddGen) then return end
                            includeWindowSkinsImport = true
                            if refresh then refresh() end
                        end,
                    })
                end,
            },
        }
        IncludeDropdown(footerFrame, importBtn, IMP_BTN_H, rowDefs)

        MakeAccentFade(importBtn, impLbl, impBrd)
        importBtn:SetScript("OnClick", function()
            -- Get profile name from the edit box
            local nameBox = importView._nameEditBox
            local label = nameBox and strtrim(nameBox:GetText()) or ""
            if label == "" then
                if importView._nameFlash then importView._nameFlash() end
                if importView._nameError then importView._nameError:Show() end
                if nameBox then nameBox:SetFocus() end
                return
            end

            -- Block duplicate profile names. EXCEPTION: an interactive API import (ImportProfileInteractive) targeting the EXACT name the
            -- calling addon requested overwrites cleanly, like the silent API -- ImportProfile replaces the stored blob wholesale (the old
            -- same-name blob is never read, so nothing mixes) and unselected modules keep current values via merge-base-on-active. A name
            -- the USER edited into a collision keeps the protection below.
            local apiS = CUI._apiImportSession
            local apiOverwrite = apiS and apiS.state ~= "done" and apiS.name == label
            local _, existingProfiles = CUI.GetProfileList()
            if existingProfiles and existingProfiles[label] and not apiOverwrite then
                CUI:ShowConfirmPopup({
                    title = CUI.L("Name Taken"),
                    message = CUI.Lf(
                        'A profile named "%1$s" already exists. Please choose a different name.',
                        label
                    ),
                    confirmText = CUI.L("OK"),
                    hideCancel = true,
                    onConfirm = function() end,
                })
                return
            end

            -- Filter on a private deep copy of the already-decoded payload: the strips below mutate it and the page must stay re-importable
            -- after a failed attempt (re-decoding would re-run the codec).
            local pickedBundle = CUI._DeepCopy(bundle)
            local isPartialImport = false
            if pickedBundle and pickedBundle.data and pickedBundle.data.addons then
                for moduleFolder in pairs(pickedBundle.data.addons) do
                    if not selectedImports[moduleFolder] then
                        pickedBundle.data.addons[moduleFolder] = nil
                        isPartialImport = true
                    end
                end
            end
            -- CDM spell allocation is top-level (the per-module loop misses it): kept ONLY when the CDM module is selected, and then every
            -- spec in the string imports as-is (no spec picker).
            if pickedBundle and pickedBundle.data then
                if not selectedImports["CludesUICooldownManager"] then pickedBundle.data.cdmSpells = nil end
            end
            -- Spec->profile assignments: top-level, applied by ImportProfile when present. Dropped wholesale unless "Auto Assign to Specs"
            -- is on (default off leaves the recipient's assignments alone).
            if pickedBundle and pickedBundle.data and not autoAssignImport then
                pickedBundle.data.assignedSpecs = nil
            end
            -- UI scale (account-wide): applied by ImportProfile ONLY on the opt-in from MaybeConfirmUIScale. PRESENCE IS CONSENT at
            -- ImportProfile -- accepted keeps the payload's uiScale; declined or matching scales STRIP it so the user's own scale stands.
            if pickedBundle and pickedBundle.data and hasUIScale and not applyImportedScale then
                pickedBundle.data.uiScale = nil
                pickedBundle.data.applyUIScale = nil
            end
            -- Layout relationships: keep only anchor/size-match edges with BOTH endpoints in the selected modules (per-element graph filter)
            -- via the payload's keyToFolder meta. selectedImports and the meta values are both CANONICAL, so they compare directly.
            -- stale={}: the sender pruned dead edges at export and the recipient's registry is irrelevant here; the "Include layout" toggle drops the whole thing separately.
            if pickedBundle and pickedBundle.data then
                local ul = pickedBundle.data.unlockLayout
                if ul and includeLayoutImport then
                    local meta = pickedBundle.data.unlockLayoutMeta
                    -- payload meta wins; the static resolver fills gaps (and ALL keys for a meta-less string) so we never drop the layout.
                    local k2f = CUI.BuildImportKeyToFolder(ul, meta and meta.keyToFolder)
                    pickedBundle.data.unlockLayout = CUI.FilterLayoutToFolders(ul, selectedImports, k2f)
                else
                    pickedBundle.data.unlockLayout = nil
                end
                -- Meta is transient -- never overlay/persist it into the profile.
                pickedBundle.data.unlockLayoutMeta = nil
            end
            -- Global appearance (fonts, customColors, darkMode, cuiAccent, numberFormat) and scale ride the Include dropdown's "Global Settings" row (on
            -- by default when carried): unchecked strips them all so the merge keeps the recipient's look. Module deselection alone never
            -- strips them -- the store merge takes each key only when present.
            if pickedBundle and pickedBundle.data and not includeGlobalsImport then
                pickedBundle.data.fonts = nil
                pickedBundle.data.customColors = nil
                pickedBundle.data.darkMode = nil
                pickedBundle.data.numberFormat = nil
                pickedBundle.data.cuiAccent = nil
                pickedBundle.data.uiScale = nil
                pickedBundle.data.applyUIScale = nil
            end
            if isPartialImport and pickedBundle and pickedBundle.data then
                -- Overrides (values AND forks) are governed solely by the Include Overrides checkbox; module deselection never strips them
                -- here. partialImport gates the override legacy keep-mine default at the store merge.
                pickedBundle.data.partialImport = true
            end
            -- Unlock-layer FORKS are whole cross-module position layers, so "Include layout" must gate them exactly like unlockLayout above
            -- or the exporter's forks replace the recipient's group layouts (ApplyLayer rewrites live anchors and CDM/AB bar positions from
            -- them on the next apply). layoutExcluded tells the store merge to KEEP the recipient's forks (nil incoming must not read as wipe).
            if pickedBundle and pickedBundle.data and not includeLayoutImport then
                -- Baseline layout excluded; fork stores belong to the Include Overrides decision below, so they are not stripped here.
                pickedBundle.data.layoutExcluded = true
            end
            -- Include Overrides (all-or-nothing): checked -> stamp the marker so ImportProfile takes the exporter's whole override system
            -- even on subset strings; unchecked -> strip every override store and stamp the exclusion so nils read as "keep mine", not "wipe".
            if pickedBundle and pickedBundle.data then
                if includeOverridesImport then
                    pickedBundle.data.overridesIncluded = true
                    pickedBundle.data.overridesExcluded = nil
                else
                    pickedBundle.data.specOverrides = nil
                    pickedBundle.data.specOverrideGroups = nil
                    pickedBundle.data.specOverrideNextId = nil
                    pickedBundle.data.condOverrides = nil
                    pickedBundle.data.condOverrideGroups = nil
                    pickedBundle.data.condOverrideNextId = nil
                    pickedBundle.data.specUnlockOverrides = nil
                    pickedBundle.data.condUnlockOverrides = nil
                    pickedBundle.data.specBmOverrides = nil
                    pickedBundle.data.condBmOverrides = nil
                    pickedBundle.data.specDmOverrides = nil
                    pickedBundle.data.condDmOverrides = nil
                    pickedBundle.data.unlockOverrideAnchors = nil
                    pickedBundle.data.overridesExcluded = true
                    pickedBundle.data.overridesIncluded = nil
                end
            end
            -- Include Window Skins: checked -> stamp the opt-in so ImportProfile applies the Blizz UI Enhanced account-global bundle before
            -- the reload; unchecked -> strip the bundle so nothing can apply and the recipient keeps their settings.
            if pickedBundle and pickedBundle.data then
                if includeWindowSkinsImport and stringHasBlizzSkin then
                    pickedBundle.data.applyBlizzSkinGlobals = true
                else
                    pickedBundle.data.blizzSkinGlobals = nil
                    pickedBundle.data.applyBlizzSkinGlobals = nil
                end
            end

            local function commit()
                -- The payload table goes to ImportProfile directly (no encode-to-string round trip on already-decoded data). An
                -- interactive-API session marks itself as committing so ImportProfile's stale-session cancellation (which guards
                -- CONCURRENT silent imports) never cancels the committing one.
                local apiSession = CUI._apiImportSession
                if apiSession and apiSession.state == "done" then apiSession = nil end
                -- The import reloads the UI as it lands (an interactive-API session hands that to its caller), and only a
                -- profile payload imports (ImportProfile refuses every other type), so the outcome is known now: the reload
                -- is asked for first in the click (RequestReload; WoW Forever refused it after the import's own work) and the
                -- import below runs before the client reloads.
                if not apiSession and pickedBundle and pickedBundle.type == "full" then
                    CUI.RequestReload(
                        CUI.L("Profile Imported"),
                        CUI.ImportReloadMessage(pickedBundle)
                    )
                end
                if apiSession then apiSession.committing = true end
                local ok, err, status = CUI.ImportProfile(pickedBundle, label)
                if apiSession then apiSession.committing = nil end
                -- Apply the preset's Blizzard Edit Mode layout (if supplied) right before the reload so profile + layout land together.
                -- pcall-guarded so a Blizzard Edit Mode error cannot block the reload. No-op on the manual paste path (no stored string).
                if ok and importView._editModeString then
                    pcall(
                        CUI.ApplyPresetEditMode,
                        importView._editModeString,
                        importView._editModeLayoutName
                    )
                end
                if ok and apiSession then
                    -- Interactive-API import: hand control back to the caller instead of reloading (the caller owns ReloadUI()). Finish
                    -- BEFORE hiding so the panel's OnHide decline hook sees a completed session and stays silent.
                    if status == "spec_locked" then
                        CUI.Print(
                            CUI.Lf(
                                '"%1$s" was saved but cannot be loaded because this spec has an assigned profile.',
                                label
                            )
                        )
                    end
                    CUI._FinishApiImportSession(true)
                    if CUI._ProfilesResetToMain then pcall(CUI._ProfilesResetToMain) end
                    CUI:Hide()
                elseif ok and status == "spec_locked" then
                    CUI:ShowInfoPopup({
                        title = CUI.L("Profile Imported"),
                        content = CUI.Lf(
                            '"%1$s" was saved but cannot be loaded because this spec has an assigned profile. Switch specs or remove the spec assignment to use it.',
                            label
                        ),
                    })
                elseif not ok then
                    CUI:ShowInfoPopup({
                        title = CUI.L("Import Failed"),
                        content = err or CUI.L("Unknown error"),
                    })
                end
            end

            -- CDM spell layouts (gated above) import as-is, no spec picker: they are per-profile (spellAssignments.profiles[profileName]),
            -- so only the NEW profile's store is populated (others untouched) and any spec not in the string falls back to default bars.
            commit()
        end)
        importBtn._flashError = BuildErrorFlash(importBtn, impBrd)

        -- Red error message shown directly below the button when no name is entered
        local nameErrorFs = CUI.MakeFont(footerFrame, 11, nil, 0.9, 0.2, 0.2)
        nameErrorFs:SetJustifyH("RIGHT")
        PanelPx.Point(nameErrorFs, "TOPRIGHT", importBtn, "BOTTOMRIGHT", 0, -14)
        nameErrorFs:SetText(CUI.L("*Please enter a profile name"))
        nameErrorFs:Hide()
        importView._nameError = nameErrorFs

        -- Store edit box reference for the import button callback
        importView._nameEditBox = inputBox

        -- Hide every other page so the import page never overlaps the one it was opened from (the main paste flow).
        mainPage:Hide()
        pastePage:Hide()
        importView:Show()
    end

    -------------------------------------------------------------------
    --  PASTE PAGE (Import Profile step 1: paste string)
    -------------------------------------------------------------------
    local function ShowPastePage()
        ClearPage(pastePage)

        local PAD = CUI.CONTENT_PAD
        local fullWidth = pastePage:GetWidth() - PAD * 2
        local py = -30

        local BACK_H = SubpageHeader(pastePage, PAD, py, CUI.L("Import Profile"))

        py = py - BACK_H - 20

        -- Big paste panel
        local PANEL_H = 200
        local panelFrame = CreateFrame("Frame", nil, pastePage)
        PanelPx.Size(panelFrame, fullWidth, PANEL_H)
        PanelPx.Point(panelFrame, "TOPLEFT", pastePage, "TOPLEFT", PAD, py)
        local panelBg = panelFrame:CreateTexture(nil, "BACKGROUND")
        panelBg:SetAllPoints()
        panelBg:SetColorTexture(0.062, 0.070, 0.082, 0.50)
        CUI.MakeRoundedBorder(panelFrame, 1, 1, 1, 0.10, panelBg)

        local pasteSF = CreateFrame("ScrollFrame", nil, panelFrame)
        pasteSF:SetPoint("TOPLEFT", 16, -12)
        pasteSF:SetPoint("BOTTOMRIGHT", -16, 12)

        local pasteInput = CreateFrame("EditBox", nil, pasteSF)
        pasteInput:SetWidth(fullWidth - 32)
        pasteInput:SetFont(FONT, 11, CUI.GetFontOutlineFlag())
        pasteInput:SetTextColor(1, 1, 1, 0.8)
        pasteInput:SetAutoFocus(false)
        pasteInput:SetMultiLine(true)
        pasteSF:SetScrollChild(pasteInput)

        -- Click anywhere on the panel to refocus the edit box
        panelFrame:EnableMouse(true)
        panelFrame:SetScript("OnMouseDown", function() pasteInput:SetFocus() end)

        local pastePlaceholder = pasteSF:CreateFontString(nil, "ARTWORK")
        pastePlaceholder:SetFont(FONT, 12, CUI.GetFontOutlineFlag())
        pastePlaceholder:SetTextColor(1, 1, 1, 0.20)
        pastePlaceholder:SetPoint("TOPLEFT", pasteSF, "TOPLEFT", 0, 0)
        pastePlaceholder:SetText(CUI.L("Paste your profile string here..."))

        pasteInput:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" then
                pastePlaceholder:Show()
            else
                pastePlaceholder:Hide()
            end
        end)
        pasteInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        pasteInput:SetScript("OnCursorChanged", function(self, _, cursorY, _, cursorH)
            local vs = pasteSF:GetVerticalScroll()
            local h = pasteSF:GetHeight()
            local bottom = -cursorY + cursorH
            if bottom > vs + h then
                pasteSF:SetVerticalScroll(bottom - h)
            elseif -cursorY < vs then
                pasteSF:SetVerticalScroll(-cursorY)
            end
        end)

        -- Large pastes go into a buffer (attached AFTER the handlers above so their scripts survive): the box only ever holds a short
        -- summary line, keeping paste instant with no letter-cap truncation.
        local pasteAbsorber = CUI.AttachImportPasteAbsorber(
            pasteInput,
            function()
                CUI:ShowInfoPopup({
                    title = CUI.L("Paste Interrupted"),
                    content = CUI.L(
                        "The pasted string could not be read completely. Please paste it again."
                    ),
                })
            end
        )

        py = py - PANEL_H - 16

        -- Continue button (Done-style)
        local contBtn, contLbl, contBrd = AccentButton(pastePage, 160, 34, "Continue", 13)
        PanelPx.Point(contBtn, "TOPRIGHT", pastePage, "TOPRIGHT", -PAD, py)

        local contReset = MakeAccentFade(contBtn, contLbl, contBrd)
        local decodeRun
        contBtn:SetScript("OnClick", function()
            if decodeRun then return end
            local importStr = pasteAbsorber.GetText()
            if importStr == "" then return end
            -- Decode across frames: lock the button and show progress so the client stays responsive on very large strings.
            contBtn:Disable()
            contBtn:SetScript("OnUpdate", nil)
            contReset()
            contLbl:SetText(CUI.L("Processing") .. "...")
            local function Restore()
                decodeRun = nil
                contBtn:Enable()
                contLbl:SetText(CUI.L("Continue"))
                contReset()
            end
            -- The paste page this decode belongs to: once it is dressed again
            -- (reopened, or the page rebuilt), the result is dropped.
            local btnGen = PoolGen(contBtn)
            decodeRun = CUI.DecodeImportStringAsync(importStr, function(bundle, err)
                if not SameDress(contBtn, btnGen) then return end
                Restore()
                -- The user may have navigated away mid-decode; a stale run's result is simply dropped.
                if not pastePage:IsVisible() then return end
                if not bundle then
                    CUI:ShowInfoPopup({
                        title = CUI.L("Import Failed"),
                        content = err or CUI.L("Invalid import string."),
                    })
                    return
                end
                -- FULL ACCOUNT string: its own flow, routed BEFORE the normal import machinery sees the payload (no module selection,
                -- include toggles, or store merging). Typed confirmation: it overwrites account-wide settings.
                if CUI.IsFullAccountPayload(bundle) then
                    pastePage:Hide()
                    local message = CUI.L(
                        "This string is a FULL ACCOUNT export. It replaces your account-wide settings with the sender's, including Quality of Life, Frame Bindings, Cooldown Manager spell setups, unlock anchors, UI scale, and spec assignments -- not just a profile. Your other profiles keep their own settings, but a profile with the same name is replaced."
                    )
                    -- Spell setups from the other client are skipped on import: say so.
                    local data = bundle.data
                    if
                        CUI.PayloadFromOtherClient(bundle)
                        and type(data) == "table"
                        and data.spellAssignments ~= nil
                    then
                        message = message
                            .. "\n\n"
                            .. CUI.L(
                                "Its Cooldown Manager spells come from the other game client and will not be imported."
                            )
                    end
                    CUI:ShowConfirmPopup({
                        title = CUI.L("Import Full Account Data"),
                        message = message,
                        disclaimer = CUI.L(
                            "This cannot be undone. Export your own profile as a backup first."
                        ),
                        typeToConfirm = "Confirm",
                        confirmText = CUI.L("Import & Reload"),
                        cancelText = CUI.L("Cancel"),
                        onConfirm = function() CUI.ImportFullAccountData(bundle) end,
                    })
                    return
                end
                pastePage:Hide()
                local pageGen = PoolGen(pastePage)
                MaybeConfirmUIScale(bundle, function(applyScale)
                    -- Not after a rebuild of the profiles page meanwhile.
                    if not SameDress(pastePage, pageGen) then return end
                    ShowImportPage(importStr, bundle, nil, nil, nil, applyScale)
                end)
            end, function(frac)
                if not SameDress(contBtn, btnGen) then return end
                contLbl:SetFormattedText("%s %d%%", CUI.L("Processing"), frac * 100)
            end)
        end)

        mainPage:Hide()
        pastePage:Show()
        pasteInput:SetFocus()
    end

    -------------------------------------------------------------------
    --  TOP SECTION: Import | Popular Presets (2 action cards)
    --  Exporting lives solely in the per-addon "Export Profile" section below -- all modules checked is the full export.
    -------------------------------------------------------------------
    _, h = W:Spacer(parent, y, 10)
    y = y - h

    -- Popular Presets: the in-game browser is retired; presets live on the
    -- CludesUI website. The card opens the announcement-style popup with
    -- the copyable link (same one the Presets tab shows).
    y = CUI.BuildActionCardRow(parent, y, {
        {
            icon = MEDIA .. "icons\\import.png",
            title = CUI.L("Import Profile"),
            desc = CUI.L("Import a profile from string."),
            onClick = function() ShowPastePage() end,
        },
    })

    -------------------------------------------------------------------
    --  MIDDLE SECTION: Active Profile | Assign to Spec | Create New
    -------------------------------------------------------------------
    _, h = W:Spacer(parent, y, 14)
    y = y - h

    do
        local LABEL_H = 16
        local CTRL_H = 30
        local PAD_X = 40
        local PAD_Y = 20
        local GAP = 40
        local ROW_H = PAD_Y + LABEL_H + 4 + CTRL_H + PAD_Y

        local fullWidth = parent:GetWidth() - CUI.CONTENT_PAD * 2
        local innerW = fullWidth - PAD_X * 2
        local DD_W = math.floor(innerW * 0.38)
        local BTN_W = math.floor((innerW - DD_W - GAP * 2) / 2)

        local lineFrame = CreateFrame("Frame", nil, parent)
        PanelPx.Size(lineFrame, fullWidth, ROW_H)
        PanelPx.Point(lineFrame, "TOPLEFT", parent, "TOPLEFT", CUI.CONTENT_PAD, y)

        -- Background panel
        local rowBrd = CUI.MakeRoundedCard(lineFrame, 0.10, 0.50)
        local rowBg = rowBrd.bg

        -- "Active Profile" label
        local profLabel = CUI.MakeFont(lineFrame, 12, nil, EG.r, EG.g, EG.b, 0.7)
        PanelPx.Point(profLabel, "TOPLEFT", lineFrame, "TOPLEFT", PAD_X, -PAD_Y)
        profLabel:SetText(CUI.L("Active Profile"))
        profLabel:SetJustifyH("LEFT")

        -- Active Profile dropdown
        local dropdownBtn, ddLabelFS, _, _, ddPaint = MakeDropdown(
            lineFrame,
            DD_W,
            CTRL_H,
            function() return CUI.GetActiveProfileName() end
        )
        CUI._profileDDBtn = dropdownBtn
        ddLabel = ddLabelFS
        PanelPx.Point(dropdownBtn, "TOPLEFT", profLabel, "BOTTOMLEFT", 0, -6)

        -- Profile dropdown menu with inline rename/delete/keybind
        local dropMenu = MakeDropdownMenu(dropdownBtn, DD_W)
        local X_SZ = 14
        local menuItems = {}

        local function RebuildProfileMenu()
            for _, entry in ipairs(menuItems) do
                entry:Hide()
            end
            local order, profileList = CUI.GetProfileList()
            local menuH = 4
            local idx = 0
            local activeName = CUI.GetActiveProfileName()
            local sid = CurrentSpecID()
            local specAssigned = sid and CUI.GetSpecProfile(sid) or nil
            for _, label in ipairs(order) do
                if profileList[label] then
                    idx = idx + 1
                    local entry = menuItems[idx]
                    if not entry then
                        entry = CreateFrame("Button", nil, dropMenu)
                        entry:SetHeight(26)
                        entry:SetFrameLevel(dropMenu:GetFrameLevel() + 1)
                        local caption = entry:CreateFontString(nil, "OVERLAY")
                        caption:SetFont(FONT, 13, CUI.GetFontOutlineFlag())
                        caption:SetPoint("LEFT", entry, "LEFT", 10, 0)
                        caption:SetPoint("RIGHT", entry, "RIGHT", -(X_SZ * 3 + 30), 0)
                        caption:SetJustifyH("LEFT")
                        caption:SetTextColor(1, 1, 1, CUI.TEXT_DIM_A)
                        entry._lbl = caption
                        local highlight = entry:CreateTexture(nil, "ARTWORK")
                        highlight:SetAllPoints()
                        highlight:SetColorTexture(1, 1, 1, 1)
                        highlight:SetAlpha(0)
                        entry._hl = highlight

                        -- Delete, Rename and Keybind icons at the right edge.
                        local icons = {}
                        local function Icon(file, anchor, rel, x)
                            local widget = CreateFrame("Button", nil, entry)
                            widget:SetSize(X_SZ, X_SZ)
                            widget:SetPoint("RIGHT", anchor, rel, x, 0)
                            widget:SetFrameLevel(entry:GetFrameLevel() + 2)
                            local texture = widget:CreateTexture(nil, "OVERLAY")
                            texture:SetAllPoints()
                            Unsnapped(texture)
                            texture:SetTexture(MEDIA .. "icons\\" .. file)
                            widget:SetAlpha(0.4)
                            icons[#icons + 1] = widget
                            return widget
                        end
                        local xBtn = Icon("cui-close.png", entry, "RIGHT", -8)
                        local editBtn = Icon("cui-edit.png", xBtn, "LEFT", -4)
                        local kbBtnI = Icon("cui-keybind-2.png", editBtn, "LEFT", -4)
                        entry._xBtn, entry._editBtn, entry._kbBtn = xBtn, editBtn, kbBtnI

                        -- The row lights while the mouse is on it or on one of its
                        -- icons (the icon under the mouse brightest), and dims
                        -- back to its resting look (selected or not) once off all.
                        local function OverIcon()
                            return xBtn:IsMouseOver() or editBtn:IsMouseOver() or kbBtnI:IsMouseOver()
                        end
                        local function IconAlpha(a)
                            for _, b in ipairs(icons) do
                                b:SetAlpha(a)
                            end
                        end
                        entry._light = function()
                            caption:SetTextColor(1, 1, 1, 1)
                            highlight:SetAlpha(CUI.DD_ITEM_HL_A)
                            IconAlpha(0.8)
                        end
                        entry._dim = function()
                            caption:SetTextColor(1, 1, 1, CUI.TEXT_DIM_A)
                            highlight:SetAlpha(entry._isSel and CUI.DD_ITEM_SEL_A or 0)
                            IconAlpha(0.4)
                        end
                        entry._overIcon = OverIcon
                        for b, tip in pairs({ [xBtn] = "Delete", [editBtn] = "Rename", [kbBtnI] = "Keybind" }) do
                            b:SetScript("OnEnter", function(self)
                                entry._light()
                                self:SetAlpha(1)
                                CUI.ShowWidgetTooltip(self, CUI.L(tip))
                            end)
                            b:SetScript("OnLeave", function(self)
                                if entry:IsMouseOver() or OverIcon() then
                                    self:SetAlpha(0.8)
                                else
                                    entry._dim()
                                end
                                CUI.HideWidgetTooltip()
                            end)
                        end
                        menuItems[idx] = entry
                    end

                    entry:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -menuH)
                    entry:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -menuH)
                    entry._lbl:SetText(label)
                    entry._isSel = (label == activeName)
                    entry._hl:SetAlpha(entry._isSel and 0.04 or 0)

                    local capName = label
                    local specLocked = specAssigned and specAssigned ~= capName

                    if specLocked then
                        entry._lbl:SetTextColor(1, 1, 1, 0.25)
                        entry._xBtn:Hide()
                        entry._editBtn:Hide()
                        entry._kbBtn:Hide()
                        entry:SetScript("OnClick", nil)
                        entry:SetScript(
                            "OnEnter",
                            function()
                                CUI.ShowWidgetTooltip(
                                    entry,
                                    CUI.L(
                                        "Your current spec has an assigned profile so you cannot switch to another. Please unassign to switch."
                                    )
                                )
                            end
                        )
                        entry:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                    else
                        local iLbl, iXBtn, iEditBtn, iKbBtnL =
                            entry._lbl, entry._xBtn, entry._editBtn, entry._kbBtn
                        iLbl:SetTextColor(1, 1, 1, CUI.TEXT_DIM_A)
                        iEditBtn:Show()
                        iKbBtnL:Show()
                        if capName == activeName then
                            iXBtn:Hide()
                            iEditBtn:ClearAllPoints()
                            iEditBtn:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
                        else
                            iXBtn:Show()
                            iEditBtn:ClearAllPoints()
                            iEditBtn:SetPoint("RIGHT", iXBtn, "LEFT", -4, 0)
                        end
                        entry:SetScript("OnEnter", entry._light)
                        entry:SetScript("OnLeave", function()
                            if not entry._overIcon() then entry._dim() end
                        end)
                        entry:SetScript("OnClick", function()
                            if capName == activeName then return end
                            dropMenu:Hide()
                            local _, profs = CUI.GetProfileList()
                            local asked = SwitchProfileAndAsk(
                                capName,
                                profs and profs[capName],
                                function() ddLabel:SetText(CUI.GetActiveProfileName()) end
                            )
                            -- A live switch only re-points db.profile: cached pages
                            -- (per-profile lists such as the CDM bar dropdown) rebuild.
                            if not asked then
                                CUI:InvalidatePageCache()
                                CUI:RefreshPage(true)
                            end
                        end)
                        iXBtn:SetScript("OnClick", function()
                            if capName == activeName then return end
                            dropMenu:Hide()
                            CUI:ShowConfirmPopup({
                                title = CUI.L("Delete Profile"),
                                message = CUI.Lf('Delete "%1$s"?', capName),
                                confirmText = CUI.L("Delete"),
                                cancelText = CUI.L("Cancel"),
                                onConfirm = function()
                                    CUI.DeleteProfile(capName)
                                    ShowProfileChange()
                                end,
                            })
                        end)
                        iEditBtn:SetScript("OnClick", function()
                            dropMenu:Hide()
                            CUI:ShowInputPopup({
                                title = CUI.L("Rename Profile"),
                                message = CUI.Lf('Enter a new name for "%1$s":', capName),
                                placeholder = capName,
                                confirmText = CUI.L("Rename"),
                                cancelText = CUI.L("Cancel"),
                                onConfirm = function(newName)
                                    newName = newName and strtrim(newName) or ""
                                    if newName == "" or newName == capName then return end
                                    if newName == "Default" then
                                        print(
                                            CUI.L('|cffff6060[CludesUI]|r Cannot rename to "Default".')
                                        )
                                        return
                                    end
                                    local _, profs = CUI.GetProfileList()
                                    if profs and profs[newName] then
                                        print(
                                            CUI.Lf(
                                                '|cffff6060[CludesUI]|r A profile named "%1$s" already exists.',
                                                newName
                                            )
                                        )
                                        return
                                    end
                                    CUI.RenameProfile(capName, newName)
                                    ShowProfileChange()
                                end,
                            })
                        end)
                        iKbBtnL:SetScript("OnClick", function()
                            dropMenu:Hide()
                            ShowProfileKeybindPopup(capName)
                        end)
                    end

                    entry:Show()
                    menuH = menuH + 26
                end
            end
            dropMenu:SetHeight(menuH + 4)
        end

        -- The dropdown stays lit while its menu is open.
        local function ActiveApplyNormal() ddPaint(false) end
        local function ActiveApplyHover() ddPaint(true) end

        dropdownBtn:SetScript("OnClick", function()
            if dropMenu:IsShown() then
                dropMenu:Hide()
            else
                RebuildProfileMenu()
                dropMenu:Show()
            end
        end)
        dropdownBtn:SetScript("OnEnter", function() ActiveApplyHover() end)
        dropdownBtn:SetScript("OnLeave", function()
            if not dropMenu:IsShown() then ActiveApplyNormal() end
        end)
        dropdownBtn:HookScript("OnHide", function() dropMenu:Hide() end)
        dropMenu:HookScript("OnShow", function() ActiveApplyHover() end)
        dropMenu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            if dropdownBtn:IsMouseOver() then
                ActiveApplyHover()
            else
                ActiveApplyNormal()
            end
        end)

        -- The other two columns: a caption, then a plain button under it.
        local function Caption(text, anchor, x)
            local fs = CUI.MakeFont(lineFrame, 12, nil, 1, 1, 1, 0.45)
            PanelPx.Point(fs, "LEFT", anchor, "LEFT", x, 0)
            fs:SetText(text)
            fs:SetJustifyH("LEFT")
            return fs
        end
        local function ColumnButton(caption, text, onClick)
            local button = CreateFrame("Button", nil, lineFrame)
            PanelPx.Size(button, BTN_W, CTRL_H)
            PanelPx.Point(button, "TOPLEFT", caption, "BOTTOMLEFT", 0, -6)
            button:SetFrameLevel(lineFrame:GetFrameLevel() + 2)
            CUI.MakeStyledButton(button, text, 11, PROF_BTN_COLOURS, onClick)
            return button
        end

        -- Assign to Spec (Assign to Class on WoW Forever, which has no specs:
        -- the popup lists one row per class there). The popup edits each
        -- profile's set of specs; the account keeps spec -> profile.
        local function OpenSpecAssign()
            local db = CludesUIDB or {}
            db.specProfiles = db.specProfiles or {}
            local order, profileList = CUI.GetProfileList()
            local specsOf = {}
            for _, label in ipairs(order) do
                specsOf[label] = {}
            end
            for specID, label in pairs(db.specProfiles) do
                if specsOf[label] then specsOf[label][specID] = true end
            end
            local tempDB = { _profileSpecs = specsOf }
            CUI:ShowSpecAssignPopup({
                db = tempDB,
                dbKey = "_profileSpecs",
                presetKey = CUI.GetActiveProfileName(),
                allPresetKeys = function()
                    local list = {}
                    for _, label in ipairs(order) do
                        if profileList[label] then list[#list + 1] = { key = label, name = label } end
                    end
                    return list
                end,
                onDone = function()
                    db.specProfiles = {}
                    for label, specSet in pairs(tempDB._profileSpecs) do
                        for specID in pairs(specSet) do
                            db.specProfiles[specID] = label
                        end
                    end
                    CUI:RefreshPage()
                end,
            })
        end
        local forever = CUI.IS_FOREVER
        local specLabel = Caption(
            forever and CUI.L("Assign to Class") or CUI.L("Assign to Spec"),
            profLabel,
            DD_W + GAP
        )
        ColumnButton(specLabel, forever and "Assign to Class" or "Assign to Spec", OpenSpecAssign)

        -- New Profile: a copy of the current one under a new name, then a
        -- reload that switches to it (the copy is the reload's pre-work).
        local function CopyProfile(label)
            label = label and strtrim(label) or ""
            if label == "" then return end
            local _, profileList = CUI.GetProfileList()
            if profileList and profileList[label] then
                CUI:ShowConfirmPopup({
                    title = CUI.L("Name Taken"),
                    message = CUI.Lf(
                        'A profile named "%1$s" already exists. Please choose a different name.',
                        label
                    ),
                    confirmText = CUI.L("OK"),
                    hideCancel = true,
                    onConfirm = function() end,
                })
                return
            end
            CUI.RequestReload(
                CUI.L("Copy Profile"),
                CUI.L("Reload to finish switching to the new profile."),
                function() CUI.SaveCurrentAsProfile(label) end
            )
        end
        local newLabel = Caption(CUI.L("New Profile"), specLabel, BTN_W + GAP)
        ColumnButton(
            newLabel,
            "Create New (Copy)",
            function()
                CUI:ShowInputPopup({
                    title = CUI.L("Copy Profile"),
                    message = CUI.L("Enter a name for the new profile:"),
                    placeholder = CUI.L("My Profile"),
                    confirmText = CUI.L("Save"),
                    cancelText = CUI.L("Cancel"),
                    onConfirm = CopyProfile,
                })
            end
        )

        y = y - ROW_H
    end

    -------------------------------------------------------------------
    --  PER-ADDON EXPORT
    -------------------------------------------------------------------
    _, h = W:Spacer(parent, y, 18)
    y = y - h

    do
        local ADDON_DB_MAP_LOCAL = CUI.VisibleProfileAddons(CUI._ADDON_DB_MAP)
        local PAD = CUI.CONTENT_PAD
        local fullWidth = parent:GetWidth() - PAD * 2
        -- Single footer row: count + "Include layout" + "Include Global Settings" side by side, Export button on the right.
        local FOOTER_H = 50

        -- Build addon item list
        local selectedAddons = {}
        local includeLayoutExport = true -- "Edit Layout Positions" include (default on)
        local includeGlobalsExport = true -- "Global Settings" include (default on)
        -- "Overrides" include: nil = AUTO -- ON when every loaded module is checked, OFF for subsets, until the user toggles it in the
        -- Include dropdown. Resolved via EffectiveIncludeOverrides (footer block).
        local includeOverridesExport = nil
        local EffectiveIncludeOverrides
        -- "Window & Tooltip Skins": the Blizz UI Enhanced account-global bundle (Window Skins + Tooltips, Menus & Popups). Default OFF --
        -- an importer who opts in gets them across ALL of their profiles.
        local includeWindowSkinsExport = false
        local addonItems = {}
        local addonVisuals = {}
        local footerCountFs
        -- Module connectivity from the LIVE active-profile layout (LOCAL folders, matching selectedAddons' keyspace). Drives the hard-couple + affordance.
        local exportComponents = CUI.BuildModuleComponents({
            anchors = CludesUIDB and CludesUIDB.unlockAnchors,
            widthMatch = CludesUIDB and CludesUIDB.unlockWidthMatch,
            heightMatch = CludesUIDB and CludesUIDB.unlockHeightMatch,
        })
        local FOLDER_DISPLAY = {}
        for _, entry in ipairs(ADDON_DB_MAP_LOCAL) do
            FOLDER_DISPLAY[entry.folder] = entry.display
        end

        for _, entry in ipairs(ADDON_DB_MAP_LOCAL) do
            local loaded = CUI.IsModuleAddonLoaded(entry.folder)
            local moduleFolder = entry.folder
            addonItems[#addonItems + 1] = {
                folder = moduleFolder,
                display = entry.display,
                desc = ADDON_DESCS[moduleFolder] or "",
                loaded = loaded,
                getVal = function() return selectedAddons[moduleFolder] or false end,
                -- Hard-couple: (un)checking a module sets its whole connected component, gated to loaded (exportable) members.
                setVal = function(value)
                    -- Layout OFF: relationships aren't exported, so skip the hard-couple and let each linked module be picked alone.
                    local members = includeLayoutExport
                        and exportComponents
                        and exportComponents[moduleFolder]
                    if members then
                        for f in pairs(members) do
                            if CUI.IsModuleAddonLoaded(f) then selectedAddons[f] = value or nil end
                        end
                    else
                        selectedAddons[moduleFolder] = value or nil
                    end
                end,
            }
            if loaded then selectedAddons[moduleFolder] = true end
        end

        local function RefreshFooterCount()
            if not footerCountFs then return end
            local count = 0
            for _ in pairs(selectedAddons) do
                count = count + 1
            end
            footerCountFs:SetText(CUI.Lf("Export will include %1$s of %2$s addons.", count, #addonItems))
        end

        local function RefreshAllAddonVisuals()
            for _, fn in ipairs(addonVisuals) do
                fn()
            end
            RefreshFooterCount()
        end

        y = ModuleListCard(parent, PAD, y, fullWidth, {
            title = "Export Profile",
            desc = "Choose which addons to include in your exported profile. Check everything for a full profile export.",
            items = addonItems,
            footerH = FOOTER_H,
            pickable = function(entry) return entry.loaded end,
            refreshAll = RefreshAllAddonVisuals,
            visuals = addonVisuals,
            row = function(entry)
                return {
                    active = entry.loaded,
                    inactiveText = CUI.L("Not Loaded"),
                    inactiveColor = { 1, 1, 1, 0.25 },
                    linked = function()
                        return includeLayoutExport and exportComponents and exportComponents[entry.folder],
                            entry.folder,
                            FOLDER_DISPLAY
                    end,
                    linkedTip = function(list)
                        return CUI.Lf(
                            "Linked by Anchor/Width/Height Matching to: %1$s. These export together.",
                            list
                        )
                    end,
                    blockedTip = CUI.L("Addon not loaded"),
                }
            end,
        })

        -- Footer (inside the background panel)
        y = y - 8

        local footerFrame = FooterBar(parent, PAD, y, fullWidth, FOOTER_H)

        footerCountFs = CUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.40)
        -- Selection count, top-left of the footer. The Include dropdown and Export Profile button sit right-aligned on the same row.
        PanelPx.Point(footerCountFs, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, -16)
        footerCountFs:SetJustifyH("LEFT")
        RefreshFooterCount()

        local EXPORT_BTN_H = 30
        local exportSelBtn, eaLbl, eaBrd = AccentButton(footerFrame, 180, EXPORT_BTN_H, "Export Profile")
        PanelPx.Point(exportSelBtn, "RIGHT", footerFrame, "RIGHT", -SIDE_PAD, 0)

        -- Include: Overrides is AUTO until toggled (on while every loaded module
        -- is checked, off for a subset), so the menu and summary recompute it
        -- on every open and hover.
        local function AllLoadedSelected()
            for _, entry in ipairs(addonItems) do
                if entry.loaded and not selectedAddons[entry.folder] then return false end
            end
            return true
        end
        EffectiveIncludeOverrides = function()
            if includeOverridesExport ~= nil then return includeOverridesExport end
            return AllLoadedSelected()
        end

        local rowDefs = {
            {
                label = "Overrides",
                sum = "Overrides",
                tip = "Include your complete override setup: spec and conditional override values, groups, their custom layouts, and Buff Manager overrides. On import this replaces the recipient's overrides entirely.",
                get = function() return EffectiveIncludeOverrides() end,
                set = function() includeOverridesExport = not EffectiveIncludeOverrides() end,
            },
            {
                label = "Edit Layout Positions",
                sum = "Layout",
                tip = "Include the anchor & size-match relationships between modules. Off = export each module's own positions only, with no cross-module tying.",
                get = function() return includeLayoutExport end,
                set = function() includeLayoutExport = not includeLayoutExport end,
            },
            {
                label = "Global Settings",
                sum = "Globals",
                tip = "Include fonts, custom colors, dark mode, accent color and UI scale with this export. Off = only the selected modules' own settings export, keeping the recipient's global look.",
                get = function() return includeGlobalsExport end,
                set = function() includeGlobalsExport = not includeGlobalsExport end,
            },
        }
        -- Window & Tooltip Skins only while that module is loaded (its bundle needs it).
        if CUI.IsModuleAddonLoaded("CludesUIBlizzardSkin") then
            rowDefs[#rowDefs + 1] = {
                label = "Window & Tooltip Skins",
                sum = "Window Skins",
                tip = "Include your Window Styling settings from its General and Tooltips & Menus pages. These are account-wide: if the importer opts in, they overwrite that player's settings across ALL of their profiles.",
                get = function() return includeWindowSkinsExport end,
                set = function() includeWindowSkinsExport = not includeWindowSkinsExport end,
            }
        end
        local dropdownBtn, refreshSummary = IncludeDropdown(footerFrame, exportSelBtn, EXPORT_BTN_H, rowDefs)
        -- Keep the AUTO summary honest after module toggles.
        dropdownBtn:HookScript("OnEnter", refreshSummary)

        MakeAccentFade(exportSelBtn, eaLbl, eaBrd)
        exportSelBtn:SetScript("OnClick", function()
            local folders = {}
            local hasAny = false
            for moduleFolder in pairs(selectedAddons) do
                folders[moduleFolder] = true
                hasAny = true
            end
            if not hasAny then
                if exportSelBtn._flashError then exportSelBtn._flashError() end
                return
            end
            local activeName = CUI.GetActiveProfileName()
            -- Every loaded module checked = FULL export: pass nil folders so the string is a plain full-profile string (no subset stamps),
            -- keeping import defaults and API strings identical.
            local allSelected = true
            for _, entry in ipairs(addonItems) do
                if entry.loaded and not selectedAddons[entry.folder] then
                    allSelected = false
                    break
                end
            end
            local exportFolders = (not allSelected) and folders or nil
            local includeOverrides = EffectiveIncludeOverrides and EffectiveIncludeOverrides() or false
            local function finishExport(includeCDM, cdmSpecs)
                local str = CUI.ExportProfile(
                    activeName,
                    exportFolders,
                    includeLayoutExport,
                    includeCDM,
                    cdmSpecs,
                    includeGlobalsExport,
                    includeOverrides,
                    includeWindowSkinsExport
                )
                if str then CUI:ShowExportPopup(str) end
            end
            -- If the CDM module is selected, run the shared flow (ask -> spec picker); otherwise export straight away with no CDM spell layout.
            if folders["CludesUICooldownManager"] then
                CUI.RunCDMSpellExportFlow(activeName, finishExport)
            else
                finishExport(false, nil)
            end
        end)
        exportSelBtn._flashError = BuildErrorFlash(exportSelBtn, eaBrd)

        y = y - FOOTER_H
    end

    -------------------------------------------------------------------
    --  Interactive Import API hookup (CludesUI.ImportProfileInteractive)
    -------------------------------------------------------------------
    -- Reset the sub-page stack to the main Profiles view. The page wrapper is cached across tab switches, so a declined/replaced API
    -- session would otherwise leave its import page showing on the next visit.
    CUI._ProfilesResetToMain = function()
        importView:Hide()
        pastePage:Hide()
        mainPage:Show()
    end

    -- Continue an API session with its decoded payload: UI-scale prompt (at most once), then the normal selection page. Registered per
    -- build (latest wins) and re-resolved from the namespace by every async continuation, so decode + scale popup land on THIS build's live frames.
    CUI._ProfilesApiProceed = function(bundle)
        local cfg = CUI._apiImportSession
        if not cfg or cfg.state == "done" then return end
        if cfg.scaleAsked then
            ShowImportPage(cfg.str, bundle, cfg.name, nil, nil, cfg.applyScale)
        else
            MaybeConfirmUIScale(bundle, function(applyScale)
                cfg.scaleAsked = true
                cfg.applyScale = applyScale
                local go = CUI._ProfilesApiProceed
                if go then go(bundle) end
            end)
        end
    end

    -- Enter (or re-enter) a pending API import session: decode the string once, then proceed. Called by ImportProfileInteractive after it
    -- navigates here, and self-invoked at each build end so a session survives page rebuilds.
    CUI._ProfilesConsumeApiImport = function()
        local cfg = CUI._apiImportSession
        if not cfg or cfg.state == "done" then return end
        CUI._EnsureApiImportCloseHook()
        cfg.state = "active"
        if cfg.payload then
            CUI._ProfilesApiProceed(cfg.payload)
        elseif not cfg.decoding then
            cfg.decoding = true
            CUI.DecodeImportStringAsync(cfg.str, function(bundle, err)
                cfg.decoding = nil
                -- The session may have been declined or replaced while the decode was in flight; drop a stale result.
                if CUI._apiImportSession ~= cfg or cfg.state == "done" then return end
                if not bundle then
                    CUI:ShowInfoPopup({
                        title = CUI.L("Import Failed"),
                        content = err or CUI.L("Invalid import string."),
                    })
                    CUI._FinishApiImportSession(false)
                    return
                end
                cfg.payload = bundle
                local go = CUI._ProfilesApiProceed
                if go then go(bundle) end
            end)
        end
    end
    CUI._ProfilesConsumeApiImport()

    return 0
end
