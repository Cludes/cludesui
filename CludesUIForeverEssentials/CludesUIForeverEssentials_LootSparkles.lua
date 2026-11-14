if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_LootSparkles.lua  (WoW Forever only)
--  Loot Sparkles: keeps the game's sparkle on lootable quest items, so you
--  never walk past one. The game draws it while the hidden setting
--  outlineModeShowLootEffectWhenDisabled is 1, and a graphics preset sets it
--  back to 0. This turns it on at login, and again a second after a change
--  to the graphics quality (or to the setting itself) resets it. Your
--  outline mode is left alone. In combat it waits for the fight to end.
--
--  Turning it off writes 0, but the game keeps drawing sparkles it has
--  started until it restarts (a /reload is not enough).
-------------------------------------------------------------------------------
local _, module = ...

local CVAR = "outlineModeShowLootEffectWhenDisabled"
local WATCHED = { graphicsquality = true, raidgraphicsquality = true, [CVAR:lower()] = true }

-- On by default: it only keeps a game sparkle visible.
local F = module.Feature("lootSparkles", { enabled = true })
local Enabled = F.Enabled

local applying, pending = false, false
local wasOn = false

local function Write(value)
    local current = C_CVar.GetCVar(CVAR)
    if current == nil or current == value then
        return
    end -- not on this client, or already right
    applying = true
    pcall(C_CVar.SetCVar, CVAR, value)
    applying = false
end

local function Ensure()
    if not Enabled() then
        return
    end
    if InCombatLockdown() then
        pending = true
        return
    end
    Write("1")
    wasOn = true
end

local timer
local function EnsureSoon(delay)
    if timer then
        timer:Cancel()
    end
    timer = C_Timer.NewTimer(delay, function()
        timer = nil
        Ensure()
    end)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then
            pending = false
            Ensure()
        end
    elseif event == "CVAR_UPDATE" then
        if not applying and type(name) == "string" and WATCHED[name:lower()] then
            EnsureSoon(1)
        end
    end
end)

local function Apply()
    if Enabled() then
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        pcall(ev.RegisterEvent, ev, "CVAR_UPDATE")
        Ensure()
        EnsureSoon(5) -- the client can settle its graphics settings after login
    else
        ev:UnregisterAllEvents()
        -- Only a switch from on: a login with it off leaves the setting alone.
        if wasOn or (F.Read().switchedOff and C_CVar.GetCVar(CVAR) == "1") then
            wasOn = false
            F.Cfg().switchedOff = nil
            if not InCombatLockdown() then
                Write("0")
            end
            CludesUI.Print(
                "|cff4cc9f0Loot Sparkles:|r off. Sparkles already showing stay until you restart the game; /reload is not enough."
            )
        end
    end
end

-- The options toggle marks a switch to off, so the setting is written back to
-- 0 even when it was turned on in an earlier session.
local function SetEnabled(v)
    F.Cfg().enabled = v and true or false
    F.Cfg().switchedOff = (not v) or nil
    Apply()
end

CludesUI._LootSparkles = { Get = F.Get, Cfg = F.Cfg, Apply = Apply, SetEnabled = SetEnabled }

F.Start(Apply)
