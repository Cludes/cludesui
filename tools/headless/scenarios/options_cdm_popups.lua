-- Cooldown Manager number-entry popups (Pickers_Options.lua): Custom Item,
-- Equipment Slot, Active State Duration, Lower Alpha, Threshold Seconds and
-- Custom Icon. Each is opened and snapshotted, then reopened per input: the
-- text typed, Enter pressed, and what reached the callback (and whether the
-- popup closed) written out; then each button hovered, left and clicked, and
-- Escape pressed.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS["CludesUICooldownManager"]
if not (mod and mod.CDMO_ShowDurationPopup) then
    OUT:write("== no popups\n")
    return
end
CUI:SelectModule("CludesUICooldownManager")
CUI:SelectPage("CDM Bars")

local db = rawget(_G, "_CUCME_AceDB")
local p = db and db.profile
local bars = p and p.cdmBars and p.cdmBars.bars
local barKey = bars and bars[1] and bars[1].key or "cooldowns"

local got
local function Record(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    got = table.concat(parts, ",")
end

local cases = {
    { "item", "CUI_CDM_ItemIDPopup", function() mod.CDMO_ShowCustomItemIDPopup(barKey, Record) end, { "", "0", "6948", "999999999" } },
    { "slot", "CUI_CDM_SlotIDPopup", function() mod.CDMO_ShowEquipmentSlotPopup(barKey, Record) end, { "", "0", "13", "14", "99" } },
    { "duration", "CUI_CDM_DurationPopup", function() mod.CDMO_ShowDurationPopup(12, Record) end, { "", "0", "7", "99999" } },
    { "duration empty", "CUI_CDM_DurationPopup", function() mod.CDMO_ShowDurationPopup(nil, Record) end, { "3" } },
    { "alpha", "CUI_CDM_AlphaPopup", function() mod.CDMO_ShowAlphaPopup(50, Record) end, { "", "0", "1", "50", "100", "101", "250" } },
    { "alpha titled", "CUI_CDM_AlphaPopup", function() mod.CDMO_ShowAlphaPopup(nil, Record, "Glow Opacity", "Hint here") end, { "30" } },
    { "threshold", "CUI_CDM_ThresholdSecondsPopup", function() mod.CDMO_ShowThresholdSecondsPopup(5, Record) end, { "", "0", "3", "60", "99" } },
    { "threshold titled", "CUI_CDM_ThresholdSecondsPopup", function() mod.CDMO_ShowThresholdSecondsPopup(nil, Record, "Other Title", "Other hint") end, { "4" } },
    { "icon", "CUI_CDM_CustomIconPopup", function() mod.ShowCDMCustomIconPopup(136081, Record) end, { "", "0", "134206", "123456789" } },
    { "icon empty", "CUI_CDM_CustomIconPopup", function() mod.ShowCDMCustomIconPopup(nil, Record) end, { "136085" } },
}

local function Kids(f, kind)
    local out = {}
    for _, c in ipairs(f["\0children"] or {}) do
        if c["\0kind"] == kind then out[#out + 1] = c end
    end
    return out
end
local function Fire(f, script, ...)
    local fn = f["\0scripts"] and f["\0scripts"][script]
    if not fn then return "none" end
    local ok, err = pcall(fn, f, ...)
    return ok and "ok" or ("ERR " .. tostring(err))
end

for _, case in ipairs(cases) do
    local label, name, open, inputs = case[1], case[2], case[3], case[4]
    got = nil
    open()
    local dialog = _G[name]
    local dimmer = _G[name .. "Dimmer"]
    if not (dialog and dimmer) then
        OUT:write("== " .. label .. " missing\n")
    else
        SNAP(label, dimmer)
        local box = Kids(dialog, "EditBox")[1]
        for _, text in ipairs(inputs) do
            got = nil
            open()
            box:SetText(text)
            Fire(box, "OnTextChanged", true)
            local r = Fire(box, "OnEnterPressed")
            HARNESS_ADVANCE(0.1)
            OUT:write("== " .. label .. " enter '" .. text .. "' " .. r .. " got=" .. tostring(got) .. " shown=" .. tostring(dimmer:IsShown()) .. "\n")
            SNAP(label .. " after '" .. text .. "'", dialog)
            HARNESS_ADVANCE(5)
        end
        for i, btn in ipairs(Kids(dialog, "Button")) do
            got = nil
            open()
            box:SetText(inputs[#inputs])
            Fire(btn, "OnEnter")
            SNAP(label .. " button " .. i .. " hover", btn)
            Fire(btn, "OnLeave")
            SNAP(label .. " button " .. i .. " left", btn)
            local r = Fire(btn, "OnClick", "LeftButton")
            OUT:write("== " .. label .. " button " .. i .. " click " .. r .. " got=" .. tostring(got) .. " shown=" .. tostring(dimmer:IsShown()) .. "\n")
        end
        open()
        local r = Fire(box, "OnEscapePressed")
        OUT:write("== " .. label .. " escape " .. r .. " shown=" .. tostring(dimmer:IsShown()) .. "\n")
        open()
        r = Fire(dimmer, "OnMouseDown", "LeftButton")
        OUT:write("== " .. label .. " dimmer click " .. r .. " shown=" .. tostring(dimmer:IsShown()) .. "\n")
    end
end
