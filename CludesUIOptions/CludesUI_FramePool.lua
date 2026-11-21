if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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
local CUI = _G.CludesUI
local Pool = CUI._Pool
if type(Pool) ~= "table" then
    Pool = {}
    CUI._Pool = Pool
end

local _G = _G
local type, pairs, next, select, pcall, rawget, rawset = type, pairs, next, select, pcall, rawget, rawset
local getmetatable, setmetatable, tonumber, tostring = getmetatable, setmetatable, tonumber, tostring
local tremove, tinsert = table.remove, table.insert

-- object -> record { cls, kind, host, gen, idle, ... } (weak keys: a record
-- lives exactly as long as its object)
local FrameRecs = setmetatable({}, { __mode = "k" })
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
        OnLoad = function(self, ...) return self:OnBackdropLoaded(...) end,
        OnSizeChanged = function(self, ...) return self:OnBackdropSizeChanged(...) end,
    },
}

-- An accent registry slot whose object was reset: inert until the object
-- registers again (CludesUI.lua RegAccent replaces the slot then).
local INERT_ACCENT = { type = "inert" }

-- The mouse buttons a frame may pass through (SetPassThroughButtons).
local PASS_BUTTONS = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }

local devOn = false
local function RefreshDev()
    local func = CUI.IsDevModeActive
    devOn = (func and func()) and true or false
end

-------------------------------------------------------------------------------
--  Scratch lists for the engine's vararg lists (resets can nest through OnHide
--  handlers, so each depth has its own list)
-------------------------------------------------------------------------------
local scratch, scratchN, depth = {}, {}, 0
local function Pack(...)
    depth = depth + 1
    local tbl = scratch[depth]
    if not tbl then
        tbl = {}
        scratch[depth] = tbl
    end
    local num = select("#", ...)
    for i = 1, num do
        tbl[i] = (select(i, ...))
    end
    scratchN[depth] = num
    return tbl, num
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
local function SpareParent()
    if not graveyard then
        graveyard = _G.CreateFrame("Frame")
        graveyard:Hide()
    end
    return graveyard
end
-- Harness / debugging accessor: never creates the frame.
Pool._Graveyard = function() return graveyard end

local warned = {}
local function DevWarn(key, msg)
    if not devOn or warned[key] then return end
    warned[key] = true
    CUI.PrintError("pool: " .. msg)
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
    getmetatable(o).__index.SetParent(o, SpareParent())
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
    if success then return val end
    return nil
end

-- Kept values (KEPT_VALUES, ANIM_KEPT): read on a probe, compared and put back.
local abs, unpack = math.abs, _G.unpack
local function PackOK(success, ...)
    if not success then return nil end
    return { n = select("#", ...), ... }
end
-- Two values are the same: numbers within rounding, vectors (Vector2DMixin) by value.
local function SameVal(posX, cursorY)
    if posX == cursorY then return true end
    local tx, ty = type(posX), type(cursorY)
    if tx == "number" and ty == "number" then return abs(posX - cursorY) < 0.0001 end
    if
        tx == "table"
        and ty == "table"
        and type(posX.GetXY) == "function"
        and type(cursorY.GetXY) == "function"
    then
        local ax, ay = posX:GetXY()
        local bx, by = cursorY:GetXY()
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
        if not SameVal(vals[i], (select(i, ...))) then return true end
    end
    return false
end
-- pairs: { { getter name, setter name }, ... }; probe: a new object of the kind.
-- Returns the pairs the probe has, each with the probe's values.
local function CaptureKept(probe, pairsList)
    local meta = getmetatable(probe).__index
    local entries
    for i = 1, #pairsList do
        local get, set = meta[pairsList[i][1]], meta[pairsList[i][2]]
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
        local keyName = entries[i]
        local vals = keyName.vals
        if Differs(vals, keyName.get(object)) then
            local done, err = pcall(keyName.set, object, unpack(vals, 1, vals.n))
            if not done or Differs(vals, keyName.get(object)) then
                success = false
                if refusedLog and #refusedLog < 50 then
                    refusedLog[#refusedLog + 1] = tostring(object:GetObjectType())
                        .. " "
                        .. keyName.name
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
    if agKept == nil then agKept = CaptureKept(ProbeHolder():CreateAnimationGroup(), AG_KEPT) or false end
    return agKept
end
local function AnimKept(kindName)
    local entries = ANIM_INFO[kindName]
    if entries == nil then
        local animGroup = ProbeHolder():CreateAnimationGroup()
        local success, a = pcall(animGroup.CreateAnimation, animGroup, kindName)
        entries = success and a and CaptureKept(a, ANIM_KEPT) or false
        ANIM_INFO[kindName] = entries
    end
    return entries
end

-- A region as the engine made it on a probe object: its draw layer, anchors
-- (relative to the object), shown state and look (a texture's blend mode; a
-- font string's font, colours and justification).
local function CaptureRegion(registry, p)
    local c = { points = {} }
    c.layer, c.sub = registry:GetDrawLayer()
    for i = 1, registry:GetNumPoints() do
        local pt, relTo, relPoint, posX, cursorY = registry:GetPoint(i)
        c.points[i] = { pt, relTo == p or relTo, relPoint, posX, cursorY }
    end
    c.shown = registry:IsShown() and true or false
    if registry.GetBlendMode then c.blend = registry:GetBlendMode() end
    if registry.GetFont then
        local filePath, size, flags = registry:GetFont()
        if filePath then c.font = { filePath, size, flags } end
        c.fontObject = registry:GetFontObject()
        c.color = { registry:GetTextColor() }
        c.shadow = { registry:GetShadowColor() }
        c.shadowOff = { registry:GetShadowOffset() }
        c.jh, c.jv = registry:GetJustifyH(), registry:GetJustifyV()
    end
    return c
end

-- Per kind, read once from a new object: its Lua keys (template mixins), its
-- input defaults, how many regions and children the engine gives it, and what
-- each engine-made region of a known role is like when new.
local KIND_INFO = {}
local function KindInfo(record)
    local kindName = record.kind
    local details = KIND_INFO[kindName]
    if details then return details end
    local p = _G.CreateFrame(record.ftype, nil, ProbeHolder(), record.tmpl)
    local meta = getmetatable(p).__index
    details = { scripts = record.tmpl and TEMPLATE_SCRIPTS[record.tmpl] or nil }
    local keyList
    for keyName, val in pairs(p) do
        if type(keyName) == "string" and keyName:byte(1) ~= 0 then
            keyList = keyList or {}
            keyList[keyName] = val
        end
    end
    details.keys = keyList
    details.mouse = p:IsMouseEnabled() and true or false
    details.wheel = (meta.IsMouseWheelEnabled and p:IsMouseWheelEnabled()) and true or false
    details.clips = (meta.DoesClipChildren and p:DoesClipChildren()) and true or false
    details.keyboard = (meta.IsKeyboardEnabled and p:IsKeyboardEnabled()) and true or false
    if record.ftype == "EditBox" then details.autoFocus = p:IsAutoFocus() and true or false end
    local kv = KEPT_VALUES[record.ftype]
    if kv then details.kept = CaptureKept(p, kv) end
    -- the engine's regions of known roles are reset in place, so they are never
    -- counted among the unnamed regions a new object starts with
    local roleMap = ENGINE_ROLES[record.ftype]
    local named = 0
    if roleMap then
        for i = 1, #roleMap do
            local get = meta[roleMap[i].get]
            if get and SafeCall(get, p) then named = named + 1 end
        end
    end
    details.nRegions = select("#", p:GetRegions()) - named
    details.nChildren = select("#", p:GetChildren())
    if roleMap then
        local eng = {}
        for i = 1, #roleMap do
            local roleName = roleMap[i]
            local get, make = meta[roleName.get], roleName.make and meta[roleName.make]
            -- the text region is measured as a dress that shows text makes it: with a font object
            if make and roleName.text and meta.SetNormalFontObject then
                pcall(meta.SetNormalFontObject, p, _G.GameFontNormal)
            end
            if make then pcall(make, p, roleName.text and " " or PROBE_ART) end
            local registry = get and SafeCall(get, p)
            if registry then eng[i] = CaptureRegion(registry, p) end
        end
        details.eng = eng
    end
    if p:IsShown() then p:Hide() end
    KIND_INFO[kindName] = details
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
        local orec = FrameRecs[ownerFrame]
        local ownerFn = CUI._WidgetTooltipOwner
        if
            (not orec or orec.gen ~= ogen)
            and ownerFn
            and ownerFn() == ownerFrame
            and CUI.HideWidgetTooltip
        then
            CUI.HideWidgetTooltip(true)
        end
    end
    if f then
        local frec = FrameRecs[f]
        local foci = _G.GetMouseFoci and _G.GetMouseFoci()
        if frec and frec.gen ~= fgen and foci and foci[1] == f and f:IsVisible() then
            local exec = _G.ExecuteFrameScript
            if exec then
                exec(f, "OnEnter", false)
            else
                local func = f:GetScript("OnEnter")
                if func then pcall(func, f, false) end
            end
        end
    end
end
local function ArmReplay()
    replayArmed = true
    local foci = _G.GetMouseFoci and _G.GetMouseFoci()
    local f = foci and foci[1]
    local frec = f and FrameRecs[f]
    if frec then
        replayFocus, replayFocusGen = f, frec.gen
    end
    local ownerFn = CUI._WidgetTooltipOwner
    local ownerFrame = ownerFn and ownerFn()
    local orec = ownerFrame and FrameRecs[ownerFrame]
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
local function ExemptSlot(self, record, slotIndex, what)
    if devOn and record.exemptGen ~= record.gen then
        local label = self.GetName and self:GetName() or "?"
        DevWarn(
            "exempt:" .. tostring(label) .. tostring(slotIndex),
            "a later dress "
                .. what
                .. " "
                .. tostring(slotIndex)
                .. " on "
                .. tostring(label)
                .. ", whose "
                .. tostring(slotIndex)
                .. " keeps its hooks through resets"
        )
    end
end

local function O_SetScript(self, slotIndex, func)
    getmetatable(self).__index.SetScript(self, slotIndex, func)
    local record = FrameRecs[self]
    if not record then return end
    if record.exempt and record.exempt[slotIndex] then
        ExemptSlot(self, record, slotIndex, "set")
        return
    end
    local cfg = record.scripts
    if not cfg then
        cfg = {}
        record.scripts = cfg
    end
    cfg[slotIndex] = true
end

local function O_HookScript(self, slotIndex, func, ...)
    local r = getmetatable(self).__index.HookScript(self, slotIndex, func, ...)
    local record = FrameRecs[self]
    if not record then return r end
    if record.exempt and record.exempt[slotIndex] then
        ExemptSlot(self, record, slotIndex, "hooked")
        return r
    end
    local cfg = record.scripts
    if not cfg then
        cfg = {}
        record.scripts = cfg
    end
    cfg[slotIndex] = true
    return r
end

local function O_SetAttribute(self, label, value)
    getmetatable(self).__index.SetAttribute(self, label, value)
    local record = FrameRecs[self]
    if record and label ~= nil then
        local a = record.attrs
        if not a then
            a = {}
            record.attrs = a
        end
        a[label] = true
    end
end

-- A scroll frame positions its scroll child, and no call clears a scroll
-- child (SetScrollChild takes no nil): the child remembers its scroll frame,
-- so its reset can hand that frame an inert placeholder instead.
local function O_SetScrollChild(self, childFrame)
    getmetatable(self).__index.SetScrollChild(self, childFrame)
    local crec = childFrame and FrameRecs[childFrame]
    if crec then crec.scrollOwner = self end
end

-- Creation goes to the pool only on an object the pool still manages (a
-- retired one creates as any frame does).
local function O_CreateTexture(self, label, layer, template, subMenu)
    if label ~= nil or template ~= nil or CUI._prebuilding or not FrameRecs[self] then
        return getmetatable(self).__index.CreateTexture(self, label, layer, template, subMenu)
    end
    return AcquireRegion(self, "Texture", "CreateTexture", layer, subMenu)
end
local function O_CreateMaskTexture(self, label, layer, template, subMenu)
    if label ~= nil or template ~= nil or CUI._prebuilding or not FrameRecs[self] then
        return getmetatable(self).__index.CreateMaskTexture(self, label, layer, template, subMenu)
    end
    return AcquireRegion(self, "MaskTexture", "CreateMaskTexture", layer, subMenu)
end
local function O_CreateLine(self, label, layer, template, subMenu)
    if label ~= nil or template ~= nil or CUI._prebuilding or not FrameRecs[self] then
        return getmetatable(self).__index.CreateLine(self, label, layer, template, subMenu)
    end
    return AcquireRegion(self, "Line", "CreateLine", layer, subMenu)
end
local function O_CreateFontString(self, label, layer, template, ...)
    if label ~= nil or template ~= nil or CUI._prebuilding or not FrameRecs[self] then
        return getmetatable(self).__index.CreateFontString(self, label, layer, template, ...)
    end
    return AcquireRegion(self, "FontString", "CreateFontString", layer, nil)
end
local function O_CreateAnimationGroup(self, label, template)
    if label ~= nil or template ~= nil or CUI._prebuilding or not FrameRecs[self] then
        return getmetatable(self).__index.CreateAnimationGroup(self, label, template)
    end
    return AcquireAG(self)
end
local function O_CreateAnimation(self, atype, label, template)
    if label ~= nil or template ~= nil or CUI._prebuilding or not FrameRecs[self] then
        return getmetatable(self).__index.CreateAnimation(self, atype, label, template)
    end
    return AcquireAnim(self, atype)
end

-- Animations a group kept from an earlier dress that the current dress did not
-- take (a group cannot drop one): pointed at a hidden region before the group
-- plays, so they change nothing (the group's next reset points them back).
local inertTarget
local function QuietLeftovers(animGroup)
    local grec = FrameRecs[animGroup]
    local poolMap = grec and grec.pools
    if not poolMap then return end
    local current = grec.cur
    for kindName, entries in pairs(poolMap) do
        for i = (current[kindName] or 0) + 1, #entries do
            local a = entries[i]
            local ar = FrameRecs[a]
            if ar and not ar.inert then
                if not inertTarget then inertTarget = ProbeHolder():CreateTexture() end
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
    if playing then QuietLeftovers(self) end
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
    local record = FrameRecs[self]
    if record then record.rotated = true end
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
        local meta = getmetatable(self).__index
        local r1, r2 = meta[setName](self, ...)
        local get = meta[getName]
        local registry = get and get(self)
        local back = registry and engHidden[registry]
        if back ~= nil then
            engHidden[registry] = nil
            if back then registry:Show() end
        end
        return r1, r2
    end
end
-- frame type -> { [setter name] = override } (made once, here)
local ENGINE_OVERRIDES = {}
for frameType, roleMap in pairs(ENGINE_ROLES) do
    local set = {}
    for i = 1, #roleMap do
        local sets = roleMap[i].sets
        if sets then
            for jdx = 1, #sets do
                set[sets[jdx]] = EngineSetter(sets[jdx], roleMap[i].get)
            end
        end
    end
    ENGINE_OVERRIDES[frameType] = set
end

-- Dev mode only: a pooled frame that something re-parents while it is idle is
-- held by module state (it must be Pool.Keep'd, plan C2).
local function O_DevSetParent(self, hostFrame, ...)
    local record = FrameRecs[self]
    if record and record.idle and record.cls == "pooled" then
        local site = _G.debugstack and _G.debugstack(2, 1, 0) or "?"
        DevWarn(
            "tripwire:" .. site,
            "an idle pooled object was re-parented (held by module state?) at " .. site
        )
    end
    return getmetatable(self).__index.SetParent(self, hostFrame, ...)
end

local function Install(object, set)
    local meta = getmetatable(object).__index
    for label, func in pairs(set) do
        if rawget(meta, label) ~= nil then rawset(object, label, func) end
    end
end

-- A retired frame drops the pool's instance overrides: a plain frame again.
local function StripOverrides(object, frameType)
    for label, func in pairs(FRAME_OVERRIDES) do
        if rawget(object, label) == func then rawset(object, label, nil) end
    end
    local eng = ENGINE_OVERRIDES[frameType]
    if eng then
        for label, func in pairs(eng) do
            if rawget(object, label) == func then rawset(object, label, nil) end
        end
    end
    if rawget(object, "SetParent") == O_DevSetParent then rawset(object, "SetParent", nil) end
end

local function NewFrameRec(cls, kindName, frameType, template, hostFrame)
    return {
        cls = cls,
        kind = kindName,
        ftype = frameType,
        tmpl = template,
        host = hostFrame,
        gen = 1,
        idle = false,
        isFrame = true,
    }
end

local function RegisterFrame(object, record)
    FrameRecs[object] = record
    -- a button's pushed text offset as new, read from the button itself as it is
    -- made (a new button's offset is not one fixed value): its resets put it back
    local meta = getmetatable(object).__index
    if meta.GetPushedTextOffset then
        record.pushX, record.pushY = object:GetPushedTextOffset()
    end
    Install(object, FRAME_OVERRIDES)
    local eng = ENGINE_OVERRIDES[record.ftype]
    if eng then Install(object, eng) end
    if devOn and record.cls == "pooled" then rawset(object, "SetParent", O_DevSetParent) end
    return object
end

-------------------------------------------------------------------------------
--  Registries keyed by an object (forgotten at its reset, so a reused object
--  never answers for its previous dress)
-------------------------------------------------------------------------------
local function ForgetRegistries(object, isFrame)
    local acc = CUI._accentElements
    local position = acc and acc._idx
    local i = position and position[object]
    if i then acc[i] = INERT_ACCENT end
    if isFrame then
        local rc = CUI._rowCounters
        if rc then rc[object] = nil end
        local forget = CUI._ForgetEscapeClose
        local record = FrameRecs[object]
        if forget and not (record and record.exempt and (record.exempt.OnShow or record.exempt.OnHide)) then
            forget(object)
        end
    end
end

local function ForgetPixelSnap(object)
    local Pix = CUI.PP
    local f = Pix and Pix.ForgetPixelSnap
    if f then f(object) end
end

local function ResetScripts(object, record, m, base)
    local cfg = record.scripts
    if cfg and next(cfg) then
        local set = m.SetScript
        for slotIndex in pairs(cfg) do
            set(object, slotIndex, base and base[slotIndex] or nil)
            cfg[slotIndex] = nil
        end
    end
end

local function ResetAttrs(object, record, m)
    local a = record.attrs
    if a and next(a) then
        local set = m.SetAttribute
        for label in pairs(a) do
            set(object, label, nil)
            a[label] = nil
        end
    end
end

-- Every string key goes, except the keys a new object of the kind has (put
-- back to their values), keys naming a method of the object's type (instance
-- hooks: the pool's own overrides, TrackOverlay's) and its host attachment keys.
local function WipeKeys(object, record, m, base)
    local keep = record.attachKeys
    for keyName, val in pairs(object) do
        if type(keyName) == "string" and keyName:byte(1) ~= 0 then
            local bv = base and base[keyName]
            if bv ~= nil then
                if val ~= bv then rawset(object, keyName, bv) end
            elseif rawget(m, keyName) == nil and not (keep and keep[keyName]) then
                rawset(object, keyName, nil)
            end
        end
    end
    if base then
        for keyName, val in pairs(base) do
            if rawget(object, keyName) == nil then rawset(object, keyName, val) end
        end
    end
end

local function HasGlow(object)
    for i = 1, #GLOW_KEYS do
        if rawget(object, GLOW_KEYS[i]) ~= nil then return true end
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
    if m.GetPropagateKeyboardInput and object:GetPropagateKeyboardInput() then return true end
    if m.CanPropagateMouseClicks and object:CanPropagateMouseClicks() then return true end
    if m.CanPropagateMouseMotion and object:CanPropagateMouseMotion() then return true end
    local pass = m.ShouldButtonPassThrough
    if pass then
        for i = 1, #PASS_BUTTONS do
            if pass(object, PASS_BUTTONS[i]) then return true end
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
        for _, keyName in pairs(km) do
            local kr = FrameRecs[keyName]
            if kr then Visit(keyName, kr, false, true, depth) end
        end
    end
    local om = OWNED[o]
    if om then
        for _, slotIndex in pairs(om) do
            local entries = slotIndex.list
            for i = 1, #entries do
                local posX = entries[i]
                local xr = FrameRecs[posX]
                if xr then Visit(posX, xr, moved, true, depth) end
            end
        end
    end
    if not r.isFrame then return end
    local poolMap = r.pools
    if poolMap then
        for _, entries in pairs(poolMap) do
            for i = 1, #entries do
                local posX = entries[i]
                local xr = FrameRecs[posX]
                if xr and xr.isFrame then Visit(posX, xr, moved, false, depth) end
            end
        end
    end
    local att = r.attach
    if att then
        for i = 1, #att do
            local a = att[i]
            local ar = FrameRecs[a]
            if ar and ar.host == o then Visit(a, ar, moved, false, depth) end
        end
    end
end
Visit = function(o, r, moved, listed, depth)
    if r.fw == walkSerial or depth > 64 then return end
    r.fw = walkSerial
    if moved then r.fm = walkSerial end
    if listed and o:IsShown() then
        frzN = frzN + 1
        frzList[frzN] = o
    end
    Parts(o, r, moved, depth + 1)
end

-- Whether walk `serial` found rel moved (a region moves with its frame).
local function MovedBy(rel, serial)
    local rr = FrameRecs[rel]
    if not rr then return false end
    if rr.fm == serial then return true end
    local hr = rr.region and rr.host and FrameRecs[rr.host]
    return hr ~= nil and hr.fm == serial
end

-- Whether something walk `serial` found moved places f, through its anchors
-- and theirs (at most depBudget anchors read; running out counts as placed).
-- An anchoring code may not read (restricted, or answered with a secret) is
-- not followed: every value is cleared by issecretvalue before any test.
local depBudget = 0
local function PlacedByMoved(frame, serial)
    local isv = _G.issecretvalue
    local restricted = frame.IsAnchoringRestricted and frame:IsAnchoringRestricted()
    if isv and isv(restricted) then return false end
    if restricted then return false end
    local last
    for i = 1, frame:GetNumPoints() do
        local _, relTo = frame:GetPoint(i)
        if isv and isv(relTo) then return false end
        if relTo ~= nil and relTo ~= last then
            last = relTo
            if MovedBy(relTo, serial) then return true end
            depBudget = depBudget - 1
            if depBudget <= 0 or PlacedByMoved(relTo, serial) then return true end
        end
    end
    return false
end

-- What a host is placed by: its first anchor's frame (the screen: UIParent).
local function PlacedBy(height)
    local isv = _G.issecretvalue
    for i = 1, height:GetNumPoints() do
        local _, relTo = height:GetPoint(i)
        if isv and isv(relTo) then break end
        if relTo ~= nil then return relTo end
    end
    return _G.UIParent
end

-- f pinned where it is now: to ref's top left corner, or to the screen
-- (UIParent's bottom left, as a dropped build's orphaned anchor kept it) when
-- ref is UIParent or has no place itself.
local function FreezeTo(frame, ref)
    local isv = _G.issecretvalue
    local l, b, wid, height = frame:GetRect()
    if isv and (isv(l) or isv(b) or isv(wid) or isv(height)) then return end
    if not (l and b and wid and height) then return end
    local UIParent = _G.UIParent
    if ref ~= UIParent and ref ~= frame then
        local rl, rebuild, rw, rh = ref:GetRect()
        if not (isv and (isv(rl) or isv(rebuild) or isv(rw) or isv(rh))) and rl and rebuild and rw and rh then
            -- ref's corner in f's own units (each scales its own offsets)
            local scale = ref:GetEffectiveScale() / frame:GetEffectiveScale()
            frame:ClearAllPoints()
            if
                pcall(
                    frame.SetPoint,
                    frame,
                    "TOPLEFT",
                    ref,
                    "TOPLEFT",
                    l - rl * scale,
                    b + height - (rebuild + rh) * scale
                )
            then
                frame:SetSize(wid, height)
                return
            end
        end
    end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    frame:SetSize(wid, height)
end

local function FreezeWalk(hostFrame, hostRec, hostMoved)
    walkSerial = walkSerial + 1
    local serial = walkSerial
    frzN = 0
    hostRec.fw = serial
    if hostMoved then hostRec.fm = serial end
    -- the host's own parts are dressed again by its pass, whether or not the
    -- host itself is
    Parts(hostFrame, hostRec, true, 1)
    if frzN == 0 then return end
    local ref = hostMoved and PlacedBy(hostFrame) or hostFrame
    for i = 1, frzN do
        local frame = frzList[i]
        depBudget = 64
        if frame ~= ref and frame:IsShown() and PlacedByMoved(frame, serial) then FreezeTo(frame, ref) end
    end
end

-- Called once per pass, before its host's parts move (ResetContents). A pass
-- that starts while one pins (a script a pin fires) leaves it to that one.
local function FreezeUnder(hostFrame, hostRec, hostMoved)
    if walking then return end
    walking = true
    local success, err = pcall(FreezeWalk, hostFrame, hostRec, hostMoved)
    walking = false
    for i = 1, frzN do
        frzList[i] = nil
    end
    frzN = 0
    if not success then _G.geterrorhandler()(err) end
end

-------------------------------------------------------------------------------
--  A host's contents at its reset (or Pool.Begin)
-------------------------------------------------------------------------------
local function ParkList(entries)
    for i = 1, #entries do
        local o = entries[i]
        local r = FrameRecs[o]
        if r and not r.idle then
            if r.isAG then
                o:Stop()
            elseif o:IsShown() then
                if not replayArmed and o:IsVisible() then ArmReplay() end
                o:Hide()
            end
            r.idle = true
        end
    end
end

-- pass: PASS_RESET (a kept host's reset) or PASS_BEGIN (Pool.Begin) starts a
-- pass on obj; nil for an object handed out again within one (already walked).
local function ResetContents(object, record, details, pass)
    -- pooled objects of this host, wherever they are now: hidden, idle
    local poolMap = record.pools
    if poolMap then
        for _, entries in pairs(poolMap) do
            ParkList(entries)
        end
        local current = record.cur
        for keyName in pairs(current) do
            current[keyName] = 0
        end
    end
    -- owned objects: hidden, cursors back to the start
    local om = OWNED[object]
    if om then
        for _, slotIndex in pairs(om) do
            ParkList(slotIndex.list)
            slotIndex.cur = 0
        end
    end
    -- attachments: hidden, their onReset runs. Pool.Begin does not reset the
    -- host, so the host's own decorations (Pool.Attach: a border, a mark, a
    -- glow) stay as they are; what module state keeps (Pool.Keep) is parked
    -- as the rest of what the host handed out is
    local att = record.attach
    if att then
        for i = 1, #att do
            local a = att[i]
            local ar = FrameRecs[a]
            if ar and ar.host == object and (pass ~= PASS_BEGIN or ar.cls == "keep") then
                if a:IsShown() then a:Hide() end
                if ar.onReset then pcall(ar.onReset, a) end
            end
        end
    end
    -- the start of a pass, after what the parts' hiding closes and before any
    -- part moves: what shows over the host and hangs on its parts stays put
    if pass then FreezeUnder(object, record, pass == PASS_RESET) end
    if not record.isFrame then return end
    -- children and regions the pool does not manage
    local buried = 0
    local skip = details and details.nChildren or 0
    local t, num = Pack(object:GetChildren())
    for i = 1, num do
        local c = t[i]
        if FrameRecs[c] == nil then
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
    local roleMap = ENGINE_ROLES[record.ftype]
    if roleMap then
        local meta = getmetatable(object).__index
        for i = 1, #roleMap do
            local get = meta[roleMap[i].get]
            local registry = get and get(object)
            if registry and FrameRecs[registry] == nil then
                if not named then
                    named = record.engRegs
                    if not named then
                        named = {}
                        record.engRegs = named
                    end
                end
                named[registry] = i
            end
        end
    end
    skip = details and details.nRegions or 0
    t, num = Pack(object:GetRegions())
    for i = 1, num do
        local registry = t[i]
        if FrameRecs[registry] == nil and not (named and named[registry]) then
            if skip > 0 then
                skip = skip - 1
            elseif ENGINE_UNSURE[record.ftype] then
                -- maybe the engine's, unnamed: left in place, the frame is retired
                if registry:IsShown() then registry:Hide() end
                record.engine = true
            else
                Bury(registry)
                buried = buried + 1
            end
        end
    end
    Release()
    -- animation groups the pool does not manage cannot move: stopped
    t, num = Pack(object:GetAnimationGroups())
    for i = 1, num do
        local animGroup = t[i]
        if FrameRecs[animGroup] == nil then animGroup:Stop() end
    end
    Release()
    if buried > 0 and devOn then
        DevWarn(
            "foreign:" .. tostring(record.key or record.kind),
            buried
                .. " foreign object(s) under "
                .. tostring(record.key or record.kind)
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
local function Fixed(record, what)
    if devOn and not verified[record.kind .. what] then
        verified[record.kind .. what] = true
        DevWarn("fix:" .. record.kind .. what, "SetToDefaults left " .. what .. " on a " .. record.kind)
    end
end

-- A scroll frame's hidden stand-in scroll child (made once per scroll frame).
local function PlaceholderFor(scrollFrame, srec)
    local ph = srec and srec.placeholder
    if not ph then
        ph = _G.CreateFrame("Frame", nil, scrollFrame)
        ph:Hide()
        FrameRecs[ph] = { cls = "placeholder", idle = true }
        if srec then srec.placeholder = ph end
    end
    return ph
end

-- A frame that is still a pool scroll frame's scroll child leaves it before
-- its next dress: that scroll frame, idle or not, would keep positioning it.
local function ReleaseScrollChild(object, record)
    local scrollFrame = record.scrollOwner
    record.scrollOwner = nil
    if not scrollFrame or scrollFrame:GetScrollChild() ~= object then return end
    getmetatable(scrollFrame).__index.SetScrollChild(
        scrollFrame,
        PlaceholderFor(scrollFrame, FrameRecs[scrollFrame])
    )
end

-- A region placed as the same region of a new object is (c, from the probe).
local function PlaceAsNew(object, registry, cfg)
    registry:SetDrawLayer(cfg.layer, cfg.sub)
    registry:ClearAllPoints()
    local pts = cfg.points
    for jdx = 1, #pts do
        local p = pts[jdx]
        local rel = p[2]
        if rel == true then rel = object end
        registry:SetPoint(p[1], rel, p[3], p[4], p[5])
    end
end

-- An engine-made region of a known role, reset where it is: the look the same
-- region of a new object has (c, from the probe), no image or text, hidden
-- until a setter of its role dresses it again (which gives back a new
-- region's shown state). A live role (the engine shows and writes it itself)
-- takes a new region's look and shown state. A button's text takes no look of
-- its own: back at the engine's defaults, it gets the font object the next
-- dress gives the button, as a new button's text does.
local function ResetEngineRegion(object, registry, cfg, roleName)
    local isText = registry.GetFont ~= nil
    if isText and not roleName.live then
        if registry.SetToDefaults then registry:SetToDefaults() end
        if cfg then PlaceAsNew(object, registry, cfg) end
        if registry:GetFont() then registry:SetText("") end
        if registry:IsShown() then registry:Hide() end
        if cfg then
            engHidden[registry] = cfg.shown
        else
            engHidden[registry] = true
        end
        return
    end
    if cfg ~= nil and (cfg.font ~= nil or not isText) then
        if registry.SetToDefaults then registry:SetToDefaults() end
        if registry.GetNumMaskTextures then
            for jdx = registry:GetNumMaskTextures(), 1, -1 do
                local mask = registry:GetMaskTexture(jdx)
                if mask then registry:RemoveMaskTexture(mask) end
            end
        end
        ForgetPixelSnap(registry)
        PlaceAsNew(object, registry, cfg)
        if cfg.blend then registry:SetBlendMode(cfg.blend) end
        if cfg.font then
            if cfg.fontObject then registry:SetFontObject(cfg.fontObject) end
            registry:SetFont(cfg.font[1], cfg.font[2], cfg.font[3])
            local col = cfg.color
            registry:SetTextColor(col[1], col[2], col[3], col[4])
            col = cfg.shadow
            registry:SetShadowColor(col[1], col[2], col[3], col[4])
            registry:SetShadowOffset(cfg.shadowOff[1], cfg.shadowOff[2])
            registry:SetJustifyH(cfg.jh)
            registry:SetJustifyV(cfg.jv)
        end
    end
    if roleName.live then
        if cfg and (registry:IsShown() and true or false) ~= cfg.shown then registry:SetShown(cfg.shown) end
        return
    end
    if registry.SetTexture then registry:SetTexture(nil) end
    if registry:IsShown() then registry:Hide() end
    if cfg then
        engHidden[registry] = cfg.shown
    else
        engHidden[registry] = true
    end
end

local function ResetEngineRegions(object, record, details, named)
    local roleMap = ENGINE_ROLES[record.ftype]
    local eng = details.eng
    local m = devOn and getmetatable(object).__index
    for registry, i in pairs(named) do
        named[registry] = nil
        ResetEngineRegion(object, registry, eng and eng[i], roleMap[i])
        if m then
            local get = m[roleMap[i].get]
            if get and get(object) ~= registry then
                Fixed(record, " no " .. roleMap[i].get:sub(4) .. " (its frame's reset dropped it)")
            end
        end
    end
end

-- Returns false when the object cannot be reset now (a propagation,
-- pass-through or keyboard flag in combat: only an out-of-combat reset may
-- clear it). pass: see ResetContents. hidden: left hidden at the end (shown
-- by the code that dresses it), so no OnShow runs at the reset.
local function ResetFrame(object, record, hostFrame, pass, hidden)
    local meta = getmetatable(object).__index
    local details = KindInfo(record)
    if _G.InCombatLockdown() and (HasPropagate(object, meta) or KeyboardChanged(object, meta, details)) then
        record.dirty = true
        return false
    end
    record.dirty = nil
    record.engine = nil
    local hook = rawget(object, "_cuiOnRecycle")
    if hook then pcall(hook, object) end
    if HasGlow(object) then
        local G = CUI.Glows
        if G and G.StopAllGlows then pcall(G.StopAllGlows, object) end
    end
    -- visible descendants get OnHide with their old scripts, as when a page was dropped
    if object:IsShown() then
        if not replayArmed and object:IsVisible() then ArmReplay() end
        object:Hide()
    end
    if record.ftype == "EditBox" and object:HasFocus() then object:ClearFocus() end
    if record.scrollOwner then ReleaseScrollChild(object, record) end
    ResetContents(object, record, details, pass)
    ResetScripts(object, record, meta, details.scripts)
    object:UnregisterAllEvents()
    ResetAttrs(object, record, meta)
    ForgetRegistries(object, true)
    WipeKeys(object, record, meta, details.keys)
    if record.ftype == "Cooldown" then object:Clear() end
    -- Click and drag registration: no getter reads either back, so the
    -- in-game reset check cannot tell whether SetToDefaults clears them.
    -- A new object's are put back first (a button answers the left
    -- button's release, nothing is registered for drag), so a reused
    -- button never answers the clicks, or starts the drags, of an earlier dress.
    if meta.RegisterForClicks then object:RegisterForClicks("LeftButtonUp") end
    if meta.RegisterForDrag then object:RegisterForDrag() end
    if object.SetToDefaults then
        object:SetToDefaults()
    else
        object:ClearAllPoints()
        object:SetAlpha(1)
        object:SetScale(1)
    end
    if record.ftype == "PlayerModel" and meta.ClearModel then object:ClearModel() end
    ForgetPixelSnap(object)
    -- what SetToDefaults is documented to cover, checked where it is cheap
    if object:GetAlpha() ~= 1 then
        object:SetAlpha(1)
        Fixed(record, "alpha")
    end
    if (object:IsMouseEnabled() and true or false) ~= details.mouse then
        object:EnableMouse(details.mouse)
        Fixed(record, "mouse")
    end
    if meta.IsMouseWheelEnabled and (object:IsMouseWheelEnabled() and true or false) ~= details.wheel then
        object:EnableMouseWheel(details.wheel)
        Fixed(record, "wheel")
    end
    if meta.DoesClipChildren and (object:DoesClipChildren() and true or false) ~= details.clips then
        object:SetClipsChildren(details.clips)
        Fixed(record, "clips")
    end
    -- what SetToDefaults keeps: the keyboard flag (left as it is only in combat,
    -- where it already matches), the pushed text offset, the kind's own settings
    -- and an edit box's history
    if KeyboardChanged(object, meta, details) and not _G.InCombatLockdown() then
        object:EnableKeyboard(details.keyboard)
    end
    if record.pushX then
        local posX, cursorY = object:GetPushedTextOffset()
        if posX ~= record.pushX or cursorY ~= record.pushY then
            object:SetPushedTextOffset(record.pushX, record.pushY)
        end
    end
    -- a setting the engine will not put back retires the frame, as a region the
    -- pool cannot name does: it is never handed out again
    if details.kept and not RestoreKept(object, details.kept) then record.engine = true end
    if meta.ClearHistory then object:ClearHistory() end
    -- No API clears a scroll frame's scroll child (SetScrollChild takes no nil):
    -- a child of an earlier dress gives way to the frame's hidden placeholder,
    -- which positions nothing and gives the frame no scroll range.
    if record.ftype == "ScrollFrame" then
        local childFrame = object:GetScrollChild()
        if childFrame and childFrame ~= record.placeholder then
            meta.SetScrollChild(object, PlaceholderFor(object, record))
        end
    end
    -- placement: the parent, its strata and the level a new child gets
    if object:GetParent() ~= hostFrame then meta.SetParent(object, hostFrame) end
    local strata = hostFrame and hostFrame:GetFrameStrata() or "MEDIUM"
    if object:GetFrameStrata() ~= strata then object:SetFrameStrata(strata) end
    object:SetFrameLevel(hostFrame and (hostFrame:GetFrameLevel() + 1) or 0)
    -- the engine's regions of known roles (named by ResetContents)
    local named = record.engRegs
    if named and next(named) then ResetEngineRegions(object, record, details, named) end
    if record.tmpl == "CooldownFrameTemplate" then
        ApplyCooldownTemplate(object)
        if object:IsShown() then object:Hide() end
    elseif record.ftype == "EditBox" then
        -- a shown auto-focus edit box takes the keyboard: show it without, then
        -- put the new object's default back (one kept hidden is shown by its
        -- dress, which turns auto-focus off first: see Pool.Kept)
        object:SetAutoFocus(false)
        if not hidden then meta.Show(object) end
        object:SetAutoFocus(details.autoFocus)
    elseif not hidden then
        -- shown as a new frame is: through the type's method, so an instance Show
        -- hook (CludesUI.TrackOverlay) never sees the reset (the Hide above it does)
        meta.Show(object)
    end
    record.gen = record.gen + 1
    record.idle = false
    return true
end

-- Returns false when a value of its own stays different (its group is retired).
local function ResetAnim(a, r)
    local meta = getmetatable(a).__index
    if a.IsPlaying and a:IsPlaying() and a.Stop then a:Stop() end
    ResetScripts(a, r, meta, nil)
    WipeKeys(a, r, meta, nil)
    if a.SetToDefaults then a:SetToDefaults() end
    -- the target a new animation has: its group's parent
    if a.SetTargetParent then a:SetTargetParent() end
    -- what SetToDefaults keeps: its timing and its type's own values
    local kept = AnimKept(r.kind)
    local fit = not kept or RestoreKept(a, kept)
    r.inert = nil
    r.gen = r.gen + 1
    return fit
end

local function ResetAG(animGroup, record)
    local meta = getmetatable(animGroup).__index
    animGroup:Stop()
    ResetScripts(animGroup, record, meta, nil)
    WipeKeys(animGroup, record, meta, nil)
    if animGroup.SetToDefaults then animGroup:SetToDefaults() end
    -- what SetToDefaults keeps: the looping, final alpha and speed
    local kept = AGKept()
    local fit = not kept or RestoreKept(animGroup, kept)
    -- its animations are reset where they are (a group cannot drop one) and
    -- handed back in order by CreateAnimation; the ones the next dress does
    -- not take are quieted before the group plays (QuietLeftovers)
    local poolMap = record.pools
    if poolMap then
        for _, entries in pairs(poolMap) do
            for i = 1, #entries do
                local a = entries[i]
                local ar = FrameRecs[a]
                if not ResetAnim(a, ar) then fit = false end
                ar.idle = true
                ar.fresh = true
            end
        end
        local current = record.cur
        for keyName in pairs(current) do
            current[keyName] = 0
        end
    end
    -- a value the engine will not put back (an animation's smoothing): the group
    -- is retired by AcquireAG, never handed out again
    record.unfit = not fit or nil
    record.gen = record.gen + 1
    record.idle = false
end

-- A group the pool will not hand out again: stopped where it is (a group cannot
-- move), a plain group again (no pool overrides), out of the pool.
local function RetireAG(animGroup)
    local record = FrameRecs[animGroup]
    FrameRecs[animGroup] = nil
    animGroup:Stop()
    for label, func in pairs(AG_OVERRIDES) do
        if rawget(animGroup, label) == func then rawset(animGroup, label, nil) end
    end
    local poolMap = record and record.pools
    if poolMap then
        for _, entries in pairs(poolMap) do
            for i = 1, #entries do
                local a = entries[i]
                FrameRecs[a] = nil
                for label, func in pairs(ANIM_OVERRIDES) do
                    if rawget(a, label) == func then rawset(a, label, nil) end
                end
            end
        end
    end
end

local function ResetRegion(object, record, hostFrame, layer, subMenu)
    local meta = getmetatable(object).__index
    if object:IsShown() then object:Hide() end
    ResetScripts(object, record, meta, nil)
    ForgetRegistries(object, false)
    WipeKeys(object, record, meta, nil)
    -- its own animation groups: stopped, handed back in order
    local poolMap = record.pools
    if poolMap then
        for _, entries in pairs(poolMap) do
            ParkList(entries)
        end
        local current = record.cur
        for keyName in pairs(current) do
            current[keyName] = 0
        end
    end
    if object.SetToDefaults then
        object:SetToDefaults()
    else
        object:ClearAllPoints()
        object:SetAlpha(1)
    end
    -- a line's thickness and a rotated texture's rotation point as new (SetToDefaults keeps both)
    if record.thick and object:GetThickness() ~= record.thick then object:SetThickness(record.thick) end
    if record.rotated then
        record.rotated = nil
        local r0, p0 = TexRotation()
        if p0 then meta.SetRotation(object, r0, p0) end
    end
    if meta.GetNumMaskTextures then
        for i = object:GetNumMaskTextures(), 1, -1 do
            local mask = object:GetMaskTexture(i)
            if mask then object:RemoveMaskTexture(mask) end
        end
    end
    ForgetPixelSnap(object)
    object:SetDrawLayer(layer, subMenu)
    if object:GetParent() ~= hostFrame then meta.SetParent(object, hostFrame) end
    object:Show()
    record.layer, record.sub = layer, subMenu
    record.gen = record.gen + 1
    record.idle = false
end

-------------------------------------------------------------------------------
--  Acquire
-------------------------------------------------------------------------------
-- An object the pool will not hand out again: out of its list, a plain frame
-- again (no pool overrides), buried.
local function Retire(object)
    local record = FrameRecs[object]
    FrameRecs[object] = nil
    if record then StripOverrides(object, record.ftype) end
    if object:IsShown() then object:Hide() end
    Bury(object)
    if record and devOn then
        DevWarn(
            "retire:" .. tostring(record.kind),
            "a " .. tostring(record.kind) .. " with a region the pool cannot name is not reused"
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
            local r = FrameRecs[entries[jdx]]
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
        local record = FrameRecs[object]
        if ResetFrame(object, record, hostFrame) then
            if not record.engine then return object end
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

local function AcquireFrame(hostFrame, hostRec, frameType, template)
    local kindName = template and (frameType .. "|" .. template) or frameType
    local poolMap = hostRec.pools
    if not poolMap then
        poolMap = {}
        hostRec.pools = poolMap
        hostRec.cur = {}
    end
    local entries = poolMap[kindName]
    if not entries then
        entries = {}
        poolMap[kindName] = entries
    end
    local i = (hostRec.cur[kindName] or 0) + 1
    local object = TakeFrame(entries, i, hostFrame)
    if not object then
        object = _G.CreateFrame(frameType, nil, hostFrame, template)
        RegisterFrame(object, NewFrameRec("pooled", kindName, frameType, template, hostFrame))
        tinsert(entries, i, object)
    end
    hostRec.cur[kindName] = i
    return object
end

AcquireRegion = function(hostFrame, kindName, method, layer, subMenu)
    local hostRec = FrameRecs[hostFrame]
    local poolMap = hostRec.pools
    if not poolMap then
        poolMap = {}
        hostRec.pools = poolMap
        hostRec.cur = {}
    end
    local entries = poolMap[kindName]
    if not entries then
        entries = {}
        poolMap[kindName] = entries
    end
    local i = (hostRec.cur[kindName] or 0) + 1
    -- the draw layer a new region of this call gets (the engine default when unset)
    local nLayer = layer or "ARTWORK"
    local nSub = (kindName ~= "FontString" and tonumber(subMenu)) or 0
    local object = entries[i]
    if object then
        ResetRegion(object, FrameRecs[object], hostFrame, nLayer, nSub)
    else
        if kindName == "FontString" then
            object = getmetatable(hostFrame).__index.CreateFontString(hostFrame, nil, layer)
        else
            object = getmetatable(hostFrame).__index[method](hostFrame, nil, layer, nil, subMenu)
        end
        FrameRecs[object] = {
            cls = "pooled",
            kind = kindName,
            host = hostFrame,
            gen = 1,
            idle = false,
            region = true,
            layer = nLayer,
            sub = nSub,
            thick = kindName == "Line" and object.GetThickness and object:GetThickness() or nil,
        }
        Install(object, REGION_OVERRIDES)
        if kindName == "Texture" then Install(object, TEX_OVERRIDES) end
        entries[i] = object
    end
    hostRec.cur[kindName] = i
    return object
end

AcquireAG = function(hostFrame)
    local hostRec = FrameRecs[hostFrame]
    local poolMap = hostRec.pools
    if not poolMap then
        poolMap = {}
        hostRec.pools = poolMap
        hostRec.cur = {}
    end
    local entries = poolMap.AnimationGroup
    if not entries then
        entries = {}
        poolMap.AnimationGroup = entries
    end
    local i = (hostRec.cur.AnimationGroup or 0) + 1
    local animGroup = entries[i]
    if animGroup then
        ResetAG(animGroup, FrameRecs[animGroup])
        if FrameRecs[animGroup].unfit then
            RetireAG(animGroup)
            animGroup = nil
        end
    end
    if not animGroup then
        animGroup = getmetatable(hostFrame).__index.CreateAnimationGroup(hostFrame)
        FrameRecs[animGroup] =
            { cls = "pooled", kind = "AnimationGroup", host = hostFrame, gen = 1, idle = false, isAG = true }
        Install(animGroup, AG_OVERRIDES)
        entries[i] = animGroup
    end
    hostRec.cur.AnimationGroup = i
    return animGroup
end

AcquireAnim = function(animGroup, atype)
    local grec = FrameRecs[animGroup]
    local poolMap = grec.pools
    if not poolMap then
        poolMap = {}
        grec.pools = poolMap
        grec.cur = {}
    end
    local kindName = atype or "Animation"
    local entries = poolMap[kindName]
    if not entries then
        entries = {}
        poolMap[kindName] = entries
    end
    local i = (grec.cur[kindName] or 0) + 1
    local a = entries[i]
    if a then
        local ar = FrameRecs[a]
        -- reset with its group, unless a play quieted it since
        if ar.fresh and not ar.inert then
            ar.fresh = nil
        else
            ResetAnim(a, ar)
            ar.fresh = nil
        end
        ar.idle = false
    else
        a = getmetatable(animGroup).__index.CreateAnimation(animGroup, atype)
        FrameRecs[a] =
            { cls = "pooled", kind = kindName, host = animGroup, gen = 1, idle = false, isAnim = true }
        Install(a, ANIM_OVERRIDES)
        entries[i] = a
    end
    grec.cur[kindName] = i
    return a
end

-------------------------------------------------------------------------------
--  Public API
-------------------------------------------------------------------------------
local function CanonicalType(frameType)
    if type(frameType) ~= "string" then return nil end
    return FRAME_TYPES[frameType] or FRAME_TYPES[frameType:lower()]
end

function Pool.CreateFrame(frameType, label, hostFrame, template, ident)
    if label == nil and ident == nil and hostFrame ~= nil and not CUI._prebuilding then
        local prec = FrameRecs[hostFrame]
        if prec and prec.isFrame and (template == nil or TEMPLATES[template]) then
            local ft = CanonicalType(frameType)
            if ft then return AcquireFrame(hostFrame, prec, ft, template) end
        end
    end
    return _G.CreateFrame(frameType, label, hostFrame, template, ident)
end

-- A new frame for Pool.Kept, hidden when asked (it has no OnShow script yet,
-- so nothing runs).
local function NewKept(object, hidden)
    if hidden and object:IsShown() then object:Hide() end
    return object, true
end

-- Every reset of a kept frame starts a pass on it (ResetContents).
function Pool.Kept(ownerFrame, key, frameType, hostFrame, template, label, hidden)
    if CUI._prebuilding or ownerFrame == nil or key == nil then
        return NewKept(_G.CreateFrame(frameType, label, hostFrame, template), hidden)
    end
    local ft = CanonicalType(frameType)
    if not ft or (template ~= nil and not TEMPLATES[template]) then
        return NewKept(_G.CreateFrame(frameType, label, hostFrame, template), hidden)
    end
    RefreshDev()
    local map = KEPT[ownerFrame]
    if not map then
        map = {}
        KEPT[ownerFrame] = map
    end
    local object = map[key]
    if object then
        local record = FrameRecs[object]
        if record and ResetFrame(object, record, hostFrame, PASS_RESET, hidden) and not record.engine then
            record.host = hostFrame
            return object, false
        end
        map[key] = nil
        Retire(object)
    end
    object = _G.CreateFrame(ft, label, hostFrame, template)
    local record = NewFrameRec("kept", template and (ft .. "|" .. template) or ft, ft, template, hostFrame)
    record.key = key
    RegisterFrame(object, record)
    map[key] = object
    return NewKept(object, hidden)
end

function Pool.Owned(ownerFrame, labelText, frameType, hostFrame, template)
    local ft = CanonicalType(frameType)
    if CUI._prebuilding or ownerFrame == nil or not ft or (template ~= nil and not TEMPLATES[template]) then
        return _G.CreateFrame(frameType, nil, hostFrame, template)
    end
    local om = OWNED[ownerFrame]
    if not om then
        om = {}
        OWNED[ownerFrame] = om
    end
    local skey = tostring(labelText) .. "|" .. ft .. "|" .. (template or "")
    local slotIndex = om[skey]
    if not slotIndex then
        slotIndex = { list = {}, cur = 0 }
        om[skey] = slotIndex
    end
    local i = slotIndex.cur + 1
    local object = TakeFrame(slotIndex.list, i, hostFrame)
    if not object then
        object = _G.CreateFrame(ft, nil, hostFrame, template)
        local record =
            NewFrameRec("owned", template and (ft .. "|" .. template) or ft, ft, template, hostFrame)
        RegisterFrame(object, record)
        tinsert(slotIndex.list, i, object)
    end
    local orec = FrameRecs[object]
    orec.host = hostFrame
    slotIndex.cur = i
    return object
end

function Pool.Begin(hostFrame)
    if CUI._prebuilding then return end
    local record = FrameRecs[hostFrame]
    if not (record and record.isFrame) then return end
    RefreshDev()
    ResetContents(hostFrame, record, KindInfo(record), PASS_BEGIN)
    -- the host itself is not reset: its own engine regions stay as they are
    local named = record.engRegs
    if named then
        for keyName in pairs(named) do
            named[keyName] = nil
        end
    end
end

-- What shows over a kept host and is placed by its parts is pinned as the
-- start of its next pass would pin it, with nothing reset: for code that moves
-- what the host is placed by before that pass starts (the panel collapses the
-- content header before its header root is dressed again). The pass then
-- finds those objects placed by what the host is placed by and leaves them.
function Pool.Pin(hostFrame)
    if CUI._prebuilding then return end
    local record = FrameRecs[hostFrame]
    if record and record.isFrame then FreezeUnder(hostFrame, record, true) end
end

-- Records whenever obj is a pooled object, also during the global search's
-- prebuild (a live pooled object a prebuild builder touches stays managed).
function Pool.Keep(object)
    local record = FrameRecs[object]
    if not record or record.cls ~= "pooled" then return object end
    local hostRec = FrameRecs[record.host]
    local entries = hostRec and hostRec.pools and hostRec.pools[record.kind]
    if entries then
        for i = 1, #entries do
            if entries[i] == object then
                tremove(entries, i)
                local c = hostRec.cur[record.kind] or 0
                if i <= c then hostRec.cur[record.kind] = c - 1 end
                break
            end
        end
    end
    record.cls = "keep"
    if hostRec then
        local att = hostRec.attach
        if not att then
            att = {}
            hostRec.attach = att
        end
        att[#att + 1] = object
    end
    return object
end

-- Records whenever host is a pooled object, also during the global search's
-- prebuild (a border made then on a live pooled frame must stay on it).
function Pool.Attach(hostFrame, object, key, onReset)
    if object == nil then return false end
    local hostRec = FrameRecs[hostFrame]
    if not hostRec then return false end
    local orec = FrameRecs[object]
    if orec and orec.cls ~= "attach" then return false end
    if not orec then
        orec = { cls = "attach" }
        FrameRecs[object] = orec
    end
    if orec.host ~= hostFrame then
        orec.host = hostFrame
        local att = hostRec.attach
        if not att then
            att = {}
            hostRec.attach = att
        end
        -- listed once per host, however often it moves between hosts
        local listed = false
        for i = 1, #att do
            if att[i] == object then
                listed = true
                break
            end
        end
        if not listed then att[#att + 1] = object end
    end
    orec.onReset = onReset
    if key ~= nil then
        local ks = hostRec.attachKeys
        if not ks then
            ks = {}
            hostRec.attachKeys = ks
        end
        ks[key] = true
    end
    return true
end

function Pool.Gen(object)
    local r = object and FrameRecs[object]
    return r and r.gen
end

function Pool.IsIdle(object)
    local r = object and FrameRecs[object]
    return (r and r.idle) and true or false
end

-- True for every object the pool manages (pooled, kept, owned, kept by module
-- state, attached); false for objects made without it.
function Pool.Managed(object) return object ~= nil and FrameRecs[object] ~= nil end

-- The slots survive every later reset; a later dress that sets or hooks one
-- again is reported in dev mode (ExemptSlot).
function Pool.ExemptScripts(object, ...)
    local record = object and FrameRecs[object]
    if not record then return end
    local ex = record.exempt
    if not ex then
        ex = {}
        record.exempt = ex
    end
    if record.exemptGen == nil then record.exemptGen = record.gen end -- the dress that first exempted
    for i = 1, select("#", ...) do
        local slotIndex = select(i, ...)
        ex[slotIndex] = true
        if record.scripts then record.scripts[slotIndex] = nil end
    end
end

-- Dev mode: pooled objects anywhere under a host (its pools, and the pools of
-- every object it handed out) that are idle yet shown were shown by code
-- outside the pool (an object kept by module state).
local function DevIdleShown(record, labelText, level)
    local poolMap = record.pools
    if not poolMap or level > 16 then return end
    for kindName, entries in pairs(poolMap) do
        for i = 1, #entries do
            local o = entries[i]
            local r = FrameRecs[o]
            if r and not r.isAG then
                if r.idle then
                    if o:IsShown() then
                        DevWarn(
                            "idleshown:" .. tostring(labelText) .. kindName,
                            "an idle "
                                .. kindName
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
function Pool._DevEndPass(hostFrame, labelText)
    if not devOn or hostFrame == nil then return end
    local record = FrameRecs[hostFrame]
    if record then DevIdleShown(record, labelText, 0) end
    -- kept frames another owner placed on this host (a section a module keeps
    -- on a page wrapper) hold pools of their own: walked too
    for _, map in pairs(KEPT) do
        for _, keyName in pairs(map) do
            local kr = FrameRecs[keyName]
            if kr and kr.host == hostFrame then
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
    for _, r in pairs(FrameRecs) do
        local cls = r.cls
        c[cls] = (c[cls] or 0) + 1
        if r.idle then c.idle = c.idle + 1 end
    end
    if graveyard then
        c.graveyard = select("#", graveyard:GetChildren()) + select("#", graveyard:GetRegions())
    end
    return c
end

-- Harness / debugging accessor: obj is a scroll frame's hidden placeholder child
-- (ResetFrame, ReleaseScrollChild), which stands for "no scroll child".
function Pool._IsPlaceholder(object)
    local r = object and FrameRecs[object]
    return (r and r.cls == "placeholder") and true or false
end

-- Harness hook (pagereuse harness reset-fuzz): resets obj exactly as the pool
-- does before handing it out again on the same host.
function Pool._ResetForTest(object)
    local record = object and FrameRecs[object]
    if not record then return false end
    if record.region then
        ResetRegion(object, record, record.host, record.layer, record.sub)
        return true
    elseif record.isAG then
        ResetAG(object, record)
        return true
    elseif record.isAnim then
        ResetAnim(object, record)
        return true
    end
    return ResetFrame(object, record, record.host)
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
        CUI.PrintError("pool check: out of combat only")
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
    local hostFrame = Pool.Kept(verifyOwner, "host", "Frame", _G.UIParent)
    hostFrame:Hide()
    hostFrame:SetSize(200, 200)
    hostFrame:SetPoint("CENTER")

    -- a vector (a texture's rotation point) prints its values
    local function Fmt(val)
        if type(val) == "table" and type(val.GetXY) == "function" then
            local posX, cursorY = val:GetXY()
            if type(posX) == "number" and type(cursorY) == "number" then
                return string.format("(%.3f, %.3f)", posX, cursorY)
            end
        end
        return tostring(val)
    end
    local function Say(kindName, what, va, vb)
        result[#result + 1] = kindName .. " " .. what .. ": new=" .. Fmt(va) .. " reset=" .. Fmt(vb)
    end
    local function Packed(...) return { n = select("#", ...), ... } end
    -- a getter's results on both objects; ownA / ownB stand for each other
    local function Compare(kindName, labelText, a, b, get, ga, ownA, ownB)
        local fa, fb = a[get], b[get]
        if type(fa) ~= "function" or type(fb) ~= "function" then return end
        local ra = Packed(pcall(fa, a, unpack(ga or EMPTY)))
        local rebuild = Packed(pcall(fb, b, unpack(ga or EMPTY)))
        if not ra[1] and not rebuild[1] then return end
        if ra[1] ~= rebuild[1] then
            Say(kindName, labelText or get, ra[1] and "ok" or "error", rebuild[1] and "ok" or "error")
            return
        end
        for i = 2, max(ra.n, rebuild.n) do
            local posX, cursorY = ra[i], rebuild[i]
            local same
            if type(posX) == "number" and type(cursorY) == "number" then
                same = abs(posX - cursorY) < 0.001
            else
                same = SameVal(posX, cursorY) or (ownA ~= nil and posX == ownA and cursorY == ownB)
            end
            if not same then
                Say(kindName, (labelText or get) .. (i > 2 and ("#" .. (i - 1)) or ""), posX, cursorY)
                return
            end
        end
    end
    -- one change on the pooled object: the setter with values, or the opposite
    -- of the new object's flag
    local function Mutate(a, b, cfg)
        if cfg.key then
            b[cfg.key] = true
            return
        end
        local set = b[cfg[1]]
        if type(set) ~= "function" then return end
        if cfg.flip then
            local fg = a[cfg.flip]
            if type(fg) ~= "function" then return end
            local success, val = pcall(fg, a)
            if success then pcall(set, b, not val) end
        elseif type(cfg.v) == "function" then
            pcall(set, b, cfg.v(hostFrame))
        else
            pcall(set, b, unpack(cfg.v or EMPTY))
        end
    end
    local function Check(kindName, a, b, c)
        if c.key then
            if rawget(a, c.key) ~= rawget(b, c.key) then
                Say(kindName, "key " .. c.key, rawget(a, c.key), rawget(b, c.key))
            end
            return
        end
        local get = c.get or c.flip
        if get then Compare(kindName, nil, a, b, get, c.ga, a, b) end
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
            v = function() return _G.GameFontNormal end,
            get = "GetNormalFontObject",
        },
        {
            "SetHighlightFontObject",
            v = function() return _G.GameFontHighlight end,
            get = "GetHighlightFontObject",
        },
        {
            "SetDisabledFontObject",
            v = function() return _G.GameFontDisable end,
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
            v = function() return _G.GetTime(), 30 end,
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
            v = function(height) return height:CreateMaskTexture() end,
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
            v = function(height) return height end,
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

    local function Run(kindName, entries, a, b, dress)
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
                    Check(kindName, a, b, c)
                end
            end
        end
    end
    local function DressFrame(o)
        o:SetSize(40, 20)
        o:ClearAllPoints()
        o:SetPoint("CENTER", hostFrame)
        if o.SetFont and o:GetObjectType() == "EditBox" then o:SetFont(FONT, 12, "") end
    end

    local function CheckPooledFrame(frameType, template, entries)
        local kindName = template and (frameType .. "|" .. template) or frameType
        local a = _G.CreateFrame(frameType, nil, hostFrame, template)
        local widget = Pool.CreateFrame(frameType, nil, hostFrame, template)
        if not FrameRecs[widget] then
            Say(kindName, "pool", "pooled", "not pooled")
            return
        end
        local finish = Run(kindName, entries, a, widget, DressFrame)
        local roleMap = ENGINE_ROLES[frameType]
        if roleMap then
            for _, roleName in ipairs(roleMap) do
                if roleName.make and widget[roleName.make] then
                    if roleName.text then pcall(widget.SetNormalFontObject, widget, _G.GameFontNormal) end
                    pcall(widget[roleName.make], widget, roleName.text and "x" or ART)
                end
                local registry = widget[roleName.get] and SafeCall(widget[roleName.get], widget)
                if registry then
                    if registry.SetVertexColor then pcall(registry.SetVertexColor, registry, 1, 0, 0, 0.5) end
                    if registry.SetTextColor then pcall(registry.SetTextColor, registry, 1, 0, 0, 1) end
                    pcall(registry.SetAlpha, registry, 0.5)
                    pcall(registry.ClearAllPoints, registry)
                end
            end
        end
        if frameType == "ScrollFrame" then
            local childFrame = _G.CreateFrame("Frame", nil, widget)
            childFrame:SetSize(10, 500)
            widget:SetScrollChild(childFrame)
        end
        Pool._ResetForTest(widget)
        finish()
        if frameType == "ScrollFrame" then
            local ca, checkBtn = a:GetScrollChild(), widget:GetScrollChild()
            if ca ~= nil or (checkBtn ~= nil and not Pool._IsPlaceholder(checkBtn)) then
                Say(kindName, "GetScrollChild", ca, checkBtn)
            end
        end
        if roleMap then
            for _, roleName in ipairs(roleMap) do
                local ga, gb = a[roleName.get], widget[roleName.get]
                local ra = ga and SafeCall(ga, a)
                local rebuild = gb and SafeCall(gb, widget)
                if rebuild and not roleName.live and ra == nil and rebuild:IsShown() then
                    local drawn = (
                        rebuild.GetTexture
                        and (rebuild:GetTexture() or (rebuild.GetAtlas and rebuild:GetAtlas()))
                    )
                        or (rebuild.GetText and rebuild:GetText() ~= "" and rebuild:GetText())
                    if drawn then Say(kindName, roleName.get .. " after the reset", "none", drawn) end
                end
                if roleName.make and a[roleName.make] then
                    if roleName.text then
                        pcall(a.SetNormalFontObject, a, _G.GameFontNormal)
                        pcall(widget.SetNormalFontObject, widget, _G.GameFontNormal)
                    end
                    pcall(a[roleName.make], a, roleName.text and "y" or ART)
                    pcall(widget[roleName.make], widget, roleName.text and "y" or ART)
                    ra = ga and SafeCall(ga, a)
                    rebuild = gb and SafeCall(gb, widget)
                end
                if ra and rebuild then
                    for _, g in ipairs(REGION_LOOK) do
                        Compare(
                            kindName,
                            roleName.get .. ":" .. g,
                            ra,
                            rebuild,
                            g,
                            g == "GetPoint" and { 1 } or nil,
                            a,
                            widget
                        )
                    end
                elseif (ra == nil) ~= (rebuild == nil) and (roleName.make or roleName.live) then
                    Say(kindName, roleName.get, ra, rebuild)
                end
            end
        end
        a:Hide()
        a:SetParent(SpareParent())
    end

    local function VerifyRegion(kindName, method, entries)
        local a = getmetatable(hostFrame).__index[method](hostFrame, nil, "ARTWORK")
        local b = hostFrame[method](hostFrame, nil, "ARTWORK")
        if not FrameRecs[b] then
            Say(kindName, "pool", "pooled", "not pooled")
            return
        end
        local finish = Run(kindName, entries, a, b, function(o)
            o:ClearAllPoints()
            if kindName == "Line" then
                o:SetStartPoint("TOPLEFT", hostFrame)
                o:SetEndPoint("BOTTOMRIGHT", hostFrame)
            else
                o:SetSize(32, 16)
                o:SetPoint("CENTER", hostFrame)
            end
            if kindName == "FontString" then
                o:SetFont(FONT, 12, "")
                o:SetText("Fuzz")
            end
        end)
        Pool._ResetForTest(b)
        finish()
        a:Hide()
        a:SetParent(SpareParent())
    end

    local function VerifyAnimations()
        local fa = getmetatable(hostFrame).__index.CreateAnimationGroup(hostFrame)
        local faA = fa:CreateAnimation("Alpha")
        local gb = hostFrame:CreateAnimationGroup()
        local gbA = gb:CreateAnimation("Alpha")
        if not FrameRecs[gb] then
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

    CheckPooledFrame("Frame", nil, { FRAME })
    CheckPooledFrame("Frame", "BackdropTemplate", { FRAME })
    CheckPooledFrame("Button", nil, { FRAME, BUTTON })
    CheckPooledFrame("CheckButton", nil, { FRAME, BUTTON, CHECK })
    CheckPooledFrame("EditBox", nil, { FRAME, EDIT })
    CheckPooledFrame("ScrollFrame", nil, { FRAME, SCROLL })
    CheckPooledFrame("StatusBar", nil, { FRAME, BAR })
    CheckPooledFrame("Cooldown", "CooldownFrameTemplate", { FRAME, CD })
    CheckPooledFrame("PlayerModel", nil, { FRAME, MODEL })
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
        local a = _G.CreateFrame("EditBox", nil, hostFrame)
        local widget = Pool.CreateFrame("EditBox", nil, hostFrame)
        if FrameRecs[widget] and pcall(widget.SetHistoryLines, widget, 5) then
            Pool._ResetForTest(widget)
            local r = FrameRecs[widget]
            if not SameVal(a:GetHistoryLines(), widget:GetHistoryLines()) and not (r and r.engine) then
                Say(
                    "EditBox",
                    "GetHistoryLines (handed out again)",
                    a:GetHistoryLines(),
                    widget:GetHistoryLines()
                )
            end
        end
        a:Hide()
        a:SetParent(SpareParent())
    end
    -- the same for an animation's smoothing: its group must be retired
    do
        local fa = getmetatable(hostFrame).__index.CreateAnimationGroup(hostFrame)
        local faA = fa:CreateAnimation("Alpha")
        local gb = hostFrame:CreateAnimationGroup()
        local gbA = gb:CreateAnimation("Alpha")
        if FrameRecs[gb] and pcall(gbA.SetSmoothing, gbA, "IN") then
            Pool._ResetForTest(gb)
            local r = FrameRecs[gb]
            if faA:GetSmoothing() ~= gbA:GetSmoothing() and not (r and r.unfit) then
                Say("Alpha", "GetSmoothing (handed out again)", faA:GetSmoothing(), gbA:GetSmoothing())
            end
        end
    end

    -- what the resets could not put back (those objects are retired)
    for i = 1, #refusedLog do
        CUI.Print("pool check note: " .. refusedLog[i])
    end
    refusedLog = nil
    for i = 1, #result do
        CUI.PrintError("pool check: " .. result[i])
    end
    CUI.Print(
        CUI.COLOR_CODES.BRAND
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
function CUI.NewInlineEye(region)
    local eye = Pool.CreateFrame("Button", nil, region)
    eye:SetSize(26, 26)
    eye:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
    eye:SetFrameLevel(region:GetFrameLevel() + 5)
    CUI.SetGlyphAlpha(eye, 0.4)
    region._lastInline = eye
    local glyph = eye:CreateTexture(nil, "OVERLAY")
    glyph:SetAllPoints()
    return eye, glyph
end

-- An eye toggle for a preview element whose shown state is store[field]: a
-- click flips it and calls onToggle, the glyph shows the action a click
-- would take, and the tooltip reads "Hide <what> preview" or "Show <what>
-- preview" to match.
function CUI.AddPreviewEye(region, store, field, what, onToggle)
    local eye, glyph = CUI.NewInlineEye(region)
    local function Paint() glyph:SetTexture(store[field] and CUI.EYE_INVISIBLE_ICON or CUI.EYE_VISIBLE_ICON) end
    Paint()
    eye:SetScript("OnClick", function()
        store[field] = not store[field]
        Paint()
        onToggle()
    end)
    eye:SetScript("OnEnter", function(self)
        CUI.SetGlyphAlpha(self, 0.7)
        CUI.ShowWidgetTooltip(self, (store[field] and "Hide " or "Show ") .. what .. " preview")
    end)
    eye:SetScript("OnLeave", function(self)
        CUI.SetGlyphAlpha(self, 0.4)
        CUI.HideWidgetTooltip()
    end)
    return eye
end

-- A mouse-catching cover over a colour swatch (or any control), ten levels
-- above it: shown, it blocks clicks on a control that cannot be edited right
-- now. It starts shown; the caller hides or shows it with its state.
function CUI.NewSwatchBlocker(control)
    local cover = Pool.CreateFrame("Frame", nil, control)
    cover:SetAllPoints()
    cover:SetFrameLevel(control:GetFrameLevel() + 10)
    cover:EnableMouse(true)
    return cover
end
