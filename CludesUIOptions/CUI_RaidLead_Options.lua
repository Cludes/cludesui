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

    ---------------------------------------------------------------------------
    --  Aura Sounds page
    ---------------------------------------------------------------------------
    local PAGE_SOUNDS = "Aura Sounds"

    local function Rebuild()
        ns.RebuildAuraSounds()
        CludesUI:InvalidatePageCache()
        CludesUI:RefreshPage(true)
    end

    local soundValues, soundOrder = {}, {}
    for _, f in ipairs(ns.SOUND_FILES) do
        soundValues[f] = f:gsub("%.%a+$", ""):gsub("(%l)(%u)", "%1 %2")
        soundOrder[#soundOrder + 1] = f
    end
    local whenValues, whenOrder = {}, {}
    for _, w in ipairs(ns.SOUND_WHEN) do
        whenValues[w.id] = w.label
        whenOrder[#whenOrder + 1] = w.id
    end

    local function SpellName(id)
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        if type(name) == "string" and name ~= "" then return name end
        return "Spell " .. id
    end

    local function BuildSoundsPage(_, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h
        local list = ns.RaidLeadDB().sounds

        CludesUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "AURA SOUNDS", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "input", text = "Add a Spell ID", inputStyle = "popup", placeholder = "Spell ID", inputWidth = 110,
              tooltip = "The spell ID of a buff or debuff that lands on you. It plays a siren when applied; change that below. The game plays these itself, so they work in boss fights.",
              getValue = function() return "" end,
              setValue = function(text)
                  local id = tonumber(text)
                  if not id or id <= 0 then return end
                  list[#list + 1] = { id = math.floor(id), when = "added", sound = "WarningSiren.ogg", on = true }
                  Rebuild()
              end },
            { type = "label", text = "" }
        );  y = y - h

        for i, e in ipairs(list) do
            local name = SpellName(e.id)
            _, h = W:SectionHeader(parent, name:upper(), y);  y = y - h
            _, h = W:DualRow(parent, y,
                { type = "toggle", text = "Play a Sound for " .. name, tooltip = "Spell ID " .. e.id,
                  getValue = function() return e.on ~= false end,
                  setValue = function(v) e.on = v and true or false; ns.RebuildAuraSounds() end },
                { type = "dropdown", text = "Play When", values = whenValues, order = whenOrder,
                  getValue = function() return e.when or "added" end,
                  setValue = function(v) e.when = v; ns.RebuildAuraSounds() end }
            );  y = y - h
            _, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Sound", values = soundValues, order = soundOrder,
                  getValue = function() return e.sound or "WarningSiren.ogg" end,
                  setValue = function(v) e.sound = v; ns.PreviewSound(v); ns.RebuildAuraSounds() end },
                { type = "labeledButton", text = "Remove This Sound", buttonText = "Remove", width = 90,
                  onClick = function() table.remove(list, i); Rebuild() end }
            );  y = y - h
        end

        return math.abs(y)
    end

    CludesUI:RegisterModule(ADDON_NAME, {
        title       = "Raid Lead",
        description = "Tools for raid leaders: sort or split the raid, and sounds for auras on you.",
        pages       = { PAGE, PAGE_SOUNDS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE then return BuildPage(pageName, parent, yOffset) end
            if pageName == PAGE_SOUNDS then return BuildSoundsPage(pageName, parent, yOffset) end
        end,
    })
end)
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
