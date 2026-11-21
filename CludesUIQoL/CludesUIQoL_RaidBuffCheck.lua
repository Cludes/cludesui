if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not CludesUI or CludesUI.IS_FOREVER then
    return
end
-------------------------------------------------------------------------------
--  CludesUIQoL_RaidBuffCheck.lua -- Raid Buff Check, part of Raid Tools
--
--  A window listing each group member's flask, food, augment rune, vantus rune
--  and missing raid buffs (QoL > Raid Tools > RAID BUFF CHECK, off by default).
--  Opens from the Buff Check button (any group member: it only reads auras)
--  and, if wanted, on every ready check while the player leads or assists.
--  Settings live in the Raid Tools profile slice;
--  RaidTools' Apply calls ns.BuffCheckSync, so nothing listens while it is off.
--
--  Out of combat only. Flask and raid buff IDs are non-secret and looked up by
--  ID. Food has no fixed ID and needs an index scan, which errors under the
--  12.1 aura restriction, so food reads as unknown there, and so do augment
--  and vantus runes while their IDs are secret. Durability, weapon oils and
--  healthstones of other players are not readable without addon comms. The
--  window hides when combat starts.
-------------------------------------------------------------------------------
local _, mod = ...

local IsSecret, PlainString = CludesUI.IsSecret, CludesUI.PlainString
local RT = mod.RT

local WELL_FED_ICON = 136000
local EATING_ICON = 133950
local AURA_SCAN_LIMIT = 255
local EXPIRE_SOON = 600 -- under 10 minutes left shows the time instead of a check
local TICK = 15 -- countdown repaint interval while one shows
local TEX_YES = "Interface\\RaidFrame\\ReadyCheck-Ready"
local TEX_NO = "Interface\\RaidFrame\\ReadyCheck-NotReady"
-- SEASON UPDATE: the season's augment rune and Vantus Rune items (header icons).
local RUNE_ITEM = 259085 -- header icons come from items: the buff spells have no cached texture
local VANTUS_ITEM = 272195 -- Vantus Rune: Tides

-- Buff IDs: the shared lists AuraBuff Reminders reads too. Older augment runes
-- count as missing. Raid buffs: only those whose class is in the group are checked.
local PREP = CludesUI.RAID_PREP_IDS
local FLASK_BUFF_IDS = PREP.flask
local RUNE_IDS, OLD_RUNE_IDS = PREP.rune, PREP.oldRune
local VANTUS_IDS = PREP.vantus
local RAID_BUFFS = PREP.raidBuffs

local PAD, TITLE_H, HEAD_H = 8, RT.TOPBAR_H, 20
local ROW_H, NAME_W, CELL_W, ICON = 18, 110, 24, 14
local BUFF_SLOTS, BUFF_STEP = 6, 16
local CELLS = 4 -- flask, food, rune, vantus
local RUNE_COL, VANTUS_COL = 3, 4
local BLOCK_GAP = 12
local ROWS_PER_BLOCK = 20
local TOTAL_ROWS = 3 -- Missing, Expiring soon, Unknown
local MIN_W = 400 -- fits the note line; the checkbox row can widen it
local NOTE_H = 16
local CB_H = 22 -- checkbox row between the totals and the note

local eventFrame = CreateFrame("Frame")
local widget
local rowList, heads = {}, {}
local units = {} -- display order
local isMember = {} -- [unit] = true for listed group members
local states = {} -- [unit] = last computed state, reused
local shownUnits = {} -- units drawn, in order
local Render -- defined with the refresh code below

-- Column geometry. The rune and vantus columns drop out while their Require
-- box is off; SetColumns recomputes this and bumps colsKey, and every row,
-- header and totals row re-places itself once per change (Place*).
local colShown, colX = { true, true, true, true }, {}
local buffsX, blockW
local colsKey = 0

local function SetColumns(runeShown, vantusShown)
    if buffsX and colShown[RUNE_COL] == runeShown and colShown[VANTUS_COL] == vantusShown then
        return
    end
    colShown[RUNE_COL], colShown[VANTUS_COL] = runeShown, vantusShown
    local posX = NAME_W
    for key = 1, CELLS do
        colX[key] = posX
        if colShown[key] then
            posX = posX + CELL_W
        end
    end
    buffsX = posX + 4
    blockW = buffsX + BUFF_SLOTS * BUFF_STEP + 2
    colsKey = colsKey + 1
end
SetColumns(true, false)
local providers = {} -- [classToken] = true for connected members
local dirty, flushPending, rosterDirty = {}, false, false
local runeReadable, vantusReadable -- every ID of the list is non-secret on this client; set on first open

local function CDB()
    return mod.RaidToolsProfile and mod.RaidToolsProfile()
end

local function Enabled()
    local cfg = CDB()
    return cfg and cfg.buffCheck == true
end

local function OpenOnReady()
    local cfg = CDB()
    return cfg and cfg.buffCheckOnReady ~= false
end

-- Default on: shows only the players who are not fully buffed.
local function OnlyMissing()
    local cfg = CDB()
    return not cfg or cfg.buffCheckOnlyMissing ~= false
end

-- Default on: a missing augment rune makes a player not fully buffed.
local function RuneRequired()
    local cfg = CDB()
    return not cfg or cfg.buffCheckRuneRequired ~= false
end

-- Default off: a missing vantus rune makes a player not fully buffed.
local function VantusRequired()
    local cfg = CDB()
    return cfg and cfg.buffCheckVantusRequired == true or false
end

local function Restricted()
    return CludesUI.AuraKit.AurasRestricted()
end

local function Msg(textValue)
    CludesUI.Print(CludesUI.COLOR_CODES.BRAND .. "CludesUI:|r " .. textValue)
end

-- On-screen text in the QoL font; Raid Tools' ApplyFonts keeps it current.
local function Text(hostFrame, size, red, green, blue)
    return RT.Text(widget, hostFrame, size, red, green, blue)
end

-------------------------------------------------------------------------------
--  Aura lookups
-------------------------------------------------------------------------------
local function AllReadable(ids)
    local should = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    if not should then
        return true
    end
    for index = 1, #ids do
        local success, secret = pcall(should, ids[index])
        if not success or IsSecret(secret) or secret ~= false then
            return false
        end
    end
    return true
end

-- What a present aura reads as: its expiration time, or true when that is
-- secret or the aura never expires.
local function Present(aura)
    local exp = aura.expirationTime
    if exp == nil or IsSecret(exp) or exp == 0 then
        return true
    end
    return exp
end

-- Non-nil means the aura is there, even when its fields are secret.
local function FindID(unitToken, ident)
    local success, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unitToken, ident)
    if success and aura ~= nil then
        return Present(aura)
    end
end

-- State values: true or an expiration time = has it, false = verified
-- missing, nil = cannot tell, "eating" = food channel up.
local function ListState(unitToken, ids, readable, restricted)
    for index = 1, #ids do
        local val = FindID(unitToken, ids[index])
        if val then
            return val
        end
    end
    if restricted and not readable then
        return nil
    end
    return false
end

-- Seconds left when under EXPIRE_SOON, else nil.
local function SoonLeft(val, nowTime)
    if type(val) ~= "number" then
        return nil
    end
    local leftX = val - nowTime
    if leftX < EXPIRE_SOON then
        return math.max(0, leftX)
    end
end

local function MinutesText(leftX)
    return CludesUI.Lf("%dm", math.ceil(leftX / 60))
end

-- "eating" while the food channel is up.
local function FoodState(unitToken, restricted)
    if restricted then
        return nil
    end
    local sawReadable, eating = false, false
    for index = 1, AURA_SCAN_LIMIT do
        local success, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unitToken, index, "HELPFUL")
        if not success then
            return nil
        end
        if not aura then
            break
        end
        local ic = aura.icon
        if ic ~= nil and not IsSecret(ic) then
            sawReadable = true
            if ic == WELL_FED_ICON then
                return Present(aura)
            end
            -- Eating only counts when no stat buff is up: refreshing one shows both.
            if ic == EATING_ICON then
                eating = true
            end
        end
    end
    if eating then
        return "eating"
    end
    if not sawReadable then
        return nil
    end
    return false
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local function SetCell(cell, status, nowTime)
    if status == nil then
        cell.tex:Hide()
        cell.q:SetText("?")
        cell.q:SetTextColor(0.6, 0.6, 0.6)
        cell.q:Show()
        return
    end
    local leftX = SoonLeft(status, nowTime)
    if leftX then
        cell.tex:Hide()
        cell.q:SetText(MinutesText(leftX))
        cell.q:SetTextColor(1, 0.8, 0.2)
        cell.q:Show()
        return
    end
    cell.q:Hide()
    if status == "eating" then
        cell.tex:SetTexture(EATING_ICON)
        cell.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        cell.tex:SetTexture(status and TEX_YES or TEX_NO)
        cell.tex:SetTexCoord(0, 1, 0, 1)
    end
    cell.tex:Show()
end

local function MakeCell(hostFrame)
    local cell = CreateFrame("Frame", nil, hostFrame)
    cell:SetSize(CELL_W, ROW_H)
    cell.tex = cell:CreateTexture(nil, "ARTWORK")
    cell.tex:SetSize(ICON, ICON)
    cell.tex:SetPoint("CENTER")
    cell.q = Text(cell, 11, 0.6, 0.6, 0.6)
    cell.q:SetPoint("CENTER")
    cell.q:SetText("?")
    return cell
end

local function MakeRow(index)
    local region = CreateFrame("Frame", nil, widget.table)
    region:SetHeight(ROW_H)
    if index % 2 == 0 then
        local stripe = region:CreateTexture(nil, "BACKGROUND")
        stripe:SetColorTexture(1, 1, 1, 0.03)
        stripe:SetAllPoints(region)
    end
    -- A member's name: a font family, which draws the scripts the font lacks
    region.name = RT.NameText(widget, region, 11, 1, 1, 1)
    region.name:SetPoint("LEFT", region, "LEFT", 4, 0)
    region.name:SetWidth(NAME_W - 6)
    region.name:SetJustifyH("LEFT")
    region.name:SetWordWrap(false)
    region.flask = MakeCell(region)
    region.food = MakeCell(region)
    region.rune = MakeCell(region)
    region.vantus = MakeCell(region)
    region.cells = { region.flask, region.food, region.rune, region.vantus }
    region.buffs = {}
    for jdx = 1, BUFF_SLOTS do
        local tex = region:CreateTexture(nil, "ARTWORK")
        tex:SetSize(ICON, ICON)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        region.buffs[jdx] = tex
    end
    region.buffsOk = region:CreateTexture(nil, "ARTWORK")
    region.buffsOk:SetSize(ICON, ICON)
    region.buffsOk:SetTexture(TEX_YES)
    region.buffsQ = Text(region, 11, 0.6, 0.6, 0.6)
    region.buffsQ:SetPoint("LEFT", region.buffsOk, "LEFT", 0, 0)
    region.buffsQ:SetText("?")
    rowList[index] = region
    return region
end

local function PlaceRow(region)
    if region._colsKey == colsKey then
        return
    end
    region._colsKey = colsKey
    region:SetWidth(blockW)
    for key = 1, CELLS do
        local cell = region.cells[key]
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", region, "LEFT", colX[key], 0)
        cell:SetShown(colShown[key])
    end
    for jdx = 1, BUFF_SLOTS do
        region.buffs[jdx]:ClearAllPoints()
        region.buffs[jdx]:SetPoint("LEFT", region, "LEFT", buffsX + (jdx - 1) * BUFF_STEP, 0)
    end
    region.buffsOk:ClearAllPoints()
    region.buffsOk:SetPoint("LEFT", region, "LEFT", buffsX, 0)
end

local function PlaceHeader(hgt)
    if hgt._colsKey == colsKey then
        return
    end
    hgt._colsKey = colsKey
    hgt:SetWidth(blockW)
    for key = 1, CELLS do
        local hit = hgt.icons[key]
        hit:ClearAllPoints()
        hit:SetPoint("LEFT", hgt, "LEFT", colX[key], 0)
        hit:SetShown(colShown[key])
    end
    hgt.buffsLabel:ClearAllPoints()
    hgt.buffsLabel:SetPoint("LEFT", hgt, "LEFT", buffsX, 0)
end

local function PlaceTotals(tr)
    if tr._colsKey == colsKey then
        return
    end
    tr._colsKey = colsKey
    tr:SetWidth(blockW)
    for key = 1, CELLS do
        local fontStr = tr.counts[key]
        fontStr:ClearAllPoints()
        fontStr:SetPoint("CENTER", tr, "LEFT", colX[key] + CELL_W / 2, 0)
        fontStr:SetShown(colShown[key])
    end
    tr.counts[CELLS + 1]:ClearAllPoints()
    tr.counts[CELLS + 1]:SetPoint("CENTER", tr, "LEFT", buffsX + ICON / 2, 0)
end

local function MakeHeader(b)
    local hgt = CreateFrame("Frame", nil, widget.table)
    hgt:SetHeight(HEAD_H)
    hgt.icons = {}
    local function MakeIcon(texture, tipText)
        local hit = CreateFrame("Frame", nil, hgt)
        hit:SetSize(CELL_W, HEAD_H)
        hgt.icons[#hgt.icons + 1] = hit
        local tex = hit:CreateTexture(nil, "ARTWORK")
        tex:SetSize(ICON + 2, ICON + 2)
        tex:SetPoint("CENTER")
        tex:SetTexture(texture)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function(self)
            CludesUI.ShowWidgetTooltip(self, tipText)
        end)
        hit:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
    end
    MakeIcon(C_Spell.GetSpellTexture(FLASK_BUFF_IDS[1]), CludesUI.L("Flask"))
    MakeIcon(WELL_FED_ICON, CludesUI.L("Food"))
    MakeIcon(C_Item.GetItemIconByID(RUNE_ITEM), CludesUI.L("Augment Rune"))
    MakeIcon(C_Item.GetItemIconByID(VANTUS_ITEM), CludesUI.L("Vantus Rune"))
    hgt.buffsLabel = Text(hgt, 11, 0.8, 0.8, 0.8)
    hgt.buffsLabel:SetText(CludesUI.L("Raid Buffs"))
    heads[b] = hgt
    return hgt
end

-- The window's events follow the window; READY_CHECK follows the option.
local function Listen(isShown)
    eventFrame:UnregisterAllEvents()
    if Enabled() and OpenOnReady() then
        eventFrame:RegisterEvent("READY_CHECK")
    end
    if isShown then
        eventFrame:RegisterEvent("UNIT_AURA")
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        eventFrame:RegisterEvent("UNIT_CONNECTION")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    end
end

-- Kept as a TOPLEFT offset: the height (and width) change with the roster and
-- the filter, and the top-left corner must stay put while they do.
local function SavePosition()
    local cfg = CDB()
    if not cfg then
        return
    end
    local leftX, topY = widget:GetLeft(), widget:GetTop()
    if not (leftX and topY) then
        return
    end
    local posX, posY = leftX, topY - UIParent:GetTop()
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", UIParent, "TOPLEFT", posX, posY)
    cfg.buffCheckPos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = posX, y = posY }
end

local function StopWake()
    if widget._wake then
        widget._wake:Cancel()
    end
    widget._wake, widget._wakeAt = nil, nil
end

local function Build()
    if widget then
        return
    end
    widget = CreateFrame("Frame", "CludesUIRaidBuffCheck", UIParent)
    widget:SetFrameStrata("MEDIUM")
    widget:SetClampedToScreen(true)
    widget:SetMovable(true)
    widget:EnableMouse(true)
    widget:RegisterForDrag("LeftButton")
    widget:SetScript("OnDragStart", widget.StartMoving)
    widget:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    widget:Hide()
    widget:SetScript("OnHide", function()
        Listen(false)
        StopWake()
    end)
    RT.AddFontOwner(widget)
    RT.SkinPanelBg(widget)
    RT.SkinPanelBorder(widget)

    local title = Text(widget, 12, 1, 1, 1)
    title:SetPoint("LEFT", widget, "TOPLEFT", PAD, -TITLE_H / 2)
    title:SetText(CludesUI.L("Raid Buff Check"))

    local close = CreateFrame("Button", nil, widget)
    close:SetSize(14, 14)
    close:SetPoint("RIGHT", widget, "TOPRIGHT", -6, -TITLE_H / 2)
    RT.SkinButtonChrome(close)
    local cfs = Text(close, 12, 1, 1, 1)
    cfs:SetPoint("CENTER", close, "CENTER", 0, 1)
    cfs:SetText("x")
    cfs:SetAlpha(0.7)
    close:SetScript("OnEnter", function()
        cfs:SetAlpha(1)
    end)
    close:SetScript("OnLeave", function()
        cfs:SetAlpha(0.7)
    end)
    close:SetScript("OnClick", function()
        widget:Hide()
    end)

    -- Checkbox row above the note, left to right; each label is part of its
    -- box's hit rect.
    local accR, accG, accB = CludesUI.GetAccentColor()
    local function MakeCheckbox(textValue, onClick)
        local callback = CreateFrame("Button", nil, widget)
        callback:SetSize(14, 14)
        local box = callback:CreateTexture(nil, "BACKGROUND")
        box:SetColorTexture(0.08, 0.08, 0.08, 0.92)
        box:SetAllPoints(callback)
        CludesUI.MakeBorder(callback, 0.35, 0.35, 0.35, 1)
        callback.check = callback:CreateTexture(nil, "ARTWORK")
        callback.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        callback.check:SetPoint("CENTER")
        callback.check:SetSize(16, 16)
        callback.check:SetVertexColor(accR, accG, accB)
        callback.label = Text(widget, 11, 0.85, 0.85, 0.85)
        callback.label:SetPoint("LEFT", callback, "RIGHT", 6, 0)
        callback.label:SetText(textValue)
        callback:SetHitRectInsets(0, -(callback.label:GetStringWidth() + 6), 0, 0)
        callback:SetScript("OnClick", onClick)
        return callback
    end
    widget.onlyBox = MakeCheckbox(CludesUI.L("Hide Fully Buffed"), function()
        local cfg = CDB()
        if not cfg then
            return
        end
        cfg.buffCheckOnlyMissing = not OnlyMissing()
        Render()
    end)
    widget.runeBox = MakeCheckbox(CludesUI.L("Require Augment Rune"), function()
        local cfg = CDB()
        if not cfg then
            return
        end
        cfg.buffCheckRuneRequired = not RuneRequired()
        Render()
    end)
    widget.vantusBox = MakeCheckbox(CludesUI.L("Require Vantus Rune"), function()
        local cfg = CDB()
        if not cfg then
            return
        end
        cfg.buffCheckVantusRequired = not VantusRequired()
        Render()
    end)
    widget.boxes = { widget.onlyBox, widget.runeBox, widget.vantusBox }
    widget.onlyBox:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", PAD + 4, NOTE_H + (CB_H - 14) / 2)
    widget.runeBox:SetPoint("LEFT", widget.onlyBox.label, "RIGHT", 16, 0)
    widget.vantusBox:SetPoint("LEFT", widget.runeBox.label, "RIGHT", 16, 0)

    widget.empty = Text(widget, 11, 0.4, 0.9, 0.4)
    widget.empty:SetPoint("TOPLEFT", widget, "TOPLEFT", PAD + 4, -TITLE_H - 6)
    widget.empty:SetText(CludesUI.L("Everyone is fully buffed."))
    widget.empty:Hide()

    -- The table (column headers, player rows, totals) in one container, so
    -- "everyone fully buffed" hides it in one go.
    widget.table = CreateFrame("Frame", nil, widget)
    widget.table:SetAllPoints(widget)

    -- Totals under the first block: one count per column, aligned with its cells.
    -- Render places them; a row of zeros is hidden.
    local labels = { CludesUI.L("Missing"), CludesUI.L("Expiring soon"), CludesUI.L("Unknown") }
    widget.totals = {}
    for t = 1, TOTAL_ROWS do
        local tr = CreateFrame("Frame", nil, widget.table)
        tr:SetHeight(ROW_H)
        local labelFS = Text(tr, 11, 0.85, 0.85, 0.85)
        labelFS:SetPoint("LEFT", tr, "LEFT", 4, 0)
        labelFS:SetText(labels[t])
        tr.counts = {}
        for key = 1, CELLS + 1 do
            tr.counts[key] = Text(tr, 11, 1, 1, 1)
        end
        widget.totals[t] = tr
    end
    widget.sep = widget.table:CreateTexture(nil, "ARTWORK")
    widget.sep:SetColorTexture(1, 1, 1, 0.15)
    widget.sep:SetHeight(1)
    widget.note = Text(widget, 10, 0.6, 0.6, 0.6)
    widget.note:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", PAD, 4)

    local place = CDB() and CDB().buffCheckPos
    if place and place.point == "TOPLEFT" then
        widget:SetPoint("TOPLEFT", UIParent, "TOPLEFT", place.x or 0, place.y or 0)
    else
        widget:SetPoint("TOPLEFT", UIParent, "TOPLEFT", UIParent:GetWidth() / 2 - MIN_W / 2, -150)
    end
end

-------------------------------------------------------------------------------
--  Roster and refresh: a state per unit, then Render draws the shown subset
-------------------------------------------------------------------------------
local function UnitClassToken(unitToken)
    local _, classTok = UnitClass(unitToken)
    return PlainString(classTok)
end

-- Alphabetical by name; a secret name sorts last, by unit token.
local sortName = {}
local function SortByName(a, b)
    local na, nb = sortName[a], sortName[b]
    if na ~= nb then
        if not na then
            return false
        end
        if not nb then
            return true
        end
        return na < nb
    end
    return a < b
end

local function CollectUnits()
    wipe(units)
    wipe(providers)
    wipe(isMember)
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            local u = "raid" .. index
            if UnitExists(u) then
                units[#units + 1] = u
            end
        end
    else
        units[1] = "player"
        for index = 1, GetNumSubgroupMembers() do
            local u = "party" .. index
            if UnitExists(u) then
                units[#units + 1] = u
            end
        end
    end
    wipe(sortName)
    for index = 1, #units do
        local u = units[index]
        local name = PlainString(UnitName(u))
        if name then
            sortName[u] = strlower(name)
        end
    end
    table.sort(units, SortByName)
    for index = 1, #units do
        local u = units[index]
        isMember[u] = true
        local cls = UnitIsConnected(u) and UnitClassToken(u)
        if cls then
            providers[cls] = true
        end
    end
end

local function ComputeState(unitToken, restricted)
    local cfg = states[unitToken]
    if not cfg then
        cfg = { icons = {} }
        states[unitToken] = cfg
    end
    local online = UnitIsConnected(unitToken)
    local dead = UnitIsDeadOrGhost(unitToken)
    local visible = UnitIsVisible(unitToken)
    if IsSecret(online) then
        online = true
    end
    if IsSecret(dead) then
        dead = false
    end
    if IsSecret(visible) then
        visible = true
    end
    cfg.online = online
    cfg.missing = 0
    cfg.buffsExp = nil
    local icons = cfg.icons
    if not online or dead or not visible then
        cfg.flask, cfg.food, cfg.rune, cfg.vantus = nil, nil, nil, nil
        for jdx = #icons, 1, -1 do
            icons[jdx] = nil
        end
        return
    end
    cfg.flask = ListState(unitToken, FLASK_BUFF_IDS, true, false)
    cfg.food = FoodState(unitToken, restricted)
    cfg.rune = ListState(unitToken, RUNE_IDS, runeReadable, restricted)
    if not cfg.rune and ListState(unitToken, OLD_RUNE_IDS, true, false) then
        cfg.rune = false
    end
    cfg.vantus = ListState(unitToken, VANTUS_IDS, vantusReadable, restricted)
    local num = 0
    for _, buff in ipairs(RAID_BUFFS) do
        if providers[buff.class] then
            local has
            local ids = buff.buffIDs
            for key = 1, #ids do
                has = FindID(unitToken, ids[key])
                if has then
                    break
                end
            end
            if not has then
                num = num + 1
                icons[num] = buff.castSpell
            elseif type(has) == "number" and (not cfg.buffsExp or has < cfg.buffsExp) then
                cfg.buffsExp = has
            end
        end
    end
    for jdx = #icons, num + 1, -1 do
        icons[jdx] = nil
    end
    cfg.missing = num
end

-- Missing, unknown (nil) and running out count; eating does not.
local function NotFullyBuffed(cfg, nowTime, runeRequired, vantusRequired)
    if runeRequired and (not cfg.rune or SoonLeft(cfg.rune, nowTime)) then
        return true
    end
    if vantusRequired and (not cfg.vantus or SoonLeft(cfg.vantus, nowTime)) then
        return true
    end
    return not cfg.flask
        or not cfg.food
        or cfg.missing > 0
        or SoonLeft(cfg.flask, nowTime)
        or SoonLeft(cfg.food, nowTime)
        or SoonLeft(cfg.buffsExp, nowTime)
end

local function PaintRow(region, unitToken, nowTime)
    local cfg = states[unitToken]
    region.name:SetText(UnitName(unitToken))
    local cls = UnitClassToken(unitToken)
    local cc = cls and CludesUI.GetClassColor(cls)
    if cc and cfg.online then
        region.name:SetTextColor(cc.r, cc.g, cc.b)
    else
        region.name:SetTextColor(0.5, 0.5, 0.5)
    end
    SetCell(region.flask, cfg.flask, nowTime)
    SetCell(region.food, cfg.food, nowTime)
    SetCell(region.rune, cfg.rune, nowTime)
    SetCell(region.vantus, cfg.vantus, nowTime)
    local icons = cfg.icons
    for jdx = 1, BUFF_SLOTS do
        local ident = icons[jdx]
        if ident then
            region.buffs[jdx]:SetTexture(C_Spell.GetSpellTexture(ident))
            region.buffs[jdx]:Show()
        else
            region.buffs[jdx]:Hide()
        end
    end
    -- flask is nil only for a row that was not read at all (offline, dead, out of range).
    local leftX = cfg.missing == 0 and SoonLeft(cfg.buffsExp, nowTime)
    region.buffsOk:SetShown(cfg.flask ~= nil and cfg.missing == 0 and not leftX)
    if cfg.flask == nil then
        region.buffsQ:SetText("?")
        region.buffsQ:SetTextColor(0.6, 0.6, 0.6)
        region.buffsQ:Show()
    elseif leftX then
        region.buffsQ:SetText(MinutesText(leftX))
        region.buffsQ:SetTextColor(1, 0.8, 0.2)
        region.buffsQ:Show()
    else
        region.buffsQ:Hide()
    end
end

-- Wide enough for the note line and the checkbox row (its labels follow the font).
local function MinWidth()
    local wid = PAD + 4
    for index, callback in ipairs(widget.boxes) do
        if index > 1 then
            wid = wid + 16
        end
        wid = wid + 14 + 6 + callback.label:GetStringWidth()
    end
    return math.max(MIN_W, wid + PAD)
end

-- n == 0: Render hides the whole table; the empty message takes one row
-- under the title.
local function Layout(num, nTotals)
    if num == 0 then
        widget:SetSize(MinWidth(), TITLE_H + 2 + ROW_H + 6 + CB_H + NOTE_H)
        widget._bgFit()
        return
    end
    local blocks = math.max(1, math.ceil(num / ROWS_PER_BLOCK))
    local perBlock = math.max(1, math.ceil(num / blocks))
    for b = 1, blocks do
        local hgt = heads[b] or MakeHeader(b)
        PlaceHeader(hgt)
        hgt:ClearAllPoints()
        hgt:SetPoint("TOPLEFT", widget, "TOPLEFT", PAD + (b - 1) * (blockW + BLOCK_GAP), -TITLE_H - 2)
        hgt:Show()
    end
    for b = blocks + 1, #heads do
        heads[b]:Hide()
    end
    for index = 1, num do
        local row = rowList[index] or MakeRow(index)
        PlaceRow(row)
        local b = math.floor((index - 1) / perBlock)
        local slot = (index - 1) % perBlock
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", heads[b + 1], "BOTTOMLEFT", 0, -slot * ROW_H)
        row:Show()
    end
    for index = num + 1, #rowList do
        rowList[index]:Hide()
    end
    widget:SetSize(
        math.max(MinWidth(), PAD * 2 + blocks * blockW + (blocks - 1) * BLOCK_GAP),
        TITLE_H + 2 + HEAD_H + perBlock * ROW_H + 6 + nTotals * ROW_H + CB_H + NOTE_H
    )
    widget._bgFit()
end

-- totals[row][column]; columns are flask, food, rune, vantus, raid buffs.
local totals = { {}, {}, {} }

local function Tally(tbl, colour, val, nowTime)
    if val == false then
        tbl[1][colour] = tbl[1][colour] + 1
    elseif val == nil then
        tbl[3][colour] = tbl[3][colour] + 1
    elseif SoonLeft(val, nowTime) then
        tbl[2][colour] = tbl[2][colour] + 1
    end
end

-- The next time the drawing changes on its own: a countdown's next step, or a
-- shown buff crossing into its last 10 minutes. One timer, re-armed only for
-- an earlier time.
local wakeAt
local function Wake(val, nowTime)
    if type(val) ~= "number" then
        return
    end
    local at = val - EXPIRE_SOON
    if at <= nowTime then
        at = nowTime + TICK
    end
    if not wakeAt or at < wakeAt then
        wakeAt = at
    end
end

local function OnWake()
    widget._wake, widget._wakeAt = nil, nil
    Render()
end

function Render()
    local filter = OnlyMissing()
    local runeRequired, vantusRequired = RuneRequired(), VantusRequired()
    SetColumns(runeRequired, vantusRequired)
    local nowTime = GetTime()
    for t = 1, TOTAL_ROWS do
        for key = 1, CELLS + 1 do
            totals[t][key] = 0
        end
    end
    wipe(shownUnits)
    wakeAt = nil
    for index = 1, #units do
        local u = units[index]
        local cfg = states[u]
        if cfg then
            Tally(totals, 1, cfg.flask, nowTime)
            Tally(totals, 2, cfg.food, nowTime)
            Tally(totals, 3, cfg.rune, nowTime)
            Tally(totals, 4, cfg.vantus, nowTime)
            -- Raid buffs: unread row = unknown, a missing buff = missing, else the soonest expiry.
            if cfg.flask == nil then
                totals[3][5] = totals[3][5] + 1
            elseif cfg.missing > 0 then
                totals[1][5] = totals[1][5] + 1
            elseif SoonLeft(cfg.buffsExp, nowTime) then
                totals[2][5] = totals[2][5] + 1
            end
            Wake(cfg.flask, nowTime)
            Wake(cfg.food, nowTime)
            if runeRequired then
                Wake(cfg.rune, nowTime)
            end
            if vantusRequired then
                Wake(cfg.vantus, nowTime)
            end
            Wake(cfg.buffsExp, nowTime)
            if not filter or NotFullyBuffed(cfg, nowTime, runeRequired, vantusRequired) then
                shownUnits[#shownUnits + 1] = u
            end
        end
    end
    -- Totals rows with a non-zero count, stacked upward from the note line.
    local num = #shownUnits
    local nTotals, topY = 0, nil
    for t = TOTAL_ROWS, 1, -1 do
        local tr = widget.totals[t]
        PlaceTotals(tr)
        local any = false
        for key = 1, CELLS + 1 do
            local c = totals[t][key]
            tr.counts[key]:SetText(c)
            if c == 0 then
                tr.counts[key]:SetTextColor(0.3, 0.9, 0.3)
            else
                tr.counts[key]:SetTextColor(1, 0.3, 0.3)
                -- A hidden column's count does not keep its row up.
                if key > CELLS or colShown[key] then
                    any = true
                end
            end
        end
        tr:SetShown(any)
        if any then
            tr:ClearAllPoints()
            tr:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", PAD, NOTE_H + CB_H + nTotals * ROW_H)
            nTotals = nTotals + 1
            topY = tr
        end
    end
    widget.sep:ClearAllPoints()
    if topY then
        widget.sep:SetPoint("BOTTOMLEFT", topY, "TOPLEFT", 0, 1)
        widget.sep:SetPoint("BOTTOMRIGHT", topY, "TOPRIGHT", 0, 1)
    end
    widget.sep:SetShown(topY ~= nil)

    Layout(num, nTotals)
    for index = 1, num do
        PaintRow(rowList[index], shownUnits[index], nowTime)
    end
    -- Nobody listed (everyone fully buffed): no header and no totals either,
    -- even when a count is non-zero for a column the filter ignores.
    widget.table:SetShown(num > 0)
    widget.empty:SetShown(num == 0)
    widget.onlyBox.check:SetShown(filter)
    widget.runeBox.check:SetShown(runeRequired)
    widget.vantusBox.check:SetShown(vantusRequired)
    if widget._restricted then
        widget.note:SetText(CludesUI.L("Food and runes cannot be read here (aura restriction). ? = unknown"))
    else
        widget.note:SetText(CludesUI.L("? = unknown (offline, dead or out of range)"))
    end
    if wakeAt and (not widget._wakeAt or wakeAt < widget._wakeAt) then
        if widget._wake then
            widget._wake:Cancel()
        end
        widget._wake = C_Timer.NewTimer(wakeAt - nowTime, OnWake)
        widget._wakeAt = wakeAt
    end
end

local function Rebuild()
    if not widget or not widget:IsShown() or InCombatLockdown() then
        return
    end
    CollectUnits()
    local restricted = Restricted()
    widget._restricted = restricted
    for index = 1, #units do
        ComputeState(units[index], restricted)
    end
    Render()
end

-- Same-burst events end in one pass: a roster or connection change re-reads
-- every member, aura changes only the members they named.
local function Flush()
    flushPending = false
    if not widget or not widget:IsShown() or InCombatLockdown() then
        wipe(dirty)
        rosterDirty = false
        return
    end
    if rosterDirty then
        rosterDirty = false
        wipe(dirty)
        Rebuild()
        return
    end
    local restricted = Restricted()
    widget._restricted = restricted
    for unitToken in pairs(dirty) do
        if isMember[unitToken] then
            ComputeState(unitToken, restricted)
        end
    end
    wipe(dirty)
    Render()
end

local function QueueFlush()
    if not flushPending then
        flushPending = true
        C_Timer.After(0.2, Flush)
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local function Open()
    if InCombatLockdown() then
        Msg(CludesUI.L("Raid Buff Check cannot be opened in combat."))
        return
    end
    if runeReadable == nil then
        runeReadable = AllReadable(RUNE_IDS)
        vantusReadable = AllReadable(VANTUS_IDS)
    end
    Build()
    widget:Show()
    Listen(true)
    Rebuild()
end

-- Called by RaidTools' Apply (login, settings, profile switch).
function mod.BuffCheckSync()
    if not Enabled() and widget then
        widget:Hide()
    end
    Listen(widget and widget:IsShown())
end

eventFrame:SetScript("OnEvent", function(_, evt, unitToken)
    if evt == "UNIT_AURA" then
        if not isMember[unitToken] then
            return
        end
        dirty[unitToken] = true
        QueueFlush()
    elseif evt == "UNIT_CONNECTION" then
        -- Also who can provide the raid buffs.
        if not isMember[unitToken] then
            return
        end
        rosterDirty = true
        QueueFlush()
    elseif evt == "GROUP_ROSTER_UPDATE" then
        if not IsInGroup() then
            widget:Hide()
            return
        end
        rosterDirty = true
        QueueFlush()
    elseif evt == "READY_CHECK" then
        if RT.HasAssist() then
            Open()
        end
    elseif evt == "PLAYER_REGEN_DISABLED" then
        if widget then
            widget:Hide()
        end
    end
end)

-- The Buff Check button.
function mod.ToggleBuffCheck()
    if not Enabled() then
        return
    end
    if widget and widget:IsShown() then
        widget:Hide()
        return
    end
    Open()
end
