if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_QoL_Alerts_Options.lua
--  ALERTS section: Combat Alert, Potion Ready Alert, Unspent Talents Alert and
--  Announce Group Deaths. The first three share one movable anchor (Unlock Mode:
--  Alerts) and have their own text, size and color; their runtime is
--  CludesUIQoL_Alerts.lua. Group Deaths keeps its own overlay (CludesUIQoL.lua).
-------------------------------------------------------------------------------

if not CludesUI._ModuleNS["CludesUIQoL"] then return end  -- module disabled: no options page

-- Text, size, color and class-color rows for the Potion / Talent alerts
-- (keys: <prefix>Text / TextSize / Color / UseClassColor; defaults come from
-- the alert itself so the swatch always shows the real default).
local function AlertCogRows(prefix, applyFrame, preview)
    local D = (CludesUI.Alerts and CludesUI.Alerts.DEFAULTS[prefix])
        or { text = "", color = { r = 1, g = 1, b = 1 } }
    local function db(k) return CludesUIDB and CludesUIDB[prefix .. k] end
    local function put(k, v)
        if not CludesUIDB then CludesUIDB = {} end
        CludesUIDB[prefix .. k] = v
    end
    return {
        { type="input", label="Text", inputWidth=130,
          get=function() return db("Text") or D.text end,
          set=function(v) put("Text", v); if CludesUI[preview] then CludesUI[preview]() end end },
        { type="slider", label="Text Size", min=14, max=64, step=1,
          get=function() return db("TextSize") or 22 end,
          set=function(v)
            put("TextSize", v)
            if CludesUI[applyFrame] then CludesUI[applyFrame]() end
            if CludesUI[preview] then CludesUI[preview]() end
          end },
        { type="colorpicker", label="Color",
          disabled=function() return db("UseClassColor") end,
          disabledTooltip="Disable Class Color to pick a custom color.", rawTooltip=true,
          get=function()
            local c = db("Color") or D.color
            return c.r, c.g, c.b
          end,
          set=function(r, g, b)
            put("Color", { r=r, g=g, b=b })
            if CludesUI[preview] then CludesUI[preview]() end
          end },
        { type="toggle", label="Class Color",
          get=function() return db("UseClassColor") end,
          set=function(v) put("UseClassColor", v); if CludesUI[preview] then CludesUI[preview]() end end },
    }
end

_G._CUI_BuildAlertsSection = function(parent, yOffset, W, PP)
    local y = yOffset
    local _, h, hdr

    hdr, h = W:SectionHeader(parent, "ALERTS", y); y = y - h
    -- One anchor carries the Combat, Potion Ready and Unspent Talents alerts,
    -- each with its own enable, so the button has no single requirement.
    CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_CombatAlert" })

    local row1
    row1, h = W:DualRow(parent, y,
        { type="toggle", text="Combat Alert",
          tooltip="Shows a large on-screen text when you enter and/or leave combat (e.g. \"+Combat\" / \"-Combat\"). Use the cog to set the display text, size, colors and which transitions are shown; use Unlock Mode to reposition the alert.",
          getValue=function()
              return CludesUIDB and CludesUIDB.combatAlertEnabled or false
          end,
          setValue=function(v)
              if not CludesUIDB then CludesUIDB = {} end
              CludesUIDB.combatAlertEnabled = v
              if CludesUI._applyCombatAlert then CludesUI._applyCombatAlert() end
              CludesUI:RefreshPage()
          end },
        { type="toggle", text="Potion Ready Alert",
          tooltip="Shows on-screen text when a potion you used is off cooldown again. Use the cog to set the text, size and color; use Unlock Mode to reposition the alerts.",
          getValue=function()
              return CludesUIDB and CludesUIDB.potionAlertEnabled or false
          end,
          setValue=function(v)
              if not CludesUIDB then CludesUIDB = {} end
              CludesUIDB.potionAlertEnabled = v
              if CludesUI._applyPotionAlert then CludesUI._applyPotionAlert() end
              CludesUI:RefreshPage()
          end }
    );  y = y - h

    local row2
    row2, h = W:DualRow(parent, y,
        { type="toggle", text="Unspent Talents Alert",
          tooltip="Shows on-screen text while you have unspent talent points. It stays up until you spend them or open your talents, and returns after a level-up. Use the cog to set the text, size and color; use Unlock Mode to reposition the alerts.",
          getValue=function()
              return CludesUIDB and CludesUIDB.talentAlertEnabled or false
          end,
          setValue=function(v)
              if not CludesUIDB then CludesUIDB = {} end
              CludesUIDB.talentAlertEnabled = v
              if CludesUI._applyTalentAlert then CludesUI._applyTalentAlert() end
              CludesUI:RefreshPage()
          end },
        { type="toggle", text="Announce Group Deaths",
          tooltip="Shows a large on-screen alert (e.g. \"Player DIED!\") whenever a party or raid member dies, so you immediately notice deaths during dungeons and raids. Use Unlock Mode to reposition the alert.",
          getValue=function()
              return CludesUIDB and CludesUIDB.announceGroupDeaths or false
          end,
          setValue=function(v)
              if not CludesUIDB then CludesUIDB = {} end
              CludesUIDB.announceGroupDeaths = v
              if CludesUI._applyAnnounceGroupDeaths then CludesUI._applyAnnounceGroupDeaths() end
              CludesUI:RefreshPage()
          end }
    );  y = y - h

    -- Inline cog (text, size, colors, mode) on the Combat Alert toggle.
    if not CludesUI._prebuilding then
        local leftRgn = row1._leftRegion
        local function caOff()
            return not (CludesUIDB and CludesUIDB.combatAlertEnabled)
        end
        local function enterClassOn()
            return CludesUIDB and CludesUIDB.combatAlertEnterUseClassColor
        end
        local function leaveClassOn()
            return CludesUIDB and CludesUIDB.combatAlertLeaveUseClassColor
        end

        local caModeValues = {
            both  = "Enter & Leave",
            enter = "Enter Only",
            leave = "Leave Only",
        }
        local caModeOrder = { "both", "enter", "leave" }

        CludesUI.BuildInlineCog(leftRgn, {
            title = "Combat Alert Settings",
            minWidth = 300,
            rows = {
                { type="dropdown", label="Show On",
                  values=caModeValues, order=caModeOrder,
                  get=function() return (CludesUIDB and CludesUIDB.combatAlertMode) or "both" end,
                  set=function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.combatAlertMode = v
                  end },
                { type="slider", label="Text Size",
                  min=14, max=64, step=1,
                  get=function()
                    return (CludesUIDB and CludesUIDB.combatAlertTextSize) or 22
                  end,
                  set=function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.combatAlertTextSize = v
                    if CludesUI._applyCombatAlertFrame then CludesUI._applyCombatAlertFrame() end
                    if CludesUI._combatAlertPreview then CludesUI._combatAlertPreview("enter") end
                  end },
                { type="input", label="Enter Text", inputWidth=90,
                  get=function()
                    return (CludesUIDB and CludesUIDB.combatAlertEnterText) or "+Combat"
                  end,
                  set=function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.combatAlertEnterText = v
                    if CludesUI._combatAlertPreview then CludesUI._combatAlertPreview("enter") end
                  end },
                { type="colorpicker", label="Enter Color",
                  disabled=enterClassOn,
                  disabledTooltip="Disable Class Color to pick a custom color.", rawTooltip=true,
                  get=function()
                    local c = (CludesUIDB and CludesUIDB.combatAlertEnterColor) or { r=1.00, g=1.00, b=1.00 }
                    return c.r, c.g, c.b
                  end,
                  set=function(r, g, b)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.combatAlertEnterColor = { r=r, g=g, b=b }
                    if CludesUI._combatAlertPreview then CludesUI._combatAlertPreview("enter") end
                  end },
                { type="toggle", label="Enter Class Color",
                  get=function() return enterClassOn() end,
                  set=function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.combatAlertEnterUseClassColor = v
                    if CludesUI._combatAlertPreview then CludesUI._combatAlertPreview("enter") end
                  end },
                { type="input", label="Leave Text", inputWidth=90,
                  get=function()
                    return (CludesUIDB and CludesUIDB.combatAlertLeaveText) or "-Combat"
                  end,
                  set=function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.combatAlertLeaveText = v
                    if CludesUI._combatAlertPreview then CludesUI._combatAlertPreview("leave") end
                  end },
                { type="colorpicker", label="Leave Color",
                  disabled=leaveClassOn,
                  disabledTooltip="Disable Class Color to pick a custom color.", rawTooltip=true,
                  get=function()
                    local c = (CludesUIDB and CludesUIDB.combatAlertLeaveColor) or { r=1.00, g=1.00, b=1.00 }
                    return c.r, c.g, c.b
                  end,
                  set=function(r, g, b)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.combatAlertLeaveColor = { r=r, g=g, b=b }
                    if CludesUI._combatAlertPreview then CludesUI._combatAlertPreview("leave") end
                  end },
                { type="toggle", label="Leave Class Color",
                  get=function() return leaveClassOn() end,
                  set=function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.combatAlertLeaveUseClassColor = v
                    if CludesUI._combatAlertPreview then CludesUI._combatAlertPreview("leave") end
                  end },
            },
            footer = { unlockKey = "CUI_CombatAlert" },
            gap = 9, disabled = caOff, disabledTooltip = "Combat Alert",
        })
    end


    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(row1._rightRegion, {
            title = "Potion Ready Alert Settings",
            minWidth = 300,
            rows = AlertCogRows("potionAlert", "_potionAlertFrame", "_potionAlertPreview"),
            footer = { unlockKey = "CUI_CombatAlert" },
            gap = 9,
            disabled = function() return not (CludesUIDB and CludesUIDB.potionAlertEnabled) end,
            disabledTooltip = "Potion Ready Alert",
        })
        CludesUI.BuildInlineCog(row2._leftRegion, {
            title = "Unspent Talents Alert Settings",
            minWidth = 300,
            rows = AlertCogRows("talentAlert", "_talentAlertFrame", "_talentAlertPreview"),
            footer = { unlockKey = "CUI_CombatAlert" },
            gap = 9,
            disabled = function() return not (CludesUIDB and CludesUIDB.talentAlertEnabled) end,
            disabledTooltip = "Unspent Talents Alert",
        })

        -- Inline cog (Text Size, Sound) on the Announce Group Deaths toggle
        local function deathOff()
            return not (CludesUIDB and CludesUIDB.announceGroupDeaths)
        end

        -- Sound dropdown: the group death sounds with a click-to-preview
        -- speaker icon on each row.
        local gdSoundValues, gdSoundOrder = CludesUI.BuildSoundDropdownValues()

        CludesUI.BuildInlineCog(row2._rightRegion, {
            title = "Group Death Alert Settings",
            rows = {
                { type="slider", label="Text Size",
                  min=14, max=64, step=1,
                  get=function()
                    return (CludesUIDB and CludesUIDB.groupDeathTextSize) or 34
                  end,
                  set=function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.groupDeathTextSize = v
                    if CludesUI._applyGroupDeathAlert then CludesUI._applyGroupDeathAlert() end
                    if CludesUI._groupDeathShowVisual then CludesUI._groupDeathShowVisual() end
                  end },
                { type="dropdown", label="Sound",
                  values=gdSoundValues, order=gdSoundOrder,
                  get=function()
                    return (CludesUIDB and CludesUIDB.groupDeathSoundKey) or "none"
                  end,
                  set=function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.groupDeathSoundKey = v
                    if v ~= "none" and CludesUI._groupDeathPlaySound then
                        CludesUI._groupDeathPlaySound()
                    end
                  end },
            },
            gap = 9, disabled = deathOff, disabledTooltip = "Announce Group Deaths",
        })
    end

    _, h = W:Spacer(parent, y, 20); y = y - h

    return math.abs(y - yOffset)
end
