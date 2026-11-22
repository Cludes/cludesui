if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CludesUI Shared Ticker
--
--  Self-disarming OnUpdate drivers: a driver frame only exists-as-running
--  while at least one subscriber is registered, so an idle UI runs no
--  per-frame code at all.
--
--  ATTRIBUTION (probe-verified 2026-07-26): the engine bills a script
--  handler's ENTIRE call tree to the addon whose execution context called
--  CreateFrame for the frame carrying the handler. The handler closure's
--  origin does not matter; who called SetScript does not matter; only the
--  frame's birth context matters -- and that context is inherited from the
--  current engine entry point (taint-style), NOT from the file the code
--  lives in. OnInitialize/OnEnable run under the parent's lifecycle
--  dispatch, so frames created there are billed to the PARENT forever.
--
--  Because of that rule there are two ways to use this module:
--
--    * CludesUI.Tick.Add/Remove -- the shared driver. Its frame is
--      created in this (parent) file, so ALL subscriber work is billed to
--      the parent addon. Fine for parent-owned work only.
--
--    * CludesUI.Tick.NewDriver(frame) -- per-addon driver. The caller
--      passes a frame it created in its OWN MAIN CHUNK (file scope), which
--      stamps the frame to that addon; every subscriber tick then bills the
--      subscribing addon. The driver logic living here in parent code is
--      irrelevant to attribution -- only the frame's birth context counts.
--
--  Usage:
--      -- child file scope:
--      ns.Drv = CludesUI.Tick.NewDriver(CreateFrame("Frame"))
--      -- anywhere:
--      ns.Drv.Add("erb_cast", function(dt) ... end)
--      ns.Drv.Remove("erb_cast")
--
--  Contract (identical for the shared driver and per-addon drivers):
--    * Add is idempotent. Calling it again with the same key replaces the
--      function and does not duplicate the entry, so an event handler can arm
--      unconditionally without first checking whether it is already armed.
--      That is deliberate: a missed re-arm freezes a bar, so callers should
--      always arm rather than trying to be clever about whether it is needed.
--    * A subscriber MUST remove itself once its work has settled (animation
--      reached its target, cast ended, cooldown finished). Removing from
--      inside your own tick is safe and is the normal way to do it.
--    * Remove on an unregistered key is a no-op, so pairing every start with
--      a stop is always safe.
--    * dt is real elapsed time since the previous dispatch, so animation
--      speed matches a per-frame OnUpdate exactly.
--
--  Note: CludesUI_Glows.lua deliberately keeps its own private driver. It
--  already implements this same arm/disarm discipline and is already free
--  when idle, so there is nothing to gain by routing it through here.
-------------------------------------------------------------------------------

local Tick = {}
CUI.Tick = Tick

-- Build a driver instance around the given frame. The frame's creating context is what
-- the engine bills, so callers wanting per-addon attribution MUST create the frame in
-- their own main chunk and pass it in. The nil fallback creates a parent-stamped frame
-- here: everything still works, but the work is billed to the parent.
local function NewDriver(frame)
    if not frame then frame = CreateFrame("Frame") end
    local keys = {} -- dense array of keys
    local ticks = {} -- parallel array of tick functions
    local slotOf = {} -- key -> position in reg
    local count = 0
    local driver = {}

    frame:Hide()
    frame:SetScript("OnUpdate", function(self, elapsed)
        -- Walk the dense array by index. A subscriber may remove itself (or another
        -- subscriber) from inside its own tick, which swap-removes and shrinks count,
        -- so re-read count every step and re-test the current slot when it was swapped
        -- rather than advancing past the entry that moved into it.
        local i = 1
        while i <= count do
            local key = keys[i]
            local fn = ticks[i]
            if fn then fn(elapsed) end
            if keys[i] == key then i = i + 1 end
        end
        if count == 0 then self:Hide() end
    end)

    -- Register (or replace) the tick function for a key. Arms the driver on
    -- the 0 -> 1 transition.
    function driver.Add(key, fn)
        if not key or type(fn) ~= "function" then return end
        local i = slotOf[key]
        if i then
            ticks[i] = fn
            return
        end
        count = count + 1
        keys[count] = key
        ticks[count] = fn
        slotOf[key] = count
        if count == 1 then frame:Show() end
    end

    -- Unregister a key. Swap-removes so churn stays O(1). Hides the driver
    -- once the last subscriber leaves, which is what makes idle free.
    function driver.Remove(key)
        local i = slotOf[key]
        if not i then return end
        local lastKey = keys[count]
        keys[i] = lastKey
        ticks[i] = ticks[count]
        slotOf[lastKey] = i
        keys[count] = nil
        ticks[count] = nil
        count = count - 1
        slotOf[key] = nil
        if count == 0 then frame:Hide() end
    end

    function driver.Has(key) return slotOf[key] ~= nil end

    -- Number of live subscribers. Zero means no per-frame code is running.
    function driver.Count() return count end

    return driver
end

Tick.NewDriver = NewDriver

-- Fixed-rate ticker without per-frame dispatch: a looping Animation fires
-- OnLoop at the configured interval and the C engine sleeps between fires,
-- so subscribing costs zero Lua at frame rate. Use for work that is
-- genuinely time-based (drains, recharges, hash motion); value fills should
-- be event-driven with an eased SetValue instead and need no ticker at all.
--
-- fn returns truthy to keep ticking; falsy stops the loop (self-disarm).
-- Start() on a playing ticker is one IsPlaying check, so arming can stay
-- indiscriminate. As with NewDriver, pass a frame created in the SUBSCRIBING
-- addon's main chunk so the engine bills that addon.
function Tick.NewAnimTicker(frame, fn, interval)
    if not frame then frame = CreateFrame("Frame") end
    local ag = frame:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local anim = ag:CreateAnimation("Animation")
    anim:SetDuration(interval or 0.05)
    local tbl = {}
    ag:SetScript("OnLoop", function()
        if not fn() then ag:Stop() end
    end)
    function tbl.Start(newInterval)
        if not ag:IsPlaying() then
            if newInterval then anim:SetDuration(newInterval) end
            ag:Play()
        end
    end
    function tbl.Stop() ag:Stop() end
    function tbl.IsPlaying() return ag:IsPlaying() end
    return tbl
end

-- Combat deferral queue: "run once after combat ends" without one event frame per
-- call site. Pass a frame created in the CALLER's main chunk (same attribution rule
-- as NewDriver). Defer(key, fn) is idempotent per key: a pending key keeps its
-- position and gets the new fn. Drains FIFO on PLAYER_REGEN_ENABLED; the set is
-- swapped out first, so an fn may Defer again (next drain), and each fn is
-- error-isolated. The event is registered only while something is pending, so idle
-- is free. Callers keep their own InCombatLockdown() gate: a Defer made out of combat
-- waits for the NEXT combat end. There is no cancel, and queues drain in no set order
-- relative to each other, so a queued fn must re-read live state when it runs. Each
-- child uses its own ns queue; CludesUI.CombatQueue is for the parent's files.
local function QueueErrorHandler(err) return geterrorhandler()(err) end

function CUI.NewCombatQueue(frame)
    if not frame then frame = CreateFrame("Frame") end
    local pending, slotOf, count = {}, {}, 0
    local q = {}

    frame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local runFns, n = pending, count
        pending, slotOf, count = {}, {}, 0
        for i = 1, n do
            xpcall(runFns[i], QueueErrorHandler)
        end
    end)

    function q.Defer(key, fn)
        if not key or type(fn) ~= "function" then return end
        local i = slotOf[key]
        if i then
            pending[i] = fn
            return
        end
        count = count + 1
        pending[count] = fn
        slotOf[key] = count
        if count == 1 then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    end

    function q.Has(key) return slotOf[key] ~= nil end

    return q
end

-- The core's own queue. CludesUI_Startup.lua and CludesUI.lua load before
-- this file, so they read it at the call, never as a load-time upvalue.
CUI.CombatQueue = CUI.NewCombatQueue(CreateFrame("Frame"))

-- The shared driver: frame created here in the parent, so subscriber work is
-- billed to the parent addon. Parent-owned subscribers only; children should
-- carry their own NewDriver(frame) with a file-scope-created frame.
local shared = NewDriver(CreateFrame("Frame"))
Tick.Add = shared.Add
Tick.Remove = shared.Remove
Tick.Has = shared.Has
Tick.Count = shared.Count
