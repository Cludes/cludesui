if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI and CludesUI.IS_FOREVER then
    return
end -- retail only: WoW Forever's mail window is its own build (gamepad navigation, surnames); the Mail card's ALT LIST section is not built there
-------------------------------------------------------------------------------
--  CludesUIBlizzardSkin_MailAlts.lua
--  The Mail card's Alt List (opt-in, CludesUIDB.mailAltList): beside the
--  Send Mail page, the player's other characters. Those on this realm or a
--  connected one take any mail, whatever their faction (your own characters of
--  the other faction there receive items and gold too); those on another realm
--  take Warbound items only, which reach every character on the account, and
--  show dimmed. A click puts the name in the To: box; a right
--  click offers Ignore This Character and Remove Character.
--  The card also keeps Shown Characters (CludesUIDB.mailAltHidden, by
--  player GUID) and, in the toggle's cog, Sort By (mailAltListSort), Max
--  Characters Shown (mailAltListMax) and Minimum Level (mailAltListMinLevel).
--
--  The roster, CludesUIDB.mailAltRoster (by player GUID, which a rename
--  keeps), is written at every login and logout even while the list is off
--  (owner decision 2026-10-24): two small writes a session and nothing during
--  play, so every character played since is listed the first time the list is
--  turned on.
--
--  Zero taint: none of our code runs inside Blizzard's mail code.
--   - The panel is a child of SendMailFrame, and no frame of ours under it
--     carries an OnShow, OnHide or OnSizeChanged script, so it shows and hides
--     with the Send Mail page with nothing of ours inside Blizzard's Show or
--     Hide calls.
--   - Its placement follows two hooksecurefunc post-hooks, installed on the
--     first enable and returning at once while off: MailFrameTab_OnClick (the
--     tab switches, Reply's included) and InboxFrame_Update (which every close
--     of the letter window runs, from OpenMailFrame_OnHide).
--   - A click only calls SendMailNameEditBox:SetText. The box's OnTextChanged
--     runs in our execution, and for a name Blizzard's handler writes no Lua
--     state (AutoCompleteEditBox_OnTextChanged acts on typed text or an empty
--     box only; SendMailFrame_CanSend only enables the Send button). The tab is
--     never switched and keyboard focus never moved for the player: both run
--     Blizzard code that writes state its secure send and autocomplete paths
--     read later. For the same reason a click leaves Blizzard's name
--     suggestions open when the player had started typing (Tab or the arrows
--     can then pick one; a typed key or Escape refreshes or closes them).
--
--  The panel's look is latched at login with the mail window's own skin
--  (which applies at login, its style changes needing a reload): CludesUI
--  and Modern draw the window theme (cui <-> modern repaints live), Blizz
--  Default draws Blizzard's own DefaultPanelTemplate.
-------------------------------------------------------------------------------
local _, mod = ...
local Skin = mod.WSkin
if not Skin then
    return
end

local CUI = CludesUI
local Theme = Skin.Theme
local IsSecret, PlainString = CUI.IsSecret, CUI.PlainString
local wipe, sort = wipe, table.sort

local DEFAULT_MAX, DEFAULT_MIN_LEVEL, DEFAULT_SORT = 10, 1, "recent"
local MAX_ROWS = 20 -- the Max Characters Shown slider's top
local PANEL_W = 170
local ROW_H = 22
local ICON_SIZE = 16
local LIST_PAD = 4 -- above the first row and below the last
local EMPTY_PAD = 10 -- around the empty-list note
local LIMITED_ALPHA = 0.55 -- a row that takes Warbound items only
-- The two looks' geometry: the title band's height, the list's side inset and
-- the gap to the window beside it (Blizzard's metal corners reach past their frame).
local CUI_TOP, CUI_INSET, CUI_GAP = 25, 1, 4
local BLIZZ_TOP, BLIZZ_INSET, BLIZZ_GAP = 21, 8, 10
local CUI_CLASS_ICONS = "Interface\\AddOns\\CludesUI\\media\\icons\\class-full\\modern.tga"
local BLIZZ_CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local SHELL_ART = "Interface\\AddOns\\CludesUI\\media\\modern_blizz.png"

local eventFrame = CreateFrame("Frame")
local panelFrame, titleText, emptyNote
local bgArt, bgShade, bgFlat -- the CludesUI look's backdrop layers
local rowList = {}
local dirty = true -- the shown list needs a repaint
local hooked = false
local blizzLook -- latched at login: the mail window wears Blizzard's look
local topH, inset, gap
local placedTo, placedSide -- the panel's current anchor
local connected -- this realm's connected realms, read once a session
local isShown = {} -- player GUIDs in display order (reused)
local mailable = 0 -- characters this page could mail before the card's filters
local sortRoster -- the roster the comparators read during one sort
local menuGuid -- the row the right-click menu was opened on
local myGuid -- this character, read at login (never in its own list)
local paintedGen, paintedFaction -- the class colour palette and faction the list was painted with
local MENU

-------------------------------------------------------------------------------
--  Settings and the roster
-------------------------------------------------------------------------------
local function Enabled()
    return CludesUIDB and CludesUIDB.mailAltList == true
end

local function Setting(key, default)
    local val = CludesUIDB and CludesUIDB[key]
    if val == nil then
        return default
    end
    return val
end

local function NumberSetting(key, default)
    local val = tonumber(Setting(key, default))
    return val and math.floor(val) or default
end

local function Roster()
    local saved = CludesUIDB
    if type(saved) ~= "table" then
        return nil
    end
    local region = saved.mailAltRoster
    if type(region) ~= "table" then
        region = {}
        saved.mailAltRoster = region
    end
    return region
end

local function Hidden()
    local hgt = CludesUIDB and CludesUIDB.mailAltHidden
    return type(hgt) == "table" and hgt or nil
end

-- This character as the roster keeps it. A read that comes back unknown keeps
-- the stored value (a level read before the character is in the world).
local function RecordPlayer()
    local unitGuid = PlainString(UnitGUID("player"))
    if unitGuid then
        myGuid = unitGuid
    end
    local name = PlainString((UnitName("player")))
    local realm = PlainString(GetRealmName())
    local _, class = UnitClass("player")
    class = PlainString(class)
    if not (unitGuid and name and realm and class) then
        return
    end
    -- The realm as mail addresses it ("Area52"): the normalized name.
    local realmKey = PlainString(GetNormalizedRealmName()) or (realm:gsub("[%s%-]", ""))
    local roster = Roster()
    if not roster then
        return
    end
    local e = roster[unitGuid]
    if type(e) ~= "table" then
        e = {}
        roster[unitGuid] = e
    end
    e.name, e.realm, e.realmKey, e.class = name, realm, realmKey, class
    local level = UnitLevel("player")
    if type(level) == "number" and not IsSecret(level) and level > 0 then
        e.level = level
    end
    local faction = PlainString((UnitFactionGroup("player")))
    if faction then
        e.faction = faction
    end
    e.seen = time()
    dirty = true
end

-- "Level 80 Mage, Horde": the hover line of a list row and of the Shown
-- Characters entries, in Blizzard's own strings.
local function Describe(e)
    local class = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[e.class]) or e.class or ""
    local textValue = e.level and UNIT_TYPE_LEVEL_TEMPLATE:format(e.level, class) or class
    local faction = e.faction and _G["FACTION_" .. e.faction:upper()]
    if faction then
        textValue = textValue .. ", " .. faction
    end
    return textValue
end

-------------------------------------------------------------------------------
--  Who the list shows: every other character, minus Shown Characters and
--  Minimum Level. Any mail reaches this realm or a connected one, either
--  faction; Warbound items reach every character on the account.
-------------------------------------------------------------------------------
local function ConnectedRealms()
    if connected then
        return connected
    end
    local own = PlainString(GetNormalizedRealmName())
    local set = {}
    if own then
        set[own] = true
    end
    local entries = C_AutoComplete.GetAutoCompleteRealms()
    if type(entries) == "table" then
        for idx = 1, #entries do
            local region = PlainString(entries[idx])
            if region then
                set[region] = true
            end
        end
    end
    -- Kept once this realm is known: the set never changes in a session.
    if own then
        connected = set
    end
    return set
end

local function ByName(a, button)
    local ea, editField = sortRoster[a], sortRoster[button]
    if ea.name ~= editField.name then
        return strcmputf8i(ea.name, editField.name) < 0
    end
    if ea.realmKey ~= editField.realmKey then
        return ea.realmKey < editField.realmKey
    end
    return a < button
end
local function ByLevel(a, button)
    local la, lb = sortRoster[a].level or 0, sortRoster[button].level or 0
    if la ~= lb then
        return la > lb
    end
    return ByName(a, button)
end
local function ByRecent(a, button)
    local sa, scrollBar = sortRoster[a].seen or 0, sortRoster[button].seen or 0
    if sa ~= scrollBar then
        return sa > scrollBar
    end
    return ByName(a, button)
end
local SORTS = { recent = ByRecent, level = ByLevel, name = ByName }

local function Collect()
    wipe(isShown)
    mailable = 0
    local roster = Roster()
    local faction = PlainString((UnitFactionGroup("player")))
    paintedFaction = faction
    -- A character without a faction yet has no mail.
    if not roster or not faction or faction == "Neutral" then
        return
    end
    local me = myGuid or PlainString(UnitGUID("player"))
    local hidden = Hidden()
    local minLevel = NumberSetting("mailAltListMinLevel", DEFAULT_MIN_LEVEL)
    for unitGuid, entry in pairs(roster) do
        if unitGuid ~= me and type(entry) == "table" and type(entry.name) == "string" and entry.realmKey then
            mailable = mailable + 1
            if not (hidden and hidden[unitGuid]) and (entry.level or 0) >= minLevel then
                isShown[#isShown + 1] = unitGuid
            end
        end
    end
    sortRoster = roster
    sort(isShown, SORTS[Setting("mailAltListSort", DEFAULT_SORT)] or ByRecent)
    sortRoster = nil
    for idx = #isShown, Clamp(NumberSetting("mailAltListMax", DEFAULT_MAX), 1, MAX_ROWS) + 1, -1 do
        isShown[idx] = nil
    end
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local Paint, Place

local function RowEnter(self)
    local roster = Roster()
    local e = self._guid and roster and roster[self._guid]
    if type(e) ~= "table" then
        return
    end
    local color = CUI.GetClassColor(e.class)
    local head = e.name
    if self._foreign then
        head = head .. " - " .. (e.realm or e.realmKey)
    end
    local textValue = CUI.HexColor(color.r, color.g, color.b) .. head .. "|r\n" .. Describe(e)
    if self._limited then
        textValue = textValue .. "\n" .. CludesUI.L("Only Warbound items can be mailed to this character.")
    end
    CUI.ShowWidgetTooltip(
        self,
        textValue
            .. "\n"
            .. CUI.COLOR_CODES.DIM
            .. CludesUI.L("Click to mail, right-click for options.")
            .. "|r",
        { anchor = "right", justify = "LEFT" }
    )
end

local function RowLeave()
    CUI.HideWidgetTooltip()
end

local function RowClick(self, btnFrame)
    if not self._guid then
        return
    end
    if btnFrame == "RightButton" then
        menuGuid = self._guid
        CUI.ShowContextMenu(self, MENU)
        return
    end
    local box = SendMailNameEditBox
    if box and self._target then
        box:SetText(self._target)
    end
end

local function NewRow(idx)
    local region = CreateFrame("Button", nil, panelFrame)
    region._mailAltRow = true
    region:SetHeight(ROW_H)
    region:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local highlight = region:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    if blizzLook then
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
        highlight:SetBlendMode("ADD")
        highlight:SetVertexColor(0.196, 0.388, 0.8)
    else
        highlight:SetColorTexture(1, 1, 1, 0.08)
    end
    local iconTex = region:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(ICON_SIZE, ICON_SIZE)
    iconTex:SetPoint("LEFT", region, "LEFT", 6, 0)
    local lvl = region:CreateFontString(nil, "OVERLAY", blizzLook and "GameFontDisableSmall" or nil)
    local name = region:CreateFontString(nil, "OVERLAY", blizzLook and "GameFontHighlightSmall" or nil)
    if not blizzLook then
        Skin.Font(lvl, 0.6, 0.6, 0.6, 11)
        -- A character's name: a font family, which draws the scripts the font lacks
        Skin.FontFamily(name, nil, nil, nil, 12)
    end
    lvl:SetPoint("RIGHT", region, "RIGHT", -6, 0)
    lvl:SetJustifyH("RIGHT")
    name:SetPoint("LEFT", iconTex, "RIGHT", 5, 0)
    name:SetPoint("RIGHT", lvl, "LEFT", -4, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    region._icon, region._name, region._lvl = iconTex, name, lvl
    region:SetScript("OnClick", RowClick)
    region:SetScript("OnEnter", RowEnter)
    region:SetScript("OnLeave", RowLeave)
    region:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", inset, -(topH + LIST_PAD + (idx - 1) * ROW_H))
    region:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -inset, -(topH + LIST_PAD + (idx - 1) * ROW_H))
    rowList[idx] = region
    return region
end

local function DressIcon(texture, class)
    local coords
    if blizzLook then
        coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            texture:SetTexture(BLIZZ_CLASS_ICONS)
        end
    else
        coords = CUI.CLASS_ICON_SPRITE_COORDS[class]
        if coords then
            texture:SetTexture(CUI_CLASS_ICONS)
        end
    end
    if coords then
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        texture:Show()
    else
        texture:Hide()
    end
end

-- A repaint under a resting cursor: the row now there shows its own tooltip.
local function ReplayHover()
    local foci = GetMouseFoci()
    for idx = 1, #foci do
        local frame = foci[idx]
        if frame and frame._mailAltRow and frame:IsVisible() then
            RowEnter(frame)
            return
        end
    end
end

-------------------------------------------------------------------------------
--  The panel
-------------------------------------------------------------------------------
local function PaintBackdrop()
    if blizzLook or not panelFrame then
        return
    end
    local modern = Skin.GetStyle("mail") == "modern"
    bgArt:SetAlpha(modern and 0 or 1)
    bgShade:SetAlpha(modern and 0 or 1)
    if modern then
        bgFlat:SetColorTexture(Skin.GetModernBG())
    else
        bgFlat:SetColorTexture(0, 0, 0, 0)
    end
end

local function Build()
    if not Theme.fontPath then
        Skin.ResolveTheme()
    end
    -- Named: a frame of ours the window skin's art sweeps leave alone.
    if blizzLook then
        topH, inset, gap = BLIZZ_TOP, BLIZZ_INSET, BLIZZ_GAP
        panelFrame = CreateFrame("Frame", "CludesUIMailAltList", SendMailFrame, "DefaultPanelTemplate")
        panelFrame:SetTitleOffsets(6, -6)
        titleText = panelFrame:GetTitleText()
    else
        topH, inset, gap = CUI_TOP, CUI_INSET, CUI_GAP
        panelFrame = CreateFrame("Frame", "CludesUIMailAltList", SendMailFrame)
        -- The mail window's own shell layers: the atlas under a black wash
        -- (CludesUI), or the one Modern colour. Built here rather than through
        -- WSkin.Shell, which hooks OnSizeChanged: no script of ours may sit in
        -- SendMailFrame's subtree.
        bgArt = panelFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bgArt:SetTexture(SHELL_ART)
        bgArt:SetAllPoints()
        bgShade = panelFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
        bgShade:SetColorTexture(0, 0, 0, 0.62)
        bgShade:SetAllPoints()
        bgFlat = panelFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        bgFlat:SetAllPoints()
        local band = panelFrame:CreateTexture(nil, "BACKGROUND", nil, -5)
        band:SetColorTexture(0, 0, 0, 0.5)
        band:SetPoint("TOPLEFT")
        band:SetPoint("TOPRIGHT")
        band:SetHeight(topH)
        Skin.AddBorder(panelFrame)
        titleText = panelFrame:CreateFontString(nil, "OVERLAY")
        Skin.Font(titleText, 1, 1, 1, 12)
        titleText:SetPoint("CENTER", band, "CENTER", 0, 0)
        PaintBackdrop()
        Skin.OnStylesChanged(PaintBackdrop)
    end
    titleText:SetText(CludesUI.L("Alts"))
    panelFrame:SetWidth(PANEL_W)
    panelFrame:SetClampedToScreen(true)
    -- It hangs outside the window: a click on its empty parts stays off the world.
    panelFrame:EnableMouse(true)
    emptyNote = panelFrame:CreateFontString(nil, "OVERLAY", blizzLook and "GameFontDisableSmall" or nil)
    if not blizzLook then
        Skin.Font(emptyNote, 0.6, 0.6, 0.6, 11)
    end
    -- Its own width, never one from anchors: the note is measured before the
    -- panel is first placed, and a width taken from unplaced anchors measures
    -- the text as one unwrapped line (a panel too short, the note cut off).
    emptyNote:SetWidth(PANEL_W - EMPTY_PAD * 2)
    emptyNote:SetPoint("TOP", panelFrame, "TOP", 0, -(topH + EMPTY_PAD))
    emptyNote:SetJustifyH("CENTER")
    emptyNote:SetSpacing(2)
end

Paint = function()
    dirty = false
    paintedGen = CUI._dmGen
    Collect()
    local roster = Roster()
    local own = PlainString(GetNormalizedRealmName())
    local realms = ConnectedRealms()
    local num = #isShown
    for idx = 1, num do
        local unitGuid = isShown[idx]
        local e = roster[unitGuid]
        local region = rowList[idx] or NewRow(idx)
        local foreign = e.realmKey ~= own
        -- Any mail reaches this realm or a connected one, either faction;
        -- another realm takes Warbound items only and shows dimmed.
        local limited = not realms[e.realmKey]
        region._guid, region._foreign, region._limited = unitGuid, foreign, limited
        -- Mail addresses another realm's character as "Name-Realm".
        region._target = foreign and (e.name .. "-" .. e.realmKey) or e.name
        DressIcon(region._icon, e.class)
        local color = CUI.GetClassColor(e.class)
        region._name:SetText(foreign and (e.name .. FOREIGN_SERVER_LABEL) or e.name)
        region._name:SetTextColor(color.r, color.g, color.b)
        region._lvl:SetText(e.level or "")
        region:SetAlpha(limited and LIMITED_ALPHA or 1)
        region:Show()
    end
    local ownerFrame = CUI._WidgetTooltipOwner()
    for idx = num + 1, #rowList do
        local region = rowList[idx]
        if ownerFrame == region then
            CUI.HideWidgetTooltip(true)
        end
        region:Hide()
        region._guid, region._target, region._limited = nil, nil, nil
    end
    local hgt
    if num > 0 then
        emptyNote:Hide()
        hgt = topH + LIST_PAD * 2 + num * ROW_H
    else
        emptyNote:SetText(
            mailable == 0 and CludesUI.L("Log into your other characters to list them here.")
                or CludesUI.L("Your other characters are hidden by Shown Characters or Minimum Level.")
        )
        emptyNote:Show()
        hgt = topH + EMPTY_PAD * 2 + math.ceil(emptyNote:GetStringHeight())
    end
    if blizzLook then
        hgt = hgt + 2
    end -- the frame's bottom edge
    panelFrame:SetHeight(hgt)
    if bgArt then
        Skin.CoverFit(bgArt, PANEL_W, hgt)
    end
    if ownerFrame then
        ReplayHover()
    end
end

local function ScreenRect(frame)
    local s = frame:GetEffectiveScale()
    local l, region, t, button = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and region and t and button) or IsSecret(l) or IsSecret(region) or IsSecret(t) or IsSecret(button) then
        return nil
    end
    return l * s, region * s, t * s, button * s
end

local function Anchor(to, side)
    if placedTo == to and placedSide == side then
        return
    end
    placedTo, placedSide = to, side
    panelFrame:ClearAllPoints()
    if side == "left" then
        panelFrame:SetPoint("TOPRIGHT", to, "TOPLEFT", -gap, 0)
    else
        panelFrame:SetPoint("TOPLEFT", to, "TOPRIGHT", gap, 0)
    end
end

-- Beside the mail window; past an open letter it would cover; on the window's
-- left when the screen has no room on its right.
Place = function()
    local mf, letter = MailFrame, OpenMailFrame
    local to, side = mf, "right"
    local ml, mr, mt = ScreenRect(mf)
    if mr then
        local s = panelFrame:GetEffectiveScale()
        local wid, hgt, g = PANEL_W * s, panelFrame:GetHeight() * s, gap * s
        local leftX = mr + g
        if letter and letter:IsShown() then
            local ll, lr, lt, lb = ScreenRect(letter)
            if ll and leftX < lr and leftX + wid > ll and mt - hgt < lt and mt > lb then
                to, leftX = letter, lr + g
            end
        end
        local screen = UIParent:GetRight() * UIParent:GetEffectiveScale()
        if leftX + wid > screen and ml - g - wid >= 0 then
            to, side = mf, "left"
        end
    end
    Anchor(to, side)
end

-- Shown before the paint: a font string measures its height only while visible.
-- Repainted when the list changed, a class colour was edited since (the colour
-- palette's generation) or this character has picked its faction since.
local function ShowPanel()
    if not panelFrame then
        Build()
    end
    panelFrame:Show()
    if dirty or paintedGen ~= CUI._dmGen or paintedFaction ~= PlainString((UnitFactionGroup("player"))) then
        Paint()
    end
    Place()
end

-- A change from the right-click menu: the list, and the open options page's
-- Shown Characters summary.
local function Changed()
    dirty = true
    if panelFrame and panelFrame:IsVisible() then
        Paint()
        Place()
    end
    if CUI:IsShown() then
        CUI:RefreshPage()
    end
end

local function SetShown(unitGuid, enabled)
    if not CludesUIDB then
        return
    end
    local hgt = CludesUIDB.mailAltHidden
    if enabled then
        if type(hgt) == "table" then
            hgt[unitGuid] = nil
            if not next(hgt) then
                CludesUIDB.mailAltHidden = nil
            end
        end
    else
        if type(hgt) ~= "table" then
            hgt = {}
            CludesUIDB.mailAltHidden = hgt
        end
        hgt[unitGuid] = true
    end
    dirty = true
end

MENU = {
    {
        text = "Ignore This Character",
        tooltip = "Hides it until ticked again in Shown Characters.",
        onClick = function()
            if menuGuid then
                SetShown(menuGuid, false)
                Changed()
            end
        end,
    },
    {
        text = "Remove Character",
        tooltip = "Forgets a deleted or moved character.",
        onClick = function()
            local roster = Roster()
            local unitGuid = menuGuid
            local e = unitGuid and roster and roster[unitGuid]
            if type(e) ~= "table" then
                return
            end
            -- Asked first: a misclick would drop a rarely played alt until it next logs in.
            CUI:ShowConfirmPopup({
                title = "Remove Character",
                message = CludesUI.Lf(
                    "Remove %s from the Alt List? It comes back when you next log into it.",
                    e.name
                ),
                confirmText = "Remove",
                cancelText = "Cancel",
                onConfirm = function()
                    roster[unitGuid] = nil
                    local hgt = Hidden()
                    if hgt and hgt[unitGuid] then
                        SetShown(unitGuid, true)
                    end
                    Changed()
                end,
            })
        end,
    },
}

-------------------------------------------------------------------------------
--  Hooks: tab switches and the letter window
-------------------------------------------------------------------------------
local function OnTab()
    if not Enabled() or not SendMailFrame:IsVisible() then
        return
    end
    ShowPanel()
end

local function OnInboxUpdate()
    if panelFrame and panelFrame:IsVisible() and Enabled() then
        Place()
    end
end

local function HookMail()
    if hooked or type(_G.MailFrameTab_OnClick) ~= "function" or type(_G.InboxFrame_Update) ~= "function" then
        return
    end
    hooked = true
    hooksecurefunc("MailFrameTab_OnClick", OnTab)
    hooksecurefunc("InboxFrame_Update", OnInboxUpdate)
end

local function Install()
    if hooked then
        return
    end
    if C_AddOns.IsAddOnLoaded("Blizzard_MailFrame") then
        HookMail()
    else
        eventFrame:RegisterEvent("ADDON_LOADED")
    end
end

-------------------------------------------------------------------------------
--  The Mail card's options (CUI_BlizzardSkin_Options.lua)
-------------------------------------------------------------------------------
mod.MailAlts = {
    DEFAULT_MAX = DEFAULT_MAX,
    DEFAULT_MIN_LEVEL = DEFAULT_MIN_LEVEL,
    DEFAULT_SORT = DEFAULT_SORT,
    MAX_ROWS = MAX_ROWS,
    Describe = Describe,
}

-- A setting changed: the hooks on the first enable, the open Send Mail page
-- repainted, the panel put away when turned off.
function mod.MailAlts.Refresh()
    dirty = true
    if Enabled() then
        Install()
        -- Visible, not shown: SendMailFrame keeps its shown flag while the
        -- mailbox is closed, and the panel paints only where it can measure.
        if hooked and SendMailFrame:IsVisible() then
            ShowPanel()
        end
    elseif panelFrame then
        panelFrame:Hide()
        local ownerFrame = CUI.ContextMenuOwner()
        if ownerFrame and ownerFrame._mailAltRow then
            CUI.CloseContextMenu()
        end
    end
end

-- Every recorded character, for Shown Characters: by realm (this one first),
-- then by name. A fresh list per call (the menu builds on open).
function mod.MailAlts.Entries()
    local result = {}
    local roster = Roster()
    if not roster then
        return result
    end
    for unitGuid, entry in pairs(roster) do
        if type(entry) == "table" and type(entry.name) == "string" then
            result[#result + 1] = {
                guid = unitGuid,
                name = entry.name,
                realm = entry.realm or entry.realmKey or "",
                class = entry.class,
                level = entry.level,
                faction = entry.faction,
            }
        end
    end
    local own = GetRealmName()
    sort(result, function(a, button)
        if a.realm ~= button.realm then
            if a.realm == own then
                return true
            end
            if button.realm == own then
                return false
            end
            return strcmputf8i(a.realm, button.realm) < 0
        end
        if a.name ~= button.name then
            return strcmputf8i(a.name, button.name) < 0
        end
        return a.guid < button.guid
    end)
    return result
end

function mod.MailAlts.IsShown(unitGuid)
    local hgt = Hidden()
    return not (hgt and hgt[unitGuid])
end

function mod.MailAlts.SetShown(unitGuid, enabled)
    SetShown(unitGuid, enabled)
    if panelFrame and panelFrame:IsVisible() then
        Paint()
        Place()
    end
end

-------------------------------------------------------------------------------
--  Boot: the roster at login and logout; the hooks once the list is on
-------------------------------------------------------------------------------
eventFrame:SetScript("OnEvent", function(self, evt, arg1)
    if evt == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        blizzLook = Skin.GetStyle("mail") == "off"
        RecordPlayer()
        if Enabled() then
            Install()
        end
    elseif evt == "PLAYER_LOGOUT" then
        RecordPlayer()
    elseif arg1 == "Blizzard_MailFrame" then
        self:UnregisterEvent("ADDON_LOADED")
        HookMail()
    end
end)
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
