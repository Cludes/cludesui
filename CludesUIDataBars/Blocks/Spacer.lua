if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\Spacer.lua
-- Spacer block factory.

local ADDON_NAME, mod = ...
local K = mod.BlockKit

local InstKey = K.InstKey

-------------------------------------------------------------------------------
--  SPACER (transparent block; the slot's optional bg tint still applies)
-------------------------------------------------------------------------------
mod.BlockFactories.spacer = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)
    function instance:Refresh() end
    function instance:Enable() end
    function instance:Disable() end
    function instance:Destroy()
        self._dead = true
    end
    function instance:GetAutoLength()
        return 0
    end
    return instance
end
