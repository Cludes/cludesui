if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Blocks\Spacer.lua - Info Bar block: empty space.
--
--  Draws nothing and claims no length of its own; the bar gives it whatever
--  room its slot settings ask for, and the slot's background tint (if any)
--  still shows.
-------------------------------------------------------------------------------
local _, mod = ...
local K = mod.BlockKit

local function Nothing() end

mod.BlockFactories.spacer = function(blockCfg, slot, contentFrame, barCtx)
    return {
        cfg = blockCfg,
        slot = slot,
        content = contentFrame,
        ctx = barCtx,
        key = K.InstKey(barCtx, blockCfg),
        Refresh = Nothing,
        Enable = Nothing,
        Disable = Nothing,
        Destroy = function(self) self._dead = true end,
        GetAutoLength = function() return 0 end,
    }
end
