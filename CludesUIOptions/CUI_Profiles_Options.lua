if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Profiles_Options.lua -- Global Settings > Profiles (and its Presets
--  subpage). It registers nothing: the Global Settings module
--  (CUI__General_Options.lua) dispatches its builder.
-------------------------------------------------------------------------------
local PP = CludesUI.PanelPP

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame. The profiles root is kept for the session
-- (PROFILES_ROOT owns it), so everything built on it is pooled.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolKept, PoolBegin, PoolManaged = CludesUI._Pool.Kept, CludesUI._Pool.Begin, CludesUI._Pool.Managed
local PoolGen, PoolIsIdle = CludesUI._Pool.Gen, CludesUI._Pool.IsIdle
local PROFILES_ROOT = {}

-- A deferred callback's frame is still in the dress it had when the callback
-- was scheduled (gen = PoolGen(obj) then): a rebuild dresses the same pooled
-- frames again, so a callback from before it must leave them alone.
local function SameDress(obj, gen)
    return PoolGen(obj) == gen and not PoolIsIdle(obj)
end

---------------------------------------------------------------------------
--  Profiles page
---------------------------------------------------------------------------

-- The UI scale an imported string is measured against: the player's pixel
-- perfect scale when they set one, else the game's. Two scales count as the
-- same within 2%.
local function MyScale()
    return CludesUIDB and CludesUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
end
local function Pct(scale)
    return math.floor(scale * 100 + 0.5)
end
local function ScalesDiffer(a, b)
    return math.abs(a - b) > 0.02
end

-- The red warning for a decoded string made on a different UI scale or
-- resolution (nil when both match). skipScale: the player already took the
-- string's scale, so only the resolution can still be off.
local function BuildScaleWarning(payload, skipScale)
    local meta = payload and payload.meta
    if not meta then
        return nil
    end
    local lines = {}
    local mine, theirs = MyScale(), meta.cuiScale or meta.uiScale
    if not skipScale and theirs and ScalesDiffer(mine, theirs) then
        lines[#lines + 1] =
            CludesUI.Lf("UI Scale Issue: Profile was made at %1$d%%, yours is %2$d%%", Pct(theirs), Pct(mine))
    end
    local w, h = GetPhysicalScreenSize()
    w, h = w and math.floor(w) or 0, h and math.floor(h) or 0
    local madeW, madeH = meta.screenW or 0, meta.screenH or 0
    if madeW > 0 and madeH > 0 and (w ~= madeW or h ~= madeH) then
        lines[#lines + 1] = CludesUI.Lf(
            "Resolution Issue: Profile was made at %1$dx%2$d, yours is %3$dx%4$d",
            madeW,
            madeH,
            w,
            h
        )
    end
    if #lines == 0 then
        return nil
    end
    return CludesUI.L("WARNING: Frame positions may be off.") .. "\n" .. table.concat(lines, "\n")
end

-- Between choosing a string or preset and the import options: a string that
-- carries another UI scale asks once whether to take it. cont(takeScale)
-- always runs (Escape and a click outside count as Keep Mine), so the page
-- change can never stall; with true the options page drops its scale line.
local function MaybeConfirmUIScale(payload, cont)
    local data = payload and payload.data
    local theirs = data and type(data.uiScale) == "number" and data.uiScale or nil
    local mine = MyScale()
    if not theirs or not ScalesDiffer(mine, theirs) then
        cont(false)
        return
    end
    CludesUI:ShowConfirmPopup({
        title = CludesUI.L("UI Scale Mismatch"),
        message = CludesUI.Lf(
            "This profile was made at %1$d%% UI scale; yours is %2$d%%. Change your UI scale to match the imported profile? This will show all profiles at this scale as UI Scale is not a per-profile setting, but can be changed at any time back to your original value.",
            Pct(theirs),
            Pct(mine)
        ),
        confirmText = CludesUI.L("Match Scale"),
        cancelText = CludesUI.L("Keep Mine"),
        onConfirm = function()
            cont(true)
        end,
        onCancel = function()
            cont(false)
        end,
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
    CludesUIQuestTracker = "A clean, updated reskin of Blizzard's Quest Tracker.",
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
    local EG = CludesUI.CLUDES_GREEN
    local boxFrame = CreateFrame("Frame", nil, parent)
    boxFrame:SetSize(CHK_SZ, CHK_SZ)
    local bg = boxFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.114, 0.106, 0.099, 1)
    if exact then
        Unsnapped(bg)
    end
    local border = CludesUI.MakeRoundedBorder(boxFrame, 0.224, 0.215, 0.207, 0.6, bg)
    local tick = boxFrame:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 3, -3)
    tick:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -3, 3)
    tick:SetColorTexture(EG.r, EG.g, EG.b, 1)
    CludesUI.RoundBody(boxFrame, tick, 1)
    if exact then
        Unsnapped(tick)
    end
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
local function BuildAddonListRow(scrollChild, i, entry, totalW, o)
    local EG = CludesUI.CLUDES_GREEN
    local rowFrame = CreateFrame("Frame", nil, scrollChild)
    rowFrame:SetSize(totalW, ROW_H_A)
    rowFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_H_A)
    -- Alternate rows a shade darker.
    local rowBg = rowFrame:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    rowBg:SetColorTexture(0, 0, 0, (i % 2 == 0) and 0.12 or 0.06)

    local nameFs = CludesUI.MakeFont(rowFrame, 13, nil, 1, 1, 1, 0.9)
    nameFs:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", SIDE_PAD, -10)
    nameFs:SetPoint("RIGHT", rowFrame, "RIGHT", -(CHK_SZ + STATUS_W + SIDE_PAD * 2 + 20), 0)
    nameFs:SetJustifyH("LEFT")
    nameFs:SetWordWrap(false)
    nameFs:SetText(CludesUI.L(entry.display))

    local descFs = CludesUI.MakeFont(rowFrame, 11, nil, 1, 1, 1, 0.30)
    descFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -5)
    descFs:SetPoint("RIGHT", nameFs, "RIGHT", 0, 0)
    descFs:SetJustifyH("LEFT")
    descFs:SetWordWrap(false)
    descFs:SetText(CludesUI.L(entry.desc))

    local statusFs = CludesUI.MakeFont(rowFrame, 11, nil, 1, 1, 1, 0.40)
    statusFs:SetPoint("RIGHT", rowFrame, "RIGHT", -SIDE_PAD, 0)
    statusFs:SetJustifyH("RIGHT")

    -- The box sits under the Include column header.
    local boxFrame, tick, boxBorder, boxBg = CheckBox(rowFrame, true)
    boxFrame:SetPoint("CENTER", rowFrame, "RIGHT", INCLUDE_CENTER_X, 0)

    local function ApplyRowVisual()
        local state = not o.active and "blocked" or (entry.getVal() and "included" or "skipped")
        local look = ROW_LOOK[state]
        nameFs:SetAlpha(look.name)
        descFs:SetAlpha(look.desc)
        tick:SetShown(look.tick)
        boxBg:SetAlpha(look.box)
        if state == "blocked" then
            local c = o.inactiveColor
            statusFs:SetText(o.inactiveText)
            statusFs:SetTextColor(c[1], c[2], c[3], c[4])
        elseif state == "included" then
            boxBorder:SetColor(EG.r, EG.g, EG.b, 0.15)
            statusFs:SetText(CludesUI.L("Ready"))
            statusFs:SetTextColor(0.196, 0.737, 0.325, 1)
        else
            boxBorder:SetColor(0.224, 0.215, 0.207, 0.6)
            statusFs:SetText(CludesUI.L("Skipped"))
            statusFs:SetTextColor(1, 1, 1, 0.35)
        end
    end
    ApplyRowVisual()
    o.visuals[#o.visuals + 1] = ApplyRowVisual

    local hoverTex = rowFrame:CreateTexture(nil, "ARTWORK")
    hoverTex:SetAllPoints()
    hoverTex:SetColorTexture(1, 1, 1, 0.05)
    hoverTex:Hide()

    if not o.active then
        -- Inactive: the row swallows the mouse, and explains itself if it can.
        local blockFrame = CreateFrame("Frame", nil, rowFrame)
        blockFrame:SetAllPoints()
        blockFrame:SetFrameLevel(rowFrame:GetFrameLevel() + 5)
        blockFrame:EnableMouse(true)
        local tip = o.blockedTip
        blockFrame:SetScript("OnEnter", function()
            if tip then
                hoverTex:Show()
                CludesUI.ShowWidgetTooltip(rowFrame, tip)
            end
        end)
        blockFrame:SetScript("OnLeave", function()
            if tip then
                hoverTex:Hide()
                CludesUI.HideWidgetTooltip()
            end
        end)
        return
    end
    local clickBtn = CreateFrame("Button", nil, rowFrame)
    clickBtn:SetAllPoints(rowFrame)
    clickBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
    clickBtn:SetScript("OnClick", function()
        entry.setVal(not entry.getVal())
        o.onToggle(ApplyRowVisual)
    end)
    clickBtn:SetScript("OnEnter", function()
        hoverTex:Show()
        if not entry.getVal() then
            nameFs:SetAlpha(0.75)
        end
        -- The modules this one carries along (nothing couples while layout is off).
        local members, own, display = o.linked()
        if not members then
            return
        end
        local names = {}
        for folder in pairs(members) do
            if folder ~= own then
                names[#names + 1] = CludesUI.L(display[folder] or folder)
            end
        end
        if #names > 0 then
            table.sort(names)
            CludesUI.ShowWidgetTooltip(rowFrame, o.linkedTip(table.concat(names, ", ")))
        end
    end)
    clickBtn:SetScript("OnLeave", function()
        hoverTex:Hide()
        if not entry.getVal() then
            nameFs:SetAlpha(0.50)
        end
        CludesUI.HideWidgetTooltip()
    end)
end

-- Done-style button hover: label and border alpha fade 0.7 -> 1 over 0.1s.
-- Returns reset(), which snaps the fade back to idle.
local function MakeAccentFade(button, caption, brd)
    local EG = CludesUI.CLUDES_GREEN
    local lerp = CludesUI.lerp
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
local function SwitchProfileAndAsk(name, profile, afterSwitch)
    local font = CludesUI.ProfileChangesFont(profile)
    local skins = CludesUI.ProfileChangesWindowSkins(profile)
    local style = CludesUI.ProfileChangesStyle(profile)
    CludesUI.SwitchProfile(name)
    if afterSwitch then
        afterSwitch()
    end
    CludesUI.RefreshAllAddons(true)
    if not (font or skins or style) then
        return false
    end
    CludesUI:ShowConfirmPopup({
        title = CludesUI.L("Reload Required"),
        message = font and CludesUI.L("Font changed. A UI reload is needed to apply the new font.")
            or skins and CludesUI.L(
                "Window skins changed for this profile. A UI reload is needed to apply them."
            )
            or CludesUI.L("Style changed for this profile. A UI reload is needed to apply it."),
        confirmText = CludesUI.L("Reload Now"),
        cancelText = CludesUI.L("Later"),
        reload = true,
    })
    return true
end

-- A profile's keybind popup: built on its first open and kept across page
-- builds; each open points it at that profile (ShowProfileKeybindPopup).
local profileKeybindPopup

function _G._CUI_BuildProfilesPage(pageName, parent, yOffset)
    local W = CludesUI.Widgets
    local y = yOffset
    local _, h
    local FONT = CludesUI.EXPRESSWAY
    local EG = CludesUI.CLUDES_GREEN
    local MEDIA = "Interface\\AddOns\\CludesUI\\media\\"

    -- Safety net: the active profile follows the current spec's assignment
    -- (spec info can be missing at login, so it may not have switched then).
    do
        local sid = CurrentSpecID()
        local assigned = sid and CludesUI.GetSpecProfile(sid)
        if assigned and assigned ~= CludesUI.GetActiveProfileName() then
            local _, profiles = CludesUI.GetProfileList()
            if profiles and profiles[assigned] then
                SwitchProfileAndAsk(assigned, profiles[assigned])
            end
        end
    end

    if parent then
        parent._showRowDivider = false
    end

    -- Built on the scroll frame itself, not its scroll child.
    local scrollFrame = CludesUI._scrollFrame
    if not scrollFrame then
        return 0
    end

    -- One root for the session: each build dresses it again, and its previous
    -- contents reset to new first (the reset hides whatever they showed).
    local root = PoolKept(PROFILES_ROOT, "root", "Frame", scrollFrame)
    root:SetAllPoints(scrollFrame)
    root:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
    CludesUI._profilesRoot = root

    -- Three pages over the root, one shown at a time: the profiles list, the
    -- import options and the paste box.
    local function Page(shown)
        local page = CreateFrame("Frame", nil, root)
        page:SetAllPoints(root)
        page:SetFrameLevel(root:GetFrameLevel())
        if not shown then
            page:Hide()
        end
        return page
    end
    local mainPage, importPage, pastePage = Page(true), Page(false), Page(false)
    parent = mainPage
    y = -10

    -- Plain buttons: the wide button's colours with the dropdowns' white
    -- border (rest and hover alpha).
    local PROF_BTN_COLOURS = { unpack(CludesUI.WB_COLOURS, 1, 24) }
    for i, value in ipairs({ 1, 1, 1, CludesUI.DD_BRD_A, 1, 1, 1, CludesUI.DD_BRD_HA }) do
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
        PP.Size(button, w, ddH)
        button:SetFrameLevel(parentFrame:GetFrameLevel() + 2)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, CludesUI.DD_BG_A)
        local brd = CludesUI.MakeRoundedBorder(button, 1, 1, 1, CludesUI.DD_BRD_A, bg)
        -- The resting alpha is the text colour's, the channel the hover
        -- colours write, so a hover and leave land back on it.
        local caption = CludesUI.MakeFont(button, 13, nil, 1, 1, 1, CludesUI.DD_TXT_A)
        caption:SetJustifyH("LEFT")
        caption:SetWordWrap(false)
        caption:SetMaxLines(1)
        caption:SetPoint("LEFT", button, "LEFT", 12, 0)
        local arrow = CludesUI.MakeDropdownArrow(button, 12, PP)
        caption:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
        caption:SetText(getLabel())
        -- RD_DD_COLOURS: background, hover background, border, hover border,
        -- text, hover text (four values each).
        local s = CludesUI.RD_DD_COLOURS
        local function Paint(hot)
            local o = hot and 4 or 0
            caption:SetTextColor(s[17 + o], s[18 + o], s[19 + o], s[20 + o])
            brd:SetColor(s[9 + o], s[10 + o], s[11 + o], s[12 + o])
            bg:SetColorTexture(s[1 + o], s[2 + o], s[3 + o], s[4 + o])
        end
        button:SetScript("OnEnter", function()
            Paint(true)
        end)
        button:SetScript("OnLeave", function()
            Paint(false)
        end)
        button._getLabel = getLabel
        return button, caption, bg, brd, Paint
    end

    -- One menu per dropdown button, kept with the button: a build that dresses
    -- the button again dresses its menu again too. A press outside both closes it.
    local function MakeDropdownMenu(anchor, w)
        local menu = PoolKept(anchor, "profilesMenu", "Frame", UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(200)
        menu:SetClampedToScreen(true)
        menu:SetSize(w, 4)
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        menu:Hide()
        local bg = menu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, 0.98)
        CludesUI.MakeRoundedBorder(menu, 1, 1, 1, CludesUI.DD_BRD_A, bg, nil, true)
        local function WatchOutside(m)
            local away = not anchor:IsMouseOver() and not m:IsMouseOver()
            if away and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
                m:Hide()
            end
        end
        menu:SetScript("OnShow", function(self)
            -- On UIParent, drawn at the panel's scale.
            self:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
            self:SetScript("OnUpdate", WatchOutside)
        end)
        menu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)
        return menu
    end

    -- Hoisted so the import callback can update it
    local ddLabel
    -- After a profile was deleted, renamed or added: the dropdown shows the
    -- active one and every page rebuilds.
    local function ShowProfileChange()
        ddLabel:SetText(CludesUI.GetActiveProfileName())
        CludesUI:InvalidatePageCache()
        CludesUI:RefreshPage(true)
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

        local popup = CreateFrame("Frame", nil, shade)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(shade:GetFrameLevel() + 10)
        popup:SetSize(320, 130)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:EnableMouse(true)
        popup:SetClampedToScreen(true)
        popup._dimmer = shade
        shade:SetScript("OnMouseDown", function()
            if not popup:IsMouseOver() then
                shade:Hide()
            end
        end)

        local popBg = popup:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints()
        popBg:SetColorTexture(0.062, 0.070, 0.082, 0.97)
        CludesUI.MakeRoundedBorder(popup, 1, 1, 1, 0.20, popBg)
        local title = CludesUI.MakeFont(popup, 14, nil, 1, 1, 1)
        title:SetPoint("TOP", popup, "TOP", 0, -14)
        popup._title = title

        -- Reads and writes the profile the popup was last opened for.
        local kbBtn, kbRefresh = CludesUI.BuildKeybindButton(popup, {
            w = 160,
            h = 30,
            font = 13,
            get = function()
                return CludesUI.GetProfileKeybind(popup._profileName)
            end,
            set = function(value)
                CludesUI.SetProfileKeybind(popup._profileName, value)
            end,
        })
        kbBtn:SetPoint("CENTER", popup, "CENTER", 0, -2)
        popup._kbRefresh = kbRefresh
        local hint = CludesUI.MakeFont(popup, 10, nil, 1, 1, 1, 0.35)
        hint:SetPoint("BOTTOM", popup, "BOTTOM", 0, 12)
        hint:SetText(CludesUI.L("Left-click to set  |  Right-click to unbind  |  Esc to close"))

        -- kbBtn's own OnHide cancels a capture in progress.
        popup:SetScript("OnHide", function()
            if popup._dimmer then
                popup._dimmer:Hide()
            end
        end)
        -- It sits on UIParent, so it closes with the panel, which closes as
        -- combat starts: a screen-wide dimmer and an armed key capture never
        -- stay up into combat.
        CludesUI:RegisterOnHide(function()
            if shade:IsShown() then
                shade:Hide()
            end
        end)
        CludesUI.PopupTakeKeys(popup, shade)
        -- Escape closes it, unless the button is capturing (it then owns the keys).
        popup:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then
                return
            end
            local close = key == "ESCAPE" and not kbBtn:IsKeyboardEnabled()
            self:SetPropagateKeyboardInput(not close)
            if close then
                shade:Hide()
            end
        end)
        return popup
    end

    local function ShowProfileKeybindPopup(profileName)
        local popup = profileKeybindPopup
        if not popup then
            popup = BuildKeybindPopup()
            profileKeybindPopup = popup
        elseif popup._dimmer:IsShown() then
            -- Still open: closed first, cancelling a capture in progress.
            popup._dimmer:Hide()
        end
        popup._profileName = profileName
        popup._title:SetText(CludesUI.Lf("Keybind: %1$s", profileName))
        popup._kbRefresh()
        popup:Show()
        popup._dimmer:Show()
    end

    -- A button's border flashes red, fading back to its resting white over 0.7s.
    local function BuildErrorFlash(button, brd)
        local flashFrame = CreateFrame("Frame", nil, button)
        flashFrame:Hide()
        local lerp = CludesUI.lerp
        local DUR = 0.7
        local elapsed = 0
        local function Paint(t)
            brd:SetColor(lerp(0.9, 1, t), lerp(0.15, 1, t), lerp(0.15, 1, t), lerp(0.7, CludesUI.DD_BRD_A, t))
        end
        flashFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= DUR then
                self:Hide()
                brd:SetColor(1, 1, 1, CludesUI.DD_BRD_A)
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
        PP.Size(backBtn, BACK_W, BACK_H)
        PP.Point(backBtn, "TOPLEFT", page, "TOPLEFT", pad, top)
        backBtn:SetFrameLevel(page:GetFrameLevel() + 2)
        local backBg = backBtn:CreateTexture(nil, "BACKGROUND")
        backBg:SetAllPoints()
        backBg:SetColorTexture(0.062, 0.070, 0.082, 0.50)
        local backBrd = CludesUI.MakeRoundedBorder(backBtn, 1, 1, 1, 0.12, backBg)
        local backIcon = backBtn:CreateTexture(nil, "ARTWORK")
        backIcon:SetSize(14, 14)
        PP.Point(backIcon, "LEFT", backBtn, "LEFT", 10, 0)
        backIcon:SetTexture(MEDIA .. "icons\\cui-arrow-left.png")
        backIcon:SetVertexColor(EG.r, EG.g, EG.b)
        backIcon:SetAlpha(0.6)
        Unsnapped(backIcon)
        local backLbl = CludesUI.MakeFont(backBtn, 12, nil, 1, 1, 1, 0.55)
        PP.Point(backLbl, "LEFT", backIcon, "RIGHT", 6, 0)
        backLbl:SetText(CludesUI.L("Back"))
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
        backBtn:SetScript("OnEnter", function()
            Paint(true)
        end)
        backBtn:SetScript("OnLeave", function()
            Paint(false)
        end)
        backBtn:SetScript("OnClick", function()
            page:Hide()
            mainPage:Show()
        end)
        local titleFs = CludesUI.MakeFont(page, 16, nil, 1, 1, 1, 0.95)
        PP.Point(titleFs, "TOP", page, "TOP", 0, top - BACK_H / 2 + 8)
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
    local function ModuleListCard(host, pad, top, totalW, cfg)
        local HDR_H, COL_HDR_H, SCROLL_MAX_H = 72, 28, 285
        local items = cfg.items
        local contentH = #items * ROW_H_A
        local scrollH = math.min(contentH, SCROLL_MAX_H)
        local y = top

        local card = CreateFrame("Frame", nil, host)
        card:SetFrameLevel(host:GetFrameLevel())
        PP.Size(card, totalW, HDR_H + COL_HDR_H + scrollH + 8 + cfg.footerH)
        PP.Point(card, "TOPLEFT", host, "TOPLEFT", pad, y)
        card:EnableMouse(false)
        CludesUI.MakeRoundedCard(card, 0.10, 0.50)

        local hdrFrame = CreateFrame("Frame", nil, host)
        PP.Size(hdrFrame, totalW, HDR_H)
        PP.Point(hdrFrame, "TOPLEFT", host, "TOPLEFT", pad, y)
        local hdrTitle = CludesUI.MakeFont(hdrFrame, 14, nil, 1, 1, 1, 0.9)
        PP.Point(hdrTitle, "TOPLEFT", hdrFrame, "TOPLEFT", SIDE_PAD, -20)
        hdrTitle:SetText(CludesUI.L(cfg.title))
        hdrTitle:SetJustifyH("LEFT")
        local hdrDesc = CludesUI.MakeFont(hdrFrame, 11, nil, 1, 1, 1, 0.35)
        PP.Point(hdrDesc, "TOPLEFT", hdrTitle, "BOTTOMLEFT", 0, -9)
        PP.Point(hdrDesc, "RIGHT", hdrFrame, "RIGHT", -(160 + SIDE_PAD), 0)
        hdrDesc:SetText(CludesUI.L(cfg.desc))
        hdrDesc:SetJustifyH("LEFT")
        hdrDesc:SetWordWrap(true)
        local hdrDiv = hdrFrame:CreateTexture(nil, "ARTWORK")
        hdrDiv:SetColorTexture(1, 1, 1, 0.10)
        hdrDiv:SetHeight(1)
        PP.Point(hdrDiv, "BOTTOMLEFT", hdrFrame, "BOTTOMLEFT", SIDE_PAD, 0)
        PP.Point(hdrDiv, "BOTTOMRIGHT", hdrFrame, "BOTTOMRIGHT", -SIDE_PAD, 0)
        Unsnapped(hdrDiv)

        -- Select All (accent while everything pickable is in) | Deselect All.
        local LINK_GAP = 12
        local function Link(text)
            local button = CreateFrame("Button", nil, hdrFrame)
            button:SetFrameLevel(hdrFrame:GetFrameLevel() + 2)
            local caption = button:CreateFontString(nil, "OVERLAY")
            caption:SetFont(FONT, 12, CludesUI.GetFontOutlineFlag())
            caption:SetText(CludesUI.L(text))
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
                if cfg.pickable(entry) and not entry.getVal() then
                    return false
                end
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
        selAllBtn:SetScript("OnEnter", function()
            PaintSelectAll(true)
        end)
        selAllBtn:SetScript("OnLeave", function()
            PaintSelectAll(false)
        end)
        selAllBtn:SetScript("OnClick", function()
            for _, entry in ipairs(items) do
                if cfg.pickable(entry) then
                    entry.setVal(true)
                end
            end
            Refresh()
        end)
        PaintSelectAll(false)
        local linkDiv = hdrFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        linkDiv:SetColorTexture(1, 1, 1, 0.15)
        Unsnapped(linkDiv)
        PP.Point(linkDiv, "LEFT", selAllBtn, "RIGHT", LINK_GAP / 2, 0)
        linkDiv:SetWidth(1)
        linkDiv:SetHeight(10)
        local deselBtn, deselLbl = Link("Deselect All")
        PP.Point(deselBtn, "LEFT", selAllBtn, "RIGHT", LINK_GAP, 0)
        deselBtn:SetScript("OnEnter", function()
            deselLbl:SetTextColor(1, 1, 1, 0.80)
        end)
        deselBtn:SetScript("OnLeave", function()
            deselLbl:SetTextColor(1, 1, 1, 0.40)
        end)
        deselBtn:SetScript("OnClick", function()
            for _, entry in ipairs(items) do
                entry.setVal(false)
            end
            Refresh()
        end)
        y = y - HDR_H

        -- Column titles over the name, the Include box and the status.
        local colHdrFrame = CreateFrame("Frame", nil, host)
        PP.Size(colHdrFrame, totalW, COL_HDR_H)
        PP.Point(colHdrFrame, "TOPLEFT", host, "TOPLEFT", pad, y)
        for _, col in ipairs({
            { "Addon", "LEFT", "LEFT", SIDE_PAD },
            { "Status", "RIGHT", "RIGHT", -SIDE_PAD },
            { "Include", "CENTER", "RIGHT", INCLUDE_CENTER_X },
        }) do
            local fs = CludesUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
            PP.Point(fs, col[2], colHdrFrame, col[3], col[4], 0)
            fs:SetText(CludesUI.L(col[1]))
            fs:SetJustifyH(col[2])
        end
        y = y - COL_HDR_H

        -- The rows, clipped to SCROLL_MAX_H and wheel-scrolled a row at a time.
        local scrollClip = CreateFrame("Frame", nil, host)
        PP.Size(scrollClip, totalW, scrollH)
        PP.Point(scrollClip, "TOPLEFT", host, "TOPLEFT", pad, y)
        scrollClip:SetClipsChildren(true)
        local scroller = CreateFrame("ScrollFrame", nil, scrollClip)
        scroller:SetAllPoints()
        local scrollChild = CreateFrame("Frame", nil, scroller)
        scrollChild:SetSize(totalW, contentH)
        scroller:SetScrollChild(scrollChild)
        local offset = 0
        scrollClip:EnableMouseWheel(true)
        scrollClip:SetScript("OnMouseWheel", function(_, delta)
            if CludesUI._ShiftWheelScale(delta) then
                return
            end
            offset = math.max(0, math.min(math.max(0, contentH - scrollH), offset - delta * ROW_H_A))
            scroller:SetVerticalScroll(offset)
        end)
        for i, entry in ipairs(items) do
            local o = cfg.row(entry)
            o.visuals = cfg.visuals
            -- Linked modules toggle together, so every row repaints.
            o.onToggle = Refresh
            BuildAddonListRow(scrollChild, i, entry, totalW, o)
        end
        return y - scrollH
    end

    -- A section footer under a module list: its frame and top rule.
    local function FooterBar(host, pad, top, totalW, height)
        local footer = CreateFrame("Frame", nil, host)
        PP.Size(footer, totalW, height)
        PP.Point(footer, "TOPLEFT", host, "TOPLEFT", pad, top)
        local rule = footer:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 1, 1, 0.10)
        rule:SetHeight(1)
        PP.Point(rule, "TOPLEFT", footer, "TOPLEFT", SIDE_PAD, 0)
        PP.Point(rule, "TOPRIGHT", footer, "TOPRIGHT", -SIDE_PAD, 0)
        Unsnapped(rule)
        return footer
    end

    -- A Done-style button: accent border and text on the dark background (the
    -- caller adds MakeAccentFade for the hover). Returns button, label, border.
    local function AccentButton(host, w, h, text, fontSize)
        local button = CreateFrame("Button", nil, host)
        PP.Size(button, w, h)
        button:SetFrameLevel(host:GetFrameLevel() + 2)
        local DB = CludesUI.DARK_BG
        local bg = CludesUI.SolidTex(button, "BACKGROUND", DB.r, DB.g, DB.b, 0.92)
        bg:SetAllPoints()
        local brd = CludesUI.MakeRoundedBorder(button, EG.r, EG.g, EG.b, 0.7, bg)
        local caption = CludesUI.MakeFont(button, fontSize or 12, nil, EG.r, EG.g, EG.b)
        caption:SetAlpha(0.7)
        caption:SetPoint("CENTER")
        caption:SetText(CludesUI.L(text))
        return button, caption, brd
    end

    -- The "Include:" checkbox dropdown left of a footer's button. rows: label,
    -- sum (its word in the summary), tip, get(), set(refresh, ddBtn); a row
    -- with enabled == false shows dimmed with offTip and takes no clicks. The
    -- button reads Everything, Nothing Extra or the list of what is in.
    -- Returns the dropdown button and its summary refresh.
    local function IncludeDropdown(footer, nextTo, h, rows)
        local dropdownBtn, ddLabelFS = MakeDropdown(footer, 190, h, function()
            return ""
        end)
        PP.Point(dropdownBtn, "RIGHT", nextTo, "LEFT", -12, 0)
        local incLbl = CludesUI.MakeFont(footer, 12, nil, 1, 1, 1, 0.6)
        PP.Point(incLbl, "RIGHT", dropdownBtn, "LEFT", -8, 0)
        incLbl:SetText(CludesUI.L("Include:"))

        local function On(def)
            return def.enabled ~= false and def.get()
        end
        local function RefreshSummary()
            local parts, total = {}, 0
            for _, def in ipairs(rows) do
                if def.enabled ~= false then
                    total = total + 1
                    if def.get() then
                        parts[#parts + 1] = CludesUI.L(def.sum)
                    end
                end
            end
            if #parts == 0 then
                ddLabelFS:SetText(CludesUI.L("Nothing Extra"))
            elseif #parts == total then
                ddLabelFS:SetText(CludesUI.L("Everything"))
            else
                ddLabelFS:SetText(table.concat(parts, ", "))
            end
        end

        local menu = MakeDropdownMenu(dropdownBtn, 240)
        menu:SetSize(240, #rows * 26 + 8)
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
            local row = CreateFrame("Button", nil, menu)
            row:SetHeight(26)
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -(4 + (i - 1) * 26))
            row:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
            row:SetFrameLevel(menu:GetFrameLevel() + 1)
            local hl = row:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 1)
            hl:SetAlpha(0)
            local boxFrame, tick = CheckBox(row)
            boxFrame:SetPoint("LEFT", row, "LEFT", 6, 0)
            marks[i] = tick
            local caption = CludesUI.MakeFont(row, 12, nil, 1, 1, 1, 0.7)
            caption:SetPoint("LEFT", boxFrame, "RIGHT", 8, 0)
            caption:SetText(CludesUI.L(def.label))
            local live = def.enabled ~= false
            if not live then
                row:SetAlpha(0.35)
            end
            row:SetScript("OnEnter", function()
                if live then
                    hl:SetAlpha(0.05)
                end
                CludesUI.ShowWidgetTooltip(row, CludesUI.L(live and def.tip or def.offTip))
            end)
            row:SetScript("OnLeave", function()
                if live then
                    hl:SetAlpha(0)
                end
                CludesUI.HideWidgetTooltip()
            end)
            if live then
                row:SetScript("OnClick", function()
                    def.set(RefreshAll, dropdownBtn)
                    RefreshAll()
                end)
            end
        end
        -- HookScript: MakeDropdownMenu owns OnShow (scale, outside-click close).
        menu:HookScript("OnShow", RefreshMenu)
        dropdownBtn:SetScript("OnClick", function()
            RefreshSummary()
            if menu:IsShown() then
                menu:Hide()
            else
                RefreshMenu()
                menu:Show()
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
        payload,
        defaultName,
        editModeString,
        editModeLayoutName,
        applyImportedScale
    )
        ClearPage(importPage)

        -- Optional Blizzard Edit Mode layout to apply alongside this import (preset path only; the manual paste path leaves these nil).
        importPage._editModeString = editModeString
        importPage._editModeLayoutName = editModeLayoutName

        local scaleWarnText = BuildScaleWarning(payload, applyImportedScale)
        local includedAddons = {}
        if payload and payload.data and payload.data.addons then
            for folder in pairs(payload.data.addons) do
                includedAddons[folder] = true
            end
        end

        -- Spec->profile assignments in the string gate the "Auto Assign to Specs" toggle (and grow the footer by one stacked row); without
        -- them the footer stays a compact single row.
        local hasSpecAssign = payload
            and payload.data
            and type(payload.data.assignedSpecs) == "table"
            and #payload.data.assignedSpecs > 0

        -- Does the string carry a UI scale? The adopt/keep decision was already made by MaybeConfirmUIScale before this page
        -- (applyImportedScale); this flag only gates the commit marker.
        local hasUIScale = payload and payload.data and type(payload.data.uiScale) == "number"

        local ADDON_DB_MAP_LOCAL = CludesUI.VisibleProfileAddons(CludesUI._ADDON_DB_MAP)
        local PAD = CludesUI.CONTENT_PAD
        local totalW = importPage:GetWidth() - PAD * 2
        -- The optional Auto Assign toggle stacks below the count row.
        local nFooterStack = (hasSpecAssign and 1 or 0)
        local FOOTER_H = 50 + nFooterStack * 24

        local iy = -30

        local BACK_H = SubpageHeader(
            importPage,
            PAD,
            iy,
            CludesUI.Lf("Importing %1$s", (defaultName or CludesUI.L("Profile")))
        )

        iy = iy - BACK_H - 8

        if scaleWarnText then
            local warnFs = CludesUI.MakeFont(importPage, 13, nil, 0.9, 0.2, 0.2, 0.85)
            PP.Point(warnFs, "TOP", importPage, "TOP", 0, iy)
            PP.Point(warnFs, "LEFT", importPage, "LEFT", PAD, 0)
            PP.Point(warnFs, "RIGHT", importPage, "RIGHT", -PAD, 0)
            warnFs:SetText(scaleWarnText)
            warnFs:SetJustifyH("CENTER")
            warnFs:SetWordWrap(true)
            iy = iy - 48
        end

        local editBox
        do
            local INPUT_H = 30
            local INPUT_W = 300
            local nameLabel = CludesUI.MakeFont(importPage, 12, nil, 1, 1, 1, 0.45)
            PP.Point(nameLabel, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
            nameLabel:SetText(CludesUI.L("Profile Name"))
            nameLabel:SetJustifyH("LEFT")

            iy = iy - 22

            local inputFrame = CreateFrame("Frame", nil, importPage)
            PP.Size(inputFrame, INPUT_W, INPUT_H)
            PP.Point(inputFrame, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
            local iBg = inputFrame:CreateTexture(nil, "BACKGROUND")
            iBg:SetAllPoints()
            iBg:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, CludesUI.DD_BG_A)
            local inputBrd = CludesUI.MakeRoundedBorder(inputFrame, 1, 1, 1, CludesUI.DD_BRD_A, iBg)
            importPage._nameFlash = BuildErrorFlash(inputFrame, inputBrd)

            editBox = CreateFrame("EditBox", nil, inputFrame)
            editBox:SetPoint("TOPLEFT", 12, -1)
            editBox:SetPoint("BOTTOMRIGHT", -12, 1)
            editBox:SetFont(FONT, 12, CludesUI.GetFontOutlineFlag())
            editBox:SetTextColor(1, 1, 1, 0.9)
            editBox:SetAutoFocus(false)
            editBox:SetMaxLetters(30)
            if defaultName then
                editBox:SetText(defaultName)
            end

            local placeholder = editBox:CreateFontString(nil, "ARTWORK")
            placeholder:SetFont(FONT, 12, CludesUI.GetFontOutlineFlag())
            placeholder:SetTextColor(1, 1, 1, 0.25)
            placeholder:SetPoint("LEFT", editBox, "LEFT", 0, 0)
            placeholder:SetText(CludesUI.L("Profile name..."))

            editBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then
                    placeholder:Show()
                else
                    placeholder:Hide()
                end
                if importPage._nameError then
                    importPage._nameError:Hide()
                end
            end)
            editBox:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
            end)
            editBox:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
            end)

            iy = iy - INPUT_H - 14
        end

        -- Import Addons section (mirrors per-addon export layout)
        local selectedImports = {}
        local includeLayoutImport = true -- "Include layout" toggle (default on)
        -- "Include Overrides" is all-or-nothing: the exporter's COMPLETE
        -- override system (values + groups + custom unlock modes + BM forks) either replaces yours wholesale or none of it comes. Offered
        -- only when the string carries override data; ON for full strings (or subsets exported with Overrides included), OFF otherwise.
        local stringHasOverrides = false
        do
            local d = payload and payload.data
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
                and (payload.data.overridesIncluded == true or (payload.data.partialImport ~= true and payload.data.overridesExcluded ~= true))
            or false
        -- "Include Window Skins": the exporter's Blizz UI Enhanced account-global bundle (Window Skins + Tooltips, Menus & Popups).
        -- Default OFF and confirmation-gated -- it overwrites the recipient's settings across ALL profiles. Grayed out when string has none.
        local stringHasBlizzSkin = (
            payload
            and payload.data
            and type(payload.data.blizzSkinGlobals) == "table"
        ) or false
        local includeWindowSkinsImport = false
        -- "Global Settings": the exporter's global appearance (fonts, custom colours, dark mode, accent, number format) and UI scale. Presence = deliberate
        -- include; this toggle is the recipient's opt-out. ON when carried, inert when the string has none.
        local stringHasGlobals = false
        do
            local d = payload and payload.data
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
            local folder = entry.folder
            -- Payload keys are CANONICAL (suite folder names); selectedImports is keyed by canon so it matches the payload + the strip loop
            -- in both suite and standalone builds. "loaded"/"desc" stay on the LOCAL folder so only this build's installed module is checkable.
            local canon = entry.canon or folder
            local loaded = CludesUI.IsModuleAddonLoaded(folder)
            local inPayload = includedAddons[canon] or false
            local canImport = loaded and inPayload
            importCanImport[canon] = canImport
            CANON_DISPLAY[canon] = entry.display
            addonItems[#addonItems + 1] = {
                folder = folder,
                canon = canon,
                display = entry.display,
                desc = ADDON_DESCS[folder] or "",
                loaded = loaded,
                inPayload = inPayload,
                canImport = canImport,
                getVal = function()
                    return selectedImports[canon] or false
                end,
                -- Hard-couple: (un)checking a module sets its whole connected component (anchor/size-match links), importable members only.
                setVal = function(value)
                    -- Layout OFF: relationships aren't imported, so skip the hard-couple and let each linked module be picked alone.
                    local members = includeLayoutImport and importComponents and importComponents[canon]
                    if members then
                        for f in pairs(members) do
                            if importCanImport[f] then
                                selectedImports[f] = value or nil
                            end
                        end
                    else
                        selectedImports[canon] = value or nil
                    end
                end,
            }
            if canImport then
                selectedImports[canon] = true
            end
        end

        -- Module connectivity from the payload's layout + meta (both CANONICAL, matching selectedImports' keyspace). Drives the hard-couple
        -- above and the "linked" row affordance. stale={} -- sender already pruned dead edges.
        do
            local ul = payload and payload.data and payload.data.unlockLayout
            local meta = payload and payload.data and payload.data.unlockLayoutMeta
            importComponents = CludesUI.BuildModuleComponents(
                ul,
                CludesUI.BuildImportKeyToFolder(ul, meta and meta.keyToFolder)
            )
        end

        local function RefreshImportCount()
            if not importCountFs then
                return
            end
            local count = 0
            for _ in pairs(selectedImports) do
                count = count + 1
            end
            importCountFs:SetText(CludesUI.Lf("Import will include %1$s of %2$s addons.", count, #addonItems))
        end

        local function RefreshAllImportVisuals()
            for _, fn in ipairs(importVisuals) do
                fn()
            end
            RefreshImportCount()
        end

        iy = ModuleListCard(importPage, PAD, iy, totalW, {
            title = "Import Addons",
            desc = "Choose which addons to import. Any addons not included will use your active profile's settings in the new profile.",
            items = addonItems,
            footerH = FOOTER_H,
            pickable = function(entry)
                return entry.canImport
            end,
            refreshAll = RefreshAllImportVisuals,
            visuals = importVisuals,
            -- Not in the string (red) or not loaded here (dim).
            row = function(entry)
                return {
                    active = entry.canImport,
                    inactiveText = entry.inPayload and CludesUI.L("Not Loaded") or CludesUI.L("Not Included"),
                    inactiveColor = entry.inPayload and { 1, 1, 1, 0.25 } or { 0.9, 0.2, 0.2, 0.7 },
                    linked = function()
                        return includeLayoutImport and importComponents and importComponents[entry.canon],
                            entry.canon,
                            CANON_DISPLAY
                    end,
                    linkedTip = function(list)
                        return CludesUI.Lf(
                            "Linked by Anchor/Width/Height Matching to: %1$s. These import together.",
                            list
                        )
                    end,
                }
            end,
        })

        -- Footer
        iy = iy - 8
        local footerFrame = FooterBar(importPage, PAD, iy, totalW, FOOTER_H)

        importCountFs = CludesUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.40)
        -- With Auto Assign present the footer has two rows, so the count sits on the upper one; otherwise it stays vertically centered.
        if nFooterStack > 0 then
            PP.Point(importCountFs, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, -16)
        else
            PP.Point(importCountFs, "LEFT", footerFrame, "LEFT", SIDE_PAD, 0)
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
            PP.Point(aaBtn, "TOPLEFT", importCountFs, "BOTTOMLEFT", 0, -8)
            local boxFrame, mark = CheckBox(aaBtn)
            boxFrame:SetPoint("LEFT", aaBtn, "LEFT", 0, 0)
            local caption = CludesUI.MakeFont(aaBtn, 12, nil, 1, 1, 1, 0.6)
            caption:SetPoint("LEFT", boxFrame, "RIGHT", 6, 0)
            caption:SetText(CludesUI.L("Auto Assign to Specs"))
            local function vis()
                mark:SetShown(autoAssignImport)
            end
            vis()
            aaBtn:SetScript("OnClick", function()
                autoAssignImport = not autoAssignImport
                vis()
            end)
            aaBtn:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(
                    aaBtn,
                    CludesUI.L(
                        "Assign this profile to the same specializations it was assigned to on export. Off = your current spec assignments stay as they are."
                    )
                )
            end)
            aaBtn:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
        end

        local IMP_BTN_H = 30
        local importBtn, impLbl, impBrd = AccentButton(footerFrame, 180, IMP_BTN_H, "Import Selected Addons")
        PP.Point(importBtn, "RIGHT", footerFrame, "RIGHT", -SIDE_PAD, 0)

        -- Include: the same four extras as the export footer. Those the string
        -- has no data for stay dimmed; Window Skins asks before turning on.
        local rowDefs = {
            {
                label = "Overrides",
                sum = "Overrides",
                enabled = stringHasOverrides,
                offTip = "This profile string does not carry any override data.",
                tip = "Import the sharer's complete override setup: spec and conditional override values, groups, their custom Layout Mode layouts, and Buff Manager overrides. This replaces ALL of your own overrides. Off = keep yours untouched.",
                get = function()
                    return includeOverridesImport
                end,
                set = function()
                    includeOverridesImport = not includeOverridesImport
                end,
            },
            {
                label = "Layout Mode Layout",
                sum = "Layout",
                enabled = true,
                tip = "Import the anchor & size-match relationships from this profile. Off = keep your own layout; only the selected modules' own positions/settings come in.",
                get = function()
                    return includeLayoutImport
                end,
                set = function()
                    includeLayoutImport = not includeLayoutImport
                end,
            },
            {
                label = "Global Settings",
                sum = "Globals",
                enabled = stringHasGlobals,
                offTip = "This profile string does not carry any global settings.",
                tip = "Apply the sharer's fonts, custom colours, dark mode, accent colour and UI scale. Off = keep your own global look and scale; only the selected modules' settings come in.",
                get = function()
                    return includeGlobalsImport
                end,
                set = function()
                    includeGlobalsImport = not includeGlobalsImport
                end,
            },
            {
                label = "Window & Tooltip Skins",
                sum = "Window Skins",
                enabled = stringHasBlizzSkin,
                offTip = "This profile string does not carry any Window & Tooltip Skins settings.",
                tip = "Apply the sharer's Window Skins Window Skins and Tooltips & Menus settings. These are account-wide and will overwrite yours across ALL profiles. Off = keep your own.",
                get = function()
                    return includeWindowSkinsImport
                end,
                set = function(refresh, dropdownBtn)
                    if includeWindowSkinsImport then
                        includeWindowSkinsImport = false
                        return
                    end
                    -- The answer is for this build of the import page: a build
                    -- that dresses the dropdown again before it comes drops it.
                    local ddGen = PoolGen(dropdownBtn)
                    CludesUI:ShowConfirmPopup({
                        title = CludesUI.L("Overwrite Window & Tooltip Settings?"),
                        message = CludesUI.L(
                            "This will replace YOUR Window Skins settings (the Window Skins and Tooltips & Menus tabs) with the sharer's, across ALL of your profiles. Your current settings on those two tabs cannot be recovered afterward."
                        ),
                        confirmText = CludesUI.L("OK"),
                        cancelText = CludesUI.L("Cancel"),
                        onConfirm = function()
                            if not SameDress(dropdownBtn, ddGen) then
                                return
                            end
                            includeWindowSkinsImport = true
                            if refresh then
                                refresh()
                            end
                        end,
                    })
                end,
            },
        }
        IncludeDropdown(footerFrame, importBtn, IMP_BTN_H, rowDefs)

        MakeAccentFade(importBtn, impLbl, impBrd)
        importBtn:SetScript("OnClick", function()
            -- Get profile name from the edit box
            local nameBox = importPage._nameEditBox
            local name = nameBox and strtrim(nameBox:GetText()) or ""
            if name == "" then
                if importPage._nameFlash then
                    importPage._nameFlash()
                end
                if importPage._nameError then
                    importPage._nameError:Show()
                end
                if nameBox then
                    nameBox:SetFocus()
                end
                return
            end

            -- Block duplicate profile names. EXCEPTION: an interactive API import (ImportProfileInteractive) targeting the EXACT name the
            -- calling addon requested overwrites cleanly, like the silent API -- ImportProfile replaces the stored blob wholesale (the old
            -- same-name blob is never read, so nothing mixes) and unselected modules keep current values via merge-base-on-active. A name
            -- the USER edited into a collision keeps the protection below.
            local apiS = CludesUI._apiImportSession
            local apiOverwrite = apiS and apiS.state ~= "done" and apiS.name == name
            local _, existingProfiles = CludesUI.GetProfileList()
            if existingProfiles and existingProfiles[name] and not apiOverwrite then
                CludesUI:ShowConfirmPopup({
                    title = CludesUI.L("Name Taken"),
                    message = CludesUI.Lf(
                        'A profile named "%1$s" already exists. Please choose a different name.',
                        name
                    ),
                    confirmText = CludesUI.L("OK"),
                    hideCancel = true,
                    onConfirm = function() end,
                })
                return
            end

            -- Filter on a private deep copy of the already-decoded payload: the strips below mutate it and the page must stay re-importable
            -- after a failed attempt (re-decoding would re-run the codec).
            local filteredPayload = CludesUI._DeepCopy(payload)
            local isPartialImport = false
            if filteredPayload and filteredPayload.data and filteredPayload.data.addons then
                for folder in pairs(filteredPayload.data.addons) do
                    if not selectedImports[folder] then
                        filteredPayload.data.addons[folder] = nil
                        isPartialImport = true
                    end
                end
            end
            -- CDM spell allocation is top-level (the per-module loop misses it): kept ONLY when the CDM module is selected, and then every
            -- spec in the string imports as-is (no spec picker).
            if filteredPayload and filteredPayload.data then
                if not selectedImports["CludesUICooldownManager"] then
                    filteredPayload.data.cdmSpells = nil
                end
            end
            -- Spec->profile assignments: top-level, applied by ImportProfile when present. Dropped wholesale unless "Auto Assign to Specs"
            -- is on (default off leaves the recipient's assignments alone).
            if filteredPayload and filteredPayload.data and not autoAssignImport then
                filteredPayload.data.assignedSpecs = nil
            end
            -- UI scale (account-wide): applied by ImportProfile ONLY on the opt-in from MaybeConfirmUIScale. PRESENCE IS CONSENT at
            -- ImportProfile -- accepted keeps the payload's uiScale; declined or matching scales STRIP it so the user's own scale stands.
            if filteredPayload and filteredPayload.data and hasUIScale and not applyImportedScale then
                filteredPayload.data.uiScale = nil
                filteredPayload.data.applyUIScale = nil
            end
            -- Layout relationships: keep only anchor/size-match edges with BOTH endpoints in the selected modules (per-element graph filter)
            -- via the payload's keyToFolder meta. selectedImports and the meta values are both CANONICAL, so they compare directly.
            -- stale={}: the sender pruned dead edges at export and the recipient's registry is irrelevant here; the "Include layout" toggle drops the whole thing separately.
            if filteredPayload and filteredPayload.data then
                local ul = filteredPayload.data.unlockLayout
                if ul and includeLayoutImport then
                    local meta = filteredPayload.data.unlockLayoutMeta
                    -- payload meta wins; the static resolver fills gaps (and ALL keys for a meta-less string) so we never drop the layout.
                    local k2f = CludesUI.BuildImportKeyToFolder(ul, meta and meta.keyToFolder)
                    filteredPayload.data.unlockLayout =
                        CludesUI.FilterLayoutToFolders(ul, selectedImports, k2f)
                else
                    filteredPayload.data.unlockLayout = nil
                end
                -- Meta is transient -- never overlay/persist it into the profile.
                filteredPayload.data.unlockLayoutMeta = nil
            end
            -- Global appearance (fonts, customColors, darkMode, cuiAccent, numberFormat) and scale ride the Include dropdown's "Global Settings" row (on
            -- by default when carried): unchecked strips them all so the merge keeps the recipient's look. Module deselection alone never
            -- strips them -- the store merge takes each key only when present.
            if filteredPayload and filteredPayload.data and not includeGlobalsImport then
                filteredPayload.data.fonts = nil
                filteredPayload.data.customColors = nil
                filteredPayload.data.darkMode = nil
                filteredPayload.data.numberFormat = nil
                filteredPayload.data.cuiAccent = nil
                filteredPayload.data.uiScale = nil
                filteredPayload.data.applyUIScale = nil
            end
            if isPartialImport and filteredPayload and filteredPayload.data then
                -- Overrides (values AND forks) are governed solely by the Include Overrides checkbox; module deselection never strips them
                -- here. partialImport gates the override legacy keep-mine default at the store merge.
                filteredPayload.data.partialImport = true
            end
            -- Unlock-layer FORKS are whole cross-module position layers, so "Include layout" must gate them exactly like unlockLayout above
            -- or the exporter's forks replace the recipient's group layouts (ApplyLayer rewrites live anchors and CDM/AB bar positions from
            -- them on the next apply). layoutExcluded tells the store merge to KEEP the recipient's forks (nil incoming must not read as wipe).
            if filteredPayload and filteredPayload.data and not includeLayoutImport then
                -- Baseline layout excluded; fork stores belong to the Include Overrides decision below, so they are not stripped here.
                filteredPayload.data.layoutExcluded = true
            end
            -- Include Overrides (all-or-nothing): checked -> stamp the marker so ImportProfile takes the exporter's whole override system
            -- even on subset strings; unchecked -> strip every override store and stamp the exclusion so nils read as "keep mine", not "wipe".
            if filteredPayload and filteredPayload.data then
                if includeOverridesImport then
                    filteredPayload.data.overridesIncluded = true
                    filteredPayload.data.overridesExcluded = nil
                else
                    filteredPayload.data.specOverrides = nil
                    filteredPayload.data.specOverrideGroups = nil
                    filteredPayload.data.specOverrideNextId = nil
                    filteredPayload.data.condOverrides = nil
                    filteredPayload.data.condOverrideGroups = nil
                    filteredPayload.data.condOverrideNextId = nil
                    filteredPayload.data.specUnlockOverrides = nil
                    filteredPayload.data.condUnlockOverrides = nil
                    filteredPayload.data.specBmOverrides = nil
                    filteredPayload.data.condBmOverrides = nil
                    filteredPayload.data.specDmOverrides = nil
                    filteredPayload.data.condDmOverrides = nil
                    filteredPayload.data.unlockOverrideAnchors = nil
                    filteredPayload.data.overridesExcluded = true
                    filteredPayload.data.overridesIncluded = nil
                end
            end
            -- Include Window Skins: checked -> stamp the opt-in so ImportProfile applies the Blizz UI Enhanced account-global bundle before
            -- the reload; unchecked -> strip the bundle so nothing can apply and the recipient keeps their settings.
            if filteredPayload and filteredPayload.data then
                if includeWindowSkinsImport and stringHasBlizzSkin then
                    filteredPayload.data.applyBlizzSkinGlobals = true
                else
                    filteredPayload.data.blizzSkinGlobals = nil
                    filteredPayload.data.applyBlizzSkinGlobals = nil
                end
            end

            local function commit()
                -- The payload table goes to ImportProfile directly (no encode-to-string round trip on already-decoded data). An
                -- interactive-API session marks itself as committing so ImportProfile's stale-session cancellation (which guards
                -- CONCURRENT silent imports) never cancels the committing one.
                local apiSession = CludesUI._apiImportSession
                if apiSession and apiSession.state == "done" then
                    apiSession = nil
                end
                -- The import reloads the UI as it lands (an interactive-API session hands that to its caller), and only a
                -- profile payload imports (ImportProfile refuses every other type), so the outcome is known now: the reload
                -- is asked for first in the click (RequestReload; WoW Forever refused it after the import's own work) and the
                -- import below runs before the client reloads.
                if not apiSession and filteredPayload and filteredPayload.type == "full" then
                    CludesUI.RequestReload(
                        CludesUI.L("Profile Imported"),
                        CludesUI.ImportReloadMessage(filteredPayload)
                    )
                end
                if apiSession then
                    apiSession.committing = true
                end
                local ok, err, status = CludesUI.ImportProfile(filteredPayload, name)
                if apiSession then
                    apiSession.committing = nil
                end
                -- Apply the preset's Blizzard Edit Mode layout (if supplied) right before the reload so profile + layout land together.
                -- pcall-guarded so a Blizzard Edit Mode error cannot block the reload. No-op on the manual paste path (no stored string).
                if ok and importPage._editModeString then
                    pcall(
                        CludesUI.ApplyPresetEditMode,
                        importPage._editModeString,
                        importPage._editModeLayoutName
                    )
                end
                if ok and apiSession then
                    -- Interactive-API import: hand control back to the caller instead of reloading (the caller owns ReloadUI()). Finish
                    -- BEFORE hiding so the panel's OnHide decline hook sees a completed session and stays silent.
                    if status == "spec_locked" then
                        CludesUI.Print(
                            CludesUI.Lf(
                                '"%1$s" was saved but cannot be loaded because this spec has an assigned profile.',
                                name
                            )
                        )
                    end
                    CludesUI._FinishApiImportSession(true)
                    if CludesUI._ProfilesResetToMain then
                        pcall(CludesUI._ProfilesResetToMain)
                    end
                    CludesUI:Hide()
                elseif ok and status == "spec_locked" then
                    CludesUI:ShowInfoPopup({
                        title = CludesUI.L("Profile Imported"),
                        content = CludesUI.Lf(
                            '"%1$s" was saved but cannot be loaded because this spec has an assigned profile. Switch specs or remove the spec assignment to use it.',
                            name
                        ),
                    })
                elseif not ok then
                    CludesUI:ShowInfoPopup({
                        title = CludesUI.L("Import Failed"),
                        content = err or CludesUI.L("Unknown error"),
                    })
                end
            end

            -- CDM spell layouts (gated above) import as-is, no spec picker: they are per-profile (spellAssignments.profiles[profileName]),
            -- so only the NEW profile's store is populated (others untouched) and any spec not in the string falls back to default bars.
            commit()
        end)
        importBtn._flashError = BuildErrorFlash(importBtn, impBrd)

        -- Red error message shown directly below the button when no name is entered
        local nameErrorFs = CludesUI.MakeFont(footerFrame, 11, nil, 0.9, 0.2, 0.2)
        nameErrorFs:SetJustifyH("RIGHT")
        PP.Point(nameErrorFs, "TOPRIGHT", importBtn, "BOTTOMRIGHT", 0, -14)
        nameErrorFs:SetText(CludesUI.L("*Please enter a profile name"))
        nameErrorFs:Hide()
        importPage._nameError = nameErrorFs

        -- Store edit box reference for the import button callback
        importPage._nameEditBox = editBox

        -- Hide every other page so the import page never overlaps the one it was opened from (the main paste flow).
        mainPage:Hide()
        pastePage:Hide()
        importPage:Show()
    end

    -------------------------------------------------------------------
    --  PASTE PAGE (Import Profile step 1: paste string)
    -------------------------------------------------------------------
    local function ShowPastePage()
        ClearPage(pastePage)

        local PAD = CludesUI.CONTENT_PAD
        local totalW = pastePage:GetWidth() - PAD * 2
        local py = -30

        local BACK_H = SubpageHeader(pastePage, PAD, py, CludesUI.L("Import Profile"))

        py = py - BACK_H - 20

        -- Big paste panel
        local PANEL_H = 200
        local panelFrame = CreateFrame("Frame", nil, pastePage)
        PP.Size(panelFrame, totalW, PANEL_H)
        PP.Point(panelFrame, "TOPLEFT", pastePage, "TOPLEFT", PAD, py)
        local panelBg = panelFrame:CreateTexture(nil, "BACKGROUND")
        panelBg:SetAllPoints()
        panelBg:SetColorTexture(0.062, 0.070, 0.082, 0.50)
        CludesUI.MakeRoundedBorder(panelFrame, 1, 1, 1, 0.10, panelBg)

        local pasteSF = CreateFrame("ScrollFrame", nil, panelFrame)
        pasteSF:SetPoint("TOPLEFT", 16, -12)
        pasteSF:SetPoint("BOTTOMRIGHT", -16, 12)

        local pasteBox = CreateFrame("EditBox", nil, pasteSF)
        pasteBox:SetWidth(totalW - 32)
        pasteBox:SetFont(FONT, 11, CludesUI.GetFontOutlineFlag())
        pasteBox:SetTextColor(1, 1, 1, 0.8)
        pasteBox:SetAutoFocus(false)
        pasteBox:SetMultiLine(true)
        pasteSF:SetScrollChild(pasteBox)

        -- Click anywhere on the panel to refocus the edit box
        panelFrame:EnableMouse(true)
        panelFrame:SetScript("OnMouseDown", function()
            pasteBox:SetFocus()
        end)

        local pastePlaceholder = pasteSF:CreateFontString(nil, "ARTWORK")
        pastePlaceholder:SetFont(FONT, 12, CludesUI.GetFontOutlineFlag())
        pastePlaceholder:SetTextColor(1, 1, 1, 0.20)
        pastePlaceholder:SetPoint("TOPLEFT", pasteSF, "TOPLEFT", 0, 0)
        pastePlaceholder:SetText(CludesUI.L("Paste your profile string here..."))

        pasteBox:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" then
                pastePlaceholder:Show()
            else
                pastePlaceholder:Hide()
            end
        end)
        pasteBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        pasteBox:SetScript("OnCursorChanged", function(self, _, cursorY, _, cursorH)
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
        local pasteAbsorber = CludesUI.AttachImportPasteAbsorber(pasteBox, function()
            CludesUI:ShowInfoPopup({
                title = CludesUI.L("Paste Interrupted"),
                content = CludesUI.L(
                    "The pasted string could not be read completely. Please paste it again."
                ),
            })
        end)

        py = py - PANEL_H - 16

        -- Continue button (Done-style)
        local contBtn, contLbl, contBrd = AccentButton(pastePage, 160, 34, "Continue", 13)
        PP.Point(contBtn, "TOPRIGHT", pastePage, "TOPRIGHT", -PAD, py)

        local contReset = MakeAccentFade(contBtn, contLbl, contBrd)
        local decodeRun
        contBtn:SetScript("OnClick", function()
            if decodeRun then
                return
            end
            local importStr = pasteAbsorber.GetText()
            if importStr == "" then
                return
            end
            -- Decode across frames: lock the button and show progress so the client stays responsive on very large strings.
            contBtn:Disable()
            contBtn:SetScript("OnUpdate", nil)
            contReset()
            contLbl:SetText(CludesUI.L("Processing") .. "...")
            local function Restore()
                decodeRun = nil
                contBtn:Enable()
                contLbl:SetText(CludesUI.L("Continue"))
                contReset()
            end
            -- The paste page this decode belongs to: once it is dressed again
            -- (reopened, or the page rebuilt), the result is dropped.
            local btnGen = PoolGen(contBtn)
            decodeRun = CludesUI.DecodeImportStringAsync(importStr, function(payload, err)
                if not SameDress(contBtn, btnGen) then
                    return
                end
                Restore()
                -- The user may have navigated away mid-decode; a stale run's result is simply dropped.
                if not pastePage:IsVisible() then
                    return
                end
                if not payload then
                    CludesUI:ShowInfoPopup({
                        title = CludesUI.L("Import Failed"),
                        content = err or CludesUI.L("Invalid import string."),
                    })
                    return
                end
                -- FULL ACCOUNT string: its own flow, routed BEFORE the normal import machinery sees the payload (no module selection,
                -- include toggles, or store merging). Typed confirmation: it overwrites account-wide settings.
                if CludesUI.IsFullAccountPayload(payload) then
                    pastePage:Hide()
                    local message = CludesUI.L(
                        "This string is a FULL ACCOUNT export. It replaces your account-wide settings with the sender's, including Utilities, Frame Bindings, Cooldown Manager spell setups, unlock anchors, UI scale, and spec assignments -- not just a profile. Your other profiles keep their own settings, but a profile with the same name is replaced."
                    )
                    -- Spell setups from the other client are skipped on import: say so.
                    local data = payload.data
                    if
                        CludesUI.PayloadFromOtherClient(payload)
                        and type(data) == "table"
                        and data.spellAssignments ~= nil
                    then
                        message = message
                            .. "\n\n"
                            .. CludesUI.L(
                                "Its Cooldown Manager spells come from the other game client and will not be imported."
                            )
                    end
                    CludesUI:ShowConfirmPopup({
                        title = CludesUI.L("Import Full Account Data"),
                        message = message,
                        disclaimer = CludesUI.L(
                            "This cannot be undone. Export your own profile as a backup first."
                        ),
                        typeToConfirm = "Confirm",
                        confirmText = CludesUI.L("Import & Reload"),
                        cancelText = CludesUI.L("Cancel"),
                        onConfirm = function()
                            CludesUI.ImportFullAccountData(payload)
                        end,
                    })
                    return
                end
                pastePage:Hide()
                local pageGen = PoolGen(pastePage)
                MaybeConfirmUIScale(payload, function(applyScale)
                    -- Not after a rebuild of the profiles page meanwhile.
                    if not SameDress(pastePage, pageGen) then
                        return
                    end
                    ShowImportPage(importStr, payload, nil, nil, nil, applyScale)
                end)
            end, function(frac)
                if not SameDress(contBtn, btnGen) then
                    return
                end
                contLbl:SetFormattedText("%s %d%%", CludesUI.L("Processing"), frac * 100)
            end)
        end)

        mainPage:Hide()
        pastePage:Show()
        pasteBox:SetFocus()
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
    y = CludesUI.BuildActionCardRow(parent, y, {
        {
            icon = MEDIA .. "icons\\import.png",
            title = CludesUI.L("Import Profile"),
            desc = CludesUI.L("Import a profile from string."),
            onClick = function()
                ShowPastePage()
            end,
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

        local totalW = parent:GetWidth() - CludesUI.CONTENT_PAD * 2
        local innerW = totalW - PAD_X * 2
        local DD_W = math.floor(innerW * 0.38)
        local BTN_W = math.floor((innerW - DD_W - GAP * 2) / 2)

        local rowFrame = CreateFrame("Frame", nil, parent)
        PP.Size(rowFrame, totalW, ROW_H)
        PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", CludesUI.CONTENT_PAD, y)

        -- Background panel
        local rowBrd = CludesUI.MakeRoundedCard(rowFrame, 0.10, 0.50)
        local rowBg = rowBrd.bg

        -- "Active Profile" label
        local profLabel = CludesUI.MakeFont(rowFrame, 12, nil, EG.r, EG.g, EG.b, 0.7)
        PP.Point(profLabel, "TOPLEFT", rowFrame, "TOPLEFT", PAD_X, -PAD_Y)
        profLabel:SetText(CludesUI.L("Active Profile"))
        profLabel:SetJustifyH("LEFT")

        -- Active Profile dropdown
        local dropdownBtn, ddLabelFS, _, _, ddPaint = MakeDropdown(rowFrame, DD_W, CTRL_H, function()
            return CludesUI.GetActiveProfileName()
        end)
        CludesUI._profileDDBtn = dropdownBtn
        ddLabel = ddLabelFS
        PP.Point(dropdownBtn, "TOPLEFT", profLabel, "BOTTOMLEFT", 0, -6)

        -- Profile dropdown menu with inline rename/delete/keybind
        local menu = MakeDropdownMenu(dropdownBtn, DD_W)
        local X_SZ = 14
        local menuItems = {}

        local function RebuildProfileMenu()
            for _, itm in ipairs(menuItems) do
                itm:Hide()
            end
            local order, profiles = CludesUI.GetProfileList()
            local menuH = 4
            local idx = 0
            local activeName = CludesUI.GetActiveProfileName()
            local sid = CurrentSpecID()
            local specAssigned = sid and CludesUI.GetSpecProfile(sid) or nil
            for _, name in ipairs(order) do
                if profiles[name] then
                    idx = idx + 1
                    local itm = menuItems[idx]
                    if not itm then
                        itm = CreateFrame("Button", nil, menu)
                        itm:SetHeight(26)
                        itm:SetFrameLevel(menu:GetFrameLevel() + 1)
                        local caption = itm:CreateFontString(nil, "OVERLAY")
                        caption:SetFont(FONT, 13, CludesUI.GetFontOutlineFlag())
                        caption:SetPoint("LEFT", itm, "LEFT", 10, 0)
                        caption:SetPoint("RIGHT", itm, "RIGHT", -(X_SZ * 3 + 30), 0)
                        caption:SetJustifyH("LEFT")
                        caption:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
                        itm._lbl = caption
                        local hl = itm:CreateTexture(nil, "ARTWORK")
                        hl:SetAllPoints()
                        hl:SetColorTexture(1, 1, 1, 1)
                        hl:SetAlpha(0)
                        itm._hl = hl

                        -- Delete, Rename and Keybind icons at the right edge.
                        local icons = {}
                        local function Icon(file, anchor, rel, x)
                            local b = CreateFrame("Button", nil, itm)
                            b:SetSize(X_SZ, X_SZ)
                            b:SetPoint("RIGHT", anchor, rel, x, 0)
                            b:SetFrameLevel(itm:GetFrameLevel() + 2)
                            local texture = b:CreateTexture(nil, "OVERLAY")
                            texture:SetAllPoints()
                            Unsnapped(texture)
                            texture:SetTexture(MEDIA .. "icons\\" .. file)
                            b:SetAlpha(0.4)
                            icons[#icons + 1] = b
                            return b
                        end
                        local xBtn = Icon("cui-close.png", itm, "RIGHT", -8)
                        local editBtn = Icon("cui-edit.png", xBtn, "LEFT", -4)
                        local kbBtnI = Icon("cui-keybind-2.png", editBtn, "LEFT", -4)
                        itm._xBtn, itm._editBtn, itm._kbBtn = xBtn, editBtn, kbBtnI

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
                        itm._light = function()
                            caption:SetTextColor(1, 1, 1, 1)
                            hl:SetAlpha(CludesUI.DD_ITEM_HL_A)
                            IconAlpha(0.8)
                        end
                        itm._dim = function()
                            caption:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
                            hl:SetAlpha(itm._isSel and CludesUI.DD_ITEM_SEL_A or 0)
                            IconAlpha(0.4)
                        end
                        itm._overIcon = OverIcon
                        for b, tip in pairs({ [xBtn] = "Delete", [editBtn] = "Rename", [kbBtnI] = "Keybind" }) do
                            b:SetScript("OnEnter", function(self)
                                itm._light()
                                self:SetAlpha(1)
                                CludesUI.ShowWidgetTooltip(self, CludesUI.L(tip))
                            end)
                            b:SetScript("OnLeave", function(self)
                                if itm:IsMouseOver() or OverIcon() then
                                    self:SetAlpha(0.8)
                                else
                                    itm._dim()
                                end
                                CludesUI.HideWidgetTooltip()
                            end)
                        end
                        menuItems[idx] = itm
                    end

                    itm:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -menuH)
                    itm:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -menuH)
                    itm._lbl:SetText(name)
                    itm._isSel = (name == activeName)
                    itm._hl:SetAlpha(itm._isSel and 0.04 or 0)

                    local capName = name
                    local specLocked = specAssigned and specAssigned ~= capName

                    if specLocked then
                        itm._lbl:SetTextColor(1, 1, 1, 0.25)
                        itm._xBtn:Hide()
                        itm._editBtn:Hide()
                        itm._kbBtn:Hide()
                        itm:SetScript("OnClick", nil)
                        itm:SetScript("OnEnter", function()
                            CludesUI.ShowWidgetTooltip(
                                itm,
                                CludesUI.L(
                                    "Your current spec has an assigned profile so you cannot switch to another. Please unassign to switch."
                                )
                            )
                        end)
                        itm:SetScript("OnLeave", function()
                            CludesUI.HideWidgetTooltip()
                        end)
                    else
                        local iLbl, iXBtn, iEditBtn, iKbBtnL = itm._lbl, itm._xBtn, itm._editBtn, itm._kbBtn
                        iLbl:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
                        iEditBtn:Show()
                        iKbBtnL:Show()
                        if capName == activeName then
                            iXBtn:Hide()
                            iEditBtn:ClearAllPoints()
                            iEditBtn:SetPoint("RIGHT", itm, "RIGHT", -8, 0)
                        else
                            iXBtn:Show()
                            iEditBtn:ClearAllPoints()
                            iEditBtn:SetPoint("RIGHT", iXBtn, "LEFT", -4, 0)
                        end
                        itm:SetScript("OnEnter", itm._light)
                        itm:SetScript("OnLeave", function()
                            if not itm._overIcon() then
                                itm._dim()
                            end
                        end)
                        itm:SetScript("OnClick", function()
                            if capName == activeName then
                                return
                            end
                            menu:Hide()
                            local _, profs = CludesUI.GetProfileList()
                            local asked = SwitchProfileAndAsk(capName, profs and profs[capName], function()
                                ddLabel:SetText(CludesUI.GetActiveProfileName())
                            end)
                            -- A live switch only re-points db.profile: cached pages
                            -- (per-profile lists such as the CDM bar dropdown) rebuild.
                            if not asked then
                                CludesUI:InvalidatePageCache()
                                CludesUI:RefreshPage(true)
                            end
                        end)
                        iXBtn:SetScript("OnClick", function()
                            if capName == activeName then
                                return
                            end
                            menu:Hide()
                            CludesUI:ShowConfirmPopup({
                                title = CludesUI.L("Delete Profile"),
                                message = CludesUI.Lf('Delete "%1$s"?', capName),
                                confirmText = CludesUI.L("Delete"),
                                cancelText = CludesUI.L("Cancel"),
                                onConfirm = function()
                                    CludesUI.DeleteProfile(capName)
                                    ShowProfileChange()
                                end,
                            })
                        end)
                        iEditBtn:SetScript("OnClick", function()
                            menu:Hide()
                            CludesUI:ShowInputPopup({
                                title = CludesUI.L("Rename Profile"),
                                message = CludesUI.Lf('Enter a new name for "%1$s":', capName),
                                placeholder = capName,
                                confirmText = CludesUI.L("Rename"),
                                cancelText = CludesUI.L("Cancel"),
                                onConfirm = function(newName)
                                    newName = newName and strtrim(newName) or ""
                                    if newName == "" or newName == capName then
                                        return
                                    end
                                    if newName == "Default" then
                                        print(
                                            CludesUI.L('|cffff6060[CludesUI]|r Cannot rename to "Default".')
                                        )
                                        return
                                    end
                                    local _, profs = CludesUI.GetProfileList()
                                    if profs and profs[newName] then
                                        print(
                                            CludesUI.Lf(
                                                '|cffff6060[CludesUI]|r A profile named "%1$s" already exists.',
                                                newName
                                            )
                                        )
                                        return
                                    end
                                    CludesUI.RenameProfile(capName, newName)
                                    ShowProfileChange()
                                end,
                            })
                        end)
                        iKbBtnL:SetScript("OnClick", function()
                            menu:Hide()
                            ShowProfileKeybindPopup(capName)
                        end)
                    end

                    itm:Show()
                    menuH = menuH + 26
                end
            end
            menu:SetHeight(menuH + 4)
        end

        -- The dropdown stays lit while its menu is open.
        local function ActiveApplyNormal()
            ddPaint(false)
        end
        local function ActiveApplyHover()
            ddPaint(true)
        end

        dropdownBtn:SetScript("OnClick", function()
            if menu:IsShown() then
                menu:Hide()
            else
                RebuildProfileMenu()
                menu:Show()
            end
        end)
        dropdownBtn:SetScript("OnEnter", function()
            ActiveApplyHover()
        end)
        dropdownBtn:SetScript("OnLeave", function()
            if not menu:IsShown() then
                ActiveApplyNormal()
            end
        end)
        dropdownBtn:HookScript("OnHide", function()
            menu:Hide()
        end)
        menu:HookScript("OnShow", function()
            ActiveApplyHover()
        end)
        menu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            if dropdownBtn:IsMouseOver() then
                ActiveApplyHover()
            else
                ActiveApplyNormal()
            end
        end)

        -- The other two columns: a caption, then a plain button under it.
        local function Caption(text, anchor, x)
            local fs = CludesUI.MakeFont(rowFrame, 12, nil, 1, 1, 1, 0.45)
            PP.Point(fs, "LEFT", anchor, "LEFT", x, 0)
            fs:SetText(text)
            fs:SetJustifyH("LEFT")
            return fs
        end
        local function ColumnButton(caption, text, onClick)
            local button = CreateFrame("Button", nil, rowFrame)
            PP.Size(button, BTN_W, CTRL_H)
            PP.Point(button, "TOPLEFT", caption, "BOTTOMLEFT", 0, -6)
            button:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            CludesUI.MakeStyledButton(button, text, 11, PROF_BTN_COLOURS, onClick)
            return button
        end

        -- Assign to Spec (Assign to Class on WoW Forever, which has no specs:
        -- the popup lists one row per class there). The popup edits each
        -- profile's set of specs; the account keeps spec -> profile.
        local function OpenSpecAssign()
            local db = CludesUIDB or {}
            db.specProfiles = db.specProfiles or {}
            local order, profiles = CludesUI.GetProfileList()
            local specsOf = {}
            for _, name in ipairs(order) do
                specsOf[name] = {}
            end
            for specID, name in pairs(db.specProfiles) do
                if specsOf[name] then
                    specsOf[name][specID] = true
                end
            end
            local tempDB = { _profileSpecs = specsOf }
            CludesUI:ShowSpecAssignPopup({
                db = tempDB,
                dbKey = "_profileSpecs",
                presetKey = CludesUI.GetActiveProfileName(),
                allPresetKeys = function()
                    local list = {}
                    for _, name in ipairs(order) do
                        if profiles[name] then
                            list[#list + 1] = { key = name, name = name }
                        end
                    end
                    return list
                end,
                onDone = function()
                    db.specProfiles = {}
                    for name, specSet in pairs(tempDB._profileSpecs) do
                        for specID in pairs(specSet) do
                            db.specProfiles[specID] = name
                        end
                    end
                    CludesUI:RefreshPage()
                end,
            })
        end
        local forever = CludesUI.IS_FOREVER
        local specLabel = Caption(
            forever and CludesUI.L("Assign to Class") or CludesUI.L("Assign to Spec"),
            profLabel,
            DD_W + GAP
        )
        ColumnButton(specLabel, forever and "Assign to Class" or "Assign to Spec", OpenSpecAssign)

        -- New Profile: a copy of the current one under a new name, then a
        -- reload that switches to it (the copy is the reload's pre-work).
        local function CopyProfile(name)
            name = name and strtrim(name) or ""
            if name == "" then
                return
            end
            local _, profiles = CludesUI.GetProfileList()
            if profiles and profiles[name] then
                CludesUI:ShowConfirmPopup({
                    title = CludesUI.L("Name Taken"),
                    message = CludesUI.Lf(
                        'A profile named "%1$s" already exists. Please choose a different name.',
                        name
                    ),
                    confirmText = CludesUI.L("OK"),
                    hideCancel = true,
                    onConfirm = function() end,
                })
                return
            end
            CludesUI.RequestReload(
                CludesUI.L("Copy Profile"),
                CludesUI.L("Reload to finish switching to the new profile."),
                function()
                    CludesUI.SaveCurrentAsProfile(name)
                end
            )
        end
        local newLabel = Caption(CludesUI.L("New Profile"), specLabel, BTN_W + GAP)
        ColumnButton(newLabel, "Create New (Copy)", function()
            CludesUI:ShowInputPopup({
                title = CludesUI.L("Copy Profile"),
                message = CludesUI.L("Enter a name for the new profile:"),
                placeholder = CludesUI.L("My Profile"),
                confirmText = CludesUI.L("Save"),
                cancelText = CludesUI.L("Cancel"),
                onConfirm = CopyProfile,
            })
        end)

        y = y - ROW_H
    end

    -------------------------------------------------------------------
    --  PER-ADDON EXPORT
    -------------------------------------------------------------------
    _, h = W:Spacer(parent, y, 18)
    y = y - h

    do
        local ADDON_DB_MAP_LOCAL = CludesUI.VisibleProfileAddons(CludesUI._ADDON_DB_MAP)
        local PAD = CludesUI.CONTENT_PAD
        local totalW = parent:GetWidth() - PAD * 2
        -- Single footer row: count + "Include layout" + "Include Global Settings" side by side, Export button on the right.
        local FOOTER_H = 50

        -- Build addon item list
        local selectedAddons = {}
        local includeLayoutExport = true -- "Unlock Mode Layout" include (default on)
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
        local exportComponents = CludesUI.BuildModuleComponents({
            anchors = CludesUIDB and CludesUIDB.unlockAnchors,
            widthMatch = CludesUIDB and CludesUIDB.unlockWidthMatch,
            heightMatch = CludesUIDB and CludesUIDB.unlockHeightMatch,
        })
        local FOLDER_DISPLAY = {}
        for _, e in ipairs(ADDON_DB_MAP_LOCAL) do
            FOLDER_DISPLAY[e.folder] = e.display
        end

        for _, entry in ipairs(ADDON_DB_MAP_LOCAL) do
            local loaded = CludesUI.IsModuleAddonLoaded(entry.folder)
            local folder = entry.folder
            addonItems[#addonItems + 1] = {
                folder = folder,
                display = entry.display,
                desc = ADDON_DESCS[folder] or "",
                loaded = loaded,
                getVal = function()
                    return selectedAddons[folder] or false
                end,
                -- Hard-couple: (un)checking a module sets its whole connected component, gated to loaded (exportable) members.
                setVal = function(value)
                    -- Layout OFF: relationships aren't exported, so skip the hard-couple and let each linked module be picked alone.
                    local members = includeLayoutExport and exportComponents and exportComponents[folder]
                    if members then
                        for f in pairs(members) do
                            if CludesUI.IsModuleAddonLoaded(f) then
                                selectedAddons[f] = value or nil
                            end
                        end
                    else
                        selectedAddons[folder] = value or nil
                    end
                end,
            }
            if loaded then
                selectedAddons[folder] = true
            end
        end

        local function RefreshFooterCount()
            if not footerCountFs then
                return
            end
            local count = 0
            for _ in pairs(selectedAddons) do
                count = count + 1
            end
            footerCountFs:SetText(CludesUI.Lf("Export will include %1$s of %2$s addons.", count, #addonItems))
        end

        local function RefreshAllAddonVisuals()
            for _, fn in ipairs(addonVisuals) do
                fn()
            end
            RefreshFooterCount()
        end

        y = ModuleListCard(parent, PAD, y, totalW, {
            title = "Export Profile",
            desc = "Choose which addons to include in your exported profile. Check everything for a full profile export.",
            items = addonItems,
            footerH = FOOTER_H,
            pickable = function(entry)
                return entry.loaded
            end,
            refreshAll = RefreshAllAddonVisuals,
            visuals = addonVisuals,
            row = function(entry)
                return {
                    active = entry.loaded,
                    inactiveText = CludesUI.L("Not Loaded"),
                    inactiveColor = { 1, 1, 1, 0.25 },
                    linked = function()
                        return includeLayoutExport and exportComponents and exportComponents[entry.folder],
                            entry.folder,
                            FOLDER_DISPLAY
                    end,
                    linkedTip = function(list)
                        return CludesUI.Lf(
                            "Linked by Anchor/Width/Height Matching to: %1$s. These export together.",
                            list
                        )
                    end,
                    blockedTip = CludesUI.L("Addon not loaded"),
                }
            end,
        })

        -- Footer (inside the background panel)
        y = y - 8

        local footerFrame = FooterBar(parent, PAD, y, totalW, FOOTER_H)

        footerCountFs = CludesUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.40)
        -- Selection count, top-left of the footer. The Include dropdown and Export Profile button sit right-aligned on the same row.
        PP.Point(footerCountFs, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, -16)
        footerCountFs:SetJustifyH("LEFT")
        RefreshFooterCount()

        local EXPORT_BTN_H = 30
        local exportSelBtn, eaLbl, eaBrd = AccentButton(footerFrame, 180, EXPORT_BTN_H, "Export Profile")
        PP.Point(exportSelBtn, "RIGHT", footerFrame, "RIGHT", -SIDE_PAD, 0)

        -- Include: Overrides is AUTO until toggled (on while every loaded module
        -- is checked, off for a subset), so the menu and summary recompute it
        -- on every open and hover.
        local function AllLoadedSelected()
            for _, entry in ipairs(addonItems) do
                if entry.loaded and not selectedAddons[entry.folder] then
                    return false
                end
            end
            return true
        end
        EffectiveIncludeOverrides = function()
            if includeOverridesExport ~= nil then
                return includeOverridesExport
            end
            return AllLoadedSelected()
        end

        local rowDefs = {
            {
                label = "Overrides",
                sum = "Overrides",
                tip = "Include your complete override setup: spec and conditional override values, groups, their custom Layout Mode layouts, and Buff Manager overrides. On import this replaces the recipient's overrides entirely.",
                get = function()
                    return EffectiveIncludeOverrides()
                end,
                set = function()
                    includeOverridesExport = not EffectiveIncludeOverrides()
                end,
            },
            {
                label = "Layout Mode Layout",
                sum = "Layout",
                tip = "Include the anchor & size-match relationships between modules. Off = export each module's own positions only, with no cross-module tying.",
                get = function()
                    return includeLayoutExport
                end,
                set = function()
                    includeLayoutExport = not includeLayoutExport
                end,
            },
            {
                label = "Global Settings",
                sum = "Globals",
                tip = "Include fonts, custom colours, dark mode, accent colour and UI scale with this export. Off = only the selected modules' own settings export, keeping the recipient's global look.",
                get = function()
                    return includeGlobalsExport
                end,
                set = function()
                    includeGlobalsExport = not includeGlobalsExport
                end,
            },
        }
        -- Window & Tooltip Skins only while that module is loaded (its bundle needs it).
        if CludesUI.IsModuleAddonLoaded("CludesUIBlizzardSkin") then
            rowDefs[#rowDefs + 1] = {
                label = "Window & Tooltip Skins",
                sum = "Window Skins",
                tip = "Include your Window Skins settings from the Window Skins and Tooltips & Menus tabs. These are account-wide: if the importer opts in, they overwrite that player's settings across ALL of their profiles.",
                get = function()
                    return includeWindowSkinsExport
                end,
                set = function()
                    includeWindowSkinsExport = not includeWindowSkinsExport
                end,
            }
        end
        local dropdownBtn, refreshSummary = IncludeDropdown(footerFrame, exportSelBtn, EXPORT_BTN_H, rowDefs)
        -- Keep the AUTO summary honest after module toggles.
        dropdownBtn:HookScript("OnEnter", refreshSummary)

        MakeAccentFade(exportSelBtn, eaLbl, eaBrd)
        exportSelBtn:SetScript("OnClick", function()
            local folders = {}
            local hasAny = false
            for folder in pairs(selectedAddons) do
                folders[folder] = true
                hasAny = true
            end
            if not hasAny then
                if exportSelBtn._flashError then
                    exportSelBtn._flashError()
                end
                return
            end
            local activeName = CludesUI.GetActiveProfileName()
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
                local str = CludesUI.ExportProfile(
                    activeName,
                    exportFolders,
                    includeLayoutExport,
                    includeCDM,
                    cdmSpecs,
                    includeGlobalsExport,
                    includeOverrides,
                    includeWindowSkinsExport
                )
                if str then
                    CludesUI:ShowExportPopup(str)
                end
            end
            -- If the CDM module is selected, run the shared flow (ask -> spec picker); otherwise export straight away with no CDM spell layout.
            if folders["CludesUICooldownManager"] then
                CludesUI.RunCDMSpellExportFlow(activeName, finishExport)
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
    CludesUI._ProfilesResetToMain = function()
        importPage:Hide()
        pastePage:Hide()
        mainPage:Show()
    end

    -- Continue an API session with its decoded payload: UI-scale prompt (at most once), then the normal selection page. Registered per
    -- build (latest wins) and re-resolved from the namespace by every async continuation, so decode + scale popup land on THIS build's live frames.
    CludesUI._ProfilesApiProceed = function(payload)
        local s = CludesUI._apiImportSession
        if not s or s.state == "done" then
            return
        end
        if s.scaleAsked then
            ShowImportPage(s.str, payload, s.name, nil, nil, s.applyScale)
        else
            MaybeConfirmUIScale(payload, function(applyScale)
                s.scaleAsked = true
                s.applyScale = applyScale
                local go = CludesUI._ProfilesApiProceed
                if go then
                    go(payload)
                end
            end)
        end
    end

    -- Enter (or re-enter) a pending API import session: decode the string once, then proceed. Called by ImportProfileInteractive after it
    -- navigates here, and self-invoked at each build end so a session survives page rebuilds.
    CludesUI._ProfilesConsumeApiImport = function()
        local s = CludesUI._apiImportSession
        if not s or s.state == "done" then
            return
        end
        CludesUI._EnsureApiImportCloseHook()
        s.state = "active"
        if s.payload then
            CludesUI._ProfilesApiProceed(s.payload)
        elseif not s.decoding then
            s.decoding = true
            CludesUI.DecodeImportStringAsync(s.str, function(payload, err)
                s.decoding = nil
                -- The session may have been declined or replaced while the decode was in flight; drop a stale result.
                if CludesUI._apiImportSession ~= s or s.state == "done" then
                    return
                end
                if not payload then
                    CludesUI:ShowInfoPopup({
                        title = CludesUI.L("Import Failed"),
                        content = err or CludesUI.L("Invalid import string."),
                    })
                    CludesUI._FinishApiImportSession(false)
                    return
                end
                s.payload = payload
                local go = CludesUI._ProfilesApiProceed
                if go then
                    go(payload)
                end
            end)
        end
    end
    CludesUI._ProfilesConsumeApiImport()

    return 0
end
