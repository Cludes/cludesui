local addonName, ns = ...
if ns.standalone then return end
-- Core.lua is loaded before this file (see TOC), so ns.K and ns.DB exist.

-- ── Fonts ──────────────────────────────────────────────────────────────────
-- Font choice works the same way as the alert sound: a name is looked up in
-- LibSharedMedia when another addon provides it, which makes every font any
-- addon has registered available here, and nothing has to be bundled. The
-- built-in game fonts remain as the fallback list.
local function GetLSM()
    if not LibStub then return nil end
    local ok, LSM = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok and LSM and LSM.Fetch then return LSM end
    return nil
end

-- {id = <name or path>, label = <display>} for every font that can be chosen.
function ns.FontList()
    local list = {}
    local seen = {}
    for _, f in ipairs(ns.K.FONT_FACES) do
        list[#list + 1] = {id = f.id, label = f.label}
        seen[f.label:lower()] = true
    end

    local LSM = GetLSM()
    if LSM and LSM.List then
        local ok, names = pcall(LSM.List, LSM, "font")
        if ok and type(names) == "table" then
            for _, name in ipairs(names) do
                if type(name) == "string" and not seen[name:lower()] then
                    seen[name:lower()] = true
                    list[#list + 1] = {id = name, label = name}
                end
            end
        end
    end
    return list
end

-- Resolves the stored setting to a usable font file path. Older configs store
-- a path directly, newer ones store a LibSharedMedia name.
function ns.FontPath()
    local value = ns.DB().fontFace
    if value == nil then
        -- No font chosen: follow the CludesUI global font.
        local path = CludesUI and CludesUI.GetFontPath and CludesUI.GetFontPath()
        if type(path) == "string" and path ~= "" then return path end
        value = ns.K.DEFAULT_FONT_FACE
    end
    if type(value) ~= "string" or value == "" then return ns.K.DEFAULT_FONT_FACE end
    if value:find("\\", 1, true) or value:find("/", 1, true) then return value end

    local LSM = GetLSM()
    if LSM then
        local ok, path = pcall(LSM.Fetch, LSM, "font", value, true)
        if ok and type(path) == "string" and path ~= "" then return path end
    end
    return ns.K.DEFAULT_FONT_FACE
end

function ns.FontFlags()
    local flags = ns.DB().fontFlags
    for _, f in ipairs(ns.K.FONT_FLAGS) do
        if f.id == flags then return f.flags end
    end
    return "OUTLINE"
end

-- Per-element text colour, stored as {r, g, b}.
function ns.FontColor(key)
    local stored  = ns.DB()[key]
    local default = ns.K.FONT_COLOR_DEFAULTS[key] or {1, 1, 1}
    if type(stored) ~= "table" then return default[1], default[2], default[3] end
    return tonumber(stored[1]) or default[1],
           tonumber(stored[2]) or default[2],
           tonumber(stored[3]) or default[3]
end

function ns.SetFontColor(key, r, g, b)
    ns.DB()[key] = {r, g, b}
end
