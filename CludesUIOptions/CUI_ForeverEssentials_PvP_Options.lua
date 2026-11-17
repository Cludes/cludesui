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
            "Lists the enemy players near you, found from their nameplates, your target, your focus and your mouseover. Turn enemy nameplates on (Ctrl+V) to find the most: while this is on they show out to 60 yards. Does not run in dungeons, raids or sanctuaries."
        ),
        Tog(
            "autoShow",
            "Open the List When an Enemy Is Seen",
            "Opens the enemy list on its Nearby tab when a new enemy is seen. It cannot open during combat.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "labeledButton",
        text = "Enemy List",
        buttonText = "Open",
        width = 90,
        tooltip = "The Nearby, Last Hour, Kill on Sight and Ignore lists. Click a name to target that player. /cpvp also opens it.",
        onClick = function()
            P.Show()
        end,
    }, {
        type = "labeledButton",
        text = "Statistics",
        buttonText = "Open",
        width = 90,
        tooltip = "Every enemy you have met, with your wins and losses against each, and a search box. /cpvp stats also opens it.",
        onClick = function()
            P.Stats()
        end,
    })
    posY = posY - hgt
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "slider",
        text = "Leave Nearby After",
        min = 30,
        max = 300,
        step = 30,
        isPercent = false,
        disabled = Off,
        tooltip = "How many seconds an enemy stays on the Nearby list after you last saw them.",
        getValue = function()
            return P.Get("removeAfter")
        end,
        setValue = function(val)
            conf.removeAfter = math.floor(val + 0.5)
        end,
    }, {
        type = "slider",
        text = "Names Shown",
        tooltip = "The most names the enemy list shows at once.",
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
        Tog(
            "battlegrounds",
            "Also Run in Battlegrounds",
            "Detects enemies in battlegrounds too. Off, it does not run there.",
            Off
        ),
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
            "Plays a sound when a new enemy is seen, and an alarm when a Kill on Sight enemy is seen or an enemy goes into stealth.",
            Off
        ),
        Tog(
            "stealthWarn",
            "Stealth Warning",
            "Warns you when an enemy you can see goes into Stealth or Prowl.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "kosWarn",
            "Kill on Sight Warning",
            "Warns you when a player on your Kill on Sight list is seen.",
            Off
        ),
        Tog(
            "kosGuildWarn",
            "Warn for Their Guildmates",
            "Also warns you when someone from the guild of a Kill on Sight player is seen.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "announceKoS",
            "Announce Kill on Sight to My Group",
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
            "Sends the enemies you see to your party, raid and guild. Players there using CludesUI or Spy, in the same zone as you, receive them.",
            Off
        ),
        Tog(
            "useShared",
            "Use Others' Sightings",
            "Adds the enemies your party, raid and guild have seen in your zone to your list.",
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
            "Puts a KoS button above the target frame when you target an enemy player. Click it to add or remove them from Kill on Sight; right-click it for more options.",
            Off
        ),
        Tog(
            "minimapTip",
            "Minimap Enemy Details",
            "While you track humanoids, the minimap's tooltip shows the level and class of the enemies you know.",
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
            "Warns you when a player on your watch list is near. Add players of your own faction (a ninja looter, a griefer) from their right-click menu, or type /cpvp watch First Last: reason. /cpvp watchlist shows the list.",
            Off
        ),
        Tog(
            "watchGroupWarn",
            "Warn When One Is in Your Group",
            "Also warns you when a player on your watch list is in your party or raid.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "combatMap",
            "Combat Map",
            "Marks each win and loss on the world map with a skull where you fought: green for a win, red for a loss.",
            Off
        ),
        {
            type = "input",
            text = "Turn Off In",
            inputWidth = 160,
            inputStyle = "popup",
            placeholder = "Booty Bay, Gadgetzan",
            tooltip = "Zones or subzones, separated by commas, where enemy detection is turned off.",
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
