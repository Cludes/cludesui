-- Resource Bars threshold editor: every bar section's Settings button
-- clicked open on the bars page (entries list and detail pane), with a
-- threshold entry, hash lines and bands set, then closed again.
local CUI = rawget(_G, "CludesUI")
local db = rawget(_G, "_CURB_AceDB")
local p = db and db.profile
for _, key in ipairs({ "primary", "health", "secondary" }) do
    local bar = p and p[key]
    if bar then
        bar.thresholdSpecs = { { specIDs = { 0 }, thresholdPct = 35, thresholdCount = 3, thresholdR = 0.9, thresholdG = 0.1,
            thresholdB = 0.1, hashValues = "20, 40", hashMode = "percent", bands = { { to = 50, r = 0, g = 1, b = 0, a = 1 } } } }
    end
end
CUI:SelectModule("CludesUIResourceBars")
CUI:SelectPage("Class, Power and Health Bars")
local function Find(root, test, out)
    out = out or {}
    if type(root) == "table" and rawget(root, "__children") then
        if test(root) then out[#out + 1] = root end
        for _, c in ipairs(root.__children) do Find(c, test, out) end
        for _, r in ipairs(root.__regions or {}) do Find(r, test, out) end
    end
    return out
end
local function HasText(f, text)
    for _, r in ipairs(f.__regions or {}) do
        if r.__kind == "FontString" and r.__v and r.__v.Text == text then return true end
    end
    return false
end
local buttons = Find(CUI._scrollFrame, function(f)
    return f.__kind == "Button" and f.__scripts.OnClick and HasText(f, "Settings")
end)
OUT:write("== settings buttons: ", #buttons, "\n")
for i, b in ipairs(buttons) do
    b.__scripts.OnClick(b, "LeftButton")
    SNAP("thr editor " .. i, CUI._scrollFrame)
    local closes = Find(CUI._scrollFrame, function(f)
        return f.__kind == "Button" and f.__scripts.OnClick and f.__shown and HasText(f, "Done")
    end)
    if closes[1] then closes[1].__scripts.OnClick(closes[1], "LeftButton") end
end
