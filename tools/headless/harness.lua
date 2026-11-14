-------------------------------------------------------------------------------
--  Headless load test for CludesUI.
--
--  Runs the suite's real Lua files under LuaJIT against a fake WoW client:
--  loads every addon in TOC order, fires the login events, drains the timers,
--  then opens the options panel and builds every page of every module.
--  It reports Lua errors. It cannot check anything visual, and the fake
--  client differs from the real one, so a clean run is not proof.
--
--  Usage (from the repo root):
--    luajit tools/headless/harness.lua [retail|forever] [CLASS] [-v]
-------------------------------------------------------------------------------
local FLAVOR  = arg[1] or "retail"
local CLASS   = arg[2] or "PALADIN"
local VERBOSE = arg[3] == "-v"
local ROOT    = "."

local realG = _G
local unpack = unpack

-------------------------------------------------------------------------------
--  Error collection
-------------------------------------------------------------------------------
local errors, errorSeen, phase = {}, {}, "boot"
-- Code that works on Blizzard's own frames (skinning their windows, hiding
-- their bars) meets stand-ins here, so its errors say nothing about the game.
local LIMITS = { "CludesUIBlizzardSkin/", "CludesUIBlizzardSkin_", "CUI_BlizzardSkin_", "CludesUIFriends/CludesUIFriends.lua",
    "CUI_Chat_Skin.lua", "CUI_ActionBars_Disposal.lua", "CUI_ActionBars_Setup.lua", "CUI_ActionBars_ButtonArt.lua" }
local function IsLimit(e)
    local text = e.msg .. (e.trace or "")
    for _, p in ipairs(LIMITS) do if text:find(p, 1, true) then return true end end
    return false
end
local function Record(msg, trace)
    msg = tostring(msg)
    local key = msg:gsub("%d+", "#")
    if errorSeen[key] then errorSeen[key].count = errorSeen[key].count + 1 return end
    local e = { msg = msg, phase = phase, trace = trace, count = 1 }
    errorSeen[key] = e
    errors[#errors + 1] = e
end
local function Handler(msg)
    Record(msg, debug.traceback("", 2))
    return msg
end
local function Safe(fn, ...)
    return xpcall(fn, Handler, ...)
end

-------------------------------------------------------------------------------
--  Fake widgets
-------------------------------------------------------------------------------
local Obj = {}
local methods = {}
local clock = 1000

local function New(kind, name, parent)
    local o = setmetatable({ __kind = kind, __name = name, __parent = parent, __shown = true,
        __scripts = {}, __v = {}, __points = {}, __children = {}, __regions = {}, __w = 0, __h = 0 }, Obj)
    if parent and type(parent) == "table" and parent.__children then
        if kind == "Texture" or kind == "FontString" or kind == "MaskTexture" or kind == "Line" then
            parent.__regions[#parent.__regions + 1] = o
        else
            parent.__children[#parent.__children + 1] = o
        end
    end
    return o
end

local function Fire(o, script, ...)
    local fn = o.__scripts[script]
    if fn then Safe(fn, o, ...) end
end

function methods.GetObjectType(o) return o.__kind end
function methods.IsObjectType(o, t) return o.__kind == t or t == "Frame" or t == "Region" end
function methods.GetName(o) return o.__name end
function methods.GetDebugName(o) return o.__name or o.__kind end
function methods.GetParent(o) return o.__parent end
function methods.SetParent(o, p) o.__parent = p end
function methods.GetChildren(o) return unpack(o.__children) end
function methods.GetNumChildren(o) return #o.__children end
function methods.GetRegions(o) return unpack(o.__regions) end
function methods.GetNumRegions(o) return #o.__regions end
function methods.IsShown(o) return o.__shown end
function methods.IsVisible(o)
    local p = o
    while p and type(p) == "table" and p.__kind do
        if not p.__shown then return false end
        p = p.__parent
    end
    return true
end
function methods.Show(o) if not o.__shown then o.__shown = true; Fire(o, "OnShow") end end
function methods.Hide(o) if o.__shown then o.__shown = false; Fire(o, "OnHide") end end
function methods.SetShown(o, v) if v then methods.Show(o) else methods.Hide(o) end end
function methods.SetScript(o, s, fn) o.__scripts[s] = fn end
function methods.GetScript(o, s) return o.__scripts[s] end
function methods.HasScript() return true end
function methods.HookScript(o, s, fn)
    local old = o.__scripts[s]
    o.__scripts[s] = old and function(...) old(...); return fn(...) end or fn
end
function methods.SetSize(o, w, h) o.__w, o.__h = tonumber(w) or 0, tonumber(h) or 0 end
function methods.SetWidth(o, w) o.__w = tonumber(w) or 0 end
function methods.SetHeight(o, h) o.__h = tonumber(h) or 0 end
function methods.GetWidth(o) return o.__w end
function methods.GetHeight(o) return o.__h end
function methods.GetSize(o) return o.__w, o.__h end
function methods.SetPoint(o, ...) o.__points[#o.__points + 1] = { ... } end
function methods.SetAllPoints(o, rel) o.__points = { { "TOPLEFT", rel }, { "BOTTOMRIGHT", rel } } end
function methods.ClearAllPoints(o) o.__points = {} end
function methods.GetNumPoints(o) return #o.__points end
function methods.GetPoint(o, i)
    local p = o.__points[i or 1]
    if not p then return nil end
    local point, a, b, c, d = p[1], p[2], p[3], p[4], p[5]
    -- SetPoint's short forms: (point), (point, x, y), (point, rel), (point, rel, x, y), (point, rel, relPoint, x, y)
    if type(a) == "number" then return point, o.__parent, point, a, b or 0 end
    if type(b) == "number" then return point, a, point, b, c or 0 end
    return point, a or o.__parent, b or point, c or 0, d or 0
end
function methods.GetLeft() return 100 end
function methods.GetRight(o) return 100 + o.__w end
function methods.GetTop() return 500 end
function methods.GetBottom(o) return 500 - o.__h end
function methods.GetCenter(o) return 100 + o.__w / 2, 500 - o.__h / 2 end
function methods.GetRect(o) return 100, 500 - o.__h, o.__w, o.__h end
function methods.GetScaledRect(o) return 100, 500 - o.__h, o.__w, o.__h end
function methods.GetScale() return 1 end
function methods.GetEffectiveScale() return 1 end
function methods.GetAlpha(o) return o.__v.Alpha or 1 end
function methods.GetEffectiveAlpha() return 1 end
function methods.GetFrameLevel(o) return o.__v.FrameLevel or 1 end
function methods.GetFrameStrata(o) return o.__v.FrameStrata or "MEDIUM" end
function methods.GetDrawLayer(o) return o.__v.DrawLayer or "ARTWORK", 0 end
function methods.GetText(o) return o.__v.Text end
-- The client refuses text on a FontString that has no font yet.
local function NeedFont(o, fn)
    if o.__kind == "FontString" and not o.__v.Font then error("FontString:" .. fn .. "(): Font not set", 3) end
end
function methods.SetText(o, t) NeedFont(o, "SetText"); o.__v.Text = t ~= nil and tostring(t) or nil end
function methods.SetFormattedText(o, f, ...) NeedFont(o, "SetFormattedText"); o.__v.Text = string.format(f, ...) end
function methods.SetFontObject(o, f) o.__v.Font = o.__v.Font or { "Fonts/FRIZQT__.TTF", 12, "" } end
function methods.GetStringWidth(o) return #(o.__v.Text or "") * 7 end
function methods.GetUnboundedStringWidth(o) return #(o.__v.Text or "") * 7 end
function methods.GetStringHeight() return 12 end
function methods.GetLineHeight() return 12 end
function methods.GetNumLines() return 1 end
function methods.IsTruncated() return false end
function methods.SetFont(o, path, size, flags) o.__v.Font = { path, size, flags }; return true end
function methods.GetFont(o) local f = o.__v.Font or { "Fonts/FRIZQT__.TTF", 12, "" }; return f[1], f[2], f[3] end
function methods.GetTextColor() return 1, 1, 1, 1 end
function methods.GetVertexColor() return 1, 1, 1, 1 end
function methods.GetShadowColor() return 0, 0, 0, 1 end
function methods.GetShadowOffset() return 0, 0 end
function methods.GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
function methods.GetMinMaxValues(o) return o.__v.Min or 0, o.__v.Max or 1 end
function methods.SetMinMaxValues(o, a, b) o.__v.Min, o.__v.Max = a, b end
function methods.GetValue(o) return o.__v.Value or 0 end
function methods.GetVerticalScroll(o) return o.__v.VerticalScroll or 0 end
function methods.GetHorizontalScroll() return 0 end
function methods.GetVerticalScrollRange() return 0 end
function methods.GetHorizontalScrollRange() return 0 end
function methods.GetScrollChild(o) return o.__v.ScrollChild end
function methods.GetChecked(o) return o.__v.Checked and true or false end
function methods.GetAttribute(o, k) return o.__attr and o.__attr[k] end
function methods.SetAttribute(o, k, v) o.__attr = o.__attr or {}; o.__attr[k] = v end
function methods.GetID(o) return o.__v.ID or 0 end
function methods.GetNumber(o) return tonumber(o.__v.Text) or 0 end
function methods.GetCursorPosition() return 0 end
function methods.GetNumLetters(o) return #(o.__v.Text or "") end
function methods.GetOwner() return nil end
function methods.GetUnit() return nil end
function methods.GetItem() return nil end
function methods.GetSpell() return nil end
function methods.NumLines() return 0 end
function methods.GetHitRectInsets() return 0, 0, 0, 0 end
function methods.GetClampRectInsets() return 0, 0, 0, 0 end
function methods.GetBackdrop() return nil end
function methods.GetBackdropColor() return 0, 0, 0, 1 end
function methods.GetBackdropBorderColor() return 1, 1, 1, 1 end
function methods.GetTexture(o) return o.__v.Texture end
function methods.GetAtlas(o) return o.__v.Atlas end
function methods.GetDuration() return 0 end
function methods.GetProgress() return 0 end
function methods.GetCooldownTimes() return 0, 0 end
function methods.GetCooldownDuration() return 0 end
function methods.IsEnabled(o) return o.__v.Enabled ~= false end
function methods.IsMouseEnabled(o) return o.__v.MouseEnabled and true or false end
function methods.EnableMouse(o, v) o.__v.MouseEnabled = v end
function methods.RegisterEvent(o, e) o.__events = o.__events or {}; o.__events[e] = true; return true end
function methods.RegisterUnitEvent(o, e) o.__events = o.__events or {}; o.__events[e] = true; return true end
function methods.UnregisterEvent(o, e) if o.__events then o.__events[e] = nil end end
function methods.UnregisterAllEvents(o) o.__events = nil end
function methods.IsEventRegistered(o, e) return o.__events and o.__events[e] or false end
function methods.CreateTexture(o, name) local t = New("Texture", name, o); if name then realG[name] = t end; return t end
function methods.CreateMaskTexture(o) return New("MaskTexture", nil, o) end
function methods.CreateLine(o) return New("Line", nil, o) end
function methods.CreateFontString(o, name, layer, inherits)
    local t = New("FontString", name, o)
    if inherits then t.__v.Font = { "Fonts/FRIZQT__.TTF", 12, "" } end
    if name then realG[name] = t end
    return t
end
function methods.CreateAnimationGroup(o) return New("AnimationGroup", nil, o) end
function methods.CreateAnimation(o, kind) return New(kind or "Animation", nil, o) end
function methods.GetAnimations(o) return unpack(o.__children) end
function methods.GetAnimationGroups() end
function methods.GetCountdownFormatter() return New("Frame") end
function methods.IsPlaying() return false end
function methods.IsForbidden() return false end
function methods.IsProtected() return false end
function methods.IsAnchoringRestricted() return false end
function methods.CanChangeProtectedState() return true end
function methods.Acquire() return New("Frame") end
function methods.ScrollToBottom() end
function methods.ScrollToTop() end
function methods.EnumerateActive() return function() end end

local OBJECT_SUFFIX = { "Texture", "FontString", "Frame", "Child", "Thumb", "Button", "EditBox", "Group", "Bar", "Region", "ScrollBar", "Model" }

-- Real widgets share a method table (code reads getmetatable(obj).__index.X),
-- so the methods are a table and only unknown names fall to the generator.
local VERBS = { "Register", "Unregister", "Play", "Stop", "Pause", "Finish", "Raise", "Lower", "Click", "Lock", "Unlock",
    "Start", "Add", "Remove", "Insert", "Highlight", "Execute", "Wrap", "Unwrap", "Run", "Rotate", "Adjust",
    "Interrupt", "Restart", "Release", "Reset", "Abort", "Copy", "Advance", "Replace", "Force", "Stretch", "Drop", "Desaturate", "Continue" }
Obj.__index = methods
setmetatable(methods, { __index = function(_, k)
    if type(k) ~= "string" then return nil end
    -- Fields the code set itself are raw; anything else that looks like a
    -- widget method gets a stand-in made from its name.
    if k:find("^Set") or k:find("^Enable") or k:find("^Disable") or k:find("^Clear") then
        local key = k:gsub("^Set", "")
        local f = function(self, v) self.__v[key] = v end
        methods[k] = f
        return f
    end
    if k:find("^Get") then
        local key = k:gsub("^Get", "")
        local wantsObject = false
        for _, s in ipairs(OBJECT_SUFFIX) do if key:find(s .. "$") then wantsObject = true break end end
        local isColor = key:find("Color$") ~= nil
        local f = function(self)
            local v = self.__v[key]
            if v ~= nil and not (wantsObject and type(v) ~= "table") then return v end
            if wantsObject then
                local child = New(key:find("FontString$") and "FontString" or key:find("Texture$") and "Texture" or "Frame", nil, self)
                self.__v[key] = child
                return child
            end
            if isColor then return 1, 1, 1, 1 end
            return 0
        end
        methods[k] = f
        return f
    end
    if k:find("^Is") or k:find("^Has") or k:find("^Can") or k:find("^Does") then
        local f = function() return false end
        methods[k] = f
        return f
    end
    -- Other fields (button.Text, frame.Left) stay nil, as on a real widget;
    -- only names that start like a widget verb get a stand-in.
    for _, verb in ipairs(VERBS) do
        if k:find("^" .. verb) then
            local f = function() end
            methods[k] = f
            return f
        end
    end
    return nil
end })

-- Blizzard's own frames (made by the global fallback): a CamelCase field that
-- is not a method reads as a template child (FriendsListFrame.ScrollBox).
local CHILD_SUFFIX = { "Box", "Bar", "Button", "Text", "Icon", "Border", "Background", "NineSlice", "Bg", "Inset", "Container",
    "Frame", "Texture", "Title", "Portrait", "Highlight", "Tab", "Tabs", "Label", "Name", "Glow", "Arrow", "Overlay", "Mask",
    "Anchor", "List", "Header", "Footer", "Panel", "Slot", "Child", "Count", "Cooldown", "Divider", "Display", "EditBox" }
local BlizzObj = {}
local function NewBlizz(name, parent)
    local o = New("Frame", name, parent)
    return setmetatable(o, BlizzObj)
end
BlizzObj.__index = function(o, k)
    local m = methods[k]
    if m ~= nil then return m end
    if type(k) == "string" and k:find("^%u") then
        for _, s in ipairs(CHILD_SUFFIX) do
            if k:find(s .. "$") then
                local child = NewBlizz(nil, o)
                rawset(o, k, child)
                return child
            end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Fake globals
-------------------------------------------------------------------------------
local G = {}
local allFrames = {}

G.UIParent = New("Frame", "UIParent"); G.UIParent.__w, G.UIParent.__h = 1920, 1080
G.WorldFrame = New("Frame", "WorldFrame"); G.WorldFrame.__w, G.WorldFrame.__h = 1920, 1080

function G.CreateFrame(kind, name, parent, template)
    local f = New(kind or "Frame", name, parent)
    if kind == "ScrollFrame" or kind == "Slider" or kind == "StatusBar" then f.__v.Min, f.__v.Max = 0, 1 end
    if type(name) == "string" then realG[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end
function G.CreateFont(name) local f = New("Font", name); realG[name] = f; return f end
function G.CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1,
        GetRGB = function(s) return s.r, s.g, s.b end, GetRGBA = function(s) return s.r, s.g, s.b, s.a end,
        SetRGB = function(s, x, y, z) s.r, s.g, s.b = x, y, z end, SetRGBA = function(s, x, y, z, w) s.r, s.g, s.b, s.a = x, y, z, w end,
        GenerateHexColor = function() return "ffffffff" end, WrapTextInColorCode = function(_, t) return t end,
        IsEqualTo = function() return false end }
end
function G.CreateVector2D(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end

-- Lua extras WoW adds
G.strsplit = function(sep, s, n) local out = {}; for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end; return unpack(out) end
G.strsplittable = function(sep, s) return { G.strsplit(sep, s) } end
G.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
G.strconcat = function(...) return table.concat({ ... }) end
G.strmatch, G.strfind, G.strsub, G.strlen, G.strlower, G.strupper, G.strrep, G.strbyte, G.strchar, G.strrev, G.format, G.gsub, G.gmatch =
    string.match, string.find, string.sub, string.len, string.lower, string.upper, string.rep, string.byte, string.char, string.reverse, string.format, string.gsub, string.gmatch
do
    local rawformat = string.format
    local function wowformat(fmt, ...)
        if type(fmt) == "string" and fmt:find("%%%d+%$") then
            local args, out, n = { ... }, {}, 0
            fmt = fmt:gsub("%%(%d+)%$", function(i) n = n + 1; out[n] = args[tonumber(i)]; return "%" end)
            return rawformat(fmt, unpack(out, 1, n))
        end
        return rawformat(fmt, ...)
    end
    string.format, G.format = wowformat, wowformat
end
G.strlenutf8 = string.len
G.strcmputf8i = function(a, b) a, b = a:lower(), b:lower(); return a < b and -1 or a > b and 1 or 0 end
string.split, string.join, string.trim = G.strsplit, G.strjoin, G.strtrim
G.tinsert, G.tremove, G.sort, G.tconcat = table.insert, table.remove, table.sort, table.concat
G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = G.wipe
G.tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
G.tIndexOf = function(t, v) for i, x in ipairs(t) do if x == v then return i end end end
G.tInvert = function(t) local o = {}; for k, v in pairs(t) do o[v] = k end return o end
G.CopyTable = function(t, shallow) local o = {}; for k, v in pairs(t) do o[k] = (type(v) == "table" and not shallow) and G.CopyTable(v) or v end return o end
G.MergeTable = function(a, b) for k, v in pairs(b) do a[k] = v end return a end
G.Mixin = function(o, ...) for i = 1, select("#", ...) do local m = select(i, ...); if type(m) == "table" then for k, v in pairs(m) do o[k] = v end end end return o end
G.CreateFromMixins = function(...) return G.Mixin({}, ...) end
G.CreateAndInitFromMixin = function(m, ...) local o = G.Mixin({}, m); if o.Init then o:Init(...) end return o end
G.GenerateClosure = function(f, ...) local a = { ... }; return function(...) local b = { unpack(a) }; for i = 1, select("#", ...) do b[#b + 1] = (select(i, ...)) end return f(unpack(b)) end end
G.floor, G.ceil, G.abs, G.min, G.max, G.sqrt, G.sin, G.cos, G.random, G.mod, G.fmod, G.pow, G.exp, G.log =
    math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt, math.sin, math.cos, math.random, math.fmod, math.fmod, math.pow, math.exp, math.log
G.PI = math.pi
G.Clamp = function(v, a, b) return v < a and a or v > b and b or v end
G.Lerp = function(a, b, t) return a + (b - a) * t end
G.Saturate = function(v) return G.Clamp(v, 0, 1) end
G.Round = function(v) return math.floor(v + 0.5) end
G.tostringall = function(...) local o = {}; for i = 1, select("#", ...) do o[i] = tostring((select(i, ...))) end return unpack(o) end
G.date, G.time, G.difftime = os.date, os.time, os.difftime
G.GetTime = function() return clock end
G.GetTimePreciseSec = function() return clock end
G.GetServerTime = function() return os.time() end
G.debugprofilestop = function() return clock * 1000 end
-- debugstack(start, top, bottom) in the client's shape: the suite reads the
-- calling addon's folder out of it ("AddOns/<folder>/").
G.debugstack = function(start, top)
    start = (tonumber(start) or 1) + 1
    local out = {}
    for level = start, start + (tonumber(top) or 12) - 1 do
        local info = debug.getinfo(level, "Sln")
        if not info then break end
        out[#out + 1] = ("[%s]:%d: in function <%s>"):format(info.source:gsub("^@", ""), info.currentline or 0, info.name or "?")
    end
    return table.concat(out, "\n")
end
G.geterrorhandler = function() return function(msg) Record(msg, debug.traceback("", 2)) end end
G.seterrorhandler = function() end
G.CallErrorHandler = function(msg) Record(msg, debug.traceback("", 2)) end
G.securecall = function(f, ...) if type(f) == "string" then f = realG[f] end if f then return f(...) end end
G.securecallfunction = G.securecall
G.secureexecuterange = function(t, f, ...) for k, v in pairs(t) do f(k, v, ...) end end
G.issecure = function() return true end
G.issecurevariable = function() return true end
G.forceinsecure = function() end
G.issecretvalue = function() return false end
G.canaccessvalue = function() return true end
G.canaccesstable = function() return true end
G.hooksecurefunc = function(a, b, c)
    local t, name, fn = realG, a, b
    if type(a) == "table" then t, name, fn = a, b, c end
    local old = rawget(t, name) or t[name]
    if type(old) ~= "function" then return end
    rawset(t, name, function(...) local r = { old(...) }; fn(...); return unpack(r) end)
end
G.print = function(...) if VERBOSE then io.write("  [print] ", table.concat({ G.tostringall(...) }, " "), "\n") end end
G.nop = function() end

-- Timers: queued and drained by the harness on a fake clock.
local timers = {}
local function AddTimer(delay, fn, repeats)
    local t = { at = clock + (tonumber(delay) or 0), fn = fn, every = repeats and (tonumber(delay) or 0) or nil }
    t.Cancel = function(s) s.cancelled = true end
    t.IsCancelled = function(s) return s.cancelled or false end
    timers[#timers + 1] = t
    return t
end
G.AuraUtil = setmetatable({ AuraFilters = setmetatable({}, { __index = function(_, k) return tostring(k):upper() end }) }, {})
G.C_UIFileAsset = { IsKnownFile = function() return true end }
G.C_DateAndTime = setmetatable({
    GetCurrentCalendarTime = function() local d = os.date("*t"); return { year = d.year, month = d.month, monthDay = d.day, weekday = d.wday, hour = d.hour, minute = d.min } end,
    GetSecondsUntilWeeklyReset = function() return 3600 end, GetSecondsUntilDailyReset = function() return 3600 end,
    GetServerTimeLocal = function() return os.time() end,
}, { __index = function() return function() return 0 end end })
G.C_Timer = {
    After = function(d, fn) AddTimer(d, fn) end,
    NewTimer = function(d, fn) return AddTimer(d, fn) end,
    NewTicker = function(d, fn, n) return AddTimer(math.max(d, 0.5), fn, true) end,
}
local function Advance(seconds)
    local stop = clock + seconds
    for _ = 1, 4000 do
        table.sort(timers, function(a, b) return a.at < b.at end)
        local t = timers[1]
        if not t or t.at > stop then break end
        table.remove(timers, 1)
        clock = math.max(clock, t.at)
        if not t.cancelled then
            Safe(t.fn, t)
            if t.every and not t.cancelled then t.at = clock + math.max(t.every, 0.5); timers[#timers + 1] = t end
        end
    end
    clock = stop
end

-- Client identity
local IFACE = FLAVOR == "forever" and 16001 or 120105
G.GetBuildInfo = function() return FLAVOR == "forever" and "1.60.1" or "12.1.5", "99999", "Nov 1 2026", IFACE end
G.WOW_PROJECT_ID, G.WOW_PROJECT_MAINLINE, G.WOW_PROJECT_CLASSIC = 1, 1, 2
G.GetLocale = function() return "enUS" end
G.GetRealmName = function() return "TestRealm" end
G.GetNormalizedRealmName = function() return "TestRealm" end
G.GetCurrentRegion = function() return 1 end
G.GetCurrentRegionName = function() return "US" end
G.GetPhysicalScreenSize = function() return 1920, 1080 end
G.GetScreenWidth = function() return 1920 end
G.GetScreenHeight = function() return 1080 end
G.GetFramerate = function() return 60 end
G.GetCursorPosition = function() return 0, 0 end
G.InCombatLockdown = function() return false end
local loggedIn = false
G.IsLoggedIn = function() return loggedIn end
G.UnitClass = function() return CLASS:sub(1, 1) .. CLASS:sub(2):lower(), CLASS, 2 end
G.UnitClassBase = function() return CLASS, 2 end
G.UnitName = function(u) return u == "player" and "Tester" or nil, nil end
G.UnitNameUnmodified = G.UnitName
G.UnitFullName = function() return "Tester", "TestRealm" end
G.GetUnitName = function() return "Tester" end
G.UnitGUID = function(u) return u == "player" and "Player-1-00000001" or nil end
G.UnitRace = function() return "Human", "Human", 1 end
G.UnitSex = function() return 2 end
G.UnitFactionGroup = function() return "Alliance", "Alliance" end
G.UnitLevel = function() return FLAVOR == "forever" and 34 or 90 end
G.UnitExists = function(u) return u == "player" end
G.UnitHealth = function() return 100 end
G.UnitHealthMax = function() return 100 end
G.UnitPower = function() return 100 end
G.UnitPowerMax = function() return 100 end
G.UnitPowerType = function() return 0, "MANA" end
G.GetSpecialization = function() return 1 end
G.GetNumSpecializations = function() return 3 end
G.GetSpecializationInfo = function(i) return 65 + (i or 1), "Spec" .. (i or 1), "", 0, "DAMAGER" end
G.GetNumClasses = function() return 13 end
G.GetClassInfo = function(i) return "Class" .. i, "CLASS" .. i, i end
G.GetNumGroupMembers = function() return 0 end
G.GetNumSubgroupMembers = function() return 0 end
G.GetInstanceInfo = function() return "World", "none", 0, "", 0, 0, false, 0, 0 end
G.IsInInstance = function() return false, "none" end
G.GetCVar = function() return "1" end
G.GetCVarBool = function() return false end
G.GetCVarDefault = function() return "1" end
G.SetCVar = function() end
G.GetBindingKey = function() return nil end
G.GetBindingText = function(k) return k or "" end
G.GetMoney = function() return 0 end
G.GetNumAddOns = function() return 0 end
G.PlaySound = function() end
G.PlaySoundFile = function() end
G.RAID_CLASS_COLORS = setmetatable({}, { __index = function(t, k)
    local c = G.CreateColor(1, 1, 1, 1); c.colorStr = "ffffffff"; rawset(t, k, c); return c end })
G.CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
G.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end })
G.LOCALIZED_CLASS_NAMES_FEMALE = G.LOCALIZED_CLASS_NAMES_MALE
G.CLASS_SORT_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
G.NUM_CHAT_WINDOWS, G.MAX_PLAYER_LEVEL, G.NUM_BAG_SLOTS, G.MAX_BOSS_FRAMES, G.MAX_RAID_MEMBERS, G.MAX_PARTY_MEMBERS = 10, 90, 4, 8, 40, 4
G.NUM_ACTIONBAR_BUTTONS, G.NUM_PET_ACTION_SLOTS, G.NUM_STANCE_SLOTS, G.NUM_BANKBAGSLOTS, G.BACKPACK_CONTAINER = 12, 10, 10, 7, 0
G.INVSLOT_FIRST_EQUIPPED, G.INVSLOT_LAST_EQUIPPED, G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 1, 19, 5
G.SlashCmdList = {}
G.StaticPopupDialogs = {}
G.UISpecialFrames = {}
G.UIPanelWindows = {}
G.ChatTypeInfo = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
G.ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff", color = G.CreateColor(1, 1, 1, 1) } end })
G.STANDARD_TEXT_FONT, G.UNIT_NAME_FONT, G.DAMAGE_TEXT_FONT, G.NAMEPLATE_FONT = "Fonts/FRIZQT__.TTF", "Fonts/FRIZQT__.TTF", "Fonts/FRIZQT__.TTF", "Fonts/FRIZQT__.TTF"
G.PixelUtil = setmetatable({
    SetPoint = function(r, ...) r:SetPoint(...) end, SetSize = function(r, w, h) r:SetSize(w, h) end,
    SetWidth = function(r, w) r:SetWidth(w) end, SetHeight = function(r, h) r:SetHeight(h) end,
    GetPixelToUIUnitFactor = function() return 1 end, GetNearestPixelSize = function(v) return v end,
    ConvertPixelsToUI = function(v) return v end,
}, { __index = function() return function() return 0 end end })

-- Addon registry (filled by the loader below)
local addons, addonOrder, LoadAddon = {}, {}, nil
local function AddonInfo(a) local e = type(a) == "number" and addons[addonOrder[a]] or addons[a]; return e end
G.C_AddOns = {
    GetNumAddOns = function() return #addonOrder end,
    GetAddOnInfo = function(a) local e = AddonInfo(a); if e then return e.name, e.title or e.name, "", true, "", "INSECURE", false end end,
    IsAddOnLoaded = function(a) local e = AddonInfo(a); return e and e.loaded or false, e and e.loaded or false end,
    IsAddOnLoadable = function(a) return AddonInfo(a) ~= nil end,
    IsAddOnLoadOnDemand = function(a) local e = AddonInfo(a); return e and e.lod or false end,
    GetAddOnEnableState = function(a) return AddonInfo(a) and 2 or 0 end,
    GetAddOnMetadata = function(a, key) local e = AddonInfo(a); return e and e.meta[key] end,
    DoesAddOnExist = function(a) return AddonInfo(a) ~= nil end,
    DoesAddOnHaveLoadError = function() return false end,
    GetAddOnDependencies = function() end, GetAddOnOptionalDependencies = function() end,
    EnableAddOn = function() end, DisableAddOn = function() end, SaveAddOns = function() end,
    LoadAddOn = function(a) local e = AddonInfo(a); if not e then return false, "MISSING" end; LoadAddon(e.name); return true end,
}
G.IsAddOnLoaded, G.LoadAddOn, G.GetAddOnMetadata = G.C_AddOns.IsAddOnLoaded, G.C_AddOns.LoadAddOn, G.C_AddOns.GetAddOnMetadata

-- Names that must read as absent: the suite's own flags and saved variables,
-- and other addons it only checks for.
local ABSENT_PREFIX = { "^CUI", "^CludesUI", "^SLASH_", "^BINDING_", "^_" }
local ABSENT = {}
for _, n in ipairs({ "ElvUI", "Details", "BigWigs", "DBM", "WeakAuras", "Plater", "Masque", "LibStub", "Clique", "OmniCC", "TomTom",
    "Bartender4", "Dominos", "MRT", "VMRT", "Skada", "Recount", "BugSack", "BugGrabber", "Questie", "Auctionator", "TSM_API",
    "Baganator", "Syndicator", "Cell", "Grid2", "VuhDo", "HealBot", "ShadowUF", "PitBull4", "Tukui", "NDui", "AceLibrary",
    "ACP", "RaiderIO", "Leatrix_Plus", "Leatrix_Maps", "Postal", "Bagnon", "AdiBags", "ArkInventory", "Hekili", "KuiNameplates",
    "TidyPlates", "NeatPlates", "Kui_Nameplates", "SexyMap", "MBB", "Prat", "Chattynator", "Glass", "XPerl", "oUF", "LibDBIcon",
    "ClickCastFrames", "ClickCastHeader", "NSRT", "NorthernSkyRaidTools", "NaowhQOL", "Elles" .. "mereUI", "Elles" .. "mereUIDB", "MethodRaidTools", "Narcissus", "TRP3_API" }) do ABSENT[n] = true end

local FRAME_SUFFIX = { "Frame", "Button", "Tooltip", "Bar", "Container", "Manager", "Parent", "Minimap", "EditBox", "Panel", "Tracker", "Cluster", "Anchor", "Flyout", "Menu" }
local FUNCTION_VERBS = { "Get", "Set", "Is", "Has", "Can", "Create", "Update", "Toggle", "Show", "Hide", "Close", "Open",
    "Register", "Unregister", "Play", "Stop", "Add", "Remove", "Select", "Click", "Load", "Reset", "Clear", "Find" }
local enumCounter = 0
local EnumNS = { __index = function(t, k) enumCounter = enumCounter + 1; rawset(t, k, enumCounter); return enumCounter end }
G.Enum = setmetatable({}, { __index = function(t, k) local ns = setmetatable({}, EnumNS); rawset(t, k, ns); return ns end })
G.Constants = setmetatable({ CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }, { __index = function(t, k) local ns = setmetatable({}, EnumNS); rawset(t, k, ns); return ns end })

local function ApiFunction(name)
    if name:find("^Is") or name:find("^Has") or name:find("^Can") or name:find("^Does") or name:find("^Should") or name:find("^Are")
        or name:find("^UnitIs") or name:find("^UnitHas") or name:find("^UnitCan") or name:find("^UnitAffecting") or name:find("^UnitIn") then
        return function() return false end
    end
    if name:find("^Create") then return function() return New("Frame") end end
    if name:find("Num") or name:find("Count") or name:find("^GetMax") or name:find("BarIndex$") then return function() return 0, 0 end end
    if name:find("^Create") then return function() return New("Frame") end end
    if name:find("^Get.*Table$") or name:find("^Get.*List$") or name:find("^Get.*IDs$") or name:find("^GetAll") or name:find("Tracked$") then return function() return {} end end
    if name:find("Money") or name:find("Coin") then return function() return "0g" end end
    return function() return nil end
end
local Soft
local NamespaceMT = { __index = function(t, k)
    if type(k) ~= "string" then return nil end
    local f = Soft(k); rawset(t, k, f); return f
end }

-- An unknown CamelCase global may be a function (UnitHealth), a namespace
-- (AuraUtil) or a frame: the stand-in can be called like the first and
-- indexed like the second. Calls answer by the name's shape; fields are
-- stand-ins too.
local SoftMT = {}
-- Name and call behaviour live beside the object, so pairs() over a
-- stand-in finds nothing, like an empty table.
local softName, softCall = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
function Soft(name)
    local s = setmetatable({}, SoftMT)
    softName[s], softCall[s] = name, ApiFunction(name)
    return s
end
SoftMT.__call = function(self, ...) return softCall[self](...) end
local softDummy
SoftMT.__index = function(self, k)
    if type(k) ~= "string" or k:find("^%l") or k:find("^_") then return nil end
    -- A widget method name answers as a widget would (GetFrameLevel -> 1).
    local m = rawget(methods, k)
    if m then
        softDummy = softDummy or New("Frame")
        local v = function(_, ...) return m(softDummy, ...) end
        rawset(self, k, v)
        return v
    end
    local v = Soft(k)
    rawset(self, k, v)
    return v
end
SoftMT.__tostring = function(self) return softName[self] or "?" end
SoftMT.__concat = function(a, b) return tostring(a) .. tostring(b) end

setmetatable(G.AuraUtil, NamespaceMT)

local unknownGlobals = {}
setmetatable(realG, { __index = function(t, k)
    local v = G[k]
    if v ~= nil then rawset(t, k, v); return v end
    if type(k) ~= "string" or ABSENT[k] then return nil end
    for _, p in ipairs(ABSENT_PREFIX) do if k:find(p) then return nil end end
    if k:find("^%l") then return nil end                       -- Lua-style names are never client API
    unknownGlobals[k] = (unknownGlobals[k] or 0) + 1
    if k:find("^C_") or k:find("Util$") or k:find("Mixin$") or k:find("Processor$") or k:find("Registry$")
        or k:find("Handler$") or k == "Settings" or k == "Menu" then v = setmetatable({}, NamespaceMT)
    elseif k:find("COLORS$") or k:find("COLOR$") or k:find("TCOORDS$") then
        v = setmetatable({}, { __index = function(_, f)
            if f == "r" or f == "g" or f == "b" or f == "a" then return 1 end
            return { r = 1, g = 1, b = 1, a = 1, 0, 1, 0, 1 }
        end })
    elseif k:find("^[%u%d_]+$") and (k:find("^NUM_") or k:find("_NUM$") or k:find("_NUM_") or k:find("NUMDIALOGS") or k:find("^MAX_") or k:find("_MAX") or k:find("COUNT") or k:find("SLOTS") or k:find("OFFSET")
        or k:find("INDEX") or k:find("SIZE") or k:find("WIDTH") or k:find("HEIGHT") or k:find("_ID$")) then v = 4
    elseif k:find("^[%u%d_]+$") then v = k                      -- ALL_CAPS: a global string
    else
        local body = k:gsub("^%w-_", "")
        local functionLike = false
        for _, verb in ipairs(FUNCTION_VERBS) do if body:find("^" .. verb) then functionLike = true break end end
        if k:find("Has%u") or k:find("Is%u") or k:find("Can%u") then functionLike = true end
        if not functionLike then
            for _, s in ipairs(FRAME_SUFFIX) do if k:find(s .. "$") or k:find(s .. "%d+$") then v = NewBlizz(k, G.UIParent) break end end
        end
        if v == nil then v = Soft(k) end
    end
    rawset(t, k, v)
    return v
end })

-------------------------------------------------------------------------------
--  TOC loader
-------------------------------------------------------------------------------
local GAMETYPE = FLAVOR == "forever" and "camelot" or "standard"

local function ReadToc(dir, tocName)
    local f = io.open(ROOT .. "/" .. dir .. "/" .. tocName, "r")
    if not f then return nil end
    local e = { name = dir, files = {}, meta = {}, deps = {} }
    for line in f:lines() do
        line = line:gsub("\r", ""):gsub("^\239\187\191", "")
        local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
        if key then
            e.meta[key] = value
            if key == "LoadOnDemand" and value == "1" then e.lod = true end
            if key == "Dependencies" or key == "RequiredDeps" then for d in value:gmatch("[^,%s]+") do e.deps[#e.deps + 1] = d end end
            if key == "Title" then e.title = value end
        elseif line:match("%S") and not line:match("^#") then
            local path, cond = line:match("^(.-)%s*%[(.-)%]%s*$")
            path = (path or line):gsub("%s+$", "")
            local ok = true
            if cond then
                local types = cond:match("AllowLoadGameType%s+(.+)")
                if types then ok = false; for t in types:gmatch("[%w_]+") do if t == GAMETYPE or (t == "mainline" and GAMETYPE == "standard") then ok = true end end end
                local locales = cond:match("AllowLoadTextLocale%s+(.+)")
                if locales then ok = locales:find("enUS") ~= nil end
            end
            if ok then e.files[#e.files + 1] = (path:gsub("\\", "/")) end
        end
    end
    f:close()
    local allow = e.meta["AllowLoadGameType"]
    if allow then
        local ok = false
        for t in allow:gmatch("[%w_]+") do if t == GAMETYPE then ok = true end end
        if not ok then return nil end
    end
    local iface = e.meta["Interface"]
    if iface and not iface:find(tostring(IFACE), 1, true) and FLAVOR == "forever" then return nil end
    return e
end

local function Discover()
    -- cmd.exe on Windows (dir), a POSIX shell elsewhere (ls).
    local windows = package.config:sub(1, 1) == "\\"
    local p = io.popen(windows and 'dir /b /ad "CludesUI*" 2>nul' or 'ls -d CludesUI*/ 2>/dev/null')
    for line in p:lines() do
        local dir = line:gsub("\r", ""):match("([^/\\]+)[/\\]?$")
        local suffix = FLAVOR == "forever" and "_Camelot" or "_Mainline"
        local e = ReadToc(dir, dir .. suffix .. ".toc") or ReadToc(dir, dir .. ".toc")
        if e then addons[dir] = e; addonOrder[#addonOrder + 1] = dir end
    end
    p:close()
    table.sort(addonOrder)
end

local function FireEvent(event, ...)
    local list = {}
    for _, f in ipairs(allFrames) do if f.__events and f.__events[event] and f.__scripts.OnEvent then list[#list + 1] = f end end
    for _, f in ipairs(list) do
        if f.__events and f.__events[event] then Safe(f.__scripts.OnEvent, f, event, ...) end
    end
end

function LoadAddon(name)
    local e = addons[name]
    if not e or e.loaded or e.loading then return end
    e.loading = true
    for _, d in ipairs(e.deps) do LoadAddon(d) end
    local ns = {}
    e.ns = ns
    for _, file in ipairs(e.files) do
        if file:lower():match("%.lua$") then
            phase = "load " .. name .. "/" .. file
            -- Chunk names as the client gives them, so paths in errors and
            -- in debugstack read "Interface/AddOns/<addon>/<file>".
            local chunk, err
            local fh = io.open(ROOT .. "/" .. name .. "/" .. file, "rb")
            if fh then
                local src = fh:read("*a"):gsub("^\239\187\191", "")
                fh:close()
                chunk, err = loadstring(src, "@Interface/AddOns/" .. name .. "/" .. file)
            else
                err = "cannot open " .. name .. "/" .. file
            end
            if not chunk then Record(err) else Safe(chunk, name, ns) end
        end
    end
    e.loaded = true
    phase = "ADDON_LOADED " .. name
    FireEvent("ADDON_LOADED", name)
end

-------------------------------------------------------------------------------
--  Run
-------------------------------------------------------------------------------
Discover()
io.write(("CludesUI headless test: %s client, %s, %d addons found\n"):format(FLAVOR, CLASS, #addonOrder))

LoadAddon("CludesUI")
for _, name in ipairs(addonOrder) do if not addons[name].lod then LoadAddon(name) end end

for _, ev in ipairs({ "VARIABLES_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "GROUP_ROSTER_UPDATE" }) do
    phase = "event " .. ev
    if ev == "PLAYER_LOGIN" then loggedIn = true end
    if ev == "PLAYER_ENTERING_WORLD" then FireEvent(ev, true, false) else FireEvent(ev, "player") end
end
phase = "timers after login"
Advance(10)

local CUI = rawget(realG, "CludesUI")
local pagesBuilt, pagesFailed = 0, 0
if not CUI then
    Record("CludesUI global missing after load")
else
    phase = "open panel"
    Safe(function() CUI:Show() end)
    Advance(3)
    Safe(function() if not (CUI._mainFrame and CUI._mainFrame:IsShown()) then CUI:Show() end end)
    Advance(3)
    -- The page registry is private to the core addon: its namespace table.
    local modules = (addons.CludesUI.ns and addons.CludesUI.ns.modules) or {}
    local keys = {}
    for k in pairs(modules) do keys[#keys + 1] = k end
    if VERBOSE or #keys == 0 then
        local notLoaded = {}
        for _, n in ipairs(addonOrder) do if not addons[n].loaded then notLoaded[#notLoaded + 1] = n end end
        io.write(("  panel shown: %s, modules registered: %d, not loaded: %s, pending timers: %d\n"):format(
            tostring(CUI._mainFrame and CUI._mainFrame:IsShown()), #keys, table.concat(notLoaded, " "), #timers))
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local m = modules[key]
        local before = #errors
        phase = "module " .. key
        Safe(function() CUI:SelectModule(key) end)
        Advance(1)
        for _, page in ipairs(type(m) == "table" and type(m.pages) == "table" and m.pages or {}) do
            phase = "page " .. key .. " > " .. tostring(page)
            local b2 = #errors
            Safe(function() CUI:SelectPage(page) end)
            Advance(1)
            pagesBuilt = pagesBuilt + 1
            if #errors > b2 then pagesFailed = pagesFailed + 1 end
        end
        if VERBOSE then io.write(("  %s: %d new error(s)\n"):format(key, #errors - before)) end
    end
end

-------------------------------------------------------------------------------
--  Report
-------------------------------------------------------------------------------
local loaded = 0
for _, n in ipairs(addonOrder) do if addons[n].loaded then loaded = loaded + 1 end end
-- A probe script (HARNESS_PROBE=<file>) runs here with the loaded suite, for
-- one-off questions: it receives the addon table and the error list.
local probe = os.getenv("HARNESS_PROBE")
if probe then
    phase = "probe"
    local chunk, err = loadfile(probe)
    if chunk then Safe(chunk, addons, errors) else io.write("probe: ", tostring(err), "\n") end
end

local real, limits = {}, 0
for _, e in ipairs(errors) do if IsLimit(e) then limits = limits + 1 else real[#real + 1] = e end end
io.write(("%d addons loaded, %d pages built, %d with errors, %d distinct errors (+%d in code the fake client cannot stand in for)\n\n"):format(
    loaded, pagesBuilt, pagesFailed, #real, limits))
if not VERBOSE then errors = real end
for i, e in ipairs(errors) do
    io.write(("[%d] (%s) x%d\n    %s\n"):format(i, e.phase, e.count, e.msg))
    if e.trace then
        local n = 0
        for line in e.trace:gmatch("[^\n]+") do
            if line:find("%.lua:%d+") and not line:find("harness%.lua") then
                n = n + 1
                if n <= 4 then io.write("      ", (line:gsub("^%s+", "")), "\n") end
            end
        end
    end
end
if VERBOSE then
    local names = {}
    for k, c in pairs(unknownGlobals) do names[#names + 1] = k end
    table.sort(names)
    io.write("\nStand-in globals used (", #names, "): ", table.concat(names, " "), "\n")
end
os.exit(#real > 0 and 1 or 0)
