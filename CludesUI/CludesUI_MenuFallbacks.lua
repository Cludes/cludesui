if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_MenuFallbacks.lua
--
--  Secure "View Houses" for the one unit menu we cannot open securely.
--
--  A raid/party member who is in another zone (a house owner hosting a
--  housewarming is ALWAYS elsewhere) trips the togglemenu classifier, and the
--  menu proxy's backstop (CludesUI_Kick.lua) re-opens the player menu from
--  Lua -- a TAINTED menu. Its protected items all fail: Set Focus, Follow and
--  the Raid Target markers throw ADDON_ACTION_FORBIDDEN; "View Houses" runs
--  HouseListFrame:InitWithContextData tainted, which poisons the house list's
--  ScrollBox data for the rest of the session (every later Visit House click,
--  even from a secure menu, is blocked at C_Housing.VisitHouse).
--
--  Everything applies to THAT menu only. Set Focus / Follow / Raid Target /
--  View Houses entries are greyed out so they cannot throw or poison, and a
--  "View Houses" button docked beside the menu opens our own house list. Each
--  row's Visit is a SecureActionButton WE own running the stock "visithouse"
--  secure action from string attributes set out of combat -- the same channel
--  an action bar's macrotext rides, read clean by the hardware click. Nothing
--  reaches a protected call from tainted execution, and Blizzard's panel is
--  never touched.
--
--  Visuals mirror the Blizzard-window skin engine (panel fill, inset fill,
--  border, flat buttons with a white hover, atlas close glyph, the
--  "blizzardSkin" font settings) so the dock and list read as one of our
--  skinned windows. The engine itself is private to the BlizzardSkin child
--  addon, so its palette is reproduced here rather than called.
--
--  Zero cost until the backstop fires: the Menu.ModifyMenu callbacks return
--  on their first line unless CludesUI._menuReopenUnit is set (only during
--  the backstop's re-open call), the button and list are built on first use,
--  and their events are registered only while shown.
-------------------------------------------------------------------------------

local CludesUI = _G.CludesUI
if not CludesUI then
    return
end
if not (Menu and Menu.ModifyMenu and Menu.GetManager and MenuUtil and MenuUtil.GetElementText) then
    return
end

local HOUSING_OK = C_Housing and C_Housing.GetOthersOwnedHouses and C_Housing.VisitHouse

-------------------------------------------------------------------------------
--  Theme (the window skin engine's palette)
-------------------------------------------------------------------------------
local T = {}
local function ResolveTheme()
    local ACC = CludesUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }
    T.accR, T.accG, T.accB = ACC.r, ACC.g, ACC.b
    T.bgR, T.bgG, T.bgB, T.bgA = 0.08, 0.08, 0.08, 0.92
    T.insetR, T.insetG, T.insetB, T.insetA = 0.04, 0.04, 0.04, 0.85
    T.brdR, T.brdG, T.brdB, T.brdA = 0.2, 0.2, 0.2, 1
    T.fontPath = (CludesUI.GetFontPath("blizzardSkin")) or CludesUI._font or STANDARD_TEXT_FONT
    T.fontFlag = (CludesUI.GetFontOutlineFlag("blizzardSkin")) or ""
    T.fontShadow = (T.fontFlag == "")
        and (not CludesUI.GetFontUseShadow or CludesUI.GetFontUseShadow("blizzardSkin"))
end

local function SolidTex(hostFrame, layer, r, g, b, a, sublevel)
    local t = hostFrame:CreateTexture(nil, layer, nil, sublevel)
    t:SetColorTexture(r, g, b, a)
    return t
end

-- BORDER/-7 strips demoted to the frame's own level, exactly as the window
-- engine draws its borders (content on the frame renders above them).
local function AddBorder(widget)
    local Pix = CludesUI.PanelPP or CludesUI.PP
    if not (Pix and Pix.CreateBorder) then
        return
    end
    local c = Pix.CreateBorder(widget, T.brdR, T.brdG, T.brdB, T.brdA, 1, "BORDER", -7)
    if c and c.SetFrameLevel then
        c:SetFrameLevel(widget:GetFrameLevel())
    end
end

-- family: a text that shows other players' writing (house and owner names)
-- takes the font as a font family, which draws the scripts the font lacks.
local function MakeText(hostFrame, dim, r, g, b, family)
    local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
    if family then
        CludesUI.SetFontFamily(fontStr, T.fontPath, dim, T.fontFlag or "", T.fontShadow)
    else
        CludesUI.PrimeFontShadow(fontStr, T.fontShadow)
        fontStr:SetFont(T.fontPath, dim, T.fontFlag or "")
    end
    fontStr:SetTextColor(r or 1, g or 1, b or 1, 1)
    return fontStr
end

local function Panel(widget, inset)
    local r, g, b, a = T.bgR, T.bgG, T.bgB, T.bgA
    if inset then
        r, g, b, a = T.insetR, T.insetG, T.insetB, T.insetA
    end
    local backdrop = SolidTex(widget, "BACKGROUND", r, g, b, a, -6)
    backdrop:SetAllPoints(widget)
    AddBorder(widget)
    return backdrop
end

-- Flat dark block with a subtle white hover and a white label; secure = a
-- SecureActionButton whose attributes the caller sets.
local function MakeButton(hostFrame, name, labelText, wid, hgt, secure)
    local b = CreateFrame("Button", name, hostFrame, secure and "SecureActionButtonTemplate" or nil)
    b:SetSize(wid, hgt)
    b:RegisterForClicks("AnyUp")
    if secure then
        b:SetAttribute("useOnKeyDown", false)
    end
    local fillTex = SolidTex(b, "BACKGROUND", T.bgR, T.bgG, T.bgB, T.bgA)
    fillTex:SetAllPoints(b)
    AddBorder(b)
    local hover = SolidTex(b, "HIGHLIGHT", 1, 1, 1, 0.1)
    hover:SetAllPoints(b)
    local t = MakeText(b, 12)
    t:SetPoint("CENTER")
    t:SetText(labelText)
    b:SetFontString(t)
    return b
end

local function MakeCloseButton(hostFrame)
    local button = CreateFrame("Button", nil, hostFrame)
    button:SetSize(22, 22)
    local posX = button:CreateTexture(nil, "OVERLAY")
    posX:SetAtlas("uitools-icon-close")
    posX:SetSize(14, 14)
    posX:SetPoint("CENTER")
    posX:SetVertexColor(1, 1, 1, 0.75)
    button:SetScript("OnEnter", function()
        posX:SetVertexColor(1, 1, 1, 1)
    end)
    button:SetScript("OnLeave", function()
        posX:SetVertexColor(1, 1, 1, 0.75)
    end)
    return button
end

local OpenHousesFor -- defined with the house list below

-------------------------------------------------------------------------------
--  "View Houses" button, docked to the reopened menu
-------------------------------------------------------------------------------
local dock
local dockEv = CreateFrame("Frame")
local hookedMenus = setmetatable({}, { __mode = "k" })
local reopenContext -- the reopened menu's contextData, captured by the modifier

local function BuildDock()
    ResolveTheme()
    local d = CreateFrame("Frame", "CludesUI_MenuFallbackDock", UIParent)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetSize(124, 34)
    d:Hide()
    Panel(d)

    d.houses = MakeButton(d, nil, UNIT_VIEW_HOUSES or CludesUI.L("View Houses"), 112, 22, false)
    d.houses:SetPoint("CENTER")
    -- The menu closes on any GLOBAL_MOUSE_DOWN outside it UNLESS the frame
    -- under the cursor answers HandlesGlobalMouseEvent (Menu.lua's opt-out for
    -- attached UI). Claim our clicks so the menu stays until OnClick, which
    -- then closes it itself.
    d.houses.HandlesGlobalMouseEvent = function()
        return true
    end
    d.houses:SetScript("OnClick", function()
        local dropMenu = d.menu
        d:Hide()
        if dropMenu then
            local mgr = Menu.GetManager()
            if mgr and mgr.CloseMenu then
                mgr:CloseMenu(dropMenu)
            end
        end
        OpenHousesFor(reopenContext)
    end)

    d:SetScript("OnHide", function(self)
        self.menu = nil
        dockEv:UnregisterAllEvents()
    end)
    d:SetScript("OnShow", function()
        dockEv:RegisterEvent("PLAYER_ENTERING_WORLD")
    end)
    dockEv:SetScript("OnEvent", function()
        d:Hide()
    end)
    dock = d
    return d
end

-- Called by the backstop right after its (tainted) re-open, while that menu is
-- the open one.
function CludesUI._ShowReopenedMenuExtras(unitToken)
    if not HOUSING_OK or not reopenContext or reopenContext.unit ~= unitToken then
        return
    end
    local mgr = Menu.GetManager()
    local dropMenu = mgr and mgr.GetOpenMenu and mgr:GetOpenMenu()
    if not dropMenu or (dropMenu.IsForbidden and dropMenu:IsForbidden()) then
        return
    end
    local d = dock or BuildDock()
    d.menu = dropMenu
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", dropMenu, "TOPRIGHT", 2, 0)
    -- Close with the menu it is docked to (menu frames are pooled: hook once
    -- per frame, act only when the dock is anchored to that frame).
    if not hookedMenus[dropMenu] then
        hookedMenus[dropMenu] = true
        dropMenu:HookScript("OnHide", function(self)
            if dock and dock.menu == self then
                dock:Hide()
            end
        end)
    end
    d:Show()
end

-------------------------------------------------------------------------------
--  House list (built once, on first use)
-------------------------------------------------------------------------------
local MAX_ROWS = 6
local ROW_H = 42
local ROW_GAP = 4
local FRAME_W = 440
local HEADER_H = 32

local listFrame, rowList, statusText, titleText
local pendingHouses -- last received house list, re-applied after combat
local listEv = CreateFrame("Frame")

local function BuildList()
    ResolveTheme()
    local f = CreateFrame("Frame", "CludesUI_HouseVisitFrame", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetScale((CludesUI.GetPopupScale()) or 1)
    f:SetWidth(FRAME_W)
    f:SetHeight(HEADER_H + 10 + MAX_ROWS * (ROW_H + ROW_GAP) + 6)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    Panel(f)

    -- Header band (inset fill) with the title and the close glyph, like a
    -- skinned window's title bar.
    local headerFrame = CreateFrame("Frame", nil, f)
    headerFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    headerFrame:SetHeight(HEADER_H)
    local hbg = SolidTex(headerFrame, "BACKGROUND", T.insetR, T.insetG, T.insetB, T.insetA, -5)
    hbg:SetAllPoints(headerFrame)
    local hline = SolidTex(headerFrame, "BORDER", T.brdR, T.brdG, T.brdB, T.brdA)
    hline:SetPoint("BOTTOMLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
    hline:SetPoint("BOTTOMRIGHT", headerFrame, "BOTTOMRIGHT", 0, 0)
    hline:SetHeight(1)

    titleText = MakeText(headerFrame, 14, nil, nil, nil, true)
    titleText:SetPoint("LEFT", headerFrame, "LEFT", 12, 0)
    titleText:SetPoint("RIGHT", headerFrame, "RIGHT", -34, 0)
    titleText:SetJustifyH("LEFT")

    local close = MakeCloseButton(headerFrame)
    close:SetPoint("RIGHT", headerFrame, "RIGHT", -6, 0)
    close:SetScript("OnClick", function()
        f:Hide()
    end)

    statusText = MakeText(f, 12, 0.7, 0.7, 0.7)
    statusText:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -(HEADER_H + 12))
    statusText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -(HEADER_H + 12))
    statusText:SetJustifyH("LEFT")

    rowList = {}
    for idx = 1, MAX_ROWS do
        local rowFrame = CreateFrame("Frame", nil, f)
        rowFrame:SetHeight(ROW_H)
        local posY = -(HEADER_H + 10 + (idx - 1) * (ROW_H + ROW_GAP))
        rowFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, posY)
        rowFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, posY)
        Panel(rowFrame, true)

        rowFrame.name = MakeText(rowFrame, 13, nil, nil, nil, true)
        rowFrame.name:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 10, -7)
        rowFrame.name:SetPoint("RIGHT", rowFrame, "RIGHT", -100, 0)
        rowFrame.name:SetJustifyH("LEFT")

        rowFrame.info = MakeText(rowFrame, 11, 0.65, 0.65, 0.65, true)
        rowFrame.info:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 10, 7)
        rowFrame.info:SetPoint("RIGHT", rowFrame, "RIGHT", -100, 0)
        rowFrame.info:SetJustifyH("LEFT")

        -- The teleport: a stock secure action, attributes = plain strings.
        local visit = MakeButton(rowFrame, "CludesUI_HouseVisit" .. idx, CludesUI.L("Visit"), 80, 24, true)
        visit:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
        visit:SetAttribute("type", "visithouse")
        rowFrame.visit = visit

        rowFrame:Hide()
        rowList[idx] = rowFrame
    end

    if CludesUI.RegisterEscapeClose then
        CludesUI.RegisterEscapeClose(f)
    end
    listFrame = f
    return f
end

local function ClearRows()
    for idx = 1, MAX_ROWS do
        rowList[idx]:Hide()
    end
end

local function ApplyHouses(houses)
    ClearRows()
    if not houses or #houses == 0 then
        statusText:SetText(CludesUI.L("No houses found."))
        statusText:Show()
        return
    end
    -- Attribute writes are refused in combat; keep the list and re-apply on
    -- PLAYER_REGEN_ENABLED (registered while shown).
    if InCombatLockdown() then
        statusText:SetText(CludesUI.L("Leave combat to enable visiting."))
        statusText:Show()
        return
    end
    statusText:Hide()
    for idx = 1, math.min(#houses, MAX_ROWS) do
        local hgt = houses[idx]
        local rowFrame = rowList[idx]
        rowFrame.name:SetText(hgt.houseName or CludesUI.L("House"))
        local where = hgt.neighborhoodName or ""
        if hgt.plotID then
            where = where
                .. (where ~= "" and "  -  " or "")
                .. string.format(HOUSING_PLOT_NUMBER or "Plot %d", hgt.plotID)
        end
        if hgt.ownerName and hgt.ownerName ~= "" then
            where = where .. (where ~= "" and "  -  " or "") .. hgt.ownerName
        end
        rowFrame.info:SetText(where)
        local val = rowFrame.visit
        val:SetAttribute("house-neighborhood-guid", hgt.neighborhoodGUID)
        val:SetAttribute("house-guid", hgt.houseGUID)
        val:SetAttribute("house-plot-id", hgt.plotID and tostring(hgt.plotID) or nil)
        local success = hgt.neighborhoodGUID and hgt.houseGUID and hgt.plotID
        val:SetAlpha(success and 1 or 0.3)
        val:EnableMouse(success and true or false)
        rowFrame:Show()
    end
end

listEv:SetScript("OnEvent", function(self, evt, arg1)
    if evt == "VIEW_HOUSES_LIST_RECIEVED" then
        pendingHouses = arg1
        ApplyHouses(arg1)
    elseif evt == "PLAYER_REGEN_ENABLED" then
        if pendingHouses then
            ApplyHouses(pendingHouses)
        end
    elseif evt == "PLAYER_ENTERING_WORLD" then
        -- A successful visit loads a new map; the list has done its job.
        if listFrame then
            listFrame:Hide()
        end
    end
end)

local function ListOnShow()
    listEv:RegisterEvent("VIEW_HOUSES_LIST_RECIEVED")
    listEv:RegisterEvent("PLAYER_REGEN_ENABLED")
    listEv:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function ListOnHide()
    listEv:UnregisterAllEvents()
    pendingHouses = nil
end

-- Request the list for the menu's player.
function OpenHousesFor(contextData)
    if not contextData then
        return
    end
    local f = listFrame
    if not f then
        f = BuildList()
        f:SetScript("OnShow", ListOnShow)
        f:SetScript("OnHide", ListOnHide)
    end
    local unitToken = contextData.unit
    local name = (
        UnitPopupSharedUtil
        and UnitPopupSharedUtil.GetFullPlayerName
        and UnitPopupSharedUtil.GetFullPlayerName(contextData)
    )
        or (unitToken and UnitName(unitToken))
        or contextData.name
        or UNKNOWN
    local unitGuid = (unitToken and UnitGUID(unitToken))
        or (UnitPopupSharedUtil and UnitPopupSharedUtil.GetGUID and UnitPopupSharedUtil.GetGUID(contextData))
    if issecretvalue and (issecretvalue(unitGuid) or issecretvalue(name)) then
        return
    end
    if not unitGuid then
        return
    end

    pendingHouses = nil
    titleText:SetText(string.format(VIEW_HOUSES_TITLE or "%s's Houses", name))
    ClearRows()
    statusText:SetText(CludesUI.L("Loading houses..."))
    statusText:Show()
    f:Show()
    C_Housing.GetOthersOwnedHouses(unitGuid, contextData.bnetIDAccount, not not contextData.isGuildMember)
end

-------------------------------------------------------------------------------
--  Menu modification: only the backstop's re-opened menu
-------------------------------------------------------------------------------
local function ModifyReopenedMenu(ownerFrame, rootDescription, contextData)
    if not CludesUI._menuReopenUnit then
        return
    end
    if not contextData or contextData.unit ~= CludesUI._menuReopenUnit then
        return
    end
    reopenContext = contextData
    local viewHouses = UNIT_VIEW_HOUSES or "View Houses"
    local setFocus = SET_FOCUS or "Set Focus"
    local follow = FOLLOW or "Follow"
    local raidTarget = RAID_TARGET_ICON or "Raid Target Icon"
    local trade = TRADE or "Trade"
    local duel = DUEL or "Duel"
    local petDuel = PET_BATTLE_PVP_DUEL or "Pet Battle Duel"
    local achievements = COMPARE_ACHIEVEMENTS or "Compare Achievements"
    for _, d in rootDescription:EnumerateElementDescriptions() do
        local textValue = MenuUtil.GetElementText(d)
        if
            d.SetEnabled
            and (
                textValue == setFocus
                or textValue == follow
                or textValue == raidTarget
                or textValue == trade
                or textValue == duel
                or textValue == petDuel
                or textValue == achievements
                or (HOUSING_OK and textValue == viewHouses)
            )
        then
            -- Range-gated entries call CheckInteractDistance from Blizzard's
            -- enabled predicate. Disable them before that predicate can run in
            -- this tainted reopen; normal secure menus keep their range checks.
            -- Protected from a tainted menu: throws (focus/follow, and every
            -- marker under Raid Target Icon -- SetRaidTarget) or poisons
            -- HouseListFrame for the session (View Houses; the docked button
            -- replaces it).
            d:SetEnabled(false)
        end
    end
end

Menu.ModifyMenu("MENU_UNIT_RAID_PLAYER", ModifyReopenedMenu)
Menu.ModifyMenu("MENU_UNIT_PARTY", ModifyReopenedMenu)
