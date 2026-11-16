if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_PvP_Options.lua
--  Forever Tools > PvP: enemy detection, Kill on Sight, sharing and extras.
-------------------------------------------------------------------------------
if not CludesUI._ModuleNS["CludesUIForeverEssentials"] then
    return
end

function _G._CUI_BuildForeverPvPPage(_, hostFrame, yOffset)
    local P = CludesUI._PvP
    if not P then
        return 0
    end
    local W = CludesUI.Widgets
    local posY = yOffset
    local _, hgt
    local conf = P.Cfg()
    local function Off()
        return not P.Get("enabled")
    end
    local function Tog(key, textValue, tipText, off)
        return {
            type = "toggle",
            text = textValue,
            tooltip = tipText,
            disabled = off,
            getValue = function()
                return P.Get(key)
            end,
            setValue = function(val)
                conf[key] = val and true or false
                P.Apply()
            end,
        }
    end

    CludesUI:ClearContentHeader()

    _, hgt = W:SectionHeader(hostFrame, "ENEMY PLAYERS", posY)
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "enabled",
            "Detect Enemy Players",
            "Lists enemy players around you, from their nameplates, your target, focus and mouseover. Turn enemy nameplates on (Ctrl+V) to see the most; while this is on they reach 60 yards. Off in dungeons, raids and sanctuaries."
        ),
        Tog(
            "autoShow",
            "Show the List When One Is Seen",
            "The list opens on Nearby when a new enemy is seen. It cannot open during combat.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "labeledButton",
        text = "Enemy List",
        buttonText = "Open",
        width = 90,
        tooltip = "Nearby, Last Hour, Kill on Sight and Ignore lists. Click a name to target it. /cpvp opens it too.",
        onClick = function()
            P.Show()
        end,
    }, {
        type = "labeledButton",
        text = "Statistics",
        buttonText = "Open",
        width = 90,
        tooltip = "Every enemy you have met, searchable, with your wins and losses. /cpvp stats.",
        onClick = function()
            P.Stats()
        end,
    })
    posY = posY - hgt
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "slider",
        text = "Remove When Unseen For",
        min = 30,
        max = 300,
        step = 30,
        isPercent = false,
        disabled = Off,
        tooltip = "Seconds before an enemy who has not been seen leaves the Nearby list.",
        getValue = function()
            return P.Get("removeAfter")
        end,
        setValue = function(val)
            conf.removeAfter = math.floor(val + 0.5)
        end,
    }, {
        type = "slider",
        text = "Rows Shown",
        min = 5,
        max = 25,
        step = 1,
        isPercent = false,
        disabled = Off,
        getValue = function()
            return P.Get("rows")
        end,
        setValue = function(val)
            conf.rows = math.floor(val + 0.5)
        end,
    })
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog("battlegrounds", "Also in Battlegrounds", nil, Off),
        { type = "label", text = "" }
    )
    posY = posY - hgt

    _, hgt = W:SectionHeader(hostFrame, "ALERTS", posY)
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "sound",
            "Alert Sound",
            "A sound when a new enemy is seen, and an alarm for Kill on Sight and stealth.",
            Off
        ),
        Tog(
            "stealthWarn",
            "Stealth Warning",
            "A warning when an enemy you can see goes into Stealth or Prowl.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog("kosWarn", "Kill on Sight Warning", nil, Off),
        Tog(
            "kosGuildWarn",
            "Warn for Their Guild",
            "Also a warning when someone from a Kill on Sight player's guild is seen.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "announceKoS",
            "Tell My Group About Kill on Sight",
            "Posts in party or raid chat when a Kill on Sight enemy is seen.",
            Off
        ),
        { type = "label", text = "" }
    )
    posY = posY - hgt

    _, hgt = W:SectionHeader(hostFrame, "SHARING AND EXTRAS", posY)
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "share",
            "Share My Sightings",
            "Sends the enemies you see to your party, raid and guild. Players running CludesUI or Spy in the same zone get them.",
            Off
        ),
        Tog(
            "useShared",
            "Use Their Sightings",
            "Adds enemies others in your group and guild have seen in your zone.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "kosButton",
            "Kill on Sight Button",
            "A KoS button above an enemy target's frame: click to add or remove them, right-click for more.",
            Off
        ),
        Tog(
            "minimapTip",
            "Minimap Enemy Details",
            "With humanoid tracking, the minimap tooltip shows the level and class of enemies you know.",
            Off
        )
    )
    posY = posY - hgt

    _, hgt = W:SectionHeader(hostFrame, "WATCH LIST, COMBAT MAP AND ZONES", posY)
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "watchWarn",
            "Warn When a Watched Player Is Near",
            "Watch players of your own faction (a ninja looter, a griefer) from their right-click menu, or /cpvp watch First Last: reason. /cpvp watchlist lists them.",
            Off
        ),
        Tog("watchGroupWarn", "Warn When One Is in Your Group", nil, Off)
    )
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "combatMap",
            "Combat Map",
            "Every win and loss as a skull on the world map where you stood: green a win, red a loss.",
            Off
        ),
        {
            type = "input",
            text = "Stay Off In",
            inputWidth = 160,
            inputStyle = "popup",
            placeholder = "Booty Bay, Gadgetzan",
            tooltip = "Zones or subzones, separated by commas, where enemy detection stays off.",
            disabled = Off,
            getValue = function()
                return P.Get("offZones")
            end,
            setValue = function(textValue)
                conf.offZones = textValue or ""
            end,
        }
    )
    posY = posY - hgt

    return math.abs(posY)
end
