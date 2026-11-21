if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_UnlockMode_Filter.lua
--  Unlock Mode element filter: which overlays a typed filter keeps. The box
--  itself is on the toolbar (CUI_UnlockMode_Bar.lua), which calls
--  UM.FilterSet(text) as the text changes and UM.FilterReset() when it hides.
--  Typing hides every overlay whose name lacks one of the typed words; the
--  real frames are never touched. Not saved: hiding the banner clears it.
--  Loaded after CUI_UnlockMode_Session.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
CUI_NS.unlockParts = CUI_NS.unlockParts or {}

-- Filter text -> lower-case words, nil when there are none.
local function ParseFilter(textValue)
    if type(textValue) ~= "string" then return nil end
    local words
    for wid in textValue:lower():gmatch("%S+") do
        words = words or {}
        words[#words + 1] = wid
    end
    return words
end

local function HasAllWords(words, name)
    if type(name) ~= "string" or name == "" then return false end
    name = name:lower()
    for idx = 1, #words do
        if not name:find(words[idx], 1, true) then return false end
    end
    return true
end

-- True when the filter keeps an element: no words, or every word (a plain
-- substring, any case) in its label or in the label as shown (translated).
local function FilterKeeps(words, labelText)
    if not words then return true end
    if HasAllWords(words, labelText) then return true end
    local isShown = CUI.L(labelText)
    return isShown ~= labelText and HasAllWords(words, isShown) or false
end

CUI_NS.unlockParts.Filter = function(LM)
    local movers, blizzOverlays = LM.movers, LM._blizzOwnedOverlays

    local words, lastKey = nil, ""

    local function Hides(key) return words ~= nil and not FilterKeeps(words, LM.GetBarLabel(key)) end
    LM.FilterHides = Hides -- ghost sync (CUI_UnlockMode_Positions.lua)

    -- Mover OnShow hook (CreateMover): every show path ends here.
    function LM.FilterOnShow(m)
        if words and Hides(m._barKey) then m:Hide() end
    end

    -- As the Shift+Right Click hide, without its session flag.
    local function HideMover(m)
        m._hoverPending = false
        if LM.selectedMover == m then LM.DeselectMover() end
        if LM.hoveredMover == m then LM.hoveredMover = nil end
        if m._hideOverlayText then m._hideOverlayText() end
        if m._cogBtn then m._cogBtn:Hide() end
        m:Hide()
    end

    local function Apply()
        if not LM.isUnlocked then return end
        -- A pick mode survives the filter (it helps find the target) unless its own mover hides.
        if LM.pickModeMover and LM.pickMode and Hides(LM.pickModeMover._barKey) then LM.CancelPickMode() end
        if LM.selectElementPicker and Hides(LM.selectElementPicker._barKey) then LM.CancelPickMode() end
        local alpha = LM.darkOverlaysEnabled and 1 or LM.MOVER_ALPHA
        for _, m in pairs(movers) do
            if Hides(m._barKey) then
                if m:IsShown() then HideMover(m) end
            elseif not m:IsShown() and not m._tempHidden then
                m:Sync()
                if m:IsShown() then m:SetAlpha(alpha) end
            end
        end
        for labelText, shade in pairs(blizzOverlays) do
            if words and not FilterKeeps(words, labelText) then
                if shade:IsShown() then
                    shade._forceCollapse()
                    shade:Hide()
                    shade._filterHidden = true
                end
            elseif shade._filterHidden then
                shade._filterHidden = nil
                if not shade._tempHidden then
                    shade:SetAlpha(1)
                    shade:Show()
                end
            end
        end
        -- Ghosts hide themselves in their sync; a refresh brings the kept ones back.
        if CUI._RefreshFallbackGhosts then CUI._RefreshFallbackGhosts() end
        if CUI._RefreshOverrideGhosts then CUI._RefreshOverrideGhosts() end
        -- Resting alpha: one hidden during the open fade-in missed its ramp (a running fade resets it).
        if CUI._SetFallbackGhostsAlpha then CUI._SetFallbackGhostsAlpha(1) end
        if CUI._SetOverrideGhostsAlpha then CUI._SetOverrideGhostsAlpha(1) end
    end

    -- The toolbar's box: applies the typed text and says whether a filter is set.
    function LM.FilterSet(textValue)
        local wid = ParseFilter(textValue)
        local key = wid and table.concat(wid, " ") or ""
        if key ~= lastKey then
            words, lastKey = wid, key
            Apply()
        end
        return words ~= nil
    end

    -- The toolbar hid (Layout Mode closed, or a combat pause): forget the filter.
    function LM.FilterReset()
        words, lastKey = nil, ""
        for _, shade in pairs(blizzOverlays) do
            shade._filterHidden = nil
        end
    end
end
