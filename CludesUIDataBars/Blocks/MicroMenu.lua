if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\MicroMenu.lua
-- Micro menu block factory and Blizzard micro menu hider.

local ADDON_NAME, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Upvalues
local _G = _G
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local GetTime = GetTime
local pairs = pairs
local ipairs = ipairs
local type = type
local pcall = pcall
local format = string.format
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local floor = math.floor
local max = math.max

local CONTENT_BASE = K.CONTENT_BASE
local InstKey = K.InstKey
local MakeEventFrame = K.MakeEventFrame
local RegisterInstEvents = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local MaybeRelayout = K.MaybeRelayout
local AttachTextOffset = K.AttachTextOffset
local BlockColorOf = K.BlockColorOf
local ParkSecureFrame = K.ParkSecureFrame

-------------------------------------------------------------------------------
--  MICROMENU (SECURE; three verbatim mechanisms)
--    1. Secure click-passthrough buttons (*clickbutton1 -> Blizzard button)
--    2. Combat lockout via RegisterStateDriver _onstate-combatlock snippet (never addon-Lua EnableMouse/SetAlpha on these frames post-creation)
--    3. Blizzard micro menu hider via SecureHandlerStateTemplate _onstate-vis (never :Hide() on MicroMenuContainer from insecure code)
-------------------------------------------------------------------------------
local MM_SPACING = 2
local MM_MEDIA = mod.MICROMENU_MEDIA

-- Button key -> icon file in CludesUI\media\micromenu\ (one PNG per button).
local MM_ICON_FILE = {
    menu = "menu-options",
    guild = "menu-guild",
    social = "menu-friends",
    char = "menu-character",
    spell = "menu-spellbook",
    ach = "menu-achievements",
    quest = "menu-quests",
    lfg = "menu-group",
    pvp = "menu-pvp",
    housing = "menu-housing",
    journal = "menu-adventure",
    pet = "menu-collections",
    shop = "menu-shop",
    help = "menu-cs",
}

local mmButtonDefs = {
    {
        key = "menu",
        binding = "TOGGLEGAMEMENU",
        label = MAINMENU_BUTTON,
        special = true,
    },
    { key = "guild", binding = "TOGGLEGUILD", label = GUILD, info = true },
    { key = "social", binding = "TOGGLESOCIAL", label = SOCIAL_LABEL or SOCIAL_BUTTON, info = true },
    { key = "char", binding = "TOGGLECHARACTER0", label = CHARACTER_BUTTON },
    -- Single combined button: PlayerSpellsMicroButton opens the merged
    -- Spec / Talents / Spellbook (and professions) frame.
    { key = "spell", binding = "TOGGLESPELLBOOK", label = "Spec / Talents / Spellbook", special = true },
    { key = "ach", binding = "TOGGLEACHIEVEMENT", label = ACHIEVEMENTS },
    { key = "quest", binding = "TOGGLEQUESTLOG", label = QUEST_LOG },
    { key = "lfg", binding = "TOGGLEGROUPFINDER", label = DUNGEONS_BUTTON },
    {
        key = "pvp",
        binding = "TOGGLECHARACTER4",
        label = PLAYER_V_PLAYER or PVP_OPTIONS or "PvP",
        special = true,
    },
    { key = "housing", binding = "TOGGLEHOUSINGDASHBOARD", label = HOUSING_MICRO_BUTTON or "Housing" },
    {
        key = "journal",
        binding = "TOGGLEENCOUNTERJOURNAL",
        label = ADVENTURE_JOURNAL,
        special = true,
    },
    { key = "pet", binding = "TOGGLECOLLECTIONS", label = COLLECTIONS },
    { key = "shop", binding = false, label = BLIZZARD_STORE },
    { key = "help", binding = false, label = HELP_BUTTON },
}
local mmButtonOrder = {}
local mmButtonDefsByKey = {}
for _, def in ipairs(mmButtonDefs) do
    mmButtonOrder[#mmButtonOrder + 1] = def.key
    mmButtonDefsByKey[def.key] = def
end

-- String names for Blizzard MicroButtons, resolved via _G at creation (first existing
-- global wins). Spellbook/talents/journal MUST open via a secure click on the micro
-- button -- addon-Lua opening taints the frame, and SetCooldown then rejects secrets inside Blizzard_SpellBookItem.
local MM_MICRO_BUTTON_NAMES = {
    guild = "GuildMicroButton",
    social = "QuickJoinToastButton",
    char = "CharacterMicroButton",
    spell = { "PlayerSpellsMicroButton", "SpellbookMicroButton" },
    journal = { "EJMicroButton" },
    ach = "AchievementMicroButton",
    quest = "QuestLogMicroButton",
    lfg = "LFDMicroButton",
    housing = "HousingMicroButton",
    pet = "CollectionsMicroButton",
    shop = "StoreMicroButton",
    help = "HelpMicroButton",
}

-- Native art is copied onto our textures; Blizzard's buttons are never modified.
local MM_BLIZZARD_ATLAS = {
    menu = "GameMenu",
    guild = "GuildCommunities",
    spell = "SpecTalents",
    talent = "SpecTalents",
    ach = "Achievements",
    quest = "Questlog",
    lfg = "Groupfinder",
    housing = "Housing",
    journal = "AdventureGuide",
    pet = "Collections",
    shop = "Shop",
    help = "GameMenu",
    profession = "Professions",
    legacy = "Legacy",
}
-- WoW Forever's group finder emblem is a round eye, held small by the art's
-- narrow width: it gets a square crop (this fraction of the art's width)
-- instead of the shared trim, so it fills the slot's full height.
local MM_SQUARE_CROP = CludesUI.IS_FOREVER and { lfg = 0.66 } or {}

local function FitBlizzardMicroIcon(iconTex, key)
    -- Native micro art has padding around its emblem. Trim that padding to
    -- match the portrait's visual weight without enlarging the slot or counters.
    -- Work inside the current sheet UV rectangle so packed sheets stay intact.
    local ulx, uly, llx, lly, urx, ury, lrx, lry = iconTex:GetTexCoord()
    local cx = (ulx + llx + urx + lrx) / 4
    local cy = (uly + lly + ury + lry) / 4
    local sx, sy = 2 / 3, 2 / 3
    local square, aspect = MM_SQUARE_CROP[key], iconTex._edbAspect
    if square and aspect then
        -- Equal pixels both ways: the height share shrinks by the art's aspect.
        sx, sy = square, square * aspect
        iconTex._edbAspect = nil
    end
    iconTex:SetTexCoord(
        cx + (ulx - cx) * sx,
        cy + (uly - cy) * sy,
        cx + (llx - cx) * sx,
        cy + (lly - cy) * sy,
        cx + (urx - cx) * sx,
        cy + (ury - cy) * sy,
        cx + (lrx - cx) * sx,
        cy + (lry - cy) * sy
    )
end
-- Art-only sources: these keys click a different Blizzard button than they copy art from.
local MM_ART_BUTTON = { menu = "MainMenuMicroButton", pvp = "PVPMicroButton", social = "SocialsMicroButton" }

-- First existing global among a name or list of names.
local function FindMicroButton(nameList)
    if type(nameList) ~= "table" then return nameList and _G[nameList] end
    for _, name in ipairs(nameList) do
        if _G[name] then return _G[name] end
    end
end

-- Draws an atlas from its sheet file with the sheet coords. An atlas-mode
-- texture does not take sheet coords in SetTexCoord, so the trim above only
-- works on art painted this way.
local function SetAtlasArt(iconTex, atlas)
    local details = C_Texture.GetAtlasInfo(atlas)
    local file = details and (details.file or details.filename)
    if not file then return false end
    iconTex:SetTexture(file)
    iconTex:SetTexCoord(
        details.leftTexCoord,
        details.rightTexCoord,
        details.topTexCoord,
        details.bottomTexCoord
    )
    -- Native shape (retail micro art is 32x40); PaintIcon fits it in the slot.
    if details.width > 0 and details.height > 0 then iconTex._edbAspect = details.width / details.height end
    return true
end

-- Blizzard's guild button: in a guild with a tabard, the banner tinted with the
-- tabard's background colour (the block draws the emblem over it); otherwise
-- the plain guild icon. The tint rides icon._edbTint for IconColor.
local function SetGuildArt(iconTex)
    local tabard = select(10, GetGuildLogoInfo()) and C_GuildInfo.GetGuildTabardInfo("player")
    if
        tabard
        and tabard.backgroundColor
        and SetAtlasArt(iconTex, "UI-HUD-MicroMenu-GuildCommunities-GuildColor-Up")
    then
        iconTex._edbTint = tabard.backgroundColor
        return "micro"
    end
    return SetAtlasArt(iconTex, "UI-HUD-MicroMenu-GuildCommunities-Up") and "micro" or false
end

-- Copies Blizzard's art for key onto icon: "micro" for padded art (micro
-- buttons) that gets trimmed, "plain" for art that fills its texture (the PvP
-- faction crest, the Battle.net portrait), false when none exists.
local function SetBlizzardArt(iconTex, key)
    if key == "guild" then return SetGuildArt(iconTex) end
    local source = FindMicroButton(MM_ART_BUTTON[key] or MM_MICRO_BUTTON_NAMES[key])
    local normal = source and source.GetNormalTexture and source:GetNormalTexture()
    local atlas = normal and normal:GetAtlas()
    if atlas then
        if SetAtlasArt(iconTex, atlas) then return "micro" end
    else
        local texture = normal and normal:GetTexture()
        if texture then
            iconTex:SetTexture(texture)
            iconTex:SetTexCoord(normal:GetTexCoord())
            -- The shape Blizzard draws it at; an unresolved size stays square.
            local wid, hgt = normal:GetSize()
            if not (issecretvalue(wid) or issecretvalue(hgt)) and wid > 0 and hgt > 0 then
                iconTex._edbAspect = wid / hgt
            end
            return "micro"
        end
    end
    local stem = MM_BLIZZARD_ATLAS[key]
    if stem and SetAtlasArt(iconTex, "UI-HUD-MicroMenu-" .. stem .. "-Up") then return "micro" end
    if key == "social" then
        -- No friends micro button exists: the Friends window's own portrait.
        iconTex:SetTexture("Interface\\FriendsFrame\\Battlenet-Portrait")
        iconTex:SetTexCoord(0, 1, 0, 1)
        return "plain"
    elseif key == "pvp" then
        -- No PvP micro button exists: the faction crest the player frame shows
        -- while flagged (the UI-PVP file keeps its emblem in one corner).
        local faction = UnitFactionGroup("player") == "Horde" and "Horde" or "Alliance"
        if
            SetAtlasArt(iconTex, "UI-HUD-UnitFrame-Player-PVP-" .. faction .. "Icon")
            or SetAtlasArt(iconTex, "UI-HUD-UnitFrame-SmallCircle-" .. faction)
        then
            return "plain"
        end
        iconTex:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
        iconTex:SetTexCoord(0, 1, 0, 1)
        return "plain"
    end
    return false
end

-- Skips the repaint while the icon already shows this style; force repaints
-- (portrait and guild changes, and PLAYER_ENTERING_WORLD for Blizzard art that
-- was missing). Returns true when it painted.
local function ApplyMicroIcon(iconTex, key, blizzard, force)
    if not force and iconTex._edbWow == blizzard then return end
    iconTex._edbWow = blizzard
    iconTex._edbAspect = nil -- square unless the Blizzard art below sets its own
    iconTex._edbTint = nil
    if blizzard and key == "char" then
        iconTex:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(iconTex, "player")
        return true
    end
    local art = blizzard and SetBlizzardArt(iconTex, key)
    if art == "micro" then
        FitBlizzardMicroIcon(iconTex, key)
    elseif not art then
        local def = mmButtonDefsByKey[key]
        iconTex:SetTexture(def.icon or (MM_MEDIA .. (MM_ICON_FILE[key] or key) .. ".png"))
        iconTex:SetTexCoord(0, 1, 0, 1)
    end
    return true
end

-- Blizzard art keeps its own colors (the guild banner its tabard tint); custom
-- art takes the block color.
local function IconColor(block, iconTex)
    local cfg = block.settings
    if cfg and cfg.iconStyle == "wow" then
        local tint = iconTex and iconTex._edbTint
        if tint then return tint.r, tint.g, tint.b end
        return 1, 1, 1
    end
    return BlockColorOf(block)
end

local function OnlineCount(key)
    if key == "guild" then
        if IsInGuild() then return select(2, GetNumGuildMembers()) or 0 end
    elseif key == "social" then
        return (select(2, BNGetNumFriends()) or 0) + (C_FriendList.GetNumOnlineFriends() or 0)
    end
end

-- WoW Forever splits the spellbook and the talents into two micro buttons. Its
-- PlayerSpellsMicroButton still exists but opens the frame on whichever tab was last
-- shown, so there the spell entry clicks the spellbook's own button and a Talents entry follows it.
-- Forever Essentials' routes come first: they open its Classic Spellbook and
-- Classic Talents while those are on and click these buttons otherwise. The
-- glyphs still come from the buttons themselves.
if CludesUI.IS_FOREVER then
    MM_MICRO_BUTTON_NAMES.spell = { "CUI_SpellbookRoute", "SpellbookMicroButton" }
    MM_MICRO_BUTTON_NAMES.talent = { "CUI_TalentsRoute", "TalentMicroButton" }
    MM_ART_BUTTON.spell = "SpellbookMicroButton"
    MM_ART_BUTTON.talent = "TalentMicroButton"
    for index, def in ipairs(mmButtonDefs) do
        if def.key == "spell" then
            def.label = SPELLBOOK or "Spellbook"
            -- Full icon path: the shared micromenu art holds glyphs this strip's own set lacks,
            -- so Talents does not repeat the Achievements glyph right beside it.
            local talent = {
                key = "talent",
                binding = "TOGGLETALENTS",
                label = TALENTS or "Talents",
                onWhenUnset = true,
                icon = MM_MEDIA .. "menu-vault.png",
            }
            tinsert(mmButtonDefs, index + 1, talent)
            tinsert(mmButtonOrder, index + 1, "talent")
            mmButtonDefsByKey.talent = talent
            break
        end
    end
    -- Forever-only micro buttons, placed after the Talents entry. Default
    -- off (opt-in via Menu Elements). Professions uses the shared
    -- menu-professions art; in the Blizzard icon style both copy their own
    -- micro button's art like every other button.
    MM_MICRO_BUTTON_NAMES.profession = "ProfessionMicroButton"
    MM_MICRO_BUTTON_NAMES.legacy = "LegacyMicroButton"
    MM_ICON_FILE.legacy = "menu-legacy"
    local extras = {
        {
            key = "profession",
            binding = "TOGGLEPROFESSIONBOOK",
            label = PROFESSIONS_BUTTON or "Professions",
            icon = MM_MEDIA .. "menu-professions.png",
        },
        { key = "legacy", binding = "TOGGLELEGACYSYSTEM", label = LEGACY_BUTTON or "Legacy" },
    }
    for index, def in ipairs(mmButtonDefs) do
        if def.key == "talent" then
            for jdx, extra in ipairs(extras) do
                tinsert(mmButtonDefs, index + jdx, extra)
                tinsert(mmButtonOrder, index + jdx, extra.key)
                mmButtonDefsByKey[extra.key] = extra
            end
            break
        end
    end
    -- Achievements, PvP, Housing, Adventure Guide and Shop stay out of the
    -- Forever strip and options checklist. Saved settings keep their keys.
    local FOREVER_OFF = { ach = true, pvp = true, housing = true, journal = true, shop = true }
    for index = #mmButtonDefs, 1, -1 do
        local key = mmButtonDefs[index].key
        if FOREVER_OFF[key] then
            tremove(mmButtonDefs, index)
            tremove(mmButtonOrder, index)
            mmButtonDefsByKey[key] = nil
        end
    end
end

-- Whether a block shows one button. A button added after blocks were saved
-- (onWhenUnset) reads a missing setting as on, as the options checklist does.
local function MMButtonOn(mm, key)
    local val = mm[key]
    if val == nil then
        local def = mmButtonDefsByKey[key]
        return def and def.onWhenUnset or false
    end
    return val
end
mod.MicroMenuButtonOn = MMButtonOn

local IndexOf = tIndexOf

-- Saved order first (unknown and repeated keys dropped). A default key the
-- saved order lacks (new, or saved on the other client: profiles are shared)
-- goes back behind its default predecessor, not to the end.
local orderSeen = {}
function mod.GetMicroMenuOrder(prefs, result)
    wipe(result)
    wipe(orderSeen)
    if type(prefs.buttonOrder) == "table" then
        for _, key in ipairs(prefs.buttonOrder) do
            if mmButtonDefsByKey[key] and not orderSeen[key] then
                result[#result + 1] = key
                orderSeen[key] = true
            end
        end
    end
    for index, key in ipairs(mmButtonOrder) do
        if not orderSeen[key] then
            local at = index > 1 and IndexOf(result, mmButtonOrder[index - 1]) or 0
            tinsert(result, at + 1, key)
        end
    end
    return result
end
-- Refresh's scratch for the resolved order (read straight through, never kept).
local orderScratch = {}

-- Saves a reordered strip. Saved keys this client lacks (the other client's
-- buttons) stay behind the key they followed, so neither client loses its order.
function mod.SetMicroMenuOrder(prefs, keyList)
    local old = prefs.buttonOrder
    if type(old) == "table" then
        for index, key in ipairs(old) do
            if not mmButtonDefsByKey[key] and not IndexOf(keyList, key) then
                local at = index > 1 and IndexOf(keyList, old[index - 1]) or 0
                tinsert(keyList, at + 1, key)
            end
        end
    end
    prefs.buttonOrder = keyList
end

-- Plain-button click handlers (no Blizzard secure backing). Shared table: they close over no instance state.
local mmClickFunctions = {}
mmClickFunctions.menu = function(_, btnFrame)
    if btnFrame == "LeftButton" then
        if not InCombatLockdown() then ToggleFrame(GameMenuFrame) end
    elseif btnFrame == "RightButton" then
        if IsShiftKeyDown() then
            CludesUI.RequestReload(CludesUI.L("Reload UI"), CludesUI.L("Reload the UI now?"))
        elseif not InCombatLockdown() then
            ToggleFrame(AddonList)
        end
    end
end
local function MMBlockedInCombat(btnFrame) return btnFrame ~= "LeftButton" or InCombatLockdown() end
mmClickFunctions.spell = function(_, btnFrame)
    if MMBlockedInCombat(btnFrame) then return end
    if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then
        PlayerSpellsUtil.ToggleSpellBookFrame()
    elseif _G.SpellBookFrame then
        ToggleFrame(_G.SpellBookFrame)
    end
end
mmClickFunctions.pvp = function(_, btnFrame)
    if MMBlockedInCombat(btnFrame) then return end
    if _G.TogglePVPUI then
        _G.TogglePVPUI()
    elseif _G.PVEFrame and _G.PVEFrame:IsShown() then
        -- Behave as a toggle: close when already on the PvP tab, otherwise switch to it.
        if PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(_G.PVEFrame) == 2 then
            HideUIPanel(_G.PVEFrame)
        elseif PanelTemplates_SetTab then
            PanelTemplates_SetTab(_G.PVEFrame, 2)
        else
            HideUIPanel(_G.PVEFrame)
        end
    elseif _G.LFDMicroButton and _G.LFDMicroButton.Click then
        _G.LFDMicroButton:Click()
        C_Timer.After(0, function()
            if _G.PVEFrame and _G.PVEFrame:IsShown() and PanelTemplates_SetTab then
                PanelTemplates_SetTab(_G.PVEFrame, 2)
            end
        end)
    end
end
mmClickFunctions.journal = function(_, btnFrame)
    if MMBlockedInCombat(btnFrame) then return end
    -- Go through Blizzard's toggle so the frame is placed by the UI panel system; ej:Show() directly would bypass ShowUIPanel.
    if _G.ToggleEncounterJournal then
        _G.ToggleEncounterJournal()
    else
        if _G.EncounterJournal_LoadUI then _G.EncounterJournal_LoadUI() end
        local ej = _G.EncounterJournal
        if ej then
            if ej:IsShown() then
                HideUIPanel(ej)
            else
                ShowUIPanel(ej)
            end
        end
    end
end

-- Blizzard micro menu hider. Calling frame:Hide() from addon Lua on Edit Mode managed
-- frames (MicroMenuContainer) taints the managed frame system, blocking the next
-- ActionBarController_UpdateAll (e.g. vehicle exit); the hider's _onstate-vis runs inside the secure context instead.
local mmHiders = {}
local function MMGetHider(widget)
    local hider = mmHiders[widget]
    if hider then return hider end
    if InCombatLockdown() then return nil end
    hider = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
    hider:SetFrameRef("target", widget)
    hider:SetAttribute(
        "_onstate-vis",
        [[
        local target = self:GetFrameRef('target')
        if newstate == 'hide' then target:Hide() else target:Show() end
    ]]
    )
    mmHiders[widget] = hider
    return hider
end

-- Union semantics: Blizzard's micro menu is hidden iff ANY micromenu block on an
-- enabled, non-deleted bar sets settings.disableBlizzardMicroMenu. Recomputed on
-- every micromenu Refresh/Destroy and every bar enable/disable/delete (engine calls this from AfterBarStateChange).
local mmLastApplied = nil -- last driver state pushed ("hide"/"show"); nil = never touched
-- force: re-push the driver even when the wanted state is unchanged. The driver registers
-- a CONSTANT state string, so its snippet runs once and never re-evaluates: anything that
-- hides the container later (a pet battle) is never undone, and the steady-state guard below
-- makes later refreshes no-ops. Callers repairing an EXTERNAL actor's move pass force; settings-driven callers pass nothing.
function mod.RefreshMicroMenuHider(force)
    local hide = false
    local profile = mod.GetProfile()
    if profile then
        local barList = profile.bars
        for index = 1, #barList do
            local barFrame = barList[index]
            if not mod.VisIsNever(barFrame) then
                for jdx = 1, #barFrame.blocks do
                    local b = barFrame.blocks[jdx]
                    if b.type == "micromenu" and b.settings and b.settings.disableBlizzardMicroMenu then
                        hide = true
                    end
                end
            end
        end
    end
    -- Never touch Blizzard's micro menu until a block opts in: with nothing applied a "show" needs no restore, so no hiders on the managed frames.
    if not hide and mmLastApplied == nil then return end
    -- Steady-state guard: re-registering the same driver re-runs the secure snippet (and
    -- re-Shows the target) for nothing. Push only changes, unless a caller is repairing an external hide, where the re-run IS the repair.
    local wanted = hide and "hide" or "show"
    if not force and wanted == mmLastApplied then return end
    mmLastApplied = wanted
    mod.DeferUntilOOC("edb_mm_blizz", function()
        -- Build the target list without array holes (any of these globals may be absent on a given client).
        local targets = {}
        if _G.MicroMenuContainer then targets[#targets + 1] = _G.MicroMenuContainer end
        if _G.MainMenuBarMicroButtons then targets[#targets + 1] = _G.MainMenuBarMicroButtons end
        if _G.MicroButtonAndBagsBar then targets[#targets + 1] = _G.MicroButtonAndBagsBar end
        for index = 1, #targets do
            local hider = MMGetHider(targets[index])
            if hider then
                UnregisterStateDriver(hider, "vis")
                RegisterStateDriver(hider, "vis", wanted)
            end
        end
        -- Action Bars' micro menu end caps follow the container's shown state
        -- (a no-op while that bar shows none).
        local ab = CludesUI._ModuleNS.CludesUIActionBars
        if ab and ab.AB_ExtraCapsShown then ab.AB_ExtraCapsShown("MicroBar") end
    end)
end

-- Character stats tooltip (always on). Fixed set: equipped item
-- level, primary stat, and the four secondary percentages with raw combat rating in
-- parentheses. Versatility is pcall-wrapped: GetVersatilityBonus/GetCombatRatingBonus
-- can return a secret value under tainted execution (arithmetic on it errors), so drop the line instead.
local CS_DIM = "|cffaaaaaa"

local function MMPrimaryStat()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex or specIndex <= 0 then return nil end
    local _, _, _, _, _, statID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if statID == LE_UNIT_STAT_STRENGTH then return SPELL_STAT1_NAME or "Strength", 1 end
    if statID == LE_UNIT_STAT_AGILITY then return SPELL_STAT2_NAME or "Agility", 2 end
    if statID == LE_UNIT_STAT_INTELLECT then return SPELL_STAT4_NAME or "Intellect", 4 end
    return nil
end

local function MMAddCharStats()
    local ar, ag, ab = mod.GetAccent()
    -- Stat reads return SECRET numbers in restricted content. They do NOT error on
    -- read: format() carries the secret into the row text, which detonates in
    -- Tip_Show's width measuring. Check every value and drop that row alone (Tip_AddDouble also refuses secret rows as a net).
    local function clean(val)
        if issecretvalue(val) then return nil end
        return val or 0
    end
    local function pctRating(labelText, pct, rating)
        pct, rating = clean(pct), clean(rating)
        if not (pct and rating) then return end
        mod.Tip_AddDouble(
            labelText,
            format("%.2f%%", pct) .. " " .. CS_DIM .. "(" .. floor(rating + 0.5) .. ")|r",
            ar,
            ag,
            ab,
            1,
            1,
            1
        )
    end

    mod.Tip_AddLine(" ")

    local _, eq = GetAverageItemLevel()
    eq = clean(eq)
    if eq then
        mod.Tip_AddDouble(STAT_AVERAGE_ITEM_LEVEL or "Item Level", format("%.1f", eq), ar, ag, ab, 1, 1, 1)
    end

    local pLabel, pIdx = MMPrimaryStat()
    if pLabel and pIdx then
        local _, eff = UnitStat("player", pIdx)
        eff = clean(eff)
        if eff then mod.Tip_AddDouble(pLabel, format("%.0f", eff), ar, ag, ab, 1, 1, 1) end
    end

    -- WoW Forever has no Mastery or Versatility.
    if CludesUI.IS_FOREVER then
        local crit, critCR = CludesUI.ForeverCritChance()
        local haste, hasteCR = CludesUI.ForeverHaste()
        pctRating(STAT_CRITICAL_STRIKE or "Critical Strike", crit, GetCombatRating(critCR))
        pctRating(STAT_HASTE or "Haste", haste, GetCombatRating(hasteCR))
        return
    end

    local crit, critCR = CludesUI.PlayerCritChance()
    pctRating(STAT_CRITICAL_STRIKE or "Critical Strike", crit, GetCombatRating(critCR))
    pctRating(STAT_HASTE or "Haste", GetHaste(), GetCombatRating(CR_HASTE_MELEE))
    pctRating(STAT_MASTERY or "Mastery", GetMasteryEffect(), GetCombatRating(CR_MASTERY))

    -- Versatility: secret-value-safe (see block comment above).
    local success, dmg, rating = pcall(function()
        local skinData = (GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0)
            + (GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE) or 0)
        return skinData, GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) or 0
    end)
    if success then pctRating(STAT_VERSATILITY or "Versatility", dmg, rating) end
end

-- Interactive Social / Guild tooltips (always on): online member lists
-- built on the owned Tip system's insecure clickable-row primitive (Tip_AddClickable).
-- Every action (whisper/invite/BNet whisper) is UNPROTECTED, so rows stay clickable in and out of combat. Shift is the fixed invite modifier.

-- Taint-safe whisper (mirrors the minimap friends tooltip): BNet friends by
-- Battle.net account name (any character/faction/realm), everyone else by character
-- name. Explicit DEFAULT_CHAT_FRAME skips ChatFrame_SendTell's FCF_OpenTemporaryWindow
-- path, which drives the secret window list and taints all of chat. Whispers are
-- suppressed in protected content (Mythic+/raid); invites are unaffected (InviteUnit opens no window).
local function MMOpenWhisper(charName, bnetName)
    -- Suppress whispers wherever chat is taint-sensitive: (1) protected content, (2)
    -- while /cuidev is on -- it forces the same secret-value restricted environment
    -- as a real Mythic+. InProtectedInstance() itself reports true in dev mode; the
    -- separate branch exists only for the clearer message.
    local blocked
    if CludesUI.IsDevModeActive() then
        blocked = "This action is protected while dev mode (/cuidev) is on."
    elseif CludesUI.InProtectedInstance() then
        blocked = "This action is protected in Mythic+ and raid combat."
    end
    if blocked then
        if UIErrorsFrame then UIErrorsFrame:AddMessage(blocked, 1.0, 0.3, 0.3, 1.0) end
        return
    end
    if bnetName and bnetName ~= "" then
        local sendBN = (ChatFrameUtil and ChatFrameUtil.SendBNetTell) or ChatFrame_SendBNetTell
        if sendBN then
            sendBN(bnetName, DEFAULT_CHAT_FRAME)
            return
        end
    end
    if charName and charName ~= "" then
        local sendTell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        -- Fix "Name-Realm-Realm" to "Name-Realm"
        local target = CludesUI.BuildFullName(charName) or charName
        if sendTell then sendTell(target, DEFAULT_CHAT_FRAME) end
    end
end

-- GuildRoster() itself fires GUILD_ROSTER_UPDATE, and the server rate-limits it (~10s); throttle so hovering the guild button does not spam requests.
local mmLastTipRoster = 0

-- Member rows per tooltip, as in the minimap friends tooltip: a big friend list or
-- guild otherwise grows it past the screen. The rest become one "...and N more" line.
local MM_TIP_MAX_ROWS = 30

local function MMBuildSocialTip()
    local ar, ag, ab = mod.GetAccent()
    local totalBN = BNGetNumFriends() or 0
    local totalWoW = C_FriendList.GetNumOnlineFriends() or 0
    local playerFaction = UnitFactionGroup("player")

    mod.Tip_AddLine(" ")

    -- Only people actually in WoW: app / other-game friends add nothing here. Same filter as the minimap tooltip (gameAccountInfo.clientProgram=="WoW").
    local isShown, hidden = 0, 0

    -- BNet friends in WoW. Indices are unsorted, so iterate all and filter.
    for index = 1, totalBN do
        local acc = C_BattleNet.GetFriendAccountInfo(index)
        local ga = acc and acc.gameAccountInfo
        local inWoW = ga and ga.isOnline and ga.clientProgram == BNET_CLIENT_WOW
        if inWoW and isShown >= MM_TIP_MAX_ROWS then
            hidden = hidden + 1
        elseif inWoW then
            local charName, realmName = ga.characterName, ga.realmName
            local faction = ga.factionName
            local iconTex = FRIENDS_TEXTURE_ONLINE
            if acc.isAFK or ga.isGameAFK then iconTex = FRIENDS_TEXTURE_AFK end
            if acc.isDND or ga.isGameBusy then iconTex = FRIENDS_TEXTURE_DND end
            -- Left text carries NO |c codes so hover recolor (Tip_Show) shows; its blue rides the left-color args. Right column keeps its codes.
            local leftX = format("|T%s:16|t %s", iconTex, acc.accountName or "?")
            -- A cross-faction BNet friend's characterName can be secret; format("%s", ...)
            -- rejects it outright, so display text uses a nil'd-out copy. The real
            -- charName below is kept whole for BuildFullName (invite/whisper). The
            -- area name rides the same format call and the faction feeds a compare,
            -- so a secret in either is dropped the same way: no area shown, and a
            -- friend whose faction cannot be read is treated as not ours to invite.
            local displayCharName, displayArea = charName, ga.areaName
            if issecretvalue(displayCharName) then displayCharName = nil end
            if issecretvalue(displayArea) then displayArea = nil end
            local secretFaction = issecretvalue(faction)
            -- Character name in its class colour when the class reads plain, else gold.
            local nameText
            local classID = ga.classID
            local ci = displayCharName
                and classID
                and not issecretvalue(classID)
                and C_CreatureInfo.GetClassInfo(classID)
            if ci and ci.classFile then
                local classColor = CludesUI.GetClassColor(ci.classFile)
                nameText = CludesUI.ColorText(displayCharName, classColor.r, classColor.g, classColor.b)
            else
                nameText = format("|cffecd672%s|r", displayCharName or "?")
            end
            local right = format("%s %s", nameText, displayArea or "")
            local bnetName = acc.accountName
            local sameFaction = (not secretFaction) and ((not faction) or (faction == playerFaction))
            -- Fix "Name-Realm-Realm" to "Name-Realm"
            local inviteName = CludesUI.BuildFullName(charName, realmName)
            mod.Tip_AddClickable(leftX, right, function(mouseButton)
                if mouseButton == "LeftButton" then
                    if IsShiftKeyDown() and sameFaction and inviteName then
                        C_PartyInfo.InviteUnit(inviteName)
                    else
                        MMOpenWhisper(nil, bnetName)
                    end
                elseif mouseButton == "RightButton" and sameFaction and inviteName then
                    MMOpenWhisper(inviteName, nil)
                end
            end, 0.51, 0.77, 1, 1, 1, 1)
            isShown = isShown + 1
        end
    end

    -- WoW (non-BNet) friends.
    if totalWoW > 0 then
        for index = 1, C_FriendList.GetNumFriends() do
            local fi = C_FriendList.GetFriendInfoByIndex(index)
            local online = fi and fi.connected
            if online and isShown >= MM_TIP_MAX_ROWS then
                hidden = hidden + 1
            elseif online then
                local iconTex = FRIENDS_TEXTURE_ONLINE
                if fi.afk then iconTex = FRIENDS_TEXTURE_AFK end
                if fi.dnd then iconTex = FRIENDS_TEXTURE_DND end
                -- No |c codes on the left (hover recolor needs a plain string); the class
                -- colour rides the left-color args (white when the class is unknown).
                local leftX = format("|T%s:16|t %s  %s", iconTex, fi.name or "?", fi.level or "")
                local cr, cg, callback = 1, 1, 1
                local token = CludesUI.ClassTokenFromLocalized(fi.className)
                if token then
                    local classColor = CludesUI.GetClassColor(token)
                    cr, cg, callback = classColor.r, classColor.g, classColor.b
                end
                local fname = fi.name
                mod.Tip_AddClickable(leftX, fi.area or "", function(mouseButton)
                    local num = fname
                    if not num then return end
                    if not num:find("%-") then num = num .. "-" .. GetRealmName():gsub("%s+", "") end
                    if mouseButton == "RightButton" then
                        MMOpenWhisper(num, nil)
                    elseif mouseButton == "LeftButton" and IsShiftKeyDown() then
                        C_PartyInfo.InviteUnit(num)
                    end
                end, cr, cg, callback, 0.8, 0.8, 0.8)
                isShown = isShown + 1
            end
        end
    end

    if isShown == 0 then
        mod.Tip_AddLine(L["NO_FRIENDS_ONLINE"], 0.6, 0.6, 0.6)
        return
    end
    if hidden > 0 then mod.Tip_AddLine(format("...and %d more", hidden), 0.53, 0.53, 0.53) end

    -- Left-click BNet-whispers (reaches them cross-realm/faction), right-click whispers the character directly: distinct actions, distinct labels.
    mod.Tip_AddLine(" ")
    mod.Tip_AddDouble(L["LEFT_CLICK"], L["WHISPER_BNET"], 1, 1, 1, ar, ag, ab)
    mod.Tip_AddDouble(L["SHIFT_LEFT_CLICK"], L["INVITE"], 1, 1, 1, ar, ag, ab)
    mod.Tip_AddDouble(L["RIGHT_CLICK"], L["WHISPER"], 1, 1, 1, ar, ag, ab)
end

local function MMBuildGuildTip(cfg)
    local ar, ag, ab = mod.GetAccent()
    mod.Tip_AddLine(" ")
    if not IsInGuild() then
        mod.Tip_AddLine(L["NOT_IN_GUILD"], 0.6, 0.6, 0.6)
        return
    end

    local nowTime = GetTime()
    if not InCombatLockdown() and (nowTime - mmLastTipRoster) >= 10 then
        mmLastTipRoster = nowTime
        C_GuildInfo.GuildRoster()
    end

    local gName = GetGuildInfo("player")
    if gName then mod.Tip_AddLine("|cff00ff00" .. gName .. "|r") end

    local noteFmt
    if cfg.showGuildNotes == true then
        local color = cfg.guildNoteColor
        local nr, ng, nb = 0.925, 0.839, 0.447
        if color then
            nr, ng, nb = color.r or nr, color.g or ng, color.b or nb
        end
        noteFmt = format(
            " |cffffffff(|r|cff%02x%02x%02x%%s|r|cffffffff)|r",
            floor(nr * 255 + 0.5),
            floor(ng * 255 + 0.5),
            floor(nb * 255 + 0.5)
        )
    end

    local isShown, hidden = 0, 0
    for index = 1, GetNumGuildMembers() do
        local name, _, _, level, _, zone, note, _, isOnline, status, class = GetGuildRosterInfo(index)
        if isOnline and isShown >= MM_TIP_MAX_ROWS then
            hidden = hidden + 1
        elseif isOnline then
            isShown = isShown + 1
            local clr, clg, clb = 1, 1, 1
            if class then
                local classColor = CludesUI.GetClassColor(class)
                clr, clg, clb = classColor.r, classColor.g, classColor.b
            end
            local st = (status == 1 and DEFAULT_AFK_MESSAGE) or (status == 2 and DEFAULT_DND_MESSAGE) or ""
            local cn = name and name:match("[^-]+") or "?"
            -- Left plain (no |c): the class color rides the left-color args so the hover recolor to accent shows, like the M+ teleport rows.
            local leftX = format("%s  %s %s", level or "", cn, st)
            -- Own color codes: the note keeps its color under the hover accent.
            if noteFmt and note and note ~= "" then leftX = leftX .. format(noteFmt, note) end
            local fname = name
            mod.Tip_AddClickable(leftX, zone or "", function(mouseButton)
                if not fname then return end
                if mouseButton == "LeftButton" then
                    if IsShiftKeyDown() then
                        C_PartyInfo.InviteUnit(CludesUI.BuildFullName(fname) or fname)
                    else
                        MMOpenWhisper(fname, nil)
                    end
                end
            end, clr, clg, clb, 1, 1, 1)
        end
    end
    if hidden > 0 then mod.Tip_AddLine(format("...and %d more", hidden), 0.53, 0.53, 0.53) end

    mod.Tip_AddLine(" ")
    mod.Tip_AddDouble(L["LEFT_CLICK"], L["WHISPER"], 1, 1, 1, ar, ag, ab)
    mod.Tip_AddDouble(L["SHIFT_LEFT_CLICK"], L["INVITE"], 1, 1, 1, ar, ag, ab)
end

mod.BlockFactories.micromenu = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)
    instance.events = {
        "GUILD_ROSTER_UPDATE",
        "BN_FRIEND_ACCOUNT_ONLINE",
        "BN_FRIEND_ACCOUNT_OFFLINE",
        "FRIENDLIST_UPDATE",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_ENTERING_WORLD",
        -- A pet battle hides this block's buttons and, with Disable Blizzard Micro
        -- Menu on, Blizzard's container; neither returns on its own. BOTH end events
        -- are registered: OVER fires while the result panel is up, CLOSE when the world
        -- UI returns, and which lands last differs per win/forfeit/flee (handler is
        -- idempotent). OPENING_START is NOT registered: refreshing into the takeover restores nothing.
        "PET_BATTLE_OVER",
        "PET_BATTLE_CLOSE",
    }

    -- Per-instance button sets (unique global names per instance).
    local frameList = {}
    local icons = {}
    local textFS = {}
    local isActive, portraitEvents, guildEvents = false, false, false
    local guildEmblem
    local lastRosterRequest = 0

    local function BlockSettings() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local function GetIconSize()
        -- Fixed content size: bar Height never scales icons (Content Scale does).
        return max(16, floor(CONTENT_BASE * 0.82 + 0.5))
    end

    local function SocialFontSize()
        -- 0.3667 ratio = 11px at the 30px base.
        return max(7, floor(CONTENT_BASE * 0.3667 + 0.5))
    end

    -- The guild emblem over the tinted tabard banner (Blizzard style in a guild),
    -- placed as Blizzard's guild button places it: 12x14, 2px up, on 32x40 art,
    -- here trimmed to its middle 2/3. Re-textured only when the banner repainted.
    local function PaintGuildEmblem(iconTex, widget, painted, wid, hgt)
        if not iconTex._edbTint then
            if guildEmblem then guildEmblem:Hide() end
            return
        end
        if not guildEmblem then
            guildEmblem = widget:CreateTexture(nil, "OVERLAY", nil, 1)
            painted = true
        end
        if painted then SetSmallGuildTabardTextures("player", guildEmblem) end
        guildEmblem:SetSize(wid * 0.5625, hgt * 0.525)
        guildEmblem:ClearAllPoints()
        guildEmblem:SetPoint("CENTER", iconTex, "CENTER", 0, hgt * 0.075)
        guildEmblem:Show()
    end

    -- Blizzard style: a shown counter sits above its icon (new blocks seed the
    -- Text Position 8px up), so the guild banner and the friends emblem drop
    -- to clear it.
    local function PlaceIcon(key)
        local iconTex, fontStr = icons[key], textFS[key]
        local drop = 0
        if fontStr and fontStr:IsShown() and BlockSettings().iconStyle == "wow" then
            drop = floor(SocialFontSize() * 0.45 + 0.5)
        end
        iconTex:ClearAllPoints()
        iconTex:SetPoint("CENTER", 0, -drop)
    end

    local function PaintIcon(key, force)
        local iconTex, widget = icons[key], frameList[key]
        if not iconTex or not widget then return end
        local painted = ApplyMicroIcon(iconTex, key, BlockSettings().iconStyle == "wow", force)
        -- SetPortraitTexture can reset anchors; restore our slot after each paint.
        PlaceIcon(key)
        local size = max(8, GetIconSize() - 6)
        -- Non-square Blizzard art keeps its shape, fitted inside the square.
        local wid, hgt = size, size
        local aspect = iconTex._edbAspect
        if aspect and aspect < 1 then
            wid = floor(size * aspect + 0.5)
        elseif aspect and aspect > 1 then
            hgt = floor(size / aspect + 0.5)
        end
        iconTex:SetSize(wid, hgt)
        if widget:IsMouseOver() then
            iconTex:SetVertexColor(mod.GetAccent())
        else
            iconTex:SetVertexColor(IconColor(blockCfg, iconTex))
        end
        if key == "guild" then PaintGuildEmblem(iconTex, widget, painted, wid, hgt) end
    end

    -- Blizzard style only: the portrait and the guild tabard repaint from their
    -- own events, registered while the style and that button are on.
    local function SyncStyleEvents()
        local mm = BlockSettings()
        local wow = isActive and mm.iconStyle == "wow"
        local wanted = wow and MMButtonOn(mm, "char") and icons.char ~= nil
        if portraitEvents ~= wanted then
            portraitEvents = wanted
            if wanted then
                instance.eventFrame:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", "player")
                instance.eventFrame:RegisterEvent("PORTRAITS_UPDATED")
            else
                instance.eventFrame:UnregisterEvent("UNIT_PORTRAIT_UPDATE")
                instance.eventFrame:UnregisterEvent("PORTRAITS_UPDATED")
            end
        end
        wanted = wow and MMButtonOn(mm, "guild") and icons.guild ~= nil
        if guildEvents ~= wanted then
            guildEvents = wanted
            if wanted then
                instance.eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
            else
                instance.eventFrame:UnregisterEvent("PLAYER_GUILD_UPDATE")
            end
        end
    end

    -- Counters sit on their button (the Text Position offsets move them; new
    -- blocks seed them 8px above the icon) in both icon styles.
    -- The counters on the guild and social buttons. The roster events repeat
    -- every few seconds, so an unchanged count (at an unchanged size) only
    -- has its colour checked.
    local counterShown = {}
    local function SetCounterText(key, value)
        local fontStr = textFS[key]
        local size = SocialFontSize()
        local shown = counterShown[key]
        if not (shown and shown.value == value and shown.size == size and fontStr:IsShown()) then
            mod.SetFont(fontStr, size, BC())
            fontStr:SetText(value)
            counterShown[key] = { value = value, size = size }
        end
        if not fontStr:IsShown() then
            fontStr:Show()
            if icons[key] then PlaceIcon(key) end
        end
        if frameList[key]:IsMouseOver() then
            fontStr:SetTextColor(mod.GetAccent())
        else
            fontStr:SetTextColor(BlockColorOf(blockCfg))
        end
    end

    local function ShowButtonTooltip(name)
        local widget = frameList[name]
        if not widget then return end
        local def = mmButtonDefsByKey[name]
        if not def then return end
        local red, green, blue = 1, 1, 1
        mod.Tip_Begin(widget)
        local title = "|cFFFFFFFF" .. (def.label or name) .. "|r"
        if def.binding then
            local k1, k2 = GetBindingKey(def.binding)
            local keyList = {}
            if k1 and k1 ~= "" then keyList[#keyList + 1] = GetBindingText(k1) end
            if k2 and k2 ~= "" then keyList[#keyList + 1] = GetBindingText(k2) end
            if #keyList > 0 then title = title .. " |cFFFFD200(" .. tconcat(keyList, " / ") .. ")|r" end
        end
        mod.Tip_AddLine(title, red, green, blue)

        if name == "ach" then
            local pts = 0
            if GetTotalAchievementPoints then pts = GetTotalAchievementPoints() or 0 end
            local hexAccent = format("%02x%02x%02x", floor(red * 255), floor(green * 255), floor(blue * 255))
            mod.Tip_AddLine(" ")
            mod.Tip_AddDouble(
                "|cFFFFFFFF" .. L["ACH_POINTS"] .. "|r",
                "|cFF" .. hexAccent .. pts .. "|r",
                1,
                1,
                1,
                red,
                green,
                blue
            )
        end

        -- Delve Journey and Companion Level rows: WoW Forever has no Delves.
        if name == "journal" and not CludesUI.IS_FOREVER then
            local hexAccent = format("%02x%02x%02x", floor(red * 255), floor(green * 255), floor(blue * 255))
            mod.Tip_AddLine(" ")
            local delveRank, delveMax = 0, "?"
            if
                C_DelvesUI
                and C_DelvesUI.GetDelvesFactionForSeason
                and C_MajorFactions
                and C_MajorFactions.GetCurrentRenownLevel
            then
                local fid = C_DelvesUI.GetDelvesFactionForSeason()
                if fid then
                    delveRank = C_MajorFactions.GetCurrentRenownLevel(fid) or 0
                    if C_MajorFactions.GetRenownLevels then
                        local levels = C_MajorFactions.GetRenownLevels(fid)
                        if type(levels) == "table" and #levels > 0 then delveMax = tostring(#levels) end
                    end
                end
            end
            mod.Tip_AddDouble(
                "|cFFFFFFFF" .. L["DELVE_JOURNEY"] .. "|r",
                "|cFF" .. hexAccent .. delveRank .. "|r |cFFAAAAAA/ " .. delveMax .. "|r",
                1,
                1,
                1,
                red,
                green,
                blue
            )
            local companionLvl = 0
            if
                C_DelvesUI
                and C_DelvesUI.GetFactionForCompanion
                and C_GossipInfo
                and C_GossipInfo.GetFriendshipReputation
            then
                local cfid = C_DelvesUI.GetFactionForCompanion()
                if cfid then
                    local fi = C_GossipInfo.GetFriendshipReputation(cfid)
                    if fi and fi.reaction then companionLvl = tonumber(fi.reaction:match("%d+")) or 0 end
                end
            end
            mod.Tip_AddDouble(
                "|cFFFFFFFF" .. L["COMPANION_LEVEL"] .. "|r",
                "|cFF" .. hexAccent .. companionLvl .. "|r",
                1,
                1,
                1,
                red,
                green,
                blue
            )
        end

        if name == "char" then
            -- Secret handling lives inside (every stat value is issecretvalue-checked);
            -- pcall is only a last resort so an API surprise never kills the rest of the tooltip.
            pcall(MMAddCharStats)
        end

        if name == "social" then pcall(MMBuildSocialTip) end
        if name == "guild" then pcall(MMBuildGuildTip, BlockSettings()) end

        mod.Tip_Show()
    end

    -- Per-button hover/click wiring. Runs once per frame, at creation time.
    local function SetupButtonScripts(name, widget)
        local isSecure = widget:GetAttribute("*clickbutton1") ~= nil
        if not isSecure then
            -- Plain button (special actions with no Blizzard micro button: menu, pvp;
            -- plus spell/journal on clients missing the global). Safe to call EnableMouse/SetScript freely.
            widget:EnableMouse(true)
            widget:RegisterForClicks("AnyUp")
            local func = mmClickFunctions[name]
            if func then
                widget:SetScript("OnClick", func)
            else
                widget:SetScript("OnClick", function() end)
            end
        else
            -- Secure button: RegisterForClicks is permitted before combat;
            -- SetScript("OnClick") is not.
            widget:RegisterForClicks("AnyUp")
        end

        -- OnEnter / OnLeave are never protected, safe on all button types.
        widget:SetScript("OnEnter", function()
            -- Hover tint stays alive in combat (our textures/fonts only).
            local red, green, blue = mod.GetAccent()
            if icons[name] then icons[name]:SetVertexColor(red, green, blue, 1) end
            -- The counter text (guild/social) follows its button's hover.
            if textFS[name] then textFS[name]:SetTextColor(red, green, blue, 1) end
            if InCombatLockdown() then
                -- The FULL tooltip reads combat-restricted surfaces (char stat
                -- secrets, guild/social rosters); in lockdown show a notice.
                local def = mmButtonDefsByKey[name]
                mod.Tip_Begin(widget)
                mod.Tip_AddLine("|cFFFFFFFF" .. ((def and def.label) or name) .. "|r", 1, 1, 1)
                mod.Tip_AddLine(L["CANNOT_USE_COMBAT"], 0.65, 0.65, 0.65)
                mod.Tip_Show()
                return
            end
            ShowButtonTooltip(name)
        end)
        widget:SetScript("OnLeave", function()
            if icons[name] then icons[name]:SetVertexColor(IconColor(blockCfg, icons[name])) end
            if textFS[name] then textFS[name]:SetTextColor(BlockColorOf(blockCfg)) end
            mod.Tip_HideUnlessInteractive(widget)
        end)
    end

    -- Create one button frame (idempotent). Returns nil in combat: secure frame creation/attribute setup must wait for PLAYER_REGEN_ENABLED.
    local function EnsureButtonFrame(def)
        local key = def.key
        if frameList[key] then return frameList[key] end
        if InCombatLockdown() then
            -- Secure creation must wait for regen; the deferred marker is the only thing that still hides the strip in combat.
            instance._mmDeferred = true
            return nil
        end
        local microBtnName = MM_MICRO_BUTTON_NAMES[key]
        local microRef
        if type(microBtnName) == "table" then
            for _, num in ipairs(microBtnName) do
                microRef = _G[num]
                if microRef then break end
            end
        elseif microBtnName then
            microRef = _G[microBtnName]
        end
        if
            (key == "housing" or key == "talent" or key == "profession" or key == "legacy") and not microRef
        then
            -- Skip optional buttons whose Blizzard micro button does not exist.
            return nil
        end
        local widget
        local gname = "CUIInfoBar_MM_" .. instance.key .. "_" .. key
        if microRef then
            -- Taint-safe: pass clicks through to the Blizzard MicroButton.
            widget = CreateFrame(
                "Button",
                gname,
                contentFrame,
                "SecureActionButtonTemplate,SecureHandlerStateTemplate"
            )
            widget:SetAttribute("*clickbutton1", microRef)
            -- Without this, the ActionButtonUseKeyDown CVar makes the secure handler act on key-down only, discarding our "AnyUp" clicks.
            widget:SetAttribute("useOnKeyDown", false)
            widget:SetAttribute("*type1", "click")
            widget:EnableMouse(true)
            widget:RegisterForClicks("AnyUp")
            -- Combat: drop the click ACTION only, from inside the secure env. Stays
            -- mouse-enabled so hover works (OnEnter shows the combat notice); a click while *type1 is nil does nothing.
            RegisterStateDriver(widget, "combatlock", "[combat] combat; nocombat")
            widget:SetAttribute(
                "_onstate-combatlock",
                [[
                if newstate == 'combat' then
                    self:SetAttribute('*type1', nil)
                else
                    self:SetAttribute('*type1', 'click')
                end
            ]]
            )
        else
            -- Plain button for special actions with no secure backing.
            widget = CreateFrame("Button", gname, contentFrame)
            widget:EnableMouse(true)
        end
        frameList[key] = widget
        if def.info then
            textFS[key] = widget:CreateFontString(nil, "OVERLAY")
            AttachTextOffset(instance, textFS[key])
        end
        icons[key] = widget:CreateTexture(nil, "OVERLAY")
        ApplyMicroIcon(icons[key], key, BlockSettings().iconStyle == "wow")
        SetupButtonScripts(key, widget)
        return widget
    end

    -- Materialise buttons for every enabled key. Tolerates a nil/partial set in combat; the REGEN_ENABLED event retries.
    local function CreateFramesInner()
        local mm = BlockSettings()
        for _, def in ipairs(mmButtonDefs) do
            if MMButtonOn(mm, def.key) then EnsureButtonFrame(def) end
        end
        -- A full out-of-combat pass clears the deferred marker (buttons that cannot exist, e.g. housing without its micro button, do not count).
        if not InCombatLockdown() then instance._mmDeferred = nil end
    end

    local function SyncCombatLook()
        -- Combat does not hide the strip or kill mouse: buttons stay visible and
        -- hoverable (combat notice tooltip), clicks are inert in lockdown (secure
        -- buttons drop *type1 via their state driver). The one combat hide left: a strip
        -- whose enabled buttons could not all be built yet stays hidden until the REGEN retry materializes them.
        if instance._mmDeferred and InCombatLockdown() then
            contentFrame:Hide()
        else
            contentFrame:Show()
        end
    end

    local function UpdateGuildText()
        local mm = BlockSettings()
        if not textFS.guild or not mm.guild or mm.hideSocialText then return end
        if not IsInGuild() then
            if textFS.guild:IsShown() then
                textFS.guild:Hide()
                if icons.guild then PlaceIcon("guild") end
            end
            return
        end
        -- Throttled: GuildRoster() itself fires GUILD_ROSTER_UPDATE, which re-enters this function; unthrottled that is a request loop.
        local nowTime = GetTime()
        if not InCombatLockdown() and (nowTime - lastRosterRequest) >= 15 then
            lastRosterRequest = nowTime
            C_GuildInfo.GuildRoster()
        end
        SetCounterText("guild", OnlineCount("guild"))
    end

    local function UpdateFriendText()
        local mm = BlockSettings()
        if mm.hideSocialText or not mm.social or not textFS.social then return end
        SetCounterText("social", OnlineCount("social"))
    end

    function instance:Refresh()
        mod.RefreshMicroMenuHider()
        SyncCombatLook()
        if not contentFrame:IsShown() or InCombatLockdown() then
            SyncStyleEvents()
            return
        end

        local mm = BlockSettings()
        wipe(counterShown) -- a full pass sets the counters' font again (it may have changed)
        -- Materialise any buttons enabled after creation (options toggle).
        CreateFramesInner()
        SyncStyleEvents()
        if not next(frameList) then return end
        if mm.hideSocialText then
            for _, fontStr in pairs(textFS) do
                fontStr:Hide()
            end
        else
            UpdateFriendText()
            UpdateGuildText()
        end
        local ICON_SIZE = GetIconSize()
        local isVertical = barCtx.IsVertical()
        local totalWidth, totalHeight, previous = 0, 0, nil
        for _, key in ipairs(mod.GetMicroMenuOrder(mm, orderScratch)) do
            local widget = frameList[key]
            -- Hide buttons toggled off after creation; lay out enabled ones.
            if widget and not MMButtonOn(mm, key) then
                widget:Hide()
                widget = nil
            end
            if widget then
                widget:Show()
                widget:SetSize(ICON_SIZE, ICON_SIZE)
                PaintIcon(key)
                if textFS[key] then
                    -- Plain button-center anchor: the block's Text Position offsets are the ONE positioning input (the wrapper injects them here).
                    textFS[key]:ClearAllPoints()
                    textFS[key]:SetPoint("CENTER", widget, "CENTER", 0, 0)
                end
                widget:ClearAllPoints()
                local spacing = mm.iconSpacing or MM_SPACING
                if previous and previous == frameList.menu then spacing = mm.mainMenuSpacing or 4 end
                if not previous then
                    if isVertical then
                        widget:SetPoint("TOP", contentFrame, "TOP", 0, 0)
                    else
                        widget:SetPoint("LEFT", contentFrame, "LEFT", 0, 0)
                    end
                else
                    if isVertical then
                        widget:SetPoint("TOP", previous, "BOTTOM", 0, -spacing)
                    else
                        widget:SetPoint("LEFT", previous, "RIGHT", spacing, 0)
                    end
                end
                local prevSpacing = 0
                if previous then prevSpacing = spacing end
                if isVertical then
                    totalHeight = totalHeight + ICON_SIZE + prevSpacing
                    totalWidth = max(totalWidth, ICON_SIZE)
                else
                    totalWidth = totalWidth + ICON_SIZE + prevSpacing
                    totalHeight = max(totalHeight, ICON_SIZE)
                end
                previous = widget
            end
        end

        contentFrame:SetSize(max(totalWidth, 1), max(totalHeight, 1))

        MaybeRelayout(instance)
    end

    instance.eventFrame = MakeEventFrame(instance, function(self, evt, unitToken)
        if evt == "PORTRAITS_UPDATED" or evt == "UNIT_PORTRAIT_UPDATE" then
            if portraitEvents and (evt == "PORTRAITS_UPDATED" or unitToken == "player") then
                PaintIcon("char", true)
            end
        elseif evt == "PLAYER_GUILD_UPDATE" then
            -- Joined, left or changed tabard: repaint the guild art. In combat the
            -- cleared memo lets the regen refresh repaint it instead.
            if guildEvents and icons.guild then
                icons.guild._edbWow = nil
                if not InCombatLockdown() then PaintIcon("guild") end
            end
        elseif evt == "GUILD_ROSTER_UPDATE" then
            UpdateGuildText()
        elseif
            evt == "BN_FRIEND_ACCOUNT_ONLINE"
            or evt == "BN_FRIEND_ACCOUNT_OFFLINE"
            or evt == "FRIENDLIST_UPDATE"
        then
            UpdateFriendText()
        elseif evt == "PET_BATTLE_OVER" or evt == "PET_BATTLE_CLOSE" then
            -- A pet battle hides two things, neither self-restoring: this block's
            -- buttons (rebuilt by the same ApplyCombatState+Refresh pair REGEN uses),
            -- and Blizzard's micro menu container if a block opted into hiding it --
            -- its hider runs off a CONSTANT state driver, so the snippet fires once and
            -- nothing re-asserts it; force makes the refresh re-push and re-register it.
            -- Both safe here: REGEN already calls Refresh in combat, and the hider defers its driver work until OOC.
            SyncCombatLook()
            self:Refresh()
            mod.RefreshMicroMenuHider(true)
        else
            -- REGEN x2 / PLAYER_ENTERING_WORLD: retry deferred button creation and re-apply the combat state.
            if evt == "PLAYER_ENTERING_WORLD" then
                for _, iconTex in pairs(icons) do
                    iconTex._edbWow = nil
                end
            end
            SyncCombatLook()
            self:Refresh()
        end
    end)

    CreateFramesInner()

    function instance:Enable()
        isActive = true
        contentFrame:Show()
        RegisterInstEvents(self)
        SyncStyleEvents()
        mod.RefreshMicroMenuHider()
        SyncCombatLook()
    end

    function instance:Disable()
        isActive, portraitEvents, guildEvents = false, false, false
        UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    -- Refresh sizes content to the laid-out strip.
    function instance:GetAutoLength()
        return max(barCtx.IsVertical() and contentFrame:GetHeight() or contentFrame:GetWidth(), 50)
    end

    function instance:Destroy()
        self._dead = true
        for key, widget in pairs(frameList) do
            ParkSecureFrame(widget, self.key .. "_" .. key)
        end
        contentFrame:Hide()
        -- The union recomputes without this instance's bar/block cfg (the
        -- engine removes the cfg before calling Destroy).
        mod.RefreshMicroMenuHider()
    end

    return instance
end
