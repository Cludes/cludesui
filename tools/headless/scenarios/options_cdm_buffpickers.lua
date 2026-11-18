-- Cooldown Manager buff pickers (Pickers_Options.lua): the Buffs bar picker
-- and the buff-to-cooldown-bar picker, in hosting mode and in "Replace with
-- Buff" selection mode, each opened and snapshotted with every row hovered;
-- then each row clicked in turn on a fresh open, writing out what the click
-- reported and the bars' tracked spells; then the toggle-closed path (a
-- second open on the same anchor) and a click away.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS["CludesUICooldownManager"]
if not (mod and mod.CDMO_ShowBuffBarPicker) then
    OUT:write("== no pickers\n")
    return
end
local spec = rawget(_G, "C_SpecializationInfo") or {}
_G.C_SpecializationInfo = spec
spec.GetSpecialization = function() return 1 end
spec.GetSpecializationInfo = function() return 65, "Holy" end
if mod.InvalidateSpecKey then mod.InvalidateSpecKey() end

CUI:SelectModule("CludesUICooldownManager")
CUI:SelectPage("CDM Bars")
local db = rawget(_G, "_CUCME_AceDB")
local p = db and db.profile
local bars = p and p.cdmBars and p.cdmBars.bars
if not bars or #bars == 0 then
    OUT:write("== no bars\n")
    return
end
local cdKey = bars[1].key

mod.GetCDMSpellsForBar = function()
    return {
        { spellID = 2001, cdID = 21, name = "Zeal Aura", icon = 136081, cdmCat = 2, cdmCatGroup = "buff" },
        { spellID = 2002, cdID = 22, name = "Alpha Shield", icon = 134206, cdmCat = 3, cdmCatGroup = "buff", onCUIBar = true },
        { spellID = 2003, cdID = 23, name = "Mid Haste", icon = 136085, cdmCat = 2, cdmCatGroup = "buff", isKnown = false },
        { spellID = 2004, cdID = 24, name = "Strike", icon = 134914, cdmCat = 0 },
        { spellID = 2005, cdID = 25, name = "Beta Ward", icon = 136107, cdmCat = 3, cdmCatGroup = "buff" },
    }
end

local anchor = CreateFrame("Button", nil, UIParent)
anchor:SetSize(36, 36)
anchor:SetPoint("CENTER")

local function FindMenu()
    for _, c in ipairs({ UIParent:GetChildren() }) do
        if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() == 300 then
            return c
        end
    end
end
local function Buttons(root)
    local out, stack = {}, { root }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and f:IsVisible() then out[#out + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
local function Fire(f, script, ...)
    local fn = f["\0scripts"] and f["\0scripts"][script]
    if not fn then return "none" end
    local ok, err = pcall(fn, f, ...)
    return ok and "ok" or ("ERR " .. tostring(err))
end
local function Tracked()
    local parts = {}
    for _, key in ipairs({ cdKey, "buffs" }) do
        local sd = mod.GetBarSpellData and mod.GetBarSpellData(key)
        local list = {}
        for _, sid in ipairs(sd and sd.assignedSpells or {}) do list[#list + 1] = tostring(sid) end
        parts[#parts + 1] = key .. "=[" .. table.concat(list, ",") .. "]"
    end
    return table.concat(parts, " ")
end
local function HideAll()
    for _, c in ipairs({ UIParent:GetChildren() }) do
        if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" then c:Hide() end
    end
end

local picked
local cases = {
    { "buffbar", function() mod.CDMO_ShowBuffBarPicker(anchor, "buffs", function() picked = (picked or "") .. "changed;" end) end },
    { "tocd", function() mod.CDMO_ShowBuffToCDPicker(anchor, cdKey, function() picked = (picked or "") .. "changed;" end) end },
    { "tocd select", function()
        mod.CDMO_ShowBuffToCDPicker(anchor, cdKey, function() picked = (picked or "") .. "changed;" end, function(sid, cd)
            picked = (picked or "") .. "picked " .. tostring(sid) .. "/" .. tostring(cd) .. ";"
        end)
    end },
}

for _, case in ipairs(cases) do
    local label, open = case[1], case[2]
    HideAll()
    open()
    local menu = FindMenu()
    if not menu then
        OUT:write("== " .. label .. " no menu\n")
    else
        SNAP(label, menu)
        local rows = Buttons(menu)
        OUT:write("== " .. label .. " rows " .. #rows .. "\n")
        for i, row in ipairs(rows) do
            Fire(row, "OnEnter")
            SNAP(label .. " row " .. i .. " hover", row)
            Fire(row, "OnLeave")
        end
        for i = 1, #rows do
            HideAll()
            picked = nil
            open()
            local m = FindMenu()
            local row = m and Buttons(m)[i]
            if row then
                local r = Fire(row, "OnClick", "LeftButton")
                HARNESS_ADVANCE(0.1)
                OUT:write("== " .. label .. " click " .. i .. " " .. r .. " picked=" .. tostring(picked) .. " open=" .. tostring(FindMenu() ~= nil) .. " " .. Tracked() .. "\n")
                HideAll()
            end
        end
        HideAll()
        open()
        open() -- the same anchor again: toggles closed
        OUT:write("== " .. label .. " reopen open=" .. tostring(FindMenu() ~= nil) .. "\n")
        HideAll()
        open()
        local m = FindMenu()
        if m then
            Fire(m, "OnUpdate", 0.1)
            OUT:write("== " .. label .. " update open=" .. tostring(FindMenu() ~= nil) .. "\n")
        end
    end
end
