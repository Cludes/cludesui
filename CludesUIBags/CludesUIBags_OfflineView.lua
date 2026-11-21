if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBags_OfflineView.lua
--  offline bank views (data from CludesUIBags_Offline.lua):
--    * bags: an alt button, then "Name's Inventory". picking an alt shows
--      their bags and the sidebar counts/filters their stuff. bank in the
--      bags sidebar (selection -3) shows their bank or the warbank.
--    * bank window: same button and "Name's Bank". an alt's bank shows over
--      the live one, with their tabs over the live sidebar.
--
--  each view is a panel over the window's item area. the bags lay out no live
--  items under it, the bank's just fade out (alpha only, the secure buttons
--  never move). the bags call ns.OfflinePanel after every refresh, the bank
--  hooks RefreshBank, and a paint only happens when something it shows moved.
--  our item buttons are display only and never touch a real slot, so it's all
--  safe in combat. hover for tooltips, shift-click links, ctrl-click previews,
--  and the window's search filters it too.
-------------------------------------------------------------------------------
local CUI = CludesUI
local mod = select(2, ...)
local Offline = mod.Offline
local Inner = mod._bagsInternals
if not (Offline and Inner) then return end -- a bags file didn't load

local GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo, C_Item.GetItemInfoInstant
local _emptyP = {}
local function BP() return (CUI._bagsDB and CUI._bagsDB.profile) or _emptyP end

-- the bags' slot size and spacing (their sliders; OnSlotMetrics below)
local SLOT_SIZE, SPACING = Inner.SLOT_SIZE, Inner.SPACING
local BAR_H, PAD = 24, 10 -- same height as the sidebar header
local ITEM_CLASS_WEAPON, ITEM_CLASS_ARMOR = Enum.ItemClass.Weapon, Enum.ItemClass.Armor
local BANK_VIEW = -3
mod.OFFLINE_BANK_VIEW = BANK_VIEW

local function GetFont() return CUI.GetFontPath("bags") end
local SetFont = mod.SetBagFont
local Hex = Offline.ClassHex

-- how old a save is, "3 days ago" style
local function Age(t)
    if type(t) ~= "number" then return nil end
    local s = math.max(time() - t, 0)
    if s < 60 then return CludesUI.L("just now") end
    return CludesUI.Lf("%1$s ago", SecondsToTime(s, false, false, 1))
end

-------------------------------------------------------------------------------
--  views: one per window. v.key is the picked alt (nil = this character),
--  v.mode is what the panel shows ("bags" | "bank" | nil).
-------------------------------------------------------------------------------
-- title text per window (functions so they read the current locale)
local bagsView = {
    win = CUI_Bags,
    viewTab = "bank",
    slots = {},
    heads = {},
    tabs = {},
    plain = function() return CludesUI.L("Inventory") end,
    word = function(name) return CludesUI.Lf("%1$s's Inventory", name) end,
}
local bankView = {
    win = _G.CUI_BankFrame,
    viewTab = "bank",
    slots = {},
    heads = {},
    tabs = {},
    plain = function() return CludesUI.L("Bank") end,
    word = function(name) return CludesUI.Lf("%1$s's Bank", name) end,
}
local views = { bagsView, bankView }
local moneyN = 0

-- a new slot size: header lines take the new inset (the next paint lays out the rest)
mod.OnSlotMetrics(function(m)
    SLOT_SIZE, SPACING = m[1], m[2]
    for _, val in ipairs(views) do
        for _, frame in ipairs(val.heads) do
            frame.line:ClearAllPoints()
            frame.line:SetPoint("LEFT", frame.label, "RIGHT", 6, 0)
            frame.line:SetPoint("RIGHT", -SPACING, 0)
        end
    end
end)

local function ShownKey(val) return val.key or Offline.CurrentKey() end

-- v.viewTab: "bank" | "warband" (all tabs, by category), "onebank" |
-- "onewarband" (all tabs, one block) or "bank:2" | "warband:1" (one tab)
local function TabKind(val)
    local key = val.viewTab
    local one = key:sub(1, 3) == "one"
    if one then key = key:sub(4) end
    local kind, i = key:match("^(%a+):?(%d*)$")
    return kind or "bank", tonumber(i), one
end

-- drop a pick that doesn't resolve anymore (option off, forgotten, source changed)
local function AltKey(val)
    if not val.key then return nil end
    if not Offline.Enabled() or val.key == Offline.CurrentKey() or not Offline.Char(val.key) then
        val.key = nil
        return nil
    end
    return val.key
end

-- the alt whose bags are showing (nil if it's this character)
function mod.OfflineAlt() return AltKey(bagsView) end

-- the search the game has applied (both windows share it), lower-cased
local function Query() return (CUI_Bags._appliedSearch or ""):lower() end

local Paint, PaintSide, SyncBank -- forward

local function Repaint(val)
    if val.scroll then val.scroll:SetVerticalScroll(0) end
    Paint(val, true)
end

-- rebuild the window around a new pick
local function Rebuild(val)
    if val.scroll then val.scroll:SetVerticalScroll(0) end
    if val == bagsView then
        if CUI_Bags:IsVisible() then CUI_Bags:RefreshInventory() end
    else
        SyncBank()
    end
end

-------------------------------------------------------------------------------
--  the title: an alt button, then "Name's Inventory" (or "Name's Bank") for
--  whoever's showing.
-------------------------------------------------------------------------------
-- delete an alt's saves, asked first. either window showing them goes back
-- to this character
local function AskForget(char)
    CUI:ShowConfirmPopup({
        title = "Delete Saved Data",
        message = CludesUI.Lf(
            "Delete %1$s's saved bags and bank? They are saved again the next time you log in on that character.",
            char.name
        ),
        confirmText = "Delete",
        cancelText = "Cancel",
        onConfirm = function()
            Offline.Forget(char.key)
            for _, wid in ipairs(views) do
                if wid.key == char.key then
                    wid.key = nil
                    Rebuild(wid)
                end
            end
        end,
    })
end

-- realm headers (only with more than one realm), each alt with an x to delete it
local function OpenPicker(val, ownerFrame)
    local itemList, realm = {}, nil
    local charList, realms = Offline.Characters(), {}
    for _, char in ipairs(charList) do
        realms[char.realm] = true
    end
    local manyRealms = next(realms) ~= nil and next(realms, next(realms)) ~= nil
    local function Off() return true end
    local isShown = ShownKey(val)
    for _, char in ipairs(charList) do
        if manyRealms and char.realm ~= realm then
            realm = char.realm
            itemList[#itemList + 1] = { text = realm, noLoc = true, isDisabled = Off }
        end
        itemList[#itemList + 1] = {
            text = Hex(char.class) .. char.name .. "|r",
            noLoc = true,
            isActive = isShown == char.key,
            onClick = function()
                val.key = not char.current and char.key or nil
                Rebuild(val)
            end,
            onRemove = not char.current and function() AskForget(char) end or nil,
            removeTip = CludesUI.L("Delete saved data"),
        }
    end
    if #charList < 2 then
        itemList[#itemList + 1] =
            { text = CludesUI.L("No other characters saved yet."), noLoc = true, isDisabled = Off }
    end
    CUI.ShowContextMenu(ownerFrame, itemList, { below = true, fontKey = "bags" })
end

local function CreatePickerButton(val, header)
    local forever = mod.BagsForever()
    local scale = header:GetParent()._foreverBagFrameScale or 1
    local btnFrame = CreateFrame("Button", nil, header)
    btnFrame:SetSize(20 * scale, 20 * scale)

    local backdrop
    if forever and C_Texture.GetAtlasInfo("common-button-tertiary-square-normal") then
        btnFrame:SetNormalAtlas("common-button-tertiary-square-normal")
        if C_Texture.GetAtlasInfo("common-button-tertiary-square-pressed") then
            btnFrame:SetPushedAtlas("common-button-tertiary-square-pressed")
        end
        if C_Texture.GetAtlasInfo("common-button-tertiary-square-hover") then
            btnFrame:SetHighlightAtlas("common-button-tertiary-square-hover")
        end
    else
        backdrop = btnFrame:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(1, 1, 1, 0.06)
        CUI.MakeBorder(btnFrame, 1, 1, 1, 0.15, CUI.PP)
    end

    local iconTex = btnFrame:CreateTexture(nil, "OVERLAY")
    if forever and C_Texture.GetAtlasInfo("socialqueuing-icon-group") then
        iconTex:SetAtlas("socialqueuing-icon-group")
        iconTex:SetDesaturated(true)
        iconTex:SetSize(15 * scale, 13 * scale)
    else
        iconTex:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-person.png")
        iconTex:SetSize(14 * scale, 14 * scale)
    end
    if forever then iconTex:SetVertexColor(1, 0.86, 0.63) end
    iconTex:SetPoint("CENTER")
    iconTex:SetAlpha(0.8)

    btnFrame:SetScript("OnClick", function(self) OpenPicker(val, self) end)
    btnFrame:SetScript("OnEnter", function(self)
        iconTex:SetAlpha(1)
        if backdrop then backdrop:SetColorTexture(1, 1, 1, 0.14) end
        CUI.ShowWidgetTooltip(self, CludesUI.L("Choose an alt"))
    end)
    btnFrame:SetScript("OnLeave", function()
        iconTex:SetAlpha(0.8)
        if backdrop then backdrop:SetColorTexture(1, 1, 1, 0.06) end
        CUI.HideWidgetTooltip()
    end)
    return btnFrame
end

-- title: the window's title font string, count: the item count next to it
local function SyncTitle(val, title, count)
    if not (title and count) then return end
    local enabled = Offline.Enabled()
    if enabled and not val.pick then val.pick = { btn = CreatePickerButton(val, title:GetParent()) } end
    local p = val.pick
    if p then p.btn:SetShown(enabled) end
    if enabled then
        local char = Offline.Char(ShownKey(val))
        local name = (char and char.name) or UnitName("player") or ""
        local class = (char and char.class) or select(2, UnitClass("player"))
        title:SetText(val.word(Hex(class) .. name .. "|r"))
    else
        title:SetText(val.plain())
    end
    local heading = title:GetParent()
    if heading._foreverTitleY then
        if enabled then p.btn:SetPoint("LEFT", heading, "TOPLEFT", 55, heading._foreverControlsY) end
        title:SetPoint("LEFT", heading, "TOPLEFT", enabled and 83 or 55, heading._foreverTitleY)
        return
    end

    count:ClearAllPoints()
    -- the button takes the title's spot (bags shift it for the sidebar arrow), the title goes after
    local pt, relTo, relPt, posX, posY = title:GetPoint(1)
    if p and relTo ~= p.btn then p.base = { pt, relTo, relPt, posX, posY } end
    if not enabled then
        if p and p.base then
            title:ClearAllPoints()
            title:SetPoint(unpack(p.base))
        end
        count:SetPoint("LEFT", title, "RIGHT", 8, 0)
        return
    end
    p.btn:ClearAllPoints()
    p.btn:SetPoint("LEFT", p.base[2], p.base[3], p.base[4], p.base[5])
    title:ClearAllPoints()
    title:SetPoint("LEFT", p.btn, "RIGHT", 8, 0)
    count:SetPoint("LEFT", title, "RIGHT", 8, 0)
end

local Place -- below
-- closing a window goes back to this character
CUI_Bags:HookScript("OnHide", function()
    if CUI_Bags:IsShown() then return end
    bagsView.key = nil
    if bagsView.mode then Place(bagsView, nil) end
end)

-------------------------------------------------------------------------------
--  the panel: a bar (bank/warband, saved time, gold) over a scrolling grid
-------------------------------------------------------------------------------
local function TabButton(val, textValue, key)
    local widget = CreateFrame("Button", nil, val.bar)
    widget:SetHeight(BAR_H)
    widget.text = widget:CreateFontString(nil, "OVERLAY")
    SetFont(widget.text, 12)
    widget.text:SetPoint("CENTER")
    widget.text:SetText(textValue)
    widget:SetWidth(widget.text:GetStringWidth() + 16)
    widget.line = widget:CreateTexture(nil, "OVERLAY")
    widget.line:SetPoint("BOTTOMLEFT", 6, 0)
    widget.line:SetPoint("BOTTOMRIGHT", -6, 0)
    widget.line:SetHeight(2)
    widget.key = key
    widget:SetScript("OnClick", function()
        val.viewTab = key
        Repaint(val)
    end)
    widget:SetScript("OnEnter", function(self)
        if val.viewTab ~= self.key then self.text:SetTextColor(1, 1, 1) end
    end)
    widget:SetScript("OnLeave", function(self)
        if val.viewTab ~= self.key then self.text:SetTextColor(0.6, 0.6, 0.6) end
    end)
    return widget
end

local function PaintTabs(val)
    local red, green, blue = CUI.GetAccentColor()
    local kind = TabKind(val)
    for _, tab in ipairs(val.tabs) do
        local enabled = tab.key == kind
        tab.text:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6)
        tab.line:SetColorTexture(red, green, blue, 1)
        tab.line:SetShown(enabled)
        -- the bank window lists the tabs in its sidebar instead
        tab:SetShown(val.mode == "bank" and not val.side and (tab.key ~= "warband" or Offline.HasWarband()))
    end
end

local function Build(val)
    if val.panel then return end
    local window = val.win
    -- above the window's item buttons so they never show through
    local panelFrame = CreateFrame("Frame", nil, window)
    panelFrame:SetFrameLevel(window:GetFrameLevel() + 40)
    panelFrame:EnableMouse(true)
    panelFrame:Hide()
    val.panel = panelFrame

    local barFrame = CreateFrame("Frame", nil, panelFrame)
    barFrame:SetPoint("TOPLEFT")
    barFrame:SetPoint("TOPRIGHT")
    barFrame:SetHeight(BAR_H)
    local bbg = barFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
    bbg:SetAllPoints()
    bbg:SetColorTexture(0, 0, 0, 0.25)
    local px = CUI.PP.mult
    local sep = barFrame:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(px)
    sep:SetPoint("BOTTOMLEFT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetColorTexture(0.15, 0.15, 0.15, 1)
    val.bar = barFrame

    local previous
    for _, skinData in ipairs({ { CludesUI.L("Bank"), "bank" }, { CludesUI.L("Warband"), "warband" } }) do
        local t = TabButton(val, skinData[1], skinData[2])
        if previous then
            t:SetPoint("LEFT", previous, "RIGHT", 0, 0)
        else
            t:SetPoint("LEFT", 6, 0)
        end
        val.tabs[#val.tabs + 1] = t
        previous = t
    end

    -- gold looks like the bags footer's (SmallMoneyFrameTemplate, 11pt)
    moneyN = moneyN + 1
    local name = "CUI_OfflineMoneyFrame" .. moneyN
    local moneyFrame = CreateFrame("Frame", name, barFrame, "SmallMoneyFrameTemplate")
    MoneyFrame_SetType(moneyFrame, "STATIC")
    for _, suffix in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
        local button = _G[name .. suffix]
        local txt = button and button:GetFontString()
        if txt then SetFont(txt, 11) end
    end
    for _, char in pairs({ moneyFrame:GetChildren() }) do
        char:EnableMouse(false)
    end
    val.money, val.moneyName = moneyFrame, name
    -- hover says whose gold it is
    local moneyHitbox = CreateFrame("Frame", nil, barFrame)
    moneyHitbox:SetPoint("TOPLEFT", moneyFrame, "TOPLEFT", -5, 5)
    moneyHitbox:SetPoint("BOTTOMRIGHT", moneyFrame, "BOTTOMRIGHT", 5, -5)
    moneyHitbox:SetFrameLevel(moneyFrame:GetFrameLevel() + 10)
    moneyHitbox:EnableMouse(true)
    moneyHitbox:SetScript("OnEnter", function(self)
        local textValue
        if val.mode == "bank" and TabKind(val) == "warband" then
            textValue = CludesUI.L("Warband Currency")
        else
            local char = Offline.Char(ShownKey(val))
            textValue = CludesUI.Lf("%1$s's Currency", (char and char.name) or UnitName("player") or "")
        end
        CUI.ShowWidgetTooltip(self, textValue)
    end)
    moneyHitbox:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)

    val.info = barFrame:CreateFontString(nil, "OVERLAY")
    SetFont(val.info, 11)
    val.info:SetTextColor(0.6, 0.6, 0.6)
    val.info:SetJustifyH("RIGHT")

    local scroll = CreateFrame("ScrollFrame", nil, panelFrame)
    scroll:SetPoint("TOPLEFT", 0, -BAR_H)
    scroll:SetPoint("BOTTOMRIGHT")
    scroll:EnableMouseWheel(true)
    local childFrame = CreateFrame("Frame", nil, scroll)
    childFrame:SetSize(1, 1)
    scroll:SetScrollChild(childFrame)
    -- the bags' own scrollbar (wheel, thumb, controller steps)
    local track, _, updateThumb = mod.AttachGridScrollbar(panelFrame, scroll, true, true)
    track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -1, 0)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -1, 0)
    val.scroll, val.child, val.track, val.updateThumb = scroll, childFrame, track, updateThumb
    val.empty = panelFrame:CreateFontString(nil, "OVERLAY")
    SetFont(val.empty, 12)
    val.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", PAD + 6, -PAD - 4)
    val.empty:SetPoint("RIGHT", scroll, "RIGHT", -PAD, 0)
    val.empty:SetJustifyH("LEFT")
    val.empty:SetTextColor(0.6, 0.6, 0.6)

    -- only a tooltip one of its slots opened
    panelFrame:SetScript("OnHide", function()
        local ownerFrame = GameTooltip:GetOwner()
        if ownerFrame and ownerFrame:GetParent() == childFrame then GameTooltip:Hide() end
    end)
end

-------------------------------------------------------------------------------
--  item buttons (display only)
-------------------------------------------------------------------------------
local function SlotOnEnter(self)
    if not self.str then return end
    mod.SetInsetBorderColor(self, 1, 1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.str)
    GameTooltip:Show()
end
local function SlotOnLeave(self)
    mod.SetInsetBorderColor(self, self._r, self._g, self._b, 1)
    GameTooltip:Hide()
end
local function SlotOnClick(self)
    local text = self.str
    if not text then return end
    -- items saved as strings get their full link back from the item cache
    local itemLink = text:find("|H", 1, true) and text or select(2, GetItemInfo(text))
    if itemLink then HandleModifiedItemClick(itemLink) end
end

local function Slot(val, i)
    local widget = val.slots[i]
    if widget then return widget end
    widget = CreateFrame("Button", nil, val.child)
    mod.SizeSlot(widget)
    widget.icon = widget:CreateTexture(nil, "ARTWORK")
    widget.icon:SetAllPoints()
    widget.Count = widget:CreateFontString(nil, "OVERLAY")
    widget.Count:SetPoint("BOTTOMRIGHT", -2, 2)
    widget.Level = widget:CreateFontString(nil, "OVERLAY")
    widget.Level:SetPoint("TOPLEFT", 1, -1)
    local highlight = widget:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    mod.CreateInsetBorder(widget, true)
    widget:SetScript("OnEnter", SlotOnEnter)
    widget:SetScript("OnLeave", SlotOnLeave)
    widget:SetScript("OnClick", SlotOnClick)
    val.slots[i] = widget
    return widget
end

local function Head(val, i)
    local frame = val.heads[i]
    if frame then return frame end
    frame = CreateFrame("Frame", nil, val.child)
    frame:SetHeight(20)
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    frame.label:SetPoint("LEFT")
    frame.label:SetTextColor(0.7, 0.7, 0.7)
    local px = CUI.PP.mult
    frame.line = frame:CreateTexture(nil, "ARTWORK")
    frame.line:SetHeight(px)
    frame.line:SetPoint("LEFT", frame.label, "RIGHT", 6, 0)
    frame.line:SetPoint("RIGHT", -SPACING, 0)
    frame.line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
    if mod.BagsForever() then mod.SetForeverBagSectionColors(frame.label, frame.line) end
    val.heads[i] = frame
    return frame
end

-------------------------------------------------------------------------------
--  content
-------------------------------------------------------------------------------
-- the containers behind the view, when they were saved, and the saved list
-- they come from (its revision says when they changed)
local function Containers(val)
    local list, saved
    local kind, i = TabKind(val)
    if val.mode == "bank" and kind == "warband" then
        local wid = Offline.Warband()
        list, saved = wid.tabs, wid.time
    else
        local char = Offline.Char(ShownKey(val))
        if not char then return nil end
        if val.mode == "bags" then return char.bags, char.bagsTime, char.bags end
        list, saved = char.bank, char.bankTime
    end
    -- one tab picked in the bank window's sidebar: the view keeps one wrapper so the memo holds
    if i and val.mode == "bank" and type(list) == "table" and list[i] then
        local one = val.one or {}
        val.one, one[1] = one, list[i]
        return one, saved, list
    end
    return list, saved, list
end

-- category edits bump this, so the memo and a paint know the grouping moved.
-- the hooks go in with the first classify (nothing to keep up before that)
local catGen = 0
local catHooked = false
local function BumpCat() catGen = catGen + 1 end
local function WatchCategories()
    catHooked = true
    local CM = _G.CUI_CategoryManager
    for _, m in ipairs({
        "InitCategories",
        "SaveState",
        "RenameCategory",
        "ReorderCategory",
        "GroupCategories",
        "AddToGroup",
        "UngroupCategory",
        "DisbandGroup",
        "RenameGroup",
        "AddCustomCategory",
        "RemoveCustomCategory",
        "AssignItem",
        "UnassignItem",
        "ToggleJunk",
        "OnJunkChanged",
        "OnEquipmentSetsChanged",
        "OnVirtualAnswersChanged",
    }) do
        if CM and type(CM[m]) == "function" then hooksecurefunc(CM, m, BumpCat) end
    end
end

-- the settings classifying reads (disabled categories, split set gear) as one
-- string, for the memo and the signature
local function DisabledKey()
    local profile = BP()
    local dis = profile.bagSplitSetGearBySet and "split|" or ""
    for key in pairs(profile.bagDisabledCategories or _emptyP) do
        dis = dis .. key .. ","
    end
    return dis
end

-- item ids asked for and not answered yet (each repaints the views when it
-- lands); an id the game says it can't load is given up on, so nothing waits on it
local pending, failed = {}, {}

-- name, quality, icon for a saved string (pets and keystones are full links)
local function Info(text, ident)
    local name, _, q, _, _, _, _, _, _, iconTex
    if text:sub(1, 5) == "item:" then
        name, _, q, _, _, _, _, _, _, iconTex = GetItemInfo(text)
    else
        name = text:match("%[(.-)%]")
        _, _, q, _, _, _, _, _, _, iconTex = GetItemInfo(ident)
        local species, _, breed = text:match("|Hbattlepet:(%d+):(%d+):(%d+)")
        if species and C_PetJournal then
            local _, petIcon = C_PetJournal.GetPetInfoBySpeciesID(tonumber(species))
            iconTex, q = petIcon or iconTex, tonumber(breed) or q
        end
    end
    return name, q, iconTex
end

-- every saved item as a display entry with its bags category; kept until the
-- list, its revision, the categories or the disabled set change, so the
-- sidebar counts and repaints share it. a pass still waiting on item data
-- runs again. bags: it's a bags list, so the 6th container is the reagent bag.
-- src: the saved list it came from (a one-tab view wraps one of its tabs)
local passes = setmetatable({}, { __mode = "k" })
local function Classified(list, bags, source)
    if not catHooked then WatchCategories() end
    local rev, dis = Offline.ListRev(source or list), DisabledKey()
    -- a one-tab view reuses its wrapper for every tab, so it's keyed on the tab itself
    local key = list
    if source and source ~= list then key = list[1] end
    local pass = key and passes[key]
    if
        pass
        and pass.rev == rev
        and pass.cat == catGen
        and pass.dis == dis
        and pass.bags == bags
        and not pass.waiting
    then
        return pass.items, pass.used, pass.total
    end
    local itemList, used, sum, wait = {}, 0, 0, false
    local mgr = _G.CUI_CategoryManager
    local cats = mgr and mgr:GetCategories()
    -- the catch-all and reagent bag once, not per item; disabled categories land in the catch-all
    local catchAll, reagent
    for i, category in ipairs(cats or {}) do
        if category.isCatchAll then catchAll = i end
        if category.isReagentBag then reagent = i end
    end
    local disabled = BP().bagDisabledCategories or _emptyP
    for place, t in ipairs(type(list) == "table" and list or {}) do
        if type(t) == "table" then
            sum = sum + (t.size or 0)
            local inReagent = bags and place == 6 and reagent
            for slot, text in pairs(type(t.items) == "table" and t.items or {}) do
                used = used + 1
                local ident = Offline.ItemID(text)
                local name, q, iconTex = Info(text, ident)
                if q == nil and ident and not failed[ident] then
                    wait = true
                    if not pending[ident] then
                        pending[ident] = true
                        C_Item.RequestLoadItemDataByID(ident)
                    end
                end
                local position = 0
                if inReagent then
                    position = reagent
                elseif cats then
                    position = mgr:ClassifyItem(text, ident, nil, nil, q or 1) or catchAll or #cats
                end
                local category = cats and cats[position]
                if catchAll and category and category._defaultName and disabled[category._defaultName] then
                    position = catchAll
                end
                name = name or ""
                local _, _, _, _, instIcon, classID = GetItemInfoInstant(ident or text)
                itemList[#itemList + 1] = {
                    str = text,
                    id = ident,
                    name = name,
                    lower = name:lower(),
                    q = q or 1,
                    icon = iconTex or instIcon,
                    cat = position,
                    n = (t.counts and t.counts[slot]) or 1,
                    gear = classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR,
                }
            end
        end
    end
    if key then
        passes[key] = {
            rev = rev,
            cat = catGen,
            dis = dis,
            bags = bags,
            waiting = wait,
            items = itemList,
            used = used,
            total = sum,
        }
    end
    return itemList, used, sum
end

-- the classified items, cut down to the search and the filter's categories
local function Collect(list, bags, query, filter, source)
    local all, used, sum = Classified(list, bags, source)
    if query == "" and not filter then return all, used, sum end
    local itemList = {}
    for _, item in ipairs(all) do
        if (query == "" or item.lower:find(query, 1, true)) and (not filter or filter[item.cat]) then
            itemList[#itemList + 1] = item
        end
    end
    return itemList, used, sum
end

-- sidebar counts for the alt's bags
function mod.OfflineCounts()
    local char = Offline.Char(bagsView.key)
    local counts, sum = {}, 0
    for _, item in ipairs((Classified(char and char.bags, true))) do
        counts[item.cat] = (counts[item.cat] or 0) + 1
        sum = sum + 1
    end
    return counts, sum
end

-- the bags sidebar selection as a category filter (nil = everything)
local function Filter(val)
    if val.mode ~= "bags" then return nil end
    local sel, set = mod.GetSelection()
    local mgr = _G.CUI_CategoryManager
    if set and mgr then
        local frame = {}
        for _, mi in ipairs(mgr:GetGroupMembers(set) or {}) do
            frame[mi] = true
        end
        return frame
    end
    if sel and sel > 0 then return { [sel] = true } end
end

-- groups in the bags' own category order
local function Group(itemList)
    local cats = _G.CUI_CategoryManager and _G.CUI_CategoryManager:GetCategories() or {}
    local by = {}
    for _, item in ipairs(itemList) do
        local g = by[item.cat]
        if not g then
            g = {
                idx = item.cat,
                name = cats[item.cat] and cats[item.cat].name or CludesUI.L("Items"),
                items = {},
            }
            by[item.cat] = g
        end
        g.items[#g.items + 1] = item
    end
    local catGroups = {}
    for _, g in pairs(by) do
        catGroups[#catGroups + 1] = g
    end
    table.sort(catGroups, function(lhs, rhs) return lhs.idx < rhs.idx end)
    for _, group in ipairs(catGroups) do
        table.sort(group.items, function(lhs, rhs)
            if lhs.q ~= rhs.q then return lhs.q > rhs.q end
            if lhs.name ~= rhs.name then return lhs.name < rhs.name end
            return lhs.str < rhs.str
        end)
    end
    return catGroups
end

local function PaintSlot(widget, item)
    local zoom = BP().bagItemIconZoom or 0.08
    widget.str = item.str
    widget.icon:SetTexture(item.icon or 134400)
    widget.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    CUI.ApplyIconTextFont(widget.Count, GetFont(), BP().bagCountFontSize or 11, "bags")
    widget.Count:SetText(item.n > 1 and item.n or "")
    widget.Level:SetFont(GetFont(), BP().itemlevelFontSize or 12, CUI.SlugFlag("OUTLINE, SLUG"))
    local lvl = item.gear and BP().showItemlevelInBags ~= false and C_Item.GetDetailedItemLevelInfo(item.str)
    if lvl and lvl > 1 then
        widget.Level:SetText(lvl)
        widget.Level:SetTextColor(1, 1, 1)
    else
        widget.Level:SetText("")
    end
    widget._r, widget._g, widget._b = mod.QualityBorderColor(item.q)
    if not widget._fvSlotBorder and item.q <= 1 and BP().bagQualityBorder ~= false then
        widget._r, widget._g, widget._b = 0.25, 0.25, 0.25
    end
    mod.SetInsetBorderColor(widget, widget._r, widget._g, widget._b, 1)
    widget:Show()
end

-- the bar's gold: its right edge on the window's own gold readout
local function PaintGold(val, gold)
    local moneyFrame, barFrame = val.money, val.bar
    moneyFrame:ClearAllPoints()
    local ref = val.goldRef and val.goldRef()
    local dx = -10
    if ref and ref:IsShown() and ref:GetRight() and barFrame:GetRight() then
        dx = ref:GetRight() - barFrame:GetRight()
    end
    moneyFrame:SetPoint("RIGHT", barFrame, "RIGHT", dx, 0)
    if type(gold) == "number" then
        MoneyFrame_Update(val.moneyName, gold)
        -- whole gold with separators, as the bags footer shows it
        local goldBtn = _G[val.moneyName .. "GoldButton"]
        local txt = goldBtn and goldBtn:GetFontString()
        if txt and gold >= 10000 then txt:SetText(BreakUpLargeNumbers(math.floor(gold / 10000))) end
        moneyFrame:Show()
    else
        moneyFrame:Hide()
    end
    val.info:ClearAllPoints()
    if moneyFrame:IsShown() then
        val.info:SetPoint("RIGHT", moneyFrame, "LEFT", -14, 0)
    else
        val.info:SetPoint("RIGHT", barFrame, "RIGHT", dx, 0)
    end
end

-- the gold for whoever's showing (the gold ledger keeps everyone's)
local function Gold(val)
    local GL = CUI.GetGoldLedger()
    if val.mode == "bank" and TabKind(val) == "warband" then return GL.WarbandMoney() end
    local key = ShownKey(val)
    if key == Offline.CurrentKey() then return GL.Money() end
    -- The ledger keys by GUID; an entry from an older build by "Name-Realm".
    local char = Offline.Char(key)
    local charList = GL.Data().chars
    local charRec = (char and char.guid and charList[char.guid]) or charList[key]
    return charRec and charRec.money
end

-- everything the grid draws from; the same signature twice means nothing moved.
-- gold and the saved time are painted on their own, outside it
local function Signature(val, list, source, query)
    local profile = BP()
    local sel, set = mod.GetSelection()
    local red, green, blue = CUI.GetAccentColor()
    local dis = DisabledKey()
    return strjoin(
        "|",
        tostring(val.mode),
        tostring(list),
        list and list[1] and tostring(list[1]) or "",
        Offline.ListRev(source),
        query,
        val.viewTab,
        tostring(sel),
        tostring(set),
        math.floor(val.panel:GetWidth() + 0.5),
        SLOT_SIZE,
        SPACING,
        catGen,
        GetFont(),
        tostring(profile.bagItemIconZoom),
        tostring(profile.bagCountFontSize),
        tostring(profile.itemlevelFontSize),
        tostring(profile.showItemlevelInBags),
        tostring(profile.bagQualityBorder),
        tostring(profile.bagCatTitleSize),
        tostring(profile.bankSidebarCollapsed),
        tostring(profile.bankHideTabsInSidebar),
        tostring(profile.bankCategorySidebar),
        tostring(mod.BankDefaultsToOne()),
        dis,
        red,
        green,
        blue
    )
end

-- the slot count in the window header (the live refresh keeps resetting it)
local function PaintCount(val)
    local count = val.count and val.count()
    if count and val.countText then
        val.painting = true
        count:SetText(val.countText)
        val.painting = false
    end
end

-- force: paint even if the signature didn't change (item data landed)
Paint = function(val, force)
    if not (val.panel and val.panel:IsShown()) then return end
    local query = Query()
    local filter = Filter(val)
    local list, saved, source = Containers(val)
    -- saved time and gold on the bar, every time (cheap; they change on every loot)
    local age = Age(saved)
    val.info:SetText(age and CludesUI.Lf("Saved %1$s", age) or "")
    PaintGold(val, Gold(val))
    local sig = Signature(val, list, source, query)
    if not force and sig == val.sig then
        PaintCount(val)
        return
    end
    val.sig = sig
    PaintTabs(val)

    local width = val.panel:GetWidth()
    local cols = math.max(math.floor((width - PAD * 2 - 10) / (SLOT_SIZE + SPACING)), 1)
    local gridW = cols * (SLOT_SIZE + SPACING)
    val.child:SetWidth(math.max(width, 1))
    local titleSize = BP().bagCatTitleSize or 11

    local itemList, used, sum = Collect(list, val.mode == "bags", query, filter, source)
    local posY, isShown, nh = -6, 0, 0
    if list then
        local catGroups = Group(itemList)
        -- onebank / onewarbank: everything in one block, no headers
        if val.mode == "bank" and select(3, TabKind(val)) then
            local all = {}
            for _, group in ipairs(catGroups) do
                for _, item in ipairs(group.items) do
                    all[#all + 1] = item
                end
            end
            catGroups = { { items = all } }
        end
        for _, group in ipairs(catGroups) do
            if group.name then
                nh = nh + 1
                local hgt = Head(val, nh)
                SetFont(hgt.label, titleSize)
                hgt:ClearAllPoints()
                hgt:SetPoint("TOPLEFT", PAD + 5, posY)
                hgt:SetWidth(gridW)
                hgt.label:SetText(group.name .. " (" .. #group.items .. ")")
                hgt:Show()
                posY = posY - 22
            end
            for i, item in ipairs(group.items) do
                isShown = isShown + 1
                local widget = Slot(val, isShown)
                widget:ClearAllPoints()
                widget:SetPoint(
                    "TOPLEFT",
                    PAD + 5 + ((i - 1) % cols) * (SLOT_SIZE + SPACING),
                    posY - math.floor((i - 1) / cols) * (SLOT_SIZE + SPACING)
                )
                PaintSlot(widget, item)
            end
            posY = posY - math.ceil(#group.items / cols) * (SLOT_SIZE + SPACING) - 6
        end
    end
    for i = isShown + 1, #val.slots do
        val.slots[i]:Hide()
    end
    for i = nh + 1, #val.heads do
        val.heads[i]:Hide()
    end
    val.child:SetHeight(math.max(-posY, 1))
    val.updateThumb()

    -- nothing saved yet, so say how to fill it
    local empty
    if not list then
        if val.mode == "bags" then
            empty = CludesUI.L("This character's bags haven't been saved yet. Log in on this character once.")
        elseif TabKind(val) == "warband" then
            empty = CludesUI.L("The warband bank hasn't been saved yet. Open it once at a banker.")
        else
            empty =
                CludesUI.L("This character's bank hasn't been saved yet. Visit a banker on this character.")
        end
    elseif isShown == 0 then
        empty = query ~= "" and CludesUI.L("No items match your search.") or CludesUI.L("No Items")
    end
    val.empty:SetText(empty or "")
    val.empty:SetShown(empty ~= nil)

    -- slots in the window header
    local textValue = ""
    if list and filter then
        textValue = CludesUI.Lf("%d Items", isShown)
    elseif list then
        textValue = CludesUI.Lf("%d / %d Slots", used, sum)
    end
    val.countText = textValue
    if val.side then PaintSide(val) end
    PaintCount(val)
end

-- item data landing, or the store changing under an open view
-- force: item data landed (the signature can't see that)
local function RunSoon(val)
    val.repaint = false
    local frame = val.force
    val.force = nil
    if not (val.panel and val.panel:IsVisible()) then return end
    -- an alt's sidebar counts come from these same items: just the sidebar, not a full refresh
    if val == bagsView and AltKey(val) then Inner.BuildSidebarButtons(mod.OfflineCounts()) end
    Paint(val, frame)
end
local function Soon(val, force)
    if force then val.force = true end
    if val.repaint then return end
    val.repaint = true
    if not val.soon then val.soon = function() RunSoon(val) end end
    C_Timer.After(0.2, val.soon)
end
-- only the ids a view asked for repaint it
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, _, ident, success)
    if not pending[ident] then return end
    pending[ident] = nil
    if not success then failed[ident] = true end
    for _, val in ipairs(views) do
        if val.panel and val.panel:IsVisible() then Soon(val, true) end
    end
end)
local function SyncEvents()
    for _, val in ipairs(views) do
        if val.panel and val.panel:IsVisible() then
            eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            return
        end
    end
    eventFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end
-- this character's own bags never show in a panel (they're live), so their
-- saves don't repaint anything
Offline.OnChange(function(what)
    if what == "bags" then return end
    for _, val in ipairs(views) do
        if val.panel and val.panel:IsVisible() then Soon(val) end
    end
end)

-- the window's own content under the panel: faded out, never hidden or moved
local function Cover(val, enabled)
    if val.covered == enabled then return end
    val.covered = enabled
    for _, frame in pairs(val.under and val.under() or {}) do
        frame:SetAlpha(enabled and 0 or 1)
    end
end

-- show the panel over a window's item area, or hide it
Place = function(val, mode, leftX, topY, bottom)
    val.mode = mode
    Cover(val, mode ~= nil)
    if val.side then val.side:SetShown(mode ~= nil) end
    if not mode then
        if val.panel then val.panel:Hide() end
        val.sig = nil
        SyncEvents()
        return
    end
    Build(val)
    local window = val.win
    local rightInset = mod.BagsForever() and -7 or -1
    val.panel:ClearAllPoints()
    val.panel:SetPoint("TOPLEFT", window, "TOPLEFT", leftX, -topY)
    val.panel:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", rightInset, bottom)
    val.panel:SetFrameLevel(window:GetFrameLevel() + 40)
    if not val.panel:IsShown() then val.track.PadSync(CUI.PadInUse()) end
    val.panel:Show()
    SyncEvents()
    Paint(val)
end

-------------------------------------------------------------------------------
--  bags: hooked into the bags refresh
-------------------------------------------------------------------------------
bagsView.count = function() return CUI_Bags.Header and CUI_Bags.Header.itemCount end
-- the list display's column bar too, or its labels show through the panel's bar
bagsView.under = function()
    return { CUI_Bags._scrollFrame, CUI_Bags._scrollTrack, mod.ListHeaderBar(CUI_Bags) }
end
bagsView.goldRef = function() return CUI_Bags.Money end

-- an alt or bank is up in the bags: no live items under it, so select modes stay off
function mod.OfflineUp() return bagsView.mode ~= nil end

-- runs after every bags refresh: covers the item area while bank is picked or
-- an alt is showing, hidden otherwise. sidebarW is the sidebar's width.
function mod.OfflinePanel(sidebarW)
    local heading = CUI_Bags.Header
    -- off: nothing to do unless it was on earlier and needs tidying up
    if not Offline.Enabled() then
        if bagsView.pick or bagsView.mode then
            SyncTitle(bagsView, heading and heading.title, heading and heading.itemCount)
            Place(bagsView, nil)
        end
        return
    end
    SyncTitle(bagsView, heading and heading.title, heading and heading.itemCount)
    local mode
    if mod.GetSelection() == BANK_VIEW then
        mode = "bank"
    elseif AltKey(bagsView) then
        mode = "bags"
    end
    local topY = (heading and heading:GetHeight() or 35) + 1
    local bottom = CUI_Bags.Footer and CUI_Bags.Footer:GetHeight() or 30
    Place(bagsView, mode, sidebarW or 0, topY, bottom)
end

-------------------------------------------------------------------------------
--  bank window: an alt's bank over the live one
-------------------------------------------------------------------------------
local CUI_Bank = bankView.win
if CUI_Bank then
    bankView.count = function() return CUI_Bank._headerItemCount end
    bankView.goldRef = function() return CUI_Bank._warbandGoldText end
    bankView.under = function()
        return {
            CUI_Bank._scrollFrame,
            CUI_Bank._scrollTrack,
            CUI_Bank._sidebarSF,
            mod.ListHeaderBar(CUI_Bank),
        }
    end

    -- the alt's tabs over the live sidebar list (header and arrow stay live), styled the same
    local ROW_H, ROW_PAD, ICON = 26, 2, 18
    local rowList = {}
    local function Row(i)
        if rowList[i] then return rowList[i] end
        local widget = CreateFrame("Button", nil, bankView.side)
        widget:SetHeight(ROW_H)
        local px = CUI.PP.mult
        widget.ind = widget:CreateTexture(nil, "OVERLAY")
        widget.ind:SetWidth(px * 2)
        widget.ind:SetPoint("TOPLEFT")
        widget.ind:SetPoint("BOTTOMLEFT")
        widget.bg = widget:CreateTexture(nil, "BACKGROUND", nil, 2)
        widget.bg:SetAllPoints()
        widget.icon = widget:CreateTexture(nil, "ARTWORK")
        widget.icon:SetSize(ICON, ICON)
        widget.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        widget.label = widget:CreateFontString(nil, "OVERLAY")
        SetFont(widget.label, 11)
        widget.label:SetJustifyH("LEFT")
        widget.label:SetWordWrap(false)
        widget.label:SetPoint("LEFT", widget.icon, "RIGHT", 6, 0)
        widget.label:SetPoint("RIGHT", widget, "RIGHT", -30, 0)
        widget.count = widget:CreateFontString(nil, "OVERLAY")
        SetFont(widget.count, 10)
        widget.count:SetJustifyH("RIGHT")
        widget.count:SetTextColor(0.5, 0.5, 0.5)
        widget.count:SetPoint("RIGHT", -6, 0)
        widget:SetScript("OnClick", function(self)
            bankView.viewTab = self.key
            Repaint(bankView)
        end)
        widget:SetScript("OnEnter", function(self)
            if not self.on then self.bg:SetColorTexture(1, 1, 1, 0.06) end
            if BP().bankSidebarCollapsed then
                CUI.ShowWidgetTooltip(self, self.name .. " (" .. self.n .. ")")
            end
        end)
        widget:SetScript("OnLeave", function(self)
            if not self.on then self.bg:SetColorTexture(1, 1, 1, 0) end
            CUI.HideWidgetTooltip()
        end)
        rowList[i] = widget
        return widget
    end

    local function Used(tbl)
        local num = 0
        for _ in pairs(type(tbl) == "table" and type(tbl.items) == "table" and tbl.items or {}) do
            num = num + 1
        end
        return num
    end

    PaintSide = function(val)
        local sidePane = val.side
        local char = Offline.Char(ShownKey(val))
        local entries = {}
        -- same layout as the live sidebar: all (tabs nested under it) and one, per kind
        local oneFirst = mod.BankDefaultsToOne()
        local function Add(kind, all, one, iconTex, oneIcon, tabs, bagKey)
            local sum = 0
            for _, tab in ipairs(tabs or {}) do
                sum = sum + Used(tab)
            end
            local function All()
                entries[#entries + 1] = { key = kind, name = all, icon = iconTex, n = sum }
                if BP().bankHideTabsInSidebar and BP().bankCategorySidebar then return end
                for i, tab in ipairs(tabs or {}) do
                    if type(tab) == "table" then
                        local bagID = Enum.BagIndex[bagKey .. i]
                        entries[#entries + 1] = {
                            key = kind .. ":" .. i,
                            nested = true,
                            name = (tab.name and tab.name ~= "") and tab.name or CludesUI.Lf("Tab %1$d", i),
                            icon = mod.BankTabIcon(bagID, tab.icon) or tab.icon or iconTex,
                            n = Used(tab),
                        }
                    end
                end
            end
            local function One()
                entries[#entries + 1] = { key = "one" .. kind, name = one, icon = oneIcon, n = sum }
            end
            local first = #entries + 1
            if oneFirst then
                One()
                All()
            else
                All()
                One()
            end
            -- the warbank's views sit apart from the bank's
            if first > 1 then entries[first].split = true end
        end
        Add(
            "bank",
            CludesUI.L("All Bank Tabs"),
            CludesUI.L("OneBank"),
            413587,
            1542860,
            char and char.bank,
            "CharacterBankTab_"
        )
        if Offline.HasWarband() then
            Add(
                "warband",
                CludesUI.L("All Warbank Tabs"),
                CludesUI.L("OneWarbank"),
                1542854,
                1542854,
                Offline.Warband().tabs,
                "AccountBankTab_"
            )
        end

        local collapsed = BP().bankSidebarCollapsed
        local wid = sidePane:GetWidth()
        local red, green, blue = CUI.GetAccentColor()
        local posY = 0
        local px = CUI.PP.mult
        if not sidePane._div then
            sidePane._div = sidePane:CreateTexture(nil, "ARTWORK")
            sidePane._div:SetColorTexture(0.2, 0.2, 0.2, 1)
        end
        sidePane._div:Hide()
        for i, entry in ipairs(entries) do
            -- a divider like the live sidebar's
            if entry.split then
                posY = posY - 4
                local inset = math.floor(wid * 0.08)
                sidePane._div:ClearAllPoints()
                sidePane._div:SetHeight(px)
                sidePane._div:SetPoint("TOPLEFT", sidePane, "TOPLEFT", inset, posY)
                sidePane._div:SetPoint("TOPRIGHT", sidePane, "TOPRIGHT", -inset, posY)
                sidePane._div:Show()
                posY = posY - px - 4
            end
            local row = Row(i)
            row.key, row.name, row.n = entry.key, entry.name, entry.n
            row.on = entry.key == val.viewTab
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", sidePane, "TOPLEFT", 0, posY)
            row:SetWidth(wid)
            mod.AnchorBagSidebarIcon(row.icon, collapsed, 8 + (entry.nested and 10 or 0))
            row.icon:SetTexture(CludesUI.ClientIcon(entry.icon))
            row.icon:SetAlpha(row.on and 1 or 0.75)
            row.label:SetShown(not collapsed)
            row.count:SetShown(not collapsed)
            row.label:SetText(entry.name)
            row.label:SetTextColor(1, 1, 1, row.on and 1 or 0.75)
            row.count:SetText(entry.n)
            row.ind:SetColorTexture(red, green, blue, 1)
            row.ind:SetShown(row.on)
            row.bg:SetColorTexture(red, green, blue, row.on and 0.1 or 0)
            if not row.on then row.bg:SetColorTexture(1, 1, 1, 0) end
            row:Show()
            posY = posY - ROW_H - ROW_PAD
        end
        for i = #entries + 1, #rowList do
            rowList[i]:Hide()
        end
    end

    SyncBank = function()
        if not CUI_Bank:IsShown() then return end
        if not Offline.Enabled() then
            if bankView.pick or bankView.mode then
                SyncTitle(bankView, CUI_Bank._headerTitle, CUI_Bank._headerItemCount)
                Place(bankView, nil)
            end
            return
        end
        SyncTitle(bankView, CUI_Bank._headerTitle, CUI_Bank._headerItemCount)
        local scrollFrame, list = CUI_Bank._scrollFrame, CUI_Bank._sidebarSF
        if not bankView.side and list then
            bankView.side = CreateFrame("Frame", nil, CUI_Bank)
            bankView.side:EnableMouse(true)
            bankView.side:Hide()
        end
        if bankView.side then
            bankView.side:ClearAllPoints()
            bankView.side:SetPoint("TOPLEFT", list, "TOPLEFT")
            bankView.side:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT")
            bankView.side:SetFrameLevel(CUI_Bank:GetFrameLevel() + 40)
        end
        -- between the window's header and footer, right of the sidebar
        local _, _, _, leftX, topY = scrollFrame:GetPoint(1)
        local _, _, _, _, bottom = scrollFrame:GetPoint(2)
        -- the list display's column bar sits above the scroll area: cover it too so it can't be clicked
        local barFrame = mod.ListHeaderBar(CUI_Bank)
        if barFrame and barFrame:IsShown() then
            local _, _, _, _, barTop = barFrame:GetPoint(1)
            if barTop then topY = barTop end
        end
        Place(bankView, AltKey(bankView) and "bank" or nil, leftX or 0, -(topY or -30), bottom or 30)
    end

    hooksecurefunc(CUI_Bank, "RefreshBank", SyncBank)
    CUI_Bank:HookScript("OnShow", SyncBank)
    CUI_Bank:HookScript("OnHide", function()
        if CUI_Bank:IsShown() then return end
        bankView.key, bankView.viewTab = nil, "bank"
        if bankView.mode then Place(bankView, nil) end
    end)
    -- the live bank keeps resetting the slot count while an alt's showing
    if CUI_Bank._headerItemCount then
        hooksecurefunc(CUI_Bank._headerItemCount, "SetText", function(fontStr)
            if bankView.painting or bankView.mode ~= "bank" or not bankView.countText then return end
            bankView.painting = true
            fontStr:SetText(bankView.countText)
            bankView.painting = false
        end)
    end
else
    SyncBank = function() end
end

-- option toggled: off leaves the bank view for all items and goes back to
-- this character; either way the bank sidebar switches layout
function Offline.SyncButton()
    if not Offline.Enabled() then
        bagsView.key, bankView.key = nil, nil
        if mod.GetSelection() == BANK_VIEW then Inner.SetSelectedCategoryIndex(0) end
    end
    if CUI_Bags:IsVisible() then CUI_Bags:RefreshInventory() end
    if CUI_Bank and CUI_Bank:IsShown() then
        CUI_Bank:RefreshBank()
    else
        SyncBank()
    end
end
