if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidLead_Options.lua
--  The Raid Lead page of the CludesUI settings panel: the setup manager's
--  buttons. Each one runs the same code as its /raidlead command.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIRaidLead"
local ns = CludesUI._ModuleNS[ADDON_NAME]
if not ns then return end

local PAGE = "Setup"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not CludesUI or not CludesUI.RegisterModule then return end

    local function Run(cmd)
        return function() if ns.Command then ns.Command(cmd) end end
    end

    local function BuildPage(_, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h

        CludesUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "RAID GROUPS", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Sort by Role", buttonText = "Sort", width = 90,
              tooltip = "Tanks, melee, ranged, then healers, filling group 1 upward. Raid leader or assistant, out of combat.",
              onClick = Run("roles") },
            { type = "labeledButton", text = "Split Into Two Halves", buttonText = "Split", width = 90,
              tooltip = "Two balanced halves for split runs. Each kind is dealt out in turn, so both sides get the same mix.",
              onClick = Run("split") }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Put Everyone Back", buttonText = "Undo", width = 90,
              tooltip = "Back to how the groups were before the last sort or split.",
              onClick = Run("undo") },
            { type = "labeledButton", text = "Stop a Sort", buttonText = "Stop", width = 90,
              tooltip = "Stops a sort that is under way. Players already moved stay where they are.",
              onClick = Run("stop") }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "label", text = "Melee and ranged are told apart by class, which is a guess for Druids, Shamans and Hunters. Results print in chat." },
            { type = "label", text = "" }
        );  y = y - h

        return math.abs(y)
    end

    CludesUI:RegisterModule(ADDON_NAME, {
        title       = "Raid Lead",
        description = "Tools for raid leaders: sort the raid by role or split it in two.",
        pages       = { PAGE },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE then return BuildPage(pageName, parent, yOffset) end
        end,
    })
end)
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
