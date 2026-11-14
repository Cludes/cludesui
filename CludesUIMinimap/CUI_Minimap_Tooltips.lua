if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Minimap_Tooltips.lua
--
--  The friends tooltip and the calendar tooltip with its lockout list.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIMinimap.lua or an earlier CUI_Minimap_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local SKIN, GetCustomTooltipScale = Inner.EBS, Inner.GetCustomTooltipScale

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local MO_Evaluate
Inner.moEvaluateSetters[#Inner.moEvaluateSetters + 1] = function(val)
    MO_Evaluate = val
end

-------------------------------------------------------------------------------
--  Friends Online indicator: guild, BNet favorites and BNet/character friends on
--  hover. Zero background work -- all data is read live when the tooltip opens.
-------------------------------------------------------------------------------
local FRIENDS_ATLAS = "housefinder_neighborhood-friends-icon"

local function GatherOnlineFriends()
    local guild, favorites, friends = {}, {}, {}
    local seenBNet = {}
    local myName = UnitName("player")
    -- Notes are stored raw: the tooltip cleans only the rows it shows, and only with Show Notes on.

    if IsInGuild and IsInGuild() then
        local sum = GetNumGuildMembers() or 0
        for i = 1, sum do
            local name, _, _, level, _, zone, publicNote, _, online, _, classFile = GetGuildRosterInfo(i)
            if online and name then
                local short = name:match("^([^%-]+)") or name
                if short ~= myName then
                    -- Fix "Name-Realm-Realm" to "Name-Realm"
                    guild[#guild + 1] = {
                        name = short,
                        full = CludesUI.BuildFullName(name) or name,
                        class = classFile,
                        zone = zone or "",
                        level = level,
                        note = publicNote,
                        kind = "guild",
                    }
                end
            end
        end
    end

    local numBNet = BNGetNumFriends and BNGetNumFriends() or 0
    for i = 1, numBNet do
        local acct = C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(i)
        if acct then
            local gameInfo = acct.gameAccountInfo
            if gameInfo and gameInfo.isOnline and gameInfo.clientProgram == "WoW" then
                local charName = gameInfo.characterName
                local classFile = gameInfo.className and gameInfo.className:upper():gsub(" ", "")
                if gameInfo.classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
                    local ci = C_CreatureInfo.GetClassInfo(gameInfo.classID)
                    if ci and ci.classFile then
                        classFile = ci.classFile
                    end
                end
                local zone = gameInfo.areaName or ""
                -- Fix "Name-Realm-Realm" to "Name-Realm"
                local full = CludesUI.BuildFullName(charName, gameInfo.realmName) or charName
                -- Battle tag without the #discriminator (fall back to accountName/RealID)
                local rawTag = acct.battleTag or acct.accountName
                local tagName = rawTag and rawTag:match("^([^#]+)") or rawTag
                local record = {
                    name = charName or tagName or "???",
                    full = full,
                    class = classFile,
                    zone = zone,
                    level = gameInfo.characterLevel,
                    bnetTag = tagName,
                    bnetName = acct.accountName or acct.battleTag,
                    bnetID = acct.bnetAccountID,
                    isFavorite = acct.isFavorite,
                    note = acct.note,
                    kind = "bnet",
                }
                if charName then
                    seenBNet[charName] = true
                end
                if acct.isFavorite then
                    favorites[#favorites + 1] = record
                else
                    friends[#friends + 1] = record
                end
            end
        end
    end

    -- Character friends, skipping anyone already seen on the BNet list.
    local numChar = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
    for i = 1, numChar do
        local details = C_FriendList.GetFriendInfoByIndex(i)
        if details and details.connected then
            local charName = details.name
            if charName and not seenBNet[charName] then
                friends[#friends + 1] = {
                    name = charName:match("^([^%-]+)") or charName,
                    full = CludesUI.BuildFullName(charName) or charName,
                    class = details.className and details.className:upper():gsub(" ", ""),
                    zone = details.area or "",
                    level = details.level,
                    note = details.notes,
                    kind = "char",
                }
            end
        end
    end

    -- Guild members are removed from the friends lists to avoid duplicates.
    local guildSet = {}
    for _, g in ipairs(guild) do
        guildSet[g.name] = true
    end
    for i = #friends, 1, -1 do
        if guildSet[friends[i].name] then
            table.remove(friends, i)
        end
    end
    for i = #favorites, 1, -1 do
        if guildSet[favorites[i].name] then
            table.remove(favorites, i)
        end
    end

    -- Sort by zone (empty zones last), then name -- groups same-location together
    local function byZone(a, b)
        local az, bz = a.zone or "", b.zone or ""
        if (az == "") ~= (bz == "") then
            return az ~= ""
        end
        if az ~= bz then
            return az < bz
        end
        return (a.name or "") < (b.name or "")
    end
    -- Friends/favorites sort A-Z by battle tag (fall back to name); guild stays grouped by zone
    local function byTag(a, b)
        return (a.bnetTag or a.name or ""):lower() < (b.bnetTag or b.name or ""):lower()
    end
    table.sort(guild, byZone)
    table.sort(favorites, byTag)
    table.sort(friends, byTag)

    return guild, favorites, friends
end

-- Custom two-column friends tooltip (same pattern as the M+ death tooltip). FTT_FONT
-- stays file-scope (shared with the calendar tooltip below); everything else lives
-- in the do-block.
-- Only ShowFriendsTooltip/HideFriendsTooltip are used outside, hence the forward declarations.
local function FTT_FONT()
    return (CludesUI.GetFontPath("minimap")) or CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
end
local ShowFriendsTooltip, HideFriendsTooltip
do
    local _friendsTT
    local _friendsTTRows = {}
    local _friendsTTHeaders = {}
    local _friendsTTDividers = {}
    local FTT_PAD = 8
    local FTT_ROW_H = 14
    local FTT_HDR_H = 16
    local FTT_GAP = 2
    local FTT_DIV_PAD = 5 -- padding above and below the divider line
    local FTT_NOTE_H = 12 -- height of the optional note line under a row
    local FTT_NOTE_INDENT = 8
    local FTT_NOTE_MAX_W = 260 -- longer notes truncate instead of widening the tooltip

    -- The name and note lines show other players' writing: a font family (no
    -- outline, no shadow), so Cyrillic, Korean and Chinese letters draw in the
    -- client's own faces. Every font write to those two strings goes through here.
    local function FTTNameFont(fontStr, dim)
        CludesUI.SetFontFamily(fontStr, FTT_FONT(), dim, "", false)
    end

    -- Hover-stable hide: small grace period so cursor can travel from button to tooltip
    local _fttHideToken = 0
    local _fttMenuOpen = false
    local function CancelFTTHide()
        _fttHideToken = _fttHideToken + 1
    end
    local function ScheduleFTTHide()
        _fttHideToken = _fttHideToken + 1
        if _fttMenuOpen then
            return
        end
        local mine = _fttHideToken
        C_Timer.After(0.15, function()
            if mine ~= _fttHideToken then
                return
            end
            if _fttMenuOpen then
                return
            end
            if _friendsTT then
                _friendsTT:Hide()
            end
        end)
    end

    -- Protected content = anywhere chat/whisper secret values can taint Blizzard's chat
    -- code: a Mythic+ run (entire run), raid combat, rated/instanced PvP. That is exactly
    -- CludesUI.InProtectedInstance(), the canonical CUI guard for taint-sensitive ops.
    -- Whispering is suppressed entirely there; invites stay allowed.
    local function FTTInProtectedContent()
        return CludesUI.InProtectedInstance() or false
    end

    -- Open a whisper. BNet friends go via their Battle.net account (reaches any character/
    -- faction/realm), everyone else by character name. An explicit chat frame skips
    -- ChatFrame_SendTell's FCF_OpenTemporaryWindow path (SetTellTarget/windowList/
    -- MessageEventHandler taint cascade); a "/w" macro can't open the editbox, only send.
    local function FTTOpenWhisper(charName, bnetName)
        -- Suppress whispers in protected content, and while /cuidev is on (it forces the
        -- same secret-value environment as a real Mythic+). InProtectedInstance() itself
        -- reports true in dev mode; the separate branch exists only for the clearer message.
        local blocked
        if CludesUI.IsDevModeActive() then
            blocked = "This action is protected while dev mode (/cuidev) is on."
        elseif FTTInProtectedContent() then
            blocked = "This action is protected in Mythic+ and raid combat."
        end
        if blocked then
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(blocked, 1.0, 0.3, 0.3, 1.0)
            end
            return
        end
        if bnetName and bnetName ~= "" then
            local sendBN = (ChatFrameUtil and ChatFrameUtil.SendBNetTell) or ChatFrame_SendBNetTell
            if sendBN then
                sendBN(bnetName, DEFAULT_CHAT_FRAME)
                return
            end
        end
        if charName and charName ~= "" then
            local sendTell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
            -- Fix "Name-Realm-Realm" to "Name-Realm"
            local targetUnit = CludesUI.BuildFullName(charName) or charName
            if sendTell then
                sendTell(targetUnit, DEFAULT_CHAT_FRAME)
            end
        end
    end

    -- Reusable right-click menu: plain buttons. Whisper -> FTTOpenWhisper (frame-scoped,
    -- no FCF taint); Invite -> C_PartyInfo.InviteUnit (taint-safe, opens no chat window).
    local _fttMenu
    local function GetFTTMenu()
        if _fttMenu then
            return _fttMenu
        end
        local PAD, RH, MW = 4, 18, 96
        local m = CreateFrame("Frame", nil, UIParent)
        m:SetFrameStrata("TOOLTIP")
        m:SetFrameLevel(500)
        m:SetClampedToScreen(true)
        m:EnableMouse(true)
        m:SetSize(MW, PAD * 2 + RH * 2)
        m:Hide()
        local backdrop = m:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.95)
        CludesUI.MakeBorder(m, 1, 1, 1, 0.15, CludesUI.PanelPP)

        local function MakeItem(textValue, yOff, onClick)
            local b = CreateFrame("Button", nil, m)
            b:RegisterForClicks("AnyUp")
            b:SetPoint("TOPLEFT", m, "TOPLEFT", PAD, yOff)
            b:SetPoint("TOPRIGHT", m, "TOPRIGHT", -PAD, yOff)
            b:SetHeight(RH)
            local highlight = b:CreateTexture(nil, "BACKGROUND")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.10)
            highlight:Hide()
            b:SetScript("OnEnter", function()
                highlight:Show()
            end)
            b:SetScript("OnLeave", function()
                highlight:Hide()
            end)
            b:SetScript("OnClick", function()
                onClick(m._target, m._bnet)
                m:Hide()
            end)
            local fontStr = b:CreateFontString(nil, "OVERLAY")
            fontStr:SetFont(FTT_FONT(), 11, "")
            fontStr:SetJustifyH("LEFT")
            fontStr:SetPoint("LEFT", b, "LEFT", 6, 0)
            fontStr:SetText(textValue)
        end

        -- Whisper(charName, bnetName); Invite always uses the character name.
        MakeItem(CludesUI.L("Whisper"), -PAD, FTTOpenWhisper)
        MakeItem(CludesUI.L("Invite"), -PAD - RH, function(targetUnit)
            if targetUnit and targetUnit ~= "" and C_PartyInfo and C_PartyInfo.InviteUnit then
                C_PartyInfo.InviteUnit(CludesUI.BuildFullName(targetUnit) or targetUnit)
            end
        end)

        m:SetScript("OnLeave", function(self)
            if not self:IsMouseOver() then
                self:Hide()
            end
        end)
        m:SetScript("OnHide", function()
            _fttMenuOpen = false
            ScheduleFTTHide()
        end)
        _fttMenu = m
        return m
    end

    local function FTTShowRowMenu(rowBtn)
        local targetUnit = rowBtn and rowBtn._fttTarget
        local bnet = rowBtn and rowBtn._fttBnet
        if (not targetUnit or targetUnit == "") and (not bnet or bnet == "") then
            return
        end
        local m = GetFTTMenu()
        m._target = targetUnit
        m._bnet = bnet
        _fttMenuOpen = true
        CancelFTTHide()
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", rowBtn, "TOPRIGHT", 0, 0)
        m:Show()
    end

    local function GetFriendsTT()
        if _friendsTT then
            return _friendsTT
        end
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("TOOLTIP")
        f:SetFrameLevel(200)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetScript("OnEnter", CancelFTTHide)
        f:SetScript("OnLeave", ScheduleFTTHide)
        f:HookScript("OnHide", function()
            if _fttMenu then
                _fttMenu:Hide()
            end
        end)
        f:Hide()
        local backdrop = f:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.92)
        CludesUI.MakeBorder(f, 1, 1, 1, 0.15, CludesUI.PanelPP)
        -- Hovering this tooltip counts as hovering the extra-button stack (crossing onto it
        -- must not hide them); MO_OverAny reads it via EBS since this local is do-block
        -- scoped. The OnHide hook is required or nothing re-runs the fade-out on close.
        SKIN._friendsTT = f
        f:HookScript("OnShow", function()
            if MO_Evaluate then
                MO_Evaluate()
            end
        end)
        f:HookScript("OnHide", function()
            if MO_Evaluate then
                MO_Evaluate()
            end
        end)
        _friendsTT = f
        return f
    end

    local function EnsureFTTRow(position)
        if _friendsTTRows[position] then
            return _friendsTTRows[position]
        end
        local tt = GetFriendsTT()
        local btn = CreateFrame("Button", nil, tt)
        btn:EnableMouse(true)
        btn:RegisterForClicks("AnyUp")
        btn:SetHeight(FTT_ROW_H)
        local highlight = btn:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)
        highlight:Hide()
        btn._hl = highlight
        btn:SetScript("OnEnter", function(self)
            CancelFTTHide()
            if self._entry then
                self._hl:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            self._hl:Hide()
            ScheduleFTTHide()
        end)
        -- Left-click whispers (frame-scoped, no FCF taint); right-click opens the menu.
        btn:SetScript("OnClick", function(self, mouseButton)
            if not self._entry then
                return
            end
            if mouseButton == "RightButton" then
                FTTShowRowMenu(self)
            elseif mouseButton == "LeftButton" then
                FTTOpenWhisper(self._fttTarget, self._fttBnet)
                CancelFTTHide()
                if _friendsTT then
                    _friendsTT:Hide()
                end
            end
        end)
        -- Name/zone are centred on the first line (not the button), so a note row can grow
        -- the button downward without moving them.
        local nameFS = btn:CreateFontString(nil, "OVERLAY")
        FTTNameFont(nameFS, 10)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetPoint("LEFT", btn, "TOPLEFT", 0, -FTT_ROW_H / 2)
        local zoneFS = btn:CreateFontString(nil, "OVERLAY")
        zoneFS:SetFont(FTT_FONT(), 10, "")
        zoneFS:SetJustifyH("RIGHT")
        zoneFS:SetPoint("RIGHT", btn, "TOPRIGHT", 0, -FTT_ROW_H / 2)
        -- Optional second line: guild/friend note, indented, truncated to the row width.
        -- One line only: a line break inside a note would overlap the rows around it.
        local noteFS = btn:CreateFontString(nil, "OVERLAY")
        FTTNameFont(noteFS, 9)
        noteFS:SetJustifyH("LEFT")
        noteFS:SetWordWrap(false)
        noteFS:SetMaxLines(1)
        noteFS:SetTextColor(0.75, 0.75, 0.75, 0.9)
        noteFS:SetPoint("LEFT", btn, "TOPLEFT", FTT_NOTE_INDENT, -FTT_ROW_H - FTT_NOTE_H / 2)
        noteFS:SetPoint("RIGHT", btn, "TOPRIGHT", 0, -FTT_ROW_H - FTT_NOTE_H / 2)
        noteFS:Hide()
        _friendsTTRows[position] = { button = btn, name = nameFS, zone = zoneFS, note = noteFS }
        return _friendsTTRows[position]
    end

    -- Row targets (read by its OnClick and the menu): target = character name (invite + character whisper), bnet = Battle.net account (preferred for whisper).
    local function FTTSetRowTarget(btn, targetUnit, bnet)
        btn._fttTarget = targetUnit
        btn._fttBnet = bnet
    end

    local function EnsureFTTHeader(position)
        if _friendsTTHeaders[position] then
            return _friendsTTHeaders[position]
        end
        local tt = GetFriendsTT()
        local fontStr = tt:CreateFontString(nil, "OVERLAY")
        fontStr:SetFont(FTT_FONT(), 12, "")
        fontStr:SetJustifyH("CENTER")
        fontStr:SetTextColor(1, 1, 1, 0.9)
        _friendsTTHeaders[position] = fontStr
        return fontStr
    end

    local function EnsureFTTDivider(position)
        if _friendsTTDividers[position] then
            return _friendsTTDividers[position]
        end
        local tt = GetFriendsTT()
        local texture = tt:CreateTexture(nil, "ARTWORK")
        texture:SetColorTexture(1, 1, 1, 0.12)
        local Pix = CludesUI.PP
        if Pix and Pix.Snap then
            texture:SetHeight(Pix.Snap(1))
        else
            texture:SetHeight(1)
        end
        _friendsTTDividers[position] = texture
        return texture
    end

    function ShowFriendsTooltip(anchorFrame)
        CancelFTTHide()
        local guild, favorites, friends = GatherOnlineFriends()
        local tt = GetFriendsTT()
        -- Scale the whole tooltip to the user's Custom Tooltip Size (re-applied each show).
        tt:SetScale(GetCustomTooltipScale())
        local sum = #guild + #favorites + #friends

        local mp = SKIN.db and SKIN.db.profile and SKIN.db.profile.minimap
        local maxRows = mp and tonumber(mp.friendsMaxRows) or 0
        if maxRows and maxRows < 0 then
            maxRows = 0
        end
        -- Hard cap 30 rows per section, even at 0 ("no cap") or stale over-max values -- big guilds otherwise build enormous tooltips. Overflow gets "...and N more".
        if maxRows == 0 or maxRows > 30 then
            maxRows = 30
        end
        local showNotes = mp and mp.friendsShowNotes

        local font = FTT_FONT()
        for i = 1, #_friendsTTRows do
            FTTNameFont(_friendsTTRows[i].name, 10)
            _friendsTTRows[i].zone:SetFont(font, 10, "")
        end
        for i = 1, #_friendsTTHeaders do
            _friendsTTHeaders[i]:SetFont(font, 12, "")
        end

        -- Hide pooled elements and clear stale entry refs.
        for i = 1, #_friendsTTRows do
            local r = _friendsTTRows[i]
            r.name:Hide()
            r.zone:Hide()
            r.note:Hide()
            if r.button then
                r.button:Hide()
                r.button:SetHeight(FTT_ROW_H)
                r.button._entry = nil
                FTTSetRowTarget(r.button, nil)
                if r.button._hl then
                    r.button._hl:Hide()
                end
            end
        end
        for i = 1, #_friendsTTHeaders do
            _friendsTTHeaders[i]:Hide()
        end
        for i = 1, #_friendsTTDividers do
            _friendsTTDividers[i]:Hide()
        end

        if sum == 0 then
            local rowFrame = EnsureFTTRow(1)
            FTTNameFont(rowFrame.name, 10)
            rowFrame.name:SetText(CludesUI.COLOR_CODES.DIM .. CludesUI.L("No friends online") .. "|r")
            rowFrame.zone:SetText("")
            tt:SetSize(FTT_PAD * 2 + 140, FTT_PAD + FTT_ROW_H + FTT_PAD)
            rowFrame.button:ClearAllPoints()
            rowFrame.button:SetPoint("TOPLEFT", tt, "TOPLEFT", FTT_PAD, -FTT_PAD)
            rowFrame.button:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -FTT_PAD, -FTT_PAD)
            rowFrame.button._entry = nil
            FTTSetRowTarget(rowFrame.button, nil)
            rowFrame.button:Show()
            rowFrame.name:Show()
            tt:ClearAllPoints()
            local gpt = SKIN._Grow.edge[SKIN._Grow.Dir()] or SKIN._Grow.edge.left
            tt:SetPoint(gpt[1], anchorFrame, gpt[2], gpt[3], gpt[4])
            tt:Show()
            return sum
        end

        local sections = {}
        if #favorites > 0 then
            sections[#sections + 1] = { title = "Favorites", list = favorites }
        end
        if #guild > 0 then
            sections[#sections + 1] = { title = "Guild", list = guild }
        end
        if #friends > 0 then
            sections[#sections + 1] = { title = "Friends", list = friends }
        end

        local rowIdx = 0
        local hdrIdx = 0
        local divIdx = 0
        local maxNameW, maxZoneW, maxNoteW = 0, 0, 0
        local curY = -FTT_PAD

        for si, sec in ipairs(sections) do
            -- Divider line between sections (not before the first)
            if si > 1 then
                curY = curY - FTT_DIV_PAD
                divIdx = divIdx + 1
                local div = EnsureFTTDivider(divIdx)
                div:ClearAllPoints()
                div:SetPoint("TOPLEFT", tt, "TOPLEFT", FTT_PAD, curY)
                div:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -FTT_PAD, curY)
                div:Show()
                curY = curY - div:GetHeight() - FTT_DIV_PAD
            end

            curY = curY - 5 -- spacing above header
            hdrIdx = hdrIdx + 1
            local heading = EnsureFTTHeader(hdrIdx)
            heading:SetFont(font, 12, "")
            local ac = CludesUI.CLUDES_GREEN or CludesUI._accentColor
            local acHex = ac
                    and format(
                        "%02x%02x%02x",
                        (ac.r or 0.05) * 255,
                        (ac.g or 0.82) * 255,
                        (ac.b or 0.62) * 255
                    )
                or "4cc9f0"
            heading:SetText(CludesUI.L(sec.title) .. " (|cff" .. acHex .. #sec.list .. "|r)")
            heading:ClearAllPoints()
            heading:SetPoint("TOP", tt, "TOP", 0, curY)
            heading:Show()
            curY = curY - FTT_HDR_H - 5 -- spacing below header

            local isShown = #sec.list
            if maxRows > 0 and isShown > maxRows then
                isShown = maxRows
            end
            for i = 1, isShown do
                local e = sec.list[i]
                rowIdx = rowIdx + 1
                local rowFrame = EnsureFTTRow(rowIdx)
                FTTNameFont(rowFrame.name, 10)
                rowFrame.zone:SetFont(font, 10, "")

                local cc = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
                local colored = cc and cc:WrapTextInColorCode(e.name) or e.name
                -- BNet friends: show battle tag before the in-game name, e.g. "Bigmacz (Unholyftw)"
                if e.bnetTag then
                    colored = "|cffffd100" .. e.bnetTag .. "|r (" .. colored .. ")"
                end
                -- Level to the right of the in-game name, e.g. "Unholyftw 80"
                local lvl = tonumber(e.level)
                if lvl and lvl > 0 then
                    colored = colored .. " |cffb0b0b0" .. lvl .. "|r"
                end
                rowFrame.name:SetText(colored)
                rowFrame.name:SetTextColor(1, 1, 1, 0.85)

                local zone = e.zone or ""
                if zone ~= "" then
                    rowFrame.zone:SetText(CludesUI.COLOR_CODES.DIM .. zone .. "|r")
                else
                    rowFrame.zone:SetText("")
                end

                rowFrame.button._entry = e
                FTTSetRowTarget(rowFrame.button, e.full or e.name, e.bnetName)
                rowFrame.button:ClearAllPoints()
                rowFrame.button:SetPoint("TOPLEFT", tt, "TOPLEFT", FTT_PAD, curY)
                rowFrame.button:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -FTT_PAD, curY)
                rowFrame.button:Show()
                rowFrame.name:Show()
                rowFrame.zone:Show()

                local nw = rowFrame.name:GetStringWidth() or 0
                local zw = rowFrame.zone:GetStringWidth() or 0
                if nw > maxNameW then
                    maxNameW = nw
                end
                if zw > maxZoneW then
                    maxZoneW = zw
                end

                local rowH = FTT_ROW_H
                local note = showNotes and CludesUI.StripFriendNoteTag(e.note)
                if note then
                    FTTNameFont(rowFrame.note, 9)
                    rowFrame.note:SetText(note)
                    rowFrame.note:Show()
                    local ntw = rowFrame.note:GetUnboundedStringWidth() or 0
                    if ntw > FTT_NOTE_MAX_W then
                        ntw = FTT_NOTE_MAX_W
                    end
                    if ntw > maxNoteW then
                        maxNoteW = ntw
                    end
                    rowH = FTT_ROW_H + FTT_NOTE_H
                end
                rowFrame.button:SetHeight(rowH)

                curY = curY - (rowH + FTT_GAP)
            end

            if maxRows > 0 and #sec.list > maxRows then
                rowIdx = rowIdx + 1
                local rowFrame = EnsureFTTRow(rowIdx)
                FTTNameFont(rowFrame.name, 10)
                rowFrame.name:SetText(
                    CludesUI.COLOR_CODES.DIM .. CludesUI.Lf("...and %1$d more", #sec.list - maxRows) .. "|r"
                )
                rowFrame.zone:SetText("")
                rowFrame.button._entry = nil
                FTTSetRowTarget(rowFrame.button, nil)
                rowFrame.button:ClearAllPoints()
                rowFrame.button:SetPoint("TOPLEFT", tt, "TOPLEFT", FTT_PAD, curY)
                rowFrame.button:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -FTT_PAD, curY)
                rowFrame.button:Show()
                rowFrame.name:Show()
                curY = curY - (FTT_ROW_H + FTT_GAP)
            end
        end

        local contentW = FTT_PAD + maxNameW + 16 + maxZoneW + FTT_PAD
        local noteW = FTT_PAD + FTT_NOTE_INDENT + maxNoteW + FTT_PAD
        local ttW = math.max(contentW, noteW, 160)
        local ttH = -curY + FTT_PAD

        tt:SetSize(ttW, ttH)
        tt:ClearAllPoints()
        local gpt = SKIN._Grow.edge[SKIN._Grow.Dir()] or SKIN._Grow.edge.left
        tt:SetPoint(gpt[1], anchorFrame, gpt[2], gpt[3], gpt[4])
        tt:Show()
        -- SetClampedToScreen handles off-screen for every Grow direction.
        return sum
    end

    function HideFriendsTooltip()
        ScheduleFTTHide()
    end
end -- friends tooltip do-block

-- Custom calendar tooltip with right-aligned kill counts and server/reset footer.
local _calendarTT
local _calendarTTTitle
local _calendarTTRows = {}
local _calendarTTFooters = {}
local CTT_PAD = 8
local CTT_ROW_H = 14
local CTT_TITLE_H = 16
local CTT_GAP = 6

local function GetCalendarTT()
    if _calendarTT then
        return _calendarTT
    end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(200)
    f:SetClampedToScreen(true)
    f:Hide()
    local backdrop = f:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.92)
    CludesUI.MakeBorder(f, 1, 1, 1, 0.15, CludesUI.PanelPP)
    _calendarTT = f
    return f
end

local function EnsureCalendarTTRow(position)
    if _calendarTTRows[position] then
        return _calendarTTRows[position]
    end
    local tt = GetCalendarTT()
    local leftFS = tt:CreateFontString(nil, "OVERLAY")
    leftFS:SetFont(FTT_FONT(), 10, "")
    leftFS:SetJustifyH("LEFT")
    local rightFS = tt:CreateFontString(nil, "OVERLAY")
    rightFS:SetFont(FTT_FONT(), 10, "")
    rightFS:SetJustifyH("RIGHT")
    _calendarTTRows[position] = { left = leftFS, right = rightFS }
    return _calendarTTRows[position]
end

local function EnsureCalendarTTFooter(position)
    if _calendarTTFooters[position] then
        return _calendarTTFooters[position]
    end
    local tt = GetCalendarTT()
    local leftFS = tt:CreateFontString(nil, "OVERLAY")
    leftFS:SetFont(FTT_FONT(), 10, "")
    leftFS:SetJustifyH("LEFT")
    leftFS:SetTextColor(1, 1, 1, 0.65)
    local rightFS = tt:CreateFontString(nil, "OVERLAY")
    rightFS:SetFont(FTT_FONT(), 10, "")
    rightFS:SetJustifyH("RIGHT")
    rightFS:SetTextColor(1, 1, 1, 0.80)
    _calendarTTFooters[position] = { left = leftFS, right = rightFS }
    return _calendarTTFooters[position]
end

local function EnsureCalendarTTTitle()
    if _calendarTTTitle then
        return _calendarTTTitle
    end
    local tt = GetCalendarTT()
    local fontStr = tt:CreateFontString(nil, "OVERLAY")
    fontStr:SetFont(FTT_FONT(), 12, "")
    fontStr:SetJustifyH("CENTER")
    fontStr:SetTextColor(1, 1, 1, 0.90)
    _calendarTTTitle = fontStr
    return fontStr
end

local function GetServerTimeText()
    local hgt, m = GetGameTime()
    local use24h = GetCVar("timeMgrUseMilitaryTime") == "1"
    if use24h then
        return format("%02d:%02d", hgt, m)
    end
    local ampm = hgt >= 12 and "PM" or "AM"
    hgt = hgt % 12
    if hgt == 0 then
        hgt = 12
    end
    return format("%d:%02d %s", hgt, m, ampm)
end

local function GetWeeklyResetText()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and SecondsToTime then
        local secs = C_DateAndTime.GetSecondsUntilWeeklyReset()
        if secs then
            return SecondsToTime(secs, true, nil, 3)
        end
    end
    return ""
end

local function HideCalendarTooltip()
    if _calendarTT then
        _calendarTT:Hide()
    end
end

local function ShowCalendarTooltip(anchorFrame, lockoutEntries)
    local tt = GetCalendarTT()
    -- Scale the whole tooltip to the user's Custom Tooltip Size (re-applied each show).
    tt:SetScale(GetCustomTooltipScale())
    local font = FTT_FONT()

    for i = 1, #_calendarTTRows do
        _calendarTTRows[i].left:Hide()
        _calendarTTRows[i].right:Hide()
    end
    for i = 1, #_calendarTTFooters do
        _calendarTTFooters[i].left:Hide()
        _calendarTTFooters[i].right:Hide()
    end

    local titleText = EnsureCalendarTTTitle()
    titleText:SetFont(font, 12, "")
    titleText:SetText(CludesUI.L("Calendar"))

    local footerData = {
        { left = CludesUI.L("Server Time"), right = GetServerTimeText() },
        { left = format("%s %s", WEEKLY or "Weekly", RESET or "Reset"), right = GetWeeklyResetText() },
    }

    local maxLeftW, maxRightW = 0, 0
    local curY = -CTT_PAD

    titleText:ClearAllPoints()
    titleText:SetPoint("TOP", tt, "TOP", 0, curY)
    titleText:Show()
    curY = curY - CTT_TITLE_H - CTT_GAP

    for i, record in ipairs(lockoutEntries) do
        local rowFrame = EnsureCalendarTTRow(i)
        rowFrame.left:SetFont(font, 10, "")
        rowFrame.right:SetFont(font, 10, "")
        rowFrame.left:SetText(record.left)
        rowFrame.right:SetText(record.right or "")
        rowFrame.left:ClearAllPoints()
        rowFrame.left:SetPoint("TOPLEFT", tt, "TOPLEFT", CTT_PAD, curY)
        rowFrame.right:ClearAllPoints()
        rowFrame.right:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -CTT_PAD, curY)
        rowFrame.left:Show()
        if record.right and record.right ~= "" then
            rowFrame.right:Show()
        end

        local lw = rowFrame.left:GetStringWidth() or 0
        local rw = rowFrame.right:GetStringWidth() or 0
        if lw > maxLeftW then
            maxLeftW = lw
        end
        if rw > maxRightW then
            maxRightW = rw
        end

        curY = curY - CTT_ROW_H
    end

    curY = curY - CTT_GAP

    for i, fd in ipairs(footerData) do
        local footer = EnsureCalendarTTFooter(i)
        footer.left:SetFont(font, 10, "")
        footer.right:SetFont(font, 10, "")
        footer.left:SetText(fd.left)
        footer.right:SetText(fd.right)
        footer.left:ClearAllPoints()
        footer.left:SetPoint("TOPLEFT", tt, "TOPLEFT", CTT_PAD, curY)
        footer.right:ClearAllPoints()
        footer.right:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -CTT_PAD, curY)
        footer.left:Show()
        footer.right:Show()

        local lw = footer.left:GetStringWidth() or 0
        local rw = footer.right:GetStringWidth() or 0
        if lw > maxLeftW then
            maxLeftW = lw
        end
        if rw > maxRightW then
            maxRightW = rw
        end

        curY = curY - CTT_ROW_H
    end

    local contentW = CTT_PAD + maxLeftW + 16 + maxRightW + CTT_PAD
    local ttW = math.max(contentW, 180)
    local ttH = -curY + CTT_PAD

    tt:SetSize(ttW, ttH)
    tt:ClearAllPoints()
    local gpt = SKIN._Grow.edge[SKIN._Grow.Dir()] or SKIN._Grow.edge.left
    tt:SetPoint(gpt[1], anchorFrame, gpt[2], gpt[3], gpt[4])
    tt:Show()
end

-- Saved instance lockouts for the calendar tooltip: inclusion/tier come from each
-- save's own live data (GetDifficultyInfo flags, encounter counts, DifficultyUtil LFR ids), never hardcoded difficulty ID lists, which rot as Blizzard adds difficulties.
local LOCKOUT_TIER_ORDER = { lfr = 1, normal = 2, heroic = 3, mythic = 4 }

-- Tier string + display label for one saved instance's difficulty.
local function LockoutTierAndLabel(difficulty, fallbackLabel)
    local tier, labelText = "normal", fallbackLabel
    if GetDifficultyInfo and difficulty then
        local d = { GetDifficultyInfo(difficulty) }
        labelText = d[1] or fallbackLabel
        if d[6] then
            tier = "mythic" -- displays as mythic
        elseif d[3] or d[5] then
            tier = "heroic" -- is, or displays as, heroic
        end
    end
    local du = _G.DifficultyUtil
    if du and du.ID and (difficulty == du.ID.RaidLFR or difficulty == du.ID.PrimaryRaidLFR) then
        tier = "lfr"
    end
    return tier, labelText or ""
end

local function GetCalendarLockoutEntries()
    if not GetNumSavedInstances or not GetSavedInstanceInfo then
        return
    end

    if RequestRaidInfo then
        RequestRaidInfo()
    end

    local entries = {}
    for i = 1, GetNumSavedInstances() do
        local name, _, _, difficulty, locked, extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress =
            GetSavedInstanceInfo(i)
        local held = name and (locked or extended)
        -- Dungeon rows only matter when the hold tracks real encounters; raids always show.
        if held and not isRaid and not (numEncounters and numEncounters > 0) then
            held = false
        end
        if held then
            local tier, diffLabel = LockoutTierAndLabel(difficulty, difficultyName)

            local rightText = diffLabel
            if numEncounters and numEncounters > 0 and encounterProgress and encounterProgress >= 0 then
                rightText = format("%s %d/%d", diffLabel, encounterProgress, numEncounters)
            end
            entries[#entries + 1] = {
                name = name,
                tierOrder = LOCKOUT_TIER_ORDER[tier] or LOCKOUT_TIER_ORDER.normal,
                left = name,
                right = rightText,
            }
        end
    end

    if #entries == 0 then
        return
    end

    table.sort(entries, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.tierOrder < b.tierOrder
    end)
    return entries
end

Inner.FRIENDS_ATLAS, Inner.GetCalendarLockoutEntries = FRIENDS_ATLAS, GetCalendarLockoutEntries
Inner.HideCalendarTooltip, Inner.HideFriendsTooltip = HideCalendarTooltip, HideFriendsTooltip
Inner.ShowCalendarTooltip, Inner.ShowFriendsTooltip = ShowCalendarTooltip, ShowFriendsTooltip
Inner.broken = false
