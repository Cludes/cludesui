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

    _, hgt = W:SectionHeader(hostFrame, "ENEMY DETECTION", posY)
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "enabled",
            "Enemy Detection",
            "Keeps a list of enemy players around you, spotted through nameplates, your target, focus and mouseover. Turn on enemy nameplates (Ctrl+V) to spot the most; while this is on, nameplates reach 60 yards. Paused in dungeons, raids and sanctuaries."
        ),
        Tog(
            "autoShow",
            "Open List on a New Enemy",
            "Pops the enemy list open on the Nearby tab when someone new is spotted. It cannot open during combat.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "labeledButton",
        text = "Enemy List",
        buttonText = "Open",
        width = 90,
        tooltip = "Shows who is nearby, who you saw in the last hour, your Kill on Sight list and your ignore list. Click a name to target them. You can also type /cpvp.",
        onClick = function()
            P.Show()
        end,
    }, {
        type = "labeledButton",
        text = "Statistics",
        buttonText = "Open",
        width = 90,
        tooltip = "Every enemy you have run into, with your wins and losses against each one. Searchable. You can also type /cpvp stats.",
        onClick = function()
            P.Stats()
        end,
    })
    posY = posY - hgt
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "slider",
        text = "Keep on Nearby List For",
        min = 30,
        max = 300,
        step = 30,
        isPercent = false,
        disabled = Off,
        tooltip = "Seconds an enemy stays on the Nearby list after you last saw them.",
        getValue = function()
            return P.Get("removeAfter")
        end,
        setValue = function(val)
            conf.removeAfter = math.floor(val + 0.5)
        end,
    }, {
        type = "slider",
        text = "Rows in the List",
        tooltip = "How many enemies the list shows at once.",
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
            "Detect in Battlegrounds",
            "Keeps detecting enemies inside battlegrounds too. Off by default.",
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
            "Play Alert Sounds",
            "A sound when someone new is spotted, and an alarm for Kill on Sight enemies and enemies going into stealth.",
            Off
        ),
        Tog(
            "stealthWarn",
            "Warn When an Enemy Stealths",
            "A warning on screen when an enemy you can see vanishes into Stealth or Prowl.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "kosWarn",
            "Warn on Kill on Sight",
            "A warning on screen when someone on your Kill on Sight list is spotted.",
            Off
        ),
        Tog(
            "kosGuildWarn",
            "Include Their Guildmates",
            "Also warns you about members of a Kill on Sight player's guild.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "announceKoS",
            "Tell Group About Kill on Sight",
            "Posts a message in party or raid chat when a Kill on Sight enemy is spotted.",
            Off
        ),
        { type = "label", text = "" }
    )
    posY = posY - hgt

    _, hgt = W:SectionHeader(hostFrame, "SHARING AND TOOLS", posY)
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "share",
            "Share What I Spot",
            "Sends the enemies you spot to your party, raid and guild. Anyone there running CludesUI or Spy in your zone gets them.",
            Off
        ),
        Tog(
            "useShared",
            "Use What Others Spot",
            "Adds enemies your party, raid and guild spot in your zone to your own list.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "kosButton",
            "Kill on Sight Button on Target",
            "A small KoS button above your target frame when you target an enemy player. Click to add or remove them; right-click for more.",
            Off
        ),
        Tog(
            "minimapTip",
            "Enemy Details on Minimap",
            "With Track Humanoids on, hovering a player dot on the minimap shows their level and class if you have met them.",
            Off
        )
    )
    posY = posY - hgt

    _, hgt = W:SectionHeader(hostFrame, "WATCH LIST AND MAP", posY)
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "watchWarn",
            "Warn When a Watched Player Is Near",
            "Your watch list is for players on your own side you want to avoid, like a ninja looter or a griefer. Add someone from their right-click menu or with /cpvp watch First Last: reason, and see the list with /cpvp watchlist.",
            Off
        ),
        Tog(
            "watchGroupWarn",
            "Warn When One Joins My Group",
            "Also warns you when someone on your watch list is in your party or raid.",
            Off
        )
    )
    posY = posY - hgt
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        Tog(
            "combatMap",
            "Fights on the World Map",
            "Drops a skull on the world map wherever you won (green) or lost (red) a fight.",
            Off
        ),
        {
            type = "input",
            text = "Pause Detection In",
            inputWidth = 160,
            inputStyle = "popup",
            placeholder = "Booty Bay, Gadgetzan",
            tooltip = "Zones or subzones, separated by commas, where enemy detection pauses (a city you idle in, for example).",
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
