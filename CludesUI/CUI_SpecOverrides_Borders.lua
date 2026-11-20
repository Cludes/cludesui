if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_SpecOverrides_Borders.lua
--
--  Element contexts, profile snapshots and diffs, unlock-session value
--  banking, the golden borders and the edit locks.
--  Reads the earlier Spec Overrides files through CUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
local Inner = CUI_NS._soInternals
-- CludesUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local BlacklistedFKey, ConflictSpec, DeepCopy = Inner.BlacklistedFKey, Inner.ConflictSpec, Inner.DeepCopy
local EntryOwning, FKeyLoaded, FS, GetGroups = Inner.EntryOwning, Inner.FKeyLoaded, Inner.FS, Inner.GetGroups
local GetStore, GOLD_B, GOLD_G, GOLD_R = Inner.GetStore, Inner.GOLD_B, Inner.GOLD_G, Inner.GOLD_R
local GroupById, L, MatchOwnedFKey, NIL_SENT = Inner.GroupById, Inner.L, Inner.MatchOwnedFKey, Inner.NIL_SENT
local PS, ReadLive, SpecName, Cond = Inner.PS, Inner.ReadLive, Inner.SpecName, Inner.Cond
local EXCLUDED_CONTEXTS, SetRequestGoldWalk = Inner.EXCLUDED_CONTEXTS, Inner.SetRequestGoldWalk

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of CludesUI_SpecOverrides.lua).
local _editGroup = nil
Inner.editGroupSetters[#Inner.editGroupSetters + 1] = function(v)
    _editGroup = v
end
local _defaultView = false
Inner.defaultViewSetters[#Inner.defaultViewSetters + 1] = function(v)
    _defaultView = v
end

-- Forward declarations (assigned further down in this file)
local RequestGoldWalk

-------------------------------------------------------------------------------
--  Element-context providers for selector pages ("which bar / frame is selected").
--  Options pages with an element selector register a provider so captured entries
--  carry their element, making labels and golden borders element-aware.
-------------------------------------------------------------------------------
local _captureContexts = {}

--- fn() -> display label of the module's currently selected element (or nil).
function CludesUI.RegisterCaptureContext(folder, func)
    if type(folder) == "string" and type(func) == "function" then
        _captureContexts[folder] = func
    end
end

local function CurrentContext()
    local modFolder = CludesUI:GetActiveModule()
    local ctxFn = modFolder and _captureContexts[modFolder]
    if not ctxFn then
        return nil
    end
    local success, context = pcall(ctxFn)
    if success and type(context) == "string" and context ~= "" then
        return context
    end
    return nil
end

-------------------------------------------------------------------------------
--  Profile snapshots + diffs (the auto-capture watcher's engine)
-------------------------------------------------------------------------------
local function SnapshotProfiles()
    local snap = {}
    local reg = CludesUI.Lite and CludesUI.Lite._dbRegistry
    if not reg then
        return snap
    end
    for _, saved in ipairs(reg) do
        if saved.folder and type(saved.profile) == "table" then
            snap[saved.folder] = DeepCopy(saved.profile)
        end
    end
    return snap
end

local function DiffTables(old, new, prefixText, result, numFlag)
    for key, nv in pairs(new) do
        local shade = old[key]
        local isNum = numFlag or (type(key) == "number")
        local filePath = prefixText and (prefixText .. PS .. tostring(key)) or tostring(key)
        if type(nv) == "table" and type(shade) == "table" then
            DiffTables(shade, nv, filePath, result, isNum)
        elseif nv ~= shade then
            result[#result + 1] = { path = filePath, val = nv, num = isNum }
        end
    end
    for key in pairs(old) do
        if new[key] == nil then
            local isNum = numFlag or (type(key) == "number")
            local filePath = prefixText and (prefixText .. PS .. tostring(key)) or tostring(key)
            result[#result + 1] = { path = filePath, removed = true, num = isNum }
        end
    end
end

local function DiffProfiles(snap)
    local result = {}
    local reg = CludesUI.Lite and CludesUI.Lite._dbRegistry
    if not reg then
        return result
    end
    for _, saved in ipairs(reg) do
        local old = saved.folder and snap[saved.folder]
        if old and type(saved.profile) == "table" then
            local changes = {}
            DiffTables(old, saved.profile, nil, changes)
            for _, c in ipairs(changes) do
                c.folder = saved.folder
                c.fkey = saved.folder .. FS .. c.path
                result[#result + 1] = c
            end
        end
    end
    return result
end

-------------------------------------------------------------------------------
--  Unlock-session value-edit banking: CAPTURED settings edited from unlock mode
--  (cog width/height inputs write the shared module store) happen panel-closed, so
--  no view owns them and the sticky harvest never adopts foreign live diffs --
--  without this the next value apply REVERTS the unlock-mode resize. A NORMAL
--  unlock session edits the shared baseline exactly like Default Editing Mode, so
--  Save & Exit banks captured diffs into values.default. Special (group fork)
--  sessions hide the size inputs and never bank here; Cancel discards.
-------------------------------------------------------------------------------
local _unlockValueSnap = nil

function CludesUI.SpecOverrides_UnlockValueSnapBegin()
    _unlockValueSnap = nil
    local storage = GetStore()
    if not storage or #storage == 0 then
        return
    end
    if CludesUI._specialUnlockGroup then
        return
    end
    _unlockValueSnap = SnapshotProfiles()
end

function CludesUI.SpecOverrides_UnlockValueSnapDiscard()
    _unlockValueSnap = nil
end

function CludesUI.SpecOverrides_UnlockValueSnapCommit()
    local snap = _unlockValueSnap
    _unlockValueSnap = nil
    if not snap then
        return
    end
    -- Sessions/views cannot be live while unlock mode is open (the panel
    -- force-closes on entry); this guards any flow that changes that.
    if _editGroup or _defaultView or Cond._edit then
        return
    end
    local changed = false
    for _, c in ipairs(DiffProfiles(snap)) do
        local record = EntryOwning(c.fkey)
        -- Match-owned size keys: an unlock-session diff on these is the match
        -- engine's write (re-pull on target resize), never a cog edit. Skip.
        if record and not BlacklistedFKey(c.fkey) and not MatchOwnedFKey(c.fkey) and FKeyLoaded(c.fkey) then
            local live = ReadLive(c.fkey)
            if type(live) ~= "table" then
                record.values.default[c.fkey] = (live == nil) and NIL_SENT or live
                changed = true
            end
        end
    end
    if changed then
        RequestGoldWalk()
    end
end

-- EXCLUDED_CONTEXTS is declared earlier, shared with the conditional-overrides
-- block. section is optional: callers with no section context (page overlay, gold
-- walk) treat a section-scoped page entry as NOT excluded -- only the listed
-- sections are outside the system, enforced where the section is known
-- (AutoCapture attribution and entry pruning).
local function IsExcludedContext(section)
    local module = CludesUI:GetActiveModule()
    local ex = module and EXCLUDED_CONTEXTS[module]
    if ex == true then
        return true
    end
    if type(ex) == "table" then
        local page = CludesUI:GetActivePage()
        local pex = page and ex[page]
        if pex == true then
            return true
        end
        if type(pex) == "table" then
            return (section and pex[section]) and true or false
        end
    end
    return false
end

--- True while a session is live AND the page in front of the user can actually bank a
--- value into it. A bespoke control that writes its own key on click (the Visibility
--- row's override marker) must gate on THIS, not on SpecOverrides_EditSessionActive:
--- session state is global, so on an excluded page that write would land in the shared
--- profile, be dropped by every capture gate as blacklisted, and strand there with
--- nothing owning it. The editing-as overlay is decoration only (EnableMouse(false)),
--- so nothing else stops such a click.
function CludesUI.SpecOverrides_SlotOverridable()
    if not CludesUI.SpecOverrides_EditSessionActive() then
        return false
    end
    return not IsExcludedContext()
end

-------------------------------------------------------------------------------
--  Golden borders: slots with an active override get a 1px gold PP border. Slots
--  match entries by READ-TRACING: getters are side-effect-free by convention (the
--  refresh system calls them constantly), so a walk swaps the addon profile tables
--  for read-tracking proxies, runs each visible slot's getters once, and matches
--  the recorded paths against entry fkeys. Needs no label metadata and is
--  inherently element-aware on selector pages (Bar 1 selected -> getters read
--  bar1 paths -> only Bar 1's entries match).
-------------------------------------------------------------------------------
local _traceSink = nil
local _traceReal = nil

local MakeReadProxy
do
    -- proxy -> the table it reads (weak). A getter that writes back a table it
    -- read under the trace (an accessor that ensures or compacts a structure)
    -- must store the tables behind the proxies: a proxy holds nothing of its
    -- own, so SavedVariables would save it empty, and the next trace would wrap
    -- it again, one layer per walk until reading it overflows the C stack.
    -- Writes unwrap the value, and the proxies one level inside a plain table
    -- built from them. (A do-block.)
    local proxyOf = setmetatable({}, { __mode = "k" })
    local function Unwrap(v)
        local r = proxyOf[v]
        while r do
            v = r
            r = proxyOf[v]
        end
        if type(v) == "table" then
            for key, posX in next, v do
                local rx = type(posX) == "table" and proxyOf[posX]
                if rx then
                    rawset(v, key, Unwrap(rx))
                end
            end
        end
        return v
    end

    MakeReadProxy = function(real, folder, prefixText)
        local proxy = {}
        setmetatable(proxy, {
            __index = function(_, key)
                local v = real[key]
                local filePath = prefixText and (prefixText .. PS .. tostring(key)) or tostring(key)
                if type(v) == "table" then
                    return MakeReadProxy(v, folder, filePath)
                end
                if _traceSink then
                    _traceSink[folder .. FS .. filePath] = true
                end
                return v
            end,
            __newindex = function(_, key, v)
                real[key] = Unwrap(v)
            end,
        })
        proxyOf[proxy] = real
        return proxy
    end
end

local function BeginTrace()
    local reg = CludesUI.Lite and CludesUI.Lite._dbRegistry
    if not reg or _traceReal then
        return false
    end
    _traceReal = {}
    for _, saved in ipairs(reg) do
        if saved.folder and type(saved.profile) == "table" then
            _traceReal[saved] = saved.profile
            saved.profile = MakeReadProxy(saved.profile, saved.folder, nil)
        end
    end
    return true
end

local function EndTrace()
    if not _traceReal then
        return
    end
    for saved, real in pairs(_traceReal) do
        saved.profile = real
    end
    _traceReal = nil
end

-- Runs a slot's getters under the read proxies; returns the set of fkeys read.
local function TraceSlot(conf)
    _traceSink = {}
    local accs = conf.accessors or { conf }
    for _, acc in ipairs(accs) do
        if acc.getValue then
            pcall(acc.getValue)
        end
    end
    local sink = _traceSink
    _traceSink = nil
    return sink
end

-- The set of fkeys a slot's getters read, traced on its own: an empty set while
-- another trace is live or the profiles cannot be traced. EndTrace runs on every
-- path (see the gold walk below).
local function SlotReads(conf)
    if not (conf and BeginTrace()) then
        return {}
    end
    local success, sink = pcall(TraceSlot, conf)
    EndTrace()
    if success and type(sink) == "table" then
        return sink
    end
    return {}
end

local function MakeBorderHost(regionFrame, red, green, blue)
    local host = CreateFrame("Frame", nil, regionFrame)
    host:SetAllPoints()
    host:SetFrameLevel(regionFrame:GetFrameLevel() + 30)
    if CludesUI.PP and CludesUI.PP.CreateBorder then
        CludesUI.PP.CreateBorder(host, red, green, blue, 0.9, 1, "OVERLAY", 7)
    end
    return host
end

-- mode: false (clear), "gold" (overridden), "red" (owned by a conflicting group
-- while editing: red border + click-blocking tooltip overlay), or "condActive" (the
-- APPLIED conditional owns this setting NOW -- the on-screen value is the
-- override's, an edit would bank into it at the next boundary, not the default;
-- labeled overlay + click blocker pointing at its edit mode).
-- tip: gold only -- the "Overridden by: ..." tooltip text (SlotTipFor), shown from
-- a small info badge in the slot's top-left corner (the only hover surface: the
-- widget's own label/control tooltips stay untouched).
-- A mark frame on a region of the options page pool rides on it (hidden at the
-- region's reset, its key kept) instead of being lost with the region's dress;
-- the region's next dress puts it at its new frame level (as a new mark would be).
local function SetSlotMark(regionFrame, mode, conflictSpecID, condName, tipText)
    local m = regionFrame._specOvGold
    if m and m._soStale then
        m._soStale = nil
        m:SetFrameLevel(regionFrame:GetFrameLevel() + 30)
    end
    m = regionFrame._specOvHover
    if m and m._soStale then
        m._soStale = nil
        m:SetFrameLevel(regionFrame:GetFrameLevel() + 31)
    end
    m = regionFrame._specOvRed
    if m and m._soStale then
        m._soStale = nil
        m:SetFrameLevel(regionFrame:GetFrameLevel() + 30)
        m._blocker:SetFrameLevel(regionFrame:GetFrameLevel() + 45)
    end
    m = regionFrame._specOvCondActive
    if m and m._soStale then
        m._soStale = nil
        m:SetFrameLevel(regionFrame:GetFrameLevel() + 30)
        m._blocker:SetFrameLevel(regionFrame:GetFrameLevel() + 45)
    end
    local Pool = CludesUI._Pool
    if mode == "gold" and not regionFrame._specOvGold then
        regionFrame._specOvGold = MakeBorderHost(regionFrame, GOLD_R, GOLD_G, GOLD_B)
        if Pool and Pool.Gen and Pool.Gen(regionFrame) then
            Pool.Attach(regionFrame, regionFrame._specOvGold, "_specOvGold", function(hgt)
                hgt._soStale = true
            end)
        end
    end
    if mode == "gold" and tipText and not regionFrame._specOvHover then
        -- Info badge: gold "i" bubble tucked inside the gold border's top-left
        -- corner (that corner is empty on every slot layout -- labels start at
        -- the side pad, vertically centered). Motion-only and click-through
        -- (same recipe as the widget label hit frames), one level above the
        -- border host so it renders on top; nothing else lives in that corner,
        -- so no control loses hover to it.
        local badge = CreateFrame("Frame", nil, regionFrame)
        badge:SetSize(14, 14)
        badge:SetPoint("TOPLEFT", regionFrame, "TOPLEFT", 3, -3)
        badge:SetFrameLevel(regionFrame:GetFrameLevel() + 31)
        local ico = badge:CreateTexture(nil, "OVERLAY")
        ico:SetAllPoints()
        if ico.SetSnapToPixelGrid then
            ico:SetSnapToPixelGrid(false)
            ico:SetTexelSnappingBias(0)
        end
        ico:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-info.png")
        ico:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 0.85)
        badge:SetScript("OnEnter", function()
            ico:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1)
            local t = regionFrame._specOvTip
            if t and CludesUI.ShowWidgetTooltip then
                CludesUI.ShowWidgetTooltip(badge, t)
            end
        end)
        badge:SetScript("OnLeave", function()
            ico:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 0.85)
            CludesUI.HideWidgetTooltip()
        end)
        badge:SetMouseClickEnabled(false)
        regionFrame._specOvHover = badge
        if Pool and Pool.Gen and Pool.Gen(regionFrame) then
            Pool.Attach(regionFrame, badge, "_specOvHover", function(hgt)
                hgt._soStale = true
            end)
        end
    end
    if mode == "red" and not regionFrame._specOvRed then
        local host = MakeBorderHost(regionFrame, 0.9, 0.2, 0.2)
        local blocker = CreateFrame("Button", nil, host)
        blocker:SetAllPoints()
        blocker:SetFrameLevel(regionFrame:GetFrameLevel() + 45)
        blocker:EnableMouse(true)
        local tint = blocker:CreateTexture(nil, "OVERLAY")
        tint:SetAllPoints()
        tint:SetColorTexture(0.9, 0.2, 0.2, 0.05)
        blocker:SetScript("OnEnter", function(self)
            if self._tipText and CludesUI.ShowWidgetTooltip then
                CludesUI.ShowWidgetTooltip(self, self._tipText)
            end
        end)
        blocker:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        host._blocker = blocker
        regionFrame._specOvRed = host
        if Pool and Pool.Gen and Pool.Gen(regionFrame) then
            Pool.Attach(regionFrame, host, "_specOvRed", function(hgt)
                hgt._soStale = true
            end)
        end
    end
    if mode == "condActive" and not regionFrame._specOvCondActive then
        -- Same look as the RF party-tab sync overlays (solid dark blue cover, centered
        -- label in the global font) plus override identity: gold border + gold label.
        -- The border goes on the BLOCKER at a high sublevel so it renders above the
        -- solid background (a border on the host would be covered).
        local host = CreateFrame("Frame", nil, regionFrame)
        host:SetAllPoints()
        host:SetFrameLevel(regionFrame:GetFrameLevel() + 30)
        local blocker = CreateFrame("Button", nil, host)
        blocker:SetAllPoints()
        blocker:SetFrameLevel(regionFrame:GetFrameLevel() + 45)
        blocker:EnableMouse(true)
        local backdrop = blocker:CreateTexture(nil, "OVERLAY")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(17 / 255, 15 / 255, 12 / 255, 1)
        if CludesUI.PP and CludesUI.PP.CreateBorder then
            CludesUI.PP.CreateBorder(blocker, GOLD_R, GOLD_G, GOLD_B, 0.9, 1, "OVERLAY", 7)
        end
        local font = (CludesUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local flag = (CludesUI.GetFontOutlineFlag()) or ""
        local labelText = blocker:CreateFontString(nil, "OVERLAY")
        if CludesUI.PrimeFontShadow and CludesUI.GetFontUseShadow then
            CludesUI.PrimeFontShadow(labelText, CludesUI.GetFontUseShadow())
        end
        labelText:SetFont(font, 13, flag)
        labelText:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 1)
        labelText:SetPoint("LEFT", blocker, "LEFT", 4, 0)
        labelText:SetPoint("RIGHT", blocker, "RIGHT", -4, 0)
        labelText:SetJustifyH("CENTER")
        labelText:SetWordWrap(false)
        blocker:SetScript("OnEnter", function(self)
            if self._tipText and CludesUI.ShowWidgetTooltip then
                CludesUI.ShowWidgetTooltip(self, self._tipText)
            end
        end)
        blocker:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        host._blocker = blocker
        host._label = labelText
        regionFrame._specOvCondActive = host
        if Pool and Pool.Gen and Pool.Gen(regionFrame) then
            Pool.Attach(regionFrame, host, "_specOvCondActive", function(hgt)
                hgt._soStale = true
            end)
        end
    end
    if regionFrame._specOvGold then
        regionFrame._specOvGold:SetShown(mode == "gold")
    end
    -- Tip lives only while the slot is gold; the label tooltips read it live.
    if mode == "gold" then
        regionFrame._specOvTip = tipText
    else
        regionFrame._specOvTip = nil
    end
    if regionFrame._specOvHover then
        regionFrame._specOvHover:SetShown(regionFrame._specOvTip ~= nil)
    end
    if regionFrame._specOvRed then
        regionFrame._specOvRed:SetShown(mode == "red")
        if mode == "red" and regionFrame._specOvRed._blocker then
            regionFrame._specOvRed._blocker._tipText = string.format(
                L("This setting already has an override for %s"),
                conflictSpecID and SpecName(conflictSpecID) or "?"
            )
        end
    end
    if regionFrame._specOvCondActive then
        regionFrame._specOvCondActive:SetShown(mode == "condActive")
        if mode == "condActive" then
            local host = regionFrame._specOvCondActive
            if host._label then
                host._label:SetText(string.format(L("Override Active: %s"), condName or "?"))
            end
            if host._blocker then
                host._blocker._tipText = string.format(
                    L("Showing the '%s' override's value. Edit it from that override's editing mode."),
                    condName or "?"
                )
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Edit locks: regions that must be non-interactive while ANY Editing-as session is
--  active (same red prevention frame as cross-group conflicts). Used by hands-off
--  systems with their own per-spec handling (e.g. Resource Bars' Threshold & Hash
--  Lines slots). Regions register per page build; dead pages release their locks
--  via the weak table.
-------------------------------------------------------------------------------
local _editLocks = setmetatable({}, { __mode = "k" })

local function UpdateEditLocks()
    local specOn = _editGroup ~= nil
    for _, host in pairs(_editLocks) do
        -- A lock whose region the options page pool reset belongs to no row until
        -- the region is locked again (AttachEditLock): it stays hidden.
        if host._inactive then
            -- nothing
            -- Predicate locks decide their own visibility per session (e.g. the
            -- Dark Mode condition locks); plain locks show for any spec session.
        elseif host._predicate then
            host:SetShown(host._predicate() and true or false)
        else
            host:SetShown(specOn)
        end
    end
end

-- AttachEditLock predicate for widgets writing the dark-mode CONDITION's input
-- flags (UF darkTheme, RF healthColorMode: the Colors page's Dark Mode rows; the
-- Class Resource Bar row is NOT an input -- DarkModeMasterOn excludes it). True when
--   (a) the editing-as session is a CONDITIONAL group with the Dark Mode
--       condition: capturing a dark flag into it lets the override flip its own
--       activation condition (apply -> false -> restore -> true -> ...); or
--   (b) ANY conditional session is active AND a Dark Mode group exists: a dark
--       flag captured into a dungeon/keybind/solo group fights the Dark Mode
--       group through the resolution ladder (same oscillation, two groups).
-- Spec-group sessions never lock these: spec activation does not read dark
-- state, so a spec-captured dark flag settles in one apply.
function CludesUI.SpecOverrides_DarkCondEditActive()
    local g = Cond and Cond._edit
    if not g then
        return false
    end
    if g.conds and g.conds.darkmode then
        return true
    end
    local groups = CludesUI.Conditions_GetGroups and CludesUI.Conditions_GetGroups()
    if groups then
        for _, og in ipairs(groups) do
            if og.conds and og.conds.darkmode then
                return true
            end
        end
    end
    return false
end

function CludesUI.SpecOverrides_AttachEditLock(regionFrame, tipText, predicate)
    if not regionFrame then
        return
    end
    local host = _editLocks[regionFrame]
    if not host then
        host = MakeBorderHost(regionFrame, 0.9, 0.2, 0.2)
        local blocker = CreateFrame("Button", nil, host)
        blocker:SetAllPoints()
        blocker:SetFrameLevel(regionFrame:GetFrameLevel() + 45)
        blocker:EnableMouse(true)
        local tint = blocker:CreateTexture(nil, "OVERLAY")
        tint:SetAllPoints()
        tint:SetColorTexture(0.9, 0.2, 0.2, 0.05)
        blocker:SetScript("OnEnter", function(self)
            if self._tipText and CludesUI.ShowWidgetTooltip then
                CludesUI.ShowWidgetTooltip(self, self._tipText)
            end
        end)
        blocker:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        host._blocker = blocker
        _editLocks[regionFrame] = host
        -- On a region of the options page pool the lock rides on it: the region's
        -- reset hides it and leaves it inactive until the region is locked again.
        local Pool = CludesUI._Pool
        if Pool and Pool.Gen and Pool.Gen(regionFrame) then
            Pool.Attach(regionFrame, host, nil, function(hgt)
                hgt._inactive = true
                hgt:Hide()
            end)
        end
    end
    if host._inactive then
        -- back on its region's new dress: at the region's new level
        host._inactive = nil
        host:SetFrameLevel(regionFrame:GetFrameLevel() + 30)
        host._blocker:SetFrameLevel(regionFrame:GetFrameLevel() + 45)
    end
    host._blocker._tipText = tipText
    host._predicate = predicate
    if predicate then
        host:SetShown(predicate() and true or false)
    else
        host:SetShown(_editGroup ~= nil)
    end
end

-- "Overridden by: ..." tooltip for a gold slot, from the slot's traced fkeys:
-- every spec group with a member spec HOLDING a value on any of them (a spec in
-- several groups lists each -- the management list buckets the same way), held
-- values on ungrouped specs by spec name (legacy / stranded values still apply),
-- the creating group when nothing holds a value yet (a fresh session capture banks
-- at exit), and every conditional group holding a value. Holding, not differing:
-- a member value equal to the current default still pins that spec, which is
-- exactly what a base editor needs to know. Outside a session a second line says
-- what a base edit does. nil when no override names resolve.
local _tipNames = {} -- array part = names in order; hash part = dedupe set
local function AddTipName(name)
    if name and not _tipNames[name] then
        _tipNames[name] = true
        _tipNames[#_tipNames + 1] = name
    end
end
local function SlotTipFor(sink)
    wipe(_tipNames)
    local groups = GetGroups()
    for fkey in pairs(sink) do
        local e = EntryOwning(fkey)
        if e and e.values then
            local held = false
            for key, m in pairs(e.values) do
                if type(key) == "number" and type(m) == "table" and m[fkey] ~= nil then
                    held = true
                    local grouped = false
                    for _, group in ipairs(groups or {}) do
                        for _, spellRef in ipairs(group.specs or {}) do
                            if spellRef == key then
                                AddTipName(group.name or "?")
                                grouped = true
                                break
                            end
                        end
                    end
                    if not grouped then
                        AddTipName(SpecName(key))
                    end
                end
            end
            if not held and e.group then
                local g = GroupById(e.group)
                if g then
                    AddTipName(g.name or "?")
                end
            end
        end
        local ce = Cond.EntryOwning(fkey)
        if ce and ce.values then
            -- A spec override on the same fkey evicts the conditional at runtime
            -- (Cond.WriteValues skips spec-owned fkeys outside a session); say so
            -- with the same "held by" wording the Overrides list row uses.
            local heldBy
            if e and e.group then
                local og = GroupById(e.group)
                heldBy = og and og.name
            end
            for key, m in pairs(ce.values) do
                if type(key) == "number" and type(m) == "table" and m[fkey] ~= nil then
                    local cg = CludesUI.Conditions_GroupById and CludesUI.Conditions_GroupById(key)
                    if cg then
                        local tag = L("conditional")
                        if heldBy then
                            tag = tag .. ", " .. string.format(L("held by '%s'"), heldBy)
                        end
                        AddTipName((cg.name or "?") .. " |cff909090(" .. tag .. ")|r")
                    end
                end
            end
        end
    end
    if #_tipNames == 0 then
        return nil
    end
    local s = "|cffc7a65a" .. L("Overridden by:") .. "|r " .. table.concat(_tipNames, ", ")
    if not _editGroup and not Cond._edit then
        s = s
            .. "\n|cff909090"
            .. L("Changes here edit the shared default; overrides keep their own values.")
            .. "|r"
    end
    return s
end

local function GoldWalk(widget, forceOff, condGid, condName)
    local conf = widget._captureCfg
    if conf and not conf.noCapture and not forceOff then
        local record, condActive
        local sink = TraceSlot(conf)
        for fkey in pairs(sink) do
            -- Applied-conditional context (no session): a slot whose fkey the
            -- LIVE conditional banks a value for shows that override's value
            -- right now -- labeled overlay instead of plain gold.
            if condGid and not condActive then
                local ce = Cond.EntryOwning(fkey)
                local m = ce and ce.values and ce.values[condGid]
                if m and m[fkey] ~= nil then
                    condActive = true
                end
            end
            if not record then
                record = EntryOwning(fkey) or Cond.EntryOwning(fkey)
            end
            if record and (condActive or not condGid) then
                break
            end
        end
        if condActive then
            SetSlotMark(widget, "condActive", nil, condName)
        elseif record then
            local conflict = ConflictSpec(record)
            if conflict then
                SetSlotMark(widget, "red", conflict)
            else
                SetSlotMark(widget, "gold", nil, nil, SlotTipFor(sink))
            end
        else
            SetSlotMark(widget, false)
        end
    else
        if widget._specOvGold then
            widget._specOvGold:Hide()
        end
        if widget._specOvRed then
            widget._specOvRed:Hide()
        end
        if widget._specOvCondActive then
            widget._specOvCondActive:Hide()
        end
        if widget._specOvHover then
            widget._specOvTip = nil
            widget._specOvHover:Hide()
        end
    end
    -- Only what is on screen: a hidden cached page is walked again when it
    -- shows (every page select requests a walk), and its getters never run
    -- under the trace meanwhile (another module's page may be excluded).
    local kids = { widget:GetChildren() }
    for idx = 1, #kids do
        local kid = kids[idx]
        if kid:IsShown() then
            GoldWalk(kid, forceOff, condGid, condName)
        end
    end
end

local _goldWalkQueued = false
RequestGoldWalk = function()
    if _goldWalkQueued then
        return
    end
    _goldWalkQueued = true
    C_Timer.After(0, function()
        _goldWalkQueued = false
        local root = _G.CludesUIFrame
        if not (root and root:IsShown()) then
            return
        end
        -- Excluded contexts never show slot marks (walk still clears stale ones)
        if IsExcludedContext() then
            GoldWalk(root, true)
            return
        end
        if BeginTrace() then
            -- Applied-conditional context for the walk: only outside every
            -- session (a session view shows session values, not the overlay).
            local condGid, condName
            if not _editGroup and not Cond._edit then
                condGid = CludesUI.Conditions_AppliedGid and CludesUI.Conditions_AppliedGid() or nil
                local g = condGid and CludesUI.Conditions_GroupById and CludesUI.Conditions_GroupById(condGid)
                    or nil
                if g then
                    condName = g.name
                else
                    condGid = nil
                end
            end
            -- pcall is LOAD-BEARING: while the trace is active every db.profile
            -- in the Lite registry is a read-tracking PROXY that iterates EMPTY
            -- under pairs/next. An error escaping GoldWalk would skip EndTrace,
            -- strand the proxies for the session, and the next snapshot/logout
            -- write-back would PERSIST empty module profiles (total settings
            -- wipe). EndTrace must run on every path.
            local success, err = pcall(GoldWalk, root, nil, condGid, condName)
            EndTrace()
            if not success and err then
                geterrorhandler()(err)
            end
        end
    end)
end
SetRequestGoldWalk(RequestGoldWalk)

Inner.CurrentContext, Inner.DiffProfiles = CurrentContext, DiffProfiles
Inner.IsExcludedContext, Inner.RequestGoldWalk = IsExcludedContext, RequestGoldWalk
Inner.SnapshotProfiles, Inner.UpdateEditLocks = SnapshotProfiles, UpdateEditLocks
Inner.SlotReads = SlotReads
Inner.broken = false
