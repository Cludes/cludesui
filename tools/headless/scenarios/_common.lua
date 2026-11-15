-- Shared helpers for the Info Bar scenarios (dofile'd after the prelude).
-- The scenario sets H.OUT = OUT (the prelude's output file is local to it).
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIDataBars
local H = { mod = mod }
BreakUpLargeNumbers = tostring
DRAWS = 0
local setFont = mod.SetFont
mod.SetFont = function(...)
    DRAWS = DRAWS + 1
    return setFont(...)
end
function H.Block(kind)
    H.bar = mod.BarsInOrder()[1] or mod.CreateBar("empty")
    H.b = mod.AddBlock(H.bar.id, kind)
    H.b.settings = H.b.settings or {}
    return H.b
end
function H.Bar() return rawget(_G, "CludesUIDataBarsBar" .. H.bar.id) end
function H.Show(label)
    mod.ApplyBar(H.bar.id)
    SNAP(label, H.Bar())
end
function H.Buttons()
    local found = {}
    local stack = { H.Bar() }
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and f["\0scripts"].OnEnter and f["\0shown"] then found[#found + 1] = f end
            for _, c in ipairs(f["\0children"]) do stack[#stack + 1] = c end
        end
    end
    return found
end
function H.Hover(label, index)
    local list = H.Buttons()
    local h = list[index or #list]
    if not h then H.OUT:write("== " .. label .. ": nothing to hover\n") return end
    h["\0scripts"].OnEnter(h)
    SNAP(label, H.Bar())
    SNAP(label .. " tooltip", rawget(_G, "CludesUIDataBarsTip"))
    h["\0scripts"].OnLeave(h)
    SNAP(label .. " left", H.Bar())
end
function H.Count(label, fn)
    local before = DRAWS
    fn()
    H.OUT:write("== draws, " .. label .. ": ", DRAWS - before, "\n")
end
function H.Vertical(label)
    H.bar.orientation = "V"
    H.Show(label)
    H.bar.orientation = "H"
    mod.ApplyBar(H.bar.id)
end
return H
