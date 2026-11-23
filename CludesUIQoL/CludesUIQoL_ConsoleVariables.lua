if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CludesUIQoL_ConsoleVariables.lua  (both clients)
--  Console Variables: every console variable the game lets you change, with
--  its value beside its default, in a CludesUI window (/ccvar, or QoL > UI).
--    Changed / All / Pinned tabs and a search; click a row to set its value,
--    Reset puts the default back, Pin keeps the value.
--    Export: the list as shown, "name=value" a line, to share; Import takes
--    such lines back (a confirm lists what changes).
--    Put Back Pinned at Login (CludesUIDB.cvarPinsOn): each pinned value is
--    set again at login (out of combat), for the ones the game resets.
--  Locked, secure and read-only variables are never listed or set, nor are
--  the ones that only make sense on this machine (adapter, monitor, sound
--  devices, locale, realm) imported or exported. Changes wait out combat.
--  Pins live in CludesUIDB.cvarPins { name = value }.
-------------------------------------------------------------------------------

local WIDTH, HEIGHT = 640, 560
local PAD = 10
local ROW_H = 20
local VALUE_W = 150
local BTN_W = 46
local SHOWN_MAX = 150
local LISTED_MAX = 8
local SHOWN_VALUE = 24
local MAX_NAME, MAX_VALUE, MAX_CVARS = 64, 255, 1000
local CVAR = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar
local NOT_SHARED = {
    lastcharacterindex = true,
    plunderstormrealm = true,
    portal = true,
    locale = true,
    textlocale = true,
    audiolocale = true,
    gxmonitor = true,
    gxadapter = true,
    gxapi = true,
    gxwindowedresolution = true,
    gxfullscreenresolution = true,
    gxnewresolution = true,
    sound_outputdrivername = true,
    sound_outputdriverindex = true,
    sound_voicechatoutputdrivername = true,
    sound_voicechatoutputdriverindex = true,
    sound_voicechatinputdrivername = true,
    sound_voicechatinputdriverindex = true,
}
local TABS = { { key = "changed", label = "Changed" }, { key = "all", label = "All" }, { key = "pinned", label = "Pinned" } }

local Kit
local window, scroll, content, summary, search
local tabButtons = {}
local rows = {}
local names, lowered, about, byLower
local values, defaults = {}, {}
local filter, shownTab = "", "changed"

local function Say(text) CUI.Print(Kit.AccentHex() .. "Console Variables:|r " .. text) end

local function Pins()
    if not CludesUIDB then return {} end
    if type(CludesUIDB.cvarPins) ~= "table" then CludesUIDB.cvarPins = {} end
    return CludesUIDB.cvarPins
end
local function Pinned(name)
    local pins = CludesUIDB and CludesUIDB.cvarPins
    return pins and pins[name]
end

local function Index()
    if names then return end
    names, lowered, about, byLower = {}, {}, {}, {}
    local all = ConsoleGetAllCommands and ConsoleGetAllCommands() or {}
    for _, info in ipairs(all) do
        local name = info.command
        if (CVAR == nil or info.commandType == CVAR) and type(name) == "string" and not about[name] then
            names[#names + 1] = name
            lowered[name] = name:lower()
            about[name] = info.help or ""
            byLower[lowered[name]] = name
        end
    end
    table.sort(names, function(a, b) return lowered[a] < lowered[b] end)
end

local function Same(a, b)
    if a == b then return true end
    local num = tonumber(a)
    return num ~= nil and num == tonumber(b)
end

-- value, default for a variable that may be changed; nil otherwise.
local function Usable(name)
    local value, default, _, _, locked, secure, readOnly = C_CVar.GetCVarInfo(name)
    if value == nil or locked or secure or readOnly then return nil end
    return value, default
end

local function Cache(name) values[name], defaults[name] = Usable(name) end

local function Listed(name)
    local value, default = values[name], defaults[name]
    if value == nil or (filter ~= "" and not lowered[name]:find(filter, 1, true)) then return nil end
    if shownTab == "changed" and Same(value, default) then return nil end
    if shownTab == "pinned" and not Pinned(name) then return nil end
    return value, default
end

local function Shown(value)
    if value == "" then return "\"\"" end
    if #value > SHOWN_VALUE then return value:sub(1, SHOWN_VALUE) .. "..." end
    return value
end

local function Private(name) return NOT_SHARED[name:lower()] == true end
local function Fits(text, max) return type(text) == "string" and #text <= max and not text:find("[%c|]") end
local function Shareable(name, value)
    return Fits(name, MAX_NAME) and name:find("^%S+$") ~= nil and Fits(value, MAX_VALUE)
end

local Redraw

local function Set(name, value)
    if InCombatLockdown() then return Say(CUI.L("Game settings can only be changed out of combat.")) end
    local taken = C_CVar.SetCVar(name, value)
    if not taken then Say(CUI.Lf("The game did not take that value for %1$s.", name)) end
    Cache(name)
    if taken and Pinned(name) and values[name] then Pins()[name] = values[name] end
    Redraw()
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------

local function Text(parent, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Kit.Font(fs, Kit.TEXT_SIZE)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.06)
    row.hover:Hide()
    row.pin = Kit.Button(row, CUI.L("Pin"), BTN_W, ROW_H - 4, function(b)
        local name = b:GetParent().cvar
        local pins = Pins()
        pins[name] = (not pins[name]) and values[name] or nil
        Redraw()
    end, { size = Kit.SMALL_SIZE })
    row.pin:SetPoint("RIGHT", 0, 0)
    row.reset = Kit.Button(row, CUI.L("Reset"), BTN_W, ROW_H - 4, function(b)
        local r = b:GetParent()
        local name, default = r.cvar, r.defaultValue
        CUI:ShowConfirmPopup({
            title = CUI.L("Console Variables"),
            message = CUI.Lf("Set %1$s back to its default, %2$s?", name, Shown(default)),
            confirmText = CUI.L("Reset"),
            onConfirm = function() Set(name, default) end,
        })
    end, { size = Kit.SMALL_SIZE })
    row.reset:SetPoint("RIGHT", row.pin, "LEFT", -4, 0)
    row.defaultText = Text(row, Kit.Palette.muted)
    row.defaultText:SetWidth(VALUE_W)
    row.defaultText:SetPoint("RIGHT", row.reset, "LEFT", -6, 0)
    row.valueText = Text(row, Kit.Palette.text)
    row.valueText:SetWidth(VALUE_W)
    row.valueText:SetPoint("RIGHT", row.defaultText, "LEFT", -6, 0)
    row.nameText = Text(row, Kit.Palette.text)
    row.nameText:SetPoint("LEFT", 4, 0)
    row.nameText:SetPoint("RIGHT", row.valueText, "LEFT", -6, 0)
    row:SetScript("OnClick", function(r)
        if InCombatLockdown() then return Say(CUI.L("Game settings can only be changed out of combat.")) end
        local name = r.cvar
        CUI:ShowInputPopup({
            title = CUI.Lf("Set %1$s", name),
            message = about[name] ~= "" and about[name] or nil,
            initialText = (C_CVar.GetCVarInfo(name)),
            selectText = true,
            confirmText = CUI.L("Set"),
            maxLetters = MAX_VALUE,
            onConfirm = function(textValue) Set(name, textValue or "") end,
        })
    end)
    row:SetScript("OnEnter", function(r)
        r.hover:Show()
        local help = about[r.cvar]
        local tip = r.cvar .. "\n" .. ((help and help ~= "") and (help .. "\n") or "") .. CUI.L("Click to change it.")
        if Pinned(r.cvar) then tip = tip .. "\n" .. CUI.Lf("Pinned at %1$s.", Shown(Pinned(r.cvar))) end
        CUI.ShowWidgetTooltip(r, tip)
    end)
    row:SetScript("OnLeave", function(r)
        r.hover:Hide()
        CUI.HideWidgetTooltip()
    end)
    rows[i] = row
    return row
end

local function Fill(row, name, value, default)
    row.cvar, row.defaultValue = name, default
    row.nameText:SetText(name)
    row.valueText:SetText(Shown(value))
    row.defaultText:SetText(Shown(default))
    local changed = not Same(value, default)
    if changed then
        row.valueText:SetTextColor(Kit.Accent())
    else
        local c = Kit.Palette.text
        row.valueText:SetTextColor(c[1], c[2], c[3])
    end
    row.reset:SetShown(changed)
    local pinned = Pinned(name) ~= nil
    row.pin:SetText(pinned and CUI.L("Pinned") or CUI.L("Pin"))
    row.pin:SetActive(pinned)
    row:Show()
end

function Redraw()
    if not (window and window:IsShown()) then return end
    local shown, matched = 0, 0
    for _, name in ipairs(names) do
        local value, default = Listed(name)
        if value then
            matched = matched + 1
            if matched <= SHOWN_MAX then
                shown = shown + 1
                Fill(Row(shown), name, value, default)
            end
        end
    end
    for i = shown + 1, #rows do
        rows[i]:Hide()
    end
    content:SetHeight(math.max(1, shown * ROW_H))
    if matched == 0 then
        if filter ~= "" then
            summary:SetText(CUI.L("No console variable matches your search."))
        elseif shownTab == "pinned" then
            summary:SetText(CUI.L("Nothing is pinned: Pin keeps a value, and Put Back Pinned at Login sets it again."))
        else
            summary:SetText(CUI.L("You have not changed any console variable from its default."))
        end
    elseif matched > SHOWN_MAX then
        summary:SetText(CUI.Lf("The first %1$d of %2$d; type more to narrow it down.", SHOWN_MAX, matched))
    else
        summary:SetText(CUI.Lf("%1$d console variable(s)", matched))
    end
    for _, b in ipairs(tabButtons) do
        b:SetActive(b.key == shownTab)
    end
    if scroll.Refresh then scroll.Refresh() end
end

-------------------------------------------------------------------------------
--  Export / import
-------------------------------------------------------------------------------

local function Export()
    local lines = {}
    for _, name in ipairs(names) do
        local value = Listed(name)
        if value and Shareable(name, value) and not Private(name) then lines[#lines + 1] = name .. "=" .. value end
    end
    if #lines == 0 then return Say(CUI.L("Nothing in the list to export.")) end
    if #lines > MAX_CVARS then
        return Say(CUI.Lf("The list has %1$d; search until it has %2$d or fewer to export it.", #lines, MAX_CVARS))
    end
    CUI:ShowCopyPopup(
        CUI.Lf("Console Variables (%1$d)", #lines),
        CUI.L("One name=value a line; Import takes it back."),
        table.concat(lines, "\n")
    )
end

local function ImportText(text)
    if InCombatLockdown() then return Say(CUI.L("Game settings can only be changed out of combat.")) end
    Index()
    local wanted, changes, left = {}, {}, 0
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local name, value = line:match("^%s*([^=%s]+)%s*=%s*(.-)%s*$")
        if name then
            if not Shareable(name, value) then return Say(CUI.L("That isn't a Console Variables list.")) end
            local known = byLower[name:lower()]
            local current = known and not Private(known) and Usable(known) or nil
            if current == nil then
                left = left + 1
            elseif not Same(current, value) then
                wanted[known] = value
                changes[#changes + 1] = known
            end
        end
    end
    if #changes == 0 then return Say(CUI.L("Nothing in that list changes anything here.")) end
    table.sort(changes, function(a, b) return lowered[a] < lowered[b] end)
    local lines = { CUI.Lf("Change %1$d console variable(s)?", #changes) }
    for i = 1, math.min(#changes, LISTED_MAX) do
        local name = changes[i]
        lines[#lines + 1] = ("%s: %s -> %s"):format(name, Shown((C_CVar.GetCVarInfo(name))), Shown(wanted[name]))
    end
    if #changes > LISTED_MAX then lines[#lines + 1] = CUI.Lf("And %1$d more", #changes - LISTED_MAX) end
    if left > 0 then lines[#lines + 1] = CUI.Lf("%1$d left out: not ones an import can change.", left) end
    CUI:ShowConfirmPopup({
        title = CUI.L("Console Variables"),
        message = table.concat(lines, "\n"),
        confirmText = CUI.L("Import"),
        onConfirm = function()
            if InCombatLockdown() then return Say(CUI.L("Game settings can only be changed out of combat.")) end
            local refused = 0
            for _, name in ipairs(changes) do
                local taken = C_CVar.SetCVar(name, wanted[name])
                if not taken then refused = refused + 1 end
                Cache(name)
                if taken and Pinned(name) and values[name] then Pins()[name] = values[name] end
            end
            Say(CUI.Lf("Changed %1$d of %2$d.", #changes - refused, #changes))
            Redraw()
        end,
    })
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------

local function HeadLabel(text, x)
    local fs = window:CreateFontString(nil, "OVERLAY")
    Kit.Font(fs, Kit.SMALL_SIZE)
    local c = Kit.Palette.muted
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetText(text)
    fs:SetPoint("TOPLEFT", x, -(Kit.HEADER_H + PAD + 22 + 8))
    return fs
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, _, name)
    local known = type(name) == "string" and byLower and byLower[name:lower()]
    if known then
        Cache(known)
        Redraw()
    end
end)

local function Build()
    Kit = CUI.Kit
    window = Kit.Window("CludesUIConsoleVariables", WIDTH, HEIGHT, CUI.L("Console Variables"))
    window:Hide()
    window:SetScript("OnShow", function() events:RegisterEvent("CVAR_UPDATE") end)
    window:SetScript("OnHide", function() events:UnregisterEvent("CVAR_UPDATE") end)
    local top = Kit.HEADER_H + PAD
    local x = PAD
    for _, t in ipairs(TABS) do
        local b = Kit.Button(window, CUI.L(t.label), 74, 22, function(self)
            shownTab = self.key
            Redraw()
        end)
        b.key = t.key
        b:SetPoint("TOPLEFT", x, -top)
        x = x + 78
        tabButtons[#tabButtons + 1] = b
    end
    local export = Kit.Button(window, CUI.L("Export"), 70, 22, Export, { tip = CUI.L("The list as it is shown, to share.") })
    export:SetPoint("TOPRIGHT", -PAD, -top)
    local import = Kit.Button(window, CUI.L("Import"), 70, 22, function()
        CUI:ShowImportPopup(ImportText, CUI.L("Import Console Variables"), CUI.L("Paste name=value lines"))
    end, { tip = CUI.L("Paste a list to set them all at once.") })
    import:SetPoint("RIGHT", export, "LEFT", -6, 0)
    search = Kit.Input(window, 1, 22, CUI.L("Search"))
    search:SetPoint("TOPLEFT", x + 4, -top)
    search:SetPoint("RIGHT", import, "LEFT", -10, 0)
    search:HookScript("OnTextChanged", function(self)
        filter = (self:GetText() or ""):lower()
        Redraw()
    end)
    -- Column heads, lined up with the row texts (pin, reset, default, value).
    local rightEdge = WIDTH - PAD - 10
    HeadLabel(CUI.L("Name"), PAD + 4)
    HeadLabel(CUI.L("Value"), rightEdge - 2 * BTN_W - 4 - 6 - VALUE_W - 6 - VALUE_W)
    HeadLabel(CUI.L("Default"), rightEdge - 2 * BTN_W - 4 - 6 - VALUE_W)
    summary = window:CreateFontString(nil, "OVERLAY")
    Kit.Font(summary, Kit.SMALL_SIZE)
    local m = Kit.Palette.muted
    summary:SetTextColor(m[1], m[2], m[3])
    summary:SetJustifyH("LEFT")
    summary:SetPoint("BOTTOMLEFT", PAD, PAD)
    summary:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    scroll, content = Kit.Scroll(window)
    scroll:SetPoint("TOPLEFT", PAD, -(top + 22 + 8 + 16))
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 10, PAD + 18)
end

local function Open()
    if not window then Build() end
    Index()
    for _, name in ipairs(names) do
        Cache(name)
    end
    window:Show()
    Redraw()
end

CUI.OpenConsoleVariables = Open

-------------------------------------------------------------------------------
--  Put Back Pinned at Login
-------------------------------------------------------------------------------

local putBack = CreateFrame("Frame")
local function PutBack()
    if not (CludesUIDB and CludesUIDB.cvarPinsOn and type(CludesUIDB.cvarPins) == "table") then return end
    if InCombatLockdown() then
        putBack:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    putBack:UnregisterEvent("PLAYER_REGEN_ENABLED")
    Kit = Kit or CUI.Kit
    local done = 0
    for name, value in pairs(CludesUIDB.cvarPins) do
        local current = Usable(name)
        if current ~= nil and not Same(current, value) then
            if C_CVar.SetCVar(name, value) then
                done = done + 1
            else
                Say(CUI.Lf("The game did not take that value for %1$s.", name))
            end
        end
    end
    if done > 0 then Say(CUI.Lf("Put back %1$d pinned console variable(s).", done)) end
end
putBack:RegisterEvent("PLAYER_LOGIN")
putBack:SetScript("OnEvent", function(self, evt)
    if evt == "PLAYER_LOGIN" then self:UnregisterEvent("PLAYER_LOGIN") end
    PutBack()
end)
CUI._ConsoleVariablesPutBack = PutBack

SLASH_CLUDESUICVAR1 = "/ccvar"
SlashCmdList.CLUDESUICVAR = function() Open() end
