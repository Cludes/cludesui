if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_FramePool.lua -- the options page frame pool
--
--  WoW never frees a frame, so a settings page that is built again must not
--  build new frames. Every frame, texture, font string, mask, line and
--  animation group a build creates on a POOL HOST goes through this pool,
--  keyed by host and kind, in creation order. When a build runs again on a
--  kept host, the pool hands back the previous build's objects, each first
--  reset to the state a new object of its kind has, and the unchanged builder
--  code dresses them again: the result equals a fresh build, and after the
--  first pass nothing is created.
--
--  A pool host is a frame the pool made: a kept frame (Pool.Kept: page
--  wrappers, header roots, menus, popups), an owned frame (Pool.Owned) and
--  every object it hands out. Frames created by other means under a host are
--  foreign: a reset moves them under a hidden graveyard frame (they are lost
--  exactly as the page they belonged to was lost before the pool).
--
--  API (suite-internal; the core captures what it uses once the options addon
--  has loaded, CludesUI.lua EnsureLoaded):
--    Pool.CreateFrame(type, name, parent, template, id)  drop-in CreateFrame
--    Pool.Kept(owner, key, type, parent, template, name, hidden) -> frame, isNew
--      (hidden: the frame comes back hidden, new or reset, and the code that
--      dresses it shows it itself, so the OnShow scripts that survive resets
--      run once, at that show, never at the reset; an edit box kept hidden
--      takes the keyboard at that show while its auto-focus is on, so that
--      dress calls SetAutoFocus(false) before it shows the box)
--    Pool.Owned(owner, label, type, parent, template)    -> frame
--    Pool.Begin(host)       restart a kept host's cursors without resetting it
--      (what it handed out and what module state keeps of it are parked; its
--      own decorations, made through Pool.Attach, stay as they are)
--    Pool.Pin(host)         pin what shows over host as its next pass will,
--      with nothing reset (see below)
--    Pool.Keep(obj)         obj is held by module state: it leaves its pool
--    Pool.Attach(host, obj, key, onReset) -> true when obj now rides on host
--    Pool.Gen(obj)          dress generation (+1 per reset), nil when unpooled
--    Pool.IsIdle(obj)       pooled and not handed out since its host's reset
--      (obj's own host only: an object under a child that was put away keeps
--      its generation and reads not idle; deferred work whose effect shows
--      while hidden, such as keyboard focus, also checks obj:IsVisible())
--    Pool.Managed(obj)      the pool manages obj (false: made without it)
--    Pool.ExemptScripts(obj, slot, ...)     slots whose scripts survive resets
--      (the code that dresses obj sets them on its first dress only: dev mode
--      warns when a later dress sets or hooks one again, which would drop or
--      stack the hooks those slots keep)
--
--  The reset (Reset* below) starts from the engine's own SetToDefaults, the
--  documented reset Blizzard's pools use, then puts back what that call keeps
--  or changes: the shown state, scripts and hooks, events, attributes, Lua
--  keys, the parent, strata and level, a region's draw layer, a template's
--  own values, the keyboard flag, a kind's own settings (KEPT_VALUES), a
--  button's pushed text offset, a line's thickness, an animation group's
--  looping and an animation's own values (ANIM_KEPT), and the pixel-snap
--  cache. Pixel snapping itself is never set
--  here: SetToDefaults turns it on, as on a new texture, and the cache entry
--  is dropped so the first image set disables it again exactly as for a new
--  texture (CludesUI_PixelPerfect.lua).
--
--  The regions an object's engine made for it (a button's state art and text,
--  a status bar's fill, a cooldown's countdown text) are reset where they are,
--  to the look the same region of a new object has (read once per kind from a
--  probe object), with no image or text and hidden until a setter of their
--  role dresses them again. Only a region the pool cannot name, on a frame
--  whose engine may make its own (status bar, cooldown, edit box), makes the
--  pool retire that frame to the graveyard and build a new one.
--
--  A pass starts at a kept host's reset (Pool.Kept) or at Pool.Begin. Before
--  anything under the host moves, each kept or owned object that shows over
--  it and is placed by its parts (an open popup, menu or flyout) is pinned at
--  its spot to what the host itself is placed by, as what a dropped build left
--  behind stayed where it was (FreezeUnder). Pool.Pin does the same ahead of
--  the pass, for code that moves what the host is placed by first.
--
--  Bypassed while the global search builds its hidden index
--  (CludesUI._prebuilding): every call then creates as today.
--  Creates no frame and registers no event until a host exists.
--  In game, /run CludesUI._Pool._DevVerifyReset() checks the reset of every
--  pooled kind against a new object and prints what differs (dev tool).
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI
local Pool = CludesUI._Pool
if type(Pool) ~= "table" then
    Pool = {}
    CludesUI._Pool = Pool
end

local _G = _G
local type, pairs, next, select, pcall, rawget, rawset = type, pairs, next, select, pcall, rawget, rawset
local getmetatable, setmetatable, tonumber, tostring = getmetatable, setmetatable, tonumber, tostring
local tremove, tinsert = table.remove, table.insert

-- object -> record { cls, kind, host, gen, idle, ... } (weak keys: a record
-- lives exactly as long as its object)
local REC = setmetatable({}, { __mode = "k" })
-- owner -> { [key] = kept frame }
local KEPT = setmetatable({}, { __mode = "k" })
-- owner -> { [label key] = { list = {}, cur = n } }
local OWNED = setmetatable({}, { __mode = "k" })

-- Frame types the pool hands out (others are created as today) and the only
-- templates it accepts (the ones options frames use).
local FRAME_TYPES = {
    Frame = "Frame",
    Button = "Button",
    CheckButton = "CheckButton",
    EditBox = "EditBox",
    ScrollFrame = "ScrollFrame",
    StatusBar = "StatusBar",
    Cooldown = "Cooldown",
    PlayerModel = "PlayerModel",
    frame = "Frame",
    button = "Button",
    checkbutton = "CheckButton",
    editbox = "EditBox",
    scrollframe = "ScrollFrame",
    statusbar = "StatusBar",
    cooldown = "Cooldown",
    playermodel = "PlayerModel",
}
local TEMPLATES = { BackdropTemplate = true, CooldownFrameTemplate = true }

-- Frame types whose engine may make regions of its own on demand: a region the
-- pool can neither name (ENGINE_ROLES) nor count among a new object's own may
-- be the engine's, so it is hidden, never moved, and the frame is not handed
-- out again.
local ENGINE_UNSURE = { StatusBar = true, Cooldown = true, EditBox = true }

-- The engine-made regions the pool resets in place, per frame type: the getter
-- naming the region, the setter that makes it on a new object (the probe) and
-- the setters that dress it again. text: a font string. live: the engine
-- shows, hides and writes the region itself (a cooldown's countdown text).
local BUTTON_ROLES = {
    { get = "GetNormalTexture", make = "SetNormalTexture", sets = { "SetNormalTexture", "SetNormalAtlas" } },
    { get = "GetPushedTexture", make = "SetPushedTexture", sets = { "SetPushedTexture", "SetPushedAtlas" } },
    {
        get = "GetHighlightTexture",
        make = "SetHighlightTexture",
        sets = { "SetHighlightTexture", "SetHighlightAtlas" },
    },
    {
        get = "GetDisabledTexture",
        make = "SetDisabledTexture",
        sets = { "SetDisabledTexture", "SetDisabledAtlas" },
    },
    { get = "GetFontString", make = "SetText", sets = { "SetText", "SetFormattedText" }, text = true },
}
local CHECK_ROLES = {
    { get = "GetCheckedTexture", make = "SetCheckedTexture", sets = { "SetCheckedTexture" } },
    {
        get = "GetDisabledCheckedTexture",
        make = "SetDisabledCheckedTexture",
        sets = { "SetDisabledCheckedTexture" },
    },
}
for i = #BUTTON_ROLES, 1, -1 do
    tinsert(CHECK_ROLES, 1, BUTTON_ROLES[i])
end
local ENGINE_ROLES = {
    Button = BUTTON_ROLES,
    CheckButton = CHECK_ROLES,
    StatusBar = {
        { get = "GetStatusBarTexture", make = "SetStatusBarTexture", sets = { "SetStatusBarTexture" } },
    },
    Cooldown = { { get = "GetCountdownFontString", live = true } },
}
-- The image a probe gives a texture role's setter to make the region.
local PROBE_ART = "Interface\\Buttons\\WHITE8X8"

-- Settings SetToDefaults keeps, per frame type: the getter, and the setter that
-- puts back a new object's values (read once from the probe).
local KEPT_VALUES = {
    EditBox = { { "GetHistoryLines", "SetHistoryLines" }, { "GetHighlightColor", "SetHighlightColor" } },
    StatusBar = { { "GetMinMaxValues", "SetMinMaxValues" } },
    Cooldown = {
        { "GetDrawEdge", "SetDrawEdge" },
        { "GetDrawSwipe", "SetDrawSwipe" },
        { "GetDrawBling", "SetDrawBling" },
        { "GetReverse", "SetReverse" },
        { "GetHideCountdownNumbers", "SetHideCountdownNumbers" },
        { "GetEdgeScale", "SetEdgeScale" },
        { "GetRotation", "SetRotation" },
        { "GetCountdownAbbrevThreshold", "SetCountdownAbbrevThreshold" },
        { "GetMinimumCountdownDuration", "SetMinimumCountdownDuration" },
        { "GetUseAuraDisplayTime", "SetUseAuraDisplayTime" },
    },
    PlayerModel = {
        { "GetFacing", "SetFacing" },
        { "GetPosition", "SetPosition" },
        { "GetModelScale", "SetModelScale" },
    },
}
-- The same for an animation, whatever its type (a pair its type lacks is skipped):
-- its timing, then each type's own values.
local ANIM_KEPT = {
    { "GetDuration", "SetDuration" },
    { "GetStartDelay", "SetStartDelay" },
    { "GetEndDelay", "SetEndDelay" },
    { "GetOrder", "SetOrder" },
    { "GetSmoothing", "SetSmoothing" },
    { "GetFromAlpha", "SetFromAlpha" },
    { "GetToAlpha", "SetToAlpha" },
    { "GetOffset", "SetOffset" },
    { "GetDegrees", "SetDegrees" },
    { "GetOrigin", "SetOrigin" },
    { "GetScaleFrom", "SetScaleFrom" },
    { "GetScaleTo", "SetScaleTo" },
    { "GetFlipBookRows", "SetFlipBookRows" },
    { "GetFlipBookColumns", "SetFlipBookColumns" },
    { "GetFlipBookFrames", "SetFlipBookFrames" },
    { "GetFlipBookFrameWidth", "SetFlipBookFrameWidth" },
    { "GetFlipBookFrameHeight", "SetFlipBookFrameHeight" },
}

-- Per-object keys of the glow engines (CludesUI_Glows.lua): their presence
-- means a glow may be registered with the shared glow driver.
local GLOW_KEYS = {
    "_cuiGlowActive",
    "_cuiScrollData",
    "_cuiFlipData",
    "_cuiSgData",
    "_cuiBgData",
    "_cuiFillData",
    "_cuiAcData",
    "_cuiAnimAnts",
    "_cuiSpecSig",
    "_cuiStealTex",
    "_cuiPanTex",
}

-- A template's own script handlers (Blizzard_SharedXML/Backdrop.xml), put back
-- on a slot code had changed.
local TEMPLATE_SCRIPTS = {
    BackdropTemplate = {
        OnLoad = function(self, ...)
            return self:OnBackdropLoaded(...)
        end,
        OnSizeChanged = function(self, ...)
            return self:OnBackdropSizeChanged(...)
        end,
    },
}

-- An accent registry slot whose object was reset: inert until the object
-- registers again (CludesUI.lua RegAccent replaces the slot then).
local INERT_ACCENT = { type = "inert" }

-- The mouse buttons a frame may pass through (SetPassThroughButtons).
local PASS_BUTTONS = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }

local devOn = false
local function RefreshDev()
    local func = CludesUI.IsDevModeActive
    devOn = (func and func()) and true or false
end

-------------------------------------------------------------------------------
--  Scratch lists for the engine's vararg lists (resets can nest through OnHide
--  handlers, so each depth has its own list)
-------------------------------------------------------------------------------
local scratch, scratchN, depth = {}, {}, 0
local function Pack(...)
    depth = depth + 1
    local t = scratch[depth]
    if not t then
        t = {}
        scratch[depth] = t
    end
    local num = select("#", ...)
    for i = 1, num do
        t[i] = (select(i, ...))
    end
    scratchN[depth] = num
    return t, num
end
local function Release()
    local t, num = scratch[depth], scratchN[depth]
    for i = 1, num do
        t[i] = nil
    end
    depth = depth - 1
end

-------------------------------------------------------------------------------
--  Graveyard, probes, replay
-------------------------------------------------------------------------------
local graveyard
local function Graveyard()
    if not graveyard then
        graveyard = _G.CreateFrame("Frame")
        graveyard:Hide()
    end
    return graveyard
end
-- Harness / debugging accessor: never creates the frame.
Pool._Graveyard = function()
    return graveyard
end

local warned = {}
local function DevWarn(key, msg)
    if not devOn or warned[key] then
        return
    end
    warned[key] = true
    CludesUI.PrintError("pool: " .. msg)
end

-- Moves an object the pool does not manage off a host being reset. Its own
-- state is left as it is: it was lost with the build that made it.
local function Bury(o)
    if (o.IsForbidden and o:IsForbidden()) or (o.IsProtected and o:IsProtected()) then
        DevWarn(
            "bury:" .. tostring(o:GetObjectType()),
            "a protected or forbidden object under a pool host was left in place"
        )
        return
    end
    getmetatable(o).__index.SetParent(o, Graveyard())
end

-- The hidden frame that holds the probe objects and the inert animation target.
local probeHolder
local function ProbeHolder()
    if not probeHolder then
        probeHolder = _G.CreateFrame("Frame")
        probeHolder:Hide()
    end
    return probeHolder
end

local function SafeCall(func, o, ...)
    local success, val = pcall(func, o, ...)
    if success then
        return val
    end
    return nil
end

-- Kept values (KEPT_VALUES, ANIM_KEPT): read on a probe, compared and put back.
local abs, unpack = math.abs, _G.unpack
local function PackOK(success, ...)
    if not success then
        return nil
    end
    return { n = select("#", ...), ... }
end
-- Two values are the same: numbers within rounding, vectors (Vector2DMixin) by value.
local function SameVal(posX, posY)
    if posX == posY then
        return true
    end
    local tx, ty = type(posX), type(posY)
    if tx == "number" and ty == "number" then
        return abs(posX - posY) < 0.0001
    end
    if
        tx == "table"
        and ty == "table"
        and type(posX.GetXY) == "function"
        and type(posY.GetXY) == "function"
    then
        local ax, ay = posX:GetXY()
        local bx, by = posY:GetXY()
        if
            type(ax) == "number"
            and type(ay) == "number"
            and type(bx) == "number"
            and type(by) == "number"
        then
            return abs(ax - bx) < 0.0001 and abs(ay - by) < 0.0001
        end
    end
    return false
end
local function Differs(vals, ...)
    for i = 1, vals.n do
        if not SameVal(vals[i], (select(i, ...))) then
            return true
        end
    end
    return false
end
-- pairs: { { getter name, setter name }, ... }; probe: a new object of the kind.
-- Returns the pairs the probe has, each with the probe's values.
local function CaptureKept(probe, pairsList)
    local m = getmetatable(probe).__index
    local entries
    for i = 1, #pairsList do
        local get, set = m[pairsList[i][1]], m[pairsList[i][2]]
        local vals = get and set and PackOK(pcall(get, probe))
        if vals then
            entries = entries or {}
            entries[#entries + 1] = { get = get, set = set, vals = vals, name = pairsList[i][2] }
        end
    end
    return entries
end
-- What a reset could not put back, while the dev check listens (Pool._DevVerifyReset).
local refusedLog
-- Returns false when a value stays different (the setter refused it or changed nothing).
local function RestoreKept(object, entries)
    local success = true
    for i = 1, #entries do
        local k = entries[i]
        local vals = k.vals
        if Differs(vals, k.get(object)) then
            local done, err = pcall(k.set, object, unpack(vals, 1, vals.n))
            if not done or Differs(vals, k.get(object)) then
                success = false
                if refusedLog and #refusedLog < 50 then
                    refusedLog[#refusedLog + 1] = tostring(object:GetObjectType())
                        .. " "
                        .. k.name
                        .. (done and " changed nothing" or (" refused: " .. tostring(err)))
                end
            end
        end
    end
    return success
end

-- A new texture's rotation and rotation point (read once from a probe texture).
local texRotRead, texRot, texPivot
local function TexRotation()
    if not texRotRead then
        texRotRead = true
        texRot, texPivot = ProbeHolder():CreateTexture():GetRotation()
    end
    return texRot, texPivot
end

-- An animation group's kept values, and per animation type its animations'
-- (each read once from a probe: an empty group, and per type the first
-- animation of a group of its own, as a new group's first animation is).
local AG_KEPT = {
    { "GetLooping", "SetLooping" },
    { "IsSetToFinalAlpha", "SetToFinalAlpha" },
    { "GetAnimationSpeedMultiplier", "SetAnimationSpeedMultiplier" },
}
local agKept
local ANIM_INFO = {}
local function AGKept()
    if agKept == nil then
        agKept = CaptureKept(ProbeHolder():CreateAnimationGroup(), AG_KEPT) or false
    end
    return agKept
end
local function AnimKept(kind)
    local entries = ANIM_INFO[kind]
    if entries == nil then
        local ag = ProbeHolder():CreateAnimationGroup()
        local success, a = pcall(ag.CreateAnimation, ag, kind)
        entries = success and a and CaptureKept(a, ANIM_KEPT) or false
        ANIM_INFO[kind] = entries
    end
    return entries
end

-- A region as the engine made it on a probe object: its draw layer, anchors
-- (relative to the object), shown state and look (a texture's blend mode; a
-- font string's font, colours and justification).
local function CaptureRegion(reg, p)
    local c = { points = {} }
    c.layer, c.sub = reg:GetDrawLayer()
    for i = 1, reg:GetNumPoints() do
        local pt, rel, rp, posX, posY = reg:GetPoint(i)
        c.points[i] = { pt, rel == p or rel, rp, posX, posY }
    end
    c.shown = reg:IsShown() and true or false
    if reg.GetBlendMode then
        c.blend = reg:GetBlendMode()
    end
    if reg.GetFont then
        local filePath, size, flags = reg:GetFont()
        if filePath then
            c.font = { filePath, size, flags }
        end
        c.fontObject = reg:GetFontObject()
        c.color = { reg:GetTextColor() }
        c.shadow = { reg:GetShadowColor() }
        c.shadowOff = { reg:GetShadowOffset() }
        c.jh, c.jv = reg:GetJustifyH(), reg:GetJustifyV()
    end
    return c
end

-- Per kind, read once from a new object: its Lua keys (template mixins), its
-- input defaults, how many regions and children the engine gives it, and what
-- each engine-made region of a known role is like when new.
local KIND_INFO = {}
local function KindInfo(rec)
    local kind = rec.kind
    local details = KIND_INFO[kind]
    if details then
        return details
    end
    local p = _G.CreateFrame(rec.ftype, nil, ProbeHolder(), rec.tmpl)
    local m = getmetatable(p).__index
    details = { scripts = rec.tmpl and TEMPLATE_SCRIPTS[rec.tmpl] or nil }
    local keyList
    for k, val in pairs(p) do
        if type(k) == "string" and k:byte(1) ~= 0 then
            keyList = keyList or {}
            keyList[k] = val
        end
    end
    details.keys = keyList
    details.mouse = p:IsMouseEnabled() and true or false
    details.wheel = (m.IsMouseWheelEnabled and p:IsMouseWheelEnabled()) and true or false
    details.clips = (m.DoesClipChildren and p:DoesClipChildren()) and true or false
    details.keyboard = (m.IsKeyboardEnabled and p:IsKeyboardEnabled()) and true or false
    if rec.ftype == "EditBox" then
        details.autoFocus = p:IsAutoFocus() and true or false
    end
    local kv = KEPT_VALUES[rec.ftype]
    if kv then
        details.kept = CaptureKept(p, kv)
    end
    -- the engine's regions of known roles are reset in place, so they are never
    -- counted among the unnamed regions a new object starts with
    local roles = ENGINE_ROLES[rec.ftype]
    local named = 0
    if roles then
        for i = 1, #roles do
            local get = m[roles[i].get]
            if get and SafeCall(get, p) then
                named = named + 1
            end
        end
    end
    details.nRegions = select("#", p:GetRegions()) - named
    details.nChildren = select("#", p:GetChildren())
    if roles then
        local eng = {}
        for i = 1, #roles do
            local role = roles[i]
            local get, make = m[role.get], role.make and m[role.make]
            -- the text region is measured as a dress that shows text makes it: with a font object
            if make and role.text and m.SetNormalFontObject then
                pcall(m.SetNormalFontObject, p, _G.GameFontNormal)
            end
            if make then
                pcall(make, p, role.text and " " or PROBE_ART)
            end
            local reg = get and SafeCall(get, p)
            if reg then
                eng[i] = CaptureRegion(reg, p)
            end
        end
        details.eng = eng
    end
    if p:IsShown() then
        p:Hide()
    end
    KIND_INFO[kind] = details
    return details
end

-- Hover replay: a reused frame that stays under a still cursor never gets a
-- new OnEnter, and a tooltip its old dress showed would stay. The first
-- visible object a reset hides in a frame (the reset object itself, or a
-- child its host parks) notes the frame under the cursor and the widget
-- tooltip's owner, each with its dress generation, and shows one hidden frame
-- whose OnUpdate hides itself first: a tooltip owner dressed again since
-- loses its tooltip, and a frame under the cursor dressed again since gets
-- its new OnEnter. A frame that is not the same object any more gets the
-- engine's own OnEnter instead.
local replayFrame
local replayArmed = false
local replayFocus, replayFocusGen, replayOwner, replayOwnerGen
local function ReplayOnUpdate(self)
    self:Hide()
    replayArmed = false
    local f, fgen, ownerFrame, ogen = replayFocus, replayFocusGen, replayOwner, replayOwnerGen
    replayFocus, replayFocusGen, replayOwner, replayOwnerGen = nil, nil, nil, nil
    if ownerFrame then
        local orec = REC[ownerFrame]
        local ownerFn = CludesUI._WidgetTooltipOwner
        if
            (not orec or orec.gen ~= ogen)
            and ownerFn
            and ownerFn() == ownerFrame
            and CludesUI.HideWidgetTooltip
        then
            CludesUI.HideWidgetTooltip(true)
        end
    end
    if f then
        local frec = REC[f]
        local foci = _G.GetMouseFoci and _G.GetMouseFoci()
        if frec and frec.gen ~= fgen and foci and foci[1] == f and f:IsVisible() then
            local exec = _G.ExecuteFrameScript
            if exec then
                exec(f, "OnEnter", false)
            else
                local func = f:GetScript("OnEnter")
                if func then
                    pcall(func, f, false)
                end
            end
        end
    end
end
local function ArmReplay()
    replayArmed = true
    local foci = _G.GetMouseFoci and _G.GetMouseFoci()
    local f = foci and foci[1]
    local frec = f and REC[f]
    if frec then
        replayFocus, replayFocusGen = f, frec.gen
    end
    local ownerFn = CludesUI._WidgetTooltipOwner
    local ownerFrame = ownerFn and ownerFn()
    local orec = ownerFrame and REC[ownerFrame]
    if orec then
        replayOwner, replayOwnerGen = ownerFrame, orec.gen
    end
    if not replayFrame then
        replayFrame = _G.CreateFrame("Frame")
        replayFrame:Hide()
        replayFrame:SetScript("OnUpdate", ReplayOnUpdate)
    end
    replayFrame:Show()
end

-------------------------------------------------------------------------------
--  Instance overrides: creation on a host, script / attribute tracking and the
--  engine regions' setters (shared functions taking self; installed only for
--  methods the type has)
-------------------------------------------------------------------------------
local AcquireRegion, AcquireAG, AcquireAnim -- defined below

-- A slot ExemptScripts keeps through resets is set on its first dress only.
local function ExemptSlot(self, rec, slot, what)
    if devOn and rec.exemptGen ~= rec.gen then
        local name = self.GetName and self:GetName() or "?"
        DevWarn(
            "exempt:" .. tostring(name) .. tostring(slot),
            "a later dress "
                .. what
                .. " "
                .. tostring(slot)
                .. " on "
                .. tostring(name)
                .. ", whose "
                .. tostring(slot)
                .. " keeps its hooks through resets"
        )
    end
end

local function O_SetScript(self, slot, func)
    getmetatable(self).__index.SetScript(self, slot, func)
    local rec = REC[self]
    if not rec then
        return
    end
    if rec.exempt and rec.exempt[slot] then
        ExemptSlot(self, rec, slot, "set")
        return
    end
    local s = rec.scripts
    if not s then
        s = {}
        rec.scripts = s
    end
    s[slot] = true
end

local function O_HookScript(self, slot, func, ...)
    local r = getmetatable(self).__index.HookScript(self, slot, func, ...)
    local rec = REC[self]
    if not rec then
        return r
    end
    if rec.exempt and rec.exempt[slot] then
        ExemptSlot(self, rec, slot, "hooked")
        return r
    end
    local s = rec.scripts
    if not s then
        s = {}
        rec.scripts = s
    end
    s[slot] = true
    return r
end

local function O_SetAttribute(self, name, value)
    getmetatable(self).__index.SetAttribute(self, name, value)
    local rec = REC[self]
    if rec and name ~= nil then
        local a = rec.attrs
        if not a then
            a = {}
            rec.attrs = a
        end
        a[name] = true
    end
end

-- A scroll frame positions its scroll child, and no call clears a scroll
-- child (SetScrollChild takes no nil): the child remembers its scroll frame,
-- so its reset can hand that frame an inert placeholder instead.
local function O_SetScrollChild(self, childFrame)
    getmetatable(self).__index.SetScrollChild(self, childFrame)
    local crec = childFrame and REC[childFrame]
    if crec then
        crec.scrollOwner = self
    end
end

-- Creation goes to the pool only on an object the pool still manages (a
-- retired one creates as any frame does).
local function O_CreateTexture(self, name, layer, tmpl, sub)
    if name ~= nil or tmpl ~= nil or CludesUI._prebuilding or not REC[self] then
        return getmetatable(self).__index.CreateTexture(self, name, layer, tmpl, sub)
    end
    return AcquireRegion(self, "Texture", "CreateTexture", layer, sub)
end
local function O_CreateMaskTexture(self, name, layer, tmpl, sub)
    if name ~= nil or tmpl ~= nil or CludesUI._prebuilding or not REC[self] then
        return getmetatable(self).__index.CreateMaskTexture(self, name, layer, tmpl, sub)
    end
    return AcquireRegion(self, "MaskTexture", "CreateMaskTexture", layer, sub)
end
local function O_CreateLine(self, name, layer, tmpl, sub)
    if name ~= nil or tmpl ~= nil or CludesUI._prebuilding or not REC[self] then
        return getmetatable(self).__index.CreateLine(self, name, layer, tmpl, sub)
    end
    return AcquireRegion(self, "Line", "CreateLine", layer, sub)
end
local function O_CreateFontString(self, name, layer, tmpl, ...)
    if name ~= nil or tmpl ~= nil or CludesUI._prebuilding or not REC[self] then
        return getmetatable(self).__index.CreateFontString(self, name, layer, tmpl, ...)
    end
    return AcquireRegion(self, "FontString", "CreateFontString", layer, nil)
end
local function O_CreateAnimationGroup(self, name, tmpl)
    if name ~= nil or tmpl ~= nil or CludesUI._prebuilding or not REC[self] then
        return getmetatable(self).__index.CreateAnimationGroup(self, name, tmpl)
    end
    return AcquireAG(self)
end
local function O_CreateAnimation(self, atype, name, tmpl)
    if name ~= nil or tmpl ~= nil or CludesUI._prebuilding or not REC[self] then
        return getmetatable(self).__index.CreateAnimation(self, atype, name, tmpl)
    end
    return AcquireAnim(self, atype)
end

-- Animations a group kept from an earlier dress that the current dress did not
-- take (a group cannot drop one): pointed at a hidden region before the group
-- plays, so they change nothing (the group's next reset points them back).
local inertTarget
local function QuietLeftovers(ag)
    local grec = REC[ag]
    local pools = grec and grec.pools
    if not pools then
        return
    end
    local current = grec.cur
    for kind, entries in pairs(pools) do
        for i = (current[kind] or 0) + 1, #entries do
            local a = entries[i]
            local ar = REC[a]
            if ar and not ar.inert then
                if not inertTarget then
                    inertTarget = ProbeHolder():CreateTexture()
                end
                ar.inert = true
                a:SetTarget(inertTarget)
            end
        end
    end
end
local function O_AGPlay(self, ...)
    QuietLeftovers(self)
    return getmetatable(self).__index.Play(self, ...)
end
local function O_AGRestart(self, ...)
    QuietLeftovers(self)
    return getmetatable(self).__index.Restart(self, ...)
end
local function O_AGSetPlaying(self, playing, ...)
    if playing then
        QuietLeftovers(self)
    end
    return getmetatable(self).__index.SetPlaying(self, playing, ...)
end

local FRAME_OVERRIDES = {
    CreateTexture = O_CreateTexture,
    CreateFontString = O_CreateFontString,
    CreateMaskTexture = O_CreateMaskTexture,
    CreateLine = O_CreateLine,
    CreateAnimationGroup = O_CreateAnimationGroup,
    SetScript = O_SetScript,
    HookScript = O_HookScript,
    SetAttribute = O_SetAttribute,
    SetScrollChild = O_SetScrollChild,
}
local REGION_OVERRIDES =
    { CreateAnimationGroup = O_CreateAnimationGroup, SetScript = O_SetScript, HookScript = O_HookScript }
-- A texture's rotation point: SetToDefaults keeps the last one SetRotation gave
-- it, so a texture marked here has a new texture's point put back by its reset.
local function O_TexSetRotation(self, ...)
    local rec = REC[self]
    if rec then
        rec.rotated = true
    end
    return getmetatable(self).__index.SetRotation(self, ...)
end
local TEX_OVERRIDES = { SetRotation = O_TexSetRotation }
local AG_OVERRIDES = {
    CreateAnimation = O_CreateAnimation,
    SetScript = O_SetScript,
    HookScript = O_HookScript,
    Play = O_AGPlay,
    Restart = O_AGRestart,
    SetPlaying = O_AGSetPlaying,
}
local ANIM_OVERRIDES = { SetScript = O_SetScript, HookScript = O_HookScript }

-- region -> the shown state a new region of its role has: noted when a reset
-- hid an engine-made region, given back by the next setter of its role.
local engHidden = setmetatable({}, { __mode = "k" })
local function EngineSetter(setName, getName)
    return function(self, ...)
        local m = getmetatable(self).__index
        local r1, r2 = m[setName](self, ...)
        local get = m[getName]
        local reg = get and get(self)
        local back = reg and engHidden[reg]
        if back ~= nil then
            engHidden[reg] = nil
            if back then
                reg:Show()
            end
        end
        return r1, r2
    end
end
-- frame type -> { [setter name] = override } (made once, here)
local ENGINE_OVERRIDES = {}
for ftype, roles in pairs(ENGINE_ROLES) do
    local set = {}
    for i = 1, #roles do
        local sets = roles[i].sets
        if sets then
            for jdx = 1, #sets do
                set[sets[jdx]] = EngineSetter(sets[jdx], roles[i].get)
            end
        end
    end
    ENGINE_OVERRIDES[ftype] = set
end

-- Dev mode only: a pooled frame that something re-parents while it is idle is
-- held by module state (it must be Pool.Keep'd, plan C2).
local function O_DevSetParent(self, hostFrame, ...)
    local rec = REC[self]
    if rec and rec.idle and rec.cls == "pooled" then
        local site = _G.debugstack and _G.debugstack(2, 1, 0) or "?"
        DevWarn(
            "tripwire:" .. site,
            "an idle pooled object was re-parented (held by module state?) at " .. site
        )
    end
    return getmetatable(self).__index.SetParent(self, hostFrame, ...)
end

local function Install(object, set)
    local m = getmetatable(object).__index
    for name, func in pairs(set) do
        if rawget(m, name) ~= nil then
            rawset(object, name, func)
        end
    end
end

-- A retired frame drops the pool's instance overrides: a plain frame again.
local function StripOverrides(object, ftype)
    for name, func in pairs(FRAME_OVERRIDES) do
        if rawget(object, name) == func then
            rawset(object, name, nil)
        end
    end
    local eng = ENGINE_OVERRIDES[ftype]
    if eng then
        for name, func in pairs(eng) do
            if rawget(object, name) == func then
                rawset(object, name, nil)
            end
        end
    end
    if rawget(object, "SetParent") == O_DevSetParent then
        rawset(object, "SetParent", nil)
    end
end

local function NewFrameRec(cls, kind, ftype, tmpl, host)
    return {
        cls = cls,
        kind = kind,
        ftype = ftype,
        tmpl = tmpl,
        host = host,
        gen = 1,
        idle = false,
        isFrame = true,
    }
end

local function RegisterFrame(object, rec)
    REC[object] = rec
    -- a button's pushed text offset as new, read from the button itself as it is
    -- made (a new button's offset is not one fixed value): its resets put it back
    local m = getmetatable(object).__index
    if m.GetPushedTextOffset then
        rec.pushX, rec.pushY = object:GetPushedTextOffset()
    end
    Install(object, FRAME_OVERRIDES)
    local eng = ENGINE_OVERRIDES[rec.ftype]
    if eng then
        Install(object, eng)
    end
    if devOn and rec.cls == "pooled" then
        rawset(object, "SetParent", O_DevSetParent)
    end
    return object
end

-------------------------------------------------------------------------------
--  Registries keyed by an object (forgotten at its reset, so a reused object
--  never answers for its previous dress)
-------------------------------------------------------------------------------
local function ForgetRegistries(object, isFrame)
    local acc = CludesUI._accentElements
    local position = acc and acc._idx
    local i = position and position[object]
    if i then
        acc[i] = INERT_ACCENT
    end
    if isFrame then
        local rc = CludesUI._rowCounters
        if rc then
            rc[object] = nil
        end
        local forget = CludesUI._ForgetEscapeClose
        local rec = REC[object]
        if forget and not (rec and rec.exempt and (rec.exempt.OnShow or rec.exempt.OnHide)) then
            forget(object)
        end
    end
end

local function ForgetPixelSnap(object)
    local Pix = CludesUI.PP
    local f = Pix and Pix.ForgetPixelSnap
    if f then
        f(object)
    end
end

local function ResetScripts(object, rec, m, base)
    local s = rec.scripts
    if s and next(s) then
        local set = m.SetScript
        for slot in pairs(s) do
            set(object, slot, base and base[slot] or nil)
            s[slot] = nil
        end
    end
end

local function ResetAttrs(object, rec, m)
    local a = rec.attrs
    if a and next(a) then
        local set = m.SetAttribute
        for name in pairs(a) do
            set(object, name, nil)
            a[name] = nil
        end
    end
end

-- Every string key goes, except the keys a new object of the kind has (put
-- back to their values), keys naming a method of the object's type (instance
-- hooks: the pool's own overrides, TrackOverlay's) and its host attachment keys.
local function WipeKeys(object, rec, m, base)
    local keep = rec.attachKeys
    for k, val in pairs(object) do
        if type(k) == "string" and k:byte(1) ~= 0 then
            local bv = base and base[k]
            if bv ~= nil then
                if val ~= bv then
                    rawset(object, k, bv)
                end
            elseif rawget(m, k) == nil and not (keep and keep[k]) then
                rawset(object, k, nil)
            end
        end
    end
    if base then
        for k, val in pairs(base) do
            if rawget(object, k) == nil then
                rawset(object, k, val)
            end
        end
    end
end

local function HasGlow(object)
    for i = 1, #GLOW_KEYS do
        if rawget(object, GLOW_KEYS[i]) ~= nil then
            return true
        end
    end
    return false
end

-- The keyboard flag, when it is not a new object's: EnableKeyboard is protected,
-- so only an out-of-combat reset may put it back.
local function KeyboardChanged(object, m, details)
    return m.IsKeyboardEnabled ~= nil and (object:IsKeyboardEnabled() and true or false) ~= details.keyboard
end

-- The flags only an out-of-combat call may clear: propagation and pass-through
-- (SetToDefaults clears them; read only in combat).
local function HasPropagate(object, m)
    if m.GetPropagateKeyboardInput and object:GetPropagateKeyboardInput() then
        return true
    end
    if m.CanPropagateMouseClicks and object:CanPropagateMouseClicks() then
        return true
    end
    if m.CanPropagateMouseMotion and object:CanPropagateMouseMotion() then
        return true
    end
    local pass = m.ShouldButtonPassThrough
    if pass then
        for i = 1, #PASS_BUTTONS do
            if pass(object, PASS_BUTTONS[i]) then
                return true
            end
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  The start of a pass: what shows over a host stays where it is
-------------------------------------------------------------------------------
-- A pass on a host (its reset by Pool.Kept, or Pool.Begin) dresses again what
-- the host handed out. A kept or owned object that shows meanwhile (an open
-- popup, menu or flyout) and is placed by those parts would follow them to
-- their new places, while what a dropped build left behind stayed where it
-- was, placed only by what the build's root was placed by. So before anything
-- under the host moves, each such object is pinned at its spot to what the
-- host is placed by (the host itself for Pool.Begin, which leaves it where it
-- is), until code places it again.
-- rec.fw: the walk that visited an object; rec.fm: the walk that found it
-- moved (a part the pass dresses again, or the host its own reset moves).
local walkSerial, walking = 0, false
local frzList, frzN = {}, 0
local PASS_RESET, PASS_BEGIN = 1, 2

-- Everything under o as the pool knows it, each with whether the pass dresses
-- it again (moved): what o handed out, its attachments and its owned objects
-- move when o's parts do (the reset that parks an owned object starts its
-- owner's next dress, which hands it out again); its kept objects never do
-- (the pass dresses none of the kept ones, nor what they hand out). The kept
-- and owned objects of every owner met are listed, the shown ones, as pin
-- candidates. Regions are not visited: one is moved with the frame that
-- handed it out (MovedBy).
local Visit
local function Parts(o, r, moved, depth)
    local km = KEPT[o]
    if km then
        for _, k in pairs(km) do
            local kr = REC[k]
            if kr then
                Visit(k, kr, false, true, depth)
            end
        end
    end
    local om = OWNED[o]
    if om then
        for _, slot in pairs(om) do
            local entries = slot.list
            for i = 1, #entries do
                local posX = entries[i]
                local xr = REC[posX]
                if xr then
                    Visit(posX, xr, moved, true, depth)
                end
            end
        end
    end
    if not r.isFrame then
        return
    end
    local pools = r.pools
    if pools then
        for _, entries in pairs(pools) do
            for i = 1, #entries do
                local posX = entries[i]
                local xr = REC[posX]
                if xr and xr.isFrame then
                    Visit(posX, xr, moved, false, depth)
                end
            end
        end
    end
    local att = r.attach
    if att then
        for i = 1, #att do
            local a = att[i]
            local ar = REC[a]
            if ar and ar.host == o then
                Visit(a, ar, moved, false, depth)
            end
        end
    end
end
Visit = function(o, r, moved, listed, depth)
    if r.fw == walkSerial or depth > 64 then
        return
    end
    r.fw = walkSerial
    if moved then
        r.fm = walkSerial
    end
    if listed and o:IsShown() then
        frzN = frzN + 1
        frzList[frzN] = o
    end
    Parts(o, r, moved, depth + 1)
end

-- Whether walk `serial` found rel moved (a region moves with its frame).
local function MovedBy(rel, serial)
    local rr = REC[rel]
    if not rr then
        return false
    end
    if rr.fm == serial then
        return true
    end
    local hr = rr.region and rr.host and REC[rr.host]
    return hr ~= nil and hr.fm == serial
end

-- Whether something walk `serial` found moved places f, through its anchors
-- and theirs (at most depBudget anchors read; running out counts as placed).
-- An anchoring code may not read (restricted, or answered with a secret) is
-- not followed: every value is cleared by issecretvalue before any test.
local depBudget = 0
local function PlacedByMoved(f, serial)
    local isv = _G.issecretvalue
    local restricted = f.IsAnchoringRestricted and f:IsAnchoringRestricted()
    if isv and isv(restricted) then
        return false
    end
    if restricted then
        return false
    end
    local last
    for i = 1, f:GetNumPoints() do
        local _, rel = f:GetPoint(i)
        if isv and isv(rel) then
            return false
        end
        if rel ~= nil and rel ~= last then
            last = rel
            if MovedBy(rel, serial) then
                return true
            end
            depBudget = depBudget - 1
            if depBudget <= 0 or PlacedByMoved(rel, serial) then
                return true
            end
        end
    end
    return false
end

-- What a host is placed by: its first anchor's frame (the screen: UIParent).
local function PlacedBy(hgt)
    local isv = _G.issecretvalue
    for i = 1, hgt:GetNumPoints() do
        local _, rel = hgt:GetPoint(i)
        if isv and isv(rel) then
            break
        end
        if rel ~= nil then
            return rel
        end
    end
    return _G.UIParent
end

-- f pinned where it is now: to ref's top left corner, or to the screen
-- (UIParent's bottom left, as a dropped build's orphaned anchor kept it) when
-- ref is UIParent or has no place itself.
local function FreezeTo(f, ref)
    local isv = _G.issecretvalue
    local l, b, wid, hgt = f:GetRect()
    if isv and (isv(l) or isv(b) or isv(wid) or isv(hgt)) then
        return
    end
    if not (l and b and wid and hgt) then
        return
    end
    local UIParent = _G.UIParent
    if ref ~= UIParent and ref ~= f then
        local rl, rb, rw, rh = ref:GetRect()
        if not (isv and (isv(rl) or isv(rb) or isv(rw) or isv(rh))) and rl and rb and rw and rh then
            -- ref's corner in f's own units (each scales its own offsets)
            local k = ref:GetEffectiveScale() / f:GetEffectiveScale()
            f:ClearAllPoints()
            if pcall(f.SetPoint, f, "TOPLEFT", ref, "TOPLEFT", l - rl * k, b + hgt - (rb + rh) * k) then
                f:SetSize(wid, hgt)
                return
            end
        end
    end
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    f:SetSize(wid, hgt)
end

local function FreezeWalk(host, hrec, hostMoved)
    walkSerial = walkSerial + 1
    local serial = walkSerial
    frzN = 0
    hrec.fw = serial
    if hostMoved then
        hrec.fm = serial
    end
    -- the host's own parts are dressed again by its pass, whether or not the
    -- host itself is
    Parts(host, hrec, true, 1)
    if frzN == 0 then
        return
    end
    local ref = hostMoved and PlacedBy(host) or host
    for i = 1, frzN do
        local f = frzList[i]
        depBudget = 64
        if f ~= ref and f:IsShown() and PlacedByMoved(f, serial) then
            FreezeTo(f, ref)
        end
    end
end

-- Called once per pass, before its host's parts move (ResetContents). A pass
-- that starts while one pins (a script a pin fires) leaves it to that one.
local function FreezeUnder(host, hrec, hostMoved)
    if walking then
        return
    end
    walking = true
    local success, err = pcall(FreezeWalk, host, hrec, hostMoved)
    walking = false
    for i = 1, frzN do
        frzList[i] = nil
    end
    frzN = 0
    if not success then
        _G.geterrorhandler()(err)
    end
end

-------------------------------------------------------------------------------
--  A host's contents at its reset (or Pool.Begin)
-------------------------------------------------------------------------------
local function ParkList(entries)
    for i = 1, #entries do
        local o = entries[i]
        local r = REC[o]
        if r and not r.idle then
            if r.isAG then
                o:Stop()
            elseif o:IsShown() then
                if not replayArmed and o:IsVisible() then
                    ArmReplay()
                end
                o:Hide()
            end
            r.idle = true
        end
    end
end

-- pass: PASS_RESET (a kept host's reset) or PASS_BEGIN (Pool.Begin) starts a
-- pass on obj; nil for an object handed out again within one (already walked).
local function ResetContents(object, rec, details, pass)
    -- pooled objects of this host, wherever they are now: hidden, idle
    local pools = rec.pools
    if pools then
        for _, entries in pairs(pools) do
            ParkList(entries)
        end
        local current = rec.cur
        for k in pairs(current) do
            current[k] = 0
        end
    end
    -- owned objects: hidden, cursors back to the start
    local om = OWNED[object]
    if om then
        for _, slot in pairs(om) do
            ParkList(slot.list)
            slot.cur = 0
        end
    end
    -- attachments: hidden, their onReset runs. Pool.Begin does not reset the
    -- host, so the host's own decorations (Pool.Attach: a border, a mark, a
    -- glow) stay as they are; what module state keeps (Pool.Keep) is parked
    -- as the rest of what the host handed out is
    local att = rec.attach
    if att then
        for i = 1, #att do
            local a = att[i]
            local ar = REC[a]
            if ar and ar.host == object and (pass ~= PASS_BEGIN or ar.cls == "keep") then
                if a:IsShown() then
                    a:Hide()
                end
                if ar.onReset then
                    pcall(ar.onReset, a)
                end
            end
        end
    end
    -- the start of a pass, after what the parts' hiding closes and before any
    -- part moves: what shows over the host and hangs on its parts stays put
    if pass then
        FreezeUnder(object, rec, pass == PASS_RESET)
    end
    if not rec.isFrame then
        return
    end
    -- children and regions the pool does not manage
    local buried = 0
    local skip = details and details.nChildren or 0
    local t, num = Pack(object:GetChildren())
    for i = 1, num do
        local c = t[i]
        if REC[c] == nil then
            if skip > 0 then
                skip = skip - 1 -- the engine's own children come first
            else
                Bury(c)
                buried = buried + 1
            end
        end
    end
    Release()
    -- the engine's regions of known roles: named here (rec.engRegs), reset in
    -- place after the frame's own reset (ResetFrame), never buried
    local named
    local roles = ENGINE_ROLES[rec.ftype]
    if roles then
        local m = getmetatable(object).__index
        for i = 1, #roles do
            local get = m[roles[i].get]
            local reg = get and get(object)
            if reg and REC[reg] == nil then
                if not named then
                    named = rec.engRegs
                    if not named then
                        named = {}
                        rec.engRegs = named
                    end
                end
                named[reg] = i
            end
        end
    end
    skip = details and details.nRegions or 0
    t, num = Pack(object:GetRegions())
    for i = 1, num do
        local reg = t[i]
        if REC[reg] == nil and not (named and named[reg]) then
            if skip > 0 then
                skip = skip - 1
            elseif ENGINE_UNSURE[rec.ftype] then
                -- maybe the engine's, unnamed: left in place, the frame is retired
                if reg:IsShown() then
                    reg:Hide()
                end
                rec.engine = true
            else
                Bury(reg)
                buried = buried + 1
            end
        end
    end
    Release()
    -- animation groups the pool does not manage cannot move: stopped
    t, num = Pack(object:GetAnimationGroups())
    for i = 1, num do
        local ag = t[i]
        if REC[ag] == nil then
            ag:Stop()
        end
    end
    Release()
    if buried > 0 and devOn then
        DevWarn(
            "foreign:" .. tostring(rec.key or rec.kind),
            buried
                .. " foreign object(s) under "
                .. tostring(rec.key or rec.kind)
                .. " (made without the pool)"
        )
    end
end

-------------------------------------------------------------------------------
--  Reset to fresh
-------------------------------------------------------------------------------
local function ApplyCooldownTemplate(cd)
    -- Blizzard_FrameXMLUtil/Mainline/Cooldown.xml: hidden, all points, a black
    -- swipe at 0.64, the secondary edge and the star bling tinted blue
    cd:SetSwipeColor(0, 0, 0, 0.64)
    cd:SetEdgeTexture("Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown")
    cd:SetBlingTexture("Interface\\Cooldown\\star4", 0.3, 0.6, 1, 0.64)
    cd:SetAllPoints()
end

local verified = {}
local function Fixed(rec, what)
    if devOn and not verified[rec.kind .. what] then
        verified[rec.kind .. what] = true
        DevWarn("fix:" .. rec.kind .. what, "SetToDefaults left " .. what .. " on a " .. rec.kind)
    end
end

-- A scroll frame's hidden stand-in scroll child (made once per scroll frame).
local function PlaceholderFor(scrollFrame, srec)
    local ph = srec and srec.placeholder
    if not ph then
        ph = _G.CreateFrame("Frame", nil, scrollFrame)
        ph:Hide()
        REC[ph] = { cls = "placeholder", idle = true }
        if srec then
            srec.placeholder = ph
        end
    end
    return ph
end

-- A frame that is still a pool scroll frame's scroll child leaves it before
-- its next dress: that scroll frame, idle or not, would keep positioning it.
local function ReleaseScrollChild(object, rec)
    local scrollFrame = rec.scrollOwner
    rec.scrollOwner = nil
    if not scrollFrame or scrollFrame:GetScrollChild() ~= object then
        return
    end
    getmetatable(scrollFrame).__index.SetScrollChild(
        scrollFrame,
        PlaceholderFor(scrollFrame, REC[scrollFrame])
    )
end

-- A region placed as the same region of a new object is (c, from the probe).
local function PlaceAsNew(object, reg, c)
    reg:SetDrawLayer(c.layer, c.sub)
    reg:ClearAllPoints()
    local pts = c.points
    for jdx = 1, #pts do
        local p = pts[jdx]
        local rel = p[2]
        if rel == true then
            rel = object
        end
        reg:SetPoint(p[1], rel, p[3], p[4], p[5])
    end
end

-- An engine-made region of a known role, reset where it is: the look the same
-- region of a new object has (c, from the probe), no image or text, hidden
-- until a setter of its role dresses it again (which gives back a new
-- region's shown state). A live role (the engine shows and writes it itself)
-- takes a new region's look and shown state. A button's text takes no look of
-- its own: back at the engine's defaults, it gets the font object the next
-- dress gives the button, as a new button's text does.
local function ResetEngineRegion(object, reg, c, role)
    local isText = reg.GetFont ~= nil
    if isText and not role.live then
        if reg.SetToDefaults then
            reg:SetToDefaults()
        end
        if c then
            PlaceAsNew(object, reg, c)
        end
        if reg:GetFont() then
            reg:SetText("")
        end
        if reg:IsShown() then
            reg:Hide()
        end
        if c then
            engHidden[reg] = c.shown
        else
            engHidden[reg] = true
        end
        return
    end
    if c ~= nil and (c.font ~= nil or not isText) then
        if reg.SetToDefaults then
            reg:SetToDefaults()
        end
        if reg.GetNumMaskTextures then
            for jdx = reg:GetNumMaskTextures(), 1, -1 do
                local mask = reg:GetMaskTexture(jdx)
                if mask then
                    reg:RemoveMaskTexture(mask)
                end
            end
        end
        ForgetPixelSnap(reg)
        PlaceAsNew(object, reg, c)
        if c.blend then
            reg:SetBlendMode(c.blend)
        end
        if c.font then
            if c.fontObject then
                reg:SetFontObject(c.fontObject)
            end
            reg:SetFont(c.font[1], c.font[2], c.font[3])
            local col = c.color
            reg:SetTextColor(col[1], col[2], col[3], col[4])
            col = c.shadow
            reg:SetShadowColor(col[1], col[2], col[3], col[4])
            reg:SetShadowOffset(c.shadowOff[1], c.shadowOff[2])
            reg:SetJustifyH(c.jh)
            reg:SetJustifyV(c.jv)
        end
    end
    if role.live then
        if c and (reg:IsShown() and true or false) ~= c.shown then
            reg:SetShown(c.shown)
        end
        return
    end
    if reg.SetTexture then
        reg:SetTexture(nil)
    end
    if reg:IsShown() then
        reg:Hide()
    end
    if c then
        engHidden[reg] = c.shown
    else
        engHidden[reg] = true
    end
end

local function ResetEngineRegions(object, rec, details, named)
    local roles = ENGINE_ROLES[rec.ftype]
    local eng = details.eng
    local m = devOn and getmetatable(object).__index
    for reg, i in pairs(named) do
        named[reg] = nil
        ResetEngineRegion(object, reg, eng and eng[i], roles[i])
        if m then
            local get = m[roles[i].get]
            if get and get(object) ~= reg then
                Fixed(rec, " no " .. roles[i].get:sub(4) .. " (its frame's reset dropped it)")
            end
        end
    end
end

-- Returns false when the object cannot be reset now (a propagation,
-- pass-through or keyboard flag in combat: only an out-of-combat reset may
-- clear it). pass: see ResetContents. hidden: left hidden at the end (shown
-- by the code that dresses it), so no OnShow runs at the reset.
local function ResetFrame(object, rec, hostFrame, pass, hidden)
    local m = getmetatable(object).__index
    local details = KindInfo(rec)
    if _G.InCombatLockdown() and (HasPropagate(object, m) or KeyboardChanged(object, m, details)) then
        rec.dirty = true
        return false
    end
    rec.dirty = nil
    rec.engine = nil
    local hook = rawget(object, "_cuiOnRecycle")
    if hook then
        pcall(hook, object)
    end
    if HasGlow(object) then
        local G = CludesUI.Glows
        if G and G.StopAllGlows then
            pcall(G.StopAllGlows, object)
        end
    end
    -- visible descendants get OnHide with their old scripts, as when a page was dropped
    if object:IsShown() then
        if not replayArmed and object:IsVisible() then
            ArmReplay()
        end
        object:Hide()
    end
    if rec.ftype == "EditBox" and object:HasFocus() then
        object:ClearFocus()
    end
    if rec.scrollOwner then
        ReleaseScrollChild(object, rec)
    end
    ResetContents(object, rec, details, pass)
    ResetScripts(object, rec, m, details.scripts)
    object:UnregisterAllEvents()
    ResetAttrs(object, rec, m)
    ForgetRegistries(object, true)
    WipeKeys(object, rec, m, details.keys)
    if rec.ftype == "Cooldown" then
        object:Clear()
    end
    -- Click and drag registration: no getter reads either back, so the
    -- in-game reset check cannot tell whether SetToDefaults clears them.
    -- A new object's are put back first (a button answers the left
    -- button's release, nothing is registered for drag), so a reused
    -- button never answers the clicks, or starts the drags, of an earlier dress.
    if m.RegisterForClicks then
        object:RegisterForClicks("LeftButtonUp")
    end
    if m.RegisterForDrag then
        object:RegisterForDrag()
    end
    if object.SetToDefaults then
        object:SetToDefaults()
    else
        object:ClearAllPoints()
        object:SetAlpha(1)
        object:SetScale(1)
    end
    if rec.ftype == "PlayerModel" and m.ClearModel then
        object:ClearModel()
    end
    ForgetPixelSnap(object)
    -- what SetToDefaults is documented to cover, checked where it is cheap
    if object:GetAlpha() ~= 1 then
        object:SetAlpha(1)
        Fixed(rec, "alpha")
    end
    if (object:IsMouseEnabled() and true or false) ~= details.mouse then
        object:EnableMouse(details.mouse)
        Fixed(rec, "mouse")
    end
    if m.IsMouseWheelEnabled and (object:IsMouseWheelEnabled() and true or false) ~= details.wheel then
        object:EnableMouseWheel(details.wheel)
        Fixed(rec, "wheel")
    end
    if m.DoesClipChildren and (object:DoesClipChildren() and true or false) ~= details.clips then
        object:SetClipsChildren(details.clips)
        Fixed(rec, "clips")
    end
    -- what SetToDefaults keeps: the keyboard flag (left as it is only in combat,
    -- where it already matches), the pushed text offset, the kind's own settings
    -- and an edit box's history
    if KeyboardChanged(object, m, details) and not _G.InCombatLockdown() then
        object:EnableKeyboard(details.keyboard)
    end
    if rec.pushX then
        local posX, posY = object:GetPushedTextOffset()
        if posX ~= rec.pushX or posY ~= rec.pushY then
            object:SetPushedTextOffset(rec.pushX, rec.pushY)
        end
    end
    -- a setting the engine will not put back retires the frame, as a region the
    -- pool cannot name does: it is never handed out again
    if details.kept and not RestoreKept(object, details.kept) then
        rec.engine = true
    end
    if m.ClearHistory then
        object:ClearHistory()
    end
    -- No API clears a scroll frame's scroll child (SetScrollChild takes no nil):
    -- a child of an earlier dress gives way to the frame's hidden placeholder,
    -- which positions nothing and gives the frame no scroll range.
    if rec.ftype == "ScrollFrame" then
        local childFrame = object:GetScrollChild()
        if childFrame and childFrame ~= rec.placeholder then
            m.SetScrollChild(object, PlaceholderFor(object, rec))
        end
    end
    -- placement: the parent, its strata and the level a new child gets
    if object:GetParent() ~= hostFrame then
        m.SetParent(object, hostFrame)
    end
    local strata = hostFrame and hostFrame:GetFrameStrata() or "MEDIUM"
    if object:GetFrameStrata() ~= strata then
        object:SetFrameStrata(strata)
    end
    object:SetFrameLevel(hostFrame and (hostFrame:GetFrameLevel() + 1) or 0)
    -- the engine's regions of known roles (named by ResetContents)
    local named = rec.engRegs
    if named and next(named) then
        ResetEngineRegions(object, rec, details, named)
    end
    if rec.tmpl == "CooldownFrameTemplate" then
        ApplyCooldownTemplate(object)
        if object:IsShown() then
            object:Hide()
        end
    elseif rec.ftype == "EditBox" then
        -- a shown auto-focus edit box takes the keyboard: show it without, then
        -- put the new object's default back (one kept hidden is shown by its
        -- dress, which turns auto-focus off first: see Pool.Kept)
        object:SetAutoFocus(false)
        if not hidden then
            m.Show(object)
        end
        object:SetAutoFocus(details.autoFocus)
    elseif not hidden then
        -- shown as a new frame is: through the type's method, so an instance Show
        -- hook (CludesUI.TrackOverlay) never sees the reset (the Hide above it does)
        m.Show(object)
    end
    rec.gen = rec.gen + 1
    rec.idle = false
    return true
end

-- Returns false when a value of its own stays different (its group is retired).
local function ResetAnim(a, r)
    local m = getmetatable(a).__index
    if a.IsPlaying and a:IsPlaying() and a.Stop then
        a:Stop()
    end
    ResetScripts(a, r, m, nil)
    WipeKeys(a, r, m, nil)
    if a.SetToDefaults then
        a:SetToDefaults()
    end
    -- the target a new animation has: its group's parent
    if a.SetTargetParent then
        a:SetTargetParent()
    end
    -- what SetToDefaults keeps: its timing and its type's own values
    local kept = AnimKept(r.kind)
    local fit = not kept or RestoreKept(a, kept)
    r.inert = nil
    r.gen = r.gen + 1
    return fit
end

local function ResetAG(ag, rec)
    local m = getmetatable(ag).__index
    ag:Stop()
    ResetScripts(ag, rec, m, nil)
    WipeKeys(ag, rec, m, nil)
    if ag.SetToDefaults then
        ag:SetToDefaults()
    end
    -- what SetToDefaults keeps: the looping, final alpha and speed
    local kept = AGKept()
    local fit = not kept or RestoreKept(ag, kept)
    -- its animations are reset where they are (a group cannot drop one) and
    -- handed back in order by CreateAnimation; the ones the next dress does
    -- not take are quieted before the group plays (QuietLeftovers)
    local pools = rec.pools
    if pools then
        for _, entries in pairs(pools) do
            for i = 1, #entries do
                local a = entries[i]
                local ar = REC[a]
                if not ResetAnim(a, ar) then
                    fit = false
                end
                ar.idle = true
                ar.fresh = true
            end
        end
        local current = rec.cur
        for k in pairs(current) do
            current[k] = 0
        end
    end
    -- a value the engine will not put back (an animation's smoothing): the group
    -- is retired by AcquireAG, never handed out again
    rec.unfit = not fit or nil
    rec.gen = rec.gen + 1
    rec.idle = false
end

-- A group the pool will not hand out again: stopped where it is (a group cannot
-- move), a plain group again (no pool overrides), out of the pool.
local function RetireAG(ag)
    local rec = REC[ag]
    REC[ag] = nil
    ag:Stop()
    for name, func in pairs(AG_OVERRIDES) do
        if rawget(ag, name) == func then
            rawset(ag, name, nil)
        end
    end
    local pools = rec and rec.pools
    if pools then
        for _, entries in pairs(pools) do
            for i = 1, #entries do
                local a = entries[i]
                REC[a] = nil
                for name, func in pairs(ANIM_OVERRIDES) do
                    if rawget(a, name) == func then
                        rawset(a, name, nil)
                    end
                end
            end
        end
    end
end

local function ResetRegion(object, rec, host, layer, sub)
    local m = getmetatable(object).__index
    if object:IsShown() then
        object:Hide()
    end
    ResetScripts(object, rec, m, nil)
    ForgetRegistries(object, false)
    WipeKeys(object, rec, m, nil)
    -- its own animation groups: stopped, handed back in order
    local pools = rec.pools
    if pools then
        for _, entries in pairs(pools) do
            ParkList(entries)
        end
        local current = rec.cur
        for k in pairs(current) do
            current[k] = 0
        end
    end
    if object.SetToDefaults then
        object:SetToDefaults()
    else
        object:ClearAllPoints()
        object:SetAlpha(1)
    end
    -- a line's thickness and a rotated texture's rotation point as new (SetToDefaults keeps both)
    if rec.thick and object:GetThickness() ~= rec.thick then
        object:SetThickness(rec.thick)
    end
    if rec.rotated then
        rec.rotated = nil
        local r0, p0 = TexRotation()
        if p0 then
            m.SetRotation(object, r0, p0)
        end
    end
    if m.GetNumMaskTextures then
        for i = object:GetNumMaskTextures(), 1, -1 do
            local mask = object:GetMaskTexture(i)
            if mask then
                object:RemoveMaskTexture(mask)
            end
        end
    end
    ForgetPixelSnap(object)
    object:SetDrawLayer(layer, sub)
    if object:GetParent() ~= host then
        m.SetParent(object, host)
    end
    object:Show()
    rec.layer, rec.sub = layer, sub
    rec.gen = rec.gen + 1
    rec.idle = false
end

-------------------------------------------------------------------------------
--  Acquire
-------------------------------------------------------------------------------
-- An object the pool will not hand out again: out of its list, a plain frame
-- again (no pool overrides), buried.
local function Retire(object)
    local rec = REC[object]
    REC[object] = nil
    if rec then
        StripOverrides(object, rec.ftype)
    end
    if object:IsShown() then
        object:Hide()
    end
    Bury(object)
    if rec and devOn then
        DevWarn(
            "retire:" .. tostring(rec.kind),
            "a " .. tostring(rec.kind) .. " with a region the pool cannot name is not reused"
        )
    end
end

-- Next object of a list for a new dress: an idle one reset to fresh, or nil.
-- Objects that cannot be reset now go to the end of the list (each candidate
-- is tried once) and mark it (list.skipped); objects with a region the pool
-- cannot name are retired.
local function TakeFrame(entries, i, hostFrame)
    -- Out of combat an idle object a combat reset skipped is taken first, so
    -- it is reset and reused instead of idling behind the newer ones; the
    -- mark clears on the first look that finds none.
    if entries.skipped and not _G.InCombatLockdown() then
        entries.skipped = nil
        for jdx = i + 1, #entries do
            local r = REC[entries[jdx]]
            if r and r.dirty then
                entries[i], entries[jdx] = entries[jdx], entries[i]
                entries.skipped = true
                break
            end
        end
    end
    local tries = #entries - i + 1
    while tries > 0 and entries[i] do
        tries = tries - 1
        local object = entries[i]
        local rec = REC[object]
        if ResetFrame(object, rec, hostFrame) then
            if not rec.engine then
                return object
            end
            tremove(entries, i)
            Retire(object)
        else
            tremove(entries, i)
            entries[#entries + 1] = object
            entries.skipped = true
        end
    end
    return nil
end

local function AcquireFrame(host, hrec, ftype, tmpl)
    local kind = tmpl and (ftype .. "|" .. tmpl) or ftype
    local pools = hrec.pools
    if not pools then
        pools = {}
        hrec.pools = pools
        hrec.cur = {}
    end
    local entries = pools[kind]
    if not entries then
        entries = {}
        pools[kind] = entries
    end
    local i = (hrec.cur[kind] or 0) + 1
    local object = TakeFrame(entries, i, host)
    if not object then
        object = _G.CreateFrame(ftype, nil, host, tmpl)
        RegisterFrame(object, NewFrameRec("pooled", kind, ftype, tmpl, host))
        tinsert(entries, i, object)
    end
    hrec.cur[kind] = i
    return object
end

AcquireRegion = function(host, kind, method, layer, sub)
    local hrec = REC[host]
    local pools = hrec.pools
    if not pools then
        pools = {}
        hrec.pools = pools
        hrec.cur = {}
    end
    local entries = pools[kind]
    if not entries then
        entries = {}
        pools[kind] = entries
    end
    local i = (hrec.cur[kind] or 0) + 1
    -- the draw layer a new region of this call gets (the engine default when unset)
    local nLayer = layer or "ARTWORK"
    local nSub = (kind ~= "FontString" and tonumber(sub)) or 0
    local object = entries[i]
    if object then
        ResetRegion(object, REC[object], host, nLayer, nSub)
    else
        if kind == "FontString" then
            object = getmetatable(host).__index.CreateFontString(host, nil, layer)
        else
            object = getmetatable(host).__index[method](host, nil, layer, nil, sub)
        end
        REC[object] = {
            cls = "pooled",
            kind = kind,
            host = host,
            gen = 1,
            idle = false,
            region = true,
            layer = nLayer,
            sub = nSub,
            thick = kind == "Line" and object.GetThickness and object:GetThickness() or nil,
        }
        Install(object, REGION_OVERRIDES)
        if kind == "Texture" then
            Install(object, TEX_OVERRIDES)
        end
        entries[i] = object
    end
    hrec.cur[kind] = i
    return object
end

AcquireAG = function(host)
    local hrec = REC[host]
    local pools = hrec.pools
    if not pools then
        pools = {}
        hrec.pools = pools
        hrec.cur = {}
    end
    local entries = pools.AnimationGroup
    if not entries then
        entries = {}
        pools.AnimationGroup = entries
    end
    local i = (hrec.cur.AnimationGroup or 0) + 1
    local ag = entries[i]
    if ag then
        ResetAG(ag, REC[ag])
        if REC[ag].unfit then
            RetireAG(ag)
            ag = nil
        end
    end
    if not ag then
        ag = getmetatable(host).__index.CreateAnimationGroup(host)
        REC[ag] = { cls = "pooled", kind = "AnimationGroup", host = host, gen = 1, idle = false, isAG = true }
        Install(ag, AG_OVERRIDES)
        entries[i] = ag
    end
    hrec.cur.AnimationGroup = i
    return ag
end

AcquireAnim = function(ag, atype)
    local grec = REC[ag]
    local pools = grec.pools
    if not pools then
        pools = {}
        grec.pools = pools
        grec.cur = {}
    end
    local kind = atype or "Animation"
    local entries = pools[kind]
    if not entries then
        entries = {}
        pools[kind] = entries
    end
    local i = (grec.cur[kind] or 0) + 1
    local a = entries[i]
    if a then
        local ar = REC[a]
        -- reset with its group, unless a play quieted it since
        if ar.fresh and not ar.inert then
            ar.fresh = nil
        else
            ResetAnim(a, ar)
            ar.fresh = nil
        end
        ar.idle = false
    else
        a = getmetatable(ag).__index.CreateAnimation(ag, atype)
        REC[a] = { cls = "pooled", kind = kind, host = ag, gen = 1, idle = false, isAnim = true }
        Install(a, ANIM_OVERRIDES)
        entries[i] = a
    end
    grec.cur[kind] = i
    return a
end

-------------------------------------------------------------------------------
--  Public API
-------------------------------------------------------------------------------
local function CanonicalType(ftype)
    if type(ftype) ~= "string" then
        return nil
    end
    return FRAME_TYPES[ftype] or FRAME_TYPES[ftype:lower()]
end

function Pool.CreateFrame(ftype, name, hostFrame, tmpl, ident)
    if name == nil and ident == nil and hostFrame ~= nil and not CludesUI._prebuilding then
        local prec = REC[hostFrame]
        if prec and prec.isFrame and (tmpl == nil or TEMPLATES[tmpl]) then
            local ft = CanonicalType(ftype)
            if ft then
                return AcquireFrame(hostFrame, prec, ft, tmpl)
            end
        end
    end
    return _G.CreateFrame(ftype, name, hostFrame, tmpl, ident)
end

-- A new frame for Pool.Kept, hidden when asked (it has no OnShow script yet,
-- so nothing runs).
local function NewKept(object, hidden)
    if hidden and object:IsShown() then
        object:Hide()
    end
    return object, true
end

-- Every reset of a kept frame starts a pass on it (ResetContents).
function Pool.Kept(ownerFrame, key, ftype, hostFrame, tmpl, name, hidden)
    if CludesUI._prebuilding or ownerFrame == nil or key == nil then
        return NewKept(_G.CreateFrame(ftype, name, hostFrame, tmpl), hidden)
    end
    local ft = CanonicalType(ftype)
    if not ft or (tmpl ~= nil and not TEMPLATES[tmpl]) then
        return NewKept(_G.CreateFrame(ftype, name, hostFrame, tmpl), hidden)
    end
    RefreshDev()
    local map = KEPT[ownerFrame]
    if not map then
        map = {}
        KEPT[ownerFrame] = map
    end
    local object = map[key]
    if object then
        local rec = REC[object]
        if rec and ResetFrame(object, rec, hostFrame, PASS_RESET, hidden) and not rec.engine then
            rec.host = hostFrame
            return object, false
        end
        map[key] = nil
        Retire(object)
    end
    object = _G.CreateFrame(ft, name, hostFrame, tmpl)
    local rec = NewFrameRec("kept", tmpl and (ft .. "|" .. tmpl) or ft, ft, tmpl, hostFrame)
    rec.key = key
    RegisterFrame(object, rec)
    map[key] = object
    return NewKept(object, hidden)
end

function Pool.Owned(ownerFrame, labelText, ftype, hostFrame, tmpl)
    local ft = CanonicalType(ftype)
    if CludesUI._prebuilding or ownerFrame == nil or not ft or (tmpl ~= nil and not TEMPLATES[tmpl]) then
        return _G.CreateFrame(ftype, nil, hostFrame, tmpl)
    end
    local om = OWNED[ownerFrame]
    if not om then
        om = {}
        OWNED[ownerFrame] = om
    end
    local skey = tostring(labelText) .. "|" .. ft .. "|" .. (tmpl or "")
    local slot = om[skey]
    if not slot then
        slot = { list = {}, cur = 0 }
        om[skey] = slot
    end
    local i = slot.cur + 1
    local object = TakeFrame(slot.list, i, hostFrame)
    if not object then
        object = _G.CreateFrame(ft, nil, hostFrame, tmpl)
        local rec = NewFrameRec("owned", tmpl and (ft .. "|" .. tmpl) or ft, ft, tmpl, hostFrame)
        RegisterFrame(object, rec)
        tinsert(slot.list, i, object)
    end
    local orec = REC[object]
    orec.host = hostFrame
    slot.cur = i
    return object
end

function Pool.Begin(host)
    if CludesUI._prebuilding then
        return
    end
    local rec = REC[host]
    if not (rec and rec.isFrame) then
        return
    end
    RefreshDev()
    ResetContents(host, rec, KindInfo(rec), PASS_BEGIN)
    -- the host itself is not reset: its own engine regions stay as they are
    local named = rec.engRegs
    if named then
        for k in pairs(named) do
            named[k] = nil
        end
    end
end

-- What shows over a kept host and is placed by its parts is pinned as the
-- start of its next pass would pin it, with nothing reset: for code that moves
-- what the host is placed by before that pass starts (the panel collapses the
-- content header before its header root is dressed again). The pass then
-- finds those objects placed by what the host is placed by and leaves them.
function Pool.Pin(host)
    if CludesUI._prebuilding then
        return
    end
    local rec = REC[host]
    if rec and rec.isFrame then
        FreezeUnder(host, rec, true)
    end
end

-- Records whenever obj is a pooled object, also during the global search's
-- prebuild (a live pooled object a prebuild builder touches stays managed).
function Pool.Keep(object)
    local rec = REC[object]
    if not rec or rec.cls ~= "pooled" then
        return object
    end
    local hrec = REC[rec.host]
    local entries = hrec and hrec.pools and hrec.pools[rec.kind]
    if entries then
        for i = 1, #entries do
            if entries[i] == object then
                tremove(entries, i)
                local c = hrec.cur[rec.kind] or 0
                if i <= c then
                    hrec.cur[rec.kind] = c - 1
                end
                break
            end
        end
    end
    rec.cls = "keep"
    if hrec then
        local att = hrec.attach
        if not att then
            att = {}
            hrec.attach = att
        end
        att[#att + 1] = object
    end
    return object
end

-- Records whenever host is a pooled object, also during the global search's
-- prebuild (a border made then on a live pooled frame must stay on it).
function Pool.Attach(host, object, key, onReset)
    if object == nil then
        return false
    end
    local hrec = REC[host]
    if not hrec then
        return false
    end
    local orec = REC[object]
    if orec and orec.cls ~= "attach" then
        return false
    end
    if not orec then
        orec = { cls = "attach" }
        REC[object] = orec
    end
    if orec.host ~= host then
        orec.host = host
        local att = hrec.attach
        if not att then
            att = {}
            hrec.attach = att
        end
        -- listed once per host, however often it moves between hosts
        local listed = false
        for i = 1, #att do
            if att[i] == object then
                listed = true
                break
            end
        end
        if not listed then
            att[#att + 1] = object
        end
    end
    orec.onReset = onReset
    if key ~= nil then
        local ks = hrec.attachKeys
        if not ks then
            ks = {}
            hrec.attachKeys = ks
        end
        ks[key] = true
    end
    return true
end

function Pool.Gen(object)
    local r = object and REC[object]
    return r and r.gen
end

function Pool.IsIdle(object)
    local r = object and REC[object]
    return (r and r.idle) and true or false
end

-- True for every object the pool manages (pooled, kept, owned, kept by module
-- state, attached); false for objects made without it.
function Pool.Managed(object)
    return object ~= nil and REC[object] ~= nil
end

-- The slots survive every later reset; a later dress that sets or hooks one
-- again is reported in dev mode (ExemptSlot).
function Pool.ExemptScripts(object, ...)
    local rec = object and REC[object]
    if not rec then
        return
    end
    local ex = rec.exempt
    if not ex then
        ex = {}
        rec.exempt = ex
    end
    if rec.exemptGen == nil then
        rec.exemptGen = rec.gen
    end -- the dress that first exempted
    for i = 1, select("#", ...) do
        local slot = select(i, ...)
        ex[slot] = true
        if rec.scripts then
            rec.scripts[slot] = nil
        end
    end
end

-- Dev mode: pooled objects anywhere under a host (its pools, and the pools of
-- every object it handed out) that are idle yet shown were shown by code
-- outside the pool (an object kept by module state).
local function DevIdleShown(rec, labelText, level)
    local pools = rec.pools
    if not pools or level > 16 then
        return
    end
    for kind, entries in pairs(pools) do
        for i = 1, #entries do
            local o = entries[i]
            local r = REC[o]
            if r and not r.isAG then
                if r.idle then
                    if o:IsShown() then
                        DevWarn(
                            "idleshown:" .. tostring(labelText) .. kind,
                            "an idle "
                                .. kind
                                .. " shows on "
                                .. tostring(labelText)
                                .. " (kept by module state?)"
                        )
                    end
                else
                    DevIdleShown(r, labelText, level + 1)
                end
            end
        end
    end
end
function Pool._DevEndPass(host, labelText)
    if not devOn or host == nil then
        return
    end
    local rec = REC[host]
    if rec then
        DevIdleShown(rec, labelText, 0)
    end
    -- kept frames another owner placed on this host (a section a module keeps
    -- on a page wrapper) hold pools of their own: walked too
    for _, map in pairs(KEPT) do
        for _, k in pairs(map) do
            local kr = REC[k]
            if kr and kr.host == host then
                DevIdleShown(kr, tostring(labelText) .. "/" .. tostring(kr.key), 0)
            end
        end
    end
end

-- In-game check (/dump CludesUI._Pool._DevCounts()): the objects the pool
-- holds by class, how many are idle, and what the graveyard holds. Never called
-- by the suite.
function Pool._DevCounts()
    local c =
        { pooled = 0, kept = 0, owned = 0, keep = 0, attach = 0, placeholder = 0, idle = 0, graveyard = 0 }
    for _, r in pairs(REC) do
        local cls = r.cls
        c[cls] = (c[cls] or 0) + 1
        if r.idle then
            c.idle = c.idle + 1
        end
    end
    if graveyard then
        c.graveyard = select("#", graveyard:GetChildren()) + select("#", graveyard:GetRegions())
    end
    return c
end

-- Harness / debugging accessor: obj is a scroll frame's hidden placeholder child
-- (ResetFrame, ReleaseScrollChild), which stands for "no scroll child".
function Pool._IsPlaceholder(object)
    local r = object and REC[object]
    return (r and r.cls == "placeholder") and true or false
end

-- Harness hook (pagereuse harness reset-fuzz): resets obj exactly as the pool
-- does before handing it out again on the same host.
function Pool._ResetForTest(object)
    local rec = object and REC[object]
    if not rec then
        return false
    end
    if rec.region then
        ResetRegion(object, rec, rec.host, rec.layer, rec.sub)
        return true
    elseif rec.isAG then
        ResetAG(object, rec)
        return true
    elseif rec.isAnim then
        ResetAnim(object, rec)
        return true
    end
    return ResetFrame(object, rec, rec.host)
end

-------------------------------------------------------------------------------
--  In-game self-check of the reset (dev tool, never called by the suite):
--  /run CludesUI._Pool._DevVerifyReset()
--  For each pooled kind, a pooled object is changed by the setters options code
--  uses on that kind (and the ones its reset relies on SetToDefaults for), is
--  reset as the pool resets it, and then it and a new object get the same
--  dress and are compared getter by getter. The engine's regions of known
--  roles must draw nothing after the reset and match a new object's once both
--  are set again. Prints every difference, then a summary.
-------------------------------------------------------------------------------
local verifyOwner
function Pool._DevVerifyReset()
    if _G.InCombatLockdown() then
        CludesUI.PrintError("pool check: out of combat only")
        return
    end
    RefreshDev()
    local unpack, max, abs = _G.unpack, math.max, math.abs
    local EMPTY = {}
    local NOOP = function() end
    local ART = PROBE_ART
    local FONT = "Fonts\\FRIZQT__.TTF"
    local result, kinds = {}, 0
    refusedLog = {}
    verifyOwner = verifyOwner or {}
    local host = Pool.Kept(verifyOwner, "host", "Frame", _G.UIParent)
    host:Hide()
    host:SetSize(200, 200)
    host:SetPoint("CENTER")

    -- a vector (a texture's rotation point) prints its values
    local function Fmt(val)
        if type(val) == "table" and type(val.GetXY) == "function" then
            local posX, posY = val:GetXY()
            if type(posX) == "number" and type(posY) == "number" then
                return string.format("(%.3f, %.3f)", posX, posY)
            end
        end
        return tostring(val)
    end
    local function Say(kind, what, va, vb)
        result[#result + 1] = kind .. " " .. what .. ": new=" .. Fmt(va) .. " reset=" .. Fmt(vb)
    end
    local function Packed(...)
        return { n = select("#", ...), ... }
    end
    -- a getter's results on both objects; ownA / ownB stand for each other
    local function Compare(kind, labelText, a, b, get, ga, ownA, ownB)
        local fa, fb = a[get], b[get]
        if type(fa) ~= "function" or type(fb) ~= "function" then
            return
        end
        local ra = Packed(pcall(fa, a, unpack(ga or EMPTY)))
        local rb = Packed(pcall(fb, b, unpack(ga or EMPTY)))
        if not ra[1] and not rb[1] then
            return
        end
        if ra[1] ~= rb[1] then
            Say(kind, labelText or get, ra[1] and "ok" or "error", rb[1] and "ok" or "error")
            return
        end
        for i = 2, max(ra.n, rb.n) do
            local posX, posY = ra[i], rb[i]
            local same
            if type(posX) == "number" and type(posY) == "number" then
                same = abs(posX - posY) < 0.001
            else
                same = SameVal(posX, posY) or (ownA ~= nil and posX == ownA and posY == ownB)
            end
            if not same then
                Say(kind, (labelText or get) .. (i > 2 and ("#" .. (i - 1)) or ""), posX, posY)
                return
            end
        end
    end
    -- one change on the pooled object: the setter with values, or the opposite
    -- of the new object's flag
    local function Mutate(a, b, c)
        if c.key then
            b[c.key] = true
            return
        end
        local set = b[c[1]]
        if type(set) ~= "function" then
            return
        end
        if c.flip then
            local fg = a[c.flip]
            if type(fg) ~= "function" then
                return
            end
            local success, val = pcall(fg, a)
            if success then
                pcall(set, b, not val)
            end
        elseif type(c.v) == "function" then
            pcall(set, b, c.v(host))
        else
            pcall(set, b, unpack(c.v or EMPTY))
        end
    end
    local function Check(kind, a, b, c)
        if c.key then
            if rawget(a, c.key) ~= rawget(b, c.key) then
                Say(kind, "key " .. c.key, rawget(a, c.key), rawget(b, c.key))
            end
            return
        end
        local get = c.get or c.flip
        if get then
            Compare(kind, nil, a, b, get, c.ga, a, b)
        end
    end

    local FRAME = {
        { "SetAlpha", v = { 0.5 }, get = "GetAlpha" },
        { "SetScale", v = { 0.8 }, get = "GetScale" },
        { "EnableMouse", flip = "IsMouseEnabled" },
        { "EnableMouseWheel", flip = "IsMouseWheelEnabled" },
        { "SetMouseClickEnabled", flip = "IsMouseClickEnabled" },
        { "SetMouseMotionEnabled", flip = "IsMouseMotionEnabled" },
        { "EnableKeyboard", flip = "IsKeyboardEnabled" },
        { "SetClipsChildren", flip = "DoesClipChildren" },
        { "SetClampedToScreen", flip = "IsClampedToScreen" },
        { "SetClampRectInsets", v = { 1, 2, 3, 4 }, get = "GetClampRectInsets" },
        { "SetHitRectInsets", v = { 1, 2, 3, 4 }, get = "GetHitRectInsets" },
        { "SetMovable", flip = "IsMovable" },
        { "SetResizable", flip = "IsResizable" },
        { "SetIgnoreParentAlpha", flip = "IsIgnoringParentAlpha" },
        { "SetIgnoreParentScale", flip = "IsIgnoringParentScale" },
        { "SetID", v = { 7 }, get = "GetID" },
        { "SetToplevel", flip = "IsToplevel" },
        { "SetFrameStrata", v = { "DIALOG" }, get = "GetFrameStrata" },
        { "SetFrameLevel", v = { 50 }, get = "GetFrameLevel" },
        { "SetFixedFrameStrata", flip = "HasFixedFrameStrata" },
        { "SetFixedFrameLevel", flip = "HasFixedFrameLevel" },
        { "SetFlattensRenderLayers", flip = "GetFlattensRenderLayers" },
        { "SetPropagateKeyboardInput", flip = "GetPropagateKeyboardInput" },
        { "SetPropagateMouseClicks", flip = "CanPropagateMouseClicks" },
        { "SetPropagateMouseMotion", flip = "CanPropagateMouseMotion" },
        {
            "SetPassThroughButtons",
            v = { "LeftButton" },
            get = "ShouldButtonPassThrough",
            ga = { "LeftButton" },
        },
        { "SetAttribute", v = { "cuiPoolCheck", 1 }, get = "GetAttribute", ga = { "cuiPoolCheck" } },
        { "Hide", get = "IsShown" },
        { "SetScript", v = { "OnEnter", NOOP }, get = "GetScript", ga = { "OnEnter" } },
        { "HookScript", v = { "OnLeave", NOOP }, get = "GetScript", ga = { "OnLeave" } },
        {
            "RegisterEvent",
            v = { "PLAYER_TARGET_CHANGED" },
            get = "IsEventRegistered",
            ga = { "PLAYER_TARGET_CHANGED" },
        },
        { key = "_cuiPoolCheck" },
    }
    local BUTTON = {
        { "Disable", get = "IsEnabled" },
        { "SetMotionScriptsWhileDisabled", flip = "GetMotionScriptsWhileDisabled" },
        { "SetButtonState", v = { "PUSHED", true }, get = "GetButtonState" },
        { "SetPushedTextOffset", v = { 5, -5 }, get = "GetPushedTextOffset" },
        {
            "SetNormalFontObject",
            v = function()
                return _G.GameFontNormal
            end,
            get = "GetNormalFontObject",
        },
        {
            "SetHighlightFontObject",
            v = function()
                return _G.GameFontHighlight
            end,
            get = "GetHighlightFontObject",
        },
        {
            "SetDisabledFontObject",
            v = function()
                return _G.GameFontDisable
            end,
            get = "GetDisabledFontObject",
        },
    }
    local CHECK = { { "SetChecked", flip = "GetChecked" } }
    local EDIT = {
        { "SetMaxLetters", v = { 5 }, get = "GetMaxLetters" },
        { "SetMaxBytes", v = { 9 }, get = "GetMaxBytes" },
        { "SetNumeric", flip = "IsNumeric" },
        { "SetMultiLine", flip = "IsMultiLine" },
        { "SetTextInsets", v = { 1, 2, 3, 4 }, get = "GetTextInsets" },
        { "SetAutoFocus", flip = "IsAutoFocus" },
        { "SetJustifyH", v = { "RIGHT" }, get = "GetJustifyH" },
        { "SetJustifyV", v = { "TOP" }, get = "GetJustifyV" },
        { "SetSpacing", v = { 3 }, get = "GetSpacing" },
        { "SetTextColor", v = { 1, 0, 0, 1 }, get = "GetTextColor" },
        { "SetHighlightColor", v = { 1, 0, 0, 1 }, get = "GetHighlightColor" },
        { "SetText", v = { "abc" }, get = "GetText" },
        { "SetCountInvisibleLetters", flip = "IsCountInvisibleLetters" },
        { "Disable", get = "IsEnabled" },
    }
    local SCROLL = {
        { "SetVerticalScroll", v = { 10 }, get = "GetVerticalScroll" },
        { "SetHorizontalScroll", v = { 5 }, get = "GetHorizontalScroll" },
    }
    local BAR = {
        { "SetMinMaxValues", v = { 0, 10 }, get = "GetMinMaxValues" },
        { "SetValue", v = { 5 }, get = "GetValue" },
        { "SetOrientation", v = { "VERTICAL" }, get = "GetOrientation" },
        { "SetReverseFill", flip = "GetReverseFill" },
        { "SetFillStyle", v = { "CENTER" }, get = "GetFillStyle" },
        { "SetRotatesTexture", flip = "GetRotatesTexture" },
        { "SetStatusBarDesaturated", flip = "IsStatusBarDesaturated" },
        { "SetStatusBarColor", v = { 1, 0, 0, 1 }, get = "GetStatusBarColor" },
    }
    local CD = {
        { "SetDrawEdge", flip = "GetDrawEdge" },
        { "SetDrawSwipe", flip = "GetDrawSwipe" },
        { "SetDrawBling", flip = "GetDrawBling" },
        { "SetReverse", flip = "GetReverse" },
        { "SetHideCountdownNumbers", flip = "GetHideCountdownNumbers" },
        { "SetEdgeScale", v = { 2 }, get = "GetEdgeScale" },
        { "SetRotation", v = { 1 }, get = "GetRotation" },
        { "SetCountdownAbbrevThreshold", v = { 5 }, get = "GetCountdownAbbrevThreshold" },
        { "SetMinimumCountdownDuration", v = { 3 }, get = "GetMinimumCountdownDuration" },
        { "SetUseAuraDisplayTime", flip = "GetUseAuraDisplayTime" },
        {
            "SetCooldown",
            v = function()
                return _G.GetTime(), 30
            end,
            get = "GetCooldownDuration",
        },
    }
    local MODEL = {
        { "SetFacing", v = { 1 }, get = "GetFacing" },
        { "SetPosition", v = { 1, 2, 3 }, get = "GetPosition" },
        { "SetModelScale", v = { 2 }, get = "GetModelScale" },
        { "SetCamDistanceScale", v = { 2 }, get = "GetCamDistanceScale" },
        { "SetPortraitZoom", v = { 0.5 }, get = "GetPortraitZoom" },
        -- the reset's ClearModel empties the model, but GetModelFileID keeps
        -- reporting the last one, so it is not compared (each dress sets its own)
        { "SetUnit", v = { "player" } },
    }
    local REGION = {
        { "SetAlpha", v = { 0.5 }, get = "GetAlpha" },
        { "Hide", get = "IsShown" },
        { "SetIgnoreParentAlpha", flip = "IsIgnoringParentAlpha" },
        { "SetIgnoreParentScale", flip = "IsIgnoringParentScale" },
        { "SetDrawLayer", v = { "OVERLAY", 3 }, get = "GetDrawLayer" },
        { "SetScale", v = { 0.8 }, get = "GetScale" },
        { key = "_cuiPoolCheck" },
    }
    local TEX = {
        { "SetTexture", v = { ART }, get = "GetTexture" },
        { "SetVertexColor", v = { 1, 0, 0, 0.5 }, get = "GetVertexColor" },
        { "SetTexCoord", v = { 0.1, 0.9, 0.1, 0.9 }, get = "GetTexCoord" },
        { "SetDesaturated", flip = "IsDesaturated" },
        { "SetDesaturation", v = { 0.5 }, get = "GetDesaturation" },
        { "SetBlendMode", v = { "ADD" }, get = "GetBlendMode" },
        { "SetRotation", v = { 1 }, get = "GetRotation" },
        { "SetHorizTile", flip = "GetHorizTile" },
        { "SetVertTile", flip = "GetVertTile" },
        { "SetTextureSliceMargins", v = { 1, 2, 3, 4 }, get = "GetTextureSliceMargins" },
        { "SetTextureSliceMode", v = { 1 }, get = "GetTextureSliceMode" },
        { "SetVertexOffset", v = { 1, 2, 3 }, get = "GetVertexOffset", ga = { 1 } },
        {
            "AddMaskTexture",
            v = function(hgt)
                return hgt:CreateMaskTexture()
            end,
            get = "GetNumMaskTextures",
        },
    }
    local FS = {
        { "SetText", v = { "x" }, get = "GetText" },
        { "SetTextColor", v = { 1, 0, 0, 1 }, get = "GetTextColor" },
        { "SetShadowColor", v = { 1, 0, 0, 1 }, get = "GetShadowColor" },
        { "SetShadowOffset", v = { 2, -2 }, get = "GetShadowOffset" },
        { "SetJustifyH", v = { "RIGHT" }, get = "GetJustifyH" },
        { "SetJustifyV", v = { "TOP" }, get = "GetJustifyV" },
        { "SetWordWrap", flip = "CanWordWrap" },
        { "SetNonSpaceWrap", flip = "CanNonSpaceWrap" },
        { "SetMaxLines", v = { 2 }, get = "GetMaxLines" },
        { "SetSpacing", v = { 3 }, get = "GetSpacing" },
        { "SetIndentedWordWrap", flip = "GetIndentedWordWrap" },
        { "SetTextScale", v = { 1.5 }, get = "GetTextScale" },
    }
    local LINE = {
        { "SetThickness", v = { 3 }, get = "GetThickness" },
        { "SetColorTexture", v = { 1, 0, 0, 1 } },
    }
    local AG = {
        { "SetLooping", v = { "REPEAT" }, get = "GetLooping" },
        { "SetToFinalAlpha", flip = "IsSetToFinalAlpha" },
        { "SetAnimationSpeedMultiplier", v = { 2 }, get = "GetAnimationSpeedMultiplier" },
        { "SetScript", v = { "OnFinished", NOOP }, get = "GetScript", ga = { "OnFinished" } },
        { key = "_cuiPoolCheck" },
    }
    local ALPHA = {
        { "SetDuration", v = { 1 }, get = "GetDuration" },
        { "SetStartDelay", v = { 1 }, get = "GetStartDelay" },
        { "SetEndDelay", v = { 1 }, get = "GetEndDelay" },
        { "SetOrder", v = { 2 }, get = "GetOrder" },
        { "SetFromAlpha", v = { 0.2 }, get = "GetFromAlpha" },
        { "SetToAlpha", v = { 0.7 }, get = "GetToAlpha" },
        {
            "SetTarget",
            v = function(hgt)
                return hgt
            end,
            get = "GetTarget",
        },
    }
    -- an engine region's look, compared on both objects once both have it
    local REGION_LOOK = {
        "IsShown",
        "GetDrawLayer",
        "GetNumPoints",
        "GetPoint",
        "GetBlendMode",
        "GetVertexColor",
        "IsDesaturated",
        "GetTexCoord",
        "GetAlpha",
        "GetTexture",
        "GetAtlas",
        "GetText",
        "GetFont",
        "GetTextColor",
        "GetJustifyH",
        "GetJustifyV",
    }

    local function Run(kind, entries, a, b, dress)
        kinds = kinds + 1
        for _, part in ipairs(entries) do
            for _, c in ipairs(part) do
                Mutate(a, b, c)
            end
        end
        return function()
            dress(a)
            dress(b)
            for _, part in ipairs(entries) do
                for _, c in ipairs(part) do
                    Check(kind, a, b, c)
                end
            end
        end
    end
    local function DressFrame(o)
        o:SetSize(40, 20)
        o:ClearAllPoints()
        o:SetPoint("CENTER", host)
        if o.SetFont and o:GetObjectType() == "EditBox" then
            o:SetFont(FONT, 12, "")
        end
    end

    local function VerifyFrame(ftype, tmpl, entries)
        local kind = tmpl and (ftype .. "|" .. tmpl) or ftype
        local a = _G.CreateFrame(ftype, nil, host, tmpl)
        local b = Pool.CreateFrame(ftype, nil, host, tmpl)
        if not REC[b] then
            Say(kind, "pool", "pooled", "not pooled")
            return
        end
        local finish = Run(kind, entries, a, b, DressFrame)
        local roles = ENGINE_ROLES[ftype]
        if roles then
            for _, role in ipairs(roles) do
                if role.make and b[role.make] then
                    if role.text then
                        pcall(b.SetNormalFontObject, b, _G.GameFontNormal)
                    end
                    pcall(b[role.make], b, role.text and "x" or ART)
                end
                local reg = b[role.get] and SafeCall(b[role.get], b)
                if reg then
                    if reg.SetVertexColor then
                        pcall(reg.SetVertexColor, reg, 1, 0, 0, 0.5)
                    end
                    if reg.SetTextColor then
                        pcall(reg.SetTextColor, reg, 1, 0, 0, 1)
                    end
                    pcall(reg.SetAlpha, reg, 0.5)
                    pcall(reg.ClearAllPoints, reg)
                end
            end
        end
        if ftype == "ScrollFrame" then
            local childFrame = _G.CreateFrame("Frame", nil, b)
            childFrame:SetSize(10, 500)
            b:SetScrollChild(childFrame)
        end
        Pool._ResetForTest(b)
        finish()
        if ftype == "ScrollFrame" then
            local ca, cb = a:GetScrollChild(), b:GetScrollChild()
            if ca ~= nil or (cb ~= nil and not Pool._IsPlaceholder(cb)) then
                Say(kind, "GetScrollChild", ca, cb)
            end
        end
        if roles then
            for _, role in ipairs(roles) do
                local ga, gb = a[role.get], b[role.get]
                local ra = ga and SafeCall(ga, a)
                local rb = gb and SafeCall(gb, b)
                if rb and not role.live and ra == nil and rb:IsShown() then
                    local drawn = (rb.GetTexture and (rb:GetTexture() or (rb.GetAtlas and rb:GetAtlas())))
                        or (rb.GetText and rb:GetText() ~= "" and rb:GetText())
                    if drawn then
                        Say(kind, role.get .. " after the reset", "none", drawn)
                    end
                end
                if role.make and a[role.make] then
                    if role.text then
                        pcall(a.SetNormalFontObject, a, _G.GameFontNormal)
                        pcall(b.SetNormalFontObject, b, _G.GameFontNormal)
                    end
                    pcall(a[role.make], a, role.text and "y" or ART)
                    pcall(b[role.make], b, role.text and "y" or ART)
                    ra = ga and SafeCall(ga, a)
                    rb = gb and SafeCall(gb, b)
                end
                if ra and rb then
                    for _, g in ipairs(REGION_LOOK) do
                        Compare(kind, role.get .. ":" .. g, ra, rb, g, g == "GetPoint" and { 1 } or nil, a, b)
                    end
                elseif (ra == nil) ~= (rb == nil) and (role.make or role.live) then
                    Say(kind, role.get, ra, rb)
                end
            end
        end
        a:Hide()
        a:SetParent(Graveyard())
    end

    local function VerifyRegion(kind, method, entries)
        local a = getmetatable(host).__index[method](host, nil, "ARTWORK")
        local b = host[method](host, nil, "ARTWORK")
        if not REC[b] then
            Say(kind, "pool", "pooled", "not pooled")
            return
        end
        local finish = Run(kind, entries, a, b, function(o)
            o:ClearAllPoints()
            if kind == "Line" then
                o:SetStartPoint("TOPLEFT", host)
                o:SetEndPoint("BOTTOMRIGHT", host)
            else
                o:SetSize(32, 16)
                o:SetPoint("CENTER", host)
            end
            if kind == "FontString" then
                o:SetFont(FONT, 12, "")
                o:SetText("Fuzz")
            end
        end)
        Pool._ResetForTest(b)
        finish()
        a:Hide()
        a:SetParent(Graveyard())
    end

    local function VerifyAnimations()
        local fa = getmetatable(host).__index.CreateAnimationGroup(host)
        local faA = fa:CreateAnimation("Alpha")
        local gb = host:CreateAnimationGroup()
        local gbA = gb:CreateAnimation("Alpha")
        if not REC[gb] then
            Say("AnimationGroup", "pool", "pooled", "not pooled")
            return
        end
        kinds = kinds + 1
        for _, c in ipairs(AG) do
            Mutate(fa, gb, c)
        end
        for _, c in ipairs(ALPHA) do
            Mutate(faA, gbA, c)
        end
        Pool._ResetForTest(gb)
        for _, c in ipairs(AG) do
            Check("AnimationGroup", fa, gb, c)
        end
        for _, c in ipairs(ALPHA) do
            Check("Alpha", faA, gbA, c)
        end
    end

    VerifyFrame("Frame", nil, { FRAME })
    VerifyFrame("Frame", "BackdropTemplate", { FRAME })
    VerifyFrame("Button", nil, { FRAME, BUTTON })
    VerifyFrame("CheckButton", nil, { FRAME, BUTTON, CHECK })
    VerifyFrame("EditBox", nil, { FRAME, EDIT })
    VerifyFrame("ScrollFrame", nil, { FRAME, SCROLL })
    VerifyFrame("StatusBar", nil, { FRAME, BAR })
    VerifyFrame("Cooldown", "CooldownFrameTemplate", { FRAME, CD })
    VerifyFrame("PlayerModel", nil, { FRAME, MODEL })
    VerifyRegion("Texture", "CreateTexture", { REGION, TEX })
    VerifyRegion("FontString", "CreateFontString", { REGION, FS })
    VerifyRegion(
        "MaskTexture",
        "CreateMaskTexture",
        { REGION, { { "SetTexture", v = { ART }, get = "GetTexture" } } }
    )
    VerifyRegion("Line", "CreateLine", { REGION, LINE })
    VerifyAnimations()
    -- an edit box whose history lines changed: when its reset cannot put them
    -- back, the pool must retire it (never hand it out again)
    do
        local a = _G.CreateFrame("EditBox", nil, host)
        local b = Pool.CreateFrame("EditBox", nil, host)
        if REC[b] and pcall(b.SetHistoryLines, b, 5) then
            Pool._ResetForTest(b)
            local r = REC[b]
            if not SameVal(a:GetHistoryLines(), b:GetHistoryLines()) and not (r and r.engine) then
                Say("EditBox", "GetHistoryLines (handed out again)", a:GetHistoryLines(), b:GetHistoryLines())
            end
        end
        a:Hide()
        a:SetParent(Graveyard())
    end
    -- the same for an animation's smoothing: its group must be retired
    do
        local fa = getmetatable(host).__index.CreateAnimationGroup(host)
        local faA = fa:CreateAnimation("Alpha")
        local gb = host:CreateAnimationGroup()
        local gbA = gb:CreateAnimation("Alpha")
        if REC[gb] and pcall(gbA.SetSmoothing, gbA, "IN") then
            Pool._ResetForTest(gb)
            local r = REC[gb]
            if faA:GetSmoothing() ~= gbA:GetSmoothing() and not (r and r.unfit) then
                Say("Alpha", "GetSmoothing (handed out again)", faA:GetSmoothing(), gbA:GetSmoothing())
            end
        end
    end

    -- what the resets could not put back (those objects are retired)
    for i = 1, #refusedLog do
        CludesUI.Print("pool check note: " .. refusedLog[i])
    end
    refusedLog = nil
    for i = 1, #result do
        CludesUI.PrintError("pool check: " .. result[i])
    end
    CludesUI.Print(
        CludesUI.COLOR_CODES.BRAND
            .. "[CludesUI]|r pool check: "
            .. kinds
            .. " kinds, "
            .. #result
            .. " difference(s)"
            .. (#result == 0 and " -- every reset matches a new object" or "")
    )
    return #result
end

-- An options row's eye toggle shell: a 26px glyph button at the left end of
-- the region's inline controls (resting at 0.4 alpha) and the texture that
-- fills it. The caller gives it its icon, click and hover.
function CludesUI.NewInlineEye(region)
    local eye = Pool.CreateFrame("Button", nil, region)
    eye:SetSize(26, 26)
    eye:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
    eye:SetFrameLevel(region:GetFrameLevel() + 5)
    CludesUI.SetGlyphAlpha(eye, 0.4)
    region._lastInline = eye
    local glyph = eye:CreateTexture(nil, "OVERLAY")
    glyph:SetAllPoints()
    return eye, glyph
end
