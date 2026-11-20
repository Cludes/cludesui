if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_FirstInstall.lua
--
--  One-time popup on first install that lets the user pick which CUI addons
--  to keep enabled. Visual style mirrors the Spec Assign popup (dimmer +
--  dark panel + white border + Check All / Uncheck All links + Done button).
--
--  Layout: one column per group (the sidebar's groups: Core / Secondary /
--  Utility / UI Enhancements), one checkbox per row, groups build down
--  independently.
--
--  Fires at PLAYER_LOGIN, BEFORE the conflict-check popup (see CludesUI.lua
--  which now gates its conflict check on CludesUIDB.firstInstallPopupShown).
-------------------------------------------------------------------------------

local CludesUI = _G.CludesUI
if not CludesUI then
    return
end

-- Standalone builds bundle this file too, but the multi-module picker is
-- meaningless there: its GROUPS reference suite sibling addons (Action Bars,
-- Nameplates, ...) that simply do not exist in a single-module standalone. So
-- the first-install popup is suite-only. The build never renames the word
-- "Standalone", so deriving this from the host addon name (the `...` vararg =
-- real folder name) is the rename-immune switch -- false in the suite (host
-- "CludesUI"), true in any "CUIStandalone*" host. See the loader guard below.
local CUI_HOST_ADDON = ...
local IS_STANDALONE = type(CUI_HOST_ADDON) == "string" and CUI_HOST_ADDON:find("Standalone") ~= nil

local Pix = CludesUI.PanelPP

local MakeBorder = CludesUI.MakeBorder
local CLUDES_GREEN = CludesUI.CLUDES_GREEN

local BORDER_R = CludesUI.BORDER_R or 1
local BORDER_G = CludesUI.BORDER_G or 1
local BORDER_B = CludesUI.BORDER_B or 1
local CB_BOX_R = CludesUI.CB_BOX_R or 0.075
local CB_BOX_G = CludesUI.CB_BOX_G or 0.113
local CB_BOX_B = CludesUI.CB_BOX_B or 0.141
local CB_BRD_A = CludesUI.CB_BRD_A or 0.25
local CB_ACT_BRD_A = CludesUI.CB_ACT_BRD_A or 0.85

-- Groups: { header, { entries } } where each entry is { label = "...", addon = "..." (folder) }
-- If addon is nil the checkbox is informational / disabled (e.g. Cursor Circle, Bags).
local GROUPS = {
    {
        header = "Core Addons",
        entries = {
            { label = "Action Bars", addon = "CludesUIActionBars" },
            { label = "Nameplates", addon = "CludesUINameplates" },
            { label = "Unit Frames", addon = "CludesUIUnitFrames" },
            { label = "Cooldown Manager", addon = "CludesUICooldownManager" },
            { label = "Resource Bars", addon = "CludesUIResourceBars" },
            { label = "Raid & Party Frames", addon = "CludesUIRaidFrames" },
        },
    },
    {
        header = "Secondary Addons",
        entries = {
            { label = "Mythic+ Tools", addon = "CludesUIMythicTimer" },
            { label = "Damage Meters", addon = "CludesUIDamageMeters" },
            { label = "Buff Reminders", addon = "CludesUIAuraBuffReminders" },
            { label = "Title Line", addon = "CludesUITitleLine" },
            { label = "Tank Kit", addon = "CludesUITank" },
            { label = "Raid Lead", addon = "CludesUIRaidLead" },
        },
    },
    {
        header = "Utility Addons",
        entries = {
            { label = "Utilities", addon = "CludesUIQoL" },
            { label = "Forever Tools", addon = "CludesUIForeverEssentials" },
            { label = "Info Bar", addon = "CludesUIDataBars" },
            { label = "Action Wheel", addon = "CludesUIQuickdraw", defaultChecked = false },
            -- Cursor Circle is a feature inside the QoL addon (cursor.enabled).
            -- The checkbox here is a front-end shortcut that writes directly to
            -- the QoL profile so users get a sensible default on first install.
            { label = "Cursor Circle", setting = "cursorCircle", defaultChecked = false },
        },
    },
    {
        header = "UI Enhancements",
        entries = {
            { label = "Window Skins", addon = "CludesUIBlizzardSkin" },
            { label = "Chat", addon = "CludesUIChat" },
            { label = "Bags", addon = "CludesUIBags" },
            { label = "Quest Tracker", addon = "CludesUIQuestTracker" },
            { label = "Friends List", addon = "CludesUIFriends" },
        },
    },
}

-- Addons the running client leaves out (switched off on WoW Forever, or
-- Forever-only everywhere else) leave the picker (the sets live with the
-- roster in CludesUI.lua).
do
    local hidden = CludesUI._CLIENT_HIDDEN_ADDONS
    for _, set in ipairs(GROUPS) do
        for idx = #set.entries, 1, -1 do
            local addon = set.entries[idx].addon
            if addon and hidden[addon] then
                table.remove(set.entries, idx)
            end
        end
    end
end

local function IsAddonEnabled(folder)
    if not folder then
        return true
    end
    if C_AddOns and C_AddOns.GetAddOnEnableState then
        local char = UnitName("player")
        return (C_AddOns.GetAddOnEnableState(folder, char) or 0) > 0
    end
    return true
end

local function SetAddonEnabled(folder, enabled)
    if not folder or not C_AddOns then
        return
    end
    if enabled then
        if C_AddOns.EnableAddOn then
            C_AddOns.EnableAddOn(folder)
        end
    else
        if C_AddOns.DisableAddOn then
            C_AddOns.DisableAddOn(folder)
        end
    end
end

local function ShowFirstInstallPopup()
    local FONT = CludesUI.GetFontPath()
    local NUM_COLS = #GROUPS
    local COL_W = 210
    local COL_GAP = 18
    local CONTENT_LEFT = 41
    local CONTENT_RIGHT = 36
    local CONTENT_TOP = 216 -- below the header band + eyebrow/title/subtitle
    local HEADER_H = 32
    local HEADER_PAD = 6
    local ROW_H = 28
    local BOX_SZ = 18
    local CHECK_INSET = 3

    local POPUP_W = CONTENT_LEFT + CONTENT_RIGHT + NUM_COLS * COL_W + (NUM_COLS - 1) * COL_GAP

    -- Compute popup height from the tallest group
    local tallestRows = 0
    for _, group in ipairs(GROUPS) do
        if #group.entries > tallestRows then
            tallestRows = #group.entries
        end
    end
    local contentH = HEADER_H + HEADER_PAD + tallestRows * ROW_H
    local POPUP_H = CONTENT_TOP + contentH + 110 -- room for links + button

    -- Escape is disabled (no onEscape): the user must click Reload UI so their
    -- addon selection always takes effect. The popup is modal with no Escape
    -- route, so it is clamped to never exceed the display.
    local dimmer, dialog = CludesUI.BuildPopupShell("CUIFirstInstall", {
        w = POPUP_W,
        h = POPUP_H,
        bump = 1,
        clamp = true,
    })

    -- Decorative header visual (announcement-popup style): three mini module
    -- cards in the look of the picker columns below, each with the green top
    -- accent and a checked box beside stand-in text lines. The center card is
    -- slightly taller/brighter, matching the sibling popups' motif.
    do
        local EGh = CLUDES_GREEN
        local CARD_W, CARD_H, CARD_GAP = 124, 52, 14
        local MIDLINE = -54
        for idx = 1, 3 do
            local isCenter = (idx == 2)
            local wid = CARD_W
            local hgt = isCenter and (CARD_H + 10) or CARD_H
            local cardFrame = CreateFrame("Frame", nil, dialog)
            cardFrame:SetFrameLevel(dialog:GetFrameLevel() + 1)
            Pix.Size(cardFrame, wid, hgt)
            Pix.Point(cardFrame, "CENTER", dialog, "TOP", (idx - 2) * (CARD_W + CARD_GAP), MIDLINE)
            local cbg = cardFrame:CreateTexture(nil, "BACKGROUND")
            cbg:SetAllPoints()
            cbg:SetColorTexture(0.121, 0.113, 0.106, 1)

            -- Green top accent (the suite's hero-card signature).
            local accent = cardFrame:CreateTexture(nil, "ARTWORK")
            accent:SetColorTexture(EGh.r, EGh.g, EGh.b, isCenter and 0.95 or 0.7)
            accent:SetHeight(2)
            Pix.Point(accent, "TOPLEFT", cardFrame, "TOPLEFT", 1, -1)
            Pix.Point(accent, "TOPRIGHT", cardFrame, "TOPRIGHT", -1, -1)
            if accent.SetSnapToPixelGrid then
                accent:SetSnapToPixelGrid(false)
                accent:SetTexelSnappingBias(0)
            end

            -- Checked box + stand-in lines: the picker rows in miniature.
            local box = cardFrame:CreateTexture(nil, "ARTWORK")
            box:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
            Pix.Size(box, 12, 12)
            Pix.Point(box, "TOPLEFT", cardFrame, "TOPLEFT", 12, -14)
            local check = cardFrame:CreateTexture(nil, "OVERLAY")
            check:SetColorTexture(EGh.r, EGh.g, EGh.b, isCenter and 1 or 0.8)
            Pix.Size(check, 6, 6)
            Pix.Point(check, "CENTER", box, "CENTER", 0, 0)
            local l1 = cardFrame:CreateTexture(nil, "ARTWORK")
            l1:SetColorTexture(1, 1, 1, isCenter and 0.42 or 0.32)
            Pix.Size(l1, wid - 52, 5)
            Pix.Point(l1, "LEFT", box, "RIGHT", 8, 0)
            local l2 = cardFrame:CreateTexture(nil, "ARTWORK")
            l2:SetColorTexture(1, 1, 1, 0.16)
            Pix.Size(l2, wid - 72, 5)
            Pix.Point(l2, "TOPLEFT", box, "BOTTOMLEFT", 0, -8)
            if isCenter then
                local l3 = cardFrame:CreateTexture(nil, "ARTWORK")
                l3:SetColorTexture(1, 1, 1, 0.12)
                Pix.Size(l3, wid - 84, 5)
                Pix.Point(l3, "TOPLEFT", l2, "BOTTOMLEFT", 0, -7)
            end
            MakeBorder(cardFrame, 1, 1, 1, isCenter and 0.16 or 0.10, Pix)
        end
    end

    -- Eyebrow
    local eyebrow = dialog:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 0.9)
    Pix.Point(eyebrow, "TOP", dialog, "TOP", 0, -104)
    eyebrow:SetText(CludesUI.L("FIRST TIME SETUP"))

    -- Title
    local title = dialog:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 25, "")
    title:SetTextColor(1, 1, 1, 1)
    Pix.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText(CludesUI.L("Welcome to CludesUI"))

    -- Subtitle
    local sub = dialog:CreateFontString(nil, "OVERLAY")
    sub:SetFont(FONT, 14, "")
    sub:SetTextColor(1, 1, 1, 0.45)
    Pix.Point(sub, "TOP", title, "BOTTOM", 0, -8)
    sub:SetWidth(POPUP_W - 60)
    sub:SetJustifyH("CENTER")
    sub:SetWordWrap(true)
    sub:SetText(
        CludesUI.L(
            "Choose which addons you want enabled. You can change any of these later in the CludesUI settings panel."
        )
    )

    -- Check All / Uncheck All links
    local LINK_Y = -196
    local LINK_GAP = 20

    local checkAllBtn = CreateFrame("Button", nil, dialog)
    checkAllBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
    local checkAllLbl = checkAllBtn:CreateFontString(nil, "OVERLAY")
    checkAllLbl:SetFont(FONT, 14, "")
    checkAllLbl:SetText(CludesUI.L("Check All"))
    checkAllLbl:SetTextColor(1, 1, 1, 0.45)
    checkAllLbl:SetPoint("CENTER")
    checkAllBtn:SetSize(checkAllLbl:GetStringWidth() + 4, 20)
    Pix.Point(checkAllBtn, "TOPLEFT", dialog, "TOPLEFT", CONTENT_LEFT, LINK_Y)
    checkAllBtn:SetScript("OnEnter", function()
        checkAllLbl:SetTextColor(1, 1, 1, 0.80)
    end)
    checkAllBtn:SetScript("OnLeave", function()
        checkAllLbl:SetTextColor(1, 1, 1, 0.45)
    end)

    local linkDivider = dialog:CreateTexture(nil, "OVERLAY", nil, 7)
    linkDivider:SetColorTexture(1, 1, 1, 0.18)
    if linkDivider.SetSnapToPixelGrid then
        linkDivider:SetSnapToPixelGrid(false)
        linkDivider:SetTexelSnappingBias(0)
    end
    Pix.Point(linkDivider, "LEFT", checkAllBtn, "RIGHT", LINK_GAP / 2, 0)
    linkDivider:SetWidth(1)
    linkDivider:SetHeight(12)

    local uncheckAllBtn = CreateFrame("Button", nil, dialog)
    uncheckAllBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
    local uncheckAllLbl = uncheckAllBtn:CreateFontString(nil, "OVERLAY")
    uncheckAllLbl:SetFont(FONT, 14, "")
    uncheckAllLbl:SetText(CludesUI.L("Uncheck All"))
    uncheckAllLbl:SetTextColor(1, 1, 1, 0.45)
    uncheckAllLbl:SetPoint("CENTER")
    uncheckAllBtn:SetSize(uncheckAllLbl:GetStringWidth() + 4, 20)
    Pix.Point(uncheckAllBtn, "LEFT", checkAllBtn, "RIGHT", LINK_GAP, 0)
    uncheckAllBtn:SetScript("OnEnter", function()
        uncheckAllLbl:SetTextColor(1, 1, 1, 0.80)
    end)
    uncheckAllBtn:SetScript("OnLeave", function()
        uncheckAllLbl:SetTextColor(1, 1, 1, 0.45)
    end)

    -- Track all checkbox rows for check-all / uncheck-all
    local allRows = {}

    -- One column per group
    for colIdx, set in ipairs(GROUPS) do
        local col = CreateFrame("Frame", nil, dialog)
        col:SetFrameLevel(dialog:GetFrameLevel() + 1)
        local colX = CONTENT_LEFT + (colIdx - 1) * (COL_W + COL_GAP)
        Pix.Point(col, "TOPLEFT", dialog, "TOPLEFT", colX, -CONTENT_TOP)
        Pix.Size(col, COL_W, POPUP_H - CONTENT_TOP - 80)

        -- Group header (styled like a class header)
        local heading = col:CreateFontString(nil, "OVERLAY")
        heading:SetFont(FONT, 18, "")
        heading:SetTextColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 0.9)
        Pix.Point(heading, "TOPLEFT", col, "TOPLEFT", 4, -4)
        heading:SetText(CludesUI.L(set.header))

        local yOff = HEADER_H + HEADER_PAD

        for _, record in ipairs(set.entries) do
            local row = CreateFrame("Button", nil, col)
            Pix.Size(row, COL_W, ROW_H)
            row:ClearAllPoints()
            Pix.Point(row, "TOPLEFT", col, "TOPLEFT", 0, -yOff)

            local box = CreateFrame("Frame", nil, row)
            Pix.Size(box, BOX_SZ, BOX_SZ)
            Pix.Point(box, "LEFT", row, "LEFT", 8, 0)
            box:SetFrameLevel(row:GetFrameLevel() + 1)

            local boxBg = box:CreateTexture(nil, "BACKGROUND")
            boxBg:SetAllPoints()
            boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
            local boxBorder = CludesUI.MakeRoundedBorder(box, BORDER_R, BORDER_G, BORDER_B, CB_BRD_A, boxBg)

            local check = box:CreateTexture(nil, "ARTWORK")
            Pix.Point(check, "TOPLEFT", box, "TOPLEFT", CHECK_INSET, -CHECK_INSET)
            Pix.Point(check, "BOTTOMRIGHT", box, "BOTTOMRIGHT", -CHECK_INSET, CHECK_INSET)
            check:SetColorTexture(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
            CludesUI.RoundBody(box, check, 1)

            local labelFS = row:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(FONT, 17, "")
            Pix.Point(labelFS, "LEFT", box, "RIGHT", 8, 0)
            labelFS:SetTextColor(1, 1, 1, 0.65)
            labelFS:SetText(CludesUI.L(record.label))

            -- Initial state resolution:
            --   entry.comingSoon -> disabled, greyed, "Coming soon" tooltip
            --   entry.addon      -> current C_AddOns enable state (unticked when the entry
            --                       says defaultChecked = false: an opt-in addon)
            --   entry.setting    -> start at entry.defaultChecked (front-end shortcut)
            --   neither          -> disabled, generic greyed state
            local checked
            if record.comingSoon then
                checked = false
            elseif record.addon then
                checked = IsAddonEnabled(record.addon) and record.defaultChecked ~= false
            elseif record.setting then
                checked = record.defaultChecked and true or false
            else
                checked = false
            end

            row._entry = record
            row._checked = checked
            row._check = check
            row._boxBorder = boxBorder
            row._lbl = labelFS
            row._informational = (record.comingSoon == true)
                or (record.addon == nil and record.setting == nil)

            local function UpdateVisual(r)
                if r._informational then
                    r._check:Hide()
                    r._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A * 0.4)
                    r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 0.35)
                    r._lbl:SetTextColor(1, 1, 1, 0.25)
                elseif r._checked then
                    r._check:Show()
                    r._boxBorder:SetColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, CB_ACT_BRD_A)
                else
                    r._check:Hide()
                    r._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A)
                end
            end
            row._boxBg = boxBg
            UpdateVisual(row)

            row:SetScript("OnClick", function(self)
                if self._informational then
                    return
                end
                self._checked = not self._checked
                UpdateVisual(self)
            end)
            row:SetScript("OnEnter", function(self)
                if self._informational then
                    CludesUI.ShowWidgetTooltip(self, "Coming soon")
                    return
                end
                self._lbl:SetTextColor(1, 1, 1, 0.90)
            end)
            row:SetScript("OnLeave", function(self)
                CludesUI.HideWidgetTooltip()
                if self._informational then
                    return
                end
                self._lbl:SetTextColor(1, 1, 1, 0.65)
            end)

            allRows[#allRows + 1] = row
            yOff = yOff + ROW_H
        end
    end

    -- Done button (text swaps between "Okay" and "Reload UI" based on changes)
    local ACC = CLUDES_GREEN
    local doneBtn = CreateFrame("Button", nil, dialog)
    doneBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
    Pix.Size(doneBtn, 200, 39)
    Pix.Point(doneBtn, "BOTTOM", dialog, "BOTTOM", 0, 38)
    local doneBg = doneBtn:CreateTexture(nil, "BACKGROUND")
    doneBg:SetAllPoints()
    doneBg:SetColorTexture(0.062, 0.070, 0.082, 0.92)
    local doneBrd = CludesUI.MakeRoundedBorder(doneBtn, ACC.r, ACC.g, ACC.b, 0.9, doneBg)
    local doneLbl = doneBtn:CreateFontString(nil, "OVERLAY")
    doneLbl:SetFont(FONT, 16, "")
    Pix.Point(doneLbl, "CENTER", doneBtn, "CENTER", 0, 0)
    doneLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
    doneBtn:SetScript("OnEnter", function()
        doneLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
        doneBrd:SetColor(ACC.r, ACC.g, ACC.b, 1)
    end)
    doneBtn:SetScript("OnLeave", function()
        doneLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
        doneBrd:SetColor(ACC.r, ACC.g, ACC.b, 0.9)
    end)

    local function SyncButtonLabel()
        -- Picking addons always ends in a reload so the enable/disable choices
        -- take effect, so the button always reads "Reload UI".
        doneLbl:SetText(CludesUI.L("Reload UI"))
    end
    SyncButtonLabel()

    -- Hook each checkbox click to refresh the button label
    for _, row in ipairs(allRows) do
        local origOnClick = row:GetScript("OnClick")
        row:SetScript("OnClick", function(self, ...)
            if origOnClick then
                origOnClick(self, ...)
            end
            SyncButtonLabel()
        end)
    end

    -- Check All / Uncheck All wiring
    checkAllBtn:SetScript("OnClick", function()
        for _, row in ipairs(allRows) do
            if not row._informational and not row._checked then
                row._checked = true
                row._check:Show()
                row._boxBorder:SetColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, CB_ACT_BRD_A)
            end
        end
        SyncButtonLabel()
    end)
    uncheckAllBtn:SetScript("OnClick", function()
        for _, row in ipairs(allRows) do
            if not row._informational and row._checked then
                row._checked = false
                row._check:Hide()
                row._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A)
            end
        end
        SyncButtonLabel()
    end)

    local function Close(triggerReload)
        if not CludesUIDB then
            CludesUIDB = {}
        end
        CludesUIDB.firstInstallPopupShown = true
        CludesUIDB.bagsUserChosen = true
        -- WoW Forever: the stamp the loader below set at ADDON_LOADED is still
        -- set unless a look was settled while this popup was up (an import, a
        -- Style page change).
        local lookOpen = CludesUIDB.styleChoicePending
        -- The style picker (CludesUI_StyleChoicePopup.lua) follows on the
        -- next login, after this popup's reload; on WoW Forever only while
        -- no look was settled here.
        CludesUIDB.styleChoicePending = (lookOpen or not CludesUI.IS_FOREVER) and true or nil
        CludesUI._firstInstallPending = nil

        -- Write QoL cursor setting directly into the profile table so it
        -- survives even if the user also disables the QoL addon. NewDB merges
        -- defaults with stored values at next init, so the written value sticks.
        local function ApplyCursorCircle(enabled)
            if not CludesUIDB then
                CludesUIDB = {}
            end
            if not CludesUIDB.profiles then
                CludesUIDB.profiles = {}
            end
            local profileName = CludesUIDB.activeProfile or "Default"
            if type(CludesUIDB.profiles[profileName]) ~= "table" then
                CludesUIDB.profiles[profileName] = {}
            end
            local prof = CludesUIDB.profiles[profileName]
            if not prof.addons then
                prof.addons = {}
            end
            if not prof.addons.CludesUIQoL then
                prof.addons.CludesUIQoL = {}
            end
            if not prof.addons.CludesUIQoL.cursor then
                prof.addons.CludesUIQoL.cursor = {}
            end
            prof.addons.CludesUIQoL.cursor.enabled = enabled and true or false
        end

        -- Always write the Cursor Circle choice, even on "no reload" close,
        -- since the default (cursor.enabled = true) differs from the popup's
        -- default-unchecked state.
        for _, row in ipairs(allRows) do
            if row._entry.setting == "cursorCircle" then
                ApplyCursorCircle(row._checked)
            end
        end

        if triggerReload then
            -- The reload first in the click, then what it applies as its
            -- pre-reload work (RequestReload): the addon enable/disable
            -- changes and, on WoW Forever, the look a fresh install starts
            -- on, written so the style picker opens on the look in use (its
            -- card then closes the picker without a second reload). The
            -- options addon loads for it, never in combat; in combat, or when
            -- it cannot load, the picker offers the look as its default instead.
            CludesUI.RequestReload(nil, nil, function()
                for _, row in ipairs(allRows) do
                    if row._entry.addon then
                        SetAddonEnabled(row._entry.addon, row._checked)
                    end
                end
                if
                    CludesUI.IS_FOREVER
                    and lookOpen
                    and not InCombatLockdown()
                    and CludesUI.EnsureOptionsLoaded()
                then
                    CludesUI.ApplyFirstInstallLook("forever")
                end
            end)
            return
        end

        dimmer:Hide()
        -- Re-apply the cursor so the written setting takes effect live
        -- (the QoL addon had already applied its default at login).
        if _G._CUCL_Apply then
            pcall(_G._CUCL_Apply)
        end
        -- No reload needed, so run the deferred conflict check now
        if CludesUI._RunConflictCheck then
            C_Timer.After(0.5, CludesUI._RunConflictCheck)
        end
    end

    doneBtn:SetScript("OnClick", function()
        -- Always reload so the addon enable/disable selections take effect.
        Close(true)
    end)

    dimmer:Show()
    -- Controller cursor: the picker has no other way out, so bring the gamepad pointer up.
    if CludesUI.PadNative() then
        CludesUI.RaiseGamePadCursor()
    end
end

CludesUI.ShowFirstInstallPopup = ShowFirstInstallPopup

-------------------------------------------------------------------------------
--  Trigger on first install only
-------------------------------------------------------------------------------
-- First-install detection captured at parent ADDON_LOADED. At that moment CludesUIDB
-- still reflects the PREVIOUS session's data: child addons have not yet initialized
-- their DBs this session, so any profile.addons entries can only have come from a prior
-- version. This cleanly separates upgrades from fresh installs without needing version
-- stamps. Standalone: never arm the suite first-install picker (see note at top of
-- file). This makes the non-firing explicit rather than relying on the incidental
-- addon-name mismatch (the renamed "CludesUI" ADDON_LOADED gate would point at the
-- core token, never the real child/folder token, so it never matched anyway).
if IS_STANDALONE then
    return
end

local _showPopupOnLogin = false

local function ComputeShowOnLogin()
    if not CludesUIDB then
        -- Truly fresh: SV not written yet.
        return true
    end
    if CludesUIDB.firstInstallPopupShown then
        return false
    end
    local profiles = CludesUIDB.profiles
    if type(profiles) == "table" then
        for _, prof in pairs(profiles) do
            if type(prof) == "table" and type(prof.addons) == "table" and next(prof.addons) then
                -- Data from a previous session: upgrade user, stamp + skip.
                CludesUIDB.firstInstallPopupShown = true
                return false
            end
        end
    end
    -- No prior data exists: treat as fresh install.
    return true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, evt, addonName)
    if evt == "ADDON_LOADED" then
        if addonName ~= "CludesUI" then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        _showPopupOnLogin = ComputeShowOnLogin()
        -- WoW Forever: the style picker (WoW Forever by default there) is due
        -- even if this session ends before the module picker's reload.
        if _showPopupOnLogin and CludesUI.IS_FOREVER then
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.styleChoicePending = true
        end
        if _showPopupOnLogin then
            -- Handshake for other first-login popups (e.g. CDM's Edit Mode
            -- reload prompt): the picker is coming and ALWAYS ends in its own
            -- forced ReloadUI, so reload-prompting popups must stay silent and
            -- let that reload apply their changes. Cleared in Close().
            CludesUI._firstInstallPending = true
        end
    elseif evt == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if not _showPopupOnLogin then
            return
        end
        C_Timer.After(0.5, function()
            if CludesUIDB and CludesUIDB.firstInstallPopupShown then
                return
            end
            -- A registered external installer owns the first-run experience:
            -- keep the picker silent (the pending handshake stays armed; the
            -- installer's import stamps first-install state, and a session
            -- with no registration brings the picker back).
            if CludesUI._externalInstaller then
                return
            end
            ShowFirstInstallPopup()
        end)
    end
end)
