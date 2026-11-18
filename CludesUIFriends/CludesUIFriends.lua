if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIFriends.lua -- Friends List skin. Direct skin of Blizzard's
--  native ScrollBox and buttons: no custom DataProvider, no friend groups.
-------------------------------------------------------------------------------
local ADDON_NAME = ...
if
    not (
        CludesUI
        and CludesUI._ModuleNS
        and CludesUI.NewCombatQueue
        and CludesUI.FriendsKit
        and CludesUI.NewFrameData
        and CludesUI.SetFontFamily
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (friends' names and notes take the parent's font families)
local mod = select(2, ...)
CludesUI._ModuleNS[ADDON_NAME] = mod -- LOD options files read this module ns via the registry
mod.CombatQueue = CludesUI.NewCombatQueue(CreateFrame("Frame"))

local SKIN = CludesUI.Lite.NewAddon("CludesUIFriends")

local Pix = CludesUI.PP

local ACC = CludesUI.CLUDES_GREEN

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD, GetFFD = CludesUI.NewFrameData()

-- Master kill-switch for modules held back from public release (Coming Soon), keyed by
-- module name; overrides that module's "enabled" flag to off regardless of the user's SavedVariables.
local TEMP_DISABLED = {}
_G._CUBS_TEMP_DISABLED = TEMP_DISABLED

local defaultSet = {
    profile = {
        friends = {
            enabled = true,
            scale = 1,
            position = nil,
            bgR = 0.05,
            bgG = 0.05,
            bgB = 0.055,
            bgAlpha = 1,
            tileR = 0,
            tileG = 0,
            tileB = 0,
            tileAlpha = 0.35,
            showBorder = true,
            borderSize = 1,
            borderR = 0,
            borderG = 0,
            borderB = 0,
            borderA = 1,
            useClassColor = false,
            useAccentTab = true,
            showClassIcons = true,
            iconStyle = "modern",
            classColorNames = true,
            nameColorR = 0.863,
            nameColorG = 0.820,
            nameColorB = 0.565,
            accentColors = true,
            factionBanners = false,
            showRegionIcons = true,
            -- Style page (reload-gated): Blizzard Style / Classic WoW UI
            useBlizzardStyle = false,
            useClassicStyle = false,
            autoAcceptFriendInvites = false,
            autoAcceptGuildInvites = false,
            showOffline = true,
            visibility = "always",
            visOnlyInstances = false,
            visHideHousing = false,
            visHideMounted = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
        },
    },
}

-------------------------------------------------------------------------------
--  Utility
-------------------------------------------------------------------------------
local function GetBorderColor(conf)
    if conf.useClassColor then
        return ACC.r, ACC.g, ACC.b, 1
    end
    return conf.borderR, conf.borderG, conf.borderB, conf.borderA or 1
end

-- Legacy FriendsFrame stays loaded-but-hidden under the Social UI; skinning it
-- re-anchors Blizzard scroll boxes and hooks mouse wheel, tainting Battle.net
-- whisper handling (SetTellTarget on a secret target) -- so the skin stays off
-- there; checked live since the switch can flip mid-session.
local function LegacyFriendsRetired()
    -- The Style page's stock styles keep Blizzard's own friends window on
    -- either path, so the legacy skin stands down for them too.
    local mns = CludesUI._ModuleNS[ADDON_NAME]
    if mns and mns.FR_Style and mns.FR_Style() ~= "cui" then
        return true
    end
    if not (C_SocialUI and C_SocialUI.IsSystemEnabled) then
        return false
    end
    local success, enabled = pcall(C_SocialUI.IsSystemEnabled)
    return success and enabled == true
end

-------------------------------------------------------------------------------
--  Combat safety
-------------------------------------------------------------------------------
local ApplyAll -- forward declaration

-- Keyed queue entry: repeat requests before regen collapse into one apply.
local function QueueApplyAll()
    mod.CombatQueue.Defer("ApplyAll", ApplyAll)
end

local function StripTextures(frame)
    if not frame then
        return
    end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local regionFrame = regions[i]
        if regionFrame:IsObjectType("Texture") then
            regionFrame:SetAlpha(0)
        end
    end
end

-------------------------------------------------------------------------------
--  Raid Tab Skinning
-------------------------------------------------------------------------------
-- NEVER CreateTexture/CreateFrame/PP.CreateBorder on any frame in the RaidFrame
-- tree -- permanently taints it, breaking ClaimRaidFrame -> RaidFrame:SetParent().
-- Safe: SetTexture(""), FontString font/color, HookScript, BackdropTemplateMixin.

local function SkinRaidRoleIcon(iconTex)
    -- No-op: CreateTexture on protected parent taints
end

local function SkinRaidTabButton(button)
    if not button or GetFFD(button).btnSkinned then
        return
    end
    GetFFD(button).btnSkinned = true
    local fontFile = CludesUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    local regions = { button:GetRegions() }
    for i = 1, #regions do
        local regionFrame = regions[i]
        if regionFrame and regionFrame:IsObjectType("Texture") then
            regionFrame:SetTexture("")
            regionFrame:SetAlpha(0)
        end
    end
    if button.SetNormalTexture then
        button:SetNormalTexture("")
    end
    if button.SetPushedTexture then
        button:SetPushedTexture("")
    end
    if button.SetHighlightTexture then
        button:SetHighlightTexture("")
    end
    if button.SetDisabledTexture then
        button:SetDisabledTexture("")
    end
    local nt = button.GetNormalTexture and button:GetNormalTexture()
    if nt then
        nt:SetTexture("")
        nt:SetAlpha(0)
    end
    local pt = button.GetPushedTexture and button:GetPushedTexture()
    if pt then
        pt:SetTexture("")
        pt:SetAlpha(0)
    end
    local ht = button.GetHighlightTexture and button:GetHighlightTexture()
    if ht then
        ht:SetTexture("")
        ht:SetAlpha(0)
    end
    local dt = button.GetDisabledTexture and button:GetDisabledTexture()
    if dt then
        dt:SetTexture("")
        dt:SetAlpha(0)
    end
    if button.Left then
        button.Left:SetAlpha(0)
    end
    if button.Right then
        button.Right:SetAlpha(0)
    end
    if button.Middle then
        button.Middle:SetAlpha(0)
    end
    if BackdropTemplateMixin then
        Mixin(button, BackdropTemplateMixin)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        button:SetBackdropColor(0.025, 0.035, 0.045, 0.92)
        button:SetBackdropBorderColor(1, 1, 1, 0.4)
    end
    local textValue = button:GetFontString()
    if textValue then
        textValue:SetFont(fontFile, 9, "")
        textValue:SetTextColor(1, 1, 1, 0.5)
        textValue:ClearAllPoints()
        textValue:SetPoint("CENTER", button, "CENTER", 0, 0)
    end
    button:HookScript("OnEnter", function()
        local region, g, b, a1, a2 = 1, 1, 1, 0.7, 0.6
        if GetFFD(button).accent then
            region, g, b = ACC.r, ACC.g, ACC.b
            a1, a2 = 1, 0.8
        end
        if textValue then
            textValue:SetTextColor(region, g, b, a1)
        end
        if button.SetBackdropBorderColor then
            button:SetBackdropBorderColor(region, g, b, a2)
        end
    end)
    button:HookScript("OnLeave", function()
        local region, g, b, a1, a2 = 1, 1, 1, 0.5, 0.4
        if GetFFD(button).accent then
            region, g, b = ACC.r, ACC.g, ACC.b
            a1, a2 = 0.7, 0.5
        end
        if textValue then
            textValue:SetTextColor(region, g, b, a1)
        end
        if button.SetBackdropBorderColor then
            button:SetBackdropBorderColor(region, g, b, a2)
        end
    end)
end

local RAID_TAB_BUTTONS = {
    "RaidFrameConvertToRaidButton",
    "RaidFrameRaidInfoButton",
    "QuickJoinFrame.JoinQueueButton",
}

local function SkinCheckbox(checkbox)
    if not checkbox or GetFFD(checkbox).skinned then
        return
    end
    GetFFD(checkbox).skinned = true
    local fontFile = CludesUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    if checkbox.SetNormalTexture then
        checkbox:SetNormalTexture("")
    end
    if checkbox.SetPushedTexture then
        checkbox:SetPushedTexture("")
    end
    if checkbox.SetHighlightTexture then
        checkbox:SetHighlightTexture("")
    end
    if checkbox.SetDisabledTexture then
        checkbox:SetDisabledTexture("")
    end
    local regions = { checkbox:GetRegions() }
    for i = 1, #regions do
        local regionFrame = regions[i]
        if regionFrame and regionFrame:IsObjectType("Texture") then
            regionFrame:SetTexture("")
        end
    end
    local textValue = checkbox.Text
        or checkbox.text
        or (checkbox.GetName and _G[checkbox:GetName() .. "Text"])
    if textValue and textValue.SetFont then
        textValue:SetFont(fontFile, 10, "")
        textValue:SetTextColor(1, 1, 1, 0.8)
    end
end

local function SkinRaidGroup(set)
    if not set or GetFFD(set).skinned then
        return
    end
    GetFFD(set).skinned = true
    local fontFile = CludesUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    local ar, ag, ab = ACC.r, ACC.g, ACC.b
    local groupName = set:GetName()
    local regions = { set:GetRegions() }
    for i = 1, #regions do
        local regionFrame = regions[i]
        if regionFrame and regionFrame:IsObjectType("Texture") then
            regionFrame:SetTexture("")
        end
    end
    if BackdropTemplateMixin then
        Mixin(set, BackdropTemplateMixin)
        set:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        set:SetBackdropColor(0.025, 0.025, 0.03, 0.98)
        set:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
    end
    local labelFrame = _G[groupName .. "Label"]
    if labelFrame then
        local regions2 = { labelFrame:GetRegions() }
        for i = 1, #regions2 do
            local regionFrame = regions2[i]
            if regionFrame and regionFrame:IsObjectType("FontString") then
                CludesUI.PrimeFontShadow(regionFrame, true)
                regionFrame:SetFont(fontFile, 10, "")
                regionFrame:SetTextColor(ar, ag, ab, 1)
            end
        end
        local fontString = labelFrame.GetFontString and labelFrame:GetFontString()
        if fontString and fontString.SetFont then
            CludesUI.PrimeFontShadow(fontString, true)
            fontString:SetFont(fontFile, 10, "")
            fontString:SetTextColor(ar, ag, ab, 1)
        end
    end
end

local function SkinRaidSlot(slot)
    if not slot or GetFFD(slot).skinned then
        return
    end
    GetFFD(slot).skinned = true
    local fontFile = CludesUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    local regions = { slot:GetRegions() }
    for i = 1, #regions do
        local regionFrame = regions[i]
        if regionFrame and regionFrame:IsObjectType("Texture") then
            regionFrame:SetTexture("")
        end
    end
    if BackdropTemplateMixin then
        Mixin(slot, BackdropTemplateMixin)
        slot:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        slot:SetBackdropColor(0.045, 0.045, 0.05, 0.9)
        slot:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.7)
    end
    local regions2 = { slot:GetRegions() }
    for i = 1, #regions2 do
        local regionFrame = regions2[i]
        if regionFrame and regionFrame:IsObjectType("FontString") then
            regionFrame:SetFont(fontFile, 9, "")
        end
    end
    slot:HookScript("OnEnter", function()
        if slot.SetBackdropColor then
            slot:SetBackdropColor(0.07, 0.07, 0.08, 0.95)
        end
    end)
    slot:HookScript("OnLeave", function()
        if slot.SetBackdropColor then
            slot:SetBackdropColor(0.045, 0.045, 0.05, 0.9)
        end
    end)
end

local function SkinRaidGroupButton(button)
    if not button or GetFFD(button).skinned then
        return
    end
    GetFFD(button).skinned = true
    local fontFile = CludesUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    local regions = { button:GetRegions() }
    for i = 1, #regions do
        local regionFrame = regions[i]
        if regionFrame and regionFrame:IsObjectType("Texture") then
            regionFrame:SetTexture("")
        end
    end
    if BackdropTemplateMixin then
        Mixin(button, BackdropTemplateMixin)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        button:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
        button:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
    end
    -- The member's name takes the font as a font family (it draws the scripts the
    -- font lacks), with the drop shadow its template font gives it
    local btnName = button.GetName and button:GetName()
    local nameFS = btnName and _G[btnName .. "Name"]
    local regions2 = { button:GetRegions() }
    for i = 1, #regions2 do
        local regionFrame = regions2[i]
        if regionFrame and regionFrame:IsObjectType("FontString") then
            if regionFrame == nameFS then
                CludesUI.SetFontFamily(regionFrame, fontFile, 9, "", true)
            else
                regionFrame:SetFont(fontFile, 9, "")
            end
        end
    end
    button:HookScript("OnEnter", function()
        if button.SetBackdropColor then
            button:SetBackdropColor(0.1, 0.1, 0.12, 1)
        end
    end)
    button:HookScript("OnLeave", function()
        if button.SetBackdropColor then
            button:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
        end
    end)
end

local function SkinRaidInfoFrame()
    -- Intentionally left unstyled (Blizzard default)
end

local function SkinRaidTab()
    for _, name in ipairs(RAID_TAB_BUTTONS) do
        local button
        if name:find("%.") then
            local parts = { strsplit(".", name) }
            button = _G[parts[1]]
            for i = 2, #parts do
                if button then
                    button = button[parts[i]]
                end
            end
        else
            button = _G[name]
        end
        if button then
            SkinRaidTabButton(button)
        end
    end
    for i = 1, 40 do
        local playerBtn = _G["RaidGroupButton" .. i]
        if playerBtn then
            SkinRaidGroupButton(playerBtn)
        end
    end
    for i = 1, 8 do
        local groupFrame = _G["RaidGroup" .. i]
        if groupFrame then
            SkinRaidGroup(groupFrame)
            for jdx = 1, 5 do
                local slot = _G["RaidGroup" .. i .. "Slot" .. jdx]
                if slot then
                    SkinRaidSlot(slot)
                end
            end
        end
    end
    local raidFrame = _G.RaidFrame
    if raidFrame then
        local children = { raidFrame:GetChildren() }
        for i = 1, #children do
            local childFrame = children[i]
            if childFrame then
                local regions = { childFrame:GetRegions() }
                for jdx = 1, #regions do
                    local regionFrame = regions[jdx]
                    if regionFrame and regionFrame:IsObjectType("Texture") then
                        local texture = regionFrame:GetTexture()
                        if texture and type(texture) == "string" then
                            local texLower = texture:lower()
                            if
                                texLower:find("role")
                                or texLower:find("tank")
                                or texLower:find("healer")
                                or texLower:find("dps")
                                or texLower:find("damager")
                            then
                                SkinRaidRoleIcon(regionFrame)
                            end
                        end
                    end
                end
            end
        end
    end
    SkinRaidInfoFrame()

    if raidFrame and not GetFFD(raidFrame).borderAdded then
        GetFFD(raidFrame).borderAdded = true
        if BackdropTemplateMixin then
            Mixin(raidFrame, BackdropTemplateMixin)
            raidFrame:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            raidFrame:SetBackdropBorderColor(1, 1, 1, 0.1)
        end
    end

    local inMplus2 = C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    local _, iType2 = IsInInstance()
    local inPvP2 = (iType2 == "pvp" or iType2 == "arena")
    if InCombatLockdown() or inMplus2 or inPvP2 then
        return
    end

    if raidFrame then
        raidFrame:ClearAllPoints()
        raidFrame:SetPoint("TOPLEFT", FriendsFrame, "TOPLEFT", 15, -76)
        raidFrame:SetPoint("BOTTOMRIGHT", FriendsFrame, "BOTTOMRIGHT", -15, 35)
    end

    local convertBtn = _G.RaidFrameConvertToRaidButton
    local raidInfoBtn = _G.RaidFrameRaidInfoButton
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if scrollBox and (convertBtn or raidInfoBtn) then
        local btnW = math.floor(raidFrame:GetWidth() / 3)
        if convertBtn then
            convertBtn:ClearAllPoints()
            convertBtn:SetSize(btnW, 22)
            convertBtn:SetPoint("BOTTOMRIGHT", scrollBox, "BOTTOMRIGHT", 0, -22)
        end
        if raidInfoBtn then
            raidInfoBtn:ClearAllPoints()
            raidInfoBtn:SetSize(btnW, 20)
            raidInfoBtn:SetPoint("TOPRIGHT", scrollBox, "TOPRIGHT", 0, 48)
        end
    end

    local checkBtn = _G.RaidFrameAllAssistCheckButton
    if checkBtn and not GetFFD(checkBtn).shifted then
        GetFFD(checkBtn).shifted = true
        local p1, rel, p2, ox, oy = checkBtn:GetPoint(1)
        if p1 then
            checkBtn:SetPoint(p1, rel, p2, (ox or 0) - 62, (oy or 0) + 59)
        end
    end
    if raidFrame then
        local roleCount = raidFrame.RoleCount
        if roleCount and not GetFFD(roleCount).shifted then
            GetFFD(roleCount).shifted = true
            local p1, rel, p2, ox, oy = roleCount:GetPoint(1)
            if p1 then
                roleCount:SetPoint(p1, rel, p2, (ox or 0) - 62, (oy or 0) + 59)
            end
        end
    end

    if raidFrame then
        local groupW = math.floor((raidFrame:GetWidth() - 10) / 2)
        for i = 1, 8 do
            local gf = _G["RaidGroup" .. i]
            if gf then
                gf:ClearAllPoints()
                gf:SetWidth(groupW)
                for jdx = 1, 5 do
                    local slot = _G["RaidGroup" .. i .. "Slot" .. jdx]
                    if slot then
                        slot:SetWidth(groupW - 6)
                    end
                end
                if i == 1 then
                    gf:SetPoint("TOPLEFT", raidFrame, "TOPLEFT", 0, 0)
                elseif i == 2 then
                    gf:SetPoint("TOPRIGHT", raidFrame, "TOPRIGHT", 0, 0)
                elseif i % 2 == 1 then
                    local above = _G["RaidGroup" .. (i - 2)]
                    if above then
                        gf:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -14)
                    end
                else
                    local above = _G["RaidGroup" .. (i - 2)]
                    if above then
                        gf:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -14)
                    end
                end
            end
        end
        for i = 1, 40 do
            local button = _G["RaidGroupButton" .. i]
            if button then
                button:SetWidth(groupW - 6)
            end
        end
    end
end

local function UpdateRaidTabButtonAccent()
    local fp = SKIN.db and SKIN.db.profile and SKIN.db.profile.friends
    if not fp then
        return
    end
    local useAccent = fp.accentColors ~= false
    for _, name in ipairs(RAID_TAB_BUTTONS) do
        local button
        if name:find("%.") then
            local parts = { strsplit(".", name) }
            button = _G[parts[1]]
            for i = 2, #parts do
                if button then
                    button = button[parts[i]]
                end
            end
        else
            button = _G[name]
        end
        if button and GetFFD(button).btnSkinned then
            local textValue = button:GetFontString()
            GetFFD(button).accent = useAccent
            if useAccent then
                if textValue then
                    textValue:SetTextColor(ACC.r, ACC.g, ACC.b, 0.7)
                end
                if button.SetBackdropBorderColor then
                    button:SetBackdropBorderColor(ACC.r, ACC.g, ACC.b, 0.5)
                end
            else
                if textValue then
                    textValue:SetTextColor(1, 1, 1, 0.5)
                end
                if button.SetBackdropBorderColor then
                    button:SetBackdropBorderColor(1, 1, 1, 0.4)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Friends List Skin
-------------------------------------------------------------------------------
local friendsSkinned = false

-- The class icon sprites, the status orb art and the region icon button come
-- from the friends kit (CludesUI_FriendsKit.lua), shared with the tiles.
local FriendsKit = CludesUI.FriendsKit
local CLASS_SPRITE_COORDS = CludesUI.CLASS_ICON_SPRITE_COORDS

-- Filled on demand for displayed rows; only search needs the complete list.
-- BNet keyed [id], WoW [id+10000].
local _friendCache = {}
local _FC_WOW_OFFSET = 10000
local _friendCacheDirty = true
local _friendCacheComplete = false

local function ResetFriendCacheIfDirty()
    if not _friendCacheDirty then
        return
    end
    wipe(_friendCache)
    _friendCacheDirty = false
    _friendCacheComplete = false
end

local function GetCachedFriendInfo(btnFrame)
    if not btnFrame or not btnFrame.buttonType or not btnFrame.id then
        return nil, nil
    end
    ResetFriendCacheIfDirty()
    local key
    if btnFrame.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        key = btnFrame.id
    elseif btnFrame.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        key = btnFrame.id + _FC_WOW_OFFSET
    end
    if not key then
        return nil, nil
    end
    local cached = _friendCache[key]
    if cached then
        if btnFrame.buttonType == FRIENDS_BUTTON_TYPE_BNET then
            return cached, nil
        else
            return nil, cached
        end
    end
    -- Read only the friend needed by this row.
    if btnFrame.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        local details = C_BattleNet and C_BattleNet.GetFriendAccountInfo(btnFrame.id)
        if details then
            _friendCache[btnFrame.id] = details
        end
        return details, nil
    elseif btnFrame.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local details = C_FriendList and C_FriendList.GetFriendInfoByIndex(btnFrame.id)
        if details then
            _friendCache[btnFrame.id + _FC_WOW_OFFSET] = details
        end
        return nil, details
    end
    return nil, nil
end

local function RefreshFriendCache()
    ResetFriendCacheIfDirty()
    if _friendCacheComplete then
        return
    end
    local numBNet = BNGetNumFriends and BNGetNumFriends() or 0
    for i = 1, numBNet do
        if not _friendCache[i] then
            local details = C_BattleNet and C_BattleNet.GetFriendAccountInfo(i)
            if details then
                _friendCache[i] = details
            end
        end
    end
    local numWoW = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
    for i = 1, numWoW do
        if not _friendCache[i + _FC_WOW_OFFSET] then
            local details = C_FriendList.GetFriendInfoByIndex(i)
            if details then
                _friendCache[i + _FC_WOW_OFFSET] = details
            end
        end
    end
    _friendCacheComplete = true
end

local function GetFriendClassFile(bnetInfo, wowInfo)
    if bnetInfo and bnetInfo.gameAccountInfo then
        local gi = bnetInfo.gameAccountInfo
        if gi.classID and gi.classID > 0 then
            local _, class = GetClassInfo(gi.classID)
            return class
        end
        if gi.className then
            return CludesUI.ClassTokenFromLocalized(gi.className)
        end
    elseif wowInfo and wowInfo.className then
        return CludesUI.ClassTokenFromLocalized(wowInfo.className)
    end
    return nil
end

local OFFLINE_ICON = "Interface\\AddOns\\CludesUI\\media\\friends\\offline.png"

local function UpdateClassIcon(btnFrame, bnetInfo, wowInfo)
    if btnFrame.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then
        return
    end
    if not btnFrame.buttonType then
        return
    end

    local p = SKIN.db.profile.friends

    local gameIcon = btnFrame.gameIcon
    if gameIcon then
        gameIcon:SetAlpha(0)
    end

    if not p.showClassIcons then
        if GetFFD(btnFrame).classIcon then
            GetFFD(btnFrame).classIcon:Hide()
        end
        return
    end

    if not GetFFD(btnFrame).classIcon then
        GetFFD(btnFrame).classIcon = btnFrame:CreateTexture(nil, "ARTWORK", nil, 2)
    end
    local iconTex = GetFFD(btnFrame).classIcon
    local hgt = btnFrame:GetHeight() - 4
    if hgt <= 0 then
        iconTex:Hide()
        return
    end

    local state = "offline"
    if bnetInfo and bnetInfo.gameAccountInfo then
        local gi = bnetInfo.gameAccountInfo
        if gi.isOnline then
            if gi.clientProgram == BNET_CLIENT_WOW and (gi.wowProjectID == 1 or gi.wowProjectID == nil) then
                state = "retail"
            else
                state = "other_game"
            end
        end
    elseif wowInfo then
        state = wowInfo.connected and "retail" or "offline"
    end

    iconTex:ClearAllPoints()

    if state == "retail" then
        local inset = math.floor(hgt * 0.025 + 0.5)
        iconTex:SetPoint("LEFT", btnFrame, "LEFT", 4, 0)
        iconTex:SetPoint("TOP", btnFrame, "TOP", 0, -(2 + inset))
        iconTex:SetPoint("BOTTOM", btnFrame, "BOTTOM", 0, 2 + inset)
        local iconH = hgt - inset * 2
        if iconH > 0 then
            iconTex:SetWidth(iconH)
        end

        local class = GetFriendClassFile(bnetInfo, wowInfo)
        if not class then
            iconTex:Hide()
            return
        end

        local style = p.iconStyle or "modern"
        if style == "blizzard" then
            iconTex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
            if coords then
                iconTex:SetTexCoord(unpack(coords))
            end
        else
            local coords = CLASS_SPRITE_COORDS[class]
            if coords then
                iconTex:SetTexture(FriendsKit.ClassIconSprite(style))
                iconTex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
        end
        iconTex:SetDesaturated(false)
        iconTex:SetAlpha(1)
    elseif state == "other_game" then
        local smallH = math.floor(hgt * 0.75)
        iconTex:SetSize(smallH, smallH)
        iconTex:SetPoint("LEFT", btnFrame, "LEFT", 4 + math.floor((hgt - smallH) / 2), 0)
        if gameIcon then
            local texture = gameIcon:GetTexture()
            if texture then
                iconTex:SetTexture(texture)
                iconTex:SetTexCoord(0, 1, 0, 1)
            end
        end
        iconTex:SetDesaturated(false)
        iconTex:SetAlpha(1)
    else -- offline
        local smallH = math.floor(hgt * 0.75)
        iconTex:SetSize(smallH, smallH)
        iconTex:SetPoint("LEFT", btnFrame, "LEFT", 4 + math.floor((hgt - smallH) / 2), 0)
        iconTex:SetTexture(OFFLINE_ICON)
        iconTex:SetTexCoord(0, 1, 0, 1)
        iconTex:SetDesaturated(false)
        iconTex:SetAlpha(0.5)
    end

    iconTex:Show()
end

-- Class color escape per class file (lazy-built cache, CludesUI_FriendsKit.lua)
local _getClassColorCode = CludesUI.FriendsKit.ClassColorCode

local function UpdateNameColor(btnFrame, bnetInfo, wowInfo)
    local p = SKIN.db.profile.friends
    local nameText = btnFrame.name or btnFrame.Name
    if not nameText then
        return
    end

    if not p.classColorNames then
        return
    end

    local class = GetFriendClassFile(bnetInfo, wowInfo)
    if not class then
        return
    end

    if wowInfo then
        local cc = RAID_CLASS_COLORS[class]
        if cc then
            nameText:SetTextColor(cc.r, cc.g, cc.b)
        end
    elseif bnetInfo then
        local textValue = nameText:GetText()
        if not textValue then
            return
        end
        local colorCode = _getClassColorCode(class)
        if not colorCode then
            return
        end
        local colored = textValue:gsub("%((.-)%)", "(" .. colorCode .. "%1|r)")
        if colored ~= textValue then
            nameText:SetText(colored)
        end
    end
end

local FACTION_TEX_ALLIANCE = "Interface\\AddOns\\CludesUI\\media\\friends\\alliance.png"
local FACTION_TEX_HORDE = "Interface\\AddOns\\CludesUI\\media\\friends\\horde.png"
local FACTION_TEX_NEUTRAL = "Interface\\AddOns\\CludesUI\\media\\friends\\neutral.png"

local function UpdateFactionOverlay(btnFrame, bnetInfo, wowInfo)
    local factionName
    local isRetail = false
    if bnetInfo and bnetInfo.gameAccountInfo then
        local gi = bnetInfo.gameAccountInfo
        factionName = gi.factionName
        if
            gi.clientProgram == BNET_CLIENT_WOW
            and (gi.wowProjectID == 1 or gi.wowProjectID == nil)
            and gi.isOnline
        then
            isRetail = true
        end
    elseif wowInfo then
        factionName = UnitFactionGroup("player")
        isRetail = true
    end

    if not GetFFD(btnFrame).factionBg then
        GetFFD(btnFrame).factionBg = btnFrame:CreateTexture(nil, "BACKGROUND", nil, 3)
    end

    local fp = SKIN.db and SKIN.db.profile and SKIN.db.profile.friends
    local showFaction = fp and fp.factionBanners ~= false
    local texPath
    if showFaction and isRetail and factionName == "Alliance" then
        texPath = FACTION_TEX_ALLIANCE
    elseif showFaction and isRetail and factionName == "Horde" then
        texPath = FACTION_TEX_HORDE
    else
        texPath = FACTION_TEX_NEUTRAL
    end

    local texture = GetFFD(btnFrame).factionBg
    texture:SetTexture(texPath)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", 0, 0)
    texture:SetPoint("BOTTOMRIGHT", btnFrame, "BOTTOMRIGHT", 0, 0)
    texture:SetAlpha(0.2)
    texture:Show()
end

local function SkinFriendButton(btnFrame)
    if GetFFD(btnFrame).skinned then
        return
    end
    GetFFD(btnFrame).skinned = true

    local fontFile = CludesUI.GetFontPath("friends") or STANDARD_TEXT_FONT

    -- family: the friend's name and info line (place, note) show other players'
    -- writing and take the font as a font family, which draws the scripts it lacks
    local function ApplyFont(fontStr, size, family)
        if not fontStr or not fontStr.SetFont then
            return
        end
        if family then
            CludesUI.SetFontFamily(fontStr, fontFile, size, "", true)
            return
        end
        CludesUI.PrimeFontShadow(fontStr, true)
        fontStr:SetFont(fontFile, size, "")
    end

    local tileBg = btnFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
    tileBg:SetAllPoints()
    tileBg:SetColorTexture(0, 0, 0, 0.10)
    GetFFD(btnFrame).tileBg = tileBg

    -- Blizzard's own highlight texture is left intact for native selection/hover.
    local hover = btnFrame:CreateTexture(nil, "ARTWORK", nil, -7)
    hover:SetAllPoints()
    hover:SetAtlas("groupfinder-highlightbar-green")
    hover:SetDesaturated(true)
    hover:SetVertexColor(0.4, 0.7, 1.0)
    hover:SetAlpha(1)
    hover:Hide()
    local hoverFill = btnFrame:CreateTexture(nil, "ARTWORK", nil, -8)
    hoverFill:SetAllPoints()
    hoverFill:SetColorTexture(1, 1, 1, 0.02)
    hoverFill:SetBlendMode("ADD")
    hoverFill:Hide()
    btnFrame:HookScript("OnEnter", function()
        hover:Show()
        hoverFill:Show()
    end)
    btnFrame:HookScript("OnLeave", function()
        hover:Hide()
        hoverFill:Hide()
    end)

    local nameText = btnFrame.name or btnFrame.Name
    ApplyFont(nameText, 12, true)
    local infoText = btnFrame.info or btnFrame.Info
    ApplyFont(infoText, 9, true)
    local statusText = btnFrame.status or btnFrame.Status
    ApplyFont(statusText, 9)
    local gameText = btnFrame.gameText or btnFrame.GameText
    ApplyFont(gameText, 9)

    -- Offset name text right for class icon
    if nameText then
        local p1, rel, p2, posX, posY = nameText:GetPoint(1)
        if p1 then
            nameText:SetPoint(p1, rel, p2, (posX or 0) + 20, posY or 0)
        end
    end
end

-- Runs from our deferred driver, outside Blizzard's row initializer.
local function PostUpdateFriendButton(btnFrame)
    if not FriendsFrame:IsShown() then
        return
    end
    if not SKIN.db or not SKIN.db.profile.friends.enabled then
        return
    end
    if btnFrame.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then
        return
    end
    if not btnFrame.buttonType then
        return
    end

    local curType = btnFrame.buttonType
    local curId = btnFrame.id or 0
    if GetFFD(btnFrame).stampType == curType and GetFFD(btnFrame).stampId == curId then
        return
    end

    local bnetInfo, wowInfo = GetCachedFriendInfo(btnFrame)
    SkinFriendButton(btnFrame)

    -- Hide Blizzard elements we replace (its selection highlight stays).
    local fav = btnFrame.Favorite
    if fav then
        fav:SetAlpha(0)
    end
    local statusIcon = btnFrame.statusIcon or btnFrame.StatusIcon
    if statusIcon then
        statusIcon:SetAlpha(0)
    end
    local statusTex = btnFrame.status
    if statusTex and statusTex.IsObjectType and statusTex:IsObjectType("Texture") then
        statusTex:SetAlpha(0)
    end
    local gameIcon = btnFrame.gameIcon
    if gameIcon then
        gameIcon:SetAlpha(0)
    end

    -- Fill blank info text for BNet app users
    if btnFrame.buttonType == FRIENDS_BUTTON_TYPE_BNET and btnFrame.id then
        local infoFS = btnFrame.info or btnFrame.Info
        if infoFS and (not infoFS:GetText() or infoFS:GetText() == "") then
            local cached = _friendCache[btnFrame.id]
            if cached and cached.gameAccountInfo then
                local gi = cached.gameAccountInfo
                local cp = gi.clientProgram
                if gi.isOnline and (cp == "App" or cp == "BSAp") then
                    local locale = GetLocale()
                    infoFS:SetText((locale == "enUS" or locale == "enGB") and "In App" or "Battle.Net")
                end
            end
        end
    end

    GetFFD(btnFrame).stampType = curType
    GetFFD(btnFrame).stampId = curId
    GetFFD(btnFrame)._origInfo = nil -- clear so note re-captures from Blizzard's fresh text

    local nameText = btnFrame.name or btnFrame.Name
    local infoText = btnFrame.info or btnFrame.Info
    if infoText and nameText then
        infoText:ClearAllPoints()
        infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3)
    end

    -- Append friend note (legacy CUI group tag stripped); Blizzard's original text is cached first so a re-skin can't double-append.
    if infoText and btnFrame.buttonType and btnFrame.id then
        local origInfo = GetFFD(btnFrame)._origInfo
        if not origInfo then
            origInfo = infoText:GetText() or ""
            -- Button recycling can leave our own suffix behind; strip it.
            origInfo = origInfo:match("^(.-)  |cff888888|") or origInfo
            GetFFD(btnFrame)._origInfo = origInfo
        end
        local userNote
        if btnFrame.buttonType == FRIENDS_BUTTON_TYPE_BNET then
            local cached = _friendCache[btnFrame.id]
            if cached then
                userNote = CludesUI.StripFriendNoteTag(cached.note)
            end
        elseif btnFrame.buttonType == FRIENDS_BUTTON_TYPE_WOW then
            local cached = _friendCache[btnFrame.id + _FC_WOW_OFFSET]
            if cached then
                userNote = CludesUI.StripFriendNoteTag(cached.notes)
            end
        end
        if userNote then
            if origInfo ~= "" then
                infoText:SetText(origInfo .. "  |cff888888|  " .. userNote .. "|r")
            else
                infoText:SetText(CludesUI.COLOR_CODES.DIM .. userNote .. "|r")
            end
        end
    end

    -- Status orb. AFK/DND can be secret values, so gate every read.
    local isOnline, isAFK, isDND = false, false, false
    local _isv = issecretvalue
    if bnetInfo then
        isOnline = bnetInfo.gameAccountInfo and bnetInfo.gameAccountInfo.isOnline
        local rawAFK = bnetInfo.isAFK
        local rawDND = bnetInfo.isDND
        isAFK = (not _isv or not _isv(rawAFK)) and rawAFK or false
        isDND = (not _isv or not _isv(rawDND)) and rawDND or false
    elseif wowInfo then
        isOnline = wowInfo.connected
        local rawAFK = wowInfo.afk
        local rawDND = wowInfo.dnd
        isAFK = (not _isv or not _isv(rawAFK)) and rawAFK or false
        isDND = (not _isv or not _isv(rawDND)) and rawDND or false
    end

    if not GetFFD(btnFrame).statusOrb then
        GetFFD(btnFrame).statusOrb = btnFrame:CreateTexture(nil, "OVERLAY", nil, 3)
        GetFFD(btnFrame).statusOrb:SetSize(18, 18)
        FriendsKit.StatusOrbArt(GetFFD(btnFrame).statusOrb)
    end
    local orb = GetFFD(btnFrame).statusOrb
    orb:ClearAllPoints()
    local nm = btnFrame.name or btnFrame.Name
    if nm then
        local textW = nm:GetStringWidth() or 0
        orb:SetPoint("TOPLEFT", nm, "TOPLEFT", textW - 1, 2)
    end
    if isOnline then
        if isDND then
            orb:SetVertexColor(1, 0.2, 0.2, 1)
        elseif isAFK then
            orb:SetVertexColor(1, 0.8, 0, 1)
        else
            orb:SetVertexColor(0.2, 1, 0.2, 1)
        end
        orb:Show()
    else
        orb:SetVertexColor(0.4, 0.4, 0.4, 0.6)
        orb:Show()
    end

    UpdateClassIcon(btnFrame, bnetInfo, wowInfo)
    UpdateNameColor(btnFrame, bnetInfo, wowInfo)
    UpdateFactionOverlay(btnFrame, bnetInfo, wowInfo)

    -- Region icon: shown only when the friend's region differs from ours.
    local fp2 = SKIN.db and SKIN.db.profile and SKIN.db.profile.friends
    FriendsKit.UpdateRegionButton(
        btnFrame,
        GetFFD(btnFrame),
        bnetInfo and bnetInfo.gameAccountInfo,
        btnFrame.travelPassButton,
        not (fp2 and fp2.showRegionIcons == false)
    )
end

local function ProcessFriendButtons(force)
    if LegacyFriendsRetired() then
        return
    end
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if not scrollBox or not scrollBox:IsVisible() then
        return
    end
    for _, btnFrame in scrollBox:EnumerateFrames() do
        if
            btnFrame.buttonType == FRIENDS_BUTTON_TYPE_BNET
            or btnFrame.buttonType == FRIENDS_BUTTON_TYPE_WOW
        then
            if force then
                GetFFD(btnFrame).stampType = nil
            end
            PostUpdateFriendButton(btnFrame)
        end
    end
end

local function SkinOneScrollbar(scrollBox, scrollBar)
    if not scrollBox or not scrollBar then
        return
    end
    if GetFFD(scrollBox).track then
        return
    end

    scrollBar:SetAlpha(0)
    GetFFD(scrollBox).scrollBar = scrollBar

    local track = CreateFrame("Frame", nil, UIParent)
    track:Hide()
    track:SetFrameStrata("HIGH")
    track:SetWidth(4)
    track:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, 0)
    track:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 0)
    track:SetFrameLevel(scrollBox:GetFrameLevel() + 10)
    GetFFD(scrollBox).track = track

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(1, 1, 1, 0)
    trackBg:SetAllPoints()

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(4)
    thumb:SetHeight(60)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetColorTexture(1, 1, 1, 0.4)
    thumbTex:SetAllPoints()

    local hitArea = CreateFrame("Button", nil, UIParent)
    hitArea:SetFrameStrata("HIGH")
    hitArea:Hide()
    track._hitArea = hitArea
    hitArea:SetWidth(16)
    hitArea:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", -4, -2)
    hitArea:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", -4, 2)
    hitArea:SetFrameLevel(track:GetFrameLevel() + 2)
    hitArea:EnableMouse(true)
    hitArea:RegisterForDrag("LeftButton")

    local SCROLL_STEP = 40
    local SCROLLBAR_ALPHA = 0.35
    local isDragging = false
    local dragStartY, dragStartPct

    local function GetPct()
        return scrollBar.GetScrollPercentage and scrollBar:GetScrollPercentage() or 0
    end

    local function GetExtent()
        return scrollBar.GetVisibleExtentPercentage and scrollBar:GetVisibleExtentPercentage() or 1
    end

    local function StepToPct()
        local ext = GetExtent()
        if ext >= 1 then
            return 0
        end
        local totalH = scrollBox:GetHeight() / ext
        if totalH <= 0 then
            return 0
        end
        return SCROLL_STEP / totalH
    end

    local function StopScrollDrag()
        if not isDragging then
            return
        end
        isDragging = false
        thumb:SetScript("OnUpdate", nil)
    end

    local function UpdateScrollThumb()
        local ext = GetExtent()
        if ext >= 1 then
            track:SetAlpha(0)
            return
        end
        track:SetAlpha(SCROLLBAR_ALPHA)
        local pct = GetPct()
        local trackH = track:GetHeight()
        local thumbH = math.max(20, trackH * ext)
        thumb:SetHeight(thumbH)
        local maxTravel = trackH - thumbH
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(pct * maxTravel))
    end

    scrollBox:SetScript("OnMouseWheel", function(_, delta)
        if GetExtent() >= 1 then
            return
        end
        local step = StepToPct()
        local newPct = math.max(0, math.min(1, GetPct() - delta * step))
        scrollBar:SetScrollPercentage(newPct)
        UpdateScrollThumb()
    end)

    local function ScrollThumbOnUpdate(self)
        if not IsMouseButtonDown("LeftButton") then
            StopScrollDrag()
            return
        end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local deltaY = dragStartY - cursorY
        local trackH = track:GetHeight()
        local maxTravel = trackH - self:GetHeight()
        if maxTravel <= 0 then
            return
        end
        local newPct = math.max(0, math.min(1, dragStartPct + deltaY / maxTravel))
        scrollBar:SetScrollPercentage(newPct)
        UpdateScrollThumb()
    end

    thumb:SetScript("OnMouseDown", function(self, mouseBtn)
        if mouseBtn ~= "LeftButton" then
            return
        end
        isDragging = true
        local _, cursorY = GetCursorPosition()
        dragStartY = cursorY / self:GetEffectiveScale()
        dragStartPct = GetPct()
        self:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    thumb:SetScript("OnMouseUp", function(_, mouseBtn)
        if mouseBtn ~= "LeftButton" then
            return
        end
        StopScrollDrag()
    end)

    hitArea:SetScript("OnMouseDown", function(_, mouseBtn)
        if mouseBtn ~= "LeftButton" then
            return
        end
        if GetExtent() >= 1 then
            return
        end
        local _, cy = GetCursorPosition()
        cy = cy / track:GetEffectiveScale()
        local topY = track:GetTop() or 0
        local trackH = track:GetHeight()
        local thumbH = thumb:GetHeight()
        if trackH <= thumbH then
            return
        end
        local frac = (topY - cy - thumbH / 2) / (trackH - thumbH)
        frac = math.max(0, math.min(1, frac))
        scrollBar:SetScrollPercentage(frac)
        UpdateScrollThumb()
        isDragging = true
        dragStartY = cy
        dragStartPct = frac
        thumb:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    hitArea:SetScript("OnMouseUp", function(_, mouseBtn)
        if mouseBtn ~= "LeftButton" then
            return
        end
        StopScrollDrag()
    end)

    if scrollBar.RegisterCallback then
        scrollBar:RegisterCallback("OnScroll", UpdateScrollThumb)
    end
    if scrollBox.RegisterCallback then
        scrollBox:RegisterCallback("OnDataRangeChanged", UpdateScrollThumb)
    end
    C_Timer.After(0.1, UpdateScrollThumb)
end

local function SkinBottomButton(button)
    if not button or GetFFD(button).btnSkinned then
        return
    end
    GetFFD(button).btnSkinned = true

    local fontFile = CludesUI.GetFontPath("friends") or STANDARD_TEXT_FONT

    StripTextures(button)

    GetFFD(button).bg = button:CreateTexture(nil, "BACKGROUND", nil, -6)
    GetFFD(button).bg:SetColorTexture(0.025, 0.035, 0.045, 0.92)
    GetFFD(button).bg:SetAllPoints()

    Pix.CreateBorder(button, 1, 1, 1, 0.4, 1, "OVERLAY", 7)

    local textValue = button:GetFontString()
    if textValue then
        textValue:SetFont(fontFile, 9, "")
        textValue:SetTextColor(1, 1, 1, 0.5)
        textValue:ClearAllPoints()
        textValue:SetPoint("CENTER", button, "CENTER", 0, 0)
    end

    button:HookScript("OnEnter", function()
        local region, g, b, a1, a2 = 1, 1, 1, 0.7, 0.6
        if GetFFD(button).accent then
            region, g, b = ACC.r, ACC.g, ACC.b
            a1, a2 = 1, 0.8
        end
        if textValue then
            textValue:SetTextColor(region, g, b, a1)
        end
        if Pix.GetBorders(button) then
            Pix.SetBorderColor(button, region, g, b, a2)
        end
    end)
    button:HookScript("OnLeave", function()
        local region, g, b, a1, a2 = 1, 1, 1, 0.5, 0.4
        if GetFFD(button).accent then
            region, g, b = ACC.r, ACC.g, ACC.b
            a1, a2 = 0.7, 0.5
        end
        if textValue then
            textValue:SetTextColor(region, g, b, a1)
        end
        if Pix.GetBorders(button) then
            Pix.SetBorderColor(button, region, g, b, a2)
        end
    end)
end

local KNOWN_BUTTONS = {
    "FriendsFrameAddFriendButton",
    "FriendsFrameSendMessageButton",
    "WhoFrameWhoButton",
    "WhoFrameAddFriendButton",
    "WhoFrameGroupInviteButton",
}

local function UpdateBottomButtonAccent()
    local fp = SKIN.db and SKIN.db.profile and SKIN.db.profile.friends
    if not fp then
        return
    end
    local useAccent = fp.accentColors ~= false

    local function ApplyAccentToBtn(button, labelFS)
        if not button then
            return
        end
        GetFFD(button).accent = useAccent
        if useAccent then
            if labelFS then
                labelFS:SetTextColor(ACC.r, ACC.g, ACC.b, 0.7)
            end
            if Pix.GetBorders(button) then
                Pix.SetBorderColor(button, ACC.r, ACC.g, ACC.b, 0.5)
            end
        else
            if labelFS then
                labelFS:SetTextColor(1, 1, 1, 0.5)
            end
            if Pix.GetBorders(button) then
                Pix.SetBorderColor(button, 1, 1, 1, 0.4)
            end
        end
    end

    for _, name in ipairs(KNOWN_BUTTONS) do
        local button = _G[name]
        if button and GetFFD(button).btnSkinned and button:IsEnabled() and name ~= "FriendsFrameAddFriendButton" then
            ApplyAccentToBtn(button, button:GetFontString())
        end
    end

    -- Send Message: text plus a border overlay skinned outside SkinBottomButton.
    local msgBtn = _G.FriendsFrameSendMessageButton
    if msgBtn then
        local textValue = msgBtn:GetFontString()
        if textValue then
            if useAccent then
                textValue:SetTextColor(ACC.r, ACC.g, ACC.b, 0.7)
            else
                textValue:SetTextColor(1, 1, 1, 0.5)
            end
        end
    end
    local ffd = FriendsFrame and GetFFD(FriendsFrame)
    if ffd then
        if ffd.msgBdr then
            if useAccent then
                Pix.SetBorderColor(ffd.msgBdr, ACC.r, ACC.g, ACC.b, 0.5)
            else
                Pix.SetBorderColor(ffd.msgBdr, 1, 1, 1, 0.4)
            end
        end
    end
end

local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

-------------------------------------------------------------------------------
--  Window-skin layer over this window's chrome. Follows the Window Skins
--  "Friends List" card (winKey socialui): CludesUI = the Character Sheet
--  look, Modern = the global Modern backdrop, Blizz Default / the window-skin
--  kill switch / Blizz UI Enhanced not loaded = this module's own flat look.
--  Repaints only regions and frames SkinFriendsFrame already created.
-------------------------------------------------------------------------------
local CHROME = {
    BG_TEX = "Interface\\AddOns\\CludesUI\\media\\modern_blizz.png",
    DARKEN = 0.38, -- the window shell's 0.62 black overlay, folded into the vertex color
    TAB = { 0.068, 0.056, 0.052 }, -- Character Sheet tab block
    TAB_HL = 0.02,
    PANE = { 0, 0, 0, 0.1 }, -- Character Sheet pane wash
    EDIT = { 0.02, 0.02, 0.02, 1 }, -- window engine input box fill
    EDGE = { 0.2, 0.2, 0.2, 1 }, -- window engine control border
    MENU = { 0.08, 0.08, 0.08, 0.97 }, -- window engine fill, kept opaque over the list
    CLOSE = "|A:uitools-icon-close:14:14|a",
}

-- The window-skin engine, when Blizz UI Enhanced is loaded (not a dependency).
-- Probed for this build's exports: a mismatched install paints the flat look.
local function ChromeEngine()
    local bs = CludesUI._ModuleNS.CludesUIBlizzardSkin
    local ws = bs and bs.WSkin
    return ws and ws.CoverFit and ws or nil
end

local function ChromeStyle(ws)
    local s = ws and ws.GetStyle("socialui")
    if s == "cui" or s == "modern" then
        return s
    end
    return "flat"
end

-- One input box or menu: its fill texture (ours) and the PP border on its host.
local function PaintControl(texture, owner, shell, fillTex, fr, fg, fb, fa, edgeA)
    if not (texture and owner) then
        return
    end
    if shell then
        local edge = CHROME.EDGE
        texture:SetColorTexture(fillTex[1], fillTex[2], fillTex[3], fillTex[4])
        Pix.SetBorderColor(owner, edge[1], edge[2], edge[3], edge[4])
    else
        texture:SetColorTexture(fr, fg, fb, fa)
        Pix.SetBorderColor(owner, 1, 1, 1, edgeA)
    end
end

-- The look PaintChrome last painted (style, and the Modern color on Modern):
-- the style-refresh gate below compares against it.
local chromePainted = {}

local function PaintChrome()
    local widget = FriendsFrame
    if not (friendsSkinned and widget) or LegacyFriendsRetired() then
        return
    end
    local ws = ChromeEngine()
    local style = ChromeStyle(ws)
    local shell = style ~= "flat"
    local fd = GetFFD(widget)
    local p = SKIN.db.profile.friends
    local seen = chromePainted
    seen.style = style
    if style == "modern" then
        seen.r, seen.g, seen.b, seen.a = ws.GetModernBG()
    end

    local backdrop = fd.bg
    if backdrop then
        if style == "cui" then
            backdrop:SetTexture(CHROME.BG_TEX)
            ws.CoverFit(backdrop, widget:GetSize())
            backdrop:SetVertexColor(CHROME.DARKEN, CHROME.DARKEN, CHROME.DARKEN, 1)
        else
            backdrop:SetTexCoord(0, 1, 0, 1)
            backdrop:SetVertexColor(1, 1, 1, 1)
            if style == "modern" then
                backdrop:SetColorTexture(seen.r, seen.g, seen.b, seen.a)
            else
                backdrop:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
            end
        end
        backdrop:SetAlpha(1)
    end

    -- Frame border: the thin border under the flat look; the window skin's
    -- atlas frame otherwise, hung on that same border container (ours).
    local region, g, b, a = GetBorderColor(p)
    local bsz = p.borderSize or 1
    if shell or bsz <= 0 then
        Pix.SetBorderColor(widget, region, g, b, 0)
    else
        Pix.UpdateBorder(widget, bsz, region, g, b, a)
    end
    if shell and fd.atlasFrame == nil then
        local owner = Pix.GetBorders(widget)
        if owner then
            ws.AtlasBorder(owner)
            fd.atlasFrame = ws.GetFFD(owner).atlasBorderFrame or false
        end
    end
    if fd.atlasFrame then
        fd.atlasFrame:SetShown(shell)
    end

    -- Tabs, tab bar, panes.
    local tr, tg, tb = FRAME_BG_R, FRAME_BG_G, FRAME_BG_B
    if shell then
        tr, tg, tb = CHROME.TAB[1], CHROME.TAB[2], CHROME.TAB[3]
    end
    local tabs = fd.tabs
    if tabs then
        for i = 1, #tabs do
            local td = FFD[tabs[i]]
            if td then
                if td.bg then
                    td.bg:SetColorTexture(tr, tg, tb, 1)
                end
                if td.activeHL then
                    td.activeHL:SetColorTexture(1, 1, 1, shell and CHROME.TAB_HL or 0.05)
                end
            end
        end
    end
    if fd.tabBarBg then
        fd.tabBarBg:SetColorTexture(tr, tg, tb)
        fd.tabBarBg:SetAlpha(1)
    end
    local pane = CHROME.PANE
    if fd.listBg then
        if shell then
            fd.listBg:SetColorTexture(pane[1], pane[2], pane[3], pane[4])
        else
            fd.listBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
        end
    end
    if fd.whoBg then
        if shell then
            fd.whoBg:SetColorTexture(pane[1], pane[2], pane[3], pane[4])
        else
            fd.whoBg:SetColorTexture(0, 0.08, 0.10, 0.35)
        end
    end

    -- Who / Quick Join button fills (SkinBottomButton's own texture): none
    -- under a window skin, so every bottom button is outline-only like the
    -- Contacts pair, which carries no fill.
    local fillA = shell and 0 or 0.92
    for i = 1, #KNOWN_BUTTONS do
        local button = _G[KNOWN_BUTTONS[i]]
        local bd = button and FFD[button]
        if bd and bd.bg then
            bd.bg:SetColorTexture(0.025, 0.035, 0.045, fillA)
        end
    end
    local qjf = _G.QuickJoinFrame
    local jb = qjf and qjf.JoinQueueButton
    local jd = jb and FFD[jb]
    if jd and jd.bg then
        jd.bg:SetColorTexture(0.025, 0.035, 0.045, fillA)
    end

    -- Input boxes and the search results menu: the window engine's control
    -- recipe under a skin, this module's creation values otherwise.
    PaintControl(fd.searchBg, fd.searchBox, shell, CHROME.EDIT, 0, 0, 0, 0.4, 0.1)
    PaintControl(fd.whoEditBg, fd.whoEdit, shell, CHROME.EDIT, 0, 0, 0, 0.4, 0.1)
    PaintControl(fd.searchMenuBg, fd.searchDropdown, shell, CHROME.MENU, 0.04, 0.05, 0.06, 0.97, 0.15)

    -- Close glyph: the house close atlas inline in our own FontString.
    local callback = fd.closeBtn
    local cd = callback and FFD[callback]
    if cd and cd.x then
        cd.idleA = shell and 0.75 or 0.5
        cd.hoverA = shell and 1 or 0.9
        cd.x:SetText(shell and CHROME.CLOSE or "x")
        cd.x:SetTextColor(1, 1, 1, 1)
        cd.x:SetAlpha(cd.idleA)
        cd.x:ClearAllPoints()
        cd.x:SetPoint("CENTER", callback, "CENTER", -2, shell and 0 or -3)
    end
end

-- Window Skins refresh (a style pick or Modern color edit on ANY card): paint
-- only when this window's look changed. Its other inputs (border size/color,
-- class color, accent) change through ApplyFriends, which paints directly.
local function OnChromeStylesChanged()
    local ws = ChromeEngine()
    local style = ChromeStyle(ws)
    local seen = chromePainted
    if style == seen.style then
        if style ~= "modern" then
            return
        end
        local region, g, b, a = ws.GetModernBG()
        if region == seen.r and g == seen.g and b == seen.b and a == seen.a then
            return
        end
    end
    PaintChrome()
end

-- Options: the Border rows stand down while a window skin draws the frame.
CludesUI._ModuleNS[ADDON_NAME].FR_ChromeShell = function()
    return ChromeStyle(ChromeEngine()) ~= "flat"
end

-------------------------------------------------------------------------------
--  SkinFriendsFrame (one-time structural setup)
-------------------------------------------------------------------------------
local function SkinFriendsFrame()
    if LegacyFriendsRetired() then
        return
    end
    local widget = FriendsFrame
    if not widget or friendsSkinned then
        return
    end
    friendsSkinned = true
    local p = SKIN.db.profile.friends
    local fontFile = CludesUI.GetFontPath("friends") or STANDARD_TEXT_FONT

    if widget.NineSlice then
        widget.NineSlice:Hide()
    end
    if widget.Bg then
        widget.Bg:Hide()
    end
    if widget.TitleBg then
        widget.TitleBg:Hide()
    end
    if widget.TopTileStreaks then
        widget.TopTileStreaks:SetAlpha(0)
    end
    if widget.PortraitContainer then
        widget.PortraitContainer:Hide()
    end
    if widget.portrait then
        widget.portrait:Hide()
    end
    if widget.PortraitFrame then
        widget.PortraitFrame:Hide()
    end
    if FriendsFramePortrait then
        FriendsFramePortrait:Hide()
    end
    if FriendsFrameIcon then
        FriendsFrameIcon:Hide()
    end

    for _, key in ipairs({
        "TopBorder",
        "TopRightCorner",
        "RightBorder",
        "BottomRightCorner",
        "BottomBorder",
        "BottomLeftCorner",
        "LeftBorder",
        "TopLeftCorner",
        "BtnCornerLeft",
        "BtnCornerRight",
    }) do
        if widget[key] then
            widget[key]:Hide()
        end
    end

    if widget.Inset then
        if widget.Inset.NineSlice then
            widget.Inset.NineSlice:Hide()
        end
        if widget.Inset.Bg then
            widget.Inset.Bg:Hide()
        end
    end

    if not GetFFD(widget).sizeSet then
        GetFFD(widget).sizeSet = true
        local origW = widget:GetWidth()
        local origH = widget:GetHeight()
        local origListH = FriendsListFrame:GetHeight()
        local EXTRA_H = 50
        local LIST_TOP = -92
        local LIST_BOTTOM = 35
        local LIST_LEFT = 15
        local LIST_RIGHT = -15
        local _sizeApplied = false
        local function ApplySize()
            if _sizeApplied then
                return
            end
            _sizeApplied = true
            widget:SetWidth(origW - 40)
            widget:SetHeight(origH + EXTRA_H)
            FriendsListFrame:SetHeight(origListH + EXTRA_H)
            FriendsListFrame.ScrollBox:ClearAllPoints()
            FriendsListFrame.ScrollBox:SetPoint("TOPLEFT", widget, "TOPLEFT", LIST_LEFT, LIST_TOP)
            FriendsListFrame.ScrollBox:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
            local function FitToListPane(frame)
                if not frame then
                    return
                end
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", widget, "TOPLEFT", LIST_LEFT, LIST_TOP)
                frame:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
                StripTextures(frame)
                if frame.Bg then
                    frame.Bg:Hide()
                end
                if frame.NineSlice then
                    frame.NineSlice:Hide()
                end
                if frame.List then
                    frame.List:ClearAllPoints()
                    frame.List:SetAllPoints(frame)
                    StripTextures(frame.List)
                    if frame.List.ScrollBox then
                        frame.List.ScrollBox:ClearAllPoints()
                        frame.List.ScrollBox:SetAllPoints(frame.List)
                    end
                end
            end
            FitToListPane(_G.RecentAlliesFrame)
            -- Skin Recent Allies scrollbar identically to Friends list
            local raFrame = _G.RecentAlliesFrame
            if raFrame and raFrame.List then
                local raBar = raFrame.List.ScrollBar or raFrame.ScrollBar
                if raBar then
                    StripTextures(raBar)
                    if raBar.Background then
                        raBar.Background:Hide()
                    end
                    if raBar.Back then
                        raBar.Back:SetAlpha(0)
                        raBar.Back:SetSize(1, 0.001)
                    end
                    if raBar.Forward then
                        raBar.Forward:SetAlpha(0)
                        raBar.Forward:SetSize(1, 0.001)
                    end
                    local raTrack = raBar.Track
                    if raTrack then
                        raTrack:DisableDrawLayer("ARTWORK")
                        raTrack:DisableDrawLayer("BACKGROUND")
                        raTrack:ClearAllPoints()
                        raTrack:SetPoint("TOPLEFT", raBar, "TOPLEFT", 0, 0)
                        raTrack:SetPoint("BOTTOMRIGHT", raBar, "BOTTOMRIGHT", 0, 0)
                    end
                    local raThumb = raBar.GetThumb and raBar:GetThumb()
                    if raThumb then
                        raThumb:DisableDrawLayer("ARTWORK")
                        raThumb:DisableDrawLayer("BACKGROUND")
                        local raTex = raThumb:CreateTexture(nil, "OVERLAY")
                        raTex:SetColorTexture(1, 1, 1, 0.4)
                        raTex:SetWidth(3)
                        raTex:SetPoint("TOP", raThumb, "TOP", 0, 0)
                        raTex:SetPoint("BOTTOM", raThumb, "BOTTOM", 0, 0)
                        raTex:SetPoint("RIGHT", raThumb, "RIGHT", 0, 0)
                    end
                    raBar:SetWidth(5)
                    local p1, rel, p2, ox, oy = raBar:GetPoint(1)
                    if p1 then
                        raBar:SetPoint(p1, rel, p2, (ox or 0) - 6, (oy or 0) + 4)
                    end
                    raBar:SetAlpha(0.6)
                    raBar:HookScript("OnEnter", function()
                        raBar:SetAlpha(0.95)
                    end)
                    raBar:HookScript("OnLeave", function()
                        raBar:SetAlpha(0.6)
                    end)
                    if raThumb then
                        raThumb:HookScript("OnEnter", function()
                            raBar:SetAlpha(0.95)
                        end)
                        raThumb:HookScript("OnLeave", function()
                            raBar:SetAlpha(0.6)
                        end)
                    end
                end
            end
            local raf = _G.RecruitAFriendFrame
            if raf then
                raf:ClearAllPoints()
                raf:SetPoint("TOPLEFT", widget, "TOPLEFT", LIST_LEFT, -20)
                raf:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM - 20)
                StripTextures(raf)
                if raf.Bg then
                    raf.Bg:Hide()
                end
                if raf.NineSlice then
                    raf.NineSlice:Hide()
                end
            end
        end

        hooksecurefunc(widget, "Show", function()
            local _mplus = C_ChallengeMode
                and C_ChallengeMode.IsChallengeModeActive
                and C_ChallengeMode.IsChallengeModeActive()
            local _, _iT = IsInInstance()
            local _pvp = (_iT == "pvp" or _iT == "arena")
            if not InCombatLockdown() and not _mplus and not _pvp then
                ApplySize()
            end
        end)
        ApplySize()
    end

    GetFFD(widget).bg = widget:CreateTexture(nil, "BACKGROUND", nil, -8)
    GetFFD(widget).bg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
    GetFFD(widget).bg:SetAllPoints()
    GetFFD(widget).bg:SetAlpha(1)

    do
        local region, g, b, a = GetBorderColor(p)
        local borderAlpha = (p.showBorder ~= false) and a or 0
        Pix.CreateBorder(widget, region, g, b, borderAlpha, p.borderSize or 1, "OVERLAY", 7)
    end

    -- Float these above the resized panel instead of clipping inside it.
    if widget.IgnoreListWindow then
        widget.IgnoreListWindow:SetParent(UIParent)
        widget.IgnoreListWindow:SetFrameStrata("DIALOG")
    end

    if _G.RaidInfoFrame then
        _G.RaidInfoFrame:SetFrameStrata("DIALOG")
    end

    if FriendsTooltip then
        FriendsTooltip:SetParent(UIParent)
        FriendsTooltip:SetFrameStrata("TOOLTIP")
    end

    local firstTab = _G.FriendsFrameTab1
    if firstTab then
        GetFFD(widget).tabBarBg = widget:CreateTexture(nil, "BACKGROUND", nil, -7)
        GetFFD(widget).tabBarBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
        GetFFD(widget).tabBarBg:SetAlpha(1)
        GetFFD(widget).tabBarBg:SetPoint("TOPLEFT", widget, "BOTTOMLEFT", 0, 2)
        GetFFD(widget).tabBarBg:SetPoint("TOPRIGHT", widget, "BOTTOMRIGHT", 0, 2)
        GetFFD(widget).tabBarBg:SetPoint("BOTTOM", firstTab, "BOTTOM", 0, 0)
    end

    -- Restyle Blizzard's tabs in-place
    local customTabs = {}
    for i = 1, widget.numTabs or 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then
            local regions = { tab:GetRegions() }
            for jdx = 1, #regions do
                local regionFrame = regions[jdx]
                if regionFrame and regionFrame:IsObjectType("Texture") then
                    regionFrame:SetTexture("")
                    if regionFrame.SetAtlas then
                        regionFrame:SetAtlas("")
                    end
                end
            end
            if tab.Left then
                tab.Left:SetTexture("")
            end
            if tab.Middle then
                tab.Middle:SetTexture("")
            end
            if tab.Right then
                tab.Right:SetTexture("")
            end
            if tab.LeftDisabled then
                tab.LeftDisabled:SetTexture("")
            end
            if tab.MiddleDisabled then
                tab.MiddleDisabled:SetTexture("")
            end
            if tab.RightDisabled then
                tab.RightDisabled:SetTexture("")
            end
            local highlight = tab:GetHighlightTexture()
            if highlight then
                highlight:SetTexture("")
            end

            if not GetFFD(tab).bg then
                GetFFD(tab).bg = tab:CreateTexture(nil, "BACKGROUND")
                GetFFD(tab).bg:SetAllPoints()
                GetFFD(tab).bg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
            end

            local tfd = GetFFD(tab)
            if not tfd.activeHL then
                local activeHL = tab:CreateTexture(nil, "ARTWORK", nil, -6)
                activeHL:SetAllPoints()
                activeHL:SetColorTexture(1, 1, 1, 0.05)
                activeHL:SetBlendMode("ADD")
                activeHL:Hide()
                tfd.activeHL = activeHL
            end

            local blizLabel = tab:GetFontString()
            local labelText = blizLabel and blizLabel:GetText() or ("Tab " .. i)
            if blizLabel then
                blizLabel:SetTextColor(0, 0, 0, 0)
            end
            tab:SetPushedTextOffset(0, 0)
            local label = tab:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontFile, 9, "")
            label:SetPoint("CENTER", tab, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetText(labelText)
            tfd.label = label

            if not tfd.underline then
                local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
                Pix.DisablePixelSnap(underline)
                underline:SetHeight(Pix.mult or 1)
                underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
                underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
                local ar, ag, ab = ACC.r, ACC.g, ACC.b
                underline:SetColorTexture(ar, ag, ab, 1)
                CludesUI.RegAccent({ type = "solid", obj = underline, a = 1 })
                underline:Hide()
                tfd.underline = underline
            end

            customTabs[i] = tab
        end
    end
    GetFFD(widget).tabs = customTabs

    local _activeSubTab = 1

    local function UpdateCustomTabs(overrideTab)
        local selected = overrideTab or PanelTemplates_GetSelectedTab(FriendsFrame) or 1
        local isContacts = (selected == 1)
        local fp = SKIN.db and SKIN.db.profile and SKIN.db.profile.friends
        local useAccent = fp and fp.accentColors ~= false
        for i, ct in ipairs(customTabs) do
            local isActive = (i == selected)
            local ctd = GetFFD(ct)
            if ctd.label then
                ctd.label:SetTextColor(1, 1, 1, isActive and 1 or 0.5)
            end
            if ctd.underline then
                ctd.underline:SetShown(isActive)
                if isActive then
                    if useAccent then
                        local ar, ag, ab = ACC.r, ACC.g, ACC.b
                        ctd.underline:SetColorTexture(ar, ag, ab, 1)
                    else
                        ctd.underline:SetColorTexture(1, 1, 1, 0.6)
                    end
                end
            end
            if ctd.activeHL then
                ctd.activeHL:SetShown(isActive)
            end
        end
        local showContactsUI = isContacts and _activeSubTab == 1
        local addBtn = _G.FriendsFrameAddFriendButton
        local msgBtn = _G.FriendsFrameSendMessageButton
        if addBtn then
            addBtn:SetAlpha(showContactsUI and 1 or 0)
            addBtn:EnableMouse(showContactsUI)
        end
        if msgBtn then
            msgBtn:SetAlpha(showContactsUI and 1 or 0)
            msgBtn:EnableMouse(showContactsUI)
        end
        if GetFFD(widget).addBdr then
            GetFFD(widget).addBdr:SetShown(showContactsUI)
        end
        if GetFFD(widget).msgBdr then
            GetFFD(widget).msgBdr:SetShown(showContactsUI)
        end
        local showListChrome = isContacts and _activeSubTab ~= 3
        if GetFFD(widget).listOverlay then
            GetFFD(widget).listOverlay:SetShown(showListChrome)
        end
        if GetFFD(widget).listBdr then
            GetFFD(widget).listBdr:SetShown(showListChrome)
        end
        if GetFFD(widget).searchBox then
            GetFFD(widget).searchBox:SetShown(isContacts)
        end
        if not isContacts and GetFFD(widget).searchDropdown then
            GetFFD(widget).searchDropdown:Hide()
        end
        local showTopUI = (selected ~= 3)
        if not isContacts and GetFFD(widget).subTabs then
            for _, ct in ipairs(GetFFD(widget).subTabs) do
                ct._label:SetTextColor(1, 1, 1, 0.53)
                ct:SetShown(showTopUI)
            end
        elseif GetFFD(widget).subTabs then
            for _, ct in ipairs(GetFFD(widget).subTabs) do
                ct:Show()
            end
            if GetFFD(widget).updateSubTabs then
                GetFFD(widget).updateSubTabs()
            end
        end
        if GetFFD(widget).statusOrb then
            GetFFD(widget).statusOrb:SetShown(isContacts)
        end
        if GetFFD(widget).broadcastBtn then
            GetFFD(widget).broadcastBtn:SetShown(isContacts)
        end
        if GetFFD(widget).titleBtn then
            GetFFD(widget).titleBtn:Show()
        end
        if GetFFD(widget).titleDiv then
            GetFFD(widget).titleDiv:Show()
        end
        local function SetTrackVisSB(sb, vis)
            if sb and GetFFD(sb).track then
                GetFFD(sb).track:SetShown(vis)
                if GetFFD(sb).track._hitArea then
                    GetFFD(sb).track._hitArea:SetShown(vis)
                end
            end
        end
        local isShown = widget:IsShown()
        local raf = _G.RecentAlliesFrame
        if raf and raf.List then
            SetTrackVisSB(raf.List.ScrollBox, isShown and isContacts and _activeSubTab == 2)
        end
        local who = _G.WhoFrame
        if who then
            SetTrackVisSB(who.ScrollBox or (who.List and who.List.ScrollBox), isShown and selected == 2)
        end
    end

    GetFFD(widget).updateCustomTabs = UpdateCustomTabs

    -- Tab changes are detected from each content frame's OnShow.
    local tabFrames = {
        { _G.FriendsListFrame, 1 },
        { _G.WhoFrame, 2 },
        { _G.RaidFrame, 3 },
        { _G.QuickJoinFrame, 4 },
    }
    for _, record in ipairs(tabFrames) do
        local sf, tabIdx = record[1], record[2]
        if sf then
            sf:HookScript("OnShow", function()
                UpdateCustomTabs(tabIdx)
                if tabIdx == 3 then
                    C_Timer.After(0, SkinRaidTab)
                    C_Timer.After(0.2, SkinRaidTab)
                end
            end)
        end
    end
    if not _G.RaidFrame then
        C_Timer.After(0.25, function()
            local rf = _G.RaidFrame
            if rf then
                rf:HookScript("OnShow", function()
                    UpdateCustomTabs(3)
                    C_Timer.After(0, SkinRaidTab)
                    C_Timer.After(0.2, SkinRaidTab)
                end)
            end
        end)
    end
    hooksecurefunc(widget, "Show", function()
        UpdateCustomTabs()
    end)

    hooksecurefunc(widget, "Hide", function()
        local function HideTrackSB(sb)
            if sb and GetFFD(sb).track then
                GetFFD(sb).track:Hide()
                if GetFFD(sb).track._hitArea then
                    GetFFD(sb).track._hitArea:Hide()
                end
            end
        end
        _activeSubTab = 1
        local raf = _G.RecentAlliesFrame
        if raf and raf.List then
            HideTrackSB(raf.List.ScrollBox)
        end
        local who = _G.WhoFrame
        if who then
            HideTrackSB(who.ScrollBox or (who.List and who.List.ScrollBox))
        end
    end)

    -- Blizzard's title is hidden and replaced with a clickable BattleTag label.
    if widget.TitleContainer then
        local blizTitle = widget.TitleContainer.TitleText or widget.TitleContainer:GetFontString()
        if blizTitle then
            blizTitle:SetAlpha(0)
        end
    elseif FriendsFrameTitleText then
        FriendsFrameTitleText:SetAlpha(0)
    end

    local _, battleTag = BNGetInfo()
    local title = battleTag or (FRIENDS or "Friends")
    local titleBtn = CreateFrame("Button", nil, widget)
    -- Above the window skin's atlas frame (+7), below the search results (+10).
    titleBtn:SetFrameLevel(widget:GetFrameLevel() + 8)

    -- The player's BattleTag: a font family, which draws the scripts the font lacks
    local titleLabel = titleBtn:CreateFontString(nil, "OVERLAY")
    CludesUI.SetFontFamily(titleLabel, fontFile, 12, "", false)
    titleLabel:SetTextColor(1, 1, 1, 0.75)
    titleLabel:SetPoint("CENTER", titleBtn, "CENTER", 0, 0)
    titleLabel:SetJustifyH("CENTER")
    titleLabel:SetText(title)

    local textW = titleLabel:GetStringWidth() or 60
    titleBtn:SetSize(textW + 16, 20)
    titleBtn:SetPoint("TOP", widget, "TOP", 0, -5)

    titleBtn._label = titleLabel
    GetFFD(widget).titleBtn = titleBtn

    titleBtn:SetScript("OnEnter", function()
        titleLabel:SetTextColor(1, 1, 1, 1)
    end)
    titleBtn:SetScript("OnLeave", function()
        titleLabel:SetTextColor(1, 1, 1, 0.75)
    end)

    local copyBackdrop, copyPopup
    local function HideCopyPopup()
        if copyPopup then
            copyPopup:Hide()
        end
        if copyBackdrop then
            copyBackdrop:Hide()
        end
    end

    local function ShowCopyPopup(textValue, anchorBtn)
        if not copyPopup then
            copyBackdrop = CreateFrame("Button", nil, UIParent)
            copyBackdrop:SetFrameStrata("DIALOG")
            copyBackdrop:SetFrameLevel(499)
            copyBackdrop:SetAllPoints(UIParent)
            local bdTex = copyBackdrop:CreateTexture(nil, "BACKGROUND")
            bdTex:SetAllPoints()
            bdTex:SetColorTexture(0, 0, 0, 0.10)
            local fadeIn = copyBackdrop:CreateAnimationGroup()
            fadeIn:SetToFinalAlpha(true)
            local a = fadeIn:CreateAnimation("Alpha")
            a:SetFromAlpha(0)
            a:SetToAlpha(1)
            a:SetDuration(0.2)
            copyBackdrop._fadeIn = fadeIn
            copyBackdrop:RegisterForClicks("AnyUp")
            copyBackdrop:SetScript("OnClick", HideCopyPopup)
            copyBackdrop:Hide()

            copyPopup = CreateFrame("Frame", nil, UIParent)
            copyPopup:SetFrameStrata("DIALOG")
            copyPopup:SetFrameLevel(500)
            copyPopup:SetSize(220, 52)
            local popFade = copyPopup:CreateAnimationGroup()
            popFade:SetToFinalAlpha(true)
            local pa = popFade:CreateAnimation("Alpha")
            pa:SetFromAlpha(0)
            pa:SetToAlpha(1)
            pa:SetDuration(0.2)
            copyPopup._fadeIn = popFade

            local backdrop = copyPopup:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.97)
            Pix.CreateBorder(copyPopup, 1, 1, 1, 0.15, 1, "OVERLAY", 7)

            local hint = copyPopup:CreateFontString(nil, "OVERLAY")
            hint:SetFont(fontFile, 8, "")
            hint:SetTextColor(1, 1, 1, 0.5)
            hint:SetPoint("TOP", copyPopup, "TOP", 0, -6)
            hint:SetText(CludesUI.L("Ctrl+C to copy, Escape to close"))

            local eb = CreateFrame("EditBox", nil, copyPopup)
            eb:SetSize(160, 16)
            eb:SetPoint("TOP", hint, "BOTTOM", 0, -4)
            eb:SetFontObject(GameFontHighlight)
            eb:SetAutoFocus(false)
            eb:SetJustifyH("CENTER")
            local ebBg = eb:CreateTexture(nil, "BACKGROUND")
            ebBg:SetColorTexture(0.098, 0.108, 0.120, 1)
            ebBg:SetPoint("TOPLEFT", -6, 4)
            ebBg:SetPoint("BOTTOMRIGHT", 6, -4)
            Pix.CreateBorder(eb, 1, 1, 1, 0.02, 1, "OVERLAY", 7)
            eb:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
                HideCopyPopup()
            end)
            eb:SetScript("OnKeyDown", function(self, key)
                if key == "C" and IsControlKeyDown() then
                    C_Timer.After(0.05, HideCopyPopup)
                end
            end)
            eb:SetScript("OnMouseUp", function(self)
                self:HighlightText()
            end)
            copyPopup:EnableMouse(true)
            copyPopup:SetScript("OnMouseDown", function()
                copyPopup._eb:SetFocus()
                copyPopup._eb:HighlightText()
            end)
            copyPopup._eb = eb
        end
        copyPopup._eb:SetText(textValue)
        copyPopup:ClearAllPoints()
        copyPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 8)
        copyBackdrop:SetAlpha(0)
        copyBackdrop:Show()
        copyBackdrop._fadeIn:Play()
        copyPopup:SetAlpha(0)
        copyPopup:Show()
        copyPopup._fadeIn:Play()
        copyPopup._eb:SetFocus()
        copyPopup._eb:HighlightText()
    end

    titleBtn:SetScript("OnClick", function(self)
        ShowCopyPopup(title, self)
    end)

    GetFFD(widget).titleDiv = widget:CreateTexture(nil, "OVERLAY", nil, 1)
    GetFFD(widget).titleDiv:SetColorTexture(1, 1, 1, 0.06)
    GetFFD(widget).titleDiv:SetHeight(1)
    GetFFD(widget).titleDiv:SetPoint("TOPLEFT", widget, "TOPLEFT", 8, -30)
    GetFFD(widget).titleDiv:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -8, -30)

    -- BattleNet ID bar reskin
    local statusDD = _G.FriendsFrameStatusDropdown
    if statusDD then
        statusDD:SetAlpha(0)
        statusDD:EnableMouse(false)
        statusDD:SetSize(1, 1)
    end

    local bnetFrame = _G.FriendsFrameBattlenetFrame
    if bnetFrame then
        StripTextures(bnetFrame)
        local children = { bnetFrame:GetChildren() }
        for i = 1, #children do
            local childFrame = children[i]
            childFrame:SetAlpha(0)
            childFrame:EnableMouse(false)
        end
        local regions = { bnetFrame:GetRegions() }
        for i = 1, #regions do
            local regionFrame = regions[i]
            if regionFrame:IsObjectType("FontString") then
                regionFrame:SetAlpha(0)
            end
        end
        if bnetFrame.BroadcastFrame then
            local bf = bnetFrame.BroadcastFrame
            bf:SetParent(FriendsFrame)
            bf:SetAlpha(1)
            bf:EnableMouse(true)
            bf:ClearAllPoints()
            bf:SetPoint("TOPLEFT", FriendsFrame, "TOPRIGHT", 5, 0)
        end
        bnetFrame:SetHeight(1)
    end

    -- UnitIsDND/UnitIsAFK can return secret values; gate both reads.
    local function GetPlayerStatusName()
        local dnd = UnitIsDND("player")
        if not issecretvalue or not issecretvalue(dnd) then
            if dnd then
                return BUSY or "Busy"
            end
        end
        local afk = UnitIsAFK("player")
        if not issecretvalue or not issecretvalue(afk) then
            if afk then
                return AWAY or "Away"
            end
        end
        return FRIENDS_LIST_ONLINE or "Online"
    end
    GetFFD(widget).getPlayerStatus = GetPlayerStatusName

    -- Custom sub-tabs (Friends/Recent Allies/Recruit A Friend)
    local customSubTabs = {}
    GetFFD(widget).subTabs = customSubTabs
    local function SkinSubTabs()
        local tabHeader = _G.FriendsTabHeader
        if not tabHeader then
            return
        end
        local tabSystem = tabHeader.TabSystem
        if not tabSystem then
            return
        end

        local blizSubTabs = {}
        local children = { tabSystem:GetChildren() }
        for i = 1, #children do
            local st = children[i]
            if st and st:IsObjectType("Button") then
                local textValue = st:GetFontString()
                local name = textValue and textValue:GetText() or ("Tab " .. i)
                blizSubTabs[#blizSubTabs + 1] = { blizTab = st, name = name }
            end
        end

        for _, details in ipairs(blizSubTabs) do
            details.blizTab:SetAlpha(0)
            details.blizTab:SetHeight(1)
            details.blizTab:EnableMouse(false)
        end
        StripTextures(tabHeader)
        if tabSystem then
            StripTextures(tabSystem)
        end

        local function UpdateSubTabs()
            local fp3 = SKIN.db and SKIN.db.profile and SKIN.db.profile.friends
            local useAccent = fp3 and fp3.accentColors ~= false
            local ar, ag, ab = ACC.r, ACC.g, ACC.b
            for i, ct in ipairs(customSubTabs) do
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if isSelected then
                    if useAccent then
                        ct._label:SetTextColor(ar, ag, ab, 1)
                    else
                        ct._label:SetTextColor(1, 1, 1, 1)
                    end
                else
                    ct._label:SetTextColor(1, 1, 1, 0.53)
                end
            end
        end
        local function UpdateSubTabWidths()
            for _, ct in ipairs(customSubTabs) do
                local wid = ct._label:GetStringWidth() or 40
                ct:SetWidth(wid)
            end
        end
        GetFFD(widget).updateSubTabs = function()
            UpdateSubTabWidths()
            UpdateSubTabs()
        end

        local ar, ag, ab = ACC.r, ACC.g, ACC.b
        for i, details in ipairs(blizSubTabs) do
            local ct = CreateFrame("Button", nil, widget)
            ct:SetFrameLevel(widget:GetFrameLevel() + 5)
            ct:SetHeight(20)

            local label = ct:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontFile, 11, "")
            label:SetPoint("LEFT", ct, "LEFT", 0, 0)
            label:SetJustifyH("LEFT")
            label:SetText(details.name:match("^(%S+)") or details.name)
            ct._label = label

            ct:SetScript("OnEnter", function()
                local isContacts = (PanelTemplates_GetSelectedTab(FriendsFrame) or 1) == 1
                if not isContacts then
                    return
                end
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if not isSelected then
                    ct._label:SetTextColor(1, 1, 1, 0.86)
                end
            end)
            ct:SetScript("OnLeave", function()
                local isContacts = (PanelTemplates_GetSelectedTab(FriendsFrame) or 1) == 1
                if not isContacts then
                    return
                end
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if isSelected then
                    local fp4 = SKIN.db and SKIN.db.profile and SKIN.db.profile.friends
                    if fp4 and fp4.accentColors ~= false then
                        ct._label:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
                    else
                        ct._label:SetTextColor(1, 1, 1, 1)
                    end
                else
                    ct._label:SetTextColor(1, 1, 1, 0.53)
                end
            end)

            ct:SetScript("OnClick", function()
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if isSelected then
                    return
                end
                local tabName = details.name or ""
                if strfind(tabName, "Recruit") then
                    -- Let Blizzard show the full RAF page natively; its tab is mouse-enabled just long enough for the click to register.
                    if bliz then
                        bliz:EnableMouse(true)
                        bliz:Click()
                        bliz:EnableMouse(false)
                    end
                    _activeSubTab = i
                    UpdateSubTabs()
                    UpdateCustomTabs()
                    return
                else
                    local bottomTab = PanelTemplates_GetSelectedTab(FriendsFrame) or 1
                    if bottomTab ~= 1 then
                        PanelTemplates_SetTab(FriendsFrame, 1)
                        FriendsFrame_Update()
                        UpdateCustomTabs()
                    end
                    if bliz then
                        bliz:EnableMouse(true)
                        bliz:Click()
                        bliz:EnableMouse(false)
                    end
                end
                _activeSubTab = i
                UpdateSubTabs()
                UpdateCustomTabs()
            end)

            ct:SetWidth(60)
            if i == 1 then
                ct:SetPoint("TOPLEFT", FriendsListFrame, "TOPLEFT", 15, -70)
            else
                ct:SetPoint("LEFT", customSubTabs[i - 1], "RIGHT", 20, 0)
            end

            customSubTabs[i] = ct
        end

        -- Extra sub-tab: "Ignored"
        do
            local index = #customSubTabs + 1
            local ct = CreateFrame("Button", nil, widget)
            ct:SetFrameLevel(widget:GetFrameLevel() + 5)
            ct:SetHeight(20)

            local label = ct:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontFile, 11, "")
            label:SetPoint("LEFT", ct, "LEFT", 0, 0)
            label:SetJustifyH("LEFT")
            label:SetText(IGNORE or "Ignored")
            ct._label = label
            ct._label:SetTextColor(1, 1, 1, 0.53)

            ct:SetScript("OnEnter", function()
                ct._label:SetTextColor(1, 1, 1, 0.86)
            end)
            ct:SetScript("OnLeave", function()
                ct._label:SetTextColor(1, 1, 1, 0.53)
            end)
            ct:SetScript("OnClick", function()
                local ilw = FriendsFrame and FriendsFrame.IgnoreListWindow
                if ilw and ilw.ToggleFrame then
                    ilw:ToggleFrame()
                end
            end)

            ct:SetWidth(60)
            ct:SetPoint("LEFT", customSubTabs[index - 1], "RIGHT", 20, 0)
            customSubTabs[index] = ct
        end

        local lastSubTab = customSubTabs[#customSubTabs]
        if lastSubTab then
            local orbBtn = CreateFrame("Button", nil, widget)
            orbBtn:SetSize(26, 26)
            orbBtn:SetFrameLevel(widget:GetFrameLevel() + 5)
            orbBtn:SetPoint("RIGHT", FriendsListFrame, "TOPRIGHT", -10, -80)
            local orbTex = orbBtn:CreateTexture(nil, "ARTWORK", nil, 2)
            orbTex:SetAllPoints()
            local orbInfo2 = C_Texture.GetAtlasInfo("lootroll-animreveal-a")
            if orbInfo2 then
                orbTex:SetTexture(orbInfo2.file)
                local aL = orbInfo2.leftTexCoord or 0
                local aR = orbInfo2.rightTexCoord or 1
                local aT = orbInfo2.topTexCoord or 0
                local aB = orbInfo2.bottomTexCoord or 1
                local aW, aH = aR - aL, aB - aT
                orbTex:SetTexCoord(aL, aL + aW / 6, aT, aT + aH / 2)
            end

            local function UpdatePlayerOrb()
                local status = GetPlayerStatusName()
                if status == (BUSY or "Busy") then
                    orbTex:SetVertexColor(1, 0.2, 0.2, 1)
                elseif status == (AWAY or "Away") then
                    orbTex:SetVertexColor(1, 0.8, 0, 1)
                else
                    orbTex:SetVertexColor(0.2, 1, 0.2, 1)
                end
            end
            UpdatePlayerOrb()

            orbBtn:SetScript("OnClick", function()
                if InCombatLockdown() then
                    return
                end
                local status = GetPlayerStatusName()
                if status == (FRIENDS_LIST_ONLINE or "Online") then
                    C_ChatInfo.SendChatMessage("", "AFK")
                    if BNSetAFK then
                        BNSetAFK(true)
                    end
                elseif status == (AWAY or "Away") then
                    C_ChatInfo.SendChatMessage("", "AFK")
                    C_ChatInfo.SendChatMessage("", "DND")
                    if BNSetAFK then
                        BNSetAFK(false)
                    end
                    if BNSetDND then
                        BNSetDND(true)
                    end
                else
                    C_ChatInfo.SendChatMessage("", "DND")
                    if BNSetDND then
                        BNSetDND(false)
                    end
                    if BNSetAFK then
                        BNSetAFK(false)
                    end
                end
            end)
            orbBtn:SetScript("OnEnter", function(self)
                CludesUI.ShowWidgetTooltip(self, "Status: " .. GetPlayerStatusName() .. "\nClick to change")
            end)
            orbBtn:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            -- Listener runs only while the panel is shown; the Show hook repaints once on open to catch flags changed while closed.
            local statusEvt = CreateFrame("Frame")
            statusEvt:SetScript("OnEvent", function()
                UpdatePlayerOrb()
            end)
            if widget:IsShown() then
                statusEvt:RegisterEvent("PLAYER_FLAGS_CHANGED")
            end
            GetFFD(widget).statusEvt = statusEvt
            GetFFD(widget).updatePlayerOrb = UpdatePlayerOrb

            GetFFD(widget).statusOrb = orbBtn

            local bcBtn = CreateFrame("Button", nil, widget)
            bcBtn:SetSize(20, 20)
            bcBtn:SetFrameLevel(orbBtn:GetFrameLevel())
            bcBtn:SetPoint("RIGHT", orbBtn, "LEFT", -2, 0)
            local bcIcon = bcBtn:CreateTexture(nil, "ARTWORK")
            bcIcon:SetAllPoints()
            bcIcon:SetAtlas("voicechat-icon-textchat-silenced")
            bcIcon:SetDesaturated(true)
            bcIcon:SetVertexColor(1, 1, 1)
            bcBtn:SetAlpha(0.6)
            bcBtn:SetScript("OnEnter", function(self)
                CludesUI.ShowWidgetTooltip(self, "Set Status Message")
            end)
            bcBtn:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            bcBtn:SetScript("OnClick", function()
                if InCombatLockdown() then
                    return
                end
                local bf = FriendsFrameBattlenetFrame and FriendsFrameBattlenetFrame.BroadcastFrame
                if not bf then
                    return
                end
                if bf:IsShown() then
                    bf:Hide()
                else
                    bf:Show()
                end
            end)
            GetFFD(widget).broadcastBtn = bcBtn
        end

        if customSubTabs[1] then
            customSubTabs[1]._label:SetTextColor(1, 1, 1, 1)
        end
        C_Timer.After(0.1, UpdateSubTabs)
        C_Timer.After(0.5, UpdateSubTabs)
        hooksecurefunc(widget, "Show", function()
            C_Timer.After(0.1, UpdateSubTabs)
        end)
    end
    SkinSubTabs()

    -- Scrollbars: NEVER RegisterCallback/SetScript on Blizzard's ScrollBar (the taint source) -- textures and points only.
    do
        local barFrame = FriendsListFrame and FriendsListFrame.ScrollBar
        if barFrame then
            StripTextures(barFrame)
            if barFrame.Background then
                barFrame.Background:Hide()
            end
            -- Collapse arrows to zero height so track fills full length
            if barFrame.Back then
                barFrame.Back:SetAlpha(0)
                barFrame.Back:SetSize(1, 0.001)
            end
            if barFrame.Forward then
                barFrame.Forward:SetAlpha(0)
                barFrame.Forward:SetSize(1, 0.001)
            end
            local track = barFrame.Track
            if track then
                track:DisableDrawLayer("ARTWORK")
                track:DisableDrawLayer("BACKGROUND")
                track:ClearAllPoints()
                track:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
                track:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
            end
            local thumb = barFrame.GetThumb and barFrame:GetThumb()
            if thumb then
                thumb:DisableDrawLayer("ARTWORK")
                thumb:DisableDrawLayer("BACKGROUND")
                local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
                thumbTex:SetColorTexture(1, 1, 1, 0.4)
                thumbTex:SetWidth(3)
                thumbTex:SetPoint("TOP", thumb, "TOP", 0, 0)
                thumbTex:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
                thumbTex:SetPoint("RIGHT", thumb, "RIGHT", 0, 0)
            end
            barFrame:SetWidth(5)
            local p1, rel, p2, ox, oy = barFrame:GetPoint(1)
            if p1 then
                barFrame:SetPoint(p1, rel, p2, (ox or 0) - 6, (oy or 0) + 4)
            end
            barFrame:SetAlpha(0.6)
            barFrame:HookScript("OnEnter", function()
                barFrame:SetAlpha(0.95)
            end)
            barFrame:HookScript("OnLeave", function()
                barFrame:SetAlpha(0.6)
            end)
            if thumb then
                thumb:HookScript("OnEnter", function()
                    barFrame:SetAlpha(0.95)
                end)
                thumb:HookScript("OnLeave", function()
                    barFrame:SetAlpha(0.6)
                end)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Search bar with instant dropdown results
    ---------------------------------------------------------------------------
    do -- search bar
        local search = CreateFrame("EditBox", nil, widget)
        search:SetSize(FriendsListFrame:GetWidth() - 30, 20)
        search:SetPoint("TOPLEFT", FriendsListFrame, "TOPLEFT", 15, -40)
        search:SetPoint("TOPRIGHT", FriendsListFrame, "TOPRIGHT", -15, -40)
        search:SetFrameLevel(widget:GetFrameLevel() + 5)
        search:SetAutoFocus(false)
        search:SetMaxLetters(20)
        search:SetJustifyH("LEFT")
        search:SetFont(fontFile, 10, "")
        search:SetTextColor(1, 1, 1, 0.9)

        local sBg = search:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        sBg:SetColorTexture(0, 0, 0, 0.4)
        Pix.CreateBorder(search, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
        GetFFD(widget).searchBg = sBg

        local sPh = search:CreateFontString(nil, "OVERLAY")
        sPh:SetFont(fontFile, 10, "")
        sPh:SetTextColor(0.5, 0.5, 0.5, 0.6)
        sPh:SetPoint("LEFT", search, "LEFT", 6, 0)
        sPh:SetText("Invite Friend...")

        local clearBtn = CreateFrame("Button", nil, search)
        clearBtn:SetSize(14, 14)
        clearBtn:SetPoint("RIGHT", search, "RIGHT", -4, 0)
        clearBtn:SetFrameLevel(search:GetFrameLevel() + 1)
        local clearX = clearBtn:CreateFontString(nil, "OVERLAY")
        clearX:SetFont(fontFile, 11, "")
        clearX:SetText("x")
        clearX:SetTextColor(1, 1, 1, 0.3)
        clearX:SetPoint("CENTER", 0, 0)
        clearBtn:SetScript("OnEnter", function()
            clearX:SetTextColor(1, 1, 1, 0.7)
        end)
        clearBtn:SetScript("OnLeave", function()
            clearX:SetTextColor(1, 1, 1, 0.3)
        end)
        clearBtn:SetScript("OnClick", function()
            search:SetText("")
            search:ClearFocus()
        end)
        clearBtn:Hide()
        search:SetTextInsets(6, 18, 0, 0)
        search:SetScript("OnEditFocusLost", function(self)
            C_Timer.After(0.15, function()
                if not search:HasFocus() then
                    search:SetText("")
                    clearBtn:Hide()
                end
            end)
        end)

        local dropdown = CreateFrame("Frame", nil, widget)
        dropdown:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -2)
        dropdown:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -2)
        dropdown:SetFrameLevel(widget:GetFrameLevel() + 10)
        dropdown:Hide()

        local ddBg = dropdown:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints()
        ddBg:SetColorTexture(0.04, 0.05, 0.06, 0.97)
        Pix.CreateBorder(dropdown, 1, 1, 1, 0.15, 1, "OVERLAY", 7)
        GetFFD(widget).searchMenuBg = ddBg

        local ROW_H = 24
        local MAX_RESULTS = 8
        local resultRows = {}

        local function GetResultRow(index)
            if resultRows[index] then
                return resultRows[index]
            end
            local row = CreateFrame("Button", nil, dropdown)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 1, -1 - (index - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -1, -1 - (index - 1) * ROW_H)

            local hover = row:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.06)

            -- A friend's name: a font family, which draws the scripts the font lacks
            local nameFS = row:CreateFontString(nil, "OVERLAY")
            CludesUI.SetFontFamily(nameFS, fontFile, 11, "", false)
            nameFS:SetPoint("LEFT", row, "LEFT", 8, 0)
            nameFS:SetWidth((FriendsListFrame:GetWidth() - 30) * 0.75)
            nameFS:SetJustifyH("LEFT")
            nameFS:SetWordWrap(false)
            row._name = nameFS

            local infoFS = row:CreateFontString(nil, "OVERLAY")
            infoFS:SetFont(fontFile, 9, "")
            infoFS:SetTextColor(0.5, 0.5, 0.5, 0.8)
            infoFS:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            infoFS:SetJustifyH("RIGHT")
            row._info = infoFS

            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(_, mouseBtn)
                local targetType = row._matchType
                local targetId = row._matchId
                local cached = row._cached

                if cached and targetType == FRIENDS_BUTTON_TYPE_BNET then
                    if cached.gameAccountInfo and cached.gameAccountInfo.isOnline then
                        local charName = cached.gameAccountInfo.characterName
                        local realmName = cached.gameAccountInfo.realmName
                        if charName then
                            -- Canonical "Name-Realm" (the helper returns nil for an
                            -- empty name; fall back rather than invite nil).
                            local fullName = CludesUI.BuildFullName(charName, realmName) or charName
                            C_PartyInfo.InviteUnit(fullName)
                        end
                    end
                elseif cached and targetType == FRIENDS_BUTTON_TYPE_WOW then
                    if cached.name and cached.connected then
                        C_PartyInfo.InviteUnit(CludesUI.BuildFullName(cached.name) or cached.name)
                    end
                end
                search:SetText("")
                search:ClearFocus()
            end)

            resultRows[index] = row
            return row
        end

        local function UpdateDropdown(term)
            if term == "" then
                dropdown:Hide()
                return
            end

            RefreshFriendCache()
            local matches = {}
            for key, details in pairs(_friendCache) do
                if key <= _FC_WOW_OFFSET then
                    local btag = (details.battleTag or ""):lower()
                    local acctName = (details.accountName or ""):lower()
                    local charName = ""
                    if details.gameAccountInfo and details.gameAccountInfo.characterName then
                        charName = details.gameAccountInfo.characterName:lower()
                    end
                    local areaName = ""
                    if details.gameAccountInfo and details.gameAccountInfo.areaName then
                        areaName = details.gameAccountInfo.areaName:lower()
                    end
                    if
                        strfind(btag, term, 1, true)
                        or strfind(acctName, term, 1, true)
                        or strfind(charName, term, 1, true)
                        or strfind(areaName, term, 1, true)
                    then
                        local displayName = details.accountName or details.battleTag or ""
                        local charDisplay = details.gameAccountInfo and details.gameAccountInfo.characterName
                            or ""
                        local areaDisplay = details.gameAccountInfo and details.gameAccountInfo.areaName or ""
                        local isOnline = details.gameAccountInfo and details.gameAccountInfo.isOnline
                        local class = GetFriendClassFile(details, nil)
                        matches[#matches + 1] = {
                            buttonType = FRIENDS_BUTTON_TYPE_BNET,
                            id = key,
                            display = displayName,
                            char = charDisplay,
                            area = areaDisplay,
                            online = isOnline,
                            classFile = class,
                            sortName = btag,
                        }
                    end
                else
                    local wowId = key - _FC_WOW_OFFSET
                    local name = (details.name or ""):lower()
                    if strfind(name, term, 1, true) then
                        local class = GetFriendClassFile(nil, details)
                        matches[#matches + 1] = {
                            buttonType = FRIENDS_BUTTON_TYPE_WOW,
                            id = wowId,
                            display = details.name or "",
                            char = "",
                            online = details.connected,
                            classFile = class,
                            sortName = name,
                        }
                    end
                end
            end

            if #matches == 0 then
                dropdown:Hide()
                return
            end

            table.sort(matches, function(a, b)
                if a.online ~= b.online then
                    return a.online
                end
                return a.sortName < b.sortName
            end)

            local sb = FriendsListFrame and FriendsListFrame.ScrollBox
            local dp = sb and sb:GetDataProvider()

            local isShown = math.min(#matches, MAX_RESULTS)
            for i = 1, isShown do
                local m = matches[i]
                local row = GetResultRow(i)
                local nameText = m.display
                if m.online then
                    -- Class-color the character name portion, append zone
                    local areaSuffix = (m.area and m.area ~= "") and (" |cff888888- " .. m.area .. "|r") or ""
                    if m.classFile and m.char ~= "" then
                        local cc = _getClassColorCode(m.classFile)
                        if cc then
                            nameText = nameText .. " (" .. cc .. m.char .. "|r)" .. areaSuffix
                        else
                            nameText = nameText .. " (" .. m.char .. ")" .. areaSuffix
                        end
                    elseif m.char ~= "" then
                        nameText = nameText .. " |cff888888(" .. m.char .. ")|r" .. areaSuffix
                    end
                    local bnc = FRIENDS_BNET_NAME_COLOR or { r = 0.510, g = 0.773, b = 1.0 }
                    row._name:SetTextColor(bnc.r, bnc.g, bnc.b)
                else
                    if m.char ~= "" then
                        nameText = nameText .. " |cff555555(" .. m.char .. ")|r"
                    end
                    row._name:SetTextColor(0.5, 0.5, 0.5)
                end
                row._name:SetText(nameText)
                row._info:SetText(m.online and "|cff33ff33Online|r" or "|cff666666Offline|r")

                row._matchType = m.buttonType
                row._matchId = m.id
                -- Store cached data for whisper/invite
                if m.buttonType == FRIENDS_BUTTON_TYPE_BNET then
                    row._cached = _friendCache[m.id]
                else
                    row._cached = _friendCache[m.id + _FC_WOW_OFFSET]
                end
                row._dpIndex = nil
                if dp then
                    local index = 0
                    for _, ed in dp:Enumerate() do
                        index = index + 1
                        if ed.buttonType == m.buttonType and ed.id == m.id then
                            row._dpIndex = index
                            break
                        end
                    end
                end
                row:Show()
            end

            for i = isShown + 1, #resultRows do
                resultRows[i]:Hide()
            end

            dropdown:SetHeight(isShown * ROW_H + 2)
            dropdown:Show()
        end

        search:SetScript("OnTextChanged", function(self)
            local t = strtrim(self:GetText())
            sPh:SetShown(t == "")
            clearBtn:SetShown(t ~= "")
            UpdateDropdown(t:lower())
        end)
        search:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
        end)
        search:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)

        GetFFD(widget).searchBox = search
        GetFFD(widget).searchDropdown = dropdown
    end

    local function SyncFriendsTabLabels()
        for i = 1, (FriendsFrame and FriendsFrame.numTabs) or 4 do
            local tab = _G["FriendsFrameTab" .. i]
            if tab then
                local tfd = GetFFD(tab)
                if tfd.label then
                    local bliz = tab:GetFontString()
                    local txt = bliz and bliz:GetText()
                    if txt then
                        tfd.label:SetText(txt)
                    end
                end
            end
        end
    end

    -- Dirty flag drains next frame so addon code never runs inside Blizzard's secure dispatch; driver frame stays hidden while clean.
    local _forceFriendSkin = false
    local skinDriver = CreateFrame("Frame")
    skinDriver:Hide()
    skinDriver:SetScript("OnUpdate", function(self)
        self:Hide()
        local force = _forceFriendSkin
        _forceFriendSkin = false
        ProcessFriendButtons(force)
    end)
    local function MarkSkinDirty(force)
        _forceFriendSkin = _forceFriendSkin or force
        local sb = FriendsListFrame and FriendsListFrame.ScrollBox
        if not sb or not sb:IsVisible() or LegacyFriendsRetired() then
            return
        end
        skinDriver:Show()
    end

    -- The native initializer runs for recycled rows on every scroll path, too.
    -- Only mark external state here; defer all API reads and styling.
    if FriendsFrame_UpdateFriendButton then
        hooksecurefunc("FriendsFrame_UpdateFriendButton", function(btnFrame)
            if
                not btnFrame
                or (
                    btnFrame.buttonType ~= FRIENDS_BUTTON_TYPE_BNET
                    and btnFrame.buttonType ~= FRIENDS_BUTTON_TYPE_WOW
                )
            then
                return
            end
            GetFFD(btnFrame).stampType = nil
            MarkSkinDirty()
        end)
    end

    -- Visibility edges ride FriendsListFrame (the tab content frame), NEVER
    -- the ScrollBox: that object's interaction surface is mapped radioactive
    -- for whisper taint (see the module history above), and the parent
    -- carries the exact same show/hide edge -- the ScrollBox is visible iff
    -- its tab content frame is.
    if FriendsListFrame then
        FriendsListFrame:HookScript("OnShow", function()
            _friendCacheDirty = true
            MarkSkinDirty(true)
        end)
        FriendsListFrame:HookScript("OnHide", function()
            skinDriver:Hide()
            _forceFriendSkin = false
        end)
        if FriendsListFrame:IsVisible() then
            MarkSkinDirty(true)
        end
    end

    local friendsEventFrame = CreateFrame("Frame")
    friendsEventFrame:SetScript("OnEvent", function(_, evt)
        _friendCacheDirty = true
        SyncFriendsTabLabels()
        MarkSkinDirty(true)
    end)

    local function RegisterFriendsEvents()
        friendsEventFrame:RegisterEvent("FRIENDLIST_UPDATE")
        friendsEventFrame:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
        friendsEventFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
        friendsEventFrame:RegisterEvent("BN_FRIEND_INVITE_ADDED")
        friendsEventFrame:RegisterEvent("BN_FRIEND_INVITE_REMOVED")
    end
    local function UnregisterFriendsEvents()
        friendsEventFrame:UnregisterAllEvents()
    end
    if FriendsFrame:IsShown() then
        RegisterFriendsEvents()
    end

    -- Events live only while the panel is open.
    widget:HookScript("OnHide", function()
        UnregisterFriendsEvents()
        local fd = GetFFD(widget)
        if fd.statusEvt then
            fd.statusEvt:UnregisterAllEvents()
        end
    end)
    widget:HookScript("OnShow", function()
        RegisterFriendsEvents()
        _friendCacheDirty = true
        MarkSkinDirty(true)
        local fd = GetFFD(widget)
        if fd.statusEvt then
            fd.statusEvt:RegisterEvent("PLAYER_FLAGS_CHANGED")
            if fd.updatePlayerOrb then
                fd.updatePlayerOrb()
            end
        end
    end)

    ---------------------------------------------------------------------------
    --  Skin Who / Raid / Quick Join tabs
    ---------------------------------------------------------------------------
    local function StripFrameChrome(frame)
        if not frame then
            return
        end
        StripTextures(frame)
        if frame.NineSlice then
            frame.NineSlice:Hide()
        end
        if frame.Bg then
            frame.Bg:Hide()
        end
        if frame.Inset then
            StripTextures(frame.Inset)
            if frame.Inset.NineSlice then
                frame.Inset.NineSlice:Hide()
            end
            if frame.Inset.Bg then
                frame.Inset.Bg:Hide()
            end
        end
    end

    -- Who tab
    do
        local who = WhoFrame
        if who then
            StripFrameChrome(who)
            who:ClearAllPoints()
            who:SetPoint("TOPLEFT", widget, "TOPLEFT", 7, 0)
            who:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -11, 0)

            local whoInset = _G.WhoFrameListInset
            if whoInset then
                StripTextures(whoInset)
                if whoInset.Bg then
                    whoInset.Bg:Hide()
                end
                if whoInset.NineSlice then
                    StripTextures(whoInset.NineSlice)
                    whoInset.NineSlice:Hide()
                end
                whoInset:SetClipsChildren(true)
                whoInset:ClearAllPoints()
                whoInset:SetPoint("TOPLEFT", widget, "TOPLEFT", 15, -92)
                whoInset:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -15, 35)
                local whoBg = whoInset:CreateTexture(nil, "BACKGROUND", nil, -5)
                whoBg:SetAllPoints()
                whoBg:SetColorTexture(0, 0.08, 0.10, 0.35)
                GetFFD(widget).whoBg = whoBg
                Pix.CreateBorder(whoInset, 1, 1, 1, 0.1, 1, "OVERLAY", 5)
            end

            for i = 1, 4 do
                local colour = _G["WhoFrameColumnHeader" .. i]
                if colour then
                    hooksecurefunc(colour, "SetPoint", function(self)
                        if GetFFD(self).adjusting then
                            return
                        end
                        GetFFD(self).adjusting = true
                        local p1, rel, p2, posX, posY = self:GetPoint(1)
                        if p1 then
                            self:ClearAllPoints()
                            local xOff = (i == 1) and 5 or 0
                            self:SetPoint(p1, rel, p2, (posX or 0) + xOff, (posY or 0) + 10)
                        end
                        GetFFD(self).adjusting = false
                    end)
                end
            end

            local col1 = _G["WhoFrameColumnHeader1"]
            local whoInset2 = _G.WhoFrameListInset
            if col1 and whoInset2 then
                local headerBg = who:CreateTexture(nil, "BACKGROUND", nil, -6)
                headerBg:SetPoint("TOPLEFT", col1, "TOPLEFT", 0, 0)
                headerBg:SetPoint("RIGHT", whoInset2, "RIGHT", 0, 0)
                headerBg:SetHeight(col1:GetHeight())
                headerBg:SetColorTexture(0, 0, 0, 0.3)
            end

            for i = 1, 4 do
                local colour = _G["WhoFrameColumnHeader" .. i]
                if colour then
                    StripTextures(colour)
                    local textValue = colour:GetFontString()
                    if textValue then
                        textValue:SetFont(fontFile, 10, "")
                        textValue:SetTextColor(1, 1, 1, 0.5)
                    end
                    colour:SetClipsChildren(true)
                    local hlTex = colour:CreateTexture(nil, "HIGHLIGHT")
                    local nextCol = _G["WhoFrameColumnHeader" .. (i + 1)]
                    if nextCol then
                        hlTex:SetPoint("TOPLEFT", colour, "TOPLEFT", 0, 0)
                        hlTex:SetPoint("BOTTOMRIGHT", nextCol, "BOTTOMLEFT", 0, 0)
                    else
                        local whoInset3 = _G.WhoFrameListInset
                        if whoInset3 then
                            hlTex:SetPoint("TOPLEFT", colour, "TOPLEFT", 0, 0)
                            hlTex:SetPoint("BOTTOM", colour, "BOTTOM", 0, 0)
                            hlTex:SetPoint("RIGHT", whoInset3, "RIGHT", 0, 0)
                        else
                            hlTex:SetAllPoints()
                        end
                    end
                    hlTex:SetColorTexture(1, 1, 1, 0.1)
                    hlTex:SetBlendMode("ADD")
                    if i > 1 then
                        local div = colour:CreateTexture(nil, "OVERLAY", nil, 7)
                        Pix.DisablePixelSnap(div)
                        div:SetWidth(Pix.mult or 1)
                        div:SetColorTexture(1, 1, 1, 0.1)
                        div:SetPoint("TOPLEFT", colour, "TOPLEFT", 0, -2)
                        div:SetPoint("BOTTOMLEFT", colour, "BOTTOMLEFT", 0, 2)
                    end
                end
            end

            local zoneDropdown = _G.WhoFrameDropdown
            if zoneDropdown then
                zoneDropdown:SetAlpha(0)
                zoneDropdown:SetSize(1, 1)
                zoneDropdown:EnableMouse(false)
                zoneDropdown:ClearAllPoints()
                zoneDropdown:SetPoint("TOPLEFT", who, "TOPLEFT", 0, 0)
            end

            local editBox = _G.WhoFrameEditBox
            if editBox then
                StripTextures(editBox)
                editBox:SetScale(0.9)
                local p1, rel, p2, ox, oy = editBox:GetPoint(1)
                if p1 then
                    editBox:SetPoint(p1, rel, p2, (ox or 0) - 1, (oy or 0) + 3)
                end
                local ebBg = editBox:CreateTexture(nil, "BACKGROUND", nil, -6)
                ebBg:SetColorTexture(0, 0, 0, 0.4)
                ebBg:SetAllPoints()
                editBox:SetTextColor(1, 1, 1, 0.8)
                Pix.CreateBorder(editBox, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
                GetFFD(widget).whoEdit = editBox
                GetFFD(widget).whoEditBg = ebBg
            end

            local totalCount = _G.WhoFrameTotals
            if totalCount and totalCount.SetFont then
                totalCount:SetFont(fontFile, 10, "")
                totalCount:SetTextColor(1, 1, 1, 0.5)
            end

            local whoInsetRef = _G.WhoFrameListInset
            local whoBtnNames =
                { "WhoFrameWhoButton", "WhoFrameAddFriendButton", "WhoFrameGroupInviteButton" }
            if whoInsetRef then
                local function LayoutWhoBtns()
                    local totalW2 = whoInsetRef:GetWidth()
                    local btnW = math.floor(totalW2 / 3)
                    local btnY = -22 - 10 + 10
                    local btns = {}
                    for _, name in ipairs(whoBtnNames) do
                        btns[#btns + 1] = _G[name]
                    end
                    if btns[1] then
                        btns[1]:ClearAllPoints()
                        btns[1]:SetSize(btnW, 22)
                        btns[1]:SetPoint("BOTTOMLEFT", whoInsetRef, "BOTTOMLEFT", 0, btnY)
                    end
                    if btns[2] then
                        btns[2]:ClearAllPoints()
                        btns[2]:SetSize(btnW, 22)
                        btns[2]:SetPoint("BOTTOMLEFT", whoInsetRef, "BOTTOMLEFT", btnW, btnY)
                    end
                    if btns[3] then
                        btns[3]:ClearAllPoints()
                        btns[3]:SetSize(btnW, 22)
                        btns[3]:SetPoint("BOTTOMRIGHT", whoInsetRef, "BOTTOMRIGHT", 0, btnY)
                    end
                end
                for _, name in ipairs(whoBtnNames) do
                    local button = _G[name]
                    if button then
                        SkinBottomButton(button)
                        hooksecurefunc(button, "Disable", function(self)
                            self:SetAlpha(0.4)
                        end)
                        hooksecurefunc(button, "Enable", function(self)
                            self:SetAlpha(1)
                        end)
                        if not button:IsEnabled() then
                            button:SetAlpha(0.4)
                        end
                    end
                end
                LayoutWhoBtns()
                who:HookScript("OnShow", LayoutWhoBtns)
            end

            local function SkinWhoRows()
                for i = 1, 22 do
                    local button = _G["WhoFrameButton" .. i]
                    if button and not GetFFD(button).skinned then
                        GetFFD(button).skinned = true
                        StripTextures(button)
                        local hover2 = button:CreateTexture(nil, "HIGHLIGHT")
                        hover2:SetAllPoints()
                        hover2:SetColorTexture(1, 1, 1, 0.04)
                        hover2:SetBlendMode("ADD")
                        for _, key in ipairs({ "Name", "Level", "Class", "Variable" }) do
                            local txt = _G["WhoFrameButton" .. i .. key]
                            if txt and txt.SetFont then
                                txt:SetFont(fontFile, 11, "")
                            end
                        end
                    end
                end
            end
            SkinWhoRows()
            who:HookScript("OnShow", SkinWhoRows)

            local sb = who.ScrollBox or who.scrollFrame
            if sb then
                local p1, rel, p2, posX, posY = sb:GetPoint(1)
                if p1 then
                    sb:SetPoint(p1, rel, p2, (posX or 0) + 5, (posY or 0) - 35)
                end
            end

            who:ClearAllPoints()
            who:SetPoint("TOPLEFT", widget, "TOPLEFT", 7, -10)
            who:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -11, 10)

            if col1 then
                col1:ClearAllPoints()
                col1:SetPoint("TOPLEFT", widget, "TOPLEFT", 7, -102)
            end

            local barFrame = sb and (sb.ScrollBar or who.ScrollBar) or who.ScrollBar
            if sb and barFrame then
                SkinOneScrollbar(sb, barFrame)
            end
        end
    end

    -- Quick Join tab
    do
        local qjf = _G.QuickJoinFrame
        if qjf then
            local qjScroll = qjf.ScrollBox or (qjf.List and qjf.List.ScrollBox)
            if qjScroll then
                qjScroll:ClearAllPoints()
                qjScroll:SetPoint("TOPLEFT", widget, "TOPLEFT", 15, -92)
                qjScroll:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -15, 35)

                if not GetFFD(qjScroll).borderAdded then
                    GetFFD(qjScroll).borderAdded = true
                    local bdr = CreateFrame("Frame", nil, qjf)
                    bdr:SetPoint("TOPLEFT", qjScroll, "TOPLEFT", 0, 0)
                    bdr:SetPoint("BOTTOMRIGHT", qjScroll, "BOTTOMRIGHT", 0, 0)
                    bdr:SetFrameLevel(qjScroll:GetFrameLevel() + 2)
                    Pix.CreateBorder(bdr, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
                end

                local qjBar = qjScroll.ScrollBar or (qjf.List and qjf.List.ScrollBar) or qjf.ScrollBar
                if qjBar then
                    SkinOneScrollbar(qjScroll, qjBar)
                end
            end

            local joinBtn = qjf.JoinQueueButton
            if joinBtn and qjScroll then
                SkinBottomButton(joinBtn)
                -- Width from FriendsFrame, never qjScroll: QuickJoinFrame is
                -- XML-hidden at skin time, so qjScroll has no layout pass and
                -- GetWidth() is 0 -- and SetSize with width 0 UNSETS the width,
                -- leaving an anchored frame with no resolvable rect (never
                -- drawn, yet IsShown/IsVisible/alpha all read healthy).
                -- qjScroll is inset 15 each side of the frame, so (w - 30) / 3
                -- matches LayoutFriendBtns' sizing for the sibling buttons.
                -- A failed measure leaves the button untouched: ClearAllPoints
                -- only runs when a re-point follows.
                local function LayoutJoinBtn()
                    local wid = widget:GetWidth()
                    if not wid or wid <= 0 then
                        return
                    end
                    joinBtn:ClearAllPoints()
                    joinBtn:SetSize(math.max(1, math.floor((wid - 30) / 3)), 22)
                    joinBtn:SetPoint("BOTTOMRIGHT", qjScroll, "BOTTOMRIGHT", 0, -22)
                end
                LayoutJoinBtn()
                -- Re-apply on show so a zero-measure pass self-repairs.
                -- HookScript, not hooksecurefunc: method hooks in this module
                -- taint BNet whispers; script hooks register C-side (same shape
                -- as the tab watcher's hook on this frame).
                qjf:HookScript("OnShow", LayoutJoinBtn)
            end
        end
    end

    -- Border/bg live on frames we own; NEVER reference FriendsListFrame.ScrollBox, even as an anchor -- it taints BNet whispers.
    if not GetFFD(widget).listOverlay then
        local overlayFrame = CreateFrame("Frame", nil, widget)
        overlayFrame:SetPoint("TOPLEFT", widget, "TOPLEFT", 15, -92)
        overlayFrame:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -15, 35)
        overlayFrame:SetFrameLevel(widget:GetFrameLevel() + 1)
        local sbBg = overlayFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        sbBg:SetAllPoints()
        sbBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
        GetFFD(widget).listBg = sbBg
        GetFFD(widget).listOverlay = overlayFrame

        local bdr = CreateFrame("Frame", nil, widget)
        bdr:SetPoint("TOPLEFT", widget, "TOPLEFT", 15, -92)
        bdr:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -15, 35)
        bdr:SetFrameLevel(widget:GetFrameLevel() + 3)
        Pix.CreateBorder(bdr, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
        GetFFD(widget).listBdr = bdr
    end

    -- Bottom buttons: anchored to the frame, never to the ScrollBox.
    SkinRaidTab()
    do
        local BTN_H = 22
        local btnFont = CludesUI.GetFontPath("friends") or STANDARD_TEXT_FONT
        local addBtn = _G.FriendsFrameAddFriendButton
        local msgBtn = _G.FriendsFrameSendMessageButton
        local fp8 = SKIN.db and SKIN.db.profile and SKIN.db.profile.friends
        local btnAccent = fp8 and fp8.accentColors ~= false
        for _, button in ipairs({ addBtn, msgBtn }) do
            if button then
                StripTextures(button)
                local textValue = button:GetFontString()
                if textValue then
                    textValue:SetFont(btnFont, 9, "")
                    if button == msgBtn and btnAccent then
                        textValue:SetTextColor(ACC.r, ACC.g, ACC.b, 0.7)
                    else
                        textValue:SetTextColor(1, 1, 1, 0.5)
                    end
                end
            end
        end
        if addBtn and msgBtn then
            local BTN_GAP = 10
            local btnY = -BTN_H - BTN_GAP + 10

            -- Border-only overlays on frames we own (no background).
            local addBdr = CreateFrame("Frame", nil, widget)
            addBdr:SetFrameLevel(widget:GetFrameLevel() + 3)
            Pix.CreateBorder(addBdr, 1, 1, 1, 0.4, 1, "OVERLAY", 7)
            GetFFD(widget).addBdr = addBdr

            local msgBdr = CreateFrame("Frame", nil, widget)
            msgBdr:SetFrameLevel(widget:GetFrameLevel() + 3)
            local fp7 = SKIN.db and SKIN.db.profile and SKIN.db.profile.friends
            local useAccent = fp7 and fp7.accentColors ~= false
            if useAccent then
                Pix.CreateBorder(msgBdr, ACC.r, ACC.g, ACC.b, 0.5, 1, "OVERLAY", 7)
            else
                Pix.CreateBorder(msgBdr, 1, 1, 1, 0.4, 1, "OVERLAY", 7)
            end
            GetFFD(widget).msgBdr = msgBdr

            local function LayoutFriendBtns()
                local totalW4 = widget:GetWidth() - 30
                local btnW = math.floor(totalW4 / 3)
                addBtn:ClearAllPoints()
                addBtn:SetSize(btnW, BTN_H)
                addBtn:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 15, 35 + btnY)
                msgBtn:ClearAllPoints()
                msgBtn:SetSize(btnW, BTN_H)
                msgBtn:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -15, 35 + btnY)
                addBdr:ClearAllPoints()
                addBdr:SetAllPoints(addBtn)
                msgBdr:ClearAllPoints()
                msgBdr:SetAllPoints(msgBtn)
            end
            LayoutFriendBtns()
            hooksecurefunc(widget, "Show", LayoutFriendBtns)
        end
    end

    local TAB_H = 26
    local numCustomTabs = #customTabs
    if numCustomTabs > 0 then
        local m = Pix.mult or 1
        local function pxSnap(posX)
            if m == 1 then
                return posX
            end
            return math.floor(posX / m + 0.5) * m
        end
        local snappedTabH = pxSnap(TAB_H)
        local onePx = m
        local lastCT

        local TAB_WIDTHS = { 0.22, 0.22, 0.22, 0.34 }
        local frameW = widget:GetWidth() or 300
        for i, ct in ipairs(customTabs) do
            ct:ClearAllPoints()
            ct:SetHeight(snappedTabH)
            if i == 1 then
                ct:SetPoint("TOPLEFT", widget, "BOTTOMLEFT", 0, 0)
            else
                ct:SetPoint("TOPLEFT", customTabs[i - 1], "TOPRIGHT", 0, 0)
            end
            if i == numCustomTabs then
                ct:SetPoint("RIGHT", widget, "BOTTOMRIGHT", 0, 0)
            else
                ct:SetWidth(frameW * (TAB_WIDTHS[i] or 0.25))
            end

            if i > 1 then
                local ctd = GetFFD(ct)
                if not ctd.div then
                    ctd.div = ct:CreateTexture(nil, "OVERLAY", nil, 7)
                    Pix.DisablePixelSnap(ctd.div)
                end
                ctd.div:SetColorTexture(1, 1, 1, 0.08)
                ctd.div:SetSize(onePx, snappedTabH)
                ctd.div:ClearAllPoints()
                ctd.div:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, 0)
            end
            lastCT = ct
        end

        if GetFFD(widget).tabBarBg and lastCT then
            GetFFD(widget).tabBarBg:SetParent(customTabs[1])
            GetFFD(widget).tabBarBg:ClearAllPoints()
            GetFFD(widget).tabBarBg:SetPoint("TOPLEFT", widget, "BOTTOMLEFT", 0, 0)
            GetFFD(widget).tabBarBg:SetPoint("BOTTOMRIGHT", lastCT, "BOTTOMRIGHT", 0, 0)
            GetFFD(widget).tabBarBg:SetDrawLayer("BACKGROUND", -8)
        end

        if not GetFFD(widget).tabTopBorder then
            GetFFD(widget).tabTopBorder = customTabs[1]:CreateTexture(nil, "OVERLAY", nil, 7)
            Pix.DisablePixelSnap(GetFFD(widget).tabTopBorder)
            GetFFD(widget).tabTopBorder:SetColorTexture(1, 1, 1, 0.08)
            GetFFD(widget).tabTopBorder:SetHeight(onePx)
            GetFFD(widget).tabTopBorder:ClearAllPoints()
            GetFFD(widget).tabTopBorder:SetPoint("TOPLEFT", widget, "BOTTOMLEFT", 0, 0)
            GetFFD(widget).tabTopBorder:SetPoint("TOPRIGHT", lastCT, "TOPRIGHT", 0, 0)
        end

        UpdateCustomTabs()
    end

    local closeBtn = widget.CloseButton or _G.FriendsFrameCloseButton
    if closeBtn then
        StripTextures(closeBtn)
        GetFFD(widget).closeBtn = closeBtn
        GetFFD(closeBtn).x = closeBtn:CreateFontString(nil, "OVERLAY")
        GetFFD(closeBtn).x:SetFont(fontFile, 14, "")
        GetFFD(closeBtn).x:SetText("x")
        GetFFD(closeBtn).x:SetTextColor(1, 1, 1, 1)
        GetFFD(closeBtn).x:SetAlpha(0.5)
        GetFFD(closeBtn).x:SetPoint("CENTER", -2, -3)
        -- Idle / hover alphas follow the window-skin look (PaintChrome).
        closeBtn:HookScript("OnEnter", function()
            local cd = GetFFD(closeBtn)
            cd.x:SetAlpha(cd.hoverA or 0.9)
        end)
        closeBtn:HookScript("OnLeave", function()
            local cd = GetFFD(closeBtn)
            cd.x:SetAlpha(cd.idleA or 0.5)
        end)
    end

    -- Window Skins style picks and the Modern color repaint this live. The
    -- first paint follows every build call (ApplyFriends, EBS:OnEnable).
    local ws = ChromeEngine()
    if ws then
        ws.OnStylesChanged(OnChromeStylesChanged)
    end

    C_Timer.After(0, UpdateCustomTabs)
end

-- Live updates: colors, border, opacity
local function ApplyFriends()
    -- Every profile apply (live switch, spec switch, import) re-syncs the
    -- auto-accept listener before any look or combat gate below.
    if _G._CUFR_SyncAutoAccept then
        _G._CUFR_SyncAutoAccept()
    end
    if LegacyFriendsRetired() then
        return
    end
    local _mplus = C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    local _, _iT = IsInInstance()
    local _pvp = (_iT == "pvp" or _iT == "arena")
    if InCombatLockdown() or _mplus or _pvp then
        QueueApplyAll()
        return
    end

    local p = SKIN.db.profile.friends
    p.enabled = true

    if not p.enabled then
        return
    end

    if not FriendsFrame then
        return
    end
    SkinFriendsFrame()

    -- Backdrop, frame border, tabs, panes, inputs and close glyph for the
    -- current window-skin look (this module's own flat look when none applies).
    PaintChrome()

    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if scrollBox then
        for _, btnFrame in scrollBox:EnumerateFrames() do
            if GetFFD(btnFrame).tileBg then
                GetFFD(btnFrame).tileBg:SetColorTexture(0, 0, 0, 0.10)
            end
        end
    end

    UpdateBottomButtonAccent()
    UpdateRaidTabButtonAccent()
    if GetFFD(FriendsFrame).updateCustomTabs then
        GetFFD(FriendsFrame).updateCustomTabs()
    end
    if GetFFD(FriendsFrame).updateSubTabs then
        GetFFD(FriendsFrame).updateSubTabs()
    end

    if GetFFD(FriendsFrame).applyScaleAndPosition then
        GetFFD(FriendsFrame).applyScaleAndPosition()
    end
end

-- Visibility
local function UpdateFriendsVisibility()
    if LegacyFriendsRetired() then
        return
    end
    local p = SKIN.db and SKIN.db.profile and SKIN.db.profile.friends
    if not p or not p.enabled then
        return
    end
    if not FriendsFrame or not FriendsFrame:IsShown() then
        return
    end
    local vis = CludesUI.EvalVisibility(p)
    if vis == "mouseover" then
        FriendsFrame:SetAlpha(0)
    else
        FriendsFrame:SetAlpha(vis and 1 or 0)
    end
end

-- Apply All
ApplyAll = function()
    ApplyFriends()
    if CludesUI.RequestVisibilityUpdate then
        C_Timer.After(0, CludesUI.RequestVisibilityUpdate)
    end
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
-- This profile's friends table: the settings the shared friends kit reads
-- (CludesUI_FriendsKit.lua: the 12.1 tiles and the invite auto-accept).
local function FriendsSettings()
    local saved = SKIN.db
    return saved and saved.profile and saved.profile.friends
end

function SKIN:OnInitialize()
    SKIN.db = CludesUI.Lite.NewDB("CludesUIFriendsDB", defaultSet)

    -- Global bridge for options <-> main communication
    _G._CUFR_DB = SKIN.db
    _G._CUFR_ApplyFriends = ApplyFriends
    _G._CUFR_ProcessFriendButtons = function()
        ProcessFriendButtons(true)
    end

    -- Auto-accept group invites from friends (and guildmates, from its cog):
    -- CludesUI_FriendsKit.lua, reading this profile's friends table.
    _G._CUFR_SyncAutoAccept = function()
        CludesUI.FriendsKit.SyncAutoAccept(FriendsSettings)
    end
    _G._CUFR_SyncAutoAccept()

    -- Visibility updater + mouseover target register only while the panel is shown;
    -- both bill this addon (dispatcher fan-out per event, mouseover scan every 0.15s)
    -- but are true no-ops closed: updater early-outs on IsShown, proxy has no rect.
    local visProxy
    if CludesUI.RegisterMouseoverTarget then
        visProxy = CreateFrame("Frame")
        visProxy.IsShown = function()
            return FriendsFrame and FriendsFrame:IsShown()
        end
        visProxy.IsMouseOver = function()
            return FriendsFrame and FriendsFrame:IsMouseOver()
        end
        visProxy.SetAlpha = function(_, a2)
            if FriendsFrame then
                FriendsFrame:SetAlpha(a2)
            end
        end
    end
    local function VisWantsHover()
        local p2 = SKIN.db and SKIN.db.profile and SKIN.db.profile.friends
        if not (p2 and p2.enabled) then
            return false
        end
        -- Hover-gated sets only reveal while their conditions pass
        return CludesUI.VisWantsMouseover(p2, "visibility")
    end
    local visRegistered = false
    local function RegisterVis()
        if visRegistered then
            return
        end
        visRegistered = true
        CludesUI.RegisterVisibilityUpdater(UpdateFriendsVisibility)
        if visProxy then
            CludesUI.RegisterMouseoverTarget(visProxy, VisWantsHover)
        end
    end
    local function UnregisterVis()
        if not visRegistered then
            return
        end
        visRegistered = false
        CludesUI.UnregisterVisibilityUpdater(UpdateFriendsVisibility)
        if visProxy and CludesUI.UnregisterMouseoverTarget then
            CludesUI.UnregisterMouseoverTarget(visProxy)
        end
    end
    if FriendsFrame then
        hooksecurefunc(FriendsFrame, "Show", RegisterVis)
        hooksecurefunc(FriendsFrame, "Hide", UnregisterVis)
        if FriendsFrame:IsShown() then
            RegisterVis()
        end
    else
        -- Frame not created yet (load-on-demand): stay registered; closures early-out safely until it exists.
        RegisterVis()
    end
end

function SKIN:OnEnable()
    ApplyAll()

    -- Re-apply the skin when the accent color changes.
    if CludesUI._accentElements then
        CludesUI._accentElements[#CludesUI._accentElements + 1] = {
            type = "callback",
            fn = function()
                if FriendsFrame and SKIN.db.profile.friends.enabled then
                    ApplyFriends()
                end
            end,
        }
    end

    local loginRefresh = CreateFrame("Frame")
    loginRefresh:RegisterEvent("PLAYER_ENTERING_WORLD")
    loginRefresh:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(0, ApplyAll)
    end)

    -- Load-on-demand hook for FriendsFrame; skipped once the Social UI owns the window (this only drives the legacy skin).
    if SKIN.db.profile.friends.enabled and not LegacyFriendsRetired() then
        if not FriendsFrame then
            local hookFrame = CreateFrame("Frame")
            hookFrame:RegisterEvent("ADDON_LOADED")
            hookFrame:SetScript("OnEvent", function(self, evt, addon)
                if addon == "Blizzard_SocialUI" then
                    C_Timer.After(0.1, function()
                        if FriendsFrame and SKIN.db.profile.friends.enabled then
                            ApplyFriends()
                        end
                    end)
                    if FriendsFrame then
                        hooksecurefunc(FriendsFrame, "Show", function()
                            if not friendsSkinned and SKIN.db.profile.friends.enabled then
                                C_Timer.After(0, ApplyFriends)
                            end
                        end)
                    end
                end
            end)
        else
            if SKIN.db.profile.friends.enabled and not friendsSkinned then
                SkinFriendsFrame()
                PaintChrome()
            end
        end
    end
end

-------------------------------------------------------------------------------
--  12.1 Social UI tiles (CludesUI_FriendsKit.lua)
-------------------------------------------------------------------------------
-- Style page choice for this module: "cui" | "blizzard" | "classic", read from
-- the real profile once and latched for the session (a profile switch prompts
-- for a reload instead). Both stock styles mean the same to the tiles -- there
-- is no vanilla version of this list -- so they keep Blizzard's own list and
-- cards and add only the CludesUI decoration (class icon, class-coloured
-- name, region mark). The legacy-skin switch above reads it too.
function mod.FR_Style()
    local val = mod._frStyle
    if val == nil then
        local saved = SKIN.db
        local p = saved and saved.profile and saved.profile.friends
        if not p then
            return "cui"
        end
        val = (p.useClassicStyle and "classic") or (p.useBlizzardStyle and "blizzard") or "cui"
        mod._frStyle = val
    end
    return val
end

-- Options-driven repaints of the decorated cards and rows
_G._CUFR_RedecorateTiles = CludesUI.FriendsKit.RedecorateTiles

-- The kit hooks the card mixin at PLAYER_LOGIN, before any card exists.
do
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        CludesUI.FriendsKit.StartTiles({
            Settings = FriendsSettings,
            style = mod.FR_Style(),
            fontKey = "friends",
        })
    end)
end
