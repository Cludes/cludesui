if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBags_List.lua
--  List bag display (bagDisplayMode = "list"): one row per bag slot, grouped by category
--  with optional subtype sub-sections, and a column header bar on the bag
--  frame (click = sort, drag = reorder, right-click = add/remove columns).
--  Mode is latched per session (CUI_Bags.IsListMode): in the Grid and Compact
--  displays nothing here is ever built. The bank's List View (bankListView) reuses the row,
--  column and header bar pieces via ns.
-------------------------------------------------------------------------------
local mod = select(2, ...)
if not (mod and mod.SetBagFont) then
    return
end

local CUI = CludesUI
local L = CludesUI.L
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local _emptyP = {}
local function BP()
    return (CUI._bagsDB and CUI._bagsDB.profile) or _emptyP
end

local ROW_H, ICON_SIZE, COL_GAP = 24, 20, 6
local function RowH()
    return BP().bagListRowHeight or ROW_H
end
local COLHDR_H = 20
local SECTION_H, SUBSECTION_H = 22, 18
local ROUND_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local ROUND_ZOOM = 0.12
local ARROW_TEX = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-left.png"
local BAG_GLYPH_TEX = "Interface\\AddOns\\CludesUI\\media\\micromenu\\menu-bags.png"

-- Column definitions. width nil = flexible (takes the leftover row width).
-- field = the per-item sort value stamped in StampItem (nil = not
-- sortable); desc = numeric
-- columns sort high-to-low on first click.
local COLUMNS = {
    icon = { label = "", width = ICON_SIZE, menuLabel = "Icon" }, -- not sortable
    name = { label = "Name", field = "_lvName", justify = "LEFT" },
    ilvl = { label = "iLvl", width = 36, field = "_lvIlvl", desc = true, justify = "RIGHT" },
    reqlvl = {
        label = "Req",
        width = 32,
        field = "_lvReq",
        desc = true,
        justify = "RIGHT",
        menuLabel = "Required Level",
    },
    type = { label = "Type", width = 96, field = "_lvType", justify = "LEFT" },
    bind = {
        label = "Bind",
        width = 40,
        field = "_lvBind",
        justify = "LEFT",
        menuLabel = "Bind Status",
    },
    track = {
        label = "Track",
        width = 40,
        field = "_lvTrackSort",
        desc = true,
        justify = "RIGHT",
        menuLabel = "Upgrade Track",
    },
    count = { label = "#", width = 40, field = "_lvCount", desc = true, justify = "RIGHT" },
    sell = { label = "Sell Price", width = 100, field = "_lvSell", desc = true, justify = "RIGHT" },
}
local COLUMN_ORDER = { "icon", "name", "ilvl", "track", "reqlvl", "type", "bind", "count", "sell" }
local DEFAULT_COLUMNS = { "icon", "name", "ilvl", "count", "sell" }

local function GetColumns()
    return BP().bagListColumns or DEFAULT_COLUMNS
end

-- Always writes a fresh copy so DEFAULT_COLUMNS is never mutated.
local function SetColumns(entries)
    BP().bagListColumns = CopyTable(entries)
end

-- List font: resolved once per layout pass, applied only when it changed
local _lfPath, _lfSize, _lfFlag
local function ResolveListFont()
    _lfPath = CUI.GetFontPath("bags")
    _lfSize = BP().bagListFontSize or 11
    _lfFlag = CUI.GetFontOutlineFlag("bags")
end
local function SetListFont(fontStr, size)
    if not _lfPath then
        ResolveListFont()
    end
    size = size or _lfSize
    if fontStr._lfPath == _lfPath and fontStr._lfSize == size and fontStr._lfFlag == _lfFlag then
        return
    end
    fontStr._lfPath, fontStr._lfSize, fontStr._lfFlag = _lfPath, size, _lfFlag
    CUI.PrimeFontShadow(fontStr, true)
    fontStr:SetFont(_lfPath, size, _lfFlag)
end

-- Repaints both list views; the bank only while it shows its List View.
local function Refresh()
    if CUI_Bags and CUI_Bags.RefreshInventory then
        CUI_Bags:RefreshInventory()
    end
    local bank = _G.CUI_BankFrame
    if bank and bank.RefreshBank and bank.IsListMode and bank.IsListMode() then
        bank:RefreshBank()
    end
end

-------------------------------------------------------------------------------
--  Subtype splitting: classID -> profile toggle
-------------------------------------------------------------------------------
local IC = Enum.ItemClass
local SPLIT_KEY = {
    [IC.Armor] = "bagListSplitArmor",
    [IC.Weapon] = "bagListSplitWeapons",
    [IC.Tradegoods] = "bagListSplitProfessions",
    [IC.Reagent] = "bagListSplitProfessions",
    [IC.Recipe] = "bagListSplitProfessions",
    [19] = "bagListSplitProfessions", -- Enum.ItemClass.Profession (Midnight)
}

-------------------------------------------------------------------------------
--  Bind column: Enum.ItemBind -> short label. Bound BoE / BoU / WuE items
--  read as SB (Soulbound); account binds keep their label.
-------------------------------------------------------------------------------
local IB = Enum.ItemBind
local BIND_ABBR = {
    [IB.OnAcquire] = "BoP",
    [IB.OnEquip] = "BoE",
    [IB.OnUse] = "BoU",
    [IB.Quest] = "Quest",
    [IB.ToWoWAccount] = "BoA",
    [IB.ToBnetAccount] = "WB", -- Warbound
    [IB.ToBnetAccountUntilEquipped] = "WuE",
}
local BIND_SOULBOUND = {
    [IB.OnEquip] = true,
    [IB.OnUse] = true,
    [IB.ToBnetAccountUntilEquipped] = true,
}
-- Warbound until Equipped reads as OnEquip from GetItemInfo; the item's bag
-- location tells them apart (one reused location, no per-row allocation).
local _bindLoc = ItemLocation:CreateEmpty()

-------------------------------------------------------------------------------
--  Per-item values (stamped on the pooled slot tables, wiped on reuse)
-------------------------------------------------------------------------------
local function StampItem(skinData)
    local details = skinData.info
    local count = skinData._mergedCount or details.stackCount or 1
    local _, _, _, baseIlvl, reqLevel, _, _, _, _, _, sellPrice, _, _, bindType = GetItemInfo(skinData.itemLink)
    local _, _, subType, _, _, classID = GetItemInfoInstant(skinData.itemLink)
    skinData._lvName = details.itemName or ""
    skinData._lvQuality = details.quality or 1
    skinData._lvIlvl = skinData._isGear and (tonumber(skinData._giIlvl) or baseIlvl) or 0
    skinData._lvReq = (reqLevel and reqLevel > 1) and reqLevel or 0
    skinData._lvType = subType or ""
    skinData._lvCount = count
    -- Track sort: tier (CUI._TRACK_RANK) then rank within it
    local rank, tc = skinData._giTrackRank or "", skinData._giTrackColor
    skinData._lvTrack = rank
    skinData._lvTrackSort = tc
            and ((CUI._TRACK_RANK and CUI._TRACK_RANK[tc] or 0) * 100 + (tonumber(rank:match("^(%d+)")) or 0))
        or 0
    skinData._lvSell = (not details.hasNoValue and sellPrice) and sellPrice * count or 0
    if bindType == IB.OnEquip and not details.isBound and skinData.bag and skinData.slot then
        _bindLoc:SetBagAndSlot(skinData.bag, skinData.slot)
        if C_Item.IsBoundToAccountUntilEquip(_bindLoc) then
            bindType = IB.ToBnetAccountUntilEquipped
        end
    end
    if details.isBound and BIND_SOULBOUND[bindType] then
        skinData._lvBind = L("SB")
    else
        skinData._lvBind = bindType and BIND_ABBR[bindType] and L(BIND_ABBR[bindType]) or ""
    end
    local key = classID and SPLIT_KEY[classID]
    skinData._lvSub = (key and BP()[key] and subType) or ""
end
mod.StampListItem = StampItem

-- Static comparator (no per-refresh closures); _sk/_sa set before each sort.
local _sk, _sa = "_lvQuality", false
local function ListCompare(a, b)
    local va, vb = a[_sk], b[_sk]
    if va ~= vb then
        if _sa then
            return va < vb
        end
        return va > vb
    end
    if a._lvName ~= b._lvName then
        return a._lvName < b._lvName
    end
    if a.bag ~= b.bag then
        return a.bag < b.bag
    end
    return a.slot < b.slot
end
mod.ListCompare = ListCompare

-- OneBag / MultiBag: real bag/slot order
local function SlotCompare(a, b)
    if a.bag ~= b.bag then
        return a.bag < b.bag
    end
    return a.slot < b.slot
end

local function SubCompare(a, b)
    -- Unsplit items ("") first, then equip slots in slot order (Group Gear by
    -- Slot), then subtypes alphabetically
    if a.label == "" then
        return b.label ~= ""
    end
    if b.label == "" then
        return false
    end
    if a.order or b.order then
        if not (a.order and b.order) then
            return a.order ~= nil
        end
        if a.order ~= b.order then
            return a.order < b.order
        end
    end
    return a.label < b.label
end

-------------------------------------------------------------------------------
--  Frame pools
-------------------------------------------------------------------------------
local _rows, _sections, _hdrBars = {}, {}, {}
local _rowsUsed, _sectionsUsed = 0, 0

local function SkinRow(button)
    -- Methods only on template sub-objects (property writes taint)
    if button.NewItemTexture then
        button.NewItemTexture:Hide()
        button.NewItemTexture:SetAlpha(0)
    end
    if button.BattlepayItemTexture then
        button.BattlepayItemTexture:Hide()
        button.BattlepayItemTexture:SetAlpha(0)
    end
    if button.flash then
        button.flash:Hide()
        button.flash:SetAlpha(0)
    end
    if button.newitemglowAnim then
        button.newitemglowAnim:Stop()
    end
    if button.NormalTexture then
        button.NormalTexture:SetAlpha(0)
    end
    if button.IconBorder then
        button.IconBorder:SetAlpha(0)
    end
    if button.icon then
        button.icon:SetAlpha(0)
    end
    if button.Count then
        button.Count:SetAlpha(0)
    end
    local ht = button:GetHighlightTexture()
    if ht then
        ht:SetTexture(nil)
        ht:SetColorTexture(1, 1, 1, 0.08)
        ht:ClearAllPoints()
        ht:SetAllPoints(button)
    end
    local pt = button:GetPushedTexture()
    if pt then
        pt:SetAtlas(nil)
        pt:SetTexture(nil)
        pt:SetColorTexture(1, 1, 1, 0.04)
        pt:ClearAllPoints()
        pt:SetAllPoints(button)
    end
end

-- Bare secure container row (no click hooks) parented under host. Returns
-- nil in combat (a secure button born in lockdown is tainted); callers skip
-- the row and fill it after combat.
local _hostRows = {} -- host -> rows created under it (live column reflow)
function mod.CreateListRow(owner)
    if InCombatLockdown() then
        return nil
    end
    local slotParent = CreateFrame("Frame", nil, owner)
    local button = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    mod.PinItemButton(button, owner)
    button:SetAllPoints(slotParent)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    SkinRow(button)

    button._stripe = button:CreateTexture(nil, "BACKGROUND")
    button._stripe:SetAllPoints()
    button._stripe:SetColorTexture(1, 1, 1, 0.03)

    button._lvIcon = button:CreateTexture(nil, "ARTWORK")
    button._lvIcon:SetSize(ICON_SIZE, ICON_SIZE)
    if button.Cooldown then
        button.Cooldown:ClearAllPoints()
        button.Cooldown:SetAllPoints(button._lvIcon)
        button.Cooldown:SetHideCountdownNumbers(true)
    end
    -- Third-party overlay painters (CUI_Bags.RunItemOverlays) parent to this,
    -- as on the grid slots: here it covers the row's icon.
    local shade = CreateFrame("Frame", nil, button)
    shade:SetAllPoints(button._lvIcon)
    shade:SetFrameLevel(button:GetFrameLevel() + 3)
    button._textOverlay = shade
    button._cells = {}
    local entries = _hostRows[owner]
    if not entries then
        entries = {}
        _hostRows[owner] = entries
    end
    entries[#entries + 1] = button
    return button
end

-- Secure container button, one per row. NEVER created in combat (a button
-- born in lockdown is tainted); RefreshInventory flags the combat refresh
-- and PLAYER_REGEN_ENABLED replays it, which fills the gap.
local function GetOrCreateRow(position)
    if _rows[position] then
        return _rows[position]
    end
    if InCombatLockdown() then
        CUI_Bags._poolShort = true
        return nil
    end
    local button = mod.CreateListRow(CUI_Bags)
    button:HookScript("OnMouseUp", mod.SlotMiddleClick)
    button:HookScript("PreClick", mod.BankRoutePreClick)
    button:HookScript("OnClick", mod.BankRouteOnClick)
    button:HookScript("PostClick", function(self)
        CUI_Bags.ShowStackSplitter(self, mod.SplitTargetBags(self:GetParent():GetID()), CUI_Bags)
    end)
    _rows[position] = button
    return button
end

-- Pre-build rows out of combat so a first open mid-fight has them.
-- Returns false when combat stopped it (GetOrCreateRow flags _poolShort) or
-- the optional time budget (msBudget ms from t0) ran out.
function mod.WarmListRows(sum, t0, msBudget)
    for i = 1, sum do
        if not _rows[i] then
            local b = GetOrCreateRow(i)
            if not b then
                return false
            end
            b:GetParent():Hide()
            if t0 and debugprofilestop() - t0 > msBudget then
                CUI_Bags._poolShort = true
                return false
            end
        end
    end
    return true
end

local function GetCell(button, ident)
    local fontStr = button._cells[ident]
    if not fontStr then
        fontStr = button:CreateFontString(nil, "OVERLAY")
        fontStr:SetWordWrap(false)
        fontStr:SetJustifyH(COLUMNS[ident].justify or "LEFT")
        button._cells[ident] = fontStr
    end
    SetListFont(fontStr)
    return fontStr
end

local function SetRoundIcon(button, round)
    if (button._lvRound or false) == round then
        return
    end
    button._lvRound = round
    local slotMask = button._textOverlay._fvIconMask
    if round then
        if slotMask then
            button._lvIcon:RemoveMaskTexture(slotMask)
        end
        if not button._lvMask then
            button._lvMask = button:CreateMaskTexture()
            button._lvMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            button._lvMask:SetAllPoints(button._lvIcon)
        end
        button._lvIcon:AddMaskTexture(button._lvMask)
        if button.Cooldown then
            button.Cooldown:SetSwipeTexture(ROUND_MASK)
        end
    else
        button._lvIcon:RemoveMaskTexture(button._lvMask)
        if slotMask then
            button._lvIcon:AddMaskTexture(slotMask)
        end
        if button.Cooldown then
            button.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
        end
    end
end

-- Collapsed sections, keyed by category _defaultName, "junk", or
-- "<section key>/<subtype>" for sub-sections. Saved in the profile.
-- Shift-click on a top-level section collapses or expands all of them.
-- A virtual category's ("Virtual:...") state lasts the session: nothing of it is saved.
local _virtualCollapsed = {}
local function IsCollapsed(key)
    return _virtualCollapsed[key] or (BP().bagListCollapsed or _emptyP)[key] == true
end
local function SetCollapsed(set, key, val)
    if key:find("^Virtual:") then
        _virtualCollapsed[key] = val
    else
        set[key] = val
    end
end
local function ToggleCollapsed(self)
    local p = BP()
    local set = p.bagListCollapsed
    if not set then
        set = {}
        p.bagListCollapsed = set
    end
    if IsShiftKeyDown() and not self._sub then
        local collapse = not IsCollapsed(self._key) or nil
        for i = 1, _sectionsUsed do
            local s = _sections[i]
            if not s._sub then
                SetCollapsed(set, s._key, collapse)
            end
        end
    else
        SetCollapsed(set, self._key, not IsCollapsed(self._key) or nil)
    end
    Refresh()
end

local function GetOrCreateSection(position)
    if _sections[position] then
        return _sections[position]
    end
    local frame = CreateFrame("Button", nil, CUI_Bags)
    frame._arrow = frame:CreateTexture(nil, "OVERLAY")
    frame._arrow:SetSize(8, 8)
    frame._arrow:SetTexture(ARROW_TEX)
    frame._arrow:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame._label = frame:CreateFontString(nil, "OVERLAY")
    frame._label:SetPoint("LEFT", frame._arrow, "RIGHT", 4, 0)
    frame._label:SetJustifyH("LEFT")
    frame._count = frame:CreateFontString(nil, "OVERLAY")
    frame._count:SetPoint("LEFT", frame._label, "RIGHT", 4, 0)
    frame._count:SetTextColor(0.7, 0.7, 0.7, 0.9)
    frame._line = frame:CreateTexture(nil, "ARTWORK")
    frame._line:SetHeight(CUI.PP.mult)
    frame._line:SetPoint("LEFT", frame._count, "RIGHT", 6, 0)
    frame._line:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    frame._line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
    frame:SetScript("OnClick", ToggleCollapsed)
    frame:SetScript("OnEnter", function(self)
        self._label:SetAlpha(1)
        self._arrow:SetAlpha(1)
    end)
    frame:SetScript("OnLeave", function(self)
        self._label:SetAlpha(0.8)
        self._arrow:SetAlpha(0.6)
    end)
    frame._label:SetAlpha(0.8)
    frame._arrow:SetAlpha(0.6)
    _sections[position] = frame
    return frame
end

-------------------------------------------------------------------------------
--  Column layout: x offset + width per visible column
-------------------------------------------------------------------------------
-- Fixed column width: the header-resized width, else the default.
-- The icon column never resizes.
local MIN_COL_W, MIN_FLEX_W = 20, 60
local function FixedWidth(ident)
    local def = COLUMNS[ident]
    if not def.width then
        return nil
    end
    if ident == "icon" then
        return def.width
    end
    local saved = BP().bagListColWidths
    return (saved and saved[ident]) or def.width
end

local _colX, _colW = {}, {}
local _lastRowW
local function LayoutColumns(rowW)
    _lastRowW = rowW
    ResolveListFont()
    local cols = GetColumns()
    local fixed = 0
    for _, ident in ipairs(cols) do
        fixed = fixed + (FixedWidth(ident) or 0)
    end
    local flexW = math.max(MIN_FLEX_W, rowW - fixed - COL_GAP * (#cols + 1))
    local posX = COL_GAP
    for _, ident in ipairs(cols) do
        local wid = FixedWidth(ident) or flexW
        _colX[ident], _colW[ident] = posX, wid
        posX = posX + wid + COL_GAP
    end
    return cols
end
mod.ListLayoutColumns = LayoutColumns

-------------------------------------------------------------------------------
--  Column header bar: click sorts, drag reorders, right-click edits columns
-------------------------------------------------------------------------------
local function MoveColumn(ident, toIdx)
    local cols = {}
    for _, c in ipairs(GetColumns()) do
        if c ~= ident then
            cols[#cols + 1] = c
        end
    end
    toIdx = math.max(1, math.min(toIdx, #cols + 1))
    table.insert(cols, toIdx, ident)
    SetColumns(cols)
    Refresh()
end

local IndexOf = tIndexOf

local function ToggleColumn(ident)
    local cols = GetColumns()
    local at = IndexOf(cols, ident)
    local result = {}
    for _, c in ipairs(cols) do
        result[#result + 1] = c
    end
    if at then
        if #result == 1 then
            return
        end -- keep at least one column
        table.remove(result, at)
    else
        -- Re-add in its default position relative to the shown columns
        local rank = IndexOf(COLUMN_ORDER, ident)
        local insertAt = #result + 1
        for i, c in ipairs(result) do
            if IndexOf(COLUMN_ORDER, c) > rank then
                insertAt = i
                break
            end
        end
        table.insert(result, insertAt, ident)
    end
    SetColumns(result)
    Refresh()
end

-- True while a column is shown or still sorts the list (its data is needed)
function mod.ListUsesColumn(ident)
    return IndexOf(GetColumns(), ident) ~= nil or BP().bagListSortKey == ident
end

local function ShowColumnMenu(ownerFrame, ident)
    MenuUtil.CreateContextMenu(ownerFrame, function(_, root)
        root:CreateTitle(L("Columns"))
        for _, cid in ipairs(COLUMN_ORDER) do
            -- WoW Forever has no upgrade tracks: Track is offered there only
            -- to switch off a column an imported profile brought in
            if cid ~= "track" or not CUI.IS_FOREVER or IndexOf(GetColumns(), cid) then
                local def = COLUMNS[cid]
                root:CreateCheckbox(L(def.menuLabel or def.label), function()
                    return IndexOf(GetColumns(), cid) ~= nil
                end, function()
                    ToggleColumn(cid)
                end)
            end
        end
        root:CreateDivider()
        local at = IndexOf(GetColumns(), ident)
        if at and at > 1 then
            root:CreateButton(L("Move Left"), function()
                MoveColumn(ident, at - 1)
            end)
        end
        if at and at < #GetColumns() then
            root:CreateButton(L("Move Right"), function()
                MoveColumn(ident, at + 1)
            end)
        end
        root:CreateCheckbox(L("Round Icons"), function()
            return BP().bagListRoundIcons == true
        end, function()
            BP().bagListRoundIcons = not BP().bagListRoundIcons
            Refresh()
        end)
        root:CreateButton(L("Reset Columns"), function()
            BP().bagListColumns = nil
            BP().bagListSortKey = nil
            BP().bagListColWidths = nil
            Refresh()
        end)
    end)
end

-- Live column drag: once past 6px, the column moves as the cursor crosses
-- a neighbour's centre (centres of the other columns, so a wide neighbour
-- cannot bounce it back and forth). OnUpdate only while the button is held.
local function OnHeaderDragUpdate(self)
    if not IsMouseButtonDown("LeftButton") then
        self:SetScript("OnUpdate", nil)
        return
    end
    local cx = GetCursorPosition()
    if not self._dragged then
        if math.abs(cx - self._downX) <= 6 then
            return
        end
        self._dragged = true
    end
    cx = cx / self:GetEffectiveScale()
    local cols, btns = GetColumns(), self:GetParent()._btns
    local target = 1
    for _, cid in ipairs(cols) do
        local b = btns[cid]
        if cid ~= self._colId and b then
            local l, region = b:GetLeft(), b:GetRight()
            if l and cx > (l + region) / 2 then
                target = target + 1
            end
        end
    end
    if target ~= IndexOf(cols, self._colId) then
        MoveColumn(self._colId, target)
    end
end

local function OnHeaderMouseDown(self, btnFrame)
    if btnFrame ~= "LeftButton" then
        return
    end
    self._downX = GetCursorPosition()
    self._dragged = nil
    self:SetScript("OnUpdate", OnHeaderDragUpdate)
end

local function OnHeaderMouseUp(self, btnFrame)
    if btnFrame == "RightButton" then
        ShowColumnMenu(self, self._colId)
        return
    end
    if btnFrame ~= "LeftButton" or not self._downX then
        return
    end
    self:SetScript("OnUpdate", nil)
    self._downX = nil
    -- A drag already moved the column live
    if self._dragged then
        self._dragged = nil
        return
    end
    local def = COLUMNS[self._colId]
    if not def.field then
        return
    end
    local p = BP()
    if p.bagListSortKey == self._colId then
        p.bagListSortAsc = not p.bagListSortAsc
    else
        p.bagListSortKey = self._colId
        p.bagListSortAsc = not def.desc
    end
    Refresh()
end

-- Live column reflow: re-place the header buttons and the visible rows'
-- cells from the current widths, without a bag rescan.
local function ReflowHost(owner)
    local barFrame = _hdrBars[owner]
    if not barFrame or not barFrame:IsShown() or not barFrame._rowW then
        return
    end
    local cols = LayoutColumns(barFrame._rowW)
    mod.UpdateListHeaderBar(owner, cols, barFrame._leftX, barFrame._topY, barFrame._startX, barFrame._noSort)
    for _, button in ipairs(_hostRows[owner] or _emptyP) do
        if button:IsVisible() then
            if button._lvIcon:IsShown() and _colX.icon then
                button._lvIcon:ClearAllPoints()
                button._lvIcon:SetPoint("LEFT", button, "LEFT", _colX.icon, 0)
            end
            for ident, fontStr in pairs(button._cells) do
                if fontStr:IsShown() and IndexOf(cols, ident) then
                    fontStr:ClearAllPoints()
                    fontStr:SetPoint("LEFT", button, "LEFT", _colX[ident], 0)
                    fontStr:SetWidth(_colW[ident])
                end
            end
        end
    end
end

-- Column resize: a grip on the header edge facing the flexible (Name)
-- column; the flexible column gives or takes the width. OnUpdate only while
-- the grip is held; a full refresh runs once on release.
local function SizerStop(self)
    if not self._startW then
        return
    end
    self:SetScript("OnUpdate", nil)
    self._startW = nil
    Refresh()
end

local function SizerOnUpdate(self)
    if not IsMouseButtonDown("LeftButton") then
        SizerStop(self)
        return
    end
    local heading = self:GetParent()
    local cx = GetCursorPosition() / heading:GetEffectiveScale()
    local wid = math.floor(self._startW + self._sign * (cx - self._startCX) + 0.5)
    wid = math.max(MIN_COL_W, math.min(self._maxW, wid))
    if wid == self._lastW then
        return
    end
    self._lastW = wid
    local p = BP()
    local t = p.bagListColWidths
    if not t then
        t = {}
        p.bagListColWidths = t
    end
    t[heading._colId] = wid
    for owner in pairs(_hdrBars) do
        ReflowHost(owner)
    end
end

local function SizerOnMouseDown(self, btnFrame)
    if btnFrame ~= "LeftButton" then
        return
    end
    local heading = self:GetParent()
    local barFrame = heading:GetParent()
    if not barFrame._rowW then
        return
    end
    LayoutColumns(barFrame._rowW)
    -- Width the flexible column can give up (no flexible column: capped growth)
    local slack = 200
    for _, cid in ipairs(GetColumns()) do
        if not COLUMNS[cid].width then
            slack = _colW[cid] - MIN_FLEX_W
        end
    end
    self._startW = FixedWidth(heading._colId)
    self._lastW = self._startW
    self._maxW = self._startW + math.max(0, slack)
    self._startCX = GetCursorPosition() / heading:GetEffectiveScale()
    self:SetScript("OnUpdate", SizerOnUpdate)
end

local function GetOrCreateHeaderBtn(barFrame, ident)
    if barFrame._btns[ident] then
        return barFrame._btns[ident]
    end
    local b = CreateFrame("Button", nil, barFrame)
    b:SetHeight(COLHDR_H)
    b._colId = ident
    b._label = b:CreateFontString(nil, "OVERLAY")
    SetListFont(b._label, 10)
    b._label:SetAllPoints()
    b._label:SetJustifyH(COLUMNS[ident].justify or "LEFT")
    b._label:SetText(COLUMNS[ident].label ~= "" and L(COLUMNS[ident].label) or "")
    b._label:SetTextColor(0.6, 0.6, 0.6)
    b._arrow = b:CreateTexture(nil, "OVERLAY")
    b._arrow:SetSize(8, 8)
    b._arrow:SetTexture(ARROW_TEX)
    if ident == "icon" then
        -- The icon column has no label: a bag glyph over the row icons,
        -- tinted like the labels.
        b._glyph = b:CreateTexture(nil, "OVERLAY")
        b._glyph:SetSize(12, 12)
        b._glyph:SetPoint("CENTER")
        b._glyph:SetTexture(BAG_GLYPH_TEX)
        b._glyph:SetVertexColor(0.6, 0.6, 0.6)
    end
    b:SetScript("OnMouseDown", OnHeaderMouseDown)
    b:SetScript("OnMouseUp", OnHeaderMouseUp)
    if COLUMNS[ident].width and ident ~= "icon" then
        local g = CreateFrame("Button", nil, b)
        g:SetSize(COL_GAP, COLHDR_H)
        local line = g:CreateTexture(nil, "HIGHLIGHT")
        line:SetWidth(CUI.PP.mult)
        line:SetPoint("TOP")
        line:SetPoint("BOTTOM")
        line:SetColorTexture(1, 1, 1, 0.6)
        g:SetScript("OnMouseDown", SizerOnMouseDown)
        g:SetScript("OnMouseUp", SizerStop)
        g:SetScript("OnHide", SizerStop)
        b._sizer = g
    end
    b:SetScript("OnEnter", function(self)
        self._label:SetTextColor(1, 1, 1)
        if self._glyph then
            self._glyph:SetVertexColor(1, 1, 1)
        end
        CUI.ShowWidgetTooltip(
            self,
            COLUMNS[self._colId].field
                    and L("Click to sort. Drag to reorder. Right-click to add or remove columns.")
                or L("Drag to reorder. Right-click to add or remove columns.")
        )
    end)
    b:SetScript("OnLeave", function(self)
        self._label:SetTextColor(0.6, 0.6, 0.6)
        if self._glyph then
            self._glyph:SetVertexColor(0.6, 0.6, 0.6)
        end
        CUI.HideWidgetTooltip()
    end)
    barFrame._btns[ident] = b
    return b
end

-- the column bar for a window, nil before its first list refresh
function mod.ListHeaderBar(owner)
    return _hdrBars[owner]
end

-- One column header bar per host frame (bags, bank). Returns its height.
function mod.UpdateListHeaderBar(owner, cols, leftX, topY, startX, noSort)
    local barFrame = _hdrBars[owner]
    if not barFrame then
        barFrame = CreateFrame("Frame", nil, owner)
        barFrame:SetHeight(COLHDR_H)
        barFrame._btns = {}
        local line = barFrame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(CUI.PP.mult)
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
        _hdrBars[owner] = barFrame
    end
    -- Kept for live reflow while a column is resized
    barFrame._rowW, barFrame._leftX, barFrame._topY, barFrame._startX, barFrame._noSort = _lastRowW, leftX, topY, startX, noSort
    local flexIdx
    for i, ident in ipairs(cols) do
        if not COLUMNS[ident].width then
            flexIdx = i
        end
    end
    barFrame:ClearAllPoints()
    barFrame:SetPoint("TOPLEFT", owner, "TOPLEFT", leftX, topY)
    barFrame:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, topY)
    barFrame:Show()
    -- Hide only dropped columns: hiding the held button would end its drag
    for ident, b in pairs(barFrame._btns) do
        if not IndexOf(cols, ident) then
            b:Hide()
        end
    end
    local sortKey = not noSort and BP().bagListSortKey
    for i, ident in ipairs(cols) do
        local b = GetOrCreateHeaderBtn(barFrame, ident)
        SetListFont(b._label, 10)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", barFrame, "TOPLEFT", startX + _colX[ident], 0)
        b:SetWidth(math.max(_colW[ident], 12))
        if b._sizer then
            -- Grip sits in the gap on the side facing the flexible column
            local g = b._sizer
            g:ClearAllPoints()
            if flexIdx and i > flexIdx then
                g._sign = -1
                g:SetPoint("RIGHT", b, "LEFT", 0, 0)
            else
                g._sign = 1
                g:SetPoint("LEFT", b, "RIGHT", 0, 0)
            end
        end
        b._arrow:ClearAllPoints()
        if ident == sortKey and COLUMNS[ident].field then
            -- Arrow sits beside the label, on the side away from the text
            if COLUMNS[ident].justify == "RIGHT" then
                b._arrow:SetPoint("RIGHT", b, "RIGHT", -(b._label:GetStringWidth() + 3), 0)
            else
                b._arrow:SetPoint("LEFT", b._label, "LEFT", b._label:GetStringWidth() + 3, 0)
            end
            b._arrow:SetRotation(BP().bagListSortAsc and -math.pi / 2 or math.pi / 2)
            b._arrow:Show()
        else
            b._arrow:Hide()
        end
        b:Show()
    end
    return COLHDR_H
end

-- Sets the ListCompare sort field from the saved header sort.
function mod.ListSortSetup()
    local sortDef = BP().bagListSortKey and COLUMNS[BP().bagListSortKey]
    if sortDef and sortDef.field then
        _sk, _sa = sortDef.field, BP().bagListSortAsc == true
    else
        _sk, _sa = "_lvQuality", false
    end
end

-------------------------------------------------------------------------------
--  Render
-------------------------------------------------------------------------------
-- dim: a pinned item in a OneBag / MultiBag bag section while Dim Items in
-- OneBag/MultiBag is on (the grid's search-miss alpha).
local function RenderRow(button, payload, cols, rowW, posX, posY, stripe, dim)
    -- Bags and bank share the column tables at their own row widths: a bank
    -- batch painted after a bags refresh re-lays them out for its width.
    if rowW ~= _lastRowW then
        LayoutColumns(rowW)
    end
    local hostFrame = button:GetParent()
    hostFrame:ClearAllPoints()
    hostFrame:SetSize(rowW, RowH())
    hostFrame:SetPoint("TOPLEFT", posX, posY)
    hostFrame:SetID(payload.bag)
    button:SetID(payload.slot)
    hostFrame:Show()
    button:Show()
    button:SetAlpha(dim and 0.2 or 1)
    button._stripe:SetShown(stripe and BP().bagListHideStripes ~= true)

    local details = payload.info
    local q = details.quality or 1
    for _, fontStr in pairs(button._cells) do
        fontStr:Hide()
    end
    button._lvIcon:Hide()
    for _, ident in ipairs(cols) do
        local cx, cw = _colX[ident], _colW[ident]
        if ident == "icon" then
            local iconTex = button._lvIcon
            local isz = math.min(ICON_SIZE, RowH() - 4)
            iconTex:SetSize(isz, isz)
            iconTex:ClearAllPoints()
            iconTex:SetPoint("LEFT", button, "LEFT", cx, 0)
            iconTex:SetTexture(details.iconFileID)
            local round = BP().bagListRoundIcons == true
            SetRoundIcon(button, round)
            -- Round: fixed crop past the icon's baked-in border so the circle edge stays clean
            local z = round and ROUND_ZOOM or (BP().bagItemIconZoom or 0.08)
            iconTex:SetTexCoord(z, 1 - z, z, 1 - z)
            -- Junk Item Visuals' Desaturate greys grey items and Junk Marker junk
            iconTex:SetDesaturated(
                details.isLocked
                    or (BP().bagDesaturateJunkItems == true and (q == 0 or CUI_CategoryManager:IsJunk(
                        details.itemID,
                        q
                    )))
                    or false
            )
            if CUI._BagsItemUnusable(payload.bag, payload.slot, payload.itemLink, details.itemID) then
                iconTex:SetVertexColor(1, 0.1, 0.1)
            else
                iconTex:SetVertexColor(1, 1, 1)
            end
            iconTex:Show()
            -- Quality Item Border: square icons only
            local shade = button._textOverlay
            if not round and (BP().bagQualityBorder ~= false or mod.BagsForever()) then
                if not (shade._brdT or shade._fvSlotBorder) then
                    mod.CreateInsetBorder(shade, true, iconTex)
                end
                local red, green, blue = mod.QualityBorderColor(q)
                mod.SetInsetBorderColor(shade, red, green, blue, 1)
                if shade._fvSlotBorder then
                    mod.SetForeverSlotQuestBorder(shade, payload._isQuest, payload._isQuestStarter)
                end
            elseif shade._brdT or shade._fvSlotBorder then
                mod.SetInsetBorderColor(shade, 0, 0, 0, 0)
                if shade._fvQuestBorder then
                    shade._fvQuestBorder:Hide()
                end
            end
        else
            local fontStr = GetCell(button, ident)
            fontStr:ClearAllPoints()
            fontStr:SetPoint("LEFT", button, "LEFT", cx, 0)
            fontStr:SetWidth(cw)
            local textValue
            if ident == "name" then
                textValue = payload._lvName
                local c = ITEM_QUALITY_COLORS[q]
                if c then
                    fontStr:SetTextColor(c.r, c.g, c.b)
                else
                    fontStr:SetTextColor(1, 1, 1)
                end
            else
                fontStr:SetTextColor(0.85, 0.85, 0.85)
                if ident == "ilvl" then
                    textValue = payload._lvIlvl > 0 and payload._lvIlvl or ""
                elseif ident == "reqlvl" then
                    textValue = payload._lvReq > 0 and payload._lvReq or ""
                elseif ident == "type" then
                    textValue = payload._lvType
                elseif ident == "bind" then
                    textValue = payload._lvBind
                elseif ident == "track" then
                    textValue = payload._lvTrack
                    local tc = payload._giTrackColor
                    if tc then
                        fontStr:SetTextColor(tc.r, tc.g, tc.b)
                    end
                elseif ident == "count" then
                    textValue = payload._lvCount > 1 and payload._lvCount or ""
                elseif ident == "sell" then
                    textValue = payload._lvSell > 0 and C_CurrencyInfo.GetCoinTextureString(payload._lvSell)
                        or ""
                end
            end
            fontStr:SetText(textValue)
            fontStr:Show()
        end
    end

    if button.Cooldown then
        if payload._cdStart and IndexOf(cols, "icon") then
            button.Cooldown:SetCooldown(payload._cdStart, payload._cdDuration)
        else
            button.Cooldown:Clear()
        end
    end
    button._textOverlay:SetShown(button._lvIcon:IsShown())
    CUI_Bags.RunItemOverlays(button, payload)
    -- Tooltip requery after the slot re-assignment (see RenderButton)
    if GameTooltip:IsOwned(button) and button.UpdateTooltip then
        button:UpdateTooltip()
    end
end
mod.RenderListRow = RenderRow

-- Mark mode: the row pool it hit-tests, and the one row it toggled
mod.ListRows = _rows
function mod.ListPaintJunk(button, details)
    local q = details.quality or 1
    button._lvIcon:SetDesaturated(
        details.isLocked
            or (BP().bagDesaturateJunkItems == true and (q == 0 or CUI_CategoryManager:IsJunk(
                details.itemID,
                q
            )))
            or false
    )
end

-- Re-pins each host's rows (the bags and the bank) after its level moved (ns.PinItemPool)
function mod.ResyncListRowLevels()
    for owner, rowList in pairs(_hostRows) do
        mod.PinItemPool(rowList, owner, "_rowPinLevel")
    end
end

-- Empty bag slot row (OneBag / MultiBag); clicking or dropping an item
-- places it in that slot.
local function RenderEmptyRow(button, cols, skinData, rowW, posX, posY, stripe)
    if rowW ~= _lastRowW then
        LayoutColumns(rowW)
    end
    local hostFrame = button:GetParent()
    hostFrame:ClearAllPoints()
    hostFrame:SetSize(rowW, RowH())
    hostFrame:SetPoint("TOPLEFT", posX, posY)
    hostFrame:SetID(skinData.bag)
    button:SetID(skinData.slot)
    hostFrame:Show()
    button:Show()
    button:SetAlpha(1)
    button._stripe:SetShown(stripe and BP().bagListHideStripes ~= true)
    button._lvIcon:Hide()
    for _, fontStr in pairs(button._cells) do
        fontStr:Hide()
    end
    if button.Cooldown then
        button.Cooldown:Clear()
    end
    local hasName = IndexOf(cols, "name")
    local fontStr = GetCell(button, "name")
    fontStr:ClearAllPoints()
    fontStr:SetPoint("LEFT", button, "LEFT", hasName and _colX.name or COL_GAP, 0)
    fontStr:SetWidth(hasName and _colW.name or (rowW - COL_GAP * 2))
    fontStr:SetTextColor(0.4, 0.4, 0.4)
    fontStr:SetText(L("Empty"))
    fontStr:Show()
    -- No item: painters clear what they drew on this reused row
    button._textOverlay:Hide()
    CUI_Bags.RunItemOverlays(button, skinData)
    if GameTooltip:IsOwned(button) and button.UpdateTooltip then
        button:UpdateTooltip()
    end
end
mod.ListRowH = RowH

-- Returns the header height and whether the section is collapsed.
local function PlaceSection(key, labelText, count, posX, posY, wid, sub)
    _sectionsUsed = _sectionsUsed + 1
    local s = GetOrCreateSection(_sectionsUsed)
    s:SetParent(CUI_Bags._scrollChild)
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", posX + (sub and 12 or 0), posY)
    s:SetSize(wid - (sub and 12 or 0), sub and SUBSECTION_H or SECTION_H)
    -- Category Title Size (11 by default: 11 / 10)
    local size = mod.GetCatTitleSize()
    local small = math.max(8, size - 1)
    SetListFont(s._label, sub and small or size)
    SetListFont(s._count, small)
    s._label:SetTextColor(sub and 0.55 or 0.7, sub and 0.55 or 0.7, sub and 0.55 or 0.7)
    s._label:SetText(labelText)
    s._count:SetText(count)
    s._key, s._sub = key, sub
    local collapsed = IsCollapsed(key) and true or false
    -- Arrow points right when collapsed, down when open
    s._arrow:SetRotation(collapsed and math.pi or math.pi / 2)
    if s._clearBtn then
        s._clearBtn:Hide()
        s._line:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    end
    s:Show()
    return sub and SUBSECTION_H or SECTION_H, collapsed
end

-- items: the already-filtered display list. Returns the content height.
-- opts: rowW, startX, leftX (scroll frame left), topY (header bar top),
-- allItems (All Items view: honour Hide in All Items), pinned (pinned set:
-- duplicate pinned items into a Pinned section at the top), slotView ("one" =
-- OneBag, "multi" = MultiBag: bag sections in slot order like the grid),
-- recent (recent itemID set: Recent section in slot views), recentOnly (the
-- Recent Items tab: every item in that one section, newest first), emptySlots
-- (slot views: empty slots as rows; nil while searching).
function mod.RenderListView(itemList, options)
    local childFrame = CUI_Bags._scrollChild
    local cats = CUI_CategoryManager:GetCategories()
    local hidden = options.allItems and BP().bagHiddenInAllItems or _emptyP
    local rowW = options.rowW

    -- Bucket: section key (category index, "pinned" or "junk") -> sub label -> items.
    -- Slot views key sections by bag ID (0-5), or "main" for OneBag's bags 0-4.
    local slotView = options.slotView
    -- One Junk section: the Junk category (under its own name) while the Junk
    -- Marker is on, else every grey item
    local junkOn = CUI_CategoryManager:IsJunkMarkerEnabled()
    local junkLabel = L("Junk")
    if junkOn then
        for _, c in ipairs(cats) do
            if c.isJunk then
                junkLabel = c.name
                break
            end
        end
    end
    local buckets, sequence = {}, {}
    local function GetBucket(key)
        local b = buckets[key]
        if not b then
            b = { key = key, subs = {}, subList = {}, n = 0, sell = 0 }
            buckets[key] = b
            sequence[#sequence + 1] = b
        end
        return b
    end
    -- subOrder: the sub-section's sort key (equip slots), nil sorts by label
    local function Add(key, sub, skinData, subOrder)
        local b = GetBucket(key)
        local sl = b.subs[sub]
        if not sl then
            sl = { label = sub, order = subOrder }
            b.subs[sub] = sl
            b.subList[#b.subList + 1] = sl
        end
        sl[#sl + 1] = skinData
        b.n = b.n + 1
        b.sell = b.sell + skinData._lvSell
    end
    -- OneBag: a WoW Forever special bag (ns.SpecialBags) keeps a section of
    -- its own, as the reagent bag does, after Main Bags.
    local special = slotView == "one" and mod.SpecialBags() or nil
    local function BagKey(bag)
        if slotView == "one" and bag ~= 5 and not (special and special[bag]) then
            return "main"
        end
        return bag
    end
    local pinnedSet, recentSet = options.pinned, options.recent
    if not slotView then
        itemList = mod.MergeDuplicates(itemList)
    end
    -- Group Gear by Slot: the gear categories' sub-sections are equip slots,
    -- in place of Split by Type
    local gearSlots = not slotView and mod.ArmorySlotGroupingEnabled()
    for _, skinData in ipairs(itemList) do
        local ci = skinData.categoryIndex
        local category = ci and cats[ci]
        if skinData.info and skinData.itemLink then
            StampItem(skinData)
            if pinnedSet and mod.IsItemPinned(pinnedSet, skinData.itemLink, skinData.info.itemID) then
                Add("pinned", "", skinData)
            end
            if recentSet and recentSet[skinData.info.itemID] and not skinData._pinnedOnly then
                Add("recent", "", skinData)
            end
            if options.recentOnly then
                Add("recent", "", skinData)
            elseif slotView then
                Add(BagKey(skinData.bag), "", skinData)
            elseif
                category
                and not (options.allItems and skinData._pinnedOnly)
                and not hidden[category._defaultName]
                and not (category.groupName and hidden[category.groupName])
            then
                local key = (junkOn and category.isJunk or (not junkOn and skinData._lvQuality == 0)) and "junk"
                    or ci
                if key == "junk" then
                    Add(key, "", skinData)
                elseif gearSlots and mod.IsArmoryGearCategory(category) then
                    local sk, labelText = mod.GetArmorySlotBucket(skinData)
                    Add(key, labelText, skinData, sk)
                else
                    Add(key, skinData._lvSub, skinData)
                end
            end
        end
    end
    if slotView and options.emptySlots then
        for _, skinData in ipairs(options.emptySlots) do
            local b = GetBucket(BagKey(skinData.bag))
            local sl = b.subs[""]
            if not sl then
                sl = { label = "" }
                b.subs[""] = sl
                b.subList[1] = sl
            end
            sl[#sl + 1] = skinData
        end
    end
    -- Pinned first, category (or bag) order, Junk after the last saved category
    -- (virtual categories follow it, as in the grid and the sidebar)
    local RANK = { pinned = -2, recent = -1, main = 0, junk = CUI_CategoryManager:GetSavedCount() + 0.5 }
    table.sort(sequence, function(lhs, rhs)
        return (RANK[lhs.key] or lhs.key) < (RANK[rhs.key] or rhs.key)
    end)
    local pinnedLabel, recentLabel = L("Pinned Items"), L("Recent Items")
    for _, c in ipairs(cats) do
        if c.isPinned then
            pinnedLabel = c.name
        end
        if c.isRecent then
            recentLabel = c.name
        end
    end

    mod.ListSortSetup()
    local rowCompare = slotView and SlotCompare or ListCompare
    local cols = LayoutColumns(rowW)
    mod.UpdateListHeaderBar(CUI_Bags, cols, options.leftX, options.topY, options.startX, slotView ~= nil)

    for _, s in ipairs(_sections) do
        s:Hide()
    end
    _sectionsUsed, _rowsUsed = 0, 0
    local posX, posY = options.startX, -4
    local showValue = BP().bagListSectionValue == true
    local rowH = RowH()

    for _, b in ipairs(sequence) do
        local labelText, secKey, count
        if b.key == "junk" then
            labelText, secKey = junkLabel, "junk"
        elseif b.key == "pinned" then
            labelText, secKey = pinnedLabel, "pinned"
        elseif b.key == "recent" then
            labelText, secKey = recentLabel, "recent"
        elseif b.key == "main" then
            local sum = 0
            for bag = 0, 4 do
                if not (special and special[bag]) then
                    sum = sum + C_Container.GetContainerNumSlots(bag)
                end
            end
            labelText, secKey = L("Main Bags"), "bagmain"
            count = "(" .. b.n .. " / " .. sum .. ")"
        elseif slotView then
            labelText, secKey = mod.BagDisplayName(b.key), "bag" .. b.key
            count = "(" .. b.n .. " / " .. C_Container.GetContainerNumSlots(b.key) .. ")"
        else
            labelText, secKey = cats[b.key].name, cats[b.key]._defaultName
        end
        count = count or ("(" .. b.n .. ")")
        if showValue and b.sell > 0 then
            count = count .. "  " .. C_CurrencyInfo.GetCoinTextureString(b.sell)
        end
        local hgt, collapsed = PlaceSection(secKey, labelText, count, posX, posY, rowW, false)
        if secKey == "recent" and BP().bagShowRecentClear == true then
            local s = _sections[_sectionsUsed]
            s._line:SetPoint("RIGHT", mod.ShowRecentClearButton(s), "LEFT", -6, 0)
        end
        posY = posY - hgt
        table.sort(b.subList, SubCompare)
        for _, sl in ipairs(b.subList) do
            if collapsed then
                break
            end
            local subCollapsed
            if sl.label ~= "" then
                hgt, subCollapsed = PlaceSection(
                    secKey .. "/" .. sl.label,
                    sl.label,
                    "(" .. #sl .. ")",
                    posX,
                    posY,
                    rowW,
                    true
                )
                posY = posY - hgt
            end
            -- Recent Items: newest pickup first, whatever the column sort
            if not subCollapsed then
                table.sort(sl, b.key == "recent" and mod.RecentCompare or rowCompare)
            end
            for i, skinData in ipairs(subCollapsed and _emptyP or sl) do
                local button = GetOrCreateRow(_rowsUsed + 1)
                if button then -- nil in combat (see GetOrCreateRow)
                    _rowsUsed = _rowsUsed + 1
                    button:GetParent():SetParent(childFrame)
                    if skinData.info then
                        RenderRow(
                            button,
                            skinData,
                            cols,
                            rowW,
                            posX,
                            posY,
                            i % 2 == 0,
                            skinData._pinDim and b.key ~= "pinned" and b.key ~= "recent"
                        )
                    else
                        RenderEmptyRow(button, cols, skinData, rowW, posX, posY, i % 2 == 0)
                    end
                    posY = posY - rowH
                end
            end
        end
        posY = posY - 6
    end
    for i = _rowsUsed + 1, #_rows do
        _rows[i]:GetParent():Hide()
    end
    return math.abs(posY) + 10, COLHDR_H
end
