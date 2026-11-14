if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI and CludesUI.IS_FOREVER then
    return
end -- no dungeon teleports on WoW Forever: no popup, no secure button, no events; the LFG Reminder options section is not built there and every reader of the _G._CUI_*TeleportPrompt hooks nil-guards
-------------------------------------------------------------------------------
--  CludesUIQoL_TeleportPrompt.lua
--  When the player joins a Group Finder (LFGList) group for a dungeon that has
--  a known teleport, show a small square popup ("LFG Reminder") with the dungeon
--  name and a one-click teleport button. The popup hides when the player enters
--  the dungeon, leaves the group, or enters combat. A "Disable Feature" text
--  below the button turns the whole feature off (re-enable in QoL options).
--
--  Taint / secret-value safety (this is critical, read before editing):
--   - The teleport spellID fed to SetAttribute("spell", id) is ALWAYS a static
--     integer resolved from our own name->spell table, never an LFG field.
--   - The dungeon is resolved on LFG_LIST_JOINED_GROUP, where the search result
--     is readable. While browsing/applying, GetSearchResultInfo returns secret
--     values (activityIDs is a secret table -> indexing throws); joining lifts
--     that. We still guard every field with issecretvalue() and wrap the whole
--     lookup in pcall, so a secret value can only make us skip the prompt, never
--     error. The dungeon name is only ever SetText'd (which accepts secrets).
--   - The secure button is created ONCE at login (out of combat); only the
--     "spell" attribute is rewritten later, and only out of combat (deferred to
--     PLAYER_REGEN_ENABLED when an accept lands mid-combat).
--   - We never hook, SetScript, or write keys onto any Blizzard Group Finder
--     frame. All state lives on frames we create or in file-local upvalues.
-------------------------------------------------------------------------------
local CUI = CludesUI
local Pix = CUI and CUI.PP
local issecretvalue = issecretvalue or function()
    return false
end

-- Settings live on the shared CludesUIDB (lazy-init, never re-init at scope).
local function TeleCfg()
    if not CludesUIDB then
        return {}
    end
    CludesUIDB.teleportPrompt = CludesUIDB.teleportPrompt or {}
    return CludesUIDB.teleportPrompt
end

local function IsEnabled()
    return TeleCfg().enabled ~= false -- default ON
end

-------------------------------------------------------------------------------
--  Layout constants
-------------------------------------------------------------------------------
local POPUP_W = 210
local TITLE_H = 27
local PAD = 10
local NAME_TOP = TITLE_H + 9 -- dungeon-name text top offset
local NAME_H = 24 -- reserved height for the name line
local BTN_TOP = NAME_TOP + NAME_H
local BTN_H = 56
local DISABLE_TOP = BTN_TOP + BTN_H + 8 -- "Disable Feature" text below the button
local DISABLE_H = 16
local POPUP_H = DISABLE_TOP + DISABLE_H + 10

-------------------------------------------------------------------------------
--  State (plain upvalues; never keyed by a possibly-secret resultID)
-------------------------------------------------------------------------------
local dialog, secureBtn
local pendingSpellID -- resolved teleport spell (static integer) to use
local pendingName -- dungeon display name for the title (guaranteed clean)
local pendingAttrSpellID -- spell attr stashed to write when leaving combat
local pendingShow -- join landed in combat; show on PLAYER_REGEN_ENABLED
local pendingHide -- hide requested in combat; hide on PLAYER_REGEN_ENABLED
local shownSpellID -- teleport the prompt last surfaced for in this group

-- Forward declarations (closures reference each other)
local BuildPopup, ShowPrompt, HidePrompt, ClearPending
local ApplyTeleportPrompt -- live enable/disable entry point (defined in the events section)
local UpdateButtonVisuals, ResolveDungeon, ResolveActiveEntry, ResolveActivity
local SavePosition, ApplySavedPosition, ApplyDisableVisibility

-------------------------------------------------------------------------------
--  Font helpers (mirror the /keys popup)
-------------------------------------------------------------------------------
local function ResolveFont()
    return (CUI.GetFontPath("extras")) or "Fonts\\FRIZQT__.TTF"
end
local function ResolveOutline()
    return (CUI.GetFontOutlineFlag("extras")) or ""
end
local function MakeLabel(hostFrame, dim, r, g, b, a)
    local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
    local flags = ResolveOutline()
    CUI.PrimeFontShadow(fontStr, flags == "")
    fontStr:SetFont(ResolveFont(), dim, flags)
    if r then
        fontStr:SetTextColor(r, g or 1, b or 1, a or 1)
    end
    return fontStr
end

-------------------------------------------------------------------------------
--  Position persistence (per-feature DB key only)
-------------------------------------------------------------------------------
SavePosition = function()
    if not dialog then
        return
    end
    local p, _, rp, posX, yo = dialog:GetPoint()
    if p then
        TeleCfg().pos = { p = p, rp = rp, x = posX, y = yo }
    end
end

ApplySavedPosition = function()
    if not dialog then
        return
    end
    dialog:ClearAllPoints()
    local place = TeleCfg().pos
    if place and place.p then
        dialog:SetPoint(place.p, UIParent, place.rp or place.p, place.x or 0, place.y or 0)
    else
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

-- Show/hide the "Disable Feature" text and trim the window height by 20px when
-- it is hidden. Driven by CludesUIDB.teleportPrompt.showDisable (default ON).
ApplyDisableVisibility = function()
    if not dialog then
        return
    end
    local show = TeleCfg().showDisable ~= false
    if dialog._disableBtn then
        dialog._disableBtn:SetShown(show)
    end
    dialog:SetHeight(show and POPUP_H or (POPUP_H - 20))
end

-------------------------------------------------------------------------------
--  Build the popup + secure button (called once at login, out of combat)
-------------------------------------------------------------------------------
BuildPopup = function()
    if dialog then
        return dialog
    end

    dialog = CreateFrame("Frame", "CUITeleportPopup", UIParent)
    dialog:SetSize(POPUP_W, POPUP_H)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(s)
        s:StartMoving()
    end)
    dialog:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        SavePosition()
    end)

    local backdrop = dialog:CreateTexture(nil, "BACKGROUND", nil, 0)
    backdrop:SetAllPoints()
    backdrop:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
    backdrop:SetTexCoord(0.25, 1, 0, 0.75)
    local overlayFrame = dialog:CreateTexture(nil, "BACKGROUND", nil, 1)
    overlayFrame:SetAllPoints()
    overlayFrame:SetColorTexture(0, 0, 0, 0.55)

    if Pix and Pix.CreateBorder then
        Pix.CreateBorder(dialog, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
    end

    -- Header bar with the dungeon title
    local hdrBg = dialog:CreateTexture(nil, "BORDER")
    hdrBg:SetColorTexture(0, 0, 0, 0.25)
    hdrBg:SetPoint("TOPLEFT", 1, -1)
    hdrBg:SetPoint("TOPRIGHT", -1, 0)
    hdrBg:SetHeight(TITLE_H)

    local titleText = MakeLabel(dialog, 11, 1, 1, 1, 1)
    titleText:SetPoint("TOPLEFT", PAD, -8)
    titleText:SetPoint("TOPRIGHT", -(PAD + 16), -8)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    titleText:SetText("LFG Reminder")

    -- Joined dungeon's full name, centered above the teleport button. Set in
    -- ShowPrompt; the name may be a secret string and SetText accepts secrets.
    local nameFS = MakeLabel(dialog, 13, 1, 1, 1, 1)
    nameFS:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, -NAME_TOP)
    nameFS:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -PAD, -NAME_TOP)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetWordWrap(true)
    dialog._name = nameFS

    -- Close (X) in the header
    local ICON_SZ, ICON_ALPHA = 14, 0.5
    local xBtn = CreateFrame("Button", nil, dialog)
    xBtn:SetSize(ICON_SZ, ICON_SZ)
    xBtn:SetPoint("RIGHT", hdrBg, "RIGHT", -8, 0)
    local xTex = xBtn:CreateTexture(nil, "ARTWORK")
    xTex:SetAllPoints()
    xTex:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
    xTex:SetAlpha(ICON_ALPHA)
    xBtn:SetScript("OnEnter", function()
        xTex:SetAlpha(1)
    end)
    xBtn:SetScript("OnLeave", function()
        xTex:SetAlpha(ICON_ALPHA)
    end)
    xBtn:SetScript("OnClick", function()
        HidePrompt()
    end)

    -- Secure teleport button (created out of combat, once). type + clicks are
    -- set here and NEVER touched again; only "spell" is rewritten (out of combat).
    secureBtn = CreateFrame("Button", "CUITeleportButton", dialog, "SecureActionButtonTemplate")
    secureBtn:SetSize(POPUP_W - PAD * 2, BTN_H)
    -- A protected frame can only be anchored to another FRAME, never to a region
    -- (texture/fontstring). Anchor to the popup frame, below the name text.
    secureBtn:SetPoint("TOP", dialog, "TOP", 0, -BTN_TOP)
    secureBtn:RegisterForClicks("AnyUp", "AnyDown")
    secureBtn:SetAttribute("type", "spell")

    local btnBg = secureBtn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetAllPoints()
    btnBg:SetColorTexture(0.044, 0.034, 0.026, 0.9)
    if Pix and Pix.CreateBorder then
        Pix.CreateBorder(secureBtn, 0, 0, 0, 1, 1, "OVERLAY", 7)
    end

    local glyph = secureBtn:CreateTexture(nil, "ARTWORK")
    glyph:SetSize(40, 40)
    glyph:SetPoint("LEFT", 8, 0)
    glyph:SetTexCoord(6 / 64, 58 / 64, 6 / 64, 58 / 64)
    secureBtn._icon = glyph

    local btnLabel = MakeLabel(secureBtn, 12, 1, 1, 1, 1)
    btnLabel:SetPoint("LEFT", glyph, "RIGHT", 8, 0)
    btnLabel:SetPoint("RIGHT", -6, 0)
    btnLabel:SetJustifyH("LEFT")
    btnLabel:SetWordWrap(false)
    btnLabel:SetText("Teleport")
    secureBtn._label = btnLabel

    local hover = secureBtn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.12)

    -- The cooldown inherits the button's protection, so anchor it to the button
    -- FRAME (matching the icon's position/size), never to the icon texture.
    local cd = CreateFrame("Cooldown", nil, secureBtn, "CooldownFrameTemplate")
    cd:SetPoint("LEFT", secureBtn, "LEFT", 8, 0)
    cd:SetSize(40, 40)
    cd:SetHideCountdownNumbers(true)
    cd:SetDrawSwipe(true)
    cd:SetDrawBling(false)
    cd:SetDrawEdge(false)
    secureBtn._cd = cd

    secureBtn:SetScript("OnEnter", function(self)
        local spellRef = pendingSpellID
        if not spellRef then
            return
        end
        if not IsPlayerSpell(spellRef) then
            CUI.ShowWidgetTooltip(self, "You have not learned this dungeon teleport yet.")
            return
        end
        local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellRef)
        if cdInfo and cdInfo.duration and cdInfo.duration > 0 then
            CUI.ShowWidgetTooltip(self, "Teleport on Cooldown")
        elseif CUI.ShowWidgetTooltip then
            CUI.ShowWidgetTooltip(self, CUI.Lf("Teleport to %s", pendingName or CUI.L("dungeon")))
        end
    end)
    secureBtn:SetScript("OnLeave", function()
        CUI.HideWidgetTooltip()
    end)

    -- "Disable Feature" text below the teleport button. Clicking it turns the
    -- whole LFG Reminder feature off and hides the popup immediately.
    local disableBtn = CreateFrame("Button", nil, dialog)
    disableBtn:SetSize(POPUP_W - PAD * 2, DISABLE_H)
    disableBtn:SetPoint("TOP", dialog, "TOP", 0, -DISABLE_TOP)
    local disableLbl = MakeLabel(disableBtn, 10, 0.6, 0.6, 0.6, 1)
    disableLbl:SetAllPoints()
    disableLbl:SetJustifyH("CENTER")
    disableLbl:SetText("Disable Feature")
    disableBtn:SetScript("OnEnter", function()
        disableLbl:SetTextColor(1, 0.3, 0.3, 1)
    end)
    disableBtn:SetScript("OnLeave", function()
        disableLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    end)
    disableBtn:SetScript("OnClick", function()
        TeleCfg().enabled = false
        ApplyTeleportPrompt()
    end)
    dialog._disableBtn = disableBtn

    -- Intentionally NOT registered for Escape-close: the popup should stay until
    -- the player teleports, enters the dungeon, leaves the group, or disables it.

    dialog:SetScale(TeleCfg().scale or 1.05)
    ApplySavedPosition()
    ApplyDisableVisibility()
    dialog:Hide()
    return dialog
end

-------------------------------------------------------------------------------
--  Visuals (all use the clean static integer, so compares are safe)
-------------------------------------------------------------------------------
UpdateButtonVisuals = function()
    if not secureBtn or not pendingSpellID then
        return
    end
    local spellRef = pendingSpellID
    local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellRef)
    if details and details.iconID then
        secureBtn._icon:SetTexture(details.iconID)
    end
    local known = IsPlayerSpell(spellRef)
    secureBtn._icon:SetDesaturated(not known)
    secureBtn._icon:SetAlpha(known and 1 or 0.4)
    local lc = known and 1 or 0.5
    secureBtn._label:SetTextColor(lc, lc, lc, 1)
    if known then
        local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellRef)
        if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
            secureBtn._cd:SetCooldown(cdInfo.startTime, cdInfo.duration)
        else
            secureBtn._cd:Clear()
        end
    else
        secureBtn._cd:Clear()
    end
end

-------------------------------------------------------------------------------
--  Resolve a known LFG activity -> teleport spell via a CLEAN string chain.
-------------------------------------------------------------------------------
ResolveActivity = function(activityID)
    if
        not (C_LFGList and C_LFGList.GetActivityInfoTable)
        or issecretvalue(activityID)
        or type(activityID) ~= "number"
    then
        return
    end
    pcall(function()
        local act = C_LFGList.GetActivityInfoTable(activityID)
        if type(act) ~= "table" then
            return
        end
        local fullName = act.fullName
        if type(fullName) ~= "string" or issecretvalue(fullName) then
            return
        end
        local spellId = CUI and CUI.ResolveTeleportSpellByName and CUI.ResolveTeleportSpellByName(fullName)
        if spellId then
            pendingSpellID = spellId
            -- Display only the dungeon name, not the trailing difficulty suffix
            -- (e.g. "Skyreach (Mythic Keystone)" -> "Skyreach").
            pendingName = (fullName:gsub("%s*%b()%s*$", ""))
        end
    end)
end

-- Search results are readable when accepting an invite. Capture immediately:
-- they can expire shortly after joining.
ResolveDungeon = function(resultID)
    if not (C_LFGList and C_LFGList.GetSearchResultInfo) then
        return
    end
    pcall(function()
        local details = C_LFGList.GetSearchResultInfo(resultID)
        if type(details) ~= "table" then
            return
        end
        local activityID = details.activityID
        if activityID == nil and details.activityIDs and not issecretvalue(details.activityIDs) then
            activityID = details.activityIDs[1]
        end
        ResolveActivity(activityID)
    end)
end

-- A leader creates or updates an active listing without receiving
-- LFG_LIST_JOINED_GROUP. Its activityIDs are documented NeverSecret.
ResolveActiveEntry = function()
    if not (C_LFGList and C_LFGList.GetActiveEntryInfo) then
        return
    end
    pcall(function()
        local record = C_LFGList.GetActiveEntryInfo()
        if type(record) ~= "table" or issecretvalue(record.activityIDs) then
            return
        end
        ResolveActivity(record.activityIDs[1])
    end)
end

-------------------------------------------------------------------------------
--  Show / Hide / Clear
-------------------------------------------------------------------------------
ShowPrompt = function()
    if not IsEnabled() or not pendingSpellID then
        return
    end
    BuildPopup()
    dialog._name:SetText(pendingName or "") -- SetText accepts secret strings natively
    if InCombatLockdown() then
        -- Cannot write the secure attribute or surface the protected teleport
        -- button in combat (and teleports cannot be cast in combat anyway).
        -- Defer the whole show to PLAYER_REGEN_ENABLED.
        pendingAttrSpellID = pendingSpellID
        pendingShow = true
        pendingHide = nil -- a deferred show supersedes any deferred hide
        return
    end
    secureBtn:SetAttribute("spell", pendingSpellID) -- always a static integer
    pendingAttrSpellID = nil
    pendingHide = nil
    UpdateButtonVisuals()
    dialog:Show()
end

HidePrompt = function()
    pendingShow = nil
    -- popup parents a SecureActionButton, so popup:Hide() is a protected call the
    -- game blocks in combat. If it's already hidden there is nothing to do (avoids
    -- the blocked call entirely -- the common case when leaving an instance in
    -- combat). If it's genuinely shown during combat, defer the hide to
    -- PLAYER_REGEN_ENABLED instead of calling the protected method now.
    if not (dialog and dialog:IsShown()) then
        pendingHide = nil
        return
    end
    if InCombatLockdown() then
        pendingHide = true
        return
    end
    pendingHide = nil
    dialog:Hide()
end

ClearPending = function()
    pendingSpellID = nil
    pendingName = nil
    pendingShow = nil
end

-- Live update hook for the options slider/toggles (scale + disable-text row).
_G._CUI_RefreshTeleportPrompt = function()
    if not dialog then
        return
    end
    dialog:SetScale(TeleCfg().scale or 1.05)
    ApplyDisableVisibility()
end

-------------------------------------------------------------------------------
--  Events. No Blizzard frame is ever hooked or SetScript-ed. Heavy events are
--  only registered when the feature is enabled (zero cost when disabled).
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")

-- Feature events are registered only while enabled and unregistered on
-- disable, so a disabled reminder costs nothing on roster/zone/combat events.
-- PLAYER_REGEN_ENABLED outlives a mid-combat disable while a combat-blocked
-- hide or secure attribute write is pending; its handler re-syncs afterwards.
local function SyncEvents()
    if IsEnabled() then
        ev:RegisterEvent("LFG_LIST_JOINED_GROUP")
        ev:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ev:UnregisterEvent("LFG_LIST_JOINED_GROUP")
        ev:UnregisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
        ev:UnregisterEvent("GROUP_ROSTER_UPDATE")
        ev:UnregisterEvent("PLAYER_ENTERING_WORLD")
        ev:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
        ev:UnregisterEvent("PLAYER_REGEN_DISABLED")
        if not (pendingHide or pendingAttrSpellID) then
            ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    end
end

-- Live enable/disable (options toggle and the in-popup Disable Feature text):
-- takes effect immediately in both directions, no reload. The popup parents a
-- secure button, so a mid-combat first enable defers the build to combat end.
local pendingBuild

-- Records the group's current listing as already shown, without showing it: a
-- /reload or re-enable starts with an empty memory, and the next edit of a listing
-- the player already saw must not pop the prompt again.
local function SeedShownFromListing()
    ClearPending()
    ResolveActiveEntry()
    shownSpellID = pendingSpellID
    ClearPending()
end

ApplyTeleportPrompt = function()
    if IsEnabled() then
        SeedShownFromListing()
        if not dialog and InCombatLockdown() then
            pendingBuild = true
            ev:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        pendingBuild = nil
        BuildPopup()
        SyncEvents()
    else
        pendingBuild = nil
        ClearPending()
        HidePrompt()
        SyncEvents()
    end
end
_G._CUI_ApplyTeleportPrompt = ApplyTeleportPrompt

ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, evt, arg1, arg2)
    if evt == "PLAYER_LOGIN" then
        -- Login is always out of combat: safe to create the secure button now.
        if IsEnabled() then
            BuildPopup()
            SyncEvents()
            SeedShownFromListing()
        end
        return
    elseif evt == "PLAYER_REGEN_ENABLED" then
        -- Finish a mid-combat enable: safe to build the secure button now.
        if pendingBuild then
            pendingBuild = nil
            if IsEnabled() then
                BuildPopup()
            end
        end
        -- Flush a secure attribute write that was blocked during combat.
        if pendingAttrSpellID and secureBtn then
            secureBtn:SetAttribute("spell", pendingAttrSpellID)
            pendingAttrSpellID = nil
        end
        -- Surface a prompt whose accept landed mid-combat.
        if pendingShow and pendingSpellID and IsEnabled() then
            pendingShow = nil
            UpdateButtonVisuals()
            if dialog then
                dialog:Show()
            end
        end
        -- Flush a hide that was blocked during combat (protected popup:Hide()).
        if pendingHide then
            pendingHide = nil
            if dialog and dialog:IsShown() then
                dialog:Hide()
            end
        end
        -- Drop any event that only stayed registered for the flushes above.
        SyncEvents()
        return
    elseif evt == "PLAYER_REGEN_DISABLED" then
        HidePrompt() -- combat-start guard (teleports cannot be cast in combat)
        return
    end

    -- Defense in depth: feature events unregister on disable, but bail if one
    -- lands mid-transition.
    if not IsEnabled() then
        ClearPending()
        HidePrompt()
        return
    end

    if evt == "LFG_LIST_JOINED_GROUP" then
        -- arg1 = searchResultID. This fires when an applicant accepts an invite.
        ClearPending()
        ResolveDungeon(arg1)
        if pendingSpellID then
            shownSpellID = pendingSpellID
            ShowPrompt()
        end
    elseif evt == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        -- Fires for the whole group on every create, edit and delist of the
        -- listing, so leaders get the prompt too. It surfaces only when the
        -- listing's dungeon is new for this group (never again for an edit or a
        -- closed prompt), and a delist hides nothing: the usual rules (dungeon
        -- entered, group left, combat) still hide it.
        local prevSpell, prevName, prevShow = pendingSpellID, pendingName, pendingShow
        ClearPending()
        ResolveActiveEntry()
        if pendingSpellID and pendingSpellID ~= shownSpellID then
            shownSpellID = pendingSpellID
            ShowPrompt()
        else
            pendingSpellID, pendingName, pendingShow = prevSpell, prevName, prevShow
        end
    elseif evt == "GROUP_ROSTER_UPDATE" then
        if not IsInGroup() then
            ClearPending()
            HidePrompt()
            shownSpellID = nil
        end
    elseif evt == "PLAYER_ENTERING_WORLD" or evt == "ZONE_CHANGED_NEW_AREA" then
        local inInstance, instanceType = IsInInstance()
        if inInstance and instanceType == "party" then
            ClearPending()
            HidePrompt()
            -- The dungeon you stand in counts as shown: re-listing it from inside
            -- (a replacement search) must not offer a teleport to it.
            local instName = GetInstanceInfo()
            shownSpellID = (
                type(instName) == "string"
                and not issecretvalue(instName)
                and CUI
                and CUI.ResolveTeleportSpellByName
                and CUI.ResolveTeleportSpellByName(instName)
            ) or nil
        end
    end
end)
