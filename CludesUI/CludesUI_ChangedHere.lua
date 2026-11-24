if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CludesUI_ChangedHere.lua
--  Changed here: the settings on the open options page that you changed this
--  session, as a "Changed here (N)" button beside Reload UI. Click it for the
--  list: each setting's old and new value with Undo, and Undo All. A setting's
--  "old" value is what it was the first time its page was opened this session
--  (switching profile starts over). Settings are read through the same
--  accessors Spec Overrides uses (_captureCfg on each options row).
-------------------------------------------------------------------------------
local Kit = CUI.Kit
local PALETTE = Kit.Palette
local MUTED, TEXT = PALETTE.muted, PALETTE.text
local TICK, ROWS_SHOWN, LIST_W = 0.5, 10, 460

local baseline = {} -- slot key -> values the first time it was seen
local slots = {} -- the open page's slots: { key, label, cfg, values }
local slotByKey = {} -- the same, by key
local state = { page = nil, profile = nil, dirty = true }
local chip, list

local function Pack(...) return { n = select("#", ...), ... } end

-- The current values of one accessor (nil when it cannot be read).
local function Read(cfg)
    local result = Pack(pcall(cfg.getValue))
    if not result[1] then return nil end
    local values = { n = result.n - 1 }
    for i = 2, result.n do
        local v = result[i]
        if type(v) == "table" then
            local copy = {}
            for key, field in pairs(v) do
                if type(field) ~= "table" and type(field) ~= "function" then copy[key] = field end
            end
            v = copy
        end
        values[i - 1] = v
    end
    return values
end

local function Same(a, b)
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-6 end
    if type(a) == "table" and type(b) == "table" then
        for key, v in pairs(a) do
            if not Same(v, b[key]) then return false end
        end
        for key in pairs(b) do
            if a[key] == nil then return false end
        end
        return true
    end
    return a == b
end

local function SameValues(a, b)
    if a.n ~= b.n then return false end
    for i = 1, a.n do
        if not Same(a[i], b[i]) then return false end
    end
    return true
end

-------------------------------------------------------------------------------
--  The open page's slots
-------------------------------------------------------------------------------

local function PageKey()
    return tostring(CUI:GetActiveModule()) .. "|" .. tostring(CUI:GetActivePage())
end

local function Add(pageKey, label, cfg, seen)
    if type(cfg) ~= "table" or type(cfg.getValue) ~= "function" or type(cfg.setValue) ~= "function" then return end
    local text = tostring(CUI.L(label or cfg.text or "?"))
    local base = pageKey .. "|" .. text
    seen[base] = (seen[base] or 0) + 1
    local key = base .. "#" .. seen[base]
    local values = Read(cfg)
    if not values then return end
    if not baseline[key] then baseline[key] = values end
    local slot = slotByKey[key]
    if slot then
        slot.cfg = cfg
        return
    end
    slot = { key = key, label = text, cfg = cfg, values = values }
    slotByKey[key] = slot
    slots[#slots + 1] = slot
end

local function Walk(frame, pageKey, seen)
    local cfg = frame._captureCfg
    if cfg and frame:IsShown() then
        if cfg.type == "multi" and cfg.accessors then
            for _, accessor in ipairs(cfg.accessors) do
                local part = accessor.text and accessor.text ~= cfg.text and (CUI.L(cfg.text or "") .. ": " .. CUI.L(accessor.text)) or cfg.text
                Add(pageKey, part, accessor, seen)
            end
        else
            Add(pageKey, cfg.text, cfg, seen)
        end
    end
    for _, kid in ipairs({ frame:GetChildren() }) do
        if kid:IsShown() then Walk(kid, pageKey, seen) end
    end
end

-- The page hides rows scrolled out of view, so each scan adds the rows on
-- screen to what this visit has seen; a new page starts over.
local function Scan()
    if state.page ~= PageKey() or state.dirty then
        wipe(slots)
        wipe(slotByKey)
    end
    state.page, state.dirty = PageKey(), false
    -- The page's rows, and the root frames some pages hang on the scroll frame itself.
    local scroll = rawget(_G, "CludesUIScrollFrame")
    if scroll then Walk(scroll, state.page, {}) end
end

-- The open page's changed slots.
local function Changed()
    local out = {}
    for _, slot in ipairs(slots) do
        local now = Read(slot.cfg)
        if now then
            slot.values = now
            if not SameValues(now, baseline[slot.key]) then out[#out + 1] = slot end
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  Showing a value
-------------------------------------------------------------------------------

local function Number(v)
    if v == math.floor(v) then return tostring(v) end
    return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
end

local function Colour(r, g, b)
    local hex = ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    return "|cff" .. hex .. "#" .. hex:upper() .. "|r"
end

local function Show(cfg, values)
    local v = values[1]
    if values.n >= 3 and type(values[1]) == "number" and type(values[2]) == "number" and type(values[3]) == "number"
        and values[1] <= 1 and values[2] <= 1 and values[3] <= 1 and cfg.type ~= "slider" then
        return Colour(values[1], values[2], values[3])
    end
    if type(v) == "table" then
        if type(v.r) == "number" and type(v.g) == "number" and type(v.b) == "number" then return Colour(v.r, v.g, v.b) end
        return "..."
    end
    if type(v) == "boolean" then return v and "On" or "Off" end
    if cfg.values and v ~= nil then
        local entry = type(cfg.values) == "table" and cfg.values[v]
        if type(entry) == "table" then entry = entry.text end
        if type(entry) == "string" then return tostring(CUI.L(entry)) end
    end
    if type(v) == "number" then return Number(v) end
    if v == nil then return "None" end
    return tostring(v)
end

-------------------------------------------------------------------------------
--  Undo
-------------------------------------------------------------------------------

local function Undo(slot)
    local old = baseline[slot.key]
    if not old then return end
    local args = old
    -- A colour read back as one { r, g, b } table goes to a setter that takes r, g, b, a.
    if old.n == 1 and type(old[1]) == "table" and old[1].r and slot.cfg.type == "colorpicker" then
        args = { n = 4, old[1].r, old[1].g, old[1].b, old[1].a }
    end
    local ok, err = pcall(slot.cfg.setValue, unpack(args, 1, args.n))
    if not ok then geterrorhandler()(err) end
end

local Render

local function UndoAll(changed)
    for _, slot in ipairs(changed) do
        Undo(slot)
    end
    CUI:RefreshPage()
    C_Timer.After(0, function() Render() end)
end

-------------------------------------------------------------------------------
--  The button and the list
-------------------------------------------------------------------------------

local function Label(parent, size, colour)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Kit.Font(fs, size)
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function BuildList()
    list = CreateFrame("Frame", nil, CUI:GetMainFrame())
    list:SetFrameStrata("DIALOG")
    list:SetWidth(LIST_W)
    list:EnableMouse(true)
    Kit.Panel(list, 0.98)
    Kit.Header(list, CUI.L("Changed here"), function() list:Hide() end)
    list.undoAll = Kit.Button(list, CUI.L("Undo All"), 80, 22, function() UndoAll(list.changed or {}) end, {
        tip = CUI.L("Puts every setting in this list back to what it was."),
    })
    list.undoAll:SetPoint("TOPRIGHT", -28, -6)
    list.more = Label(list, Kit.SMALL_SIZE, MUTED)
    list.rows = {}
    list:Hide()
end

local function ListRow(index)
    local row = list.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, list)
    row:SetHeight(Kit.ROW_H + 4)
    row:SetPoint("TOPLEFT", 10, -(Kit.HEADER_H + 6) - (index - 1) * (Kit.ROW_H + 4))
    row:SetPoint("RIGHT", -10, 0)
    row.undo = Kit.Button(row, CUI.L("Undo"), 52, 20, function(self)
        local slot = self:GetParent().slot
        if not slot then return end
        Undo(slot)
        CUI:RefreshPage()
        C_Timer.After(0, function() Render() end)
    end)
    row.undo:SetPoint("RIGHT", 0, 0)
    row.name = Label(row, Kit.TEXT_SIZE, TEXT)
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetWidth(180)
    row.value = Label(row, Kit.TEXT_SIZE, MUTED)
    row.value:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.value:SetPoint("RIGHT", row.undo, "LEFT", -8, 0)
    list.rows[index] = row
    return row
end

local function RenderList(changed)
    if not list then BuildList() end
    list.changed = changed
    local shown = math.min(#changed, ROWS_SHOWN)
    for index = 1, math.max(shown, #list.rows) do
        local slot = index <= shown and changed[index] or nil
        local row = slot and ListRow(index) or list.rows[index]
        if row then
            row.slot = slot
            row:SetShown(slot ~= nil)
            if slot then
                row.name:SetText(slot.label)
                row.value:SetText(Show(slot.cfg, baseline[slot.key]) .. "  ->  |cffe6e8eb" .. Show(slot.cfg, slot.values) .. "|r")
            end
        end
    end
    local extra = #changed - shown
    list.more:SetShown(extra > 0)
    list.more:SetText(CUI.Lf and CUI.Lf("and %1$d more", extra) or ("and " .. extra .. " more"))
    list.more:ClearAllPoints()
    list.more:SetPoint("TOPLEFT", 10, -(Kit.HEADER_H + 10) - shown * (Kit.ROW_H + 4))
    list:SetHeight(Kit.HEADER_H + 14 + shown * (Kit.ROW_H + 4) + (extra > 0 and 18 or 0))
    list:ClearAllPoints()
    list:SetPoint("BOTTOMLEFT", chip, "TOPLEFT", 0, 8)
end

local function BuildChip()
    local footer = CUI._footerBar
    if not (footer and footer._reloadBtn) then return end
    chip = Kit.Button(footer, "", 140, footer._reloadBtn:GetHeight(), function()
        if list and list:IsShown() then return list:Hide() end
        RenderList(Changed())
        list:Show()
    end, { tip = CUI.L("Settings on this page you changed this session. Click to see them, with Undo.") })
    chip:SetPoint("LEFT", footer._reloadBtn, "RIGHT", 16, 0)
    chip:SetFrameLevel(footer:GetFrameLevel() + 2)
    chip:Hide()
end

Render = function()
    if not chip then BuildChip() end
    if not chip then return end
    local profile = CludesUIDB and CludesUIDB.activeProfile
    if profile ~= state.profile then
        state.profile = profile
        wipe(baseline)
        state.dirty = true
    end
    Scan()
    local changed = Changed()
    chip:SetShown(#changed > 0)
    if #changed > 0 then
        chip:SetText(Kit.AccentHex() .. CUI.L("Changed here") .. "|r (" .. #changed .. ")")
        chip:SetWidth(math.max(120, chip:GetTextWidth() + 24))
    end
    if list and list:IsShown() then
        if #changed == 0 then list:Hide() else RenderList(changed) end
    end
end

-------------------------------------------------------------------------------
--  Upkeep: read the page while the options window is open
-------------------------------------------------------------------------------

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker.elapsed = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < TICK then return end
    self.elapsed = 0
    Render()
end)

local function Rescan()
    state.dirty = true
    if list then list:Hide() end
end

CUI:RegisterOnShow(function()
    state.dirty = true
    ticker:Show()
end)
CUI:RegisterOnHide(function()
    ticker:Hide()
    if list then list:Hide() end
end)
hooksecurefunc(CUI, "SelectPage", Rescan)
hooksecurefunc(CUI, "SelectModule", Rescan)

CUI._ChangedHere = { Render = Render, Slots = function() return slots end, Changed = Changed, Undo = Undo, UndoAll = UndoAll }
