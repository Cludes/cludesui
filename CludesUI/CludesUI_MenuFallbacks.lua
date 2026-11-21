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

local CUI = _G.CludesUI
if not CUI then
    return
end
if not (Menu and Menu.ModifyMenu and Menu.GetManager and MenuUtil and MenuUtil.GetElementText) then
    return
end

local HOUSING_OK = C_Housing and C_Housing.GetOthersOwnedHouses and C_Housing.VisitHouse

-------------------------------------------------------------------------------
--  Theme (the window skin engine's palette)
-------------------------------------------------------------------------------
local Fallbacks = {}
local function ResolveTheme()
    local ACC = CUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }
    Fallbacks.accR, Fallbacks.accG, Fallbacks.accB = ACC.r, ACC.g, ACC.b
    Fallbacks.bgR, Fallbacks.bgG, Fallbacks.bgB, Fallbacks.bgA = 0.08, 0.08, 0.08, 0.92
    Fallbacks.insetR, Fallbacks.insetG, Fallbacks.insetB, Fallbacks.insetA = 0.04, 0.04, 0.04, 0.85
    Fallbacks.brdR, Fallbacks.brdG, Fallbacks.brdB, Fallbacks.brdA = 0.2, 0.2, 0.2, 1
    Fallbacks.fontPath = (CUI.GetFontPath("blizzardSkin")) or CUI._font or STANDARD_TEXT_FONT
    Fallbacks.fontFlag = (CUI.GetFontOutlineFlag("blizzardSkin")) or ""
    Fallbacks.fontShadow = (Fallbacks.fontFlag == "")
        and (not CUI.GetFontUseShadow or CUI.GetFontUseShadow("blizzardSkin"))
end

local function SolidTex(hostFrame, layer, red, green, blue, a, sublevel)
    local tex = hostFrame:CreateTexture(nil, layer, nil, sublevel)
    tex:SetColorTexture(red, green, blue, a)
    return tex
end

-- BORDER/-7 strips demoted to the frame's own level, exactly as the window
-- engine draws its borders (content on the frame renders above them).
local function AddBorder(widget)
    local Pix = CUI.PanelPP or CUI.PP
    if not (Pix and Pix.CreateBorder) then
        return
    end
    local c = Pix.CreateBorder(widget, Fallbacks.brdR, Fallbacks.brdG, Fallbacks.brdB, Fallbacks.brdA, 1, "BORDER", -7)
    if c and c.SetFrameLevel then
        c:SetFrameLevel(widget:GetFrameLevel())
    end
end

-- family: a text that shows other players' writing (house and owner names)
-- takes the font as a font family, which draws the scripts the font lacks.
local function MakeText(hostFrame, size, red, green, blue, family)
    local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
    if family then
        CUI.SetFontFamily(fontStr, Fallbacks.fontPath, size, Fallbacks.fontFlag or "", Fallbacks.fontShadow)
    else
        CUI.PrimeFontShadow(fontStr, Fallbacks.fontShadow)
        fontStr:SetFont(Fallbacks.fontPath, size, Fallbacks.fontFlag or "")
    end
    fontStr:SetTextColor(red or 1, green or 1, blue or 1, 1)
    return fontStr
end

local function Panel(widget, inset)
    local red, green, blue, a = Fallbacks.bgR, Fallbacks.bgG, Fallbacks.bgB, Fallbacks.bgA
    if inset then
        red, green, blue, a = Fallbacks.insetR, Fallbacks.insetG, Fallbacks.insetB, Fallbacks.insetA
    end
    local backdrop = SolidTex(widget, "BACKGROUND", red, green, blue, a, -6)
    backdrop:SetAllPoints(widget)
    AddBorder(widget)
    return backdrop
end

-- Flat dark block with a subtle white hover and a white label; secure = a
-- SecureActionButton whose attributes the caller sets.
local function MakeButton(hostFrame, name, labelText, wid, hgt, secure)
    local widget = CreateFrame("Button", name, hostFrame, secure and "SecureActionButtonTemplate" or nil)
    widget:SetSize(wid, hgt)
    widget:RegisterForClicks("AnyUp")
    if secure then
        widget:SetAttribute("useOnKeyDown", false)
    end
    local fill = SolidTex(widget, "BACKGROUND", Fallbacks.bgR, Fallbacks.bgG, Fallbacks.bgB, Fallbacks.bgA)
    fill:SetAllPoints(widget)
    AddBorder(widget)
    local hover = SolidTex(widget, "HIGHLIGHT", 1, 1, 1, 0.1)
    hover:SetAllPoints(widget)
    local t = MakeText(widget, 12)
    t:SetPoint("CENTER")
    t:SetText(labelText)
    widget:SetFontString(t)
    return widget
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

    d.houses = MakeButton(d, nil, UNIT_VIEW_HOUSES or CUI.L("View Houses"), 112, 22, false)
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
function CUI._ShowReopenedMenuExtras(unitToken)
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

local listFrame, rowList, statusText, title
local pendingHouses -- last received house list, re-applied after combat
local listEv = CreateFrame("Frame")

local function BuildList()
    ResolveTheme()
    local frame = CreateFrame("Frame", "CludesUI_HouseVisitFrame", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetScale((CUI.GetPopupScale()) or 1)
    frame:SetWidth(FRAME_W)
    frame:SetHeight(HEADER_H + 10 + MAX_ROWS * (ROW_H + ROW_GAP) + 6)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    Panel(frame)

    -- Header band (inset fill) with the title and the close glyph, like a
    -- skinned window's title bar.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_H)
    local hbg = SolidTex(header, "BACKGROUND", Fallbacks.insetR, Fallbacks.insetG, Fallbacks.insetB, Fallbacks.insetA, -5)
    hbg:SetAllPoints(header)
    local hline = SolidTex(header, "BORDER", Fallbacks.brdR, Fallbacks.brdG, Fallbacks.brdB, Fallbacks.brdA)
    hline:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    hline:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    hline:SetHeight(1)

    title = MakeText(header, 14, nil, nil, nil, true)
    title:SetPoint("LEFT", header, "LEFT", 12, 0)
    title:SetPoint("RIGHT", header, "RIGHT", -34, 0)
    title:SetJustifyH("LEFT")

    local close = MakeCloseButton(header)
    close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    statusText = MakeText(frame, 12, 0.7, 0.7, 0.7)
    statusText:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(HEADER_H + 12))
    statusText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -(HEADER_H + 12))
    statusText:SetJustifyH("LEFT")

    rowList = {}
    for idx = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetHeight(ROW_H)
        local posY = -(HEADER_H + 10 + (idx - 1) * (ROW_H + ROW_GAP))
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, posY)
        row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, posY)
        Panel(row, true)

        row.name = MakeText(row, 13, nil, nil, nil, true)
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -7)
        row.name:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        row.name:SetJustifyH("LEFT")

        row.info = MakeText(row, 11, 0.65, 0.65, 0.65, true)
        row.info:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 7)
        row.info:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        row.info:SetJustifyH("LEFT")

        -- The teleport: a stock secure action, attributes = plain strings.
        local visit = MakeButton(row, "CludesUI_HouseVisit" .. idx, CUI.L("Visit"), 80, 24, true)
        visit:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        visit:SetAttribute("type", "visithouse")
        row.visit = visit

        row:Hide()
        rowList[idx] = row
    end

    if CUI.RegisterEscapeClose then
        CUI.RegisterEscapeClose(frame)
    end
    listFrame = frame
    return frame
end

local function ClearRows()
    for idx = 1, MAX_ROWS do
        rowList[idx]:Hide()
    end
end

local function ApplyHouses(houses)
    ClearRows()
    if not houses or #houses == 0 then
        statusText:SetText(CUI.L("No houses found."))
        statusText:Show()
        return
    end
    -- Attribute writes are refused in combat; keep the list and re-apply on
    -- PLAYER_REGEN_ENABLED (registered while shown).
    if InCombatLockdown() then
        statusText:SetText(CUI.L("Leave combat to enable visiting."))
        statusText:Show()
        return
    end
    statusText:Hide()
    for idx = 1, math.min(#houses, MAX_ROWS) do
        local hgt = houses[idx]
        local row = rowList[idx]
        row.name:SetText(hgt.houseName or CUI.L("House"))
        local where = hgt.neighborhoodName or ""
        if hgt.plotID then
            where = where
                .. (where ~= "" and "  -  " or "")
                .. string.format(HOUSING_PLOT_NUMBER or "Plot %d", hgt.plotID)
        end
        if hgt.ownerName and hgt.ownerName ~= "" then
            where = where .. (where ~= "" and "  -  " or "") .. hgt.ownerName
        end
        row.info:SetText(where)
        local visitBtn = row.visit
        visitBtn:SetAttribute("house-neighborhood-guid", hgt.neighborhoodGUID)
        visitBtn:SetAttribute("house-guid", hgt.houseGUID)
        visitBtn:SetAttribute("house-plot-id", hgt.plotID and tostring(hgt.plotID) or nil)
        local success = hgt.neighborhoodGUID and hgt.houseGUID and hgt.plotID
        visitBtn:SetAlpha(success and 1 or 0.3)
        visitBtn:EnableMouse(success and true or false)
        row:Show()
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
    local frame = listFrame
    if not frame then
        frame = BuildList()
        frame:SetScript("OnShow", ListOnShow)
        frame:SetScript("OnHide", ListOnHide)
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
    title:SetText(string.format(VIEW_HOUSES_TITLE or "%s's Houses", name))
    ClearRows()
    statusText:SetText(CUI.L("Loading houses..."))
    statusText:Show()
    frame:Show()
    C_Housing.GetOthersOwnedHouses(unitGuid, contextData.bnetIDAccount, not not contextData.isGuildMember)
end

-------------------------------------------------------------------------------
--  Menu modification: only the backstop's re-opened menu
-------------------------------------------------------------------------------
local function ModifyReopenedMenu(ownerFrame, rootDescription, contextData)
    if not CUI._menuReopenUnit then
        return
    end
    if not contextData or contextData.unit ~= CUI._menuReopenUnit then
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
