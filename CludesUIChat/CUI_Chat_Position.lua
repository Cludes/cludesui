if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Chat_Position.lua
--
--  Where the main chat window sits and how large it is: the Edit Mode
--  store, the saved position and its guard, genesis capture, the resize
--  grip and the size lock.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIChat.lua or an earlier CUI_Chat_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local CHAT = mod.ECHAT
local min, upper, floor, abs = min, max, floor, math.abs

local CFD, EnsureChatClampInsets = Inner.CFD, Inner.EnsureChatClampInsets

-------------------------------------------------------------------------------
--  Chat position: owned by CUI unlock mode once a position is saved (genesis-
--  captured otherwise). Two writers place ChatFrame1: Edit Mode on every
--  layout apply (login, layout switches, Edit Mode exit, every layout save,
--  spec changes -- which WoW Forever also fires on level-ups) and
--  ApplyChatPosition right after it, through the anchor guard. On the
--  player's own layout the store lane below writes our anchor and size into
--  it, so Edit Mode's apply lands on our rect and our pass finds nothing to
--  do. A Blizzard preset cannot be written: there every apply moves chat and
--  the guard moves it back within the same frame (a frame at Edit Mode's
--  spot is the blink, and it moves Blizzard's invisible link zones under our
--  text off our lines: right-clicks that miss or pick the wrong name).
-------------------------------------------------------------------------------

-- ChatFrame1 is an Edit Mode system: its SetPoint and ClearAllPoints are Edit
-- Mode's Lua overrides, which from our code would mark Edit Mode's anchor
-- sweep and the frame's snap state as written by us. Every anchor write of
-- ours goes through the saved C methods instead.
local ClearFramePoints, SetFramePoint = CludesUI.ClearFramePoints, CludesUI.SetFramePoint

-------------------------------------------------------------------------------
--  Edit Mode store. Blizzard's saved-dimensions restore skips the main window
--  ("controlled via edit mode"), so the active Edit Mode layout is the native
--  store for ChatFrame1's position and size, and every layout apply re-applies
--  it. All access goes through the C_EditMode data API only -- never
--  EditModeManagerFrame methods (secure manager chains) -- and only ever saves
--  the blob CludesUI.EditModeLayoutsForSave builds (presets first, as
--  SaveLayouts takes it) with chat's entry edited, so a malformed save cannot
--  be constructed here. Never while Edit Mode is open (it saves its own copy
--  over anything written meanwhile) or in combat.
-------------------------------------------------------------------------------
local function EMChatEnums()
    local sysEnum = Enum and Enum.EditModeSystem
    local setEnum = Enum and Enum.EditModeChatFrameSetting
    local layEnum = Enum and Enum.EditModeLayoutType
    if
        not (
            sysEnum
            and sysEnum.ChatFrame
            and setEnum
            and setEnum.WidthHundreds
            and setEnum.WidthTensAndOnes
            and setEnum.HeightHundreds
            and setEnum.HeightTensAndOnes
            and layEnum
            and layEnum.Preset ~= nil
        )
    then
        return nil
    end
    return sysEnum.ChatFrame, setEnum, layEnum
end

local function EMChatFindSystem(layout, sysChat)
    local systems = layout and layout.systems
    if type(systems) ~= "table" then
        return nil
    end
    for index = 1, #systems do
        local cfg = systems[index]
        if type(cfg) == "table" and cfg.system == sysChat then
            return cfg
        end
    end
end

local function EditModeSetting(sys, settingID)
    local st = sys and sys.settings
    if type(st) ~= "table" then
        return nil
    end
    for index = 1, #st do
        local row = st[index]
        if type(row) == "table" and row.setting == settingID then
            return row
        end
    end
end

-- The blob and the ACTIVE layout entry: blob, entry, sysChat, setEnum,
-- isPreset (nil on any unexpected shape, or while Edit Mode is open).
-- activeLayout indexes the merged list, presets first. A preset entry is
-- read-only (SaveLayouts ignores edits to it): it is only ever read.
local function EMChatResolve()
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then
        return nil
    end
    local sysChat, setEnum, layEnum = EMChatEnums()
    if not sysChat then
        return nil
    end
    if CludesUI.EditModeOpen() then
        return nil
    end
    local blob, numPresets = CludesUI.EditModeLayoutsForSave()
    if not blob then
        return nil
    end
    local isActive = blob.activeLayout
    if type(isActive) ~= "number" then
        return nil
    end
    local record = blob.layouts[isActive]
    if type(record) ~= "table" then
        return nil
    end
    local isPreset = isActive <= numPresets or record.layoutType == layEnum.Preset
    return blob, record, sysChat, setEnum, isPreset
end

-- Stored chat size of a chat system entry (Edit Mode encodes each dimension
-- as hundreds + tens-and-ones setting pairs). nil when unreadable.
local function EMChatReadSize(sys, setEnum)
    local wH = EditModeSetting(sys, setEnum.WidthHundreds)
    local wT = EditModeSetting(sys, setEnum.WidthTensAndOnes)
    local hH = EditModeSetting(sys, setEnum.HeightHundreds)
    local hT = EditModeSetting(sys, setEnum.HeightTensAndOnes)
    if
        not (
            wH
            and wT
            and hH
            and hT
            and type(wH.value) == "number"
            and type(wT.value) == "number"
            and type(hH.value) == "number"
            and type(hT.value) == "number"
        )
    then
        return nil
    end
    return wH.value * 100 + wT.value, hH.value * 100 + hT.value
end

-- True while the saved size still needs the second-corner anchor:
-- cfg.chatSize exists and the active layout does not hold it (or cannot be
-- read). Once it does, Edit Mode's own apply sizes chat and the anchor
-- enforcement stands down.
local function EMChatSizeDelta()
    local conf = CHAT.DB()
    local size = conf and conf.chatSize
    if not (size and size.w and size.h) then
        return false
    end
    -- Belt: after a store write this session, keep the anchor enforcement
    -- standing anyway. Field-tested that SaveLayouts coheres EM's cached
    -- tables immediately, so this should never matter -- it guards the
    -- untested edges (event timing on other clients) at the cost of one
    -- boolean.
    if mod._emChatWrote then
        return true
    end
    local blob, record, sysChat, setEnum = EMChatResolve()
    local sys = blob and EMChatFindSystem(record, sysChat)
    local wid, hgt
    if sys then
        wid, hgt = EMChatReadSize(sys, setEnum)
    end
    if not wid then
        return true
    end
    return abs(wid - size.w) > 1 or abs(hgt - size.h) > 1
end

-- Where each of UIParent's nine points sits in a rect: its share of the
-- width from the left edge and of the height from the bottom edge.
local POINT_FRAC = {
    BOTTOMLEFT = { 0, 0 },
    BOTTOM = { 0.5, 0 },
    BOTTOMRIGHT = { 1, 0 },
    LEFT = { 0, 0.5 },
    CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 },
    TOPLEFT = { 0, 1 },
    TOP = { 0.5, 1 },
    TOPRIGHT = { 1, 1 },
}

-- The screen's size in ChatFrame1's units, the units of its anchor offsets
-- and rect reads.
local function ChatScreenSize(cf1)
    local scale = UIParent:GetEffectiveScale() / cf1:GetEffectiveScale()
    return UIParent:GetWidth() * scale, UIParent:GetHeight() * scale
end

-- The screen point the player picked for chat's saved spot (Unlock Mode's
-- Relative to Screen), nil while unset: the spot then keeps the form its
-- last save gave it.
local function ChatScreenChoice(conf)
    local p = conf and conf.chatScreenPoint
    return (p and POINT_FRAC[p]) and p or nil
end

-- The single anchor that places chat from the saved position, pixel-snapped
-- as every apply places it: point, relPoint, x, y (nil while unsaved).
local function ChatAnchorTarget(conf, cf1)
    local place = conf.chatPosition
    local px, py = place and place.x, place and place.y
    if not (place and place.point and px and py) then
        return nil
    end
    local relPoint = place.relPoint or place.point
    local PPa = CludesUI and CludesUI.PP
    if PPa then
        local es = cf1:GetEffectiveScale()
        -- Per axis: an offset that places the frame's middle (the centre, TOP
        -- and BOTTOM across, LEFT and RIGHT up) snaps against the dimension
        -- the rect carries, the saved size once there is one, so both edges
        -- land on pixels; an edge offset snaps to whole pixels.
        local frame = POINT_FRAC[place.point]
        local size = conf.chatSize
        if frame and frame[1] == 0.5 then
            px = PPa.SnapCenterForDim(px, size and size.w or cf1:GetWidth() or 0, es)
        else
            px = PPa.SnapForES(px, es)
        end
        if frame and frame[2] == 0.5 then
            py = PPa.SnapCenterForDim(py, size and size.h or cf1:GetHeight() or 0, es)
        else
            py = PPa.SnapForES(py, es)
        end
    end
    return place.point, relPoint, px, py
end

-------------------------------------------------------------------------------
--  Store lane: write chat's anchor (and size, once saved) into the active
--  layout whenever it would place chat elsewhere.
-------------------------------------------------------------------------------

-- The anchor the store gets: the target's single anchor in Edit Mode's units
-- (offsets at scale 1, as Edit Mode keeps them). Reused across passes.
local emAnchor = { relativeTo = "UIParent" }

-- Fills emAnchor from the saved position; false while unsaved.
local function EMChatFillAnchor(conf, cf1)
    local anchorPoint, relPoint, px, py = ChatAnchorTarget(conf, cf1)
    if not anchorPoint then
        return false
    end
    local scale = cf1:GetScale() or 1
    emAnchor.point, emAnchor.relativePoint = anchorPoint, relPoint
    emAnchor.offsetX, emAnchor.offsetY = px * scale, py * scale
    return true
end

-- The entry already places chat on emAnchor, its only anchor (within Edit
-- Mode's own anchor tolerance).
local function EMChatAnchorAgrees(sys)
    local ai = sys.anchorInfo
    return type(ai) == "table"
        and sys.anchorInfo2 == nil
        and ai.point == emAnchor.point
        and ai.relativeTo == emAnchor.relativeTo
        and ai.relativePoint == emAnchor.relativePoint
        and type(ai.offsetX) == "number"
        and type(ai.offsetY) == "number"
        and abs(ai.offsetX - emAnchor.offsetX) < 0.1
        and abs(ai.offsetY - emAnchor.offsetY) < 0.1
end

-- The entry already sizes chat w x h (no w: the size is not ours to keep).
local function EMChatSizeAgrees(sys, setEnum, wid, hgt)
    if not wid then
        return true
    end
    local sw, sh = EMChatReadSize(sys, setEnum)
    return sw ~= nil and abs(sw - wid) <= 1 and abs(sh - hgt) <= 1
end

-- One size row (added when the entry lacks it), noted for Uninstall CUI
-- first. pairID: the dimension's other row, which goes back with it.
local function EMChatSetRow(layout, sys, ident, value, pairID)
    local row = EditModeSetting(sys, ident)
    if not row then
        if type(sys.settings) ~= "table" then
            sys.settings = {}
        end
        sys.settings[#sys.settings + 1] = { setting = ident, value = value }
        return
    end
    CludesUI.NoteEditModeSetting(layout, sys, ident, row.value, value, nil, pairID)
    row.value = value
end

-- Writes emAnchor and, with w, the size into sys (chat's entry of layout),
-- each change noted for Uninstall CUI first.
local function EMChatWrite(layout, sys, setEnum, wid, hgt)
    if not EMChatAnchorAgrees(sys) then
        CludesUI.NoteEditModeAnchor(layout, sys, emAnchor)
        local ai = sys.anchorInfo
        if type(ai) ~= "table" then
            ai = {}
            sys.anchorInfo = ai
        end
        ai.point, ai.relativeTo, ai.relativePoint =
            emAnchor.point, emAnchor.relativeTo, emAnchor.relativePoint
        ai.offsetX, ai.offsetY = emAnchor.offsetX, emAnchor.offsetY
        sys.anchorInfo2 = nil
        sys.isInDefaultPosition = false
    end
    if not EMChatSizeAgrees(sys, setEnum, wid, hgt) then
        -- All four rows: Uninstall puts each dimension's pair back whole.
        wid, hgt = upper(0, floor(wid + 0.5)), upper(0, floor(hgt + 0.5))
        EMChatSetRow(layout, sys, setEnum.WidthHundreds, floor(wid / 100), setEnum.WidthTensAndOnes)
        EMChatSetRow(layout, sys, setEnum.WidthTensAndOnes, wid % 100, setEnum.WidthHundreds)
        EMChatSetRow(layout, sys, setEnum.HeightHundreds, floor(hgt / 100), setEnum.HeightTensAndOnes)
        EMChatSetRow(layout, sys, setEnum.HeightTensAndOnes, hgt % 100, setEnum.HeightHundreds)
    end
end

-- The last saved layout and target written this session: each is written
-- once at most, so a store that will not take a value can never loop
-- write -> apply -> write.
local emLast = {}

-- One store pass: when the active saved layout would place chat elsewhere,
-- write chat's anchor (and its size, once saved) into it. A preset is never
-- written.
function mod.EMChatSync()
    if InCombatLockdown() then
        return
    end
    local conf = CHAT.DB()
    local cf1 = _G.ChatFrame1
    if not (conf and cf1 and EMChatFillAnchor(conf, cf1)) then
        return
    end
    local blob, record, sysChat, setEnum, isPreset = EMChatResolve()
    if not blob or isPreset then
        return
    end
    local sys = EMChatFindSystem(record, sysChat)
    if not sys then
        return
    end
    local size = conf.chatSize
    local wid, hgt
    if size and size.w and size.h then
        wid, hgt = size.w, size.h
    end
    if EMChatAnchorAgrees(sys) and EMChatSizeAgrees(sys, setEnum, wid, hgt) then
        return
    end
    if
        emLast.name == record.layoutName
        and emLast.layoutType == record.layoutType
        and emLast.point == emAnchor.point
        and emLast.relPoint == emAnchor.relativePoint
        and emLast.x == emAnchor.offsetX
        and emLast.y == emAnchor.offsetY
        and emLast.w == wid
        and emLast.h == hgt
    then
        return
    end
    emLast.name, emLast.layoutType = record.layoutName, record.layoutType
    emLast.point, emLast.relPoint = emAnchor.point, emAnchor.relativePoint
    emLast.x, emLast.y, emLast.w, emLast.h = emAnchor.offsetX, emAnchor.offsetY, wid, hgt
    EMChatWrite(record, sys, setEnum, wid, hgt)
    if pcall(C_EditMode.SaveLayouts, blob) then
        mod._emChatWrote = true
    end
end

-- Unlock mode's Reset: chat's entry in the active saved layout goes back to
-- Edit Mode's default position and size (its own Reset To Default Position,
-- plus the size); the next settled sight captures that spot as ours.
function mod.EMChatResetStore()
    if InCombatLockdown() then
        return
    end
    local blob, record, sysChat, setEnum, isPreset = EMChatResolve()
    if not blob or isPreset then
        return
    end
    local sys = EMChatFindSystem(record, sysChat)
    local mgr = EditModePresetLayoutManager
    if not (sys and mgr and mgr.GetDefaultSystemAnchorInfo and mgr.GetDefaultSettingForSystem) then
        return
    end
    local okA, def = pcall(mgr.GetDefaultSystemAnchorInfo, mgr, sysChat)
    if not (okA and type(def) == "table") then
        return
    end
    CludesUI.NoteEditModeAnchor(record, sys, def)
    sys.anchorInfo = def
    sys.anchorInfo2 = nil
    sys.isInDefaultPosition = true
    local wH, wT = setEnum.WidthHundreds, setEnum.WidthTensAndOnes
    local hH, hT = setEnum.HeightHundreds, setEnum.HeightTensAndOnes
    local okW1, vW1 = pcall(mgr.GetDefaultSettingForSystem, mgr, sysChat, nil, wH)
    local okW2, vW2 = pcall(mgr.GetDefaultSettingForSystem, mgr, sysChat, nil, wT)
    local okH1, vH1 = pcall(mgr.GetDefaultSettingForSystem, mgr, sysChat, nil, hH)
    local okH2, vH2 = pcall(mgr.GetDefaultSettingForSystem, mgr, sysChat, nil, hT)
    if okW1 and okW2 and type(vW1) == "number" and type(vW2) == "number" then
        EMChatSetRow(record, sys, wH, vW1, wT)
        EMChatSetRow(record, sys, wT, vW2, wH)
    end
    if okH1 and okH2 and type(vH1) == "number" and type(vH2) == "number" then
        EMChatSetRow(record, sys, hH, vH1, hT)
        EMChatSetRow(record, sys, hT, vH2, hH)
    end
    emLast.name = nil
    if pcall(C_EditMode.SaveLayouts, blob) then
        mod._emChatWrote = true
    end
end

-- The apply passes' store pass: one per frame at most, outside the pass that
-- asked (never inside Edit Mode's apply), after combat, and not while a grip
-- drag, an unlock session or the first-install picker is open.
local RunChatStoreSync
RunChatStoreSync = function()
    mod._emSyncQueued = nil
    if mod._chatSizingActive or CludesUI._unlockActive or CludesUI._firstInstallPending then
        return
    end
    if InCombatLockdown() then
        CludesUI.CombatQueue.Defer("ChatEMStoreSync", RunChatStoreSync)
        return
    end
    mod.EMChatSync()
end
local function ScheduleChatStoreSync()
    if mod._emSyncQueued then
        return
    end
    mod._emSyncQueued = true
    C_Timer.After(0, RunChatStoreSync)
end

-------------------------------------------------------------------------------
--  Placement
-------------------------------------------------------------------------------

-- The anchors ApplyChatPosition places: one, or two while the saved size
-- rides a second corner. Reused across passes.
local chatTarget = { {}, {} }
local function SetChatTarget(index, anchorPoint, relPoint, posX, posY)
    local tbl = chatTarget[index]
    tbl.point, tbl.relPoint, tbl.x, tbl.y = anchorPoint, relPoint, posX, posY
end

-- The corner opposite each corner anchor, and the signs of the saved size
-- that reach it from there (y grows upward): a corner position's second
-- anchor, against the same point of UIParent.
local SIZE_CORNER = {
    BOTTOMLEFT = { "TOPRIGHT", 1, 1 },
    TOPLEFT = { "BOTTOMRIGHT", 1, -1 },
    TOPRIGHT = { "BOTTOMLEFT", -1, -1 },
    BOTTOMRIGHT = { "TOPLEFT", -1, 1 },
}

-- ChatFrame1 already carries exactly the first n target anchors (GetPoint
-- returns the anchor definitions, never a lagging rect), within Edit Mode's
-- own anchor tolerance. A secret read counts as a mismatch.
local function ChatAtTarget(cf1, n)
    local issecret = _G.issecretvalue
    local num = cf1:GetNumPoints()
    if (issecret and issecret(num)) or num ~= n then
        return false
    end
    for index = 1, n do
        local anchorPoint, relTo, relPoint, posX, posY = cf1:GetPoint(index)
        if
            issecret
            and (
                issecret(anchorPoint)
                or issecret(relTo)
                or issecret(relPoint)
                or issecret(posX)
                or issecret(posY)
            )
        then
            return false
        end
        if relTo ~= UIParent or type(posX) ~= "number" or type(posY) ~= "number" then
            return false
        end
        local hit = false
        for jdx = 1, n do
            local tbl = chatTarget[jdx]
            if
                tbl.point == anchorPoint
                and tbl.relPoint == relPoint
                and abs(tbl.x - posX) < 0.1
                and abs(tbl.y - posY) < 0.1
            then
                hit = true
            end
        end
        if not hit then
            return false
        end
    end
    return true
end

-- Deferred pass that rewrites a foreign-form saved position as BOTTOMLEFT once
-- the rect resolves (defined after ApplyChatPosition, which arms it).
local CanonicalizeChatPosition

local function PlaceChat()
    -- A grip resize is an engine-driven op on ChatFrame1; the op re-anchors
    -- the frame, Edit Mode's machinery reacts with ApplySystemAnchor, and
    -- the guard below would then re-apply the SAVED anchors every tick --
    -- a revert war that freezes the resize. Held off until release.
    if mod._chatSizingActive then
        return
    end
    local conf = CHAT.DB()
    if not conf or not conf.chatPosition then
        return
    end
    local place = conf.chatPosition
    local cf1 = _G.ChatFrame1
    if not cf1 then
        return
    end
    -- Corner positions only resolve with the clamp insets zeroed; assert
    -- before anchoring so the enforcement itself can never land clamped.
    EnsureChatClampInsets()
    -- Saved size rides as a SECOND corner anchor: a two-point rect is
    -- anchor-determined, so no code path ever calls SetSize on ChatFrame1
    -- (a synchronous SetSize dispatch would run the dock relayout tainted),
    -- the engine layout pass dispatches its OnSizeChanged SECURE, and any
    -- Blizzard SetSize is overridden by the anchors.
    -- Second-corner enforcement serves only while the Edit Mode store
    -- disagrees with the saved size (pre-migration, fresh imports, presets);
    -- once the store carries it, Blizzard's own apply owns the size and this
    -- stands down.
    local size = conf.chatSize
    local sizeLane = size and size.w and size.h and EMChatSizeDelta()
    local anchorPoint, relPoint, px, py = ChatAnchorTarget(conf, cf1)
    if not anchorPoint then
        return
    end
    local n = 1
    local frac = POINT_FRAC[anchorPoint]
    if sizeLane and frac and not SIZE_CORNER[anchorPoint] then
        -- Centre and edge-middle forms compose the rect around their point
        -- outright. A lone anchor there would resolve on the frame's explicit
        -- size for a tick, and the canonicalize below would read the corner
        -- of THAT rect -- landing the chat half the size delta away from
        -- where it was dropped.
        SetChatTarget(1, "TOPLEFT", relPoint, px - frac[1] * size.w, py + (1 - frac[2]) * size.h)
        SetChatTarget(2, "BOTTOMRIGHT", relPoint, px + (1 - frac[1]) * size.w, py - frac[2] * size.h)
        n = 2
    else
        SetChatTarget(1, anchorPoint, relPoint, px, py)
        -- Corner positions compose the size anchor at the opposite corner. A
        -- single-anchor apply would leave the rect on the frame's explicit
        -- (Edit Mode, stale) size until the deferred normalize below lands --
        -- a window where a late Edit Mode pass baked the old size in, and the
        -- normalize would save the corner of THAT rect. Any corner can arrive:
        -- an unlock mode nudge saves whichever anchor GetPoint lists first.
        local opp = sizeLane and SIZE_CORNER[anchorPoint]
        if opp then
            SetChatTarget(2, opp[1], relPoint, px + opp[2] * size.w, py + opp[3] * size.h)
            n = 2
        end
    end
    -- Compare-gated: once Edit Mode's own apply lands on our anchors (the
    -- store carries them), there is nothing to write -- unless the clamp
    -- insets were just put back (EnsureChatClampInsets above): a rect pinned
    -- under the other insets only lets go once the anchors are written again.
    if mod._chatReanchor or not ChatAtTarget(cf1, n) then
        mod._chatReanchor = nil
        ClearFramePoints(cf1)
        for index = 1, n do
            local tbl = chatTarget[index]
            SetFramePoint(cf1, tbl.point, UIParent, tbl.relPoint, tbl.x, tbl.y)
        end
    end
    local canonTo = ChatScreenChoice(conf) or (sizeLane and "BOTTOMLEFT")
    if canonTo and (anchorPoint ~= canonTo or relPoint ~= canonTo) and not mod._chatCanonPending then
        -- Canonicalize once the rect resolves to the form chat keeps: the
        -- player's Relative to Screen point, else BOTTOMLEFT while the size
        -- rides a second corner, so every later apply composes on the fast
        -- path. One pass pending at a time: every apply in between lands in
        -- the same pass.
        mod._chatCanonPending = true
        C_Timer.After(0, CanonicalizeChatPosition)
    end
    -- The visible stack follows numerically; sync it now rather than at the
    -- next event so drags and guard re-applies land in one motion.
    if CHAT.PositionChatPanelsNow then
        CHAT.PositionChatPanelsNow()
    end
    -- The sync above reads the rect the SetPoints just changed, and same-tick
    -- reads can lag the engine layout pass (the grip-save rule) -- the panel,
    -- the tab band anchored to it, and the strip's clip then disagree for a
    -- tick (ghost tabs clipped to slivers). One coalesced deferred re-sync
    -- lands panels-then-strip on the resolved rect for EVERY apply path.
    if not mod._chatPosResync then
        mod._chatPosResync = true
        C_Timer.After(0, function()
            mod._chatPosResync = nil
            if CHAT.PositionChatPanelsNow then
                CHAT.PositionChatPanelsNow()
            end
            if CHAT.TabsRefreshNow then
                CHAT.TabsRefreshNow()
            end
        end)
    end
    -- Keep the store on our rect once ownership has begun (the anchor guard
    -- is installed at the first settled sight).
    if CFD(cf1).anchorGuarded then
        ScheduleChatStoreSync()
    end
end
CanonicalizeChatPosition = function()
    mod._chatCanonPending = nil
    local cf1 = _G.ChatFrame1
    local cfg2 = CHAT.DB()
    if not cf1 or not cfg2 or not cfg2.chatPosition or mod._chatSizingActive then
        mod._chatCanonLaps = nil
        return
    end
    -- A rect pinned under other clamp insets is not where the anchors put it:
    -- never save that spot. Re-anchor and try again next tick, at most twice:
    -- Edit Mode re-seats the insets from its selection box on its own layout
    -- passes, so a lap that keeps finding them moved would otherwise run every
    -- frame forever. Stopping keeps the saved form, which every apply still
    -- places; the next apply from elsewhere tries again.
    EnsureChatClampInsets()
    if mod._chatReanchor then
        local laps = (mod._chatCanonLaps or 0) + 1
        if laps > 2 then
            mod._chatCanonLaps = nil
            return
        end
        mod._chatCanonLaps = laps
        PlaceChat()
        return
    end
    mod._chatCanonLaps = nil
    local l, b, region, t = cf1:GetLeft(), cf1:GetBottom(), cf1:GetRight(), cf1:GetTop()
    local issecret = _G.issecretvalue
    if
        not (l and b and region and t)
        or (issecret and (issecret(l) or issecret(b) or issecret(region) or issecret(t)))
    then
        return
    end
    -- The frame's point at its spot, measured from the same point of the
    -- screen (BOTTOMLEFT: the rect's own left and bottom).
    local target = ChatScreenChoice(cfg2) or "BOTTOMLEFT"
    local frame = POINT_FRAC[target]
    local sw, sh = ChatScreenSize(cf1)
    cfg2.chatPosition = {
        point = target,
        relPoint = target,
        x = l + frame[1] * (region - l - sw),
        y = b + frame[2] * (t - b - sh),
    }
    PlaceChat()
end

CHAT.ApplyChatPosition = PlaceChat
mod._EMChatSizeDelta = EMChatSizeDelta

-- Unlock Mode's Relative to Screen for chat (the cog): the point of the
-- screen chat's saved spot is measured from. Unset, it is the point the saved
-- spot uses. A pick only names it: the next apply (in a session, its close)
-- re-expresses the spot from it, where chat already stands.
function mod.GetChatScreenPoint()
    local conf = CHAT.DB()
    local p = ChatScreenChoice(conf)
    if p then
        return p
    end
    local place = conf and conf.chatPosition
    local rel = place and (place.relPoint or place.point)
    return (rel and POINT_FRAC[rel]) and rel or "BOTTOMLEFT"
end

function mod.SetChatScreenPoint(anchorPoint)
    local conf = CHAT.DB()
    if not (conf and POINT_FRAC[anchorPoint]) then
        return
    end
    conf.chatScreenPoint = anchorPoint
    if not CludesUI._unlockActive then
        PlaceChat()
    end
end

-- The left and bottom edges a saved spot puts a w x h chat at, in
-- ChatFrame1's units (nil for a point it does not know).
function mod.ChatSavedLeftBottom(place, wid, hgt, cf1)
    local fp, fr = POINT_FRAC[place.point], POINT_FRAC[place.relPoint or place.point]
    if not (fp and fr and place.x and place.y) then
        return nil
    end
    local sw, sh = ChatScreenSize(cf1)
    return fr[1] * sw + place.x - fp[1] * wid, fr[2] * sh + place.y - fp[2] * hgt
end

-- Re-assert after an Edit Mode layout apply in the SAME frame: a one-shot
-- OnUpdate on a frame of ours (hidden while idle) runs after this frame's
-- event handlers and before it renders, so Edit Mode's rect never shows. A
-- timer waits for the next frame, and that one frame at Edit Mode's spot is
-- the blink (it also moves Blizzard's link zones off our lines). A request
-- only shows the frame: no addon code runs inside Edit Mode's apply.
local chatReassert = CreateFrame("Frame")
chatReassert:Hide()
chatReassert:SetScript("OnUpdate", function(self)
    self:Hide()
    if mod._chatSizingActive or CludesUI._unlockActive then
        return
    end
    local conf = CHAT.DB()
    if conf and conf.chatPosition then
        PlaceChat()
    end
end)

-- Edit Mode's layout apply (login server-data arrival, layout switches) can
-- re-rect the main window through paths the ApplySystemAnchor guard never
-- sees, taking the last word over the settled-sight apply -- the frame sits
-- at Edit Mode's rect while the panel stack holds ours until an interaction
-- re-arms enforcement. Its own event is the precise edge: re-assert there,
-- gated on ownership having begun (anchor guard installed) so it can never
-- fire early.
do
    local emWatch = CreateFrame("Frame")
    emWatch:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    emWatch:SetScript("OnEvent", function()
        local conf = CHAT.DB()
        if not (conf and conf.chatPosition) then
            return
        end
        local cf1 = _G.ChatFrame1
        local d1 = cf1 and CFD(cf1)
        if not (d1 and d1.anchorGuarded) then
            return
        end
        chatReassert:Show()
    end)
end

-- Genesis capture: on the first settled sight with no saved position,
-- ChatFrame1's current (Edit-Mode-placed) rect becomes OUR saved position.
-- Pixel-identical takeover -- users see no change on update; from then on
-- chat position is an CUI unlock element.
-- The sidebar's footprint left of the chat panel under the current look: its
-- width, a Separate Sidebar's gap, less the stock column's seat overlap; 0
-- while it sits on the right or never shows.
local function GenesisFP(conf)
    if conf.sidebarRight or conf.sidebarVisibility == "never" then
        return 0
    end
    return min(
        100,
        upper(30, conf.sidebarWidth or (CHAT.SidebarWidthDefault and CHAT.SidebarWidthDefault() or 40))
    ) + ((conf.sidebarSeparate == true) and (conf.sidebarSeparateSpacing or 8) or 0) - (CHAT.SB_KIT and CHAT.SB_KIT.col.dx or 0)
end

local function CaptureChatPositionGenesis()
    local conf = CHAT.DB()
    if not conf then
        return
    end
    -- One-time ownership migration: positions saved before the Edit Mode
    -- era are stale (users repositioned via Edit Mode since; re-applying
    -- an ancient spot would visibly move their chat on update). Discard
    -- once so genesis captures the CURRENT placement.
    local stale = false
    if conf._chatPosOwnership ~= 1 then
        conf._chatPosOwnership = 1
        stale = conf.chatPosition ~= nil
        conf.chatPosition = nil
    end
    if conf.chatPosition then
        return
    end
    local cf1 = _G.ChatFrame1
    if not cf1 then
        return
    end
    local leftX, bottom = cf1:GetLeft(), cf1:GetBottom()
    if not (leftX and bottom) then
        return
    end
    -- Blizzard's chat spot leaves no room for our sidebar on its left, so the
    -- first capture moves chat right by the sidebar's footprint. Not for a
    -- position the migration above just dropped: that layout already had the
    -- sidebar. The footprint is kept (plain data) for GenesisSettle below.
    if not stale then
        local fp = GenesisFP(conf)
        leftX = leftX + fp / (cf1:GetScale() or 1)
        conf._chatGenesisFP, conf._chatGenesisX = fp, leftX
        mod._chatGenesisNow = true
    end
    conf.chatPosition = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = leftX, y = bottom }
end

-- A fresh install settles its look after that capture (the style picker, a
-- later session), and each look's sidebar has its own footprint: from the
-- next session on, every settled sight re-measures it and moves chat by the
-- difference while chat still sits where the capture put it (a drag ends
-- this), until no style choice is pending.
local function GenesisSettle()
    local conf = CHAT.DB()
    local old = conf and conf._chatGenesisFP
    if not old or mod._chatGenesisNow then
        return
    end
    local place, cf1 = conf.chatPosition, _G.ChatFrame1
    if
        not (
            place
            and cf1
            and place.point == "BOTTOMLEFT"
            and conf._chatGenesisX
            and place.x
            and abs(place.x - conf._chatGenesisX) < 0.5
        )
    then
        conf._chatGenesisFP, conf._chatGenesisX = nil, nil
        return
    end
    local nowTime = GenesisFP(conf)
    if nowTime ~= old then
        place.x = place.x + (nowTime - old) / (cf1:GetScale() or 1)
        conf._chatGenesisFP, conf._chatGenesisX = nowTime, place.x
    end
    if not (CludesUIDB and CludesUIDB.styleChoicePending) then
        conf._chatGenesisFP, conf._chatGenesisX = nil, nil
    end
end

-- Edit Mode override, the suite's action-bar anchor-guard pattern: post-hook
-- the system anchor apply and re-apply OURS from the one-shot re-assert
-- frame (same frame, outside Edit Mode's secure chain). One hook covers the
-- login layout apply, layout switches, spec changes and Edit Mode exit. ChatFrame1 is NEVER reparented and
-- its SetPoint is NEVER hooked -- both are recorded failure classes (Edit
-- Mode's UpdateSystemAnchorInfo assumes a UIParent child; a reparented
-- chat came back with no anchors at all).
local function InstallChatAnchorGuard()
    local cf1 = _G.ChatFrame1
    if not cf1 or not cf1.ApplySystemAnchor then
        return
    end
    local skinData = CFD(cf1)
    if skinData.anchorGuarded then
        return
    end
    skinData.anchorGuarded = true
    hooksecurefunc(cf1, "ApplySystemAnchor", function()
        local conf = CHAT.DB()
        if conf and conf.chatPosition then
            chatReassert:Show()
        end
    end)
    -- Edit Mode also sets the clamp insets from its selection box (32-60px
    -- past the window) on every layout apply and on entering Edit Mode,
    -- which applies no anchor; a chat near a screen edge is then pinned
    -- inward. The same re-assert puts our insets back and re-anchors.
    if cf1.UpdateClampOffsets then
        hooksecurefunc(cf1, "UpdateClampOffsets", function()
            local conf = CHAT.DB()
            if conf and conf.chatPosition then
                chatReassert:Show()
            end
        end)
    end
end

-- Kill Edit Mode's selection overlay for chat: the unit-frame treatment
-- adapted. Their Blizzard frames die by hidden reparent; cf1 must stay
-- live, and Edit Mode still drives its Selection child -- so the Selection
-- goes alpha-0 and mouse-dead IN PLACE (never reparented: a region its
-- owner still writes must stay in its tree). Chat can be neither
-- highlighted nor dragged in Edit Mode; asserted from the state sync since
-- Edit Mode rewrites the overlay across its sessions.
-- Edit Mode's resize handle on the main window (EditModeResizeButton, a
-- Button child Edit Mode shows on enter and hides on exit) gets the same
-- in-place treatment: sizing belongs to our grip, and a live handle here
-- would write Edit Mode's size store behind the size lane's back.
function CHAT.SuppressChatEditModeSelection()
    local cf1 = _G.ChatFrame1
    if not cf1 then
        return
    end
    CludesUI.SetEditModeChildInert(cf1.Selection, true)
    CludesUI.SetEditModeChildInert(cf1.EditModeResizeButton, true)
end
mod._CaptureChatPositionGenesis = CaptureChatPositionGenesis
mod._GenesisSettle = GenesisSettle
mod._InstallChatAnchorGuard = InstallChatAnchorGuard

-- Main chat size is applied as a second corner anchor inside
-- ApplyChatPosition (cfg.chatSize; anchor-determined rect, never SetSize).
-- Undocked windows stay Blizzard-sized. This stub remains for callers.
local function ApplyChatSize() end
CHAT.ApplyChatSize = ApplyChatSize

-- Main chat resize grip: our button, ANCHOR-driven sizing. Blizzard never
-- shows ChatFrame1's own resize button (Edit Mode owned main chat sizing,
-- and our position takeover suppressed Edit Mode), so this grip is the sole
-- resize surface. HARD CONSTRAINTS, both field-proven:
--   - Never SetSize ChatFrame1 in any form: its OnSizeChanged is wired to
--     FCFDock_OnPrimarySizeChanged, which writes dock.isDirty/leftTab AND
--     installs the dock OnUpdate script; a synchronous insecure dispatch
--     taints the dock slots the secure whisper temp-window chain reads
--     (the recorded UpdateHeader secret-rect detonation class).
--   - StartSizing is engine-VETOED on the Edit-Mode-managed main window
--     (probed: rect identical before/after with the op "running"); the
--     docked branch in Blizzard's ResizeButton XML is legacy-dead.
-- The lane that satisfies both: pin TOPLEFT and drive the BOTTOMRIGHT
-- corner anchor from the cursor. A two-point rect is anchor-determined;
-- the engine layout pass recomputes it and dispatches OnSizeChanged as a
-- fresh SECURE execution (Blizzard's own dock relayout defers its work one
-- frame for exactly this timing). Persistence: cfg.chatSize, applied as
-- the second corner anchor by ApplyChatPosition -- Blizzard's saved-
-- dimensions restore explicitly skips the main window.
local function BuildMainChatResizeGrip(castFrame)
    local skinData = CFD(castFrame)
    if skinData.resizeGrip or not skinData.bg then
        return
    end
    local grip = CreateFrame("Button", nil, skinData.bg)
    skinData.resizeGrip = grip
    grip:SetSize(18, 18)
    -- Anchored to the chat frame like the undocked buttons, so the icon
    -- hugs the true resize corner regardless of panel insets; nudged out
    -- past the frame edge so it sits in the panel's corner, not the text's.
    grip:SetPoint("BOTTOMRIGHT", castFrame, "BOTTOMRIGHT", 4, -3)
    grip:SetFrameStrata("HIGH")
    local texture = grip:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\resize_element.png")
    texture:SetDesaturated(true)
    texture:SetVertexColor(1, 1, 1)
    grip:SetAlpha(0.4)

    -- Damage-meters drag mechanics, anchor-driven: per tick the TOPLEFT stays
    -- pinned and the BOTTOMRIGHT corner anchor follows the cursor (shift =
    -- axis lock, min sizes, screen-edge caps). The rect is anchor-determined,
    -- so the engine layout pass recomputes it and ChatFrame1's OnSizeChanged
    -- (the dock relayout) dispatches SECURE. StartSizing is NOT usable here
    -- (engine-vetoed on the Edit-Mode-managed main window; field-probed) and
    -- SetSize is BANNED (synchronous tainted dispatch). No InProtectedInstance
    -- gate: /cuidev makes it return true and would dead-stop the grip; all
    -- rect reads below are secret-gated instead.
    local MIN_W, MIN_H = 220, 100
    local sizing = false
    local startX, startY, startW, startH, anchorLeft, anchorTop
    local curW, curH, axis, shiftWas
    local ticker = CreateFrame("Frame")
    ticker:Hide()
    ticker:SetScript("OnUpdate", function()
        if not sizing then
            return
        end
        local curX, curY = GetCursorPosition()
        local es = castFrame:GetEffectiveScale()
        local dx = curX / es - startX
        local dy = startY - curY / es
        local shiftDown = IsShiftKeyDown()
        local newW, newH
        if shiftDown then
            if not shiftWas then
                axis = (math.abs(dx) >= math.abs(dy)) and "w" or "h"
            end
            if axis == "w" then
                newW, newH = math.max(MIN_W, startW + dx), startH
            else
                newW, newH = startW, math.max(MIN_H, startH + dy)
            end
        else
            axis = nil
            newW = math.max(MIN_W, startW + dx)
            newH = math.max(MIN_H, startH + dy)
        end
        -- Cap so the frame can't extend past screen edges from the pinned corner.
        local screenR = UIParent:GetRight() or 0
        local screenB = UIParent:GetBottom() or 0
        if screenR - anchorLeft > MIN_W then
            newW = math.min(newW, screenR - anchorLeft)
        end
        if anchorTop - screenB > MIN_H then
            newH = math.min(newH, anchorTop - screenB)
        end
        curW, curH = newW, newH
        -- Full re-anchor per tick: a mid-drag Edit Mode anchor write would
        -- otherwise leave a third point and overconstrain the rect.
        ClearFramePoints(castFrame)
        SetFramePoint(castFrame, "TOPLEFT", UIParent, "BOTTOMLEFT", anchorLeft, anchorTop)
        SetFramePoint(castFrame, "BOTTOMRIGHT", UIParent, "BOTTOMLEFT", anchorLeft + newW, anchorTop - newH)
        shiftWas = shiftDown
        -- The visible stack is positioned numerically; sync per tick so the
        -- panels ride the drag with zero lag.
        if CHAT.PositionChatPanelsNow then
            CHAT.PositionChatPanelsNow()
        end
    end)

    grip:SetScript("OnMouseDown", function(_, btnFrame)
        if btnFrame ~= "LeftButton" then
            return
        end
        -- Belt behind the combat hide: no drag may start in lockdown even
        -- if a hide edge races the click.
        if InCombatLockdown() then
            return
        end
        local issecret = _G.issecretvalue
        local leftX, topY = castFrame:GetLeft(), castFrame:GetTop()
        local wid, hgt = castFrame:GetWidth(), castFrame:GetHeight()
        if not (leftX and topY and wid and hgt) then
            return
        end
        if issecret and (issecret(leftX) or issecret(topY) or issecret(wid) or issecret(hgt)) then
            return
        end
        -- Hold the position enforcement for the whole drag: our per-tick
        -- corner anchors rule until release.
        mod._chatSizingActive = true
        ClearFramePoints(castFrame)
        SetFramePoint(castFrame, "TOPLEFT", UIParent, "BOTTOMLEFT", leftX, topY)
        SetFramePoint(castFrame, "BOTTOMRIGHT", UIParent, "BOTTOMLEFT", leftX + wid, topY - hgt)
        anchorLeft, anchorTop = leftX, topY
        local curX, curY = GetCursorPosition()
        local es = castFrame:GetEffectiveScale()
        startX, startY = curX / es, curY / es
        startW, startH = wid, hgt
        curW, curH = wid, hgt
        shiftWas = false
        sizing = true
        ticker:Show()
        -- Held for the whole drag: the cursor can slide off the grip mid-
        -- drag, and its OnLeave alone would disarm the geometry follower
        -- while the frame is still resizing.
        if CHAT.FollowArm then
            CHAT.FollowArm()
        end
    end)
    grip:SetScript("OnMouseUp", function(_, btnFrame)
        if btnFrame ~= "LeftButton" or not sizing then
            return
        end
        sizing = false
        ticker:Hide()
        mod._chatSizingActive = nil
        if CHAT.FollowRelease then
            CHAT.FollowRelease()
        end
        -- Save from the drag's own numbers (never frame reads: the rect
        -- resolves in the engine layout pass and can lag the final tick).
        -- Persistence is OUR DB key -- Blizzard's saved-dimensions restore
        -- explicitly skips the main window ("controlled via edit mode").
        local conf = CHAT.DB()
        if conf and curW and curH then
            local wid = math.floor(curW + 0.5)
            local hgt = math.floor(curH + 0.5)
            conf.chatSize = { w = wid, h = hgt }
            conf.chatPosition = {
                point = "BOTTOMLEFT",
                relPoint = "BOTTOMLEFT",
                x = anchorLeft,
                y = anchorTop - hgt,
            }
        end
        -- The apply also hands the rect to the Edit Mode store (its next-frame
        -- store pass; a quiet no-op when the store already agrees).
        if CHAT.ApplyChatPosition then
            CHAT.ApplyChatPosition()
        end
        if CHAT.TabsRefreshNow then
            CHAT.TabsRefreshNow()
        end
    end)
    -- Lock toggled or panel hidden mid-drag: end the drag and release the
    -- position hold, or the guard would stay suspended forever.
    grip:SetScript("OnHide", function()
        if sizing then
            sizing = false
            ticker:Hide()
            mod._chatSizingActive = nil
            if CHAT.FollowRelease then
                CHAT.FollowRelease()
            end
        end
    end)
    -- Undocked-button hover parity; a resize drag starts and stays on this
    -- grip, so the geometry follower arms while the mouse is here and the
    -- panels ride the drag live.
    grip:SetScript("OnEnter", function(self)
        self:SetAlpha(0.75)
        if CHAT.FollowArm then
            CHAT.FollowArm()
        end
    end)
    grip:SetScript("OnLeave", function(self)
        self:SetAlpha(0.4)
        if CHAT.FollowRelease then
            CHAT.FollowRelease()
        end
    end)
    -- Combat gate: resizing is disabled in combat, matching Edit Mode's own
    -- posture. Both edges recompute through the lock applier (the single
    -- shown-state authority), so the combat hide can never fight the lock
    -- setting; built once with the grip (idempotency guard above).
    local combatGate = CreateFrame("Frame")
    combatGate:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatGate:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatGate:SetScript("OnEvent", function()
        if CHAT.ApplyLockChatSize then
            CHAT.ApplyLockChatSize()
        end
    end)
end
mod._BuildMainChatResizeGrip = BuildMainChatResizeGrip

-- Unlock-mode placements of ChatFrame1 (the Chat mover's drag start, every
-- drag tick, arrow/cog nudges) collapse it to ONE anchor point: the mover
-- treats every element as explicitly sized. The main window's size rides a
-- second corner anchor instead (SetSize on ChatFrame1 is banned -- see the
-- grip above), so a one-point frame falls back to its explicit size, which
-- is whatever Edit Mode's last apply set, not ours. Called from the
-- element's onLiveMove after each placement: re-add the opposite corner
-- from the anchor DEFINITION (GetPoint returns the SetPoint arguments, never
-- a lagging rect) so the frame keeps its size through the whole session.
-- The placed anchor can be any corner, edge middle or the centre: a nudge
-- re-places whichever anchor GetPoint lists first, the size corner included.
-- Idempotent -- a frame already carrying two points is left alone.
local function KeepMainChatSizeCorner()
    local conf = CHAT.DB()
    local size = conf and conf.chatSize
    if not (size and size.w and size.h) then
        return
    end
    local cf1 = _G.ChatFrame1
    if not cf1 or cf1:GetNumPoints() ~= 1 then
        return
    end
    local anchorPoint, relTo, relPoint, posX, posY = cf1:GetPoint(1)
    if relTo ~= UIParent then
        return
    end
    local issecret = _G.issecretvalue
    if issecret and (issecret(posX) or issecret(posY)) then
        return
    end
    if type(posX) ~= "number" or type(posY) ~= "number" then
        return
    end
    relPoint = relPoint or anchorPoint
    local wid, hgt = size.w, size.h
    local opp = SIZE_CORNER[anchorPoint]
    local frac = POINT_FRAC[anchorPoint]
    if opp then
        SetFramePoint(cf1, opp[1], UIParent, relPoint, posX + opp[2] * wid, posY + opp[3] * hgt)
    elseif frac then
        ClearFramePoints(cf1)
        SetFramePoint(cf1, "TOPLEFT", UIParent, relPoint, posX - frac[1] * wid, posY + (1 - frac[2]) * hgt)
        SetFramePoint(
            cf1,
            "BOTTOMRIGHT",
            UIParent,
            relPoint,
            posX + (1 - frac[1]) * wid,
            posY - frac[2] * hgt
        )
    end
end
mod._KeepMainChatSizeCorner = KeepMainChatSizeCorner

-- Lock Main Chat Size: hides OUR grip (main chat's sole resize surface).
-- Blizzard's ChatFrame1ResizeButton stays permanently dead -- alpha + mouse
-- only, never isLocked/FCF_SetLocked (the dock-list/isLocked poison class).
function CHAT.ApplyLockChatSize()
    local conf = CHAT.DB()
    local locked = conf and conf.lockChatSize == true
    local button = _G.ChatFrame1ResizeButton
    if button then
        button:SetAlpha(0)
        button:EnableMouse(false)
    end
    local cf1 = _G.ChatFrame1
    local grip = cf1 and CFD(cf1).resizeGrip
    if grip then
        -- Hidden in combat too: Edit Mode itself is combat-disabled, and a
        -- mid-combat resize could hit protected chat frames (the whisper-
        -- window lockdown class). The grip's OnHide ends any drag that was
        -- live when combat started; the regen listener in the grip build
        -- recomputes this on both combat edges.
        grip:SetShown(not locked and not InCombatLockdown())
    end
end

Inner.broken = false
