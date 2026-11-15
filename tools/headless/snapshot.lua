-------------------------------------------------------------------------------
--  snapshot.lua - what a frame tree shows, as text, for comparing two
--  versions of the code (tools/headless/compare.py).
--
--  Snapshot(root) -> lines, one per frame or region under root, in creation
--  order: its path (kind and index under its parent), whether it is shown,
--  size, anchors (other frames named by their path), text, font, colours,
--  alpha, texture, and which scripts it has. Numbers are rounded to 3
--  places so two equal results print equal.
-------------------------------------------------------------------------------
local Snapshot = {}

local function Num(v)
    if type(v) ~= "number" then return tostring(v) end
    local s = string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end

local function Value(v, paths)
    if type(v) == "table" then
        if paths[v] then return "@" .. paths[v] end
        if rawget(v, "\0kind") then return "@" .. (v["\0name"] or v["\0kind"]) end
        local parts = {}
        for i = 1, #v do parts[i] = Value(v[i], paths) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return Num(v)
end

-- The fields worth comparing, in a fixed order.
local FIELDS = { "Text", "Font", "TextColor", "ColorTexture", "VertexColor", "Gradient", "Alpha", "Texture",
    "Atlas", "TexCoord", "JustifyH", "FrameStrata", "FrameLevel", "Scale", "DrawLayer", "Desaturated" }

function Snapshot.Take(root, label)
    local paths, order = {}, {}
    local function Walk(o, path)
        paths[o] = path
        order[#order + 1] = o
        local kids = rawget(o, "\0children") or {}
        local regions = rawget(o, "\0regions") or {}
        for i, r in ipairs(regions) do Walk(r, path .. "/" .. r["\0kind"] .. i) end
        for i, c in ipairs(kids) do Walk(c, path .. "/" .. c["\0kind"] .. i) end
    end
    Walk(root, label or "root")
    local lines = {}
    for _, o in ipairs(order) do
        local bits = { paths[o], o["\0kind"], o["\0shown"] and "shown" or "hidden", Num(o["\0w"]) .. "x" .. Num(o["\0h"]) }
        for _, p in ipairs(o["\0points"] or {}) do
            local parts = {}
            for i = 1, #p do parts[i] = Value(p[i], paths) end
            bits[#bits + 1] = "pt(" .. table.concat(parts, ",") .. ")"
        end
        for _, k in ipairs(FIELDS) do
            local v = o["\0v"][k]
            if v ~= nil then bits[#bits + 1] = k .. "=" .. Value(v, paths) end
        end
        local scripts = {}
        for s in pairs(o["\0scripts"] or {}) do scripts[#scripts + 1] = s end
        table.sort(scripts)
        if #scripts > 0 then bits[#bits + 1] = "scripts=" .. table.concat(scripts, ",") end
        lines[#lines + 1] = table.concat(bits, " ")
    end
    return lines
end

-- Runs every OnUpdate under root for n frames of dt seconds (animations settle).
function Snapshot.Settle(root, n, dt)
    for _ = 1, n or 30 do
        local stack = { root }
        while #stack > 0 do
            local o = table.remove(stack)
            if rawget(o, "\0shown") ~= false then
                local up = o["\0scripts"] and o["\0scripts"].OnUpdate
                if up then pcall(up, o, dt or 0.02) end
                for _, c in ipairs(rawget(o, "\0children") or {}) do stack[#stack + 1] = c end
            end
        end
    end
end

return Snapshot
