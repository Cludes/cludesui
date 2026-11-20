if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Friends list on WoW Forever
--
--  The Friends module (the retail friends list) stays off the Forever client,
--  and the Social UI pack in CludesUIBlizzardSkin_WindowPacks.lua skins
--  only the Social UI window, so Blizzard's legacy friends window took no
--  treatment. This gives it the standard window treatment under the
--  SAME "Friends List" card and key the Social UI pack uses (winKey
--  "socialui", enable key reskinSocialUI, the per-window style dropdown), so
--  every standard option applies and no enable or style key is added (the
--  card's own settings, friendsListCard, joined the export allowlist and the
--  module's reset list):
--    - the shell, border, top bar and house close button through the engine;
--      the corner portrait art, the nested inset box and the stock tab art
--      gone; the title in the house font;
--    - the contacts tab row across the top, the Battle.net strip with its
--      broadcast popup (panel, input, buttons), the status dropdown, the
--      Add Friend / Send Message buttons, the ignore list's own framed
--      window, the raid and quick-join panels' art and buttons, and every
--      thin scrollbar under the window;
--    - the pooled list rows keep Blizzard's own row colouring and icons and
--      take the house font; the category headers lose their art.
--  The card also hosts what the Friends module gives retail's friends list,
--  from the shared friends kit (CludesUI_FriendsKit.lua), with its own
--  settings on the card (CludesUIDB.friendsListCard): the CludesUI
--  tiles on the Social UI window's friend cards while the card is skinned,
--  and auto-accepting group invites from friends whatever the card's skin.
--  The custom friends list, the parent's CludesUI_FriendsList.lua, starts
--  here after the tiles: rows of our own over Blizzard's list, for the card's
--  Tile Height and friend groups. Its switch, Custom Friends List Tiles,
--  follows the card's look until picked (on while the card is skinned,
--  CludesUI or Modern; off under Blizz Default, where the kit's host
--  starts for the list alone and Blizzard's cards stay Blizzard's own).
--
--  Cost: a one-time pass at login on frames that already exist, then one
--  font pass per row initialisation (Blizzard's own, on rows it recycles),
--  and the kit's paint per card initialisation; auto-accept's invite event
--  only while it is on. Under Blizz Default with the custom list off,
--  nothing of the kit or the list starts. Nothing here runs on retail
--  (IS_FOREVER is false).
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
local CUI = _G.CludesUI
if not (CUI and CUI.IS_FOREVER) then
    return
end
local Skin = mod.WSkin
if not (Skin and Skin.RegisterWindow and Skin.Shell) then
    return
end

local WIN = "socialui"

local FFD, GetFFD = CUI.NewFrameData()

-- One pooled list frame: a category header (carries a Title) loses its art
-- and takes the house font; a friend or ignore row keeps Blizzard's colours
-- and icons and only takes the font on its text.
local function SkinListRow(button)
    if not button or (button.IsForbidden and button:IsForbidden()) then
        return
    end
    local skinData = GetFFD(button)
    if skinData.done then
        return
    end
    skinData.done = true
    if button.Title then
        Skin.FadeRegions(button)
        Skin.Font(button.Title)
        Skin.White(button.Title)
        return
    end
    -- A friend's or ignored player's name and its info line (place, broadcast):
    -- font families, which draw the scripts the house font lacks
    if button.name then
        Skin.FontFamily(button.name)
    end
    if button.info then
        Skin.FontFamily(button.info)
    end
end

-- The rows are recycled by the scroll box: the frames alive now, then every
-- initialisation from here on (the event hands owner, frame, elementData).
local function HookRows(box)
    if not box or GetFFD(box).hooked then
        return
    end
    GetFFD(box).hooked = true
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(box, function(_, widget)
            SkinListRow(widget)
        end, nil, false)
        if box.ForEachFrame then
            box:ForEachFrame(function(widget)
                SkinListRow(widget)
            end)
        end
    end
end

local function SkinButton(button)
    if button then
        Skin.Button(button)
        Skin.WhiteButtonLabel(button)
    end
end

local function SkinFriends()
    local frame = _G.FriendsFrame
    if not frame then
        return
    end
    local skinData = GetFFD(frame)
    if skinData.done then
        return
    end
    skinData.done = true

    Skin.Shell(WIN, frame)
    Skin.RemovePortrait(frame)
    -- The Battle.net portrait art that rides the corner beside the portrait.
    if _G.FriendsFrameIcon then
        _G.FriendsFrameIcon:SetAlpha(0)
    end
    Skin.CommonChrome(frame, "FriendsFrame")
    if frame.NineSlice then
        Skin.FadeNineSlice(frame.NineSlice)
    end
    if frame.Inset then
        Skin.Inset(frame.Inset)
    end
    local titleText = _G.FriendsFrameTitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
    if titleText then
        Skin.Font(titleText)
        Skin.White(titleText)
    end

    -- Contacts / ignore tab row across the top, the Battle.net strip and the
    -- status dropdown, all owned by the tab header that spans the frame.
    local heading = frame.FriendsTabHeader
    if heading then
        if heading.TabSystem then
            Skin.TabSystem(heading.TabSystem, { darkActive = true })
        end
        local bn = heading.BattlenetFrame or _G.FriendsFrameBattlenetFrame
        if bn then
            Skin.FadeRegions(bn)
            if bn.Tag then
                Skin.FontFamily(bn.Tag)
                Skin.White(bn.Tag)
            end
            if bn.UnavailableLabel then
                Skin.Font(bn.UnavailableLabel)
            end
            local subFrame = bn.BroadcastFrame
            if subFrame then
                Skin.Panel(subFrame)
                if subFrame.Border then
                    Skin.FadeRegions(subFrame.Border)
                end
                if subFrame.EditBox then
                    Skin.EditBox(subFrame.EditBox)
                end
                SkinButton(subFrame.UpdateButton)
                SkinButton(subFrame.CancelButton)
            end
        end
        local dropdown = heading.StatusDropdown or _G.FriendsFrameStatusDropdown
        if dropdown then
            Skin.Dropdown(dropdown)
        end
    end

    -- The friends list: its bottom buttons, its rows and headers.
    local entries = _G.FriendsListFrame
    if entries then
        SkinButton(_G.FriendsFrameAddFriendButton)
        SkinButton(_G.FriendsFrameSendMessageButton)
        if entries.FriendsDisabledText then
            Skin.Font(entries.FriendsDisabledText)
        end
        HookRows(entries.ScrollBox)
    end

    -- The ignore list: a framed window of its own inside the frame.
    local ig = frame.IgnoreListWindow
    if ig then
        Skin.Shell(WIN, ig)
        Skin.RemovePortrait(ig)
        Skin.CommonChrome(ig, "FriendsFrameIgnoreList")
        if ig.NineSlice then
            Skin.FadeNineSlice(ig.NineSlice)
        end
        if ig.Inset then
            Skin.Inset(ig.Inset)
        end
        local it = ig.TitleContainer and ig.TitleContainer.TitleText
        if it then
            Skin.Font(it)
            Skin.White(it)
        end
        SkinButton(ig.UnignorePlayerButton)
        HookRows(ig.ScrollBox)
    end

    -- The raid and quick-join panels Blizzard parents in when their tab is
    -- picked, where the client ships them: art off, buttons flattened.
    local raid = _G.RaidFrame
    if raid then
        Skin.FadeArtIn(raid)
        Skin.ButtonsIn(raid)
    end
    local qj = _G.QuickJoinFrame
    if qj then
        Skin.FadeArtIn(qj)
        Skin.ButtonsIn(qj)
    end

    -- Every thin scrollbar under the window: both lists and the panels.
    Skin.ScrollBarsIn(frame)

    -- Bottom tabs (the client numbers them with a gap).
    local tabs = {}
    for idx = 1, 4 do
        local t = _G["FriendsFrameTab" .. idx]
        if t then
            Skin.Tab(t, { darkActive = true })
            tabs[#tabs + 1] = t
        end
    end
    Skin.NormalizeTabRow(tabs)
end

-- The engine applies it at login when the card is on, and refreshes the
-- style live; the frame is not load-on-demand, so no addon gate.
Skin.RegisterWindow({
    key = WIN,
    apply = SkinFriends,
})

--------------------------------------------------------------------------------
--  The card's own settings: the friends kit reads them through a view that
--  looks like the Friends module's profile table (an unset key reads that
--  module's default); the options card writes through FriendsCardSet.
--------------------------------------------------------------------------------
local CARD_DEFAULTS = {
    enabled = true,
    showClassIcons = true,
    iconStyle = "modern",
    classColorNames = true,
    factionBanners = false,
    showRegionIcons = true,
    autoAcceptFriendInvites = false,
    autoAcceptGuildInvites = false,
    -- The custom friends list (CludesUI_FriendsList.lua): the tile height
    -- starts at that list's own default
    tileHeight = select(3, CUI.FriendsList.TileRange()),
}
-- Custom Friends List Tiles (customTiles) unset: the card's look decides, on
-- while the card is skinned (CludesUI or Modern) and off under Blizz
-- Default. A pick is kept only where it differs from that (FriendsCardSet),
-- so a card that never deviated keeps following its look.
local function CustomTilesDefault()
    return CUI.GetBlizzWindowStyle(WIN) ~= "off"
end

local cardView = setmetatable({}, {
    __index = function(_, keyName)
        local tbl = CludesUIDB and CludesUIDB.friendsListCard
        local val = tbl and tbl[keyName]
        if val == nil then
            if keyName == "customTiles" then
                return CustomTilesDefault()
            end
            val = CARD_DEFAULTS[keyName]
        end
        return val
    end,
})
local function CardSettings()
    return cardView
end

-- The card's look as it stood at login: the tiles on Blizzard's cards follow
-- it for the session (a change across Blizz Default reloads)
local loggedIn, skinnedAtLogin = false, false

-- The kit's host, then the custom friends list, which draws with it: each
-- once per session, the list's switch deciding whether it shows. The kit
-- hooks Blizzard's cards only while the card was skinned at login; under
-- Blizz Default the host serves the list alone, so it may also start later,
-- when the switch is first turned on. The list's online friends wear
-- Blizzard's own card art at the alpha given here (onlineCards): whole under
-- Blizz Default, a quarter of it under the card's own tiles.
local function StartHost()
    if not loggedIn then
        return
    end
    CUI.FriendsKit.StartTiles({
        Settings = CardSettings,
        style = "cui",
        fontKey = "blizzardSkin",
        cards = skinnedAtLogin,
        onlineCards = skinnedAtLogin and 0.25 or 1,
    })
    CUI.FriendsList.Start()
end

function mod.FriendsCardGet(keyName)
    return cardView[keyName]
end

function mod.FriendsCardSet(keyName, val)
    if not CludesUIDB then
        CludesUIDB = {}
    end
    local tbl = CludesUIDB.friendsListCard
    if not tbl then
        tbl = {}
        CludesUIDB.friendsListCard = tbl
    end
    if keyName == "customTiles" and val == CustomTilesDefault() then
        val = nil
    end
    tbl[keyName] = val
    if keyName == "autoAcceptFriendInvites" or keyName == "autoAcceptGuildInvites" then
        CUI.FriendsKit.SyncAutoAccept(CardSettings)
    else
        if keyName == "customTiles" and cardView.customTiles then
            StartHost()
        end
        CUI.FriendsKit.RedecorateTiles()
        CUI.FriendsList.Refresh()
    end
end

-- After a reset cleared the settings
function mod.FriendsCardRefresh()
    CUI.FriendsKit.SyncAutoAccept(CardSettings)
    if cardView.customTiles then
        StartHost()
    end
    CUI.FriendsKit.RedecorateTiles()
    CUI.FriendsList.Refresh()
end

-- At PLAYER_LOGIN, before any card exists: the kit's host while the card is
-- skinned or the custom list is on; auto-accept runs whatever the skin.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    CUI.FriendsKit.SyncAutoAccept(CardSettings)
    loggedIn = true
    skinnedAtLogin = CUI.GetBlizzWindowStyle(WIN) ~= "off"
    if skinnedAtLogin or cardView.customTiles then
        StartHost()
    end
end)
