if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResultsList.lua - our own premade results list
--  blizzard's list stays alive underneath, faded out. we only read the
--  results and draw the groups that pass the filters, no gaps.
--  own selection + sign up button, nothing written to blizzard's panel
--  (that's what tainted it before). secret results: we step aside.
-------------------------------------------------------------------------------
local FOLDER, mod = ...
if CludesUI.HELD_BACK_ADDONS[FOLDER] then
    return
end -- held back (CludesUIGroupFinder.lua)
local GFNS = mod
local CUI = CludesUI

local DUNGEONS, RAIDS = 2, 3
local DELVES = GROUP_FINDER_CATEGORY_ID_DELVES or 121
local QUESTS, CUSTOM = 1, GROUP_FINDER_CUSTOM_CATEGORY or 6
local X_TEX = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png"
local CANCEL_H = 18 -- smallest cancel square
local GAP = 2
local Secret = CludesUI.IsSecret
local function Readable(t)
    return type(t) == "table" and not Secret(t) and not (canaccesstable and not canaccesstable(t))
end
-- cui's group finder skin is on; off, our rows and buttons take blizzard's look (a reload swaps, like the skin)
local function Skinned()
    return mod.SkinOn and mod.SkinOn() or false
end

-- display settings, in the profile (CludesUIGroupFinder.lua)
local function DB()
    return mod.OwnListDB()
end
-- bumped by every display change: the rows lay out again
local styleGen = 0
function mod.OwnListOn()
    return mod.Enabled()
end
function mod.OwnListRowHeight()
    return tonumber(DB().rowHeight) or 50
end
-- text sizes
local SIZE_DEFAULTS = { titleSize = 12, nameSize = 10, lineSize = 10, scoreSize = 10 }
function mod.OwnListSize(k)
    return tonumber(DB()[k]) or SIZE_DEFAULTS[k]
end
function mod.SetOwnListSize(k, val)
    DB()[k] = val
    styleGen = styleGen + 1
    if mod.OwnListRefresh then
        mod.OwnListRefresh()
    end
end
-- display settings
local DISPLAY_DEFAULTS = {
    iconShape = "circle",
    borderTexture = "solid",
    borderSize = 1,
    missingIcons = "blizzard",
    appsFirst = true,
    signupClicks = "double",
    visibility = "hidden",
    lineDelisted = false,
    lineAccepted = false,
    lineCancelled = false,
    lineDeclined = false,
}
function mod.OwnListGet(k)
    local val = DB()[k]
    if val == nil then
        return DISPLAY_DEFAULTS[k]
    end
    return val
end
-- user's border color, else the style's
function mod.OwnListBorderColor()
    local bc = mod.OwnListGet("borderColor")
    if type(bc) == "table" then
        return bc.r or 1, bc.g or 1, bc.b or 1
    end
    local btex = mod.OwnListGet("borderTexture") or "solid"
    if btex ~= "solid" and mod.OwnListGet("iconShape") == "square" then
        local c = CUI.GetBorderStyleSelectDefaults(btex)
        return c.r, c.g, c.b
    end
    if mod.ThemeBorder then
        return mod.ThemeBorder()
    end
    return 1, 1, 1
end
function mod.SetOwnListValue(k, val)
    DB()[k] = val
    styleGen = styleGen + 1
    if mod.OwnListRefresh then
        mod.OwnListRefresh()
    end
end

-- dungeons & raids background: the skin asks for this whenever it paints the
-- window, and gets nothing while group finder is off
CUI._ShellLooks = CUI._ShellLooks or {}
CUI._ShellLooks.lfg = function()
    if not mod.Enabled() then
        return nil
    end
    local skinData = DB()
    return skinData.windowBgColor, skinData.windowBgOpacity
end
-- no list rebuild, the color picker fires every frame while dragging
function mod.SetWindowLook(k, val)
    DB()[k] = val
    if CUI._WSkinRefreshStyles then
        CUI._WSkinRefreshStyles()
    end
end

local SP, widget, body, rowList, isShown = nil, nil, nil, {}, {}
local scrollPx = 0
local isActive = false
local guard = false
local lastClickID, lastClickTime, clickCount = nil, 0, 0
local selected -- ours, blizzard's is never touched
local Paint -- defined further down
local AnySecret -- same
local signBtn
-- result updates wait here for one flush on the next frame (a hidden frame)
local dirty, fullDirty, flusher = {}, false, nil
-- ticks the signed-up timers, shown only while a row in view has one
local ticker
-- clicks to sign up, per setting
local CLICKS_NEEDED = { single = 1, double = 2, triple = 3 }

-- delisted-then-relisted counts as fresh, so you can apply again
local function AppStatus(ident)
    local _, status, pending = C_LFGList.GetApplicationInfo(ident)
    if Secret(status) or Secret(pending) then
        return nil, nil
    end
    if status == "declined_delisted" then
        local details = C_LFGList.GetSearchResultInfo(ident)
        local delisted = Readable(details) and details.isDelisted
        if delisted == false then
            status = "none"
        end
    end
    return status, pending
end

-- when each pending application went in. blizzard hands back the time left
-- (applications time out after 5 min), so a reload still counts from the start
local APP_TIMEOUT = 300
local appliedAt = {}
local function SignedUpAt(ident)
    local _, status, pending, leftX = C_LFGList.GetApplicationInfo(ident)
    if Secret(status) or Secret(pending) or Secret(leftX) or status ~= "applied" then
        appliedAt[ident] = nil
        return nil
    end
    if not appliedAt[ident] then
        local gone = type(leftX) == "number" and math.max(0, APP_TIMEOUT - leftX) or 0
        appliedAt[ident] = GetTime() - gone
    end
    return appliedAt[ident]
end
-- time left before the application times out, like blizzard's
local function TimeLeft(at)
    local s = math.max(0, APP_TIMEOUT - math.floor(GetTime() - at))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- a friend or guildmate in the group: blizzard's blue name (once per row paint: no table)
local function FriendColor(details)
    local bn, char, guild = details.numBNetFriends, details.numCharFriends, details.numGuildMates
    if Secret(bn) or Secret(char) or Secret(guild) then
        return nil
    end
    if (tonumber(bn) or 0) + (tonumber(char) or 0) + (tonumber(guild) or 0) > 0 and BATTLENET_FONT_COLOR then
        return BATTLENET_FONT_COLOR:GetRGB()
    end
end

-- blizzard's row check, plus the relisted case
local function Selectable(ident)
    local status, pending = AppStatus(ident)
    if status ~= "none" or pending then
        return false
    end
    local details = C_LFGList.GetSearchResultInfo(ident)
    if not Readable(details) then
        return false
    end
    local delisted = details.isDelisted
    return not Secret(delisted) and not delisted
end

-- blizzard's sign up checks, read-only. returns ok, why not
local function SignUpState(ident)
    local message = LFGListUtil_GetActiveQueueMessage and LFGListUtil_GetActiveQueueMessage(true)
    if message then
        return false, message
    end
    if LFGListUtil_IsAppEmpowered and not LFGListUtil_IsAppEmpowered() then
        return false, LFG_LIST_APP_UNEMPOWERED
    end
    if
        IsInGroup(LE_PARTY_CATEGORY_HOME)
        and C_LFGList.IsCurrentlyApplying
        and C_LFGList.IsCurrentlyApplying()
    then
        return false, LFG_LIST_APP_CURRENTLY_APPLYING
    end
    local _, act = C_LFGList.GetNumApplications()
    local max = MAX_LFG_LIST_APPLICATIONS or 5
    if type(act) == "number" and act >= max then
        return false, LFG_LIST_HIT_MAX_APPLICATIONS and string.format(LFG_LIST_HIT_MAX_APPLICATIONS, max)
    end
    if GetNumGroupMembers(LE_PARTY_CATEGORY_HOME) > (MAX_PARTY_MEMBERS or 4) + 1 then
        return false, LFG_LIST_MAX_MEMBERS
    end
    local t, hgt, skinData = C_LFGList.GetAvailableRoles()
    if not (t or hgt or skinData) then
        return false, LFG_LIST_MUST_CHOOSE_SPEC
    end
    if GroupHasOfflineMember and GroupHasOfflineMember(LE_PARTY_CATEGORY_HOME) then
        return false, LFG_LIST_OFFLINE_MEMBER
    end
    if not ident then
        return false, LFG_LIST_SELECT_A_SEARCH_RESULT
    end
    if not Selectable(ident) then
        return false
    end
    return true
end

-- opens blizzard's sign up dialog directly
local function SignUp(ident)
    if not (ident and SignUpState(ident)) then
        return
    end
    local dlg = LFGListApplicationDialog
    if not (LFGListApplicationDialog_Show and dlg) then
        return
    end
    LFGListApplicationDialog_Show(dlg, ident)
    -- quick signup: auto confirm unless shift (if the core helper
    -- already did it, the dialog's gone)
    if
        CludesUIDB
        and CludesUIDB.quickSignup
        and not IsShiftKeyDown()
        and dlg:IsShown()
        and dlg.SignUpButton
        and dlg.SignUpButton:IsEnabled()
    then
        dlg.SignUpButton:Click()
    end
end

local function PaintSignBtn()
    if not signBtn then
        return
    end
    local success, why = SignUpState(selected)
    signBtn:SetEnabled(success)
    signBtn.why = (not success) and why or nil
end
-- first-seen order, so applied groups can stay put
local posOf, nextPos = {}, 0
local function Pos(ident)
    if not posOf[ident] then
        nextPos = nextPos + 1
        posOf[ident] = nextPos
    end
    return posOf[ident]
end
local function ByPos(a, b)
    return Pos(a) < Pos(b)
end

local function Accent()
    local a = CUI.CLUDES_GREEN
    if a then
        return a.r, a.g, a.b
    end
    return 0.30, 0.79, 0.94
end

-------------------------------------------------------------------------------
--  which groups show
-------------------------------------------------------------------------------
-- dimmed mode keeps filtered groups, faded
local dimmed = {}
-- kept from the last collect: applications, each listed group's filter pass
-- (a result update is checked against it) and the sort's values
local seen, isApp, passOf, sortVal = {}, {}, {}, {}
local noteOf, tops = {}, {} -- shown groups with a note, each shown row's top

-- the group's note when notes are on and it has one
local function NoteText(details)
    if not mod.OwnListGet("groupNotes") or not Readable(details) then
        return nil
    end
    local c = details.comment
    if type(c) ~= "string" or Secret(c) or c == "" then
        return nil
    end
    return c
end
-- the note's line under the row
local function NoteHeight()
    return mod.OwnListSize("lineSize") + 4
end
local sortDown, sortAppsFirst = false, true
local function BySortVal(a, b)
    if sortAppsFirst and isApp[a] ~= isApp[b] then
        return isApp[a] == true
    end
    local va, vb = sortVal[a], sortVal[b]
    if va ~= vb then
        if sortDown then
            return va > vb
        end
        return va < vb
    end
    return Pos(a) < Pos(b)
end
local function Collect()
    wipe(isShown)
    wipe(dimmed)
    wipe(seen)
    wipe(isApp)
    wipe(passOf)
    local dim = mod.OwnListGet("visibility") == "dimmed"
    local res = SP and SP.results
    if type(res) ~= "table" then
        return
    end
    local appsFirst = mod.OwnListGet("appsFirst") ~= false
    for _, ident in ipairs(res) do
        if not Secret(ident) then
            Pos(ident)
        end
    end
    local apps = C_LFGList.GetApplications() or {}
    for _, ident in ipairs(apps) do
        if not Secret(ident) then
            isApp[ident] = true
        end
    end
    if appsFirst then
        for _, ident in ipairs(apps) do
            if not Secret(ident) and not seen[ident] then
                seen[ident] = true
                isShown[#isShown + 1] = ident
            end
        end
    end
    for _, ident in ipairs(res) do
        if not Secret(ident) and not seen[ident] then
            seen[ident] = true
            local pass = (isApp[ident] or not GFNS.ExtraPasses or GFNS.ExtraPasses(ident)) and true or false
            passOf[ident] = pass
            if pass then
                isShown[#isShown + 1] = ident
            elseif dim then
                dimmed[ident] = true
                isShown[#isShown + 1] = ident
            end
        end
    end
    if not appsFirst then
        -- old applications, then back in original order
        for _, ident in ipairs(apps) do
            if not Secret(ident) and not seen[ident] then
                seen[ident] = true
                isShown[#isShown + 1] = ident
            end
        end
        table.sort(isShown, ByPos)
    end
    -- sort by score or size, applications stay on top
    local gc = GFNS.Cfg and GFNS.Cfg()
    local by = gc and gc.extraSortBy
    local field = (by == "high" or by == "low") and "leaderOverallDungeonScore"
        or (by == "big" or by == "small") and "numMembers"
    if field then
        sortDown, sortAppsFirst = by == "high" or by == "big", appsFirst
        wipe(sortVal)
        for _, ident in ipairs(isShown) do
            local details = C_LFGList.GetSearchResultInfo(ident)
            local val = Readable(details) and details[field]
            sortVal[ident] = (type(val) == "number" and not Secret(val)) and val or 0
        end
        table.sort(isShown, BySortVal)
    end
    wipe(noteOf)
    if mod.OwnListGet("groupNotes") then
        for _, ident in ipairs(isShown) do
            if NoteText(C_LFGList.GetSearchResultInfo(ident)) then
                noteOf[ident] = true
            end
        end
    end
end

-------------------------------------------------------------------------------
--  right-click menu
-------------------------------------------------------------------------------
-- a player link in chat: clicking it is blizzard's own whisper, so nothing of ours
-- touches the chat box (opening it from here taints the chat type)
local function WhisperLeader(leader)
    local name = CUI.BuildFullName(leader) or leader
    local widget = DEFAULT_CHAT_FRAME
    if not (name and widget) then
        return
    end
    local itemLink = "|Hplayer:" .. name .. "|h[" .. name .. "]|h"
    widget:AddMessage(CludesUI.Lf("Click to whisper the group leader: %1$s", itemLink), 1, 0.82, 0)
end

-- blizzard's menu under blizzard's tag, so other add-ons' entries (raider.io's
-- copy link and so on) still show. the owner is our row, which has resultID
-- like blizzard's does
local function TaggedMenu(anchor, ident, details, leader)
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:SetTag("MENU_LFG_FRAME_SEARCH_ENTRY")
        -- a hidden flag is never tested: the title shows the name, as the row does
        local censored = details.censored
        if Secret(censored) then
            censored = nil
        end
        root:CreateTitle(censored and CENSORED_LFG_GROUP_NAME or details.name or "")
        local wid = root:CreateButton(WHISPER_LEADER or "Whisper Leader", function()
            WhisperLeader(leader)
        end)
        if leader then
            wid:SetTooltip(function(tipText)
                GameTooltip_AddNormalLine(tipText, CludesUI.L("Prompts in chat to whisper the party leader."))
            end)
        else
            wid:SetEnabled(false)
            wid:SetTooltip(function(tipText)
                GameTooltip_SetTitle(tipText, WHISPER or "Whisper")
                GameTooltip_AddNormalLine(
                    tipText,
                    LFG_LIST_MUST_SIGN_UP_TO_WHISPER or "Sign up to whisper the leader"
                )
            end)
        end
        root:CreateButton(LFG_LIST_REPORT_GROUP_FOR or "Report Group", function()
            LFGList_ReportListing(ident, leader)
        end)
        root:CreateButton(REPORT_GROUP_FINDER_ADVERTISEMENT or "Report Advertisement", function()
            LFGList_ReportAdvertisement(ident)
        end)
    end)
end

function mod.OwnListMenu(anchor, ident)
    local details = C_LFGList.GetSearchResultInfo(ident)
    if not Readable(details) then
        return
    end
    local leader = details.leaderName
    if Secret(leader) then
        leader = nil
    end
    TaggedMenu(anchor, ident, details, leader)
end

-------------------------------------------------------------------------------
--  a row
-------------------------------------------------------------------------------
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
-- members, tanks first
local function ByRole(a, b)
    local ra, rb = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
    if ra ~= rb then
        return ra < rb
    end
    return a.k < b.k
end
-- raid role colors
local RR_ROLES = { "TANK", "HEALER", "DAMAGER" }
local RR_COLORS =
    { TANK = { 0.16, 0.38, 0.78 }, HEALER = { 0.16, 0.62, 0.24 }, DAMAGER = { 0.72, 0.16, 0.16 } }
mod.RaidRoleColors = RR_COLORS
local NEED_ATLAS = {
    TANK = "groupfinder-icon-role-micro-tank",
    HEALER = "groupfinder-icon-role-micro-heal",
    DAMAGER = "groupfinder-icon-role-micro-dps",
}
local REMAINING = { TANK = "TANK_REMAINING", HEALER = "HEALER_REMAINING", DAMAGER = "DAMAGER_REMAINING" }
local PERSON_TEX = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-person.png"
local PLAYERS_COLOR = { 0.4, 0.4, 0.42 }
-- a count circle's border, the same as the member icons get (ring when round,
-- border style when square)
local function CircleEdge(p, round, px, cr, cg, callback, texture, key)
    p.ring:Hide()
    p.edge:Hide()
    if px <= 0 then
        return
    end
    if round then
        p.ring:ClearAllPoints()
        p.ring:SetPoint("TOPLEFT", p.bg, "TOPLEFT", -px, px)
        p.ring:SetPoint("BOTTOMRIGHT", p.bg, "BOTTOMRIGHT", px, -px)
        p.ring:SetColorTexture(cr, cg, callback, 1)
        p.ring:Show()
    else
        if p.edge._key ~= key then
            p.edge._key = key
            CUI.ApplyBorderStyle(p.edge, px, cr, cg, callback, 1, texture)
        end
        p.edge:Show()
    end
end
-- the right side follows the activity's display type, as blizzard's rows do:
-- member icons, role counts, a player count, or nothing
local function MemberMode(ai, cap)
    local DT = Enum.LFGListDisplayType
    local dt = ai and ai.displayType
    if DT and type(dt) == "number" and not Secret(dt) then
        if dt == DT.RoleEnumerate or dt == DT.ClassEnumerate then
            return cap <= 5 and "icons" or "counts"
        end
        if dt == DT.RoleCount then
            return "counts"
        end
        if dt == DT.PlayerCount then
            return "players"
        end
        -- HideAll, and a type blizzard's rows do not draw (its newer Comment): nothing
        return nil
    end
    return cap > 5 and "counts" or "icons"
end
-- status text + colors
local G, R, Y = { 0.1, 1, 0.1 }, { 1, 0.25, 0.25 }, { 1, 0.82, 0 }
-- blizzard's strings have color codes baked in, strip them
local function Plain(t)
    return t and (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
-- blizzard has no delisted or failed string (its list shows Declined / Cancelled), so the fallback
-- goes through L
local function St(textValue, fallback, c)
    return { Plain(textValue) or CludesUI.L(fallback), c[1], c[2], c[3] }
end
local STATUS = {
    applied = St(LFG_LIST_PENDING, "Pending", G),
    invited = St(LFG_LIST_APP_INVITED, "Invited", G),
    inviteaccepted = St(LFG_LIST_APP_INVITE_ACCEPTED, "Invite Accepted", G),
    invitedeclined = St(LFG_LIST_APP_INVITE_DECLINED, "Invite Declined", R),
    declined = St(LFG_LIST_APP_DECLINED, "Declined", R),
    declined_full = St(LFG_LIST_APP_FULL, "Full", R),
    declined_delisted = St(LFG_LIST_APP_DELISTED, "Delisted", R),
    timedout = St(LFG_LIST_APP_TIMED_OUT, "Timed Out", R),
    cancelled = St(LFG_LIST_APP_CANCELLED, "Cancelled", Y),
    failed = St(LFG_LIST_APP_FAILED, "Failed", R),
}
-- underline setting + color per status
-- each status: its switch, its own color and the key of the user's color
local LINE_DELISTED = { "lineDelisted", 0.6, 0.6, 0.6, "color_lineDelisted" }
local LINE_ACCEPTED = { "lineAccepted", 0.1, 0.9, 0.1, "color_lineAccepted" }
local LINE_CANCELLED = { "lineCancelled", 1, 0.55, 0.1, "color_lineCancelled" }
local LINE_DECLINED = { "lineDeclined", 1, 0.2, 0.2, "color_lineDeclined" }
-- by switch, for the settings page's color pickers
mod.STATUS_LINES = {
    lineDelisted = LINE_DELISTED,
    lineAccepted = LINE_ACCEPTED,
    lineCancelled = LINE_CANCELLED,
    lineDeclined = LINE_DECLINED,
}
-- a status's color: the user's, else its own
local function StatusColor(line)
    local c = mod.OwnListGet(line[5])
    if type(c) == "table" then
        return c.r or 1, c.g or 1, c.b or 1
    end
    return line[2], line[3], line[4]
end
local LINE_OF = {
    [STATUS.declined_delisted] = LINE_DELISTED,
    [STATUS.applied] = LINE_ACCEPTED,
    [STATUS.invited] = LINE_ACCEPTED,
    [STATUS.inviteaccepted] = LINE_ACCEPTED,
    [STATUS.cancelled] = LINE_CANCELLED,
    [STATUS.declined] = LINE_DECLINED,
    [STATUS.declined_full] = LINE_DECLINED,
    [STATUS.timedout] = LINE_DECLINED,
    [STATUS.invitedeclined] = LINE_DECLINED,
    [STATUS.failed] = LINE_DECLINED,
}

-- parent: the settings preview's, else the list's (only the list's go in rows)
local function MakeRow(i, hostFrame)
    local region = CreateFrame("Button", nil, hostFrame or body)
    region:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local stock = not Skinned()
    region.stock = stock
    region.bg = region:CreateTexture(nil, "BACKGROUND")
    region.bg:SetAllPoints()
    region.bg:SetColorTexture(1, 1, 1, stock and 0.04 or 0.03)
    region.sel = region:CreateTexture(nil, "BORDER")
    region.sel:SetAllPoints()
    if stock then
        region.sel:SetAtlas("groupfinder-highlightbar-yellow")
        region.sel:SetBlendMode("ADD")
        region.sel:Hide()
    end
    -- status underline
    region.under = region:CreateTexture(nil, "ARTWORK", nil, 7)
    region.under:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", 0, 0)
    region.under:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
    region.under:SetHeight(2)
    region.under:Hide()
    -- status highlight across the row, under the selection
    region.stat = region:CreateTexture(nil, "BACKGROUND", nil, 1)
    region.stat:SetAllPoints()
    region.stat:Hide()
    region.hl = region:CreateTexture(nil, "HIGHLIGHT")
    region.hl:SetAllPoints()
    if stock then
        region.hl:SetAtlas("groupfinder-highlightbar-blue")
        region.hl:SetBlendMode("ADD")
    else
        region.hl:SetColorTexture(1, 1, 1, 0.06)
    end
    -- the row without its note: icons and counts centre on it
    region.mid = region:CreateTexture(nil, "BACKGROUND")
    region.mid:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
    region.mid:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, 0)
    -- the group's note, one line under the row
    region.note = region:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    region.note:SetJustifyH("LEFT")
    region.note:SetWordWrap(false)
    region.note:SetMaxLines(1)
    region.note:Hide()
    region.name = region:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    region.name:SetJustifyH("LEFT")
    region.name:SetWordWrap(false)
    region.act = region:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    region.act:SetJustifyH("LEFT")
    region.act:SetWordWrap(false)
    -- short dungeon name before the title
    region.short = region:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    region.short:Hide()
    -- line three bits
    region.sep1 = region:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    region.sep1:SetText("||")
    region.style = region:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    region.sep2 = region:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    region.sep2:SetText("||")
    region.tag = region:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    region.flag = region:CreateTexture(nil, "OVERLAY")
    region.flag:SetSize(13, 10)
    region.sep3 = region:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    region.sep3:SetText("||")
    region.timer = region:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- kept for every paint of this row: line three's parts, the sized ones,
    -- the line layout, the members and the open roles
    region.line3 = { region.sep1, region.style, region.sep2, region.tag, region.flag, region.sep3, region.timer }
    region.lineFS = { region.sep1, region.style, region.sep2, region.tag, region.sep3, region.timer }
    region.lineH, region.lineY = {}, {}
    region.members, region.mpool, region.needs = {}, {}, {}
    -- cancel button
    if stock then
        -- blizzard's red x button
        region.cancel = CreateFrame("Button", nil, region, "UIMenuButtonStretchTemplate")
        region.cancel.tex = region.cancel:CreateTexture(nil, "ARTWORK")
        region.cancel.tex:SetAtlas("groupfinder-icon-redx")
        region.cancel.tex:SetPoint("CENTER")
        region.cancel:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        -- the template's highlight is inset and cropped; the whole glow, on the whole button
        local highlight = region.cancel:GetHighlightTexture()
        if highlight then
            highlight:ClearAllPoints()
            highlight:SetAllPoints()
            highlight:SetTexCoord(0, 1, 0, 1)
        end
    else
        region.cancel = CreateFrame("Button", nil, region)
        region.cancel.bg = region.cancel:CreateTexture(nil, "BACKGROUND")
        region.cancel.bg:SetAllPoints()
        region.cancel.bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        region.cancel.edge = CUI.MakeBorder(region.cancel, 0.25, 0.25, 0.25, 1, CUI.PanelPP)
        region.cancel.tex = region.cancel:CreateTexture(nil, "OVERLAY")
        region.cancel.tex:SetTexture(X_TEX)
        region.cancel.tex:SetPoint("CENTER")
        region.cancel.tex:SetVertexColor(0.8, 0.8, 0.8, 1)
    end
    region.cancel:SetScript("OnEnter", function(self)
        if not stock then
            self.tex:SetVertexColor(1, 0.3, 0.3, 1)
            if self.edge and self.edge.SetColor then
                self.edge:SetColor(1, 0.3, 0.3, 1)
            end
        end
        CUI.ShowWidgetTooltip(self, CANCEL_SIGN_UP or "Cancel Sign Up")
    end)
    region.cancel:SetScript("OnLeave", function(self)
        if not stock then
            self.tex:SetVertexColor(0.8, 0.8, 0.8, 1)
            if self.edge and self.edge.SetColor then
                self.edge:SetColor(0.25, 0.25, 0.25, 1)
            end
        end
        CUI.HideWidgetTooltip()
    end)
    region.cancel:SetScript("OnClick", function(self)
        if self:GetParent().preview then
            return
        end
        local ident = self:GetParent().resultID
        if ident and not Secret(ident) then
            C_LFGList.CancelApplication(ident)
        end
    end)
    region.status = region:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    region.status:SetJustifyH("RIGHT")
    region.score = region:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    region.score:SetJustifyH("RIGHT")
    region.icons, region.crowns, region.rings, region.roles = {}, {}, {}, {}
    for k = 1, 5 do
        local t = region:CreateTexture(nil, "ARTWORK", nil, 2)
        region.icons[k] = t
        -- ring behind round spec icons
        local ring = region:CreateTexture(nil, "ARTWORK", nil, 1)
        ring:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 1)
        ring:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, -1)
        ring:Hide()
        region.rings[k] = ring
        local m1 = region:CreateMaskTexture()
        m1:SetTexture(
            "Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        m1:SetAllPoints(ring)
        ring:AddMaskTexture(m1)
        local m2 = region:CreateMaskTexture()
        m2:SetTexture(
            "Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        m2:SetAllPoints(t)
        region.masks = region.masks or {}
        region.masks[k] = m2
        -- role mark on top
        local role = region:CreateTexture(nil, "ARTWORK", nil, 3)
        role:SetPoint("CENTER", t)
        role:Hide()
        region.roles[k] = role
        -- holds the square border
        local bf = CreateFrame("Frame", nil, region)
        bf:SetAllPoints(t)
        bf:EnableMouse(false)
        bf:Hide()
        region.borders = region.borders or {}
        region.borders[k] = bf
        -- leader crown
        local c = region:CreateTexture(nil, "OVERLAY")
        c:SetAtlas("groupfinder-icon-leader")
        c:SetPoint("BOTTOM", t, "TOP", 0, 2)
        c:Hide()
        region.crowns[k] = c
    end
    -- raid role counts, and a 4th circle for a player count
    region.rr = {}
    for k = 1, 4 do
        local backdrop = region:CreateTexture(nil, "ARTWORK", nil, 1)
        local mask = region:CreateMaskTexture()
        mask:SetTexture(
            "Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        mask:SetAllPoints(backdrop)
        local t = region:CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetPoint("CENTER", backdrop)
        local c = region:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c:SetJustifyH("CENTER")
        -- the member icons' borders: a ring behind round ones, a border frame on square ones
        local ring = region:CreateTexture(nil, "ARTWORK", nil, 0)
        local rm = region:CreateMaskTexture()
        rm:SetTexture(
            "Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        rm:SetAllPoints(ring)
        ring:AddMaskTexture(rm)
        local edge = CreateFrame("Frame", nil, region)
        edge:SetAllPoints(backdrop)
        edge:EnableMouse(false)
        backdrop:Hide()
        t:Hide()
        c:Hide()
        ring:Hide()
        edge:Hide()
        region.rr[k] = { bg = backdrop, mask = mask, icon = t, count = c, ring = ring, edge = edge }
    end
    -- row art
    region.art = region:CreateTexture(nil, "BACKGROUND", nil, 7)
    if mod.ROW_ART then
        region.art:SetAlpha(mod.ROW_ART.alpha)
        local m = region:CreateMaskTexture()
        m:SetTexture(mod.ROW_ART.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(region.art)
        region.art:AddMaskTexture(m)
    end
    region.art:Hide()
    region:SetScript("OnClick", function(self, btnFrame)
        if self.preview then
            return
        end
        local ident = self.resultID
        if not ident or not isActive then
            return
        end
        if btnFrame == "RightButton" then
            return mod.OwnListMenu(self, ident)
        end
        local nowTime = GetTime()
        if lastClickID == ident and (nowTime - lastClickTime) < 0.4 then
            clickCount = clickCount + 1
        else
            clickCount = 1
        end
        lastClickID, lastClickTime = ident, nowTime
        local need = CLICKS_NEEDED[mod.OwnListGet("signupClicks")] or 2
        local signup = CludesUIDB and CludesUIDB.quickSignup and clickCount >= need
        -- at the app limit, cancel the oldest
        if mod.GFCancelOldest then
            mod.GFCancelOldest(ident)
        end
        -- same check blizzard's row click does
        if not Selectable(ident) then
            return
        end
        if selected ~= ident then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            selected = ident
            Paint()
        end
        if signup and SignUpState(ident) then
            lastClickID, clickCount = nil, 0
            SignUp(ident)
        end
    end)
    region:SetScript("OnEnter", function(self)
        if self.preview then
            if mod.OwnListPreviewTip then
                mod.OwnListPreviewTip(self)
            end
            return
        end
        if not self.resultID then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 25, 0)
        LFGListUtil_SetSearchEntryTooltip(GameTooltip, self.resultID)
        GameTooltip:Show()
    end)
    region:SetScript("OnLeave", GameTooltip_Hide)
    if i then
        rowList[i] = region
    end
    return region
end

local function SetSize(fontStr, size)
    local success, filePath, _, flags = pcall(fontStr.GetFont, fontStr)
    if success and filePath then
        fontStr:SetFont(filePath, size, flags or "")
    end
end

-- a count circle's number: above it, or on it (its symbol hidden) when the row
-- is too short for a line above. the width its slot takes
local function PlaceCount(p, num, isz, fsz, inside)
    -- on the circle the number shrinks to fit inside it
    SetSize(p.count, inside and math.min(fsz, math.max(6, math.floor(isz * 0.7 + 0.5))) or fsz)
    p.count:SetText(num)
    p.count:ClearAllPoints()
    -- a box even on both sides of the circle, the text centred in it
    if inside then
        p.icon:Hide()
        p.count:SetPoint("LEFT", p.bg, "LEFT", -isz, 0)
        p.count:SetPoint("RIGHT", p.bg, "RIGHT", isz, 0)
    else
        p.icon:Show()
        p.count:SetPoint("BOTTOMLEFT", p.bg, "TOPLEFT", -isz, 1)
        p.count:SetPoint("BOTTOMRIGHT", p.bg, "TOPRIGHT", isz, 1)
    end
    p.count:Show()
    if inside then
        return isz
    end
    return math.max(isz, math.ceil(p.count:GetStringWidth() or 8))
end

-- Texts that show other players' writing (group titles here, applicant names
-- and notes in the applicant list) take a font family: Cyrillic, Korean and
-- Chinese letters draw in the client's own faces. Face and outline are the
-- string's template's, read once before its first switch and kept here (a
-- string on a family is never read back); the templates' drop shadow rides the
-- family. Every font write to such a string goes through here.
local famFace, famFlags = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
function mod.OwnListNameFont(fontStr, size)
    local face = famFace[fontStr]
    if not face then
        local success, filePath, _, flags = pcall(fontStr.GetFont, fontStr)
        if not (success and filePath) then
            return
        end
        face = filePath
        famFace[fontStr], famFlags[fontStr] = filePath, flags or ""
    end
    CUI.SetFontFamily(fontStr, face, size, famFlags[fontStr], true)
end

local function IconSize(hgt)
    -- 16px at 100%, 1px per 5%
    local c = GFNS.Cfg and GFNS.Cfg()
    local pct = tonumber(c and c.iconSize) or (GFNS.DEFAULTS and GFNS.DEFAULTS.iconSize) or 125
    return math.max(8, math.min(hgt - 4, 16 + math.floor((pct - 100) / 5 + 0.5)))
end

mod.OwnListIconSize = IconSize

-- a row's layout: again only for a new row height or a display change (styleGen)
local function Layout(region, hgt)
    if region.layH == hgt and region.layGen == styleGen then
        return
    end
    region.layH, region.layGen = hgt, styleGen
    region.mid:SetHeight(hgt)
    local pad = 6
    local tS, nS, lS = mod.OwnListSize("titleSize"), mod.OwnListSize("nameSize"), mod.OwnListSize("lineSize")
    mod.OwnListNameFont(region.name, tS)
    SetSize(region.act, nS)
    local sized = region.lineFS
    for i = 1, #sized do
        SetSize(sized[i], lS)
    end
    mod.OwnListNameFont(region.note, lS)
    -- title always fits, then the dungeon, then line three
    local room = hgt - 4
    local lines = region.lineH
    wipe(lines)
    lines[1] = tS + 2
    if room >= tS + nS + 6 then
        lines[2] = nS + 2
    end
    local gc = GFNS.Cfg and GFNS.Cfg()
    local third = not (gc and gc.extraShowPlaystyle == false)
        or (gc and gc.extraRegionTags ~= false and mod.RegionList() ~= nil)
    if lines[2] and third and room >= tS + nS + lS + 10 then
        lines[3] = lS + 2
    end
    local sum = 0
    for i = 1, #lines do
        sum = sum + lines[i]
    end
    sum = sum + (#lines - 1) * 2
    local posY = math.floor((hgt - sum) / 2)
    local lineY = region.lineY
    wipe(lineY)
    for i = 1, #lines do
        lineY[i] = posY
        posY = posY + lines[i] + 2
    end
    region.name:ClearAllPoints()
    region.name:SetPoint("TOPLEFT", region, "TOPLEFT", pad, -region.lineY[1])
    region.act:ClearAllPoints()
    if lines[2] then
        region.act:SetPoint("TOPLEFT", region, "TOPLEFT", pad, -region.lineY[2])
        region.act:Show()
    else
        region.act:Hide()
    end
    region.lines = #lines
    region.pad = pad

    local isz = IconSize(hgt)
    local bpx = tonumber(mod.OwnListGet("borderSize")) or 0
    local gap = 2 + ((mod.OwnListGet("iconShape") ~= "square") and bpx * 2 or 0) -- room for rings
    local cw = math.max(8, math.floor(isz * 0.6 + 0.5))
    -- cancel square left of the text, about two lines tall (placed in fill)
    local cs = math.max(CANCEL_H, math.min(hgt - 8, tS + nS + 6))
    region.cancel:SetSize(cs, cs)
    local xs = math.floor(cs * (region.stock and 0.6 or 0.45) + 0.5)
    region.cancel.tex:SetSize(xs, xs)
    region.cancelSize = cs
    region.cancel:SetFrameLevel(region:GetFrameLevel() + 5)
    SetSize(region.score, mod.OwnListSize("scoreSize"))
    local posX = -pad - ((mod.OwnListGet("iconShape") ~= "square") and bpx or 0)
    for k = 5, 1, -1 do
        local t = region.icons[k]
        t:SetSize(isz, isz)
        region.roles[k]:SetSize(math.floor(isz * 0.7 + 0.5), math.floor(isz * 0.7 + 0.5))
        region.crowns[k]:SetSize(cw, math.floor(cw * 0.6 + 0.5))
        t:ClearAllPoints()
        t:SetPoint("RIGHT", region.mid, "RIGHT", posX, 0)
        posX = posX - isz - gap
    end
    region.scoreX = posX - 4 -- a raid's role counts move the score; the next group puts it back
    region.scoreRaid = nil
    region.score:ClearAllPoints()
    region.score:SetPoint("RIGHT", region.mid, "RIGHT", region.scoreX, 0)
    region.status:ClearAllPoints()
    region.status:SetPoint("RIGHT", region.score, "LEFT", -8, 0)
    region.name:SetPoint("RIGHT", region.status, "LEFT", -8, 0)
    region.act:SetPoint("RIGHT", region.status, "LEFT", -8, 0)
end

-- line three's next part, after the one placed before it (r.l3prev)
local function Put(region, p, gap)
    p:ClearAllPoints()
    local previous = region.l3prev
    if previous then
        p:SetPoint("LEFT", previous, "RIGHT", gap or 0, 0)
    else
        p:SetPoint("TOPLEFT", region, "TOPLEFT", region.textX or region.pad, -region.lineY[3])
    end
    p:Show()
    region.l3prev = p
end

-- where a row reads its group from: the game's results, or the settings
-- preview's sample groups
local LIVE = {
    info = function(ident)
        return C_LFGList.GetSearchResultInfo(ident)
    end,
    activity = function(act)
        return C_LFGList.GetActivityInfoTable(act)
    end,
    player = function(ident, k)
        return C_LFGList.GetSearchResultPlayerInfo(ident, k)
    end,
    counts = function(ident)
        return C_LFGList.GetSearchResultMemberCounts(ident)
    end,
    appStatus = AppStatus,
    signedAt = SignedUpAt,
    nameColor = function(ident, details, ai)
        if mod.GFNameColor then
            return mod.GFNameColor(ident, details, ai)
        end
    end,
    region = function(ident)
        if mod.RegionTagOf then
            return mod.RegionTagOf(ident)
        end
    end,
    art = function(ident)
        return mod.RowArtFor and mod.RowArtFor(ident)
    end,
}

-- line three: playstyle | region | time since you signed up
local function LineThree(region, ident, details, source)
    local parts = region.line3
    for i = 1, #parts do
        parts[i]:Hide()
    end
    region.signedAt = nil
    region.l3prev = nil
    if (region.lines or 0) < 3 then
        return
    end
    local style = ""
    local ps = details.generalPlaystyle
    local gc = GFNS.Cfg and GFNS.Cfg()
    if not (gc and gc.extraShowPlaystyle == false) and type(ps) == "number" and not Secret(ps) then
        style = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. ps] or ""
    end
    local tag, tr, tg, tb, flag
    tag, tr, tg, tb, flag = source.region(ident)
    if style ~= "" then
        region.style:SetText(style)
        Put(region, region.style)
    end
    if tag then
        if region.l3prev then
            Put(region, region.sep2, 4)
        end
        region.tag:SetText(tag)
        region.tag:SetTextColor(tr, tg, tb, 1)
        Put(region, region.tag, 4)
        if flag then
            local fh = math.max(8, mod.OwnListSize("lineSize"))
            region.flag:SetSize(math.floor(fh * 4 / 3 + 0.5), fh)
            region.flag:SetTexture(flag)
            Put(region, region.flag, 4)
        end
    end
    local at = source.signedAt(ident)
    if at then
        if region.l3prev then
            Put(region, region.sep3, 4)
        end
        region.timer:SetText(TimeLeft(at))
        Put(region, region.timer, 4)
        region.signedAt = at
    end
end

local function Fill(region, ident, source)
    source = source or LIVE
    region.resultID = ident
    local details = source.info(ident)
    if not Readable(details) then
        region:Hide()
        return
    end
    -- protected text, straight to the font string
    region.name:SetText(details.name)
    local acts = details.activityIDs
    local act = type(acts) == "table" and not Secret(acts) and acts[1]
    local ai = act and not Secret(act) and source.activity(act)
    if not Readable(ai) then
        ai = nil
    end
    -- colored group names
    local nr, ng, nb
    nr, ng, nb = source.nameColor(ident, details, ai) -- "and" would drop g and b
    if not nr then
        nr, ng, nb = FriendColor(details)
    end
    if nr then
        region.name:SetTextColor(nr, ng, nb)
    else
        region.name:SetTextColor(1, 0.82, 0)
    end
    region.act:SetText(ai and ai.fullName or "")
    -- the note, only where the list left room for it (protected text, straight to the font string)
    local note = region.noteRoom and NoteText(details)
    if note then
        region.note:ClearAllPoints()
        region.note:SetPoint("TOPLEFT", region.mid, "BOTTOMLEFT", region.pad or 6, 0)
        region.note:SetPoint("TOPRIGHT", region.mid, "BOTTOMRIGHT", -(region.pad or 6), 0)
        region.note:SetText(string.format(LFG_LIST_COMMENT_FORMAT or "%s", note))
        local fc = LFG_LIST_COMMENT_FONT_COLOR
        if fc then
            region.note:SetTextColor(fc.r, fc.g, fc.b)
        else
            region.note:SetTextColor(0.6, 0.6, 0.6)
        end
    end
    region.note:SetShown(note and true or false)
    -- signed up: the cancel square sits left of the text, which moves over for it
    local appStatus = source.appStatus(ident)
    local canCancel = appStatus == "applied"
    local x0 = region.pad or 6
    region.cancel:ClearAllPoints()
    if canCancel then
        region.cancel:SetPoint("LEFT", region.mid, "LEFT", x0, 0)
        x0 = x0 + (region.cancelSize or CANCEL_H) + 6
    end
    region.cancel:SetShown(canCancel)
    region.textX = x0
    if region.act:IsShown() then
        region.act:SetPoint("TOPLEFT", region, "TOPLEFT", x0, -(region.lineY and region.lineY[2] or 0))
    end
    local short = (region.lines or 0) < 2 and ai and mod.GFShortName(ai.fullName)
    if short and short ~= "" then
        -- the title's face, size and outline (the title is on a family, so they
        -- come from what it was given, never read back from it)
        local filePath = famFace[region.name]
        if filePath then
            region.short:SetFont(filePath, mod.OwnListSize("titleSize"), famFlags[region.name])
        end
        region.short:SetTextColor(region.act:GetTextColor())
        region.short:SetText(short)
        region.short:ClearAllPoints()
        region.short:SetPoint("TOPLEFT", region, "TOPLEFT", x0, -(region.lineY and region.lineY[1] or 0))
        region.short:Show()
        region.name:SetPoint("TOPLEFT", region.short, "TOPRIGHT", 4, 0)
    else
        region.short:Hide()
        region.name:SetPoint("TOPLEFT", region, "TOPLEFT", x0, -(region.lineY and region.lineY[1] or 0))
    end
    LineThree(region, ident, details, source)
    local Opt = mod.GFOpt or function()
        return true
    end
    local score = details.leaderOverallDungeonScore
    if Opt("leaderRating") and type(score) == "number" and not Secret(score) and score > 0 then
        -- raider.io or game colors
        local cr, cg, callback = 1, 1, 1
        if mod.GFRatingColor then
            cr, cg, callback = mod.GFRatingColor(score)
        end
        region.score:SetText(score)
        region.score:SetTextColor(cr, cg, callback)
    else
        region.score:SetText("")
    end
    local st = appStatus and STATUS[appStatus]
    local delisted = details.isDelisted
    if not Secret(delisted) and delisted then
        st = STATUS.declined_delisted
    end -- secret check first
    if st then
        region.status:SetText(st[1])
        -- same color as the status effect
        local sl = LINE_OF[st]
        if sl then
            region.status:SetTextColor(StatusColor(sl))
        else
            region.status:SetTextColor(st[2], st[3], st[4], 1)
        end
    else
        region.status:SetText("")
    end
    -- status effect: an underline, or the whole row tinted
    local line = st and LINE_OF[st]
    local enabled = line and mod.OwnListGet(line[1]) ~= false or false
    local rowFx = enabled and mod.OwnListGet("statusStyle") == "row" or false
    if enabled then
        local lr, lg, lb = StatusColor(line)
        -- solid, so it reads the same over any window background (the preview's is darker)
        if rowFx then
            region.stat:SetColorTexture(lr * 0.15 + 0.045, lg * 0.15 + 0.045, lb * 0.15 + 0.045, 1)
        else
            region.under:SetColorTexture(lr, lg, lb, 0.9)
        end
    end
    region.under:SetShown(enabled and not rowFx)
    region.stat:SetShown(rowFx)
    -- row art
    local art = source.art(ident)
    if art and mod.ROW_ART then
        local wid = region:GetWidth() or 0
        region.art:SetTexture(art)
        region.art:SetTexCoord(unpack(mod.ROW_ART.crop))
        region.art:ClearAllPoints()
        region.art:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
        region.art:SetPoint("BOTTOMLEFT", region.mid, "BOTTOMLEFT", 0, 0)
        region.art:SetWidth(math.max(1, math.floor(wid * mod.ROW_ART.share)))
        region.art:Show()
    else
        region.art:Hide()
    end
    -- members, tanks first (the row's own tables, refilled)
    local members, pool = region.members, region.mpool
    wipe(members)
    local n = details.numMembers
    if type(n) == "number" and not Secret(n) then
        for k = 1, n do
            local p = source.player(ident, k)
            if Readable(p) and p.classFilename and not Secret(p.classFilename) then
                local specInfo = p.specName
                if Secret(specInfo) then
                    specInfo = nil
                end
                local lead = p.isLeader
                if Secret(lead) then
                    lead = nil
                end
                local role = p.assignedRole
                if Secret(role) then
                    role = nil
                end
                local e = pool[#members + 1]
                if not e then
                    e = {}
                    pool[#members + 1] = e
                end
                e.cls, e.role, e.spec, e.lead, e.k = p.classFilename, role, specInfo, lead, k
                members[#members + 1] = e
            end
        end
    end
    table.sort(members, ByRole)
    local cap = ai and ai.maxNumPlayers or 5
    local mode = MemberMode(ai, cap)
    -- open roles for the empty slots
    local needs = region.needs
    wipe(needs)
    if mod.OwnListGet("missingIcons") ~= "none" and mode == "icons" and cap == 5 then
        local counts = source.counts(ident)
        if Readable(counts) then
            for i = 1, #RR_ROLES do
                local role = RR_ROLES[i]
                local leftX = counts[REMAINING[role]]
                if type(leftX) == "number" and not Secret(leftX) then
                    for _ = 1, leftX do
                        needs[#needs + 1] = role
                    end
                end
            end
        end
    end
    local specOn = Opt("specIcons")
    -- the crown goes with the activity line when the row's too short for it
    local crownOn = Opt("leaderCrown") and (region.lines or 0) >= 2
    local square = mod.OwnListGet("iconShape") == "square"
    local bpx = tonumber(mod.OwnListGet("borderSize")) or 0
    local btex = mod.OwnListGet("borderTexture") or "solid"
    local br, backdrop, bb = 1, 1, 1
    local bc = mod.OwnListGet("borderColor")
    if type(bc) == "table" then
        br, backdrop, bb = bc.r or 1, bc.g or 1, bc.b or 1
    elseif btex ~= "solid" and square then
        local c = CUI.GetBorderStyleSelectDefaults(btex)
        br, backdrop, bb = c.r, c.g, c.b
    elseif mod.ThemeBorder then
        br, backdrop, bb = mod.ThemeBorder()
    end
    local bkey = btex .. ":" .. bpx .. ":" .. br .. ":" .. backdrop .. ":" .. bb
    local blizzMissing = mod.OwnListGet("missingIcons") ~= "cludes"
    local nextNeed = 1
    for k = 1, 5 do
        local t, m, role, bf = region.icons[k], members[k], region.roles[k], region.borders[k]
        region.crowns[k]:Hide()
        region.rings[k]:Hide()
        role:Hide()
        role:SetDesaturated(false)
        role:SetAlpha(1)
        bf:Hide()
        if t._masked then
            t:RemoveMaskTexture(region.masks[k])
            t._masked = nil
        end
        t:SetTexCoord(0, 1, 0, 1)
        t:SetDesaturated(false)
        if mode ~= "icons" then
            t:Hide()
        elseif m then
            local iconTex = specOn and m.spec and mod.GFSpecIcon and mod.GFSpecIcon(m.cls, m.spec)
            if iconTex then
                t:SetTexture(iconTex)
                t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            elseif square then
                -- square: class color tile
                local cc = C_ClassColor and C_ClassColor.GetClassColor(m.cls)
                if cc then
                    t:SetColorTexture(cc.r * 0.75, cc.g * 0.75, cc.b * 0.75, 1)
                else
                    t:SetColorTexture(0.3, 0.3, 0.3, 1)
                end
            else
                -- the game's class circle
                t:SetAtlas("groupfinder-icon-class-color-" .. m.cls)
            end
            if not iconTex and NEED_ATLAS[m.role] then
                role:SetAtlas(NEED_ATLAS[m.role])
                role:Show()
            end
            if square then
                if bpx > 0 then
                    if bf._key ~= bkey then
                        bf._key = bkey
                        CUI.ApplyBorderStyle(bf, bpx, br, backdrop, bb, 1, btex)
                    end
                    bf:Show()
                end
            elseif iconTex then
                -- round spec icon + ring
                t:AddMaskTexture(region.masks[k])
                t._masked = true
                if bpx > 0 then
                    local ring = region.rings[k]
                    ring:ClearAllPoints()
                    ring:SetPoint("TOPLEFT", t, "TOPLEFT", -bpx, bpx)
                    ring:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", bpx, -bpx)
                    ring:SetColorTexture(br, backdrop, bb, 1)
                    ring:Show()
                end
            end
            t:SetAlpha(1)
            t:Show()
            if crownOn and m.lead then
                region.crowns[k]:Show()
            end
        elseif k <= cap then
            local need = needs[nextNeed]
            nextNeed = nextNeed + 1
            local needTex = need and not blizzMissing and mod.RoleIconTex and mod.RoleIconTex(need)
            if need and blizzMissing then
                -- blizzard style: small grey mark
                t:Hide()
                role:SetAtlas(NEED_ATLAS[need])
                role:SetDesaturated(true)
                role:SetAlpha(0.6)
                role:Show()
            elseif needTex then
                -- small, like blizzard's
                t:Hide()
                role:SetTexture(needTex)
                role:SetAlpha(0.6)
                role:Show()
            else
                t:SetAtlas("groupfinder-icon-emptyslot")
                t:SetAlpha(blizzMissing and 1 or 0.5)
                t:Show()
            end
        else
            t:Hide()
        end
    end
    -- raid role counts, rating to their left
    local counts = mode == "counts" and source.counts(ident)
    if not Readable(counts) then
        counts = nil
    end
    local ellIcons = mod.OwnListGet("missingIcons") == "cludes"
    local round = mod.OwnListGet("iconShape") ~= "square"
    -- round rings sit outside the circle, so the first one steps in like the member icons
    local posX = -(region.pad or 6) - (round and bpx or 0)
    local isz = region.icons[1]:GetWidth() or 16
    local fsz = mod.OwnListSize("scoreSize")
    -- a number above a centred circle needs its height on top: else it goes on the circle
    local inside = (region.layH or isz) < isz + 2 * (fsz + 1)
    for k = 3, 1, -1 do
        local p = region.rr[k]
        local role = RR_ROLES[k]
        local num = counts and counts[role]
        if counts and type(num) == "number" and not Secret(num) then
            -- icon centered, count above
            local c = RR_COLORS[role]
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
            p.bg:SetPoint("RIGHT", region.mid, "RIGHT", posX, 0)
            p.bg:Show()
            CircleEdge(p, round, bpx, br, backdrop, bb, btex, bkey)
            local texture = ellIcons and mod.RoleIconTex and mod.RoleIconTex(role)
            if texture then
                p.icon:SetTexture(texture)
            else
                p.icon:SetAtlas(NEED_ATLAS[role])
            end
            local gsz = math.floor(isz * 0.7 + 0.5)
            p.icon:SetSize(gsz, gsz)
            posX = posX - PlaceCount(p, num, isz, fsz, inside) - 6 - (round and bpx * 2 or 0)
        else
            p.bg:Hide()
            p.icon:Hide()
            p.count:Hide()
            p.ring:Hide()
            p.edge:Hide()
        end
    end
    -- player count: a grey circle with a person, the number above, like the role counts
    local players = mode == "players" and n
    local pc = region.rr[4]
    if type(players) == "number" and not Secret(players) then
        pc.bg:SetColorTexture(PLAYERS_COLOR[1], PLAYERS_COLOR[2], PLAYERS_COLOR[3], 1)
        if round and not pc.masked then
            pc.bg:AddMaskTexture(pc.mask)
            pc.masked = true
        elseif not round and pc.masked then
            pc.bg:RemoveMaskTexture(pc.mask)
            pc.masked = nil
        end
        pc.bg:SetSize(isz, isz)
        pc.bg:ClearAllPoints()
        pc.bg:SetPoint("RIGHT", region.mid, "RIGHT", posX, 0)
        pc.bg:Show()
        CircleEdge(pc, round, bpx, br, backdrop, bb, btex, bkey)
        local gsz = math.floor(isz * 0.7 + 0.5)
        pc.icon:SetTexture(PERSON_TEX)
        pc.icon:SetSize(gsz, gsz)
        posX = posX - PlaceCount(pc, players, isz, fsz, inside) - 6 - (round and bpx * 2 or 0)
    else
        players = nil
        pc.bg:Hide()
        pc.icon:Hide()
        pc.count:Hide()
        pc.ring:Hide()
        pc.edge:Hide()
    end
    if counts or players then
        region.score:ClearAllPoints()
        region.score:SetPoint("RIGHT", region.mid, "RIGHT", posX - 6, 0)
        region.scoreRaid = true
    elseif region.scoreRaid then
        -- the slot showed a raid before: the score goes back beside the icons
        region.scoreRaid = nil
        region.score:ClearAllPoints()
        region.score:SetPoint("RIGHT", region.mid, "RIGHT", region.scoreX or -6, 0)
    end
    if region.stock then
        region.sel:SetShown(selected == ident)
    else
        local ar, ag, ab = Accent()
        region.sel:SetColorTexture(ar, ag, ab, selected == ident and 0.18 or 0)
    end
    if dimmed[ident] then
        region:SetAlpha(0.35)
    else
        region:SetAlpha((st and st ~= STATUS.applied and st ~= STATUS.invited) and 0.5 or 1)
    end
    region:Show()
end

-------------------------------------------------------------------------------
--  settings preview: sample groups drawn by the list's own rows
-------------------------------------------------------------------------------
local PV_W, PV_PAD, PV_MARGIN = 330, 8, 10 -- about the list's row width
local PV_SCALE = 1.3 -- drawn larger than the list, to read the details
local PV_STEP = 0.3 -- a wheel tick, in rows
local PV_DD_W, PV_DD_GAP = 170, 12 -- the preview picker, right of it
local PV_TITLES = {
    groups = CludesUI.L("Group Finder Preview"),
    dungeon = CludesUI.L("Applicant Preview"),
    raid = CludesUI.L("Applicant Preview"),
}
local PV_TITLE = 22 -- the "Group Finder Preview" strip
-- the rows' window keeps one height (two rows at the default height): taller
-- rows get cut off at its bottom, as in the list, and the page never moves.
-- more groups show as rows get shorter
local PV_VIEW_H = 2 * 50 + GAP
-- cludes's own holy paladin in every preview, and two friends' characters
local PV_ELLE, PV_LUELLA, PV_BLOCKJOB = "Ellesm\195\169re", "Luella", "Blockjob"
mod.PreviewElle, mod.PreviewLuella, mod.PreviewBlockjob = PV_ELLE, PV_LUELLA, PV_BLOCKJOB
-- the sample groups. dungeon = index in this season's list, else a raid of that
-- difficulty; specs = members, leader first (made-up names in the tooltip)
local PV = {
    pv1 = {
        name = CludesUI.L("Weekly key, chill run"),
        dungeon = 1,
        style = 2,
        score = 2780,
        age = 420,
        new = true,
        note = CludesUI.L("Know the route, have fun"),
        specs = { { 73, true }, { 64 }, { 260 }, { 102 } },
    },
    pv2 = {
        name = CludesUI.L("Heroic raid, need healers"),
        raid = PLAYER_DIFFICULTY2 or "Heroic",
        style = 3,
        score = 1950,
        age = 1260,
        applied = true,
        specs = {
            { 66, true },
            { 268 },
            { 65, false, PV_ELLE },
            { 105 },
            { 264 },
            { 71 },
            { 72, false, PV_BLOCKJOB },
            { 251 },
            { 252 },
            { 253 },
            { 254 },
            { 62 },
            { 63 },
            { 258 },
            { 262 },
            { 577 },
            { 1467 },
        },
        open = { TANK = 0, HEALER = 3, DAMAGER = 3 },
    },
    pv3 = {
        name = CludesUI.L("Push for the timer, bring lust"),
        dungeon = 2,
        style = 3,
        score = 3120,
        age = 300,
        note = CludesUI.L("Timing it, voice optional"),
        specs = { { 250, true }, { 264 }, { 72, false, PV_BLOCKJOB } },
    },
    pv4 = {
        name = CludesUI.L("Need a tank, fast and clean"),
        dungeon = 3,
        style = 2,
        score = 2450,
        age = 640,
        specs = { { 270, true }, { 70 }, { 253 }, { 1467 } },
    },
    pv5 = {
        name = CludesUI.L("Normal clear, all welcome"),
        raid = PLAYER_DIFFICULTY1 or "Normal",
        style = 1,
        score = 1420,
        age = 900,
        specs = {
            { 73, true },
            { 257, false, PV_LUELLA },
            { 264 },
            { 71 },
            { 254 },
            { 62 },
            { 259 },
            { 102 },
            { 577 },
        },
        open = { TANK = 1, HEALER = 1, DAMAGER = 4 },
    },
    pv6 = {
        name = CludesUI.L("Learning the route, be patient"),
        dungeon = 4,
        style = 1,
        score = 1850,
        age = 180,
        specs = { { 104, true }, { 257, false, PV_LUELLA }, { 265 }, { 63 } },
    },
}
local PV_IDS = { "pv1", "pv2", "pv3", "pv4", "pv5", "pv6" }
local PV_ACT = {} -- activity id -> group id
for i, ident in ipairs(PV_IDS) do
    PV[ident].act = i
    PV_ACT[i] = ident
end
local pv = { dungeons = {} }

-- one of this season's dungeons, for the name and the row art. its keystone
-- activity gives the name the list shows ("... (Mythic Keystone)")
local function PvDungeon(i)
    if pv.dungeons[i] then
        return pv.dungeons[i]
    end
    local CMode = C_ChallengeMode
    local maps = CMode and CMode.GetMapTable and CMode.GetMapTable()
    local name, mapID
    local map = maps and (maps[i] or maps[1])
    if map then
        local n, _, _, _, _, mid = CMode.GetMapUIInfo(map)
        name, mapID = n, mid
    end
    -- names can be missing right after login, so it asks again next paint
    if not name then
        return { full = CludesUI.L("Dungeon") }
    end
    local full
    local acts = mapID and C_LFGList.GetAvailableActivities and C_LFGList.GetAvailableActivities(DUNGEONS)
    for _, act in ipairs(Readable(acts) and acts or {}) do
        local ai = not Secret(act) and C_LFGList.GetActivityInfoTable(act)
        if
            Readable(ai)
            and ai.isMythicPlusActivity
            and ai.mapID == mapID
            and type(ai.fullName) == "string"
        then
            full = ai.fullName
            break
        end
    end
    pv.dungeons[i] = { full = full or (name .. " (" .. CludesUI.L("Mythic Keystone") .. ")"), mapID = mapID }
    return pv.dungeons[i]
end

-- members by role, and what a five-player group still needs
local function PvCounts(g)
    if g.counts then
        return g.counts
    end
    local n = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for _, spec in ipairs(g.specs) do
        local _, _, _, _, role = GetSpecializationInfoByID(spec[1])
        if n[role] then
            n[role] = n[role] + 1
        end
    end
    local open = g.open
        or {
            TANK = math.max(0, 1 - n.TANK),
            HEALER = math.max(0, 1 - n.HEALER),
            DAMAGER = math.max(0, 3 - n.DAMAGER),
        }
    g.counts = {
        TANK = n.TANK,
        HEALER = n.HEALER,
        DAMAGER = n.DAMAGER,
        TANK_REMAINING = open.TANK,
        HEALER_REMAINING = open.HEALER,
        DAMAGER_REMAINING = open.DAMAGER,
    }
    return g.counts
end

local PREVIEW = {
    info = function(ident)
        local g = PV[ident]
        return {
            name = g.name,
            comment = g.note or "",
            activityIDs = { g.act },
            generalPlaystyle = g.style,
            leaderOverallDungeonScore = g.score,
            numMembers = #g.specs,
            isDelisted = false,
        }
    end,
    activity = function(act)
        local g = PV[PV_ACT[act]]
        local DT = Enum.LFGListDisplayType
        if g.dungeon then
            local skinData = PvDungeon(g.dungeon)
            return {
                fullName = skinData.full,
                maxNumPlayers = 5,
                displayType = DT and DT.RoleEnumerate,
                mapID = skinData.mapID,
            }
        end
        return {
            fullName = (RAID or "Raid") .. " (" .. g.raid .. ")",
            maxNumPlayers = 30,
            displayType = DT and DT.RoleCount,
        }
    end,
    player = function(ident, k)
        local s = PV[ident].specs[k]
        if not s then
            return nil
        end
        local _, specInfo, _, _, role, cls = GetSpecializationInfoByID(s[1])
        return { classFilename = cls, specName = specInfo, assignedRole = role, isLeader = s[2] or false }
    end,
    counts = function(ident)
        return PvCounts(PV[ident])
    end,
    appStatus = function(ident)
        return PV[ident].applied and "applied" or "none"
    end,
    signedAt = function(ident)
        if PV[ident].applied then
            return GetTime() - 95
        end
    end,
    -- the first group reads as new
    nameColor = function(ident)
        if PV[ident].new and GFNS.Cfg and GFNS.Cfg().nameColors == true then
            return 0.3, 1, 0.3
        end
    end,
    -- your own realm's tag
    region = function()
        if mod.RegionTagOfName then
            return mod.RegionTagOfName(UnitName("player"))
        end
    end,
    art = function(ident)
        local g = PV[ident]
        local skinData = g.dungeon and PvDungeon(g.dungeon)
        return skinData and skinData.mapID and mod.RowArtForMap and mod.RowArtForMap(skinData.mapID)
    end,
}

-- lays the rows out and fills them; the header height for it
local function PvFit()
    local frame, view = pv.frame, pv.view
    local heading = frame:GetParent()
    local hgt = mod.OwnListRowHeight()
    local mode = pv.mode or "groups"
    pv.title:SetText(PV_TITLES[mode])
    -- applicants: the applicant list draws its samples in the same window
    local apps = mode ~= "groups" and mod.ApplicantPreviewPaint ~= nil
    view:SetShown(not apps)
    pv.appHost:SetShown(apps)
    pv.appHost:SetSize(PV_W, PV_VIEW_H)
    if mod.ApplicantPreviewPaint then
        mod.ApplicantPreviewPaint(pv.appHost, apps and mode or nil, PV_W, PV_VIEW_H)
    end
    -- a fixed width: the list's own only settles once group finder opens
    local rw = PV_W
    local nH = NoteHeight()
    -- the heights first: the scroll stops at the last group
    local sum = -GAP
    for i, ident in ipairs(PV_IDS) do
        local region = pv.rows[i]
        region.noteRoom = NoteText(PREVIEW.info(ident)) and true or nil
        region.pvH = hgt + (region.noteRoom and nH or 0)
        sum = sum + region.pvH + GAP
    end
    pv.maxScroll = math.max(0, sum - PV_VIEW_H)
    pv.scroll = math.max(0, math.min(pv.scroll or 0, pv.maxScroll))
    local posY = -pv.scroll
    for i, ident in ipairs(PV_IDS) do
        local region = pv.rows[i]
        local rh = region.pvH
        -- rows outside the window aren't drawn at all
        if posY + rh > 0 and posY < PV_VIEW_H then
            region:SetSize(rw, rh)
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -posY)
            region.layH = nil -- every paint lays out again
            Layout(region, hgt)
            Fill(region, ident, PREVIEW)
            region:Show()
        else
            region.resultID = nil
            region:Hide()
        end
        posY = posY + rh + GAP
    end
    view:SetSize(rw, PV_VIEW_H)
    -- scroll thumb
    local th = pv.thumb
    if pv.maxScroll > 0 then
        local tH = math.max(12, PV_VIEW_H * PV_VIEW_H / (sum > 0 and sum or 1))
        th:SetHeight(tH)
        th:ClearAllPoints()
        th:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, -(PV_VIEW_H - tH) * (pv.scroll / pv.maxScroll))
        th:Show()
    else
        th:Hide()
    end
    local fw, fh = rw + PV_PAD * 2, PV_PAD + PV_TITLE + PV_VIEW_H + PV_PAD
    frame:SetSize(fw, fh)
    -- the ui's own scale and then some, grown or shrunk with the settings
    -- window's scale, and shrunk only if the panel is narrower
    local hw = heading:GetWidth() or 0
    -- room for the picker on both sides, so the preview stays centered
    local avail = (hw > 0 and hw or pv.hdrW or 600)
        - PV_MARGIN * 2
        - (pv.dd and (PV_DD_W + PV_DD_GAP) * 2 or 0)
    local userScale = (CludesUIDB and CludesUIDB.panelScale) or 1
    local s = UIParent:GetEffectiveScale() / heading:GetEffectiveScale() * PV_SCALE * userScale
    if fw * s > avail then
        s = avail / fw
    end
    frame:SetScale(s)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", heading, "CENTER", 0, 0)
    return math.ceil(fh * s) + PV_MARGIN * 2
end

-- the tooltips' names: the suite's preview roster (CludesUI.PREVIEW_ROSTER,
-- shared with the raid & party frames preview). members take a name of their
-- own class first
local PV_ROSTER = CludesUI.PREVIEW_ROSTER

mod.PreviewRoster = PV_ROSTER -- the applicant preview's names too

local function PvPlayers(ident)
    local entries, used = {}, {}
    local start = (PV[ident].act - 1) * 3 -- groups lead with different names
    local function Take(cls)
        for pass = 1, 2 do
            for i = 0, #PV_ROSTER - 1 do
                local k = (start + i) % #PV_ROSTER + 1
                local e = PV_ROSTER[k]
                if not used[k] and (pass == 2 or e.class == cls) then
                    used[k] = true
                    return e.name
                end
            end
        end
    end
    for _, spec in ipairs(PV[ident].specs) do
        local _, specInfo, _, _, role, cls, className = GetSpecializationInfoByID(spec[1])
        if cls then
            entries[#entries + 1] = {
                assignedRole = role,
                classFilename = cls,
                className = className,
                specName = specInfo,
                isLeader = spec[2] or false,
                name = spec[3] or Take(cls),
            }
        end
    end
    return entries
end

-- a group tooltip from the sample data, its member lines as the list adds them
function mod.OwnListPreviewTip(region)
    local ident = region.resultID
    if not ident then
        return
    end
    local details = PREVIEW.info(ident)
    local ai = PREVIEW.activity(details.activityIDs[1])
    local DT = Enum.LFGListDisplayType
    local enumerate = DT and ai.displayType == DT.RoleEnumerate
    local players = PvPlayers(ident)
    local tipText = GameTooltip
    tipText:SetOwner(region, "ANCHOR_RIGHT", 25, 0)
    tipText:SetText(details.name, 1, 1, 1, 1, true)
    tipText:AddLine(ai.fullName)
    local ps = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. details.generalPlaystyle]
    if ps then
        tipText:AddLine(ps, 0.6, 0.6, 0.6)
    end
    if details.comment ~= "" then
        local fc = LFG_LIST_COMMENT_FONT_COLOR
        tipText:AddLine(
            string.format(LFG_LIST_COMMENT_FORMAT or "%s", details.comment),
            fc and fc.r or 0.6,
            fc and fc.g or 0.6,
            fc and fc.b or 0.6,
            true
        )
    end
    tipText:AddLine(" ")
    local leader = players[1] and players[1].name
    if leader then
        tipText:AddLine(string.format(LFG_LIST_TOOLTIP_LEADER or "Leader: %s", leader))
    end
    local score = details.leaderOverallDungeonScore
    local colour = C_ChallengeMode.GetDungeonScoreRarityColor
        and C_ChallengeMode.GetDungeonScoreRarityColor(score)
    local scoreText = colour and colour:WrapTextInColorCode(score) or tostring(score)
    tipText:AddLine(string.format(DUNGEON_SCORE_LEADER or "Leader's Mythic+ Rating: %s", scoreText))
    tipText:AddLine(string.format(LFG_LIST_TOOLTIP_AGE or "Created %s ago", SecondsToTime(PV[ident].age)))
    tipText:AddLine(" ")
    if enumerate then
        local roleName = { TANK = TANK, HEALER = HEALER, DAMAGER = DAMAGER }
        for _, p in ipairs(players) do
            local cc = RAID_CLASS_COLORS[p.classFilename] or NORMAL_FONT_COLOR
            tipText:AddLine(
                string.format(
                    LFG_LIST_TOOLTIP_CLASS_ROLE or "%s - %s",
                    p.className,
                    roleName[p.assignedRole] or ""
                ),
                cc.r,
                cc.g,
                cc.b
            )
        end
    else
        local n = PREVIEW.counts(ident)
        tipText:AddLine(
            string.format(
                LFG_LIST_TOOLTIP_MEMBERS or "Members: %d (%d/%d/%d)",
                details.numMembers,
                n.TANK,
                n.HEALER,
                n.DAMAGER
            )
        )
    end
    if GFNS.Cfg().classTooltip ~= false and mod.GFTooltipMembers then
        mod.GFTooltipMembers(tipText, players, enumerate)
    end
    tipText:Show()
end

-- the settings page's content header
function mod.OwnListPreviewBuild(heading, hdrW)
    local frame = pv.frame
    if not frame then
        frame = CreateFrame("Frame", nil, heading)
        pv.frame = frame
        local backdrop = frame:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.05, 0.05, 0.05, 0.9)
        CUI.MakeBorder(frame, 0.2, 0.2, 0.2, 1, CUI.PanelPP)
        -- a title like the raid frames' overlay preview
        local title = CUI.MakeFont(frame, 13, nil, 1, 1, 1, 0.9)
        title:SetPoint("TOP", frame, "TOP", 0, -7)
        pv.title = title
        -- the rows' window: what doesn't fit is cut off
        local view = CreateFrame("Frame", nil, frame)
        view:SetPoint("TOPLEFT", frame, "TOPLEFT", PV_PAD, -(PV_PAD + PV_TITLE))
        view:SetClipsChildren(true)
        pv.view = view
        -- the wheel scrolls part of a row at a time: it's drawn larger than the list
        view:EnableMouseWheel(true)
        view:SetScript("OnMouseWheel", function(_, delta)
            local was = pv.scroll or 0
            local step = math.floor((mod.OwnListRowHeight() + GAP) * PV_STEP + 0.5)
            pv.scroll = math.max(0, math.min(was - delta * step, pv.maxScroll or 0))
            if pv.scroll ~= was then
                PvFit()
                -- the hovered row changed under the mouse
                if GameTooltip:IsShown() and GameTooltip:GetOwner() and GameTooltip:GetOwner().preview then
                    GameTooltip:Hide()
                end
            end
        end)
        pv.thumb = view:CreateTexture(nil, "OVERLAY", nil, 7)
        pv.thumb:SetWidth(2)
        pv.thumb:SetColorTexture(1, 1, 1, 0.25)
        pv.thumb:Hide()
        -- the applicant samples' window, in the same spot
        pv.appHost = CreateFrame("Frame", nil, frame)
        pv.appHost:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
        pv.appHost:SetClipsChildren(true)
        pv.appHost:Hide()
        -- groups or applicants, picked right of the preview (the settings page
        -- builds this header, so the options widgets are loaded)
        local dropdown = CUI.BuildDropdownControl(
            heading,
            PV_DD_W,
            heading:GetFrameLevel() + 3,
            { groups = "Groups", dungeon = "Dungeon Applicants", raid = "Raid Applicants" },
            { "groups", "dungeon", "raid" },
            function()
                return pv.mode or "groups"
            end,
            function(val)
                pv.mode = val
                GameTooltip_Hide()
                mod.OwnListPreviewPaint()
            end
        )
        dropdown:SetPoint("LEFT", frame, "RIGHT", PV_DD_GAP, 0)
        pv.dd = dropdown
        pv.rows = {}
        for i = 1, #PV_IDS do
            local region = MakeRow(nil, view)
            region.preview = true
            pv.rows[i] = region
        end
        -- the settings window's scale changed: size it again
        if not CUI._onScaleChanged then
            CUI._onScaleChanged = {}
        end
        CUI._onScaleChanged[#CUI._onScaleChanged + 1] = mod.OwnListPreviewPaint
    else
        frame:SetParent(heading)
        if pv.dd then
            pv.dd:SetParent(heading)
        end
    end
    -- a rebuilt page detaches it first, which can leave it under the window's
    -- drag area, and that would take the hover
    frame:SetFrameLevel(heading:GetFrameLevel() + 2)
    if pv.dd then
        pv.dd:SetFrameLevel(heading:GetFrameLevel() + 3)
        pv.dd:Show()
    end
    pv.hdrW = hdrW
    frame:Show()
    pv.h = PvFit()
    return pv.h
end

-- a display setting changed: draw again (the height only moves with the ui scale)
function mod.OwnListPreviewPaint()
    local frame = pv.frame
    if not (frame and frame:IsVisible()) then
        return
    end
    local hgt = PvFit()
    if hgt ~= pv.h then
        pv.h = hgt
        CUI:SetContentHeaderHeightSilent(hgt)
    end
end

-------------------------------------------------------------------------------
--  the list
-------------------------------------------------------------------------------
local empty, thumb

-- the timers tick only while a row in view shows one
local function SyncTicker()
    if not ticker then
        return
    end
    local any = false
    if isActive then
        for i = 1, #rowList do
            local region = rowList[i]
            if region.signedAt and region:IsShown() then
                any = true
                break
            end
        end
    end
    ticker:SetShown(any)
end

function Paint() -- forward-declared up top
    if not (widget and isActive) then
        return
    end
    local hgt = mod.OwnListRowHeight()
    local height = body:GetHeight() or 0
    -- a group with a note is a line taller
    local nH = NoteHeight()
    local sum = 0
    wipe(tops)
    for i = 1, #isShown do
        tops[i] = sum
        sum = sum + hgt + (noteOf[isShown[i]] and nH or 0) + GAP
    end
    local maxPx = math.max(0, sum - GAP - height)
    scrollPx = math.max(0, math.min(scrollPx, maxPx))
    local first = 1
    while tops[first + 1] and tops[first + 1] <= scrollPx do
        first = first + 1
    end
    local used = 0
    for position = first, #isShown do
        local posY = tops[position] - scrollPx
        if posY >= height then
            break
        end
        used = used + 1
        local region = rowList[used] or MakeRow(used)
        local ident = isShown[position]
        region.noteRoom = noteOf[ident]
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -posY)
        region:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -posY)
        region:SetHeight(hgt + (region.noteRoom and nH or 0))
        Layout(region, hgt)
        Fill(region, ident)
    end
    for i = used + 1, #rowList do
        rowList[i].resultID = nil
        rowList[i]:Hide()
    end
    PaintSignBtn()
    SyncTicker()
    -- scroll thumb
    if maxPx > 0 then
        local share = height / (maxPx + height)
        local th = math.max(16, height * share)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -1, -(height - th) * (scrollPx / maxPx))
        thumb:Show()
    else
        thumb:Hide()
    end
    if SP.searching then
        empty:SetText("") -- blizzard's spinner covers it
    elseif #isShown == 0 then
        local sum = type(SP.results) == "table" and #SP.results or 0
        empty:SetText(
            sum > 0 and CludesUI.Lf("%1$d groups found, none match your filters", sum)
                or CludesUI.L("No groups found")
        )
    else
        empty:SetText("")
    end
end

-- keep blizzard's list hidden while ours shows
local function HoldHidden(frame, a)
    if guard or not isActive or a == 0 then
        return
    end
    guard = true
    frame:SetAlpha(0)
    guard = false
end

-- a hidden sign up status (keys, encounters): our rows couldn't tell if a group can be picked
local function AppSecret(ident)
    local _, status, pending = C_LFGList.GetApplicationInfo(ident)
    return Secret(status) or Secret(pending)
end

-- one result's secrecy, as AnySecret reads the whole list
local function ResultSecret(ident)
    if Secret(ident) or AppSecret(ident) then
        return true
    end
    local details = C_LFGList.GetSearchResultInfo(ident)
    return details ~= nil
        and (not Readable(details) or Secret(details.activityIDs) or Secret(details.isDelisted))
end

local function RowFor(ident)
    for i = 1, #rowList do
        local region = rowList[i]
        if region.resultID == ident and region:IsShown() then
            return region
        end
    end
end

-- the frame after result updates: each changed group repaints its own row.
-- The whole list collects again only when it has to: a group gone secret, one
-- whose filter pass changed, a sort that follows score or size, or a refresh
-- that was asked for
local function Flush()
    flusher:Hide()
    if not isActive then
        wipe(dirty)
        fullDirty = false
        return
    end
    local full = fullDirty
    fullDirty = false
    if not full then
        local gc = GFNS.Cfg and GFNS.Cfg()
        local by = gc and gc.extraSortBy
        full = by == "high" or by == "low" or by == "big" or by == "small"
    end
    if not full then
        local notesOn = mod.OwnListGet("groupNotes")
        for ident in pairs(dirty) do
            if ResultSecret(ident) then
                full = true
                break
            end
            local was = passOf[ident]
            -- a group outside the last collect is not on our list
            if was ~= nil and not isApp[ident] then
                local pass = (not GFNS.ExtraPasses or GFNS.ExtraPasses(ident)) and true or false
                if pass ~= was then
                    full = true
                    break
                end
            end
            -- a listed group's note came or went: its row is a line taller or shorter
            if
                notesOn
                and (isApp[ident] or was == true or dimmed[ident])
                and (NoteText(C_LFGList.GetSearchResultInfo(ident)) ~= nil) ~= (noteOf[ident] == true)
            then
                full = true
                break
            end
        end
    end
    if full then
        wipe(dirty)
        mod.OwnListRefresh()
        return
    end
    for ident in pairs(dirty) do
        local region = RowFor(ident)
        if region then
            Fill(region, ident)
        end
    end
    wipe(dirty)
    PaintSignBtn()
    SyncTicker()
end

local function Build()
    if widget then
        return
    end
    SP = LFGListFrame and LFGListFrame.SearchPanel
    if not (SP and SP.ScrollBox) then
        return
    end
    widget = CreateFrame("Frame", nil, SP)
    -- shown only while active: a first visit to quests or custom never turns it
    -- on, and a shown empty frame there took every click and scroll
    widget:Hide()
    if LFGListSearchPanel_DoSearch then
        hooksecurefunc("LFGListSearchPanel_DoSearch", function()
            wipe(posOf)
            nextPos = 0
            selected = nil
        end)
    end
    widget:SetPoint("TOPLEFT", SP.ScrollBox, "TOPLEFT", 3, 0)
    widget:SetPoint("BOTTOMRIGHT", SP.ScrollBar or SP.ScrollBox, "BOTTOMRIGHT", 0, 0)
    widget:SetFrameLevel(SP.ScrollBox:GetFrameLevel() + 10)
    widget:EnableMouse(true) -- blizzard's hidden rows never get clicks
    widget:EnableMouseWheel(true)
    widget:SetScript("OnMouseWheel", function(_, delta)
        scrollPx = scrollPx - delta * (mod.OwnListRowHeight() + GAP)
        Paint()
    end)
    widget:SetScript("OnSizeChanged", Paint)
    body = CreateFrame("Frame", nil, widget)
    body:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", SP.ScrollBox, "BOTTOMRIGHT", -3, 0)
    body:SetClipsChildren(true)
    empty = widget:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", widget, "TOP", 0, -30)
    thumb = widget:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(1, 1, 1, 0.3)
    -- our sign up button over blizzard's
    local scrollBar = SP.SignUpButton
    if scrollBar then
        local stock = not Skinned()
        signBtn = CreateFrame("Button", nil, SP, stock and "UIPanelButtonTemplate" or nil)
        signBtn:SetAllPoints(scrollBar)
        signBtn:SetFrameLevel(scrollBar:GetFrameLevel() + 5)
        signBtn:SetNormalFontObject("GameFontNormal")
        signBtn:SetHighlightFontObject("GameFontHighlight")
        signBtn:SetDisabledFontObject("GameFontDisable")
        signBtn:SetText(SIGN_UP or "Sign Up")
        signBtn:SetMotionScriptsWhileDisabled(true)
        local skin = CUI._ModuleNS and CUI._ModuleNS.CludesUIBlizzardSkin
        local S = skin and skin.WSkin
        -- stock keeps the template's art
        if not stock and S and S.Button then
            S.Button(signBtn)
        elseif not stock then
            local backdrop = signBtn:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0.06, 0.06, 0.06, 0.95)
            CUI.MakeBorder(signBtn, 0.25, 0.25, 0.25, 1, CUI.PanelPP)
            local highlight = signBtn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.1)
        end
        signBtn:SetScript("OnClick", function()
            SignUp(selected)
        end)
        signBtn:SetScript("OnEnter", function(self)
            if not self.why then
                return
            end
            CUI.ShowWidgetTooltip(self, self.why)
        end)
        signBtn:SetScript("OnLeave", CUI.HideWidgetTooltip)
        signBtn:Hide()
        hooksecurefunc(scrollBar, "SetAlpha", HoldHidden)
    end
    hooksecurefunc(SP.ScrollBox, "SetAlpha", HoldHidden)
    if SP.ScrollBar then
        hooksecurefunc(SP.ScrollBar, "SetAlpha", HoldHidden)
    end
    if SP.SearchingSpinner then
        hooksecurefunc(SP.SearchingSpinner, "SetAlpha", HoldHidden)
    end
    hooksecurefunc("LFGListSearchPanel_UpdateResults", function(panelFrame)
        if panelFrame == SP then
            mod.OwnListRefresh()
        end
    end)
    -- sign up timers tick once a second, just their text, on a frame shown
    -- only while a row in view has one (SyncTicker)
    ticker = CreateFrame("Frame", nil, widget)
    ticker:Hide()
    local tick = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        tick = tick + dt
        if tick < 1 then
            return
        end
        tick = 0
        for i = 1, #rowList do
            local region = rowList[i]
            if region.signedAt and region:IsShown() then
                region.timer:SetText(TimeLeft(region.signedAt))
            end
        end
    end)
    -- result updates gather here and flush once, on the next frame
    flusher = CreateFrame("Frame")
    flusher:Hide()
    flusher:SetScript("OnUpdate", Flush)
    widget:SetScript("OnEvent", function(_, evt, ident)
        if evt == "LFG_LIST_SEARCH_RESULT_UPDATED" then
            -- one group changed; a result can also go secret mid-list
            if type(ident) == "number" and not Secret(ident) then
                dirty[ident] = true
            else
                fullDirty = true
            end
            flusher:Show()
        elseif evt == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
            -- applications reorder the list (applied groups on top)
            fullDirty = true
            flusher:Show()
        else
            PaintSignBtn()
        end
    end)
end

-- any result secret? hand back to blizzard's list
function AnySecret()
    local res = SP and SP.results
    if type(res) ~= "table" then
        return false
    end
    for _, ident in ipairs(res) do
        if Secret(ident) or AppSecret(ident) then
            return true
        end
        local details = C_LFGList.GetSearchResultInfo(ident)
        if
            details and (not Readable(details) or Secret(details.activityIDs) or Secret(details.isDelisted))
        then
            return true
        end
    end
    return false
end

-- the categories our list covers
local OURS = { [DUNGEONS] = true, [RAIDS] = true, [DELVES] = true, [QUESTS] = true, [CUSTOM] = true }

-- ours on those searches with readable results
function mod.OwnListRefresh()
    mod.OwnListPreviewPaint()
    local wanted = mod.OwnListOn()
    if wanted and not widget then
        Build()
    end
    if not widget then
        return
    end
    local category = SP.categoryID
    -- the results are walked for secrecy only where our list could show
    local nowTime = (
        wanted
        and SP:IsVisible()
        and OURS[category]
        and not ((GFNS.ExtraResultsSecret and GFNS.ExtraResultsSecret()) or AnySecret())
    )
            and true
        or false
    if nowTime ~= isActive then
        isActive = nowTime
        local a = isActive and 0 or 1
        guard = true
        SP.ScrollBox:SetAlpha(a)
        if SP.ScrollBar then
            SP.ScrollBar:SetAlpha(a)
        end
        if SP.SearchingSpinner then
            SP.SearchingSpinner:SetAlpha(a)
        end -- its "searching..." sat over our rows
        if signBtn then
            SP.SignUpButton:SetAlpha(a)
        end
        guard = false
        widget:SetShown(isActive)
        if signBtn then
            signBtn:SetShown(isActive)
        end
        if isActive then
            widget:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
            widget:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
            -- keep the sign up button current
            widget:RegisterEvent("GROUP_ROSTER_UPDATE")
            widget:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
            widget:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
            widget:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        else
            widget:UnregisterAllEvents()
            wipe(dirty)
            fullDirty = false
            flusher:Hide()
            -- blizzard's rows were left alone while ours covered them: their look again
            if mod.RedecorateRows then
                mod.RedecorateRows()
            end
        end
    end
    if isActive then
        -- stay over blizzard's faded list and button: if something raises them,
        -- the mouse would go to rows nobody can see
        local lv = SP.ScrollBox:GetFrameLevel() + 10
        if widget:GetFrameLevel() < lv then
            widget:SetFrameLevel(lv)
        end
        if signBtn then
            lv = SP.SignUpButton:GetFrameLevel() + 5
            if signBtn:GetFrameLevel() < lv then
                signBtn:SetFrameLevel(lv)
            end
        end
        Collect()
        Paint()
    end
end

-- our list covers blizzard's (search.lua leaves blizzard's hidden rows alone meanwhile)
function mod.OwnListActive()
    return isActive
end

-- settings reset
function mod.ResetOwnList()
    wipe(DB())
    styleGen = styleGen + 1
    mod.OwnListRefresh()
end

function mod.SetOwnListRowHeight(val)
    DB().rowHeight = val
    mod.OwnListPreviewPaint()
    if isActive then
        Paint()
    end
end

-- filters or display changed: the rows lay out again
GFNS.ExtraRefilter = function()
    styleGen = styleGen + 1
    if isActive or mod.OwnListOn() then
        mod.OwnListRefresh()
    end
end
GFNS.ExtraRedecorate = GFNS.ExtraRefilter

-- menus open: dim ours too
local prevDim = GFNS.ExtraOnDim
GFNS.ExtraOnDim = function(enabled)
    if prevDim then
        prevDim(enabled)
    end
    if widget then
        widget:SetAlpha(enabled and 0.35 or 1)
    end
end

if mod.WhenGroupFinder then
    mod.WhenGroupFinder(function()
        local sp = LFGListFrame and LFGListFrame.SearchPanel
        if sp then
            sp:HookScript("OnShow", function()
                -- a profile switched while the window was closed brings its own sizes
                styleGen = styleGen + 1
                if mod.OwnListOn() then
                    mod.OwnListRefresh()
                end
            end)
        end
    end)
end
