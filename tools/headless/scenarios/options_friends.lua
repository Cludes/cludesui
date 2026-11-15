-- Friends List options page as built, then with every setting changed (icon
-- theme, class colours, border size and class-colour border, accent colours
-- and faction banners off, region icons off, auto-accept and guildmates on)
-- and the page re-read.
local CUI = rawget(_G, "CludesUI")
CUI:SelectModule("CludesUIFriends")
CUI:SelectPage("Friends")
SNAP("friends", CUI._scrollFrame)
local db = rawget(_G, "_CUFR_DB")
local f = db and db.profile and db.profile.friends
if f then
    f.iconStyle = "classic"
    f.classColorNames = true
    f.borderSize = 2
    f.useClassColor = true
    f.accentColors = false
    f.factionBanners = false
    f.showRegionIcons = false
    f.autoAcceptFriendInvites = true
    f.autoAcceptGuildInvites = true
end
CUI:RefreshPage()
SNAP("friends set", CUI._scrollFrame)
