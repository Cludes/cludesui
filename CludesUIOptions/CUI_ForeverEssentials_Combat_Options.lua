if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Combat_Options.lua
--  Forever Tools > Combat: combat helpers: stance and aura icon, tracking reminder, swing timer, mana bar, consumable bar, combat extras, paladin blessings, mana efficiency, healer mana and pet tracker. Each section reads and writes its own feature's
--  keys (the same ones it had on the General page).
-------------------------------------------------------------------------------
if not CUI._ModuleNS["CludesUIForeverEssentials"] then return end

function _G._CUI_BuildForeverCombatPage(_, hostFrame, yOffset)
    local W = CUI.Widgets
    local cursorY = yOffset
    local _, height, heading

    CUI:ClearContentHeader()

    ---------------------------------------------------------------------------
    --  ACTIVE STANCE, FORM, ASPECT & AURA
    ---------------------------------------------------------------------------
    local AF = CUI._ActiveForm
    if AF then
        local function afOff() return not AF.Get("enabled") end
        local function AFSet(key, val)
            AF.Cfg()[key] = val
            AF.Apply()
        end
        local _, class = UnitClass("player")
        local labelText = class == "WARRIOR" and "Show Current Stance"
            or class == "DRUID" and "Show Current Form"
            or class == "PALADIN" and "Show Current Aura"
            or class == "HUNTER" and "Show Current Aspect"
            or "Show Current Stance / Form"

        heading, height = W:SectionHeader(hostFrame, "ACTIVE STANCE, FORM, ASPECT & AURA", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_ActiveForm", disabled = afOff, disabledTooltip = labelText }
        )

        _, height = CUI.BuildVisibilityRow(W, hostFrame, cursorY, {
            leftCfg = {
                type = "toggle",
                text = labelText,
                tooltip = "Shows an icon for your active stance, form, aura or aspect. Hidden while none is active.",
                getValue = function() return not afOff() end,
                setValue = CUI.SectionToggleSetValue(function(val) AFSet("enabled", val) end),
            },
            -- The table exists once it was turned on, and the row is greyed out
            -- while it is off, so viewing the page saves nothing.
            getStore = function() return afOff() and AF.Read() or AF.Cfg() end,
            caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
            disabledFn = afOff,
            disabledTooltip = labelText,
            onChanged = CUI.RequestVisibilityUpdate,
            onOptionChanged = CUI.RequestVisibilityUpdate,
        })
        cursorY = cursorY - height

        if not afOff() then
            -- Icon Size | Icon Zoom
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Icon Size",
                min = 16,
                max = 96,
                step = 1,
                isPercent = false,
                getValue = function() return AF.Get("iconSize") end,
                setValue = function(val) AFSet("iconSize", val) end,
            }, {
                type = "slider",
                text = "Icon Zoom",
                tooltip = "Crops the icon's edges.",
                min = 0,
                max = 25,
                step = 1,
                isPercent = false,
                getValue = function() return AF.Get("zoom") end,
                setValue = function(val) AFSet("zoom", val) end,
            })
            cursorY = cursorY - height

            -- Border Style | Border Size (+ color swatch)
            local texValues, texOrder = CUI.GetBorderTextureDropdown()
            local borderRow
            borderRow, height = W:DualRow(
                hostFrame,
                cursorY,
                {
                    type = "dropdown",
                    text = "Border Style",
                    values = texValues,
                    order = texOrder,
                    getValue = function() return AF.Get("borderTexture") end,
                    setValue = function(val)
                        local c = AF.Cfg()
                        c.borderTexture = val
                        c.borderTextureOffset, c.borderTextureOffsetY = nil, nil
                        local color = CUI.GetBorderStyleSelectDefaults(val)
                        c.borderR, c.borderG, c.borderB, c.borderA = color.r, color.g, color.b, 1
                        local defaultSize = CUI.GetBorderDefaultSize(nil, val)
                        if defaultSize then c.borderSize = defaultSize end
                        if c.borderSizePx then c.borderSizePx = false end
                        AF.Apply()
                        -- Rebuild: the offset row follows the Solid / textured pick.
                        CUI:RefreshPage(true)
                    end,
                },
                CUI.BorderPxSliderCfg({
                    text = "Border Size",
                    getStep = function() return AF.Get("borderSize") end,
                    setStep = function(val) AF.Cfg().borderSize = val end,
                    getTex = function() return AF.Get("borderTexture") end,
                    getPx = function() return AF.Read().borderSizePx end,
                    setPx = function(val) AF.Cfg().borderSizePx = val end,
                    apply = AF.Apply,
                })
            )
            cursorY = cursorY - height

            if not CUI._prebuilding then
                local region = borderRow._rightRegion
                local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
                    region,
                    region:GetFrameLevel() + 5,
                    function()
                        return AF.Get("borderR"), AF.Get("borderG"), AF.Get("borderB"), AF.Get("borderA")
                    end,
                    function(red, green, blue, a)
                        local c = AF.Cfg()
                        c.borderR, c.borderG, c.borderB, c.borderA = red, green, blue, a or 1
                        AF.Apply()
                    end,
                    true,
                    20
                )
                colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -12, 0)
                region._lastInline = colorSwatch
                CUI.RegisterWidgetRefresh(updateSwatch)
            end

            -- Width | Height Offset: only while a textured style is selected.
            local texKey = AF.Get("borderTexture")
            if texKey ~= "" and texKey ~= "solid" then
                local offL, offR = CUI.BorderOffsetRowCfgs({
                    getTex = function() return AF.Get("borderTexture") end,
                    getStep = function() return AF.Get("borderSize") end,
                    getSizeKey = function() return AF.Get("borderSize") end,
                    getPx = function() return AF.Read().borderSizePx end,
                    getX = function() return AF.Read().borderTextureOffset end,
                    setX = function(val) AF.Cfg().borderTextureOffset = val end,
                    getY = function() return AF.Read().borderTextureOffsetY end,
                    setY = function(val) AF.Cfg().borderTextureOffsetY = val end,
                    apply = AF.Apply,
                })
                _, height = W:DualRow(hostFrame, cursorY, offL, offR)
                cursorY = cursorY - height
            end
        end
    end

    ---------------------------------------------------------------------------
    --  TRACKING REMINDER
    ---------------------------------------------------------------------------
    local TR = CUI._TrackingReminder
    if TR then
        local function trOff() return not TR.Get("enabled") end
        local function TRSet(key, val)
            TR.Cfg()[key] = val
            TR.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "TRACKING REMINDER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_TrackingReminder", disabled = trOff, disabledTooltip = "Tracking Reminder" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Tracking Reminder",
            tooltip = "A row of icons for the tracking you know but have not turned on: Find Treasure, hunter tracks, Track Humanoids in Cat Form, Sense Undead, Sense Demons. Click one to turn it on. Hidden in combat.",
            getValue = function() return not trOff() end,
            setValue = function(val) TRSet("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Include Find Herbs and Minerals",
            disabled = trOff,
            getValue = function() return TR.Get("gathering") end,
            setValue = function(val) TRSet("gathering", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Icon Size",
            min = 16,
            max = 64,
            step = 1,
            isPercent = false,
            disabled = trOff,
            getValue = function() return TR.Get("iconSize") end,
            setValue = function(val) TRSet("iconSize", math.floor(val + 0.5)) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  SWING TIMER
    ---------------------------------------------------------------------------
    local STm = CUI._SwingTimer
    if STm then
        local function stOff() return not STm.Get("enabled") end
        local function STSet(key, val)
            STm.Cfg()[key] = val
            STm.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "SWING TIMER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_SwingTimer", disabled = stOff, disabledTooltip = "Swing Timer" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Swing Timer",
            tooltip = "A bar per weapon that fills to your next auto attack. The game sends each swing's real length, so haste and parry haste are already counted.",
            getValue = function() return not stOff() end,
            setValue = function(val) STSet("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Hide When Idle",
            disabled = stOff,
            tooltip = "Hide a bar when that weapon has not swung for a moment.",
            getValue = function() return STm.Get("hideIdle") end,
            setValue = function(val) STSet("hideIdle", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Off Hand Bar",
            disabled = stOff,
            getValue = function() return STm.Get("offHand") end,
            setValue = function(val) STSet("offHand", val and true or false) end,
        }, {
            type = "toggle",
            text = "Ranged Bar",
            disabled = stOff,
            getValue = function() return STm.Get("ranged") end,
            setValue = function(val) STSet("ranged", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Width",
            min = 80,
            max = 400,
            step = 1,
            isPercent = false,
            disabled = stOff,
            getValue = function() return STm.Get("width") end,
            setValue = function(val) STSet("width", math.floor(val + 0.5)) end,
        }, {
            type = "slider",
            text = "Height",
            min = 6,
            max = 30,
            step = 1,
            isPercent = false,
            disabled = stOff,
            getValue = function() return STm.Get("height") end,
            setValue = function(val) STSet("height", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  MANA BAR AND FIVE-SECOND RULE
    ---------------------------------------------------------------------------
    local DM = CUI._DruidMana
    if DM then
        local function dmOff() return not DM.Get("enabled") end
        local function DMSet(key, val)
            DM.Cfg()[key] = val
            DM.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "MANA BAR", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_ManaBar", disabled = dmOff, disabledTooltip = "Mana Bar" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Mana Bar",
            tooltip = "Shows a druid's mana while in Bear, Cat or another form that hides it.",
            getValue = function() return not dmOff() end,
            setValue = function(val) DMSet("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Five-Second Rule",
            disabled = dmOff,
            tooltip = "A line under the bar counts down five seconds after you spend mana, while spirit regen is paused.",
            getValue = function() return DM.Get("fiveSecond") end,
            setValue = function(val) DMSet("fiveSecond", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Always Show",
            disabled = dmOff,
            tooltip = "Show the bar all the time, for any class with mana, not only a druid in a form.",
            getValue = function() return DM.Get("always") end,
            setValue = function(val) DMSet("always", val and true or false) end,
        }, {
            type = "slider",
            text = "Width",
            min = 80,
            max = 400,
            step = 1,
            isPercent = false,
            disabled = dmOff,
            getValue = function() return DM.Get("width") end,
            setValue = function(val) DMSet("width", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  CONSUMABLE BAR
    ---------------------------------------------------------------------------
    local CB = CUI._ConsumableBar
    if CB then
        local function cbOff() return not CB.Get("enabled") end
        local function CBSet(key, val)
            CB.Cfg()[key] = val
            CB.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "CONSUMABLE BAR", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_ConsumableBar", disabled = cbOff, disabledTooltip = "Consumable Bar" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Consumable Bar",
            tooltip = "The consumables in your bags on a bar you can click, with how many you carry and their cooldowns. It works in combat; an item you run out of in a fight keeps its icon until the fight ends.",
            getValue = function() return not cbOff() end,
            setValue = function(val) CBSet("enabled", val and true or false) end,
        }, {
            type = "slider",
            text = "Icon Size",
            min = 16,
            max = 64,
            step = 1,
            isPercent = false,
            disabled = cbOff,
            getValue = function() return CB.Get("iconSize") end,
            setValue = function(val) CBSet("iconSize", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
        local cats = CB.Categories
        for idx = 1, #cats, 2 do
            local function Toggle(cfg)
                if not cfg then return { type = "label", text = "" } end
                return {
                    type = "toggle",
                    text = cfg.label,
                    disabled = cbOff,
                    getValue = function() return CB.Get(cfg.key) end,
                    setValue = function(val) CBSet(cfg.key, val and true or false) end,
                }
            end
            _, height = W:DualRow(hostFrame, cursorY, Toggle(cats[idx]), Toggle(cats[idx + 1]))
            cursorY = cursorY - height
        end
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Most Icons",
            min = 1,
            max = 30,
            step = 1,
            isPercent = false,
            disabled = cbOff,
            getValue = function() return CB.Get("maxIcons") end,
            setValue = function(val) CBSet("maxIcons", math.floor(val + 0.5)) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  COMBAT EXTRAS
    ---------------------------------------------------------------------------
    local CE = CUI._CombatExtras
    if CE then
        local function Set(f, key, val)
            f.Cfg()[key] = val
            f.Apply()
        end
        local function Off(f)
            return function() return not f.Get("enabled") end
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "COMBAT EXTRAS", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Combat Timer",
            tooltip = "How long the current fight has run, held for a few seconds after it ends. Move it in Edit Layout.",
            getValue = function() return CE.timer.Get("enabled") end,
            setValue = function(val) Set(CE.timer, "enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Fight Length in Chat",
            disabled = Off(CE.timer),
            getValue = function() return CE.timer.Get("chat") end,
            setValue = function(val) Set(CE.timer, "chat", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Combat Alert",
            tooltip = "+ Combat and - Combat fade in the middle of the screen as you enter and leave combat.",
            getValue = function() return CE.alert.Get("enabled") end,
            setValue = function(val) Set(CE.alert, "enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Alert Sound",
            tooltip = "The sound the alert plays.",
            disabled = Off(CE.alert),
            getValue = function() return CE.alert.Get("sound") end,
            setValue = function(val) Set(CE.alert, "sound", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Stealth Reminder",
            tooltip = "For rogues, and druids in Cat Form: Not stealthed shows while you are out of combat and out of stealth. Never in an inn or a city, or while mounted.",
            getValue = function() return CE.stealth.Get("enabled") end,
            setValue = function(val) Set(CE.stealth, "enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Only in a Group",
            disabled = Off(CE.stealth),
            getValue = function() return CE.stealth.Get("groupOnly") end,
            setValue = function(val) Set(CE.stealth, "groupOnly", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  PALADIN BLESSINGS
    ---------------------------------------------------------------------------
    local BL = CUI._Blessings
    if BL then
        local function bOff() return not BL.Get("enabled") end
        local function Set(key, val)
            BL.Cfg()[key] = val
            BL.Apply()
        end
        local function Tog(key, textValue, tipText)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = bOff,
                getValue = function() return BL.Get(key) end,
                setValue = function(val) Set(key, val and true or false) end,
            }
        end
        local function Slider(key, textValue, lo, hi, tipText)
            return {
                type = "slider",
                text = textValue,
                tooltip = tipText,
                min = lo,
                max = hi,
                step = 1,
                isPercent = false,
                disabled = bOff,
                getValue = function() return BL.Get(key) end,
                setValue = function(val) Set(key, math.floor(val + 0.5)) end,
            }
        end
        local ROLE_VALUES = {
            none = "None",
            might = "Blessing of Might",
            wisdom = "Blessing of Wisdom",
            kings = "Blessing of Kings",
        }
        local ROLE_ORDER = { "none", "might", "wisdom", "kings" }
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "PALADIN BLESSINGS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_BlessingBar", disabled = bOff, disabledTooltip = "Blessing Bar" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Blessing Bar",
            tooltip = "For paladins: your aura and a button per class in the group. Left-click a class to bless the next member who needs it, missing first; in combat each click steps to the next. Right-click a class for its blessing, its player list or the assignments. Plans are shared with the group's other paladins, and PallyPower users' plans are read too.",
            getValue = function() return not bOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "labeledButton",
            text = "Assignments",
            buttonText = "Open",
            width = 90,
            disabled = bOff,
            tooltip = "Every paladin's blessing for each class and their aura, with Auto-Assign, a saved preset and a report to chat. Also /cbless.",
            onClick = function() BL.Open() end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("showAura", "Aura Button", "Casts your aura. Right-click it to choose which, wheel to cycle."),
            Tog(
                "showFury",
                "Righteous Fury Button",
                "Casts Righteous Fury on yourself. A red ! means it is not up."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("showSeal", "Seal Button", "Casts your seal. Right-click it to choose which, wheel to cycle."),
            Tog(
                "showAuto",
                "Auto Buff Button",
                "Left-click blesses the next player in need, right-click the next Greater Blessing."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "autoGreater",
                "Auto Buff Greater First",
                "Swaps the Auto Buff button: left-click casts a Greater Blessing, right-click a single one."
            ),
            Tog("showClasses", "Class Buttons", "Off leaves only the Auto Buff button and the key bindings.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "playerList",
                "Player List",
                "Right-click a class to list its players: bless one, or give one their own blessing."
            ),
            Tog("tooltips", "Show Tooltips", "A tooltip on each bar button.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "labels",
                "Class Labels",
                "Each class's name under its button, or beside it when the bar is vertical."
            ),
            Tog(
                "timers",
                "Minutes Left",
                "Minutes left on each class's shortest blessing, and on each player's."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "smart",
                "Smart Blessings",
                "No Wisdom for warriors and rogues, no Might for priests, mages and warlocks in the menus."
            ),
            Tog(
                "respect",
                "Respect Blessing Time",
                "Only bless players who are missing a blessing or running out."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("wait", "Wait for Players", "Cast a Greater Blessing only when the whole class is in range."),
            Tog(
                "bench",
                "Hide the Bench",
                "In a raid dungeon, leave out the players outside its usual groups."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("inParty", "Use in Party", "Show the bar in a party. It always shows in a raid."),
            Tog("solo", "Use When Solo", "Show the bar when you are not in a group.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Main Tank Blessing",
            values = ROLE_VALUES,
            order = ROLE_ORDER,
            disabled = bOff,
            tooltip = "A warrior, druid or paladin marked as tank or main tank gets this instead of their class blessing.",
            getValue = function() return BL.Get("tank") end,
            setValue = function(val) Set("tank", val) end,
        }, {
            type = "dropdown",
            text = "Main Assist Blessing",
            values = ROLE_VALUES,
            order = ROLE_ORDER,
            disabled = bOff,
            tooltip = "A warrior, druid or paladin marked as main assist gets this instead of their class blessing.",
            getValue = function() return BL.Get("assist") end,
            setValue = function(val) Set("assist", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "vertical",
                "Vertical Bar",
                "The bar grows down instead of right, with the class names beside the buttons."
            ),
            {
                type = "dropdown",
                text = "Button Border",
                disabled = bOff,
                values = { black = "Black", status = "Status Color", none = "None" },
                order = { "black", "status", "none" },
                tooltip = "With Status Color the class buttons show their state on their edge instead of tinting the icon: red missing, yellow running out, blue only players with their own.",
                getValue = function() return BL.Get("border") end,
                setValue = function(val) Set("border", val) end,
            }
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider("size", "Button Size", 20, 60),
            Slider("spacing", "Button Spacing", 0, 30)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider(
                "groupGap",
                "Aura / Class Gap",
                0,
                40,
                "The extra gap between your own buttons and the class buttons."
            ),
            Slider("perRow", "Class Buttons per Row", 1, 9)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, Slider("timerSize", "Timer Text Size", 8, 20), {
            type = "label",
            text = "Key bindings: Next Blessing and Next Greater Blessing, under CludesUI in the game's Key Bindings.",
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  MANA EFFICIENCY
    ---------------------------------------------------------------------------
    local SE = CUI._SpellEfficiency
    if SE then
        local function seOff() return not SE.Get("enabled") end
        local function SESet(key, val) SE.Cfg()[key] = val end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "MANA EFFICIENCY", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Mana Efficiency",
            tooltip = "A line on a mana spell's tooltip (and a macro that casts one) with its healing or damage per mana and per second, with your spell power and talents counted.",
            getValue = function() return not seOff() end,
            setValue = function(val) SESet("enabled", val and true or false) end,
        }, {
            type = "dropdown",
            text = "Show",
            disabled = seOff,
            values = { all = "Healing and Damage", heal = "Healing Only", damage = "Damage Only" },
            order = { "all", "heal", "damage" },
            getValue = function() return SE.Get("show") end,
            setValue = function(val) SESet("show", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Per Mana",
            disabled = seOff,
            getValue = function() return SE.Get("perMana") end,
            setValue = function(val) SESet("perMana", val and true or false) end,
        }, {
            type = "toggle",
            text = "Per Second",
            disabled = seOff,
            getValue = function() return SE.Get("perSecond") end,
            setValue = function(val) SESet("perSecond", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Per Mana per Second",
            disabled = seOff,
            getValue = function() return SE.Get("perManaSecond") end,
            setValue = function(val) SESet("perManaSecond", val and true or false) end,
        }, {
            type = "dropdown",
            text = "Style",
            disabled = seOff,
            values = { long = "Words (healing per mana)", short = "Short (HPM, HPS)" },
            order = { "long", "short" },
            getValue = function() return SE.Get("style") end,
            setValue = function(val) SESet("style", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Count Spell Power",
            disabled = seOff,
            getValue = function() return SE.Get("bonus") end,
            setValue = function(val) SESet("bonus", val and true or false) end,
        }, {
            type = "toggle",
            text = "Count Talents",
            disabled = seOff,
            getValue = function() return SE.Get("talents") end,
            setValue = function(val) SESet("talents", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Decimals",
            min = 0,
            max = 2,
            step = 1,
            isPercent = false,
            disabled = seOff,
            getValue = function() return SE.Get("decimals") end,
            setValue = function(val) SESet("decimals", math.floor(val + 0.5)) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  HEALER MANA AND PET TRACKER
    ---------------------------------------------------------------------------
    local GW = CUI._GroupWatch
    if GW then
        local hm, pt = GW.healer, GW.pet
        local function Set(f, key, val)
            f.Cfg()[key] = val
            f.Apply()
        end
        local function hmOff() return not hm.Get("enabled") end
        local function ptOff() return not pt.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "HEALER MANA", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_HealerMana", disabled = hmOff, disabledTooltip = "Healer Mana" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Healer Mana",
            tooltip = "Your group's healers and their mana, lowest first, with a cup beside anyone drinking. Move it in Edit Layout.",
            getValue = function() return not hmOff() end,
            setValue = function(val) Set(hm, "enabled", val and true or false) end,
        }, {
            type = "dropdown",
            text = "Show In",
            disabled = hmOff,
            values = { instance = "Dungeons & Raids", group = "Any Group" },
            order = { "instance", "group" },
            getValue = function() return hm.Get("where") end,
            setValue = function(val) Set(hm, "where", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Yourself",
            disabled = hmOff,
            getValue = function() return hm.Get("showSelf") end,
            setValue = function(val) Set(hm, "showSelf", val and true or false) end,
        }, {
            type = "toggle",
            text = "Mark Drinking",
            disabled = hmOff,
            getValue = function() return hm.Get("drinking") end,
            setValue = function(val) Set(hm, "drinking", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Say When You Drink",
            tooltip = "As a healer in a dungeon or raid group, sitting down to drink says \"Drinking (25% mana)\" in group chat, and \"Mana full\" once you are ready. Works even with the Healer Mana list off.",
            getValue = function() return hm.Get("sayDrink") end,
            setValue = function(val) Set(hm, "sayDrink", val and true or false) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Width",
            min = 100,
            max = 300,
            step = 5,
            isPercent = false,
            disabled = hmOff,
            getValue = function() return hm.Get("width") end,
            setValue = function(val) Set(hm, "width", math.floor(val + 0.5)) end,
        }, {
            type = "slider",
            text = "Text Size",
            min = 8,
            max = 20,
            step = 1,
            isPercent = false,
            disabled = hmOff,
            getValue = function() return hm.Get("size") end,
            setValue = function(val) Set(hm, "size", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "PET TRACKER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_PetTracker", disabled = ptOff, disabledTooltip = "Pet Tracker" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Pet Tracker",
            tooltip = "A warning while a hunter or warlock has no pet out. A warlock who sacrificed their demon, and a hunter with Lone Wolf, are left alone.",
            getValue = function() return not ptOff() end,
            setValue = function(val) Set(pt, "enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Warn While Passive",
            disabled = ptOff,
            getValue = function() return pt.Get("passive") end,
            setValue = function(val) Set(pt, "passive", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Warn on Low Pet Health",
            disabled = ptOff,
            getValue = function() return pt.Get("lowHealth") end,
            setValue = function(val) Set(pt, "lowHealth", val and true or false) end,
        }, {
            type = "slider",
            text = "Low Health Below",
            min = 5,
            max = 90,
            step = 1,
            isPercent = false,
            disabled = ptOff,
            getValue = function() return pt.Get("lowBelow") end,
            setValue = function(val) Set(pt, "lowBelow", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Only In Combat",
            disabled = ptOff,
            getValue = function() return pt.Get("combatOnly") end,
            setValue = function(val) Set(pt, "combatOnly", val and true or false) end,
        }, {
            type = "toggle",
            text = "Only In Dungeons & Raids",
            disabled = ptOff,
            getValue = function() return pt.Get("instanceOnly") end,
            setValue = function(val) Set(pt, "instanceOnly", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Hide While Mounted",
            disabled = ptOff,
            getValue = function() return pt.Get("hideMounted") end,
            setValue = function(val) Set(pt, "hideMounted", val and true or false) end,
        }, {
            type = "toggle",
            text = "Show Icon",
            disabled = ptOff,
            getValue = function() return pt.Get("showIcon") end,
            setValue = function(val) Set(pt, "showIcon", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    return math.abs(cursorY)
end
