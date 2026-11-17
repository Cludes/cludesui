-- The two filter editors (Raid Frames' Buff Manager and Player Aura Bars):
-- each opened and snapped, then every visible button in it clicked, the
-- editor opened fresh before each, with any popup the click opened snapped
-- and closed and the editor's filter list written out after.
local CUI = rawget(_G, "CludesUI")
local NS = CUI._ModuleNS or {}
local function Find(root, test)
    local out, stack = {}, { root }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if test(f) then out[#out + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
local function Dump(v, depth)
    if type(v) ~= "table" then
        if type(v) == "number" then return string.format("%.3f", v) end
        return tostring(v)
    end
    if depth > 6 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(v[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function Hosts()
    local hosts = { UIParent }
    if CUI.OverlayParent and CUI.OverlayParent() ~= UIParent then hosts[2] = CUI.OverlayParent() end
    return hosts
end
local function ShownTops()
    local set = {}
    for _, host in ipairs(Hosts()) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() then set[c] = true end
        end
    end
    return set
end

local editors = {
    {
        label = "raid frames",
        mod = NS["CludesUIRaidFrames"],
        open = "BMP_ShowFilterEditor",
        key = "_bm2FilterEditor",
        filters = "BM2_Filters",
    },
    {
        label = "aura bars",
        mod = NS["CludesUIUnitFrames"],
        open = "PABMP_ShowFilterEditor",
        key = "_pabFilterEditor",
        filters = "PAB_Filters",
    },
}
for _, ed in ipairs(editors) do
    local m = ed.mod
    local function Open()
        if m[ed.key] and m[ed.key].Hide then m[ed.key]:Hide() end
        local ok, err = pcall(m[ed.open])
        if not ok then OUT:write("   ERR open " .. tostring(err) .. "\n") end
        return m[ed.key]
    end
    local function DumpFilters()
        local f = m[ed.filters] and m[ed.filters]()
        OUT:write("   filters " .. Dump(f, 0) .. "\n")
    end
    local function Buttons(root)
        return Find(root, function(f)
            return f["\0kind"] == "Button" and f:IsVisible() and f["\0scripts"].OnClick ~= nil
        end)
    end
    if m and m[ed.open] then
        local ui = Open()
        OUT:write("== " .. ed.label .. " editor " .. tostring(ui ~= nil) .. "\n")
        if ui then
            SNAP(ed.label .. " editor", ui)
            DumpFilters()
            local n = #Buttons(ui)
            OUT:write("== " .. ed.label .. " buttons " .. n .. "\n")
            for i = 1, n do
                ui = Open()
                local b = ui and Buttons(ui)[i]
                if b then
                    local before = ShownTops()
                    local ok, err = pcall(b["\0scripts"].OnClick, b, "LeftButton")
                    OUT:write("== " .. ed.label .. " click " .. i .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
                    HARNESS_ADVANCE(0.1)
                    local k = 0
                    for _, host in ipairs(Hosts()) do
                        for _, c in ipairs({ host:GetChildren() }) do
                            if c:IsShown() and not before[c] and c ~= m[ed.key] then
                                k = k + 1
                                SNAP(ed.label .. " click " .. i .. " popup " .. k, c)
                                c:Hide()
                            end
                        end
                    end
                    if m[ed.key] and m[ed.key]:IsShown() then SNAP(ed.label .. " click " .. i .. " editor", m[ed.key]) end
                    DumpFilters()
                end
            end
            if m[ed.key] then m[ed.key]:Hide() end
        end
    else
        OUT:write("== " .. ed.label .. " editor missing\n")
    end
end
