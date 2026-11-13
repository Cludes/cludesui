if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_PvP_Options.lua
--  Forever Tools > PvP: enemy detection, Kill on Sight, sharing and extras.
-------------------------------------------------------------------------------
if not CludesUI._ModuleNS["CludesUIForeverEssentials"] then return end

function _G._CUI_BuildForeverPvPPage(_, parent, yOffset)
    local P = CludesUI._PvP
    if not P then return 0 end
    local W = CludesUI.Widgets
    local y = yOffset
    local _, h
    local cfg = P.Cfg()
    local function Off() return not P.Get("enabled") end
    local function Tog(key, text, tip, off)
        return { type = "toggle", text = text, tooltip = tip, disabled = off,
                 getValue = function() return P.Get(key) end,
                 setValue = function(v) cfg[key] = v and true or false; P.Apply() end }
    end

    CludesUI:ClearContentHeader()

    _, h = W:SectionHeader(parent, "ENEMY PLAYERS", y);  y = y - h
    _, h = W:DualRow(parent, y,
        Tog("enabled", "Detect Enemy Players",
            "Lists enemy players around you, from their nameplates, your target, focus and mouseover. Turn enemy nameplates on (Ctrl+V) to see the most. Off in dungeons, raids and sanctuaries."),
        Tog("autoShow", "Show the List When One Is Seen", "The list opens on Nearby when a new enemy is seen. It cannot open during combat.", Off)
    );  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "labeledButton", text = "Enemy List", buttonText = "Open", width = 90,
          tooltip = "Nearby, Last Hour, Kill on Sight and Ignore lists. Click a name to target it. /cpvp opens it too.",
          onClick = function() P.Show() end },
        { type = "labeledButton", text = "Statistics", buttonText = "Open", width = 90,
          tooltip = "Every enemy you have met, searchable, with your wins and losses. /cpvp stats.",
          onClick = function() P.Stats() end }
    );  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Remove When Unseen For", min = 30, max = 300, step = 30, isPercent = false, disabled = Off,
          tooltip = "Seconds before an enemy who has not been seen leaves the Nearby list.",
          getValue = function() return P.Get("removeAfter") end,
          setValue = function(v) cfg.removeAfter = math.floor(v + 0.5) end },
        { type = "slider", text = "Rows Shown", min = 5, max = 25, step = 1, isPercent = false, disabled = Off,
          getValue = function() return P.Get("rows") end,
          setValue = function(v) cfg.rows = math.floor(v + 0.5) end }
    );  y = y - h
    _, h = W:DualRow(parent, y,
        Tog("battlegrounds", "Also in Battlegrounds", nil, Off),
        { type = "label", text = "" }
    );  y = y - h

    _, h = W:SectionHeader(parent, "ALERTS", y);  y = y - h
    _, h = W:DualRow(parent, y,
        Tog("sound", "Alert Sound", "A sound when a new enemy is seen, and an alarm for Kill on Sight and stealth.", Off),
        Tog("stealthWarn", "Stealth Warning", "A warning when an enemy you can see goes into Stealth or Prowl.", Off)
    );  y = y - h
    _, h = W:DualRow(parent, y,
        Tog("kosWarn", "Kill on Sight Warning", nil, Off),
        Tog("kosGuildWarn", "Warn for Their Guild", "Also a warning when someone from a Kill on Sight player's guild is seen.", Off)
    );  y = y - h
    _, h = W:DualRow(parent, y,
        Tog("announceKoS", "Tell My Group About Kill on Sight", "Posts in party or raid chat when a Kill on Sight enemy is seen.", Off),
        { type = "label", text = "" }
    );  y = y - h

    _, h = W:SectionHeader(parent, "SHARING AND EXTRAS", y);  y = y - h
    _, h = W:DualRow(parent, y,
        Tog("share", "Share My Sightings", "Sends the enemies you see to your party, raid and guild. Players running CludesUI or Spy in the same zone get them.", Off),
        Tog("useShared", "Use Their Sightings", "Adds enemies others in your group and guild have seen in your zone.", Off)
    );  y = y - h
    _, h = W:DualRow(parent, y,
        Tog("kosButton", "Kill on Sight Button", "A KoS button above an enemy target's frame: click to add or remove them, right-click for more.", Off),
        Tog("minimapTip", "Minimap Enemy Details", "With humanoid tracking, the minimap tooltip shows the level and class of enemies you know.", Off)
    );  y = y - h

    _, h = W:SectionHeader(parent, "WATCH LIST, COMBAT MAP AND ZONES", y);  y = y - h
    _, h = W:DualRow(parent, y,
        Tog("watchWarn", "Warn When a Watched Player Is Near", "Watch players of your own faction (a ninja looter, a griefer) from their right-click menu, or /cpvp watch First Last: reason. /cpvp watchlist lists them.", Off),
        Tog("watchGroupWarn", "Warn When One Is in Your Group", nil, Off)
    );  y = y - h
    _, h = W:DualRow(parent, y,
        Tog("combatMap", "Combat Map", "Every win and loss as a skull on the world map where you stood: green a win, red a loss.", Off),
        { type = "input", text = "Stay Off In", inputWidth = 160, inputStyle = "popup", placeholder = "Booty Bay, Gadgetzan",
          tooltip = "Zones or subzones, separated by commas, where enemy detection stays off.",
          disabled = Off,
          getValue = function() return P.Get("offZones") end,
          setValue = function(text) cfg.offZones = text or "" end }
    );  y = y - h

    return math.abs(y)
end
