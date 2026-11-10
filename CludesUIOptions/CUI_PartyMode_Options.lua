if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_PartyMode_Options.lua
--  Party Mode options page for CludesUI
--  Shared across all CludesUI addons -- only the first to load runs.
--  DEFERRED: body runs on first CludesUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
if _G._CludesUIPartyModeOptionsLoaded then return end
_G._CludesUIPartyModeOptionsLoaded = true

local CludesUI = _G.CludesUI
CludesUI._deferredInits[#CludesUI._deferredInits + 1] = function()
-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

-- EnsureLoaded runs after PLAYER_LOGIN, so execute the init body directly.
do

    if not CludesUI or not CludesUI.RegisterModule then return end
    local PP = CludesUI.PanelPP

    local PAGE_PARTY = "Party Mode"
    local PAGE_AFK   = "AFK"
    local PAGE_HOROSCOPE = "Should I Raid Tonight?"

    ---------------------------------------------------------------------------
    --  Build the Party Mode page
    ---------------------------------------------------------------------------
    local function BuildPartyModePage(pageName, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h

        -------------------------------------------------------------------
        --  Activate / Deactivate button
        -------------------------------------------------------------------
        local activateBtnFrame, activateBtnLbl
        activateBtnFrame, h = W:WideButton(parent,
            (CludesUIDB and CludesUIDB.partyMode) and "Deactivate Party Mode" or "Activate Party Mode",
            y,
            function()
                if CludesUI_TogglePartyMode then CludesUI_TogglePartyMode() end
                -- Update label after toggle
                if activateBtnLbl then
                    activateBtnLbl:SetText(
                        (CludesUIDB and CludesUIDB.partyMode) and CludesUI.L("Deactivate Party Mode") or CludesUI.L("Activate Party Mode")
                    )
                end
            end
        );  y = y - h
        -- Grab the label FontString from the button child: the SHOWN button and
        -- label (a pooled row also holds the hidden children and regions an
        -- earlier dress left there, so the first child is not necessarily it).
        if not CludesUI._prebuilding then
            local btn
            for _, c in ipairs({ activateBtnFrame:GetChildren() }) do
                if c:IsShown() and c:IsObjectType("Button") then btn = c; break end
            end
            if btn then
                for _, rgn in ipairs({ btn:GetRegions() }) do
                    if rgn:IsShown() and rgn:IsObjectType("FontString") and rgn:GetText() then
                        activateBtnLbl = rgn
                        break
                    end
                end
            end
        end
        -- Keep label in sync if toggled via keybind while panel is open
        if activateBtnLbl then
            CludesUI.RegisterWidgetRefresh(function()
                activateBtnLbl:SetText(
                    (CludesUIDB and CludesUIDB.partyMode) and CludesUI.L("Deactivate Party Mode") or CludesUI.L("Activate Party Mode")
                )
            end)
        end

        -------------------------------------------------------------------
        --  PARTY MODE (disco lights overlay)
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "PARTY MODE", y);  y = y - h

        -- Row 1: Toggle Keybind (full-width custom row)
        do
            local ROW_H = 50
            local SIDE_PAD = 20
            local kbFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - CludesUI.CONTENT_PAD * 2
            PP.Size(kbFrame, totalW, ROW_H)
            PP.Point(kbFrame, "TOPLEFT", parent, "TOPLEFT", CludesUI.CONTENT_PAD, y)
            CludesUI.RowBg(kbFrame, parent)

            local label = CludesUI.MakeFont(kbFrame, 14, nil, CludesUI.TEXT_WHITE_R, CludesUI.TEXT_WHITE_G, CludesUI.TEXT_WHITE_B)
            PP.Point(label, "LEFT", kbFrame, "LEFT", SIDE_PAD, 0)
            label:SetText(CludesUI.L("Toggle On/Off Keybind"))

            local kbBtn, refresh = CludesUI.BuildKeybindButton(kbFrame, {
                w = 140, h = 30, font = 13,
                get = function() return CludesUIDB and CludesUIDB.partyModeKey end,
                set = function(fullKey)
                    if not CludesUIDB then CludesUIDB = {} end
                    if fullKey then
                        ClearOverrideBindings(CludesUIPartyModeBindBtn)
                        SetOverrideBindingClick(CludesUIPartyModeBindBtn, true, fullKey, "CludesUIPartyModeBindBtn")
                    elseif CludesUIDB.partyModeKey then
                        ClearOverrideBindings(CludesUIPartyModeBindBtn)
                    end
                    CludesUIDB.partyModeKey = fullKey
                end,
            })
            PP.Point(kbBtn, "RIGHT", kbFrame, "RIGHT", -SIDE_PAD, 0)
            CludesUI.RegisterWidgetRefresh(refresh)

            y = y - ROW_H
        end

        -- Row 2: Brightness slider (full-width)
        do
            local ROW_H = 50
            local SIDE_PAD = 20
            local frame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - CludesUI.CONTENT_PAD * 2
            PP.Size(frame, totalW, ROW_H)
            PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CludesUI.CONTENT_PAD, y)
            CludesUI.RowBg(frame, parent)

            local label = CludesUI.MakeFont(frame, 14, nil, CludesUI.TEXT_WHITE_R, CludesUI.TEXT_WHITE_G, CludesUI.TEXT_WHITE_B)
            PP.Point(label, "LEFT", frame, "LEFT", SIDE_PAD, 0)
            label:SetText(CludesUI.L("Brightness"))

            local function briGet()
                local db = CludesUIDB
                local v = db and db.partyModeBrightness
                if v == nil then v = 0.65 end
                return math.floor(v * 100 + 0.5)
            end
            local function briSet(v)
                if not CludesUIDB then CludesUIDB = {} end
                CludesUIDB.partyModeBrightness = v / 100
            end

            local trackFrame, valBox = CludesUI.BuildSliderCore(frame, 160, 4, 14, 40, 26, 13, CludesUI.SL_INPUT_A,
                0, 100, 1, briGet, briSet, false)
            PP.Point(valBox, "RIGHT", frame, "RIGHT", -SIDE_PAD, 0)
            PP.Point(trackFrame, "RIGHT", valBox, "LEFT", -12, 0)

            y = y - ROW_H
        end

        -- Row 3: Dim the Lights While Active (toggle)
        _, h = W:Toggle(parent, "Dim the Lights While Active", y,
            function() return CludesUIDB and (CludesUIDB.partyModeDimLights ~= false) end,
            function(v)
                if not CludesUIDB then CludesUIDB = {} end
                CludesUIDB.partyModeDimLights = v
                -- Live apply/restore if party mode is currently active
                if CludesUIDB.partyMode then
                    if v and not CludesUI_IsDimLightsActive() then
                        CludesUI_ApplyDimLights()
                    elseif not v and CludesUI_IsDimLightsActive() then
                        CludesUI_RestoreDimLights()
                    end
                end
            end,
            nil
        );  y = y - h

        -- Row 3b: Spinning (checkbox dropdown + speed cog). Full-width row
        -- (nil right slot expands the left region), matching the rest of
        -- this section. Each target's spin lives in its own module; this page
        -- owns only the shared CludesUIDB keys, so a target whose addon is
        -- disabled is a harmless no-op. partyModeSpinBars is a boolean (Action
        -- Bars only) or a per-target table: CludesUI.PartySpinOn reads
        -- both and CludesUI.PartySpinSet turns a boolean into the table on
        -- its first write, with the same meaning. One speed drives every target.
        do
            local SPIN_ITEMS = {
                { key = "actionBars", label = "Action Bars" },
                { key = "dataBars",   label = "Data Bars" },
                { key = "unitFrames", label = "Unit Frames" },
                { key = "resource",   label = "Resource Bars" },
                { key = "power",      label = "Power Bars" },
                { key = "partyFrames", label = "Party Frames" },
                { key = "raidFrames",  label = "Raid Frames" },
            }
            local spinRow
            spinRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Spinning",
                  tooltip="Orbits the checked elements while Party Mode is active.",
                  values={ ["_placeholder"]="..." }, order={ "_placeholder" },
                  getValue=function() return "_placeholder" end,
                  setValue=function() end },
                nil
            );  y = y - h
            if not CludesUI._prebuilding then
                local rgn = spinRow._leftRegion
                if rgn._control then rgn._control:Hide() end
                local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                    rgn, 200, rgn:GetFrameLevel() + 2,
                    SPIN_ITEMS,
                    -- The setting itself, whether or not Party Mode is on.
                    function(k) return CludesUI.PartySpinOn(k, true) end,
                    function(k, v)
                        CludesUI.PartySpinSet(k, v)
                        CludesUI.PartySpin_RefreshAll()
                    end)
                PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                rgn._control = cbDD
                rgn._lastInline = nil
                CludesUI.RegisterWidgetRefresh(cbDDRefresh)
                CludesUI.BuildInlineCog(rgn, {
                    title = "Spin",
                    rows = {
                        { type="slider", label="Speed", min=0, max=720, step=10,
                          tooltip="Degrees per second. 360 is one full turn a second; 0 parks the bars where they are.",
                          get=function()
                              local v = CludesUIDB and CludesUIDB.partyModeSpinSpeed
                              if v == nil then v = 120 end
                              return v
                          end,
                          set=function(v)
                              if not CludesUIDB then CludesUIDB = {} end
                              CludesUIDB.partyModeSpinSpeed = v
                              CludesUI.PartySpin_RefreshAll()
                          end },
                    },
                })
            end
        end

        -- Row 4: Play Sound on Party Mode (dropdown; shares the whisper
        -- alert catalogue incl. SharedMedia, with per-item preview icons)
        do
            local sndPaths, sndNames, sndOrder = {}, { none = "None" }, { "none" }
            if CludesUI_GetPartyModeSounds then
                sndPaths, sndNames, sndOrder = CludesUI_GetPartyModeSounds()
            end
            -- Shallow-copy the shared names table so _menuOpts (preview
            -- icon) doesn't pollute it.
            local sndValues = {}
            for k, v in pairs(sndNames) do sndValues[k] = v end
            sndValues._menuOpts = {
                itemHeight = 26,
                maxTextWidthPct = 0.8,
                searchable = true,
                iconAtlas = function(key)
                    if key == "none" then return nil end
                    if not sndPaths[key] then return nil end
                    return CludesUI.SOUND_ICON_ATLAS
                end,
                iconPressedAtlas = function(key)
                    if key == "none" then return nil end
                    return CludesUI.SOUND_ICON_PRESSED_ATLAS
                end,
                iconOnClick = function(key)
                    local path = sndPaths[key]
                    if path then PlaySoundFile(path, "Master") end
                end,
                iconTooltip = function() return "Preview Sound" end,
            }
            _, h = W:Dropdown(parent, "Play Sound on Party Mode", y, sndValues,
                function() return (CludesUIDB and CludesUIDB.partyModeSoundKey) or "none" end,
                function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.partyModeSoundKey = v
                end,
                sndOrder)
            y = y - h
        end

        -------------------------------------------------------------------
        --  CELEBRATION TRIGGERS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CELEBRATION TRIGGERS", y);  y = y - h

        -- Helper: set a trigger DB key and refresh widgets
        local function TriggerSet(key)
            return function(v)
                if not CludesUIDB then CludesUIDB = {} end
                CludesUIDB[key] = v
                local rl = CludesUI._widgetRefreshList
                if rl then for i = 1, #rl do rl[i]() end end
            end
        end
        local function TriggerGet(key)
            return function() return CludesUIDB and CludesUIDB[key] or false end
        end

        local CB_SPLITS = { 0.333, 0.333, 0.334, rowHeight = 36 }
        local randomlyCheckbox = { type = "checkbox", text = "Randomly", getValue = TriggerGet("partyModeTriggerRandom"), setValue = function(v)
            if not CludesUIDB then CludesUIDB = {} end
            CludesUIDB.partyModeTriggerRandom = v
            if v then
                CludesUI_StartRandomTrigger()
            else
                CludesUI_StopRandomTrigger()
            end
            local rl = CludesUI._widgetRefreshList
            if rl then for i = 1, #rl do rl[i]() end end
        end }
        -- Bloodlust is debuff-triggered with a hardcoded 40s celebration; it is
        -- intentionally NOT wired into the Auto Celebration Duration slider, so
        -- it has its own setValue rather than the shared TriggerSet.
        local bloodlustCheckbox = { type = "checkbox", text = "Bloodlust",
            getValue = TriggerGet("partyModeTriggerBloodlust"),
            setValue = function(v)
                if not CludesUIDB then CludesUIDB = {} end
                CludesUIDB.partyModeTriggerBloodlust = v
                if CludesUI_UpdatePartyModeLustListener then CludesUI_UpdatePartyModeLustListener() end
                local rl = CludesUI._widgetRefreshList
                if rl then for i = 1, #rl do rl[i]() end end
            end }
        local levelUpCheckbox = { type = "checkbox", text = "Level Up",
            getValue = TriggerGet("partyModeTriggerLevelUp"),
            setValue = function(v)
                if not CludesUIDB then CludesUIDB = {} end
                CludesUIDB.partyModeTriggerLevelUp = v
                if CludesUI_UpdatePartyModeLevelUpListener then CludesUI_UpdatePartyModeLevelUpListener() end
                local rl = CludesUI._widgetRefreshList
                if rl then for i = 1, #rl do rl[i]() end end
            end }

        if CludesUI.IS_FOREVER then
            -- WoW Forever has no keystones, no rated PvP, no Sated or Exhaustion
            -- debuffs for the Bloodlust trigger and no Mythic, Heroic or Raid
            -- Finder difficulties, and its vanilla raids report difficulty 9 or
            -- 148, which no boss kill trigger maps. Show only what can fire there.
            _, h = W:TripleRow(parent, y,
                randomlyCheckbox, levelUpCheckbox, nil,
                CB_SPLITS
            );  y = y - h
        else
            -- Row 1: Randomly | Timed Keystone | Mythic Boss Kill
            _, h = W:TripleRow(parent, y,
                randomlyCheckbox,
                { type = "checkbox", text = "Timed Keystone",     getValue = TriggerGet("partyModeTriggerKeystone"),   setValue = TriggerSet("partyModeTriggerKeystone") },
                { type = "checkbox", text = "Mythic Boss Kill",   getValue = TriggerGet("partyModeTriggerMythicBoss"), setValue = TriggerSet("partyModeTriggerMythicBoss") },
                CB_SPLITS
            );  y = y - h

            -- Row 2: Rated Arena Win | Rated BG Win | Heroic Boss Kill
            _, h = W:TripleRow(parent, y,
                { type = "checkbox", text = "Rated Arena Win",    getValue = TriggerGet("partyModeTriggerRatedArena"), setValue = TriggerSet("partyModeTriggerRatedArena") },
                { type = "checkbox", text = "Rated BG Win",       getValue = TriggerGet("partyModeTriggerRatedBG"),    setValue = TriggerSet("partyModeTriggerRatedBG") },
                { type = "checkbox", text = "Heroic Boss Kill",   getValue = TriggerGet("partyModeTriggerHeroicBoss"), setValue = TriggerSet("partyModeTriggerHeroicBoss") },
                CB_SPLITS
            );  y = y - h

            -- Row 3: Normal Boss Kill | Raid Finder Boss Kill | Mythic 0 Completion
            _, h = W:TripleRow(parent, y,
                { type = "checkbox", text = "Normal Boss Kill",       getValue = TriggerGet("partyModeTriggerNormalBoss"),  setValue = TriggerSet("partyModeTriggerNormalBoss") },
                { type = "checkbox", text = "Raid Finder Boss Kill",  getValue = TriggerGet("partyModeTriggerLFRBoss"),     setValue = TriggerSet("partyModeTriggerLFRBoss") },
                { type = "checkbox", text = "Mythic 0 Completion",    getValue = TriggerGet("partyModeTriggerMythic0"),     setValue = TriggerSet("partyModeTriggerMythic0") },
                CB_SPLITS
            );  y = y - h

            -- Row 4: Bloodlust | Level Up
            _, h = W:TripleRow(parent, y,
                bloodlustCheckbox, levelUpCheckbox, nil,
                CB_SPLITS
            );  y = y - h
        end

        -- Bottom border for the checkbox grid (matches SectionHeader separator style)
        -- Placed 1px above current y so the next row's background doesn't cover it
        do
            local totalW = parent:GetWidth() - CludesUI.CONTENT_PAD * 2
            local sep = parent:CreateTexture(nil, "ARTWORK", nil, 7)
            sep:SetColorTexture(CludesUI.BORDER_R, CludesUI.BORDER_G, CludesUI.BORDER_B, 0.02)
            PP.Size(sep, totalW, 1)
            PP.Point(sep, "TOPLEFT", parent, "TOPLEFT", CludesUI.CONTENT_PAD, y + 1)
        end

        -- Celebration Trigger Duration slider (conditionally enabled)
        local durFrame
        do
            local function AnyCelebrationTriggerEnabled()
                if not CludesUIDB then return false end
                return CludesUIDB.partyModeTriggerKeystone
                    or CludesUIDB.partyModeTriggerMythicBoss
                    or CludesUIDB.partyModeTriggerHeroicBoss
                    or CludesUIDB.partyModeTriggerNormalBoss
                    or CludesUIDB.partyModeTriggerLFRBoss
                    or CludesUIDB.partyModeTriggerMythic0
                    or CludesUIDB.partyModeTriggerRatedBG
                    or CludesUIDB.partyModeTriggerRatedArena
                    or CludesUIDB.partyModeTriggerLevelUp
                    or CludesUIDB.partyModeTriggerRandom
                    or false
            end

            durFrame, h = W:Slider(parent, "Auto Celebration Duration", y, 10, 60, 1,
                function()
                    local db = CludesUIDB
                    local v = db and db.partyModeMPlusDuration
                    if v == nil then v = 30 end
                    return v
                end,
                function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.partyModeMPlusDuration = v
                end,
                nil
            );  y = y - h

            -- Add "(seconds)" suffix in smaller, dimmer text
            if not CludesUI._prebuilding then
                local suffix = durFrame:CreateFontString(nil, "OVERLAY")
                suffix:SetFont(CludesUI.EXPRESSWAY, 11, "")
                suffix:SetTextColor(1, 1, 1, 0.35)
                local durLabel
                local regions = { durFrame:GetRegions() }
                for i = 1, #regions do
                    local reg = regions[i]
                    if reg and reg.GetText and CludesUI.EnKey(reg:GetText()) == "Auto Celebration Duration" then
                        durLabel = reg
                        break
                    end
                end
                if durLabel then
                    -- Anchor to the END OF THE TEXT, not the region's right
                    -- edge: ClampRowLabel stretches full-width row labels to
                    -- the slider track, so "RIGHT" sits at the track edge.
                    suffix:SetPoint("LEFT", durLabel, "LEFT", durLabel:GetStringWidth() + 5, 0)
                else
                    suffix:SetPoint("LEFT", durFrame, "LEFT", 250, 0)
                end
                suffix:SetText(CludesUI.L("(seconds)"))
            end

            local function RefreshDurDisabled()
                local enabled = AnyCelebrationTriggerEnabled()
                durFrame:SetAlpha(enabled and 1 or 0.35)
                durFrame:EnableMouse(enabled)
            end
            RefreshDurDisabled()
            CludesUI.RegisterWidgetRefresh(RefreshDurDisabled)

            -- Disabled tooltip for duration slider (split: label zone + control zone)
            if not CludesUI._prebuilding then
                -- Find the label and slider control regions
                local durLabel, durControl
                local regions = { durFrame:GetRegions() }
                for i = 1, #regions do
                    local reg = regions[i]
                    if reg and reg.GetText and CludesUI.EnKey(reg:GetText()) == "Auto Celebration Duration" then
                        durLabel = reg
                        break
                    end
                end

                -- Label hit zone (left half)
                local durHitLabel = CreateFrame("Frame", nil, durFrame)
                durHitLabel:SetFrameLevel(durFrame:GetFrameLevel() + 10)
                durHitLabel:EnableMouse(false)
                if durLabel then
                    durHitLabel:SetPoint("TOPLEFT", durFrame, "TOPLEFT", 0, 0)
                    durHitLabel:SetPoint("BOTTOMLEFT", durFrame, "BOTTOMLEFT", 0, 0)
                    durHitLabel:SetWidth(durFrame:GetWidth() * 0.5)
                end
                durHitLabel:SetScript("OnEnter", function(self)
                    if not AnyCelebrationTriggerEnabled() then
                        CludesUI.ShowWidgetTooltip(self, CludesUI.DisabledTooltip("at least one Celebration Trigger"))
                    end
                end)
                durHitLabel:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)

                -- Control hit zone (right half)
                local durHitControl = CreateFrame("Frame", nil, durFrame)
                durHitControl:SetFrameLevel(durFrame:GetFrameLevel() + 10)
                durHitControl:EnableMouse(false)
                durHitControl:SetPoint("TOPRIGHT", durFrame, "TOPRIGHT", 0, 0)
                durHitControl:SetPoint("BOTTOMRIGHT", durFrame, "BOTTOMRIGHT", 0, 0)
                durHitControl:SetWidth(durFrame:GetWidth() * 0.5)
                durHitControl:SetScript("OnEnter", function(self)
                    if not AnyCelebrationTriggerEnabled() then
                        CludesUI.ShowWidgetTooltip(self, CludesUI.DisabledTooltip("at least one Celebration Trigger"))
                    end
                end)
                durHitControl:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)

                local function UpdateDurHit()
                    local dis = not AnyCelebrationTriggerEnabled()
                    durHitLabel:EnableMouse(dis)
                    durHitControl:EnableMouse(dis)
                end
                UpdateDurHit()
                CludesUI.RegisterWidgetRefresh(UpdateDurHit)
            end

            -- Random cooldown slider (grayed out unless random trigger is enabled)
            local cdFrame
            cdFrame, h = W:Slider(parent, "Random Celebrations Minimum Cooldown", y, 1, 30, 1,
                function()
                    local db = CludesUIDB
                    local v = db and db.partyModeRandomCooldown
                    if v == nil then v = 10 end
                    return v
                end,
                function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.partyModeRandomCooldown = v
                end,
                nil
            );  y = y - h

            -- Add "(minutes)" suffix in smaller, dimmer text
            if not CludesUI._prebuilding then
                local suffix = cdFrame:CreateFontString(nil, "OVERLAY")
                suffix:SetFont(CludesUI.EXPRESSWAY, 11, "")
                suffix:SetTextColor(1, 1, 1, 0.35)
                local cdLabel
                local regions = { cdFrame:GetRegions() }
                for i = 1, #regions do
                    local reg = regions[i]
                    if reg and reg.GetText and CludesUI.EnKey(reg:GetText()) == "Random Celebrations Minimum Cooldown" then
                        cdLabel = reg
                        break
                    end
                end
                if cdLabel then
                    -- Same text-end anchoring as the duration suffix above.
                    suffix:SetPoint("LEFT", cdLabel, "LEFT", cdLabel:GetStringWidth() + 5, 0)
                else
                    suffix:SetPoint("LEFT", cdFrame, "LEFT", 350, 0)
                end
                suffix:SetText(CludesUI.L("(minutes)"))
            end

            local function RefreshCdDisabled()
                local enabled = CludesUIDB and CludesUIDB.partyModeTriggerRandom or false
                cdFrame:SetAlpha(enabled and 1 or 0.35)
                cdFrame:EnableMouse(enabled)
            end
            RefreshCdDisabled()
            CludesUI.RegisterWidgetRefresh(RefreshCdDisabled)

            -- Disabled tooltip for cooldown slider (split: label zone + control zone)
            if not CludesUI._prebuilding then
                local cdLabel
                local regions = { cdFrame:GetRegions() }
                for i = 1, #regions do
                    local reg = regions[i]
                    if reg and reg.GetText and CludesUI.EnKey(reg:GetText()) == "Random Celebrations Minimum Cooldown" then
                        cdLabel = reg
                        break
                    end
                end

                -- Label hit zone (left half)
                local cdHitLabel = CreateFrame("Frame", nil, cdFrame)
                cdHitLabel:SetFrameLevel(cdFrame:GetFrameLevel() + 10)
                cdHitLabel:EnableMouse(false)
                if cdLabel then
                    cdHitLabel:SetPoint("TOPLEFT", cdFrame, "TOPLEFT", 0, 0)
                    cdHitLabel:SetPoint("BOTTOMLEFT", cdFrame, "BOTTOMLEFT", 0, 0)
                    cdHitLabel:SetWidth(cdFrame:GetWidth() * 0.5)
                end
                cdHitLabel:SetScript("OnEnter", function(self)
                    local enabled = CludesUIDB and CludesUIDB.partyModeTriggerRandom or false
                    if not enabled then
                        CludesUI.ShowWidgetTooltip(self, CludesUI.DisabledTooltip("the Randomly trigger"))
                    end
                end)
                cdHitLabel:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)

                -- Control hit zone (right half)
                local cdHitControl = CreateFrame("Frame", nil, cdFrame)
                cdHitControl:SetFrameLevel(cdFrame:GetFrameLevel() + 10)
                cdHitControl:EnableMouse(false)
                cdHitControl:SetPoint("TOPRIGHT", cdFrame, "TOPRIGHT", 0, 0)
                cdHitControl:SetPoint("BOTTOMRIGHT", cdFrame, "BOTTOMRIGHT", 0, 0)
                cdHitControl:SetWidth(cdFrame:GetWidth() * 0.5)
                cdHitControl:SetScript("OnEnter", function(self)
                    local enabled = CludesUIDB and CludesUIDB.partyModeTriggerRandom or false
                    if not enabled then
                        CludesUI.ShowWidgetTooltip(self, CludesUI.DisabledTooltip("the Randomly trigger"))
                    end
                end)
                cdHitControl:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)

                local function UpdateCdHit()
                    local enabled = CludesUIDB and CludesUIDB.partyModeTriggerRandom or false
                    cdHitLabel:EnableMouse(not enabled)
                    cdHitControl:EnableMouse(not enabled)
                end
                UpdateCdHit()
                CludesUI.RegisterWidgetRefresh(UpdateCdHit)
            end
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Build the AFK page
    ---------------------------------------------------------------------------
    local function BuildAfkPage(pageName, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h
        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  AFK SCREEN
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "AFK SCREEN", y);  y = y - h

        local function AfkOff() return not (CludesUIDB and CludesUIDB.partyModeAfk) end
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Bouncing Logo When AFK",
              tooltip="Dims the screen and bounces the CUI logo around it while you are AFK. Click anywhere to dismiss. Type /afk to preview.",
              getValue=function() return not AfkOff() end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.partyModeAfk = v
                  CludesUI_UpdateAfkScreen()
                  CludesUI:RefreshPage()
              end },
            { type="slider", text="Logo Speed", min=50, max=1000, step=10,
              disabled=AfkOff, disabledTooltip="Bouncing Logo When AFK",
              getValue=function() return (CludesUIDB and CludesUIDB.partyModeAfkSpeed) or 150 end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.partyModeAfkSpeed = v
              end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Spin Logo",
              tooltip="Spins the logo while it bounces.",
              disabled=AfkOff, disabledTooltip="Bouncing Logo When AFK",
              getValue=function() return CludesUIDB and CludesUIDB.partyModeAfkSpin or false end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.partyModeAfkSpin = v
                  CludesUI_UpdateAfkScreen()
                  CludesUI:RefreshPage()
              end },
            { type="slider", text="Spin Speed", min=30, max=720, step=10,
              tooltip="Degrees per second. 360 is one full turn a second.",
              disabled=function() return AfkOff() or not CludesUIDB.partyModeAfkSpin end,
              disabledTooltip="Spin Logo",
              getValue=function() return (CludesUIDB and CludesUIDB.partyModeAfkSpinSpeed) or 180 end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.partyModeAfkSpinSpeed = v
                  CludesUI_UpdateAfkScreen()
              end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Horizontal Spin",
              tooltip="Spins the logo around its upright axis, like a flipped coin.",
              disabled=AfkOff, disabledTooltip="Bouncing Logo When AFK",
              getValue=function() return CludesUIDB and CludesUIDB.partyModeAfkFlip or false end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.partyModeAfkFlip = v
                  CludesUI_UpdateAfkScreen()
                  CludesUI:RefreshPage()
              end },
            { type="slider", text="Horizontal Spin Speed", min=30, max=720, step=10,
              tooltip="Degrees per second. 360 is one full turn a second.",
              disabled=function() return AfkOff() or not CludesUIDB.partyModeAfkFlip end,
              disabledTooltip="Horizontal Spin",
              getValue=function() return (CludesUIDB and CludesUIDB.partyModeAfkFlipSpeed) or 180 end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.partyModeAfkFlipSpeed = v
                  CludesUI_UpdateAfkScreen()
              end }
        );  y = y - h

        local cornerRow
        cornerRow, h = W:DualRow(parent, y,
            { type="toggle", text="Party Lights on Corner Hit",
              tooltip="Starts Party Mode whenever the logo lands in a corner. Set how long it lasts with the cog.",
              disabled=AfkOff, disabledTooltip="Bouncing Logo When AFK",
              getValue=function() return CludesUIDB and CludesUIDB.partyModeAfkCorner or false end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.partyModeAfkCorner = v
                  CludesUI:RefreshPage()
              end },
            { type="slider", text="Corner Odds", min=5, max=50, step=5,
              tooltip="How easily a bounce counts as a corner. Lower is rarer.",
              disabled=function() return AfkOff() or not CludesUIDB.partyModeAfkCorner end,
              disabledTooltip="Party Lights on Corner Hit",
              getValue=function() return (CludesUIDB and CludesUIDB.partyModeAfkCornerSize) or 50 end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.partyModeAfkCornerSize = v
              end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type="slider", text="Logo Size", min=0.5, max=3.0, step=0.05,
              tooltip="Scales the logo and its text. Applies the next time the AFK screen shows.",
              disabled=AfkOff, disabledTooltip="Bouncing Logo When AFK",
              getValue=function() return (CludesUIDB and CludesUIDB.partyModeAfkScale) or 1 end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.partyModeAfkScale = v
              end },
            CludesUI.BlankRowCfg()
        );  y = y - h
        if not CludesUI._prebuilding then
            local function CornerOff() return AfkOff() or not CludesUIDB.partyModeAfkCorner end
            CludesUI.BuildInlineCog(cornerRow._leftRegion, {
                disabled = CornerOff, disabledTooltip = "Party Lights on Corner Hit",
                title = "Corner Party",
                rows = {
                    { type="slider", label="Duration", min=1, max=15, step=1,
                      tooltip="Seconds Party Mode runs after a corner hit.",
                      get=function() return (CludesUIDB and CludesUIDB.partyModeAfkCornerSecs) or 15 end,
                      set=function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.partyModeAfkCornerSecs = v
                      end },
                },
            })
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    CludesUI:RegisterModule("CludesUIPartyMode", {
        title       = "Party Mode",
        description = "Disco lights overlay for celebrations.",
        pages       = { PAGE_PARTY, PAGE_HOROSCOPE, PAGE_AFK },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_PARTY then
                return BuildPartyModePage(pageName, parent, yOffset)
            elseif pageName == PAGE_AFK then
                return BuildAfkPage(pageName, parent, yOffset)
            elseif pageName == PAGE_HOROSCOPE then
                return CludesUI._BuildRaidHoroscopePage(parent, yOffset)
            end
        end,
        resetScope  = "account",
        onReset     = function()
            -- Stop party mode (restores CVars if dimmed)
            if CludesUIDB and CludesUIDB.partyMode then
                CludesUIDB.partyMode = false
                CludesUI_StopPartyMode()
            end
            if CludesUIDB then
                CludesUIDB.partyMode = nil
                CludesUIDB.partyModeKey = nil
                CludesUIDB.partyModeMPlus = nil
                CludesUIDB.partyModeMPlusDuration = nil
                CludesUIDB.partyModeBrightness = nil
                CludesUIDB.partyModeTriggerKeystone = nil
                CludesUIDB.partyModeTriggerMythicBoss = nil
                CludesUIDB.partyModeTriggerHeroicBoss = nil
                CludesUIDB.partyModeTriggerNormalBoss = nil
                CludesUIDB.partyModeTriggerLFRBoss = nil
                CludesUIDB.partyModeTriggerMythic0 = nil
                CludesUIDB.partyModeTriggerBloodlust = nil
                CludesUIDB.partyModeTriggerLevelUp = nil
                CludesUIDB.partyModeTriggerRatedBG = nil
                CludesUIDB.partyModeTriggerRatedArena = nil
                CludesUIDB.partyModeTriggerRandom = nil
                CludesUIDB.partyModeRandomCooldown = nil
                CludesUIDB.partyModeDimLights = nil
                CludesUIDB.partyModeSoundKey = nil
                CludesUIDB.partyModeAfk = nil
                CludesUIDB.partyModeAfkSpeed = nil
                CludesUIDB.partyModeAfkSpin = nil
                CludesUIDB.partyModeAfkSpinSpeed = nil
                CludesUIDB.partyModeAfkCorner = nil
                CludesUIDB.partyModeAfkCornerSize = nil
                CludesUIDB.partyModeAfkCornerSecs = nil
                CludesUIDB.partyModeAfkScale = nil
                CludesUIDB.partyModeAfkFlip = nil
                CludesUIDB.partyModeAfkFlipSpeed = nil
                CludesUIDB.raidHoroscope = nil
            end
            CludesUI_UpdateAfkScreen()
            -- Stop random trigger timer
            CludesUI_StopRandomTrigger()
            -- Drop the Bloodlust and Level Up event listeners with their keys
            if CludesUI_UpdatePartyModeLustListener then CludesUI_UpdatePartyModeLustListener() end
            if CludesUI_UpdatePartyModeLevelUpListener then CludesUI_UpdatePartyModeLevelUpListener() end
            -- Clear any override bindings
            if CludesUIPartyModeBindBtn then
                ClearOverrideBindings(CludesUIPartyModeBindBtn)
            end
            CludesUI:SelectPage(PAGE_PARTY)
        end,
    })
end  -- end do block
end  -- end deferred init
