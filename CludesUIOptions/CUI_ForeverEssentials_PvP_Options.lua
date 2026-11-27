if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_PvP_Options.lua
--  Forever Tools > PvP: enemy detection, Kill on Sight, sharing and extras.
-------------------------------------------------------------------------------
if not CUI._ModuleNS["CludesUIForeverEssentials"] then return end

function _G._CUI_BuildForeverPvPPage(_, hostFrame, yOffset)
    local P = CUI._PvP
    if not P then return 0 end
    local W = CUI.Widgets
    local cursorY = yOffset
    local _, height
    local rowConf = P.Cfg()
    local function Off() return not P.Get("enabled") end
    local function Tog(key, textValue, tipText, off)
        return {
            type = "toggle",
            text = textValue,
            tooltip = tipText,
            disabled = off,
            getValue = function() return P.Get(key) end,
            setValue = function(val)
                rowConf[key] = val and true or false
                P.Apply()
            end,
        }
    end

    CUI:ClearContentHeader()

    _, height = W:SectionHeader(hostFrame, "ENEMY DETECTION", cursorY)
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
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
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "labeledButton",
        text = "Enemy List",
        buttonText = "Open",
        width = 90,
        tooltip = "Shows who is nearby, who you saw in the last hour, your Kill on Sight list and your ignore list. Click a name to target them. You can also type /cpvp.",
        onClick = function() P.Show() end,
    }, {
        type = "labeledButton",
        text = "Statistics",
        buttonText = "Open",
        width = 90,
        tooltip = "Every enemy you have run into, with your wins and losses against each one. Searchable. You can also type /cpvp stats.",
        onClick = function() P.Stats() end,
    })
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Keep on Nearby List For",
        min = 30,
        max = 300,
        step = 30,
        isPercent = false,
        disabled = Off,
        tooltip = "Seconds an enemy stays on the Nearby list after you last saw them.",
        getValue = function() return P.Get("removeAfter") end,
        setValue = function(val) rowConf.removeAfter = math.floor(val + 0.5) end,
    }, {
        type = "slider",
        text = "Rows in the List",
        tooltip = "How many enemies the list shows at once.",
        min = 5,
        max = 25,
        step = 1,
        isPercent = false,
        disabled = Off,
        getValue = function() return P.Get("rows") end,
        setValue = function(val) rowConf.rows = math.floor(val + 0.5) end,
    })
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Tog(
            "battlegrounds",
            "Detect in Battlegrounds",
            "Keeps detecting enemies inside battlegrounds too. Off by default.",
            Off
        ),
        { type = "label", text = "" }
    )
    cursorY = cursorY - height

    _, height = W:SectionHeader(hostFrame, "ALERTS", cursorY)
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
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
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
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
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Tog(
            "announceKoS",
            "Tell Group About Kill on Sight",
            "Posts a message in party or raid chat when a Kill on Sight enemy is spotted.",
            Off
        ),
        { type = "label", text = "" }
    )
    cursorY = cursorY - height

    _, height = W:SectionHeader(hostFrame, "SHARING AND TOOLS", cursorY)
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
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
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
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
    cursorY = cursorY - height

    _, height = W:SectionHeader(hostFrame, "WATCH LIST AND MAP", cursorY)
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
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
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
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
            getValue = function() return P.Get("offZones") end,
            setValue = function(textValue) rowConf.offZones = textValue or "" end,
        }
    )
    cursorY = cursorY - height

    cursorY = _G._CUI_BuildForeverPvPAuras(hostFrame, cursorY)
    return math.abs(cursorY)
end

-- PvP Auras and Battleground Displays (CludesUIForeverEssentials_PvPAuras.lua),
-- after the enemy detection sections. Returns the new cursor.
function _G._CUI_BuildForeverPvPAuras(hostFrame, cursorY)
    local A = CUI._PvPAuras
    if not A then return cursorY end
    local W = CUI.Widgets
    local _, height, heading
    local function Set(key, val, refresh)
        A.Cfg()[key] = val
        A.Apply()
        if refresh then CUI:RefreshPage() end
    end
    local function Off() return not A.Get("enabled") end
    local function Needs(key)
        return function() return Off() or not A.Get(key) end
    end
    local function Tog(key, textValue, tipText, off, refresh)
        return {
            type = "toggle",
            text = textValue,
            tooltip = tipText,
            disabled = off,
            getValue = function() return A.Get(key) == true end,
            setValue = function(val) Set(key, val and true or false, refresh) end,
        }
    end
    local function Slider(key, textValue, minV, maxV, step, tipText, off)
        return {
            type = "slider",
            text = textValue,
            tooltip = tipText,
            min = minV,
            max = maxV,
            step = step,
            isPercent = false,
            disabled = off,
            getValue = function() return A.Get(key) end,
            setValue = function(val) Set(key, math.floor(val + 0.5)) end,
        }
    end
    local function Row(left, right)
        _, height = W:DualRow(hostFrame, cursorY, left, right or { type = "label", text = "" })
        cursorY = cursorY - height
    end
    local function Header(textValue, unlockKey, label)
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, textValue, cursorY)
        cursorY = cursorY - height
        if unlockKey then
            CUI.BuildSectionUnlockJump(heading, { key = unlockKey, disabled = Off, disabledTooltip = label })
        end
    end
    -- Every spell of a list on or off at once.
    local function SetAll(entries, prefix, val)
        local c = A.Cfg()
        for _, entry in ipairs(entries) do
            c[prefix .. entry.key] = val
        end
        A.Apply()
        CUI:RefreshPage()
    end
    local function SpellGrid(entries, prefix, off)
        for idx = 1, #entries, 2 do
            local function Spell(entry)
                if not entry then return nil end
                return Tog(prefix .. entry.key, entry.label, entry.group, off)
            end
            Row(Spell(entries[idx]), Spell(entries[idx + 1]))
        end
    end

    Header("PVP AURAS", "CUI_PvPAuras", "PvP Auras")
    Row(
        Tog(
            "enabled",
            "PvP Auras",
            "Your target's short buffs, the crowd control on them and the debuffs you pick, as large icons that keep working in combat. Changes apply out of combat.",
            nil,
            true
        ),
        Slider("size", "Icon Size", 24, 64, 1, nil, Off)
    )
    Row(
        Tog("timer", "Show Time Left", nil, Off, true),
        Tog("count", "Show Stacks", nil, Off)
    )
    Row(
        Tog(
            "warn",
            "Warn Before It Ends",
            "The time left turns yellow, then red near the end, so you see crowd control about to break.",
            Needs("timer"),
            true
        ),
        Slider(
            "warnAt",
            "Red Under",
            1,
            10,
            1,
            "The seconds left when the time turns red; it turns yellow at twice that.",
            function() return Off() or not (A.Get("timer") and A.Get("warn")) end
        )
    )
    Row(
        Tog(
            "warnBlink",
            "Blink When Red",
            "The red time left blinks, to catch your eye.",
            function() return Off() or not (A.Get("timer") and A.Get("warn")) end
        ),
        Tog(
            "absorb",
            "Show Absorb",
            "Left of the icons, a shield and in blue how much your target's shields still absorb, while one is up.",
            Off
        )
    )
    Row(
        Tog(
            "buffs",
            "Short Buffs",
            "Your target's buffs that last a short while, like Divine Shield, Evasion or Sprint.",
            Off,
            true
        ),
        Slider(
            "buffLength",
            "Up To (seconds)",
            5,
            120,
            5,
            "The longest a buff can last to show; longer ones like Arcane Intellect stay hidden.",
            Needs("buffs")
        )
    )
    Row(
        Tog("buffMagicOnly", "Only Magic Buffs", "Only buffs a dispel or purge can take off.", Needs("buffs")),
        Slider("buffMax", "Max Buffs", 1, 10, 1, nil, Needs("buffs"))
    )
    Row(
        Tog(
            "cc",
            "Crowd Control",
            "The crowd control on your target; pick which in the Crowd Control section below.",
            Off,
            true
        ),
        Slider("ccMax", "Max Crowd Control", 1, 10, 1, nil, Needs("cc"))
    )
    Row(
        Tog(
            "debuffs",
            "Debuffs",
            "The debuffs on your target you pick in the Debuffs section below, like Mortal Strike.",
            Off,
            true
        ),
        Slider("debuffMax", "Max Debuffs", 1, 10, 1, nil, Needs("debuffs"))
    )
    Row(
        Tog(
            "focus",
            "Focus Panel",
            "A second panel for your focus, to keep Sap or Polymorph's time on one enemy while you fight another. It steps aside while your focus is your target.",
            Off,
            true
        ),
        Tog("focusName", "Focus Name", "Your focus's name, tinted by class, with their class icon above the panel.", Needs("focus"))
    )
    Row(
        Tog("focusBuffs", "Focus Short Buffs", nil, Needs("focus")),
        Tog("focusCC", "Focus Crowd Control", nil, Needs("focus"))
    )
    Row(Tog("focusDebuffs", "Focus Debuffs", nil, Needs("focus")))

    Header("CROWD CONTROL")
    Row(
        Tog(
            "ccOther",
            "Other Crowd Control",
            "Crowd control from creatures and anything not listed below.",
            Off
        ),
        {
            type = "labeledButton",
            text = "Every Spell",
            buttonText = "Show All",
            width = 90,
            tooltip = "Lights every crowd control spell below. Shift-click to dim them all, to light only the few you want.",
            disabled = Off,
            onClick = function() SetAll(A.Spells.crowdControl, A.CC_PREFIX, not IsShiftKeyDown()) end,
        }
    )
    SpellGrid(A.Spells.crowdControl, A.CC_PREFIX, Off)

    Header("DEBUFFS")
    Row({
        type = "input",
        text = "Your Own Spell IDs",
        inputWidth = 160,
        inputStyle = "popup",
        placeholder = "12294, 21551",
        tooltip = "More debuffs to show by spell ID, separated by spaces or commas (Wowhead has the ID).",
        disabled = Off,
        getValue = function() return A.Get("debuffExtra") end,
        setValue = function(textValue) Set("debuffExtra", textValue or "") end,
    }, {
        type = "labeledButton",
        text = "Every Debuff",
        buttonText = "Show All",
        width = 90,
        tooltip = "Lights every debuff below. Shift-click to dim them all.",
        disabled = Off,
        onClick = function() SetAll(A.Spells.debuffs, A.DEBUFF_PREFIX, not IsShiftKeyDown()) end,
    })
    SpellGrid(A.Spells.debuffs, A.DEBUFF_PREFIX, Off)

    -- Battleground Countdown: its own switch, apart from PvP Auras.
    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height
    heading, height = W:SectionHeader(hostFrame, "BATTLEGROUND DISPLAYS", cursorY)
    cursorY = cursorY - height
    CUI.BuildSectionUnlockJump(heading, {
        key = "CUI_BGCountdown",
        disabled = function() return not A.CountdownGet("enabled") end,
        disabledTooltip = "Movable Countdown",
    })
    Row({
        type = "toggle",
        text = "Movable Countdown",
        tooltip = "Move the battleground start countdown in Edit Layout. The battleground scores move with Top Bar Event Text (Quality of Life > Window Mover).",
        getValue = function() return A.CountdownGet("enabled") == true end,
        setValue = function(val)
            A.CountdownCfg().enabled = val and true or false
            A.Apply()
            CUI:RefreshPage()
        end,
    })
    return cursorY
end
