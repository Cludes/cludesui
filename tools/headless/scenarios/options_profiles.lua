-- Profiles: each page built fresh; then, on the Profiles page, every visible
-- button clicked in turn (the page rebuilt fresh before each), with whatever
-- the click opens snapped and the profile list written out after it.
local CUI = rawget(_G, "CludesUI")
local function Hosts()
    local hosts = { UIParent }
    if CUI.OverlayParent and CUI.OverlayParent() ~= UIParent then hosts[2] = CUI.OverlayParent() end
    return hosts
end
local function Shown()
    local set = {}
    for _, host in ipairs(Hosts()) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() then set[c] = true end
        end
    end
    return set
end
-- What is on screen at the start (the panel itself) stays; anything a click
-- opened since is closed before the next rebuild.
local baseline = Shown()
local function Rebuild(page)
    for _, host in ipairs(Hosts()) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() and not baseline[c] then
                c:Hide()
            end
        end
    end
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("_CUIProfiles")
    CUI:SelectPage(page)
end
local function Buttons(root)
    local out, stack = {}, { root }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and f:IsVisible() and f["\0scripts"].OnClick then out[#out + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
local function Profiles()
    local db = rawget(_G, "CludesUIDB")
    local names = {}
    for k in pairs(db and db.profiles or {}) do names[#names + 1] = tostring(k) end
    table.sort(names)
    return table.concat(names, ",") .. " active=" .. tostring(db and db.activeProfile)
end
for _, page in ipairs({ "Profiles", "Overrides", "Full Export" }) do
    Rebuild(page)
    SNAP("page " .. page, CUI._scrollFrame)
    SNAP("header " .. page, CUI._contentHeader or CUI._headerFrame)
end
Rebuild("Profiles")
local n = #Buttons(CUI._scrollFrame)
OUT:write("== buttons " .. n .. "\n")
for i = 1, n do
    Rebuild("Profiles")
    local b = Buttons(CUI._scrollFrame)[i]
    if b then
        local before = Shown()
        local ok, err = pcall(b["\0scripts"].OnClick, b, "LeftButton")
        OUT:write("== click " .. i .. (ok and "" or (" ERR " .. tostring(err))) .. " " .. Profiles() .. "\n")
        for _, host in ipairs(Hosts()) do
            for _, c in ipairs({ host:GetChildren() }) do
                if c:IsShown() and not before[c] then
                    SNAP("click " .. i .. " opened", c)
                    c:Hide()
                end
            end
        end
    end
end
Rebuild("Profiles")
SNAP("again", CUI._scrollFrame)
