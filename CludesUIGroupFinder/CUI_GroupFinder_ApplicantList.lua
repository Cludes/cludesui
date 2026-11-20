if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ApplicantList.lua - our own applicant list
--  blizzard's list stays alive underneath, faded out. we only read the
--  applicants and draw them with more columns, nothing written to blizzard's
--  panel. secret values: we step aside. without leader rights it's the same
--  list under our own "group forming" cover, no buttons.
-------------------------------------------------------------------------------
local FOLDER, mod = ...
if CludesUI.HELD_BACK_ADDONS[FOLDER] then
    return
end -- held back (CludesUIGroupFinder.lua)
local CUI = CludesUI

local GAP, ROLE_GAP = 2, 4
local BOX_RIGHT = 29 -- blizzard's list stops this far from the panel's right edge
local HOME = LE_PARTY_CATEGORY_HOME
local ROLES = { "TANK", "HEALER", "DAMAGER" }
local ROLE_ATLAS = {
    TANK = "groupfinder-icon-role-micro-tank",
    HEALER = "groupfinder-icon-role-micro-heal",
    DAMAGER = "groupfinder-icon-role-micro-dps",
}
local BAD = CludesUI.COLOR_CODES.BAD

-- right to left from the buttons, the name takes what's left
local SPEC_COL = { key = "spec", title = CludesUI.L("Spec"), w = 26 }
local ROLE_COL = { key = "role", title = ROLE or "Role", w = 44 }
local ILVL_COL = { key = "ilvl", title = ITEM_LEVEL_ABBR or "iLvl", w = 34 }
local RATING_COL = { key = "rating", title = RATING or "Rating", w = 44 }
local KEY_COL = { key = "best", title = CludesUI.L("Key"), w = 36 }
local COLS_BASE = { SPEC_COL, ROLE_COL, ILVL_COL }
local COLS_KEYS = { SPEC_COL, ROLE_COL, ILVL_COL, RATING_COL, KEY_COL }
local COLS_PVP = { SPEC_COL, ROLE_COL, ILVL_COL, RATING_COL }

local Secret = CludesUI.IsSecret
local function Readable(t)
    return type(t) == "table" and not Secret(t) and not (canaccesstable and not canaccesstable(t))
end

local AV, widget, headerRow, body, thumb, empty, coverFrame, raidRoles
local VisibleCols
local isActive, guard = false, false
local blocks, entries = {}, {}
local cols, baseCols = COLS_BASE, COLS_BASE
local activity
local empowered = false
local rowHeight, btnSize, buttonSpace, iconSize = 36, 20, 50, 21
local layoutKey
local scrollPx = 0

-- the applicant list runs whenever the module does
function mod.ApplicantListOn()
    return mod.Enabled()
end

-- where the rows read their applicants from: the game, or the settings
-- preview's samples while it paints (then put straight back)
local LIVE = {
    info = function(ident)
        return C_LFGList.GetApplicantInfo(ident)
    end,
    member = function(ident, k)
        return C_LFGList.GetApplicantMemberInfo(ident, k)
    end,
    best = function(ident, k)
        return C_LFGList.GetApplicantBestDungeonScore(ident, k)
    end,
    counts = function()
        return GetGroupMemberCountsForDisplay()
    end,
}
local source = LIVE

-------------------------------------------------------------------------------
--  reading
-------------------------------------------------------------------------------
-- +12, red when it wasn't timed
local function KeyText(s)
    if not Readable(s) then
        return "-"
    end
    local lvl, done = s.bestRunLevel, s.finishedSuccess
    if Secret(lvl) or Secret(done) or type(lvl) ~= "number" or lvl == 0 then
        return "-"
    end
    return (done and "" or BAD) .. "+" .. lvl .. (done and "" or "|r")
end

local function ActiveActivity()
    local record = C_LFGList.GetActiveEntryInfo()
    local acts = Readable(record) and record.activityIDs
    local act = Readable(acts) and acts[1]
    if not act or Secret(act) then
        return nil
    end
    return act, C_LFGList.GetActivityInfoTable(act)
end

-- any applicant value hidden from us? hand back to blizzard's list.
-- status and member count never go secret, the rest can
local function AnySecret()
    local apps = C_LFGList.GetApplicants()
    if not apps then
        return false
    end
    if not Readable(apps) then
        return true
    end
    for _, ident in ipairs(apps) do
        if Secret(ident) then
            return true
        end
        local details = C_LFGList.GetApplicantInfo(ident)
        if details then
            if not Readable(details) then
                return true
            end
            for k = 1, details.numMembers or 0 do
                local label, classFile, _, _, ilvl, _, tank, healer, damage, role, _, score, pvpIlvl, _, _, specID =
                    C_LFGList.GetApplicantMemberInfo(ident, k)
                if
                    Secret(label)
                    or Secret(classFile)
                    or Secret(ilvl)
                    or Secret(tank)
                    or Secret(healer)
                    or Secret(damage)
                    or Secret(role)
                    or Secret(score)
                    or Secret(pvpIlvl)
                    or Secret(specID)
                then
                    return true
                end
            end
        end
    end
    return false
end

-- these drop off the list
local DECLINED = { declined = true, declined_full = true, declined_delisted = true, invitedeclined = true }

-- blizzard's order: new ones at the bottom. a secret field keeps the order we got
local isNew, sequence = {}, {} -- by applicant, refilled by every collect
local function ByOrder(a, b)
    if isNew[a] ~= isNew[b] then
        return isNew[b]
    end
    if sequence[a] ~= sequence[b] then
        return sequence[a] < sequence[b]
    end
    return a < b
end
local function Collect()
    wipe(entries)
    wipe(isNew)
    wipe(sequence)
    local apps = C_LFGList.GetApplicants()
    if not Readable(apps) then
        return
    end
    local sortable = true
    for _, ident in ipairs(apps) do
        local details = C_LFGList.GetApplicantInfo(ident)
        if
            Readable(details)
            and not (DECLINED[details.applicationStatus] and not details.pendingApplicationStatus)
        then
            entries[#entries + 1] = ident
            if Secret(details.isNew) or Secret(details.displayOrderID) then
                sortable = false
            else
                isNew[ident] = details.isNew and true or false
                sequence[ident] = details.displayOrderID or 0
            end
        end
    end
    if not sortable then
        return
    end
    table.sort(entries, ByOrder)
end

-------------------------------------------------------------------------------
--  buttons
-------------------------------------------------------------------------------
local function DoInvite(ident)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    C_LFGList.InviteApplicant(ident)
end

local function Invite(self)
    local b = self:GetParent()
    local ident = b.applicantID
    if not ident or b.preview then
        return
    end
    -- going past 5 needs a raid: our own popup, blizzard's would carry our taint
    if
        not IsInRaid(HOME)
        and GetNumGroupMembers(HOME) + (b.numMembers or 1) + C_LFGList.GetNumInvitedApplicantMembers()
            > (MAX_PARTY_MEMBERS or 4) + 1
    then
        CUI:ShowConfirmPopup({
            title = INVITE or "Invite",
            message = LFG_LIST_CONVERT_TO_RAID_WARNING
                or "Inviting this player will convert your party to a raid.",
            confirmText = INVITE or "Invite",
            onConfirm = function()
                C_PartyInfo.ConfirmConvertToRaid()
                DoInvite(ident)
            end,
        })
        return
    end
    DoInvite(ident)
end

local function Decline(self)
    local b = self:GetParent()
    local ident = b.applicantID
    if not ident or b.preview then
        return
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if b.appStatus == "applied" or b.appStatus == "invited" then
        C_LFGList.DeclineApplicant(ident)
    else
        C_LFGList.RemoveApplicant(ident)
    end
end

-- icon lives on a child frame, the skin's restrip fades direct textures
local function SquareButton(hostFrame, atlas, onClick)
    local button = CreateFrame("Button", nil, hostFrame)
    button:SetMotionScriptsWhileDisabled(true)
    local skin = CUI._ModuleNS and CUI._ModuleNS.CludesUIBlizzardSkin
    local S = skin and skin.WSkin
    if S and S.Button then
        S.Button(button)
    else
        local backdrop = button:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        CUI.MakeBorder(button, 0.25, 0.25, 0.25, 1, CUI.PanelPP)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.1)
    end
    local holderFrame = CreateFrame("Frame", nil, button)
    holderFrame:SetAllPoints()
    holderFrame:SetFrameLevel(button:GetFrameLevel() + 2)
    button.icon = holderFrame:CreateTexture(nil, "OVERLAY")
    button.icon:SetAtlas(atlas)
    button.icon:SetPoint("CENTER")
    button:SetScript("OnClick", onClick)
    -- the row stays lit while the mouse is on its buttons
    button:SetScript("OnEnter", function(self)
        for _, l in ipairs(hostFrame.lines) do
            l:LockHighlight()
        end
        if self.tip then
            CUI.ShowWidgetTooltip(self, self.tip)
        end
    end)
    button:SetScript("OnLeave", function()
        for _, l in ipairs(hostFrame.lines) do
            l:UnlockHighlight()
        end
        CUI.HideWidgetTooltip()
    end)
    return button
end

local function SizeSquare(button)
    button:SetSize(btnSize, btnSize)
    local px = math.floor(btnSize * 0.42)
    button.icon:SetSize(px, px)
end

-------------------------------------------------------------------------------
--  right-click menu + tooltip
-------------------------------------------------------------------------------
-- a player link in chat: clicking it is blizzard's own whisper
local function WhisperLink(label)
    local full = CUI.BuildFullName(label) or label
    if not (full and DEFAULT_CHAT_FRAME) then
        return
    end
    local itemLink = "|Hplayer:" .. full .. "|h[" .. full .. "]|h"
    DEFAULT_CHAT_FRAME:AddMessage(CludesUI.Lf("Click to whisper the applicant: %1$s", itemLink), 1, 0.82, 0)
end

local function LineMenu(rowLine)
    local ident = rowLine:GetParent().applicantID
    if not ident or rowLine:GetParent().preview then
        return
    end
    local label = C_LFGList.GetApplicantMemberInfo(ident, rowLine.memberIdx)
    if Secret(label) then
        label = nil
    end
    -- both of these print the name in chat
    local hidden = mod.OwnListGet("streamerNames")
    -- names shown: blizzard's tagged menu, so other add-ons' entries (raider.io's
    -- copy link and so on) still show. names hidden: ours, they'd show the name
    if not hidden then
        MenuUtil.CreateContextMenu(rowLine, function(_, root)
            root:SetTag("MENU_LFG_FRAME_MEMBER_APPLY")
            root:CreateTitle(label or "")
            local wid = root:CreateButton(WHISPER or "Whisper", function()
                WhisperLink(label)
            end)
            root:CreateButton(LFG_LIST_REPORT_PLAYER or "Report Player", function()
                LFGList_ReportApplicant(ident, label or "")
            end)
            local ig = root:CreateButton(IGNORE_PLAYER or "Ignore Player", function()
                C_FriendList.AddIgnore(label)
                C_LFGList.DeclineApplicant(ident)
            end)
            if not label then
                wid:SetEnabled(false)
                ig:SetEnabled(false)
            end
        end)
        return
    end
    CUI.ShowContextMenu(rowLine, {
        {
            text = WHISPER or "Whisper",
            noLoc = true,
            isDisabled = function()
                return hidden or not label
            end,
            onClick = function()
                WhisperLink(label)
            end,
        },
        {
            text = LFG_LIST_REPORT_PLAYER or "Report Player",
            noLoc = true,
            onClick = function()
                LFGList_ReportApplicant(ident, label or "")
            end,
        },
        {
            text = IGNORE_PLAYER or "Ignore Player",
            noLoc = true,
            isDisabled = function()
                return hidden or not label
            end,
            onClick = function()
                C_FriendList.AddIgnore(label)
                C_LFGList.DeclineApplicant(ident)
            end,
        },
    })
end

-- blizzard's would show what's hidden, this one only has what's still allowed
local function PrivateTooltip(rowLine, ident)
    local k = rowLine.memberIdx
    local label, classFile, localClass, _, ilvl, _, _, _, _, _, _, score, pvpIlvl, _, _, specID =
        C_LFGList.GetApplicantMemberInfo(ident, k)
    local classColor = classFile and RAID_CLASS_COLORS[classFile]
    local red, green, blue = 1, 1, 1
    if classColor then
        red, green, blue = classColor.r, classColor.g, classColor.b
    end
    GameTooltip:SetOwner(rowLine, "ANCHOR_NONE")
    GameTooltip:SetPoint("BOTTOMLEFT", rowLine, "TOPLEFT", 105, 0)
    local isShown = mod.OwnListGet("streamerNames") and localClass or label
    GameTooltip:SetText(isShown or " ", red, green, blue)
    if not mod.OwnListGet("streamerSpec") and type(specID) == "number" and specID > 0 then
        local specName = select(2, GetSpecializationInfoByID(specID))
        if specName then
            GameTooltip:AddLine(specName, 1, 1, 1)
        end
    end
    local gear = activity and activity.isPvpActivity and pvpIlvl or ilvl
    if type(gear) == "number" then
        GameTooltip:AddDoubleLine(ITEM_LEVEL_ABBR or "iLvl", math.floor(gear), 1, 0.82, 0, 1, 1, 1)
    end
    if not mod.OwnListGet("streamerRating") and baseCols == COLS_KEYS and type(score) == "number" then
        GameTooltip:AddDoubleLine(RATING or "Rating", score, 1, 0.82, 0, 1, 1, 1)
    end
    local details = C_LFGList.GetApplicantInfo(ident)
    local comment = Readable(details) and details.comment
    if
        not mod.OwnListGet("streamerNote")
        and type(comment) == "string"
        and not Secret(comment)
        and comment ~= ""
    then
        GameTooltip:AddLine(" ")
        local fc = LFG_LIST_COMMENT_FONT_COLOR
        GameTooltip:AddLine(
            string.format(LFG_LIST_COMMENT_FORMAT or "%s", comment),
            fc and fc.r or 0.6,
            fc and fc.g or 0.6,
            fc and fc.b or 0.6,
            true
        )
    end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  raider.io: its lines on the hover tooltip, and its full profile next to the
--  window while shift is held (its own side panel only follows blizzard's
--  rows). public api only, nothing happens without raider.io
-------------------------------------------------------------------------------
local rioApi, rioTip, rioWatch, rioLine
local function Rio()
    if rioApi == nil then
        rioApi = _G.RaiderIO or false
    end
    return rioApi and type(rioApi.ShowProfile) == "function" and rioApi or nil
end

-- the hovered applicant's name and realm, nil when hidden or unreadable
local function RioWho(rowLine)
    if mod.OwnListGet("streamerNames") or mod.OwnListGet("streamerRating") then
        return
    end
    local ident = rowLine:GetParent().applicantID
    if not ident or Secret(ident) then
        return
    end
    local full, classFile = C_LFGList.GetApplicantMemberInfo(ident, rowLine.memberIdx)
    if type(full) ~= "string" or Secret(full) or full == "" then
        return
    end
    local label, realm = strsplit("-", full, 2)
    return label, realm or GetNormalizedRealmName(), not Secret(classFile) and classFile or nil
end

local function RioLines(rowLine)
    local api = Rio()
    local label, realm = RioWho(rowLine)
    if not (api and label and GameTooltip:IsOwned(rowLine)) then
        return
    end
    local success, altered = pcall(api.ShowProfile, GameTooltip, label, realm)
    if success and altered then
        GameTooltip:Show()
    end
end

local function RioPanel()
    local api, label, realm, classFile = Rio(), nil, nil, nil
    if rioLine and rioLine:IsVisible() and IsShiftKeyDown() then
        label, realm, classFile = RioWho(rioLine)
    end
    if not (api and label) then
        if rioTip then
            rioTip:Hide()
        end
        return
    end
    rioTip = rioTip
        or CreateFrame("GameTooltip", "CludesUIGroupFinderRioTip", UIParent, "SharedTooltipTemplate")
    local anchor = PVEFrame or AV
    rioTip:SetOwner(anchor, "ANCHOR_NONE")
    rioTip:ClearAllPoints()
    rioTip:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    local classColor = classFile and CUI.GetClassColor(classFile)
    rioTip:SetText(label, classColor and classColor.r or 1, classColor and classColor.g or 1, classColor and classColor.b or 1)
    local success, altered = pcall(api.ShowProfile, rioTip, label, realm)
    if success and altered then
        rioTip:Show()
    else
        rioTip:Hide()
    end
end

-- shift is only watched while an applicant is hovered
local function RioEnter(rowLine)
    if not Rio() then
        return
    end
    rioLine = rowLine
    if not rioWatch then
        rioWatch = CreateFrame("Frame")
        rioWatch:SetScript("OnEvent", RioPanel)
    end
    rioWatch:RegisterEvent("MODIFIER_STATE_CHANGED")
    RioPanel()
end

local function RioLeave()
    rioLine = nil
    if rioWatch then
        rioWatch:UnregisterEvent("MODIFIER_STATE_CHANGED")
    end
    if rioTip then
        rioTip:Hide()
    end
end

local PvTip -- the settings preview's tooltip (below)

-- blizzard's own applicant tooltip unless something's hidden
local function LineEnter(rowLine)
    if rowLine:GetParent().preview then
        return PvTip(rowLine)
    end
    local ident = rowLine:GetParent().applicantID
    -- values can go secret between repaints, the next one hands over to blizzard's list
    if not (ident and LFGListApplicantMember_OnEnter) or AnySecret() then
        return
    end
    if
        mod.OwnListGet("streamerNote")
        or mod.OwnListGet("streamerNames")
        or mod.OwnListGet("streamerRating")
        or mod.OwnListGet("streamerSpec")
    then
        PrivateTooltip(rowLine, ident)
    else
        pcall(LFGListApplicantMember_OnEnter, rowLine)
    end
    RioLines(rowLine)
    RioEnter(rowLine)
end

local function LineLeave()
    GameTooltip_Hide()
    RioLeave()
end

-------------------------------------------------------------------------------
--  an applicant
-------------------------------------------------------------------------------
local function MakeLine(b, k)
    local l = CreateFrame("Button", nil, b)
    l:RegisterForClicks("RightButtonUp")
    l.memberIdx = k
    l.hl = l:CreateTexture(nil, "HIGHLIGHT")
    l.hl:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
    l.hl:SetColorTexture(1, 1, 1, 0.06)
    l.leaver = l:CreateTexture(nil, "ARTWORK")
    l.leaver:SetAtlas("groupfinder-icon-leaver")
    l.leaver:SetSize(12, 12)
    l.friend = l:CreateTexture(nil, "ARTWORK")
    l.friend:SetAtlas("groupfinder-icon-friend")
    l.friend:SetSize(14, 14)
    l.name = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l.name:SetJustifyH("LEFT")
    l.name:SetWordWrap(false)
    l.bullet = l:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l.bullet:SetText("\226\128\162")
    l.bullet:SetTextColor(0.6, 0.6, 0.6)
    l.region = l:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l.region:SetPoint("TOPLEFT", l.name, "BOTTOMLEFT", 0, -2)
    l.regionFlag = l:CreateTexture(nil, "ARTWORK")
    l.regionFlag:SetPoint("LEFT", l.region, "RIGHT", 4, 0)
    l.cells = {}
    for _, key in ipairs({ "ilvl", "rating", "best" }) do
        local fontStr = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fontStr:SetJustifyH("CENTER")
        fontStr:SetWordWrap(false)
        l.cells[key] = fontStr
    end
    -- spec icon, same looks as the results list's
    l.spec = l:CreateTexture(nil, "ARTWORK", nil, 2)
    l.specRing = l:CreateTexture(nil, "ARTWORK", nil, 1)
    l.specRing:Hide()
    local ringMask = l:CreateMaskTexture()
    ringMask:SetTexture(
        "Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE"
    )
    ringMask:SetAllPoints(l.specRing)
    l.specRing:AddMaskTexture(ringMask)
    l.specMask = l:CreateMaskTexture()
    l.specMask:SetTexture(
        "Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE"
    )
    l.specMask:SetAllPoints(l.spec)
    l.specBorder = CreateFrame("Frame", nil, l)
    l.specBorder:SetAllPoints(l.spec)
    l.specBorder:EnableMouse(false)
    l.specBorder:Hide()
    -- own role buttons, the leader can switch an applicant's role
    l.roles = {}
    for index = 1, 3 do
        local roleBtn = CreateFrame("Button", nil, l)
        roleBtn.tex = roleBtn:CreateTexture(nil, "ARTWORK")
        roleBtn.tex:SetPoint("CENTER")
        -- colored tile behind it, border like the spec icon's
        roleBtn.bg = roleBtn:CreateTexture(nil, "BACKGROUND")
        roleBtn.bg:SetAllPoints()
        roleBtn.bg:Hide()
        roleBtn.ring = roleBtn:CreateTexture(nil, "BACKGROUND", nil, -1)
        local ringMask = roleBtn:CreateMaskTexture()
        ringMask:SetTexture(
            "Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        ringMask:SetAllPoints(roleBtn.ring)
        roleBtn.ring:AddMaskTexture(ringMask)
        roleBtn.ring:Hide()
        roleBtn.border = CreateFrame("Frame", nil, roleBtn)
        roleBtn.border:SetAllPoints()
        roleBtn.border:EnableMouse(false)
        roleBtn.border:Hide()
        roleBtn.mask = roleBtn:CreateMaskTexture()
        roleBtn.mask:SetTexture(
            "Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        roleBtn.mask:SetAllPoints(roleBtn.bg)
        roleBtn:SetMotionScriptsWhileDisabled(true)
        roleBtn:SetScript("OnClick", function(self)
            local hostFrame = self:GetParent()
            local ident = hostFrame:GetParent().applicantID
            if ident and self.role and not hostFrame:GetParent().preview then
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                C_LFGList.SetApplicantMemberRole(ident, hostFrame.memberIdx, self.role)
            end
        end)
        roleBtn:SetScript("OnEnter", function(self)
            local rowLine = self:GetParent()
            rowLine:LockHighlight()
            LineEnter(rowLine)
        end)
        roleBtn:SetScript("OnLeave", function(self)
            self:GetParent():UnlockHighlight()
            GameTooltip_Hide()
        end)
        l.roles[index] = roleBtn
    end
    l:SetScript("OnClick", LineMenu)
    l:SetScript("OnEnter", LineEnter)
    l:SetScript("OnLeave", LineLeave)
    b.lines[k] = l
    return l
end

local function MakeBlock(index, hostFrame, storage)
    local b = CreateFrame("Frame", nil, hostFrame or body)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 1, 1, 0.03)
    -- status underline
    b.under = b:CreateTexture(nil, "ARTWORK", nil, 7)
    b.under:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.under:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.under:SetHeight(2)
    b.under:Hide()
    b.lines = {}
    b.note = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.note:SetJustifyH("LEFT")
    b.note:SetWordWrap(true)
    -- the note's part of the row: same highlight, tooltip and menu
    b.noteHit = CreateFrame("Button", nil, b)
    b.noteHit:SetAllPoints(b.note)
    b.noteHit:RegisterForClicks("RightButtonUp")
    b.noteHit:SetScript("OnClick", function()
        LineMenu(b.lines[1])
    end)
    b.noteHit:SetScript("OnEnter", function()
        for _, l in ipairs(b.lines) do
            l:LockHighlight()
        end
        LineEnter(b.lines[1])
    end)
    b.noteHit:SetScript("OnLeave", function()
        for _, l in ipairs(b.lines) do
            l:UnlockHighlight()
        end
        GameTooltip_Hide()
    end)
    b.decline = SquareButton(b, "groupfinder-icon-redx", Decline)
    b.invite = SquareButton(b, "groupfinder-icon-greencheckmark", Invite)
    b.invite:SetPoint("RIGHT", b.decline, "LEFT", -GAP, 0)
    b.decline.tip = DECLINE or "Decline"
    b.status = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.status:SetJustifyH("RIGHT")
    local into = storage or blocks
    into[index] = b
    return b
end

-- text, color, the results list's underline setting
local STATUS = {
    invited = { LFG_LIST_APP_INVITED or "Invited", 0.1, 0.9, 0.1, "lineAccepted" },
    inviteaccepted = { LFG_LIST_APP_INVITE_ACCEPTED or "Invite Accepted", 0.1, 0.9, 0.1, "lineAccepted" },
    invitedeclined = { LFG_LIST_APP_INVITE_DECLINED or "Invite Declined", 1, 0.2, 0.2, "lineDeclined" },
    failed = { LFG_LIST_APP_CANCELLED or "Cancelled", 1, 0.55, 0.1, "lineCancelled" },
    cancelled = { LFG_LIST_APP_CANCELLED or "Cancelled", 1, 0.55, 0.1, "lineCancelled" },
    declined = { LFG_LIST_APP_DECLINED or "Declined", 1, 0.2, 0.2, "lineDeclined" },
    declined_full = { LFG_LIST_APP_DECLINED or "Declined", 1, 0.2, 0.2, "lineDeclined" },
    declined_delisted = { LFG_LIST_APP_DECLINED or "Declined", 0.6, 0.6, 0.6, "lineDelisted" },
    timedout = { LFG_LIST_APP_TIMED_OUT or "Timed Out", 1, 0.2, 0.2, "lineDeclined" },
}
local GONE = {
    failed = true,
    cancelled = true,
    declined = true,
    declined_full = true,
    declined_delisted = true,
    invitedeclined = true,
    timedout = true,
    inviteaccepted = true,
}

-- same place the header puts each column
local function PlaceCells(l)
    local posX = 0
    -- only the columns in play show, streamer mode can drop some
    for _, fontStr in pairs(l.cells) do
        fontStr:Hide()
    end
    for c = #cols, 1, -1 do
        local colour = cols[c]
        posX = posX - colour.w
        local fontStr = l.cells[colour.key]
        if fontStr then
            fontStr:Show()
            fontStr:ClearAllPoints()
            fontStr:SetPoint("LEFT", l, "RIGHT", posX, 0)
            fontStr:SetWidth(colour.w)
        elseif colour == ROLE_COL then
            l.roleX = posX
        elseif colour == SPEC_COL then
            l.specX = posX
        end
    end
    l.name:ClearAllPoints()
    l.nameRight = posX
end

local function FontSize(fontStr, size)
    local success, filePath, _, flags = pcall(fontStr.GetFont, fontStr)
    if success and filePath then
        fontStr:SetFont(filePath, size, flags or "")
    end
end

-- icon when we know the spec, else the class like the results list
local function PaintSpec(l, classFile, specID, grey)
    local t, ring, bf = l.spec, l.specRing, l.specBorder
    ring:Hide()
    bf:Hide()
    if l.specMasked then
        t:RemoveMaskTexture(l.specMask)
        l.specMasked = nil
    end
    if grey or mod.OwnListGet("streamerSpec") then
        t:Hide()
        return
    end
    t:SetSize(iconSize, iconSize)
    t:ClearAllPoints()
    t:SetPoint("CENTER", l, "RIGHT", l.specX + SPEC_COL.w / 2, 0)
    t:SetTexCoord(0, 1, 0, 1)
    local square = mod.OwnListGet("iconShape") == "square"
    local iconTex = type(specID) == "number" and specID > 0 and select(4, GetSpecializationInfoByID(specID))
    if iconTex then
        t:SetTexture(iconTex)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif square then
        local classColor = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
        if classColor then
            t:SetColorTexture(classColor.r * 0.75, classColor.g * 0.75, classColor.b * 0.75, 1)
        else
            t:SetColorTexture(0.3, 0.3, 0.3, 1)
        end
    elseif classFile then
        t:SetAtlas("groupfinder-icon-class-color-" .. classFile)
    else
        t:SetColorTexture(0.3, 0.3, 0.3, 1)
    end
    local buttonPx = tonumber(mod.OwnListGet("borderSize")) or 0
    local br, backdrop, bb = mod.OwnListBorderColor()
    if square then
        if buttonPx > 0 and CUI.ApplyBorderStyle then
            local btex = mod.OwnListGet("borderTexture") or "solid"
            local bkey = btex .. ":" .. buttonPx .. ":" .. br .. ":" .. backdrop .. ":" .. bb
            if bf._key ~= bkey then
                bf._key = bkey
                CUI.ApplyBorderStyle(bf, buttonPx, br, backdrop, bb, 1, btex)
            end
            bf:Show()
        end
    elseif iconTex then
        t:AddMaskTexture(l.specMask)
        l.specMasked = true
        if buttonPx > 0 then
            ring:ClearAllPoints()
            ring:SetPoint("TOPLEFT", t, "TOPLEFT", -buttonPx, buttonPx)
            ring:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", buttonPx, -buttonPx)
            ring:SetColorTexture(br, backdrop, bb, 1)
            ring:Show()
        end
    end
    t:Show()
end

-- the results list's colored role tile
local function PaintRole(roleBtn, role, classFile)
    roleBtn.bg:Show()
    -- the applicant's class color when asked, else the role's
    if classFile and not Secret(classFile) and mod.OwnListGet("roleClassColors") then
        local classColor = CUI.GetClassColor(classFile)
        roleBtn.bg:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
    else
        local c = mod.RaidRoleColors[role]
        roleBtn.bg:SetColorTexture(c[1], c[2], c[3], 1)
    end
    local round = mod.OwnListGet("iconShape") ~= "square"
    if round and not roleBtn.masked then
        roleBtn.bg:AddMaskTexture(roleBtn.mask)
        roleBtn.masked = true
    elseif not round and roleBtn.masked then
        roleBtn.bg:RemoveMaskTexture(roleBtn.mask)
        roleBtn.masked = nil
    end
    local texture = mod.OwnListGet("missingIcons") == "cludes" and mod.RoleIconTex and mod.RoleIconTex(role)
    if texture then
        roleBtn.tex:SetTexture(texture)
    else
        roleBtn.tex:SetAtlas(ROLE_ATLAS[role])
    end
    local gsz = math.floor(iconSize * 0.7 + 0.5)
    roleBtn.tex:SetSize(gsz, gsz)
    local buttonPx = tonumber(mod.OwnListGet("borderSize")) or 0
    local br, backdrop, bb = mod.OwnListBorderColor()
    roleBtn.ring:Hide()
    roleBtn.border:Hide()
    if buttonPx <= 0 then
        return
    end
    if round then
        roleBtn.ring:ClearAllPoints()
        roleBtn.ring:SetPoint("TOPLEFT", roleBtn.bg, "TOPLEFT", -buttonPx, buttonPx)
        roleBtn.ring:SetPoint("BOTTOMRIGHT", roleBtn.bg, "BOTTOMRIGHT", buttonPx, -buttonPx)
        roleBtn.ring:SetColorTexture(br, backdrop, bb, 1)
        roleBtn.ring:Show()
    elseif CUI.ApplyBorderStyle then
        local btex = mod.OwnListGet("borderTexture") or "solid"
        local bkey = btex .. ":" .. buttonPx .. ":" .. br .. ":" .. backdrop .. ":" .. bb
        if roleBtn.border._key ~= bkey then
            roleBtn.border._key = bkey
            CUI.ApplyBorderStyle(roleBtn.border, buttonPx, br, backdrop, bb, 1, btex)
        end
        roleBtn.border:Show()
    end
end

-- a mark before the name, after the one placed before it (l.markPrev)
local function After(l, texture, isShown, posX)
    texture:SetShown(isShown)
    if not isShown then
        return
    end
    local anchor = l.markPrev
    texture:ClearAllPoints()
    texture:SetPoint("LEFT", anchor, anchor == l and "LEFT" or "RIGHT", anchor == l and posX or 1, 0)
    l.markPrev = texture
end

local function FillLine(l, ident, k, grey, noTouch)
    local label, classFile, localClass, _, ilvl, _, tank, healer, damage, assigned, relation, score, pvpIlvl, _, _, specID, leaver =
        source.member(ident, k)
    PlaceCells(l)
    PaintSpec(l, classFile, specID, grey)
    -- the applicant's name: a font family (ns.OwnListNameFont), never FontSize
    mod.OwnListNameFont(l.name, mod.OwnListSize("titleSize"))
    for _, fontStr in pairs(l.cells) do
        FontSize(fontStr, mod.OwnListSize("scoreSize"))
    end
    -- leaver, friend, name
    local posX = k > 1 and 18 or 6
    l.markPrev = l
    After(l, l.leaver, not Secret(leaver) and leaver, posX)
    After(l, l.friend, not Secret(relation) and relation, posX)
    local anchor = l.markPrev
    -- region under the name when the row has the height for it
    local tag, tr, tg, tb, flag
    if not grey and mod.RegionTagOfName then
        tag, tr, tg, tb, flag = mod.RegionTagOfName(label)
    end
    local lineSize = mod.OwnListSize("lineSize")
    if tag and rowHeight < mod.OwnListSize("titleSize") + lineSize + 6 then
        tag = nil
    end
    local nameY = tag and math.ceil((lineSize + 2) / 2) or 0
    l.name:SetPoint("LEFT", anchor, anchor == l and "LEFT" or "RIGHT", anchor == l and posX or 2, nameY)
    l.name:SetPoint("RIGHT", l, "RIGHT", l.nameRight - 2, nameY)
    if mod.OwnListGet("streamerNames") then
        l.name:SetText(localClass or "")
    else
        l.name:SetText(label and Ambiguate(label, "short") or "")
    end
    -- a group's other members hang off the leader's row
    l.bullet:SetShown(k > 1 and not grey)
    l.bullet:ClearAllPoints()
    l.bullet:SetPoint("LEFT", l, "LEFT", 9, nameY)
    l.region:SetShown(tag ~= nil)
    l.regionFlag:SetShown(tag ~= nil and flag ~= nil)
    if tag then
        FontSize(l.region, lineSize)
        l.region:SetText(tag)
        l.region:SetTextColor(tr, tg, tb, 1)
        if flag then
            local fh = math.max(8, lineSize)
            l.regionFlag:SetSize(math.floor(fh * 4 / 3 + 0.5), fh)
            l.regionFlag:SetTexture(flag)
        end
    end
    local classColor = classFile and RAID_CLASS_COLORS[classFile]
    if grey or not classColor then
        l.name:SetTextColor(0.6, 0.6, 0.6)
    else
        l.name:SetTextColor(classColor.r, classColor.g, classColor.b)
    end

    -- the roles they picked, the one they're down for lit up
    local picked = l.picked
    if not picked then
        picked = {}
        l.picked = picked
    end
    wipe(picked)
    if tank then
        picked[#picked + 1] = "TANK"
    end
    if healer then
        picked[#picked + 1] = "HEALER"
    end
    if damage then
        picked[#picked + 1] = "DAMAGER"
    end
    for index = 1, 3 do
        local roleBtn, role = l.roles[index], picked[index]
        roleBtn:SetShown(role ~= nil and not grey)
        roleBtn.role = role
        if role then
            PaintRole(roleBtn, role, classFile)
            roleBtn:SetAlpha(role == assigned and 1 or 0.3)
            roleBtn:SetEnabled(not noTouch and role ~= assigned)
            roleBtn:ClearAllPoints()
            -- centered under the column title
            roleBtn:SetSize(iconSize, iconSize)
            local step = iconSize + ROLE_GAP
            roleBtn:SetPoint(
                "LEFT",
                l,
                "RIGHT",
                l.roleX + (ROLE_COL.w - #picked * step + ROLE_GAP) / 2 + (index - 1) * step,
                0
            )
        end
    end

    local details = activity
    for _, fontStr in pairs(l.cells) do
        fontStr:SetText("")
        fontStr:SetTextColor(1, 1, 1)
    end
    if grey then
        return
    end
    local c = l.cells
    if details and details.isPvpActivity and type(pvpIlvl) == "number" then
        c.ilvl:SetText(math.floor(pvpIlvl))
    elseif type(ilvl) == "number" then
        c.ilvl:SetText(math.floor(ilvl))
    end
    if baseCols == COLS_KEYS then
        if type(score) == "number" then
            local red, green, blue = 1, 1, 1
            if mod.GFRatingColor then
                red, green, blue = mod.GFRatingColor(score)
            end
            c.rating:SetText(score)
            c.rating:SetTextColor(red, green, blue)
        else
            c.rating:SetText("-")
        end
        c.best:SetText(KeyText(source.best(ident, k)))
    elseif baseCols == COLS_PVP then
        local act = ActiveActivity()
        local pvp = act and C_LFGList.GetApplicantPvpRatingInfoForListing(ident, k, act)
        local rating = Readable(pvp) and pvp.rating
        c.rating:SetText((rating and not Secret(rating)) and rating or "-")
    end
end

local function FillBlock(b, ident, numAllowed, current, numInvited)
    local details = source.info(ident)
    if not Readable(details) then
        b.applicantID = nil
        b:Hide()
        return 0
    end
    local n = details.numMembers or 1
    local status, pending = details.applicationStatus, details.pendingApplicationStatus
    b.applicantID, b.numMembers, b.appStatus = ident, n, status
    local grey = not pending and GONE[status] or false
    for k = 1, n do
        local l = b.lines[k] or MakeLine(b, k)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -(k - 1) * rowHeight)
        l:SetPoint("TOPRIGHT", b, "TOPRIGHT", -buttonSpace, -(k - 1) * rowHeight)
        -- the highlight runs on under the buttons
        l.hl:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", buttonSpace, 0)
        l:SetHeight(rowHeight)
        FillLine(l, ident, k, grey, not empowered or status == "invited")
        l:Show()
    end
    for k = n + 1, #b.lines do
        b.lines[k]:Hide()
    end
    -- the applicant's note, the block only grows when there is one
    local comment, noteH = details.comment, 0
    local hasNote = not grey
        and not mod.OwnListGet("streamerNote")
        and type(comment) == "string"
        and not Secret(comment)
        and comment ~= ""
    b.note:SetShown(hasNote)
    b.noteHit:SetShown(hasNote)
    if hasNote then
        mod.OwnListNameFont(b.note, mod.OwnListSize("lineSize"))
        b.note:ClearAllPoints()
        b.note:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -n * rowHeight)
        b.note:SetWidth(math.max(40, (body:GetWidth() or 200) - buttonSpace - 8))
        b.note:SetText(string.format(LFG_LIST_COMMENT_FORMAT or "%s", comment))
        local fc = LFG_LIST_COMMENT_FONT_COLOR
        if fc then
            b.note:SetTextColor(fc.r, fc.g, fc.b)
        else
            b.note:SetTextColor(0.6, 0.6, 0.6)
        end
        noteH = math.ceil(b.note:GetStringHeight() or 12) + 6
    end
    local last = b.lines[n]
    if last then
        last.hl:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", buttonSpace, -noteH)
    end
    SizeSquare(b.invite)
    SizeSquare(b.decline)
    -- buttons and status stay on the top row, whatever hangs below it
    b.decline:ClearAllPoints()
    b.decline:SetPoint("RIGHT", b, "TOPRIGHT", -3, -rowHeight / 2)
    b.invite:SetShown(empowered and not pending and status == "applied")
    b.decline:SetShown(empowered and not pending and status ~= "invited")
    -- blizzard's fullness check
    local tipText
    if n + current > numAllowed then
        tipText = LFG_LIST_GROUP_TOO_FULL
    elseif n + current + numInvited > numAllowed then
        tipText = LFG_LIST_INVITED_APP_FILLS_GROUP
    end
    b.invite:SetEnabled(not tipText)
    b.invite.icon:SetDesaturated(tipText ~= nil)
    b.invite.tip = tipText or INVITE or "Invite"
    -- a status replaces the columns once they're out of play
    local state = STATUS[status]
    b.status:ClearAllPoints()
    if b.decline:IsShown() then
        b.status:SetPoint("RIGHT", b.decline, "LEFT", -6, 0)
    else
        b.status:SetPoint("RIGHT", b, "TOPRIGHT", -6, -rowHeight / 2)
    end
    b.status:SetShown(state ~= nil)
    if state then
        b.status:SetText(state[1])
        b.status:SetTextColor(state[2], state[3], state[4])
    end
    -- same underline and fade as a results row
    if state and mod.OwnListGet(state[5]) ~= false then
        b.under:SetColorTexture(state[2], state[3], state[4], 0.9)
        b.under:Show()
    else
        b.under:Hide()
    end
    b:SetAlpha(grey and 0.5 or 1)
    return rowHeight * n + noteH
end

-------------------------------------------------------------------------------
--  the list
-------------------------------------------------------------------------------
local function Position()
    if not isActive then
        return
    end
    local height = body:GetHeight() or 0
    local sum = 0
    for index = 1, #entries do
        sum = sum + blocks[index].h + GAP
    end
    sum = math.max(0, sum - GAP)
    local maxPx = math.max(0, sum - height)
    scrollPx = math.max(0, math.min(scrollPx, maxPx))
    local posY = -scrollPx
    for index = 1, #entries do
        local b = blocks[index]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -posY)
        b:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -posY)
        b:SetHeight(b.h)
        b:SetShown(b.applicantID ~= nil and posY + b.h > 0 and posY < height)
        posY = posY + b.h + GAP
    end
    if maxPx > 0 then
        local th = math.max(16, height * height / sum)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -1, -(height - th) * (scrollPx / maxPx))
        thumb:Show()
    else
        thumb:Hide()
    end
end

-- same left edge, right edge and scrollbar spot as the results list
local function LayoutFrame()
    local c = mod.Cfg and mod.Cfg()
    local pad = tonumber(c and c.padding) or 12
    local sp = LFGListFrame.SearchPanel
    local barW = sp and sp.ScrollBar and sp.ScrollBar:GetWidth() or 8
    -- rows stop short of the bottom buttons
    local boxB, avB = AV.ScrollBox:GetBottom(), AV:GetBottom()
    local bottomY = (boxB and avB)
            and math.max(0, (mod.BOTTOM_Y or 8) + (AV.EditButton:GetHeight() or 22) + 4 - (boxB - avB))
        or 0
    local key = pad .. ":" .. barW .. ":" .. buttonSpace .. ":" .. bottomY
    if key == layoutKey then
        return
    end
    layoutKey = key
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", AV.ScrollBox, "TOPLEFT", pad, 0)
    widget:SetPoint("BOTTOMRIGHT", AV.ScrollBox, "BOTTOMRIGHT", BOX_RIGHT - pad / 2 + barW / 2, bottomY)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", AV.ScrollBox, "BOTTOMRIGHT", BOX_RIGHT - pad, bottomY)
    headerRow:ClearAllPoints()
    headerRow:SetPoint("BOTTOMLEFT", body, "TOPLEFT", 0, 3)
    headerRow:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", -buttonSpace, 3)
end

-- the group's role counts at the top, drawn like a raid row in the results list
local function PaintRaidRoles()
    local wanted = activity
        and Enum.LFGListDisplayType
        and activity.displayType == Enum.LFGListDisplayType.RoleCount
    local payload = wanted and source.counts()
    wanted = wanted and Readable(payload)
    raidRoles:SetShown(wanted and true or false)
    if not wanted then
        return
    end
    local isz = mod.OwnListIconSize(mod.OwnListRowHeight())
    local round = mod.OwnListGet("iconShape") ~= "square"
    local ell = mod.OwnListGet("missingIcons") == "cludes"
    local fsz = mod.OwnListSize("scoreSize")
    local posX = 0
    for k = 3, 1, -1 do
        local p, role = raidRoles.parts[k], ROLES[k]
        local num = payload[role]
        if type(num) == "number" and not Secret(num) then
            local c = mod.RaidRoleColors[role]
            p.bg:SetColorTexture(c[1], c[2], c[3], 1)
            if round and not p.masked then
                p.bg:AddMaskTexture(p.mask)
                p.masked = true
            elseif not round and p.masked then
                p.bg:RemoveMaskTexture(p.mask)
                p.masked = nil
            end
            p.bg:SetSize(isz, isz)
            p.bg:ClearAllPoints()
            p.bg:SetPoint("RIGHT", raidRoles, "RIGHT", posX, 0)
            p.bg:Show()
            local texture = ell and mod.RoleIconTex and mod.RoleIconTex(role)
            if texture then
                p.icon:SetTexture(texture)
            else
                p.icon:SetAtlas(ROLE_ATLAS[role])
            end
            local gsz = math.floor(isz * 0.7 + 0.5)
            p.icon:SetSize(gsz, gsz)
            p.icon:Show()
            FontSize(p.count, fsz)
            p.count:SetText(num)
            p.count:Show()
            posX = posX - math.max(isz, math.ceil(p.count:GetStringWidth() or 8)) - 6
        else
            p.bg:Hide()
            p.icon:Hide()
            p.count:Hide()
        end
    end
end

-- a title's width, so narrow columns never cut it off
local ruler
local function TitleWidth(title)
    if not ruler then
        ruler = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ruler:SetAlpha(0)
    end
    ruler:SetText(title)
    return math.ceil(ruler:GetStringWidth() or 24) + 4
end

-- the most roles any applicant in the list picked
local function MostRoles(ids)
    local maxCount = 1
    for _, ident in ipairs(ids) do
        local details = source.info(ident)
        if
            Readable(details) and (details.pendingApplicationStatus or not GONE[details.applicationStatus])
        then
            for k = 1, details.numMembers or 1 do
                local _, _, _, _, _, _, tank, healer, damage = source.member(ident, k)
                maxCount = math.max(maxCount, (tank and 1 or 0) + (healer and 1 or 0) + (damage and 1 or 0))
            end
        end
    end
    return maxCount
end

local function PaintHeader()
    for _, fontStr in ipairs(headerRow.titles) do
        fontStr:Hide()
    end
    local posX, used = 0, 0
    for c = #cols, 1, -1 do
        local colour = cols[c]
        posX = posX - colour.w
        used = used + 1
        local fontStr = headerRow.titles[used]
        if not fontStr then
            fontStr = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fontStr:SetJustifyH("CENTER")
            fontStr:SetWordWrap(false)
            headerRow.titles[used] = fontStr
        end
        fontStr:ClearAllPoints()
        fontStr:SetPoint("LEFT", headerRow, "RIGHT", posX, 0)
        fontStr:SetWidth(colour.w)
        fontStr:SetText(colour.title)
        fontStr:Show()
    end
end

-- the listing's columns minus what streamer mode hides
local visibleCols = {}
VisibleCols = function(base, result)
    local noSpec, noRating = mod.OwnListGet("streamerSpec"), mod.OwnListGet("streamerRating")
    if not (noSpec or noRating) then
        return base
    end
    result = result or visibleCols
    wipe(result)
    for _, colour in ipairs(base) do
        if not ((noSpec and colour == SPEC_COL) or (noRating and colour == RATING_COL)) then
            result[#result + 1] = colour
        end
    end
    return result
end

local function Paint()
    if not isActive then
        return
    end
    empowered = LFGListUtil_IsEntryEmpowered() and true or false
    coverFrame:SetShown(not empowered)
    rowHeight = tonumber(mod.OwnListGet("applicantRowHeight")) or 36
    btnSize = math.max(18, math.min(rowHeight - 8, 24))
    buttonSpace = btnSize * 2 + GAP + 8
    iconSize = mod.OwnListIconSize(rowHeight)
    Collect()
    -- role is only as wide as the applicants need, the name takes the rest
    local maxCount = MostRoles(entries)
    SPEC_COL.w = math.max(TitleWidth(SPEC_COL.title), iconSize) + 6
    ROLE_COL.w = math.max(TitleWidth(ROLE_COL.title), iconSize * maxCount + ROLE_GAP * (maxCount - 1)) + 6
    LayoutFrame()
    local act, ai = ActiveActivity()
    activity = act and ai or nil
    if activity and activity.isMythicPlusActivity then
        baseCols = COLS_KEYS
    elseif activity and activity.isRatedPvpActivity then
        baseCols = COLS_PVP
    else
        baseCols = COLS_BASE
    end
    cols = VisibleCols(baseCols)
    PaintHeader()
    PaintRaidRoles()
    local numAllowed = activity and activity.maxNumPlayers or 0
    if numAllowed == 0 then
        numAllowed = MAX_RAID_MEMBERS or 40
    end
    local current = GetNumGroupMembers(HOME)
    local numInvited = C_LFGList.GetNumInvitedApplicantMembers()
    for index, ident in ipairs(entries) do
        local b = blocks[index] or MakeBlock(index)
        b.h = FillBlock(b, ident, numAllowed, current, numInvited)
    end
    for index = #entries + 1, #blocks do
        blocks[index].applicantID = nil
        blocks[index]:Hide()
    end
    empty:SetShown(#entries == 0)
    Position()
end

local function HoldHidden(frame, a)
    if guard or not isActive or a == 0 then
        return
    end
    guard = true
    frame:SetAlpha(0)
    guard = false
end

local function Faded()
    return {
        AV.ScrollBox,
        AV.ScrollBar,
        AV.NameColumnHeader,
        AV.RoleColumnHeader,
        AV.ItemLevelColumnHeader,
        AV.RatingColumnHeader,
        AV.UnempoweredCover,
        AV.DataDisplay and AV.DataDisplay.RoleCount,
    }
end

-- the raid role counts: a circle and a number per role
local function MakeRaidRoles(hostFrame)
    local rr = CreateFrame("Frame", nil, hostFrame)
    rr:SetSize(1, 1)
    rr.parts = {}
    for k = 1, 3 do
        local backdrop = rr:CreateTexture(nil, "ARTWORK", nil, 1)
        local mask = rr:CreateMaskTexture()
        mask:SetTexture(
            "Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        mask:SetAllPoints(backdrop)
        local iconTex = rr:CreateTexture(nil, "ARTWORK", nil, 3)
        iconTex:SetPoint("CENTER", backdrop)
        local count = rr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        count:SetJustifyH("CENTER")
        count:SetPoint("BOTTOM", backdrop, "TOP", 0, 1)
        rr.parts[k] = { bg = backdrop, mask = mask, icon = iconTex, count = count }
    end
    return rr
end

local function Build()
    widget = CreateFrame("Frame", nil, AV)
    widget:SetFrameLevel(AV.ScrollBox:GetFrameLevel() + 10)
    widget:EnableMouse(true)
    widget:EnableMouseWheel(true)
    local function Wheel(_, delta)
        scrollPx = scrollPx - delta * (rowHeight + GAP)
        Position()
    end
    widget:SetScript("OnMouseWheel", Wheel)
    -- blizzard's hidden rows get no clicks in the strip left of ours
    local shield = CreateFrame("Frame", nil, widget)
    shield:SetPoint("TOPLEFT", AV.ScrollBox, "TOPLEFT", 0, 0)
    shield:SetPoint("BOTTOMRIGHT", widget, "BOTTOMLEFT", 0, 0)
    shield:EnableMouse(true)
    shield:EnableMouseWheel(true)
    shield:SetScript("OnMouseWheel", Wheel)
    widget:SetScript("OnSizeChanged", Position)
    widget:Hide()
    body = CreateFrame("Frame", nil, widget)
    body:SetClipsChildren(true)
    empty = widget:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", widget, "TOP", 0, -20)
    empty:SetText(LFG_LIST_NO_APPLICANTS or "No applicants")
    thumb = widget:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(1, 1, 1, 0.3)
    -- blizzard's cover would sit under our rows, so ours goes on top of them
    coverFrame = CreateFrame("Frame", nil, widget)
    coverFrame:SetAllPoints(body)
    coverFrame:SetFrameLevel(widget:GetFrameLevel() + 20)
    coverFrame:EnableMouse(true)
    coverFrame:EnableMouseWheel(true)
    coverFrame:SetScript("OnMouseWheel", Wheel)
    local tint = coverFrame:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints()
    tint:SetColorTexture(0.035, 0.071, 0.118, 0.5)
    local forming = coverFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
    forming:SetPoint("CENTER", coverFrame, "CENTER", 0, 20)
    forming:SetText(LFG_LIST_GROUP_FORMING or "Your group is currently forming.")
    coverFrame:Hide()
    -- our column titles over blizzard's
    headerRow = CreateFrame("Frame", nil, AV)
    headerRow:SetHeight(24)
    headerRow:SetFrameLevel(AV.ScrollBox:GetFrameLevel() + 10)
    headerRow:EnableMouse(true)
    headerRow:Hide()
    headerRow.titles = {}
    local nameTitle = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameTitle:SetPoint("LEFT", headerRow, "LEFT", 6, 0)
    nameTitle:SetText(NAME or "Name")
    -- sits where blizzard's counts were, their tooltip still works underneath
    raidRoles = MakeRaidRoles(headerRow)
    raidRoles:SetPoint(
        "RIGHT",
        AV.DataDisplay and AV.DataDisplay.RoleCount or AV.DataDisplay or AV,
        "RIGHT",
        0,
        0
    )
    for _, frame in ipairs(Faded()) do
        hooksecurefunc(frame, "SetAlpha", HoldHidden)
    end
end

-- ours only with readable applicants
local function Wanted()
    return mod.ApplicantListOn() and AV:IsVisible() and not AnySecret()
end

local function SetActive(nowTime)
    if nowTime == isActive then
        return
    end
    if nowTime and not widget then
        Build()
    end
    isActive = nowTime
    if not widget then
        return
    end
    local a = isActive and 0 or 1
    guard = true
    for _, frame in ipairs(Faded()) do
        frame:SetAlpha(a)
    end
    guard = false
    widget:SetShown(isActive)
    headerRow:SetShown(isActive)
    if not isActive then
        GameTooltip_Hide()
        RioLeave()
    end
end

-- a black bar over blizzard's text, the mouse stops there so its tooltip can't show either
local censor = {}
local function CensorBar(key, fontStr, enabled, maxW, hgt)
    local barFrame = censor[key]
    if not barFrame then
        if not enabled then
            return
        end
        barFrame = CreateFrame("Frame", nil, AV)
        barFrame:SetFrameLevel(AV:GetFrameLevel() + 30)
        barFrame:EnableMouse(true)
        local texture = barFrame:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        texture:SetColorTexture(0, 0, 0, 1)
        censor[key] = barFrame
    end
    barFrame:SetShown(enabled and true or false)
    if not enabled then
        return
    end
    local wid = math.max(40, math.min(fontStr:GetStringWidth() or maxW, maxW))
    barFrame:ClearAllPoints()
    barFrame:SetPoint("LEFT", fontStr, "LEFT", -2, 0)
    barFrame:SetSize(wid + 4, hgt)
end

local function PaintCensor()
    local enabled = mod.ApplicantListOn()
    if AV.EntryName then
        CensorBar("title", AV.EntryName, enabled and mod.OwnListGet("streamerTitle"), 290, 20)
    end
    local desc = AV.DescriptionFrame
    if desc and desc.Text then
        CensorBar("dungeon", desc.Text, enabled and mod.OwnListGet("streamerDungeon"), 310, 16)
    end
end

-- events only while the list is on and the viewer's up
local watch, watching
local EVENTS = {
    "LFG_LIST_APPLICANT_LIST_UPDATED",
    "LFG_LIST_APPLICANT_UPDATED",
    "LFG_LIST_ACTIVE_ENTRY_UPDATE",
    "GROUP_ROSTER_UPDATE",
    "PARTY_LEADER_CHANGED",
    "PLAYER_ROLES_ASSIGNED",
    "PLAYER_REGEN_DISABLED",
    "ADDON_RESTRICTION_STATE_CHANGED",
}

local function SyncEvents()
    local wanted = (mod.ApplicantListOn() and watch:IsVisible()) and true or false
    if wanted == watching then
        return
    end
    watching = wanted
    if wanted then
        for _, event in ipairs(EVENTS) do
            watch:RegisterEvent(event)
        end
    else
        watch:UnregisterAllEvents()
    end
end

function mod.ApplicantListRefresh()
    if not AV then
        return
    end
    SyncEvents()
    PaintCensor()
    SetActive(Wanted() and true or false)
    Paint()
    if mod.LayoutViewer then
        mod.LayoutViewer()
    end
end

-- display settings repaint us too
local baseRefresh = mod.OwnListRefresh
mod.OwnListRefresh = function()
    baseRefresh()
    mod.ApplicantListRefresh()
end

-- applicant events gather here: one refresh on the next frame, from a frame
-- hidden again until the next event
local refresher
local function Queue()
    if not refresher then
        refresher = CreateFrame("Frame")
        refresher:Hide()
        refresher:SetScript("OnUpdate", function(self)
            self:Hide()
            mod.ApplicantListRefresh()
        end)
    end
    refresher:Show()
end

if mod.WhenGroupFinder then
    mod.WhenGroupFinder(function()
        AV = LFGListFrame and LFGListFrame.ApplicationViewer
        if not (AV and AV.ScrollBox and AV.Inset) then
            AV = nil
            return
        end
        -- a child of the viewer shows and hides with it, no hooks on blizzard's frame
        watch = CreateFrame("Frame", nil, AV)
        watch:SetScript("OnShow", function()
            SyncEvents()
            if watching then
                Queue()
            end
        end)
        watch:SetScript("OnHide", function()
            SyncEvents()
            SetActive(false)
        end)
        watch:SetScript("OnEvent", function(_, evt)
            -- combat can lift with no event of ours, look again once it's over
            if evt == "PLAYER_REGEN_DISABLED" then
                mod.CombatQueue.Defer("applicantList", Queue)
            end
            Queue()
        end)
        if watch:IsVisible() then
            watch:GetScript("OnShow")(watch)
        end
    end)
end

-------------------------------------------------------------------------------
--  settings preview: sample applicants drawn by the list's own rows, for a
--  key or a raid listing. the list's state is set aside while it paints
-------------------------------------------------------------------------------
local DT = Enum.LFGListDisplayType
local PV_ACT = {
    dungeon = { isMythicPlusActivity = true, maxNumPlayers = 5, displayType = DT and DT.RoleEnumerate },
    raid = { maxNumPlayers = 30, displayType = DT and DT.RoleCount },
}
-- members: class, spec, roles picked (T/H/D), the role they're down for,
-- item level over yours, rating, best key, timed, and a fixed name (the easter eggs)
local PV_APPS = {
    dungeon = {
        {
            note = CludesUI.L("Timed it last week, happy to lead"),
            members = { { "MONK", 268, "T", "TANK", 6, 3120, 12, true } },
        },
        {
            members = {
                { "WARRIOR", 72, "D", "DAMAGER", 3, 2890, 11, true, mod.PreviewBlockjob },
                { "PALADIN", 65, "H", "HEALER", 4, 2950, 11, true, mod.PreviewElle },
            },
        },
        { members = { { "MAGE", 63, "D", "DAMAGER", -2, 2610, 10, false } } },
        {
            status = "invited",
            members = { { "PRIEST", 257, "HD", "HEALER", 1, 2780, 11, true, mod.PreviewLuella } },
        },
        {
            note = CludesUI.L("Can tank or dps"),
            members = { { "DEMONHUNTER", 581, "TD", "TANK", 2, 3010, 12, false } },
        },
    },
    raid = {
        { members = { { "DRUID", 104, "T", "TANK", 3 } } },
        {
            note = CludesUI.L("Have the tier set, need the trinket"),
            members = { { "SHAMAN", 264, "HD", "HEALER", 1 } },
        },
        { members = { { "HUNTER", 254, "D", "DAMAGER", 4 }, { "ROGUE", 260, "D", "DAMAGER", 2 } } },
        { members = { { "PALADIN", 65, "H", "HEALER", 2, nil, nil, nil, mod.PreviewElle } } },
        { status = "invited", members = { { "EVOKER", 1467, "HD", "DAMAGER", 0 } } },
        { members = { { "DEATHKNIGHT", 250, "TD", "DAMAGER", 5 } } },
    },
}
local PV_COUNTS = { TANK = 2, HEALER = 4, DAMAGER = 11 }
local applicantView = { blocks = {}, scroll = 0, ids = {}, data = {} }

-- names: the suite's preview roster (CludesUI.PREVIEW_ROSTER), one of the
-- member's class first
local function PvNames(kind)
    local roster = mod.PreviewRoster or CludesUI.PREVIEW_ROSTER
    local used, start = {}, kind == "raid" and 7 or 0
    local function Take(cls)
        for pass = 1, 2 do
            for index = 0, #roster - 1 do
                local k = (start + index) % #roster + 1
                local e = roster[k]
                if not used[k] and (pass == 2 or e.class == cls) then
                    used[k] = true
                    return e.name
                end
            end
        end
        return "Applicant"
    end
    local base = select(2, GetAverageItemLevel()) or 0
    local ids, payload = applicantView.ids, applicantView.data
    wipe(ids)
    wipe(payload)
    for index, a in ipairs(PV_APPS[kind]) do
        local ident = kind .. index
        local m = {}
        for k, skinData in ipairs(a.members) do
            m[k] = {
                name = skinData[9] or Take(skinData[1]),
                class = skinData[1],
                spec = skinData[2],
                roles = skinData[3],
                assigned = skinData[4],
                ilvl = math.max(1, base + skinData[5]),
                score = skinData[6],
                best = skinData[7] and { bestRunLevel = skinData[7], finishedSuccess = skinData[8] },
            }
        end
        ids[#ids + 1] = ident
        payload[ident] = {
            info = {
                applicationStatus = a.status or "applied",
                numMembers = #m,
                isNew = false,
                displayOrderID = index,
                comment = a.note or "",
            },
            members = m,
        }
    end
end

local PREVIEW = {
    info = function(ident)
        return applicantView.data[ident] and applicantView.data[ident].info
    end,
    member = function(ident, k)
        local m = applicantView.data[ident] and applicantView.data[ident].members[k]
        if not m then
            return nil
        end
        local localClass = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[m.class] or m.class
        return m.name,
            m.class,
            localClass,
            80,
            m.ilvl,
            0,
            m.roles:find("T") ~= nil,
            m.roles:find("H") ~= nil,
            m.roles:find("D") ~= nil,
            m.assigned,
            nil,
            m.score,
            m.ilvl,
            nil,
            nil,
            m.spec,
            false
    end,
    best = function(ident, k)
        local m = applicantView.data[ident] and applicantView.data[ident].members[k]
        return m and m.best
    end,
    counts = function()
        return PV_COUNTS
    end,
}

-- what the settings allow: name or class, spec, item level, rating, the note
PvTip = function(rowLine)
    local ident = rowLine:GetParent().applicantID
    local label, classFile, localClass, _, ilvl, _, _, _, _, _, _, score, _, _, _, specID =
        PREVIEW.member(ident, rowLine.memberIdx)
    if not label then
        return
    end
    local classColor = CUI.GetClassColor(classFile)
    GameTooltip:SetOwner(rowLine, "ANCHOR_NONE")
    GameTooltip:SetPoint("BOTTOMLEFT", rowLine, "TOPLEFT", 105, 0)
    GameTooltip:SetText(mod.OwnListGet("streamerNames") and localClass or label, classColor.r, classColor.g, classColor.b)
    local specName = not mod.OwnListGet("streamerSpec") and select(2, GetSpecializationInfoByID(specID))
    GameTooltip:AddLine(specName and (specName .. " " .. localClass) or localClass, 1, 1, 1)
    GameTooltip:AddDoubleLine(ITEM_LEVEL_ABBR or "iLvl", math.floor(ilvl), 1, 0.82, 0, 1, 1, 1)
    if score and not mod.OwnListGet("streamerRating") then
        GameTooltip:AddDoubleLine(RATING or "Rating", score, 1, 0.82, 0, 1, 1, 1)
    end
    local comment = PREVIEW.info(ident).comment
    if comment ~= "" and rowLine.memberIdx == 1 and not mod.OwnListGet("streamerNote") then
        GameTooltip:AddLine(" ")
        local fc = LFG_LIST_COMMENT_FONT_COLOR
        GameTooltip:AddLine(
            string.format(LFG_LIST_COMMENT_FORMAT or "%s", comment),
            fc and fc.r or 0.6,
            fc and fc.g or 0.6,
            fc and fc.b or 0.6,
            true
        )
    end
    GameTooltip:Show()
end

local function PvPosition()
    local hgt = applicantView.body:GetHeight() or 0
    local sum = -GAP
    for index = 1, #applicantView.ids do
        sum = sum + applicantView.blocks[index].h + GAP
    end
    applicantView.maxScroll = math.max(0, sum - hgt)
    applicantView.scroll = math.max(0, math.min(applicantView.scroll, applicantView.maxScroll))
    local posY = -applicantView.scroll
    for index = 1, #applicantView.ids do
        local b = applicantView.blocks[index]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", applicantView.body, "TOPLEFT", 0, -posY)
        b:SetPoint("TOPRIGHT", applicantView.body, "TOPRIGHT", 0, -posY)
        b:SetHeight(b.h)
        b:SetShown(posY + b.h > 0 and posY < hgt)
        posY = posY + b.h + GAP
    end
    local th = applicantView.thumb
    if applicantView.maxScroll > 0 then
        local tH = math.max(12, hgt * hgt / sum)
        th:SetHeight(tH)
        th:ClearAllPoints()
        th:SetPoint("TOPRIGHT", applicantView.body, "TOPRIGHT", 0, -(hgt - tH) * (applicantView.scroll / applicantView.maxScroll))
        th:Show()
    else
        th:Hide()
    end
end

local function PvBuild(owner)
    local frame = CreateFrame("Frame", nil, owner)
    frame:SetAllPoints(owner)
    applicantView.frame = frame
    applicantView.head = CreateFrame("Frame", nil, frame)
    applicantView.head.titles = {}
    local nameTitle = applicantView.head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameTitle:SetPoint("LEFT", applicantView.head, "LEFT", 6, 0)
    nameTitle:SetText(NAME or "Name")
    applicantView.raidRoles = MakeRaidRoles(applicantView.head)
    applicantView.body = CreateFrame("Frame", nil, frame)
    applicantView.body:SetClipsChildren(true)
    applicantView.body:EnableMouseWheel(true)
    applicantView.body:SetScript("OnMouseWheel", function(_, delta)
        local was = applicantView.scroll
        local step = math.floor((rowHeight + GAP) * 0.3 + 0.5)
        applicantView.scroll = math.max(0, math.min(was - delta * step, applicantView.maxScroll or 0))
        if applicantView.scroll ~= was then
            PvPosition()
            GameTooltip_Hide()
        end
    end)
    applicantView.thumb = applicantView.body:CreateTexture(nil, "OVERLAY", nil, 7)
    applicantView.thumb:SetWidth(2)
    applicantView.thumb:SetColorTexture(1, 1, 1, 0.25)
end

-- the list's own state, kept while the preview paints
local keptSet = {}
local function Keep()
    keptSet[1], keptSet[2], keptSet[3], keptSet[4] = source, headerRow, body, raidRoles
    keptSet[5], keptSet[6], keptSet[7], keptSet[8] = rowHeight, btnSize, buttonSpace, iconSize
    keptSet[9], keptSet[10], keptSet[11], keptSet[12] = activity, baseCols, cols, empowered
    keptSet[13], keptSet[14] = SPEC_COL.w, ROLE_COL.w
end
local function PutBack()
    source, headerRow, body, raidRoles = keptSet[1], keptSet[2], keptSet[3], keptSet[4]
    rowHeight, btnSize, buttonSpace, iconSize = keptSet[5], keptSet[6], keptSet[7], keptSet[8]
    activity, baseCols, cols, empowered = keptSet[9], keptSet[10], keptSet[11], keptSet[12]
    SPEC_COL.w, ROLE_COL.w = keptSet[13], keptSet[14]
end

local pvCols = {}
local function PvPaint(kind, wid, hgt)
    PvNames(kind)
    source, headerRow, body, raidRoles = PREVIEW, applicantView.head, applicantView.body, applicantView.raidRoles
    rowHeight = tonumber(mod.OwnListGet("applicantRowHeight")) or 36
    btnSize = math.max(18, math.min(rowHeight - 8, 24))
    buttonSpace = btnSize * 2 + GAP + 8
    iconSize = mod.OwnListIconSize(rowHeight)
    empowered = true
    local maxCount = MostRoles(applicantView.ids)
    SPEC_COL.w = math.max(TitleWidth(SPEC_COL.title), iconSize) + 6
    ROLE_COL.w = math.max(TitleWidth(ROLE_COL.title), iconSize * maxCount + ROLE_GAP * (maxCount - 1)) + 6
    activity = PV_ACT[kind]
    baseCols = kind == "dungeon" and COLS_KEYS or COLS_BASE
    cols = VisibleCols(baseCols, pvCols)
    -- a raid's header is tall enough for the counts' numbers over their circles
    local headH = 24
    if kind == "raid" then
        headH =
            math.max(24, mod.OwnListIconSize(mod.OwnListRowHeight()) + 2 * mod.OwnListSize("scoreSize") + 6)
    end
    applicantView.head:ClearAllPoints()
    applicantView.head:SetPoint("TOPLEFT", applicantView.frame, "TOPLEFT", 0, 0)
    applicantView.head:SetSize(wid - buttonSpace, headH)
    applicantView.body:ClearAllPoints()
    applicantView.body:SetPoint("TOPLEFT", applicantView.frame, "TOPLEFT", 0, -headH)
    applicantView.body:SetSize(wid, math.max(1, hgt - headH))
    PaintHeader()
    -- the counts sit left of the column titles
    local colsW = 0
    for _, colour in ipairs(cols) do
        colsW = colsW + colour.w
    end
    applicantView.raidRoles:ClearAllPoints()
    applicantView.raidRoles:SetPoint("RIGHT", applicantView.head, "RIGHT", -colsW - 8, 0)
    PaintRaidRoles()
    local max = activity.maxNumPlayers
    for index, ident in ipairs(applicantView.ids) do
        local b = applicantView.blocks[index] or MakeBlock(index, applicantView.body, applicantView.blocks)
        b.preview = true
        b.h = FillBlock(b, ident, max, 1, 0)
    end
    for index = #applicantView.ids + 1, #applicantView.blocks do
        applicantView.blocks[index].applicantID = nil
        applicantView.blocks[index]:Hide()
    end
end

-- draws the sample applicants for a key ("dungeon") or a raid into host,
-- w by h; kind nil hides them
function mod.ApplicantPreviewPaint(owner, kind, wid, hgt)
    if not kind then
        if applicantView.frame then
            applicantView.frame:Hide()
        end
        return
    end
    if not applicantView.frame then
        PvBuild(owner)
    end
    if applicantView.kind ~= kind then
        applicantView.kind, applicantView.scroll = kind, 0
    end
    applicantView.frame:Show()
    Keep()
    local success, err = pcall(PvPaint, kind, wid, hgt)
    PutBack()
    if not success then
        geterrorhandler()(err)
    end
    PvPosition()
end
