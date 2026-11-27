-- "/cui help" (CludesUI.lua): the main commands, only those registered.
local CUI = rawget(_G, "CludesUI")
HARNESS_ADVANCE(0.5)
local lines = {}
local print0 = CUI.Print
CUI.Print = function(msg) lines[#lines + 1] = (tostring(msg):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
SlashCmdList.CUIOPTIONS("help")
CUI.Print = print0
for _, line in ipairs(lines) do OUT:write("== " .. line .. "\n") end
