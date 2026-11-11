if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_PartyMode.lua
--
--  Party Mode (the full-screen spotlight show, the spinning frames and the
--  AFK screen) was removed from CludesUI. Something like it may come back
--  later as CludesUI's own feature, built from scratch.
--
--  Action Bars, Info Bar, Raid Frames, Resource Bars and Unit Frames still
--  ask this file for a "spin" engine when they load. They get one that does
--  nothing, so none of them needs to change.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI
if not CludesUI then return end

local function Nothing() end

--- Used to build a spin engine for a set of frames and return its refresh
--- function. Returns a refresh that does nothing.
function CludesUI.PartySpin_Create()
    return Nothing
end
