if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Gear_Options.lua
--  Forever Tools > Gear: gear: simplified stats, gear sets, gear score, talent builds, best in slot and stat weights. Each section reads and writes its own feature's
--  keys (the same ones it had on the General page).
-------------------------------------------------------------------------------
if not CUI._ModuleNS["CludesUIForeverEssentials"] then return end

function _G._CUI_BuildForeverGearPage(_, hostFrame, yOffset)
    local W = CUI.Widgets
    local cursorY = yOffset
    local _, height, heading

    CUI:ClearContentHeader()

    ---------------------------------------------------------------------------
    --  SIMPLIFIED STATS (item tooltips)
    ---------------------------------------------------------------------------
    local SS = CUI._SimplifiedStats
    if SS then
        local function Set(keyName, val)
            SS.Cfg()[keyName] = val
            CUI:RefreshPage() -- update the dependent rows' disabled state
        end
        local function shortenOff() return not SS.Get("shorten") end
        local function colorsOff() return not SS.Get("colors") end

        _, height = W:SectionHeader(hostFrame, "SIMPLIFIED STATS", cursorY)
        cursorY = cursorY - height

        -- Shorten Equip Lines | Color Stats
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Shorten Equip Lines",
            tooltip = "Shortens Equip: and Set: stat lines on item tooltips to +X Stat.",
            getValue = function() return SS.Get("shorten") end,
            setValue = function(val) Set("shorten", val) end,
        }, {
            type = "toggle",
            text = "Color Stats",
            tooltip = "Colors each stat name on item tooltips, enchants included, and its number per Number Color.",
            getValue = function() return SS.Get("colors") end,
            setValue = function(val) Set("colors", val) end,
        })
        cursorY = cursorY - height

        -- Merge Equal Spell Power | Number Color
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Merge Equal Spell Power",
            tooltip = "Shows equal spell damage and healing as one Spell Power line.",
            disabled = shortenOff,
            disabledTooltip = "Shorten Equip Lines",
            getValue = function() return SS.Get("merge") end,
            setValue = function(val) Set("merge", val) end,
        }, {
            type = "dropdown",
            text = "Number Color",
            disabled = colorsOff,
            disabledTooltip = "Color Stats",
            values = { signed = "Green / Red", stat = "Stat Color", line = "Line Color" },
            order = { "signed", "stat", "line" },
            getValue = function() return SS.Get("numColor") end,
            setValue = function(val) SS.Cfg().numColor = (val ~= "signed") and val or nil end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  GEAR SETS
    ---------------------------------------------------------------------------
    local GS = CUI._GearSets
    if GS then
        local function gsOff() return not GS.Get("enabled") end
        local function GSSet(key, val)
            GS.Cfg()[key] = val
            GS.Apply()
        end
        local function SetChoices()
            local values, sequence = { [""] = "None" }, { "" }
            for _, s in ipairs(GS.List()) do
                values[s.name] = s.name
                sequence[#sequence + 1] = s.name
            end
            return values, sequence
        end
        local values, sequence = SetChoices()
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "GEAR SETS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_GearSets", disabled = gsOff, disabledTooltip = "Gear Sets" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Gear Sets Bar",
            tooltip = "Your equipment sets on a bar; click one to wear it. The set you are wearing is lit. Armour cannot change in combat, so a click in combat waits for the fight to end.",
            getValue = function() return not gsOff() end,
            setValue = function(val) GSSet("enabled", val and true or false) end,
        }, {
            type = "input",
            text = "Save What You Wear",
            inputWidth = 140,
            inputStyle = "popup",
            placeholder = "Set name",
            tooltip = "Type a name to save the gear you have on as a set. Using an existing name saves over it.",
            getValue = function() return "" end,
            setValue = function(textValue)
                GS.Save(textValue)
                C_Timer.After(0.5, function() CUI:RefreshPage(true) end)
            end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "While Mounted",
            values = values,
            order = sequence,
            disabled = gsOff,
            tooltip = "Wear this set while mounted, and put your gear back when you dismount.",
            getValue = function() return GS.Get("mountedSet") end,
            setValue = function(val) GSSet("mountedSet", val) end,
        }, {
            type = "dropdown",
            text = "While Resting",
            values = values,
            order = sequence,
            disabled = gsOff,
            tooltip = "Wear this set in an inn or a city, and put your gear back when you leave.",
            getValue = function() return GS.Get("restingSet") end,
            setValue = function(val) GSSet("restingSet", val) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  GEAR SCORE
    ---------------------------------------------------------------------------
    local GSC = CUI._GearScore
    if GSC then
        local function gOff() return not GSC.Get("enabled") end
        local function Set(key, val)
            GSC.Cfg()[key] = val
            GSC.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "GEAR SCORE", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Gear Score",
            tooltip = "One number for a character's gear on the item level scale: 26.4 is worth a full set of level 26 epics. Colored by how close it is to dungeon blues five levels over their level. Shown under your level on the character sheet, under item level on the inspect sheet, and in Group Inspect.",
            getValue = function() return not gOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "On Player Tooltips",
            disabled = gOff,
            tooltip = "Player tooltips show their Gear Score: yours from your gear, others' once they have been inspected.",
            getValue = function() return GSC.Get("tooltip") end,
            setValue = function(val) Set("tooltip", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Inspect Players You Hover",
            disabled = gOff,
            tooltip = "The player you hover is inspected in the background (one at a time, in range, out of combat), so their tooltip gets a score. Never while your own Inspect window is open.",
            getValue = function() return GSC.Get("hoverInspect") end,
            setValue = function(val) Set("hoverInspect", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  TALENT BUILDS
    ---------------------------------------------------------------------------
    local TB = CUI._TalentBuilds
    if TB then
        local function tOff() return not TB.Get("enabled") end
        local function Set(key, val)
            TB.Cfg()[key] = val
            TB.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "TALENT BUILDS", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Talent Builds",
            tooltip = "/cbuilds: talent builds as the order you spend points, per class on this account. Save your talents now, import and export them as a line, follow one: its next talent lights up in CludesUI's talent window, and Learn spends your unspent points along it.",
            getValue = function() return not tOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "labeledButton",
            text = "Builds Window",
            buttonText = "Open",
            width = 90,
            disabled = tOff,
            tooltip = "Opens the Talent Builds window. Also /cbuilds.",
            onClick = function() TB.Builds.Toggle() end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Next Talent on Level-Up",
            disabled = tOff,
            tooltip = "Each level-up, a chat line names the next talent of the build you follow.",
            getValue = function() return TB.Get("levelUpLine") end,
            setValue = function(val) Set("levelUpLine", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  BEST IN SLOT
    ---------------------------------------------------------------------------
    local BI = CUI._BiS
    if BI then
        local function BSet(key, val) BI.Cfg()[key] = val and true or false end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "BEST IN SLOT", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Your BiS List",
            buttonText = "Open",
            width = 90,
            tooltip = "Your pick for every gear slot and whether you have it. Alt+Shift-click any item to add or remove it. Shared by your characters of this class. /cbis opens it too.",
            onClick = function() BI.Show() end,
        }, {
            type = "toggle",
            text = "Alt+Shift-Click to Add",
            getValue = function() return BI.Get("enabled") end,
            setValue = function(val) BSet("enabled", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Mark BiS on Tooltips",
            getValue = function() return BI.Get("tooltip") end,
            setValue = function(val) BSet("tooltip", val) end,
        }, {
            type = "toggle",
            text = "Drop Alert",
            tooltip = "A warning, a sound and a chat line when a BiS item you do not have drops: in the loot window, or looted by anyone near you.",
            getValue = function() return BI.Get("alert") end,
            setValue = function(val) BSet("alert", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Export",
            inputWidth = 160,
            inputStyle = "popup",
            tooltip = "Copy this line to share your list.",
            getValue = function() return BI.Export() end,
            setValue = function() end,
        }, {
            type = "input",
            text = "Import",
            inputWidth = 160,
            inputStyle = "popup",
            placeholder = "CUIBIS1:...",
            tooltip = "Paste a CludesUI BiS line for your class. It replaces your list.",
            getValue = function() return "" end,
            setValue = function(textValue) BI.Import(textValue) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  STAT WEIGHTS
    ---------------------------------------------------------------------------
    local SWt = CUI._StatWeights
    if SWt then
        local rowConf = SWt.Cfg()
        local function Rebuild()
            C_Timer.After(0.05, function() CUI:RefreshPage(true) end)
        end
        local values, sequence = { [""] = "Automatic (talents)" }, { "" }
        for _, spec in ipairs(SWt.Specs()) do
            values[spec.key] = spec.name
            sequence[#sequence + 1] = spec.key
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "STAT WEIGHTS", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Upgrades on Tooltips",
            tooltip = "Gear that is an upgrade for your spec says so on its tooltip, as a percent over what you wear. The BiS window shows each pick's gain too. An estimate from these weights.",
            getValue = function() return SWt.Get("enabled") end,
            setValue = function(val)
                rowConf.enabled = val and true or false
                Rebuild()
            end,
        }, {
            type = "dropdown",
            text = "Spec",
            values = values,
            order = sequence,
            tooltip = "Automatic weighs by the talent tree you spent most points in.",
            getValue = function() return rowConf.spec or "" end,
            setValue = function(val)
                rowConf.spec = val
                Rebuild()
            end,
        })
        cursorY = cursorY - height
        if SWt.Get("enabled") then
            local key = SWt.ActiveSpec()
            local weights = SWt.For(key) or {}
            local entries = {}
            for _, st in ipairs(SWt.Stats) do
                if (weights[st[1]] or 0) ~= 0 then entries[#entries + 1] = st end
            end
            local function Slider(st)
                if not st then return { type = "label", text = "" } end
                local max = st[3]
                local step = max >= 20 and 0.5 or (max >= 5 and 0.1 or (max >= 1 and 0.05 or 0.005))
                return {
                    type = "slider",
                    text = st[2],
                    min = 0,
                    max = max,
                    step = step,
                    isPercent = false,
                    getValue = function() return (SWt.For(key) or {})[st[1]] or 0 end,
                    setValue = function(val) SWt.Set(key, st[1], val) end,
                }
            end
            for idx = 1, #entries, 2 do
                _, height = W:DualRow(hostFrame, cursorY, Slider(entries[idx]), Slider(entries[idx + 1]))
                cursorY = cursorY - height
            end
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "labeledButton",
                text = "Weights for " .. (SWt.Spec(key) and SWt.Spec(key).name or "?"),
                buttonText = "Reset",
                width = 90,
                tooltip = "Put this spec's weights back to the defaults.",
                onClick = function()
                    SWt.Reset(key)
                    Rebuild()
                end,
            }, { type = "label", text = "Main stat, Spell Damage, Healing or Stamina is 1." })
            cursorY = cursorY - height
        end
    end

    return math.abs(cursorY)
end
