-- Window Skins: every page the client offers built fresh (with its header
-- preview), every inline cog on it clicked with the popup it opens snapped,
-- then the first page again from the page cache.
local CUI = rawget(_G, "CludesUI")
local pages = { "Window Skins", "Window Mover", "Tooltips", "Chat Bubbles" }
if not CUI.IS_FOREVER then pages[#pages + 1] = "Dragon Riding" end
local function Hosts()
    local hosts = { UIParent }
    if CUI.OverlayParent and CUI.OverlayParent() ~= UIParent then hosts[2] = CUI.OverlayParent() end
    return hosts
end
local function Cogs(root)
    local out, stack = {}, { root }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and rawget(f, "_cuiCogId") and f:IsVisible() then out[#out + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
for _, page in ipairs(pages) do
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIBlizzardSkin")
    CUI:SelectPage(page)
    SNAP("page " .. page, CUI._scrollFrame)
    SNAP("header " .. page, CUI._contentHeader or CUI._headerFrame)
    local cogs = Cogs(CUI._scrollFrame)
    OUT:write("== cogs " .. page .. " " .. #cogs .. "\n")
    for i, cog in ipairs(cogs) do
        local before = {}
        for _, host in ipairs(Hosts()) do
            for _, c in ipairs({ host:GetChildren() }) do if c:IsShown() then before[c] = true end end
        end
        local click = cog["\0scripts"].OnClick
        if click then pcall(click, cog, "LeftButton") end
        for _, host in ipairs(Hosts()) do
            for _, c in ipairs({ host:GetChildren() }) do
                if c:IsShown() and not before[c] then
                    SNAP("cog " .. page .. " " .. i, c)
                    c:Hide()
                end
            end
        end
    end
end
CUI:SelectPage("Window Skins")
SNAP("again", CUI._scrollFrame)

-- The module's reset (as Reset & Reload runs it, minus the reload): every key
-- either version might clear is seeded, then the survivors are listed.
-- The page registry is private: found through the upvalues of the core's
-- functions (two levels down), as the table that holds this module's config.
local reg
local seen = {}
local function Look(fn, depth)
    if reg or seen[fn] or depth > 2 then return end
    seen[fn] = true
    for i = 1, 200 do
        local name, v = debug.getupvalue(fn, i)
        if not name then break end
        if type(v) == "table" and rawget(v, "CludesUIBlizzardSkin") ~= nil
            and type(rawget(v, "CludesUIBlizzardSkin")) == "table" and v.CludesUIBlizzardSkin.onReset then
            reg = v
            return
        elseif type(v) == "function" then
            Look(v, depth + 1)
        end
    end
end
for _, fn in pairs(CUI) do
    if type(fn) == "function" then Look(fn, 0) end
    if reg then break end
end
local cfg = reg and reg.CludesUIBlizzardSkin
OUT:write("== reset " .. tostring(cfg and cfg.onReset ~= nil) .. "\n")
if cfg and cfg.onReset then
    local seeded = {
    "accentReskinElements",
    "blizzWinAccentBar",
    "blizzWinBarFill",
    "blizzWinLinks",
    "blizzWindowModernDefault",
    "blizzWindowSkinStyles",
    "charSheetBlizzColors",
    "charSheetDurabilityLocation",
    "charSheetDurabilityShowLabel",
    "charSheetEnchantNames",
    "charSheetEnchantSize",
    "charSheetHideSlotFlyoutArrows",
    "charSheetIconZoom",
    "charSheetItemStats",
    "charSheetItemStatsTertiary",
    "charSheetSeasonPanel",
    "charSheetSeasonVault",
    "charSheetSocketPanel",
    "charSheetSocketPanelStats",
    "customTooltips",
    "flyoutItemLevels",
    "flyoutItemStats",
    "flyoutItemStatsTertiary",
    "friendsListCard",
    "highlightSecondaryItems",
    "highlightTertiaryItems",
    "inspectEnchantNames",
    "inspectEnchantSize",
    "inspectShowEnchants",
    "inspectShowItemLevel",
    "inspectShowUpgradeTrack",
    "itemStackModifier",
    "lfgRememberRoles",
    "lootIconBorder",
    "lootToastQualityStrip",
    "lootToastQualityStripMoney",
    "lootToastScale",
    "lootWindowBorderQualityColor",
    "mailAltList",
    "mailAltListMax",
    "mailAltListMinLevel",
    "mailAltListSort",
    "merchantBulkBuy",
    "merchantCols",
    "merchantExpand",
    "merchantListRowHeight",
    "merchantRows",
    "merchantShowAsList",
    "merchantShowItemLevel",
    "popupMenuButtonBackgroundColor",
    "popupMenuButtonTextColor",
    "popupMenuButtonTextColorMode",
    "queueTimerBarHeight",
    "queueTimerTextColor",
    "queueTimerTextOffsetY",
    "queueTimerTextSize",
    "reskinAchievements",
    "reskinAddonList",
    "reskinAdventureGuide",
    "reskinAuctionHouse",
    "reskinBNetToast",
    "reskinBagBar",
    "reskinCalendar",
    "reskinCatalyst",
    "reskinCollections",
    "reskinCraftOrders",
    "reskinDelvePicker",
    "reskinDelves",
    "reskinDressUp",
    "reskinExtraActionButton",
    "reskinFlagCarriers",
    "reskinGameMenu",
    "reskinGossip",
    "reskinGreatVault",
    "reskinGroupInvite",
    "reskinGuild",
    "reskinHousing",
    "reskinInspectRecipe",
    "reskinItemUpgrade",
    "reskinLFGMenu",
    "reskinLegacySystem",
    "reskinLoot",
    "reskinLootHistory",
    "reskinLootRoll",
    "reskinLootToast",
    "reskinMacros",
    "reskinMail",
    "reskinMerchant",
    "reskinMicroMenu",
    "reskinPlayerChoice",
    "reskinPlayerSpells",
    "reskinPopupsMenus",
    "reskinProfessions",
    "reskinProfessionsBook",
    "reskinQuest",
    "reskinQueuePopup",
    "reskinQueueStatus",
    "reskinReadyCheck",
    "reskinSettings",
    "reskinSocialUI",
    "reskinSocket",
    "reskinTrade",
    "reskinTrainer",
    "reskinTransmog",
    "reskinWidgetBars",
    "reskinWorldMap",
    "resurrectAcceptGlow",
    "showAdjustedStats",
    "showCharSheetDurability",
    "showEnchants",
    "showGems",
    "showIconID",
    "showItemID",
    "showItemLevel",
    "showItemMaxStacks",
    "showManaStat",
    "showMythicRating",
    "showPvpItemLevel",
    "showQueueTimer",
    "showSecondaryBoth",
    "showSecondaryRaw",
    "showSpellID",
    "showTertiaryBoth",
    "showTertiaryRaw",
    "showUpgradeTrack",
    "spellIDModifier",
    "statCategoryColors",
    "statCategoryUseColor",
    "statSectionsOrder",
    "themedCharacterSheet",
    "themedInspectSheet",
    "thirdPartySkinAddons",
    "thirdPartySkinsOff",
    "tooltipAFKTag",
    "tooltipAnchorCursor",
    "tooltipBgColor",
    "tooltipBgOpacity",
    "tooltipBorderSize",
    "tooltipBuffOffsetX",
    "tooltipBuffOffsetY",
    "tooltipBuffPosition",
    "tooltipBuffSize",
    "tooltipBuffsPerRow",
    "tooltipClassLineColor",
    "tooltipCompactLevel",
    "tooltipCursorOffsetX",
    "tooltipCursorOffsetY",
    "tooltipCursorPosition",
    "tooltipFactionColor",
    "tooltipFontScale",
    "tooltipGrowthDirection",
    "tooltipGuildmateColor",
    "tooltipHealthStripHeight",
    "tooltipHealthStripTexture",
    "tooltipHideHealthStrip",
    "tooltipItemLevel",
    "tooltipLevelColor",
    "tooltipMythicScore",
    "tooltipPlayerTitles",
    "tooltipShowBuffs",
    "tooltipShowGuildRank",
    "tooltipShowMode",
    "tooltipShowModifier",
    "tooltipShowMount",
    "tooltipShowTarget",
    "uberTooltips",
    "uberTooltipsManual",
    "widgetBarMinSize",
    "windowSkinStyleSlots",
    "tooltipBorderTexture",
    "tooltipBorderThickness",
    "tooltipBorderThicknessPx",
    "tooltipBorderColor",
    "tooltipBorderColorMode",
    "tooltipBorderOpacity",
    "tooltipBorderOffsetX",
    "tooltipBorderOffsetY",
    "tooltipBorderShiftX",
    "tooltipBorderShiftY",
    "tooltipBorderBehind",
    "popupMenuBorderTexture",
    "popupMenuBorderThickness",
    "popupMenuBorderThicknessPx",
    "popupMenuBorderColor",
    "popupMenuBorderColorMode",
    "popupMenuBorderOpacity",
    "popupMenuBorderOffsetX",
    "popupMenuBorderOffsetY",
    "popupMenuBorderShiftX",
    "popupMenuBorderShiftY",
    "popupMenuBorderBehind",
    "popupMenuButtonBorderTexture",
    "popupMenuButtonBorderThickness",
    "popupMenuButtonBorderThicknessPx",
    "popupMenuButtonBorderColor",
    "popupMenuButtonBorderColorMode",
    "popupMenuButtonBorderOpacity",
    "popupMenuButtonBorderOffsetX",
    "popupMenuButtonBorderOffsetY",
    "popupMenuButtonBorderShiftX",
    "popupMenuButtonBorderShiftY",
    "popupMenuButtonBorderBehind",
    "lootWindowBorderTexture",
    "lootWindowBorderThickness",
    "lootWindowBorderThicknessPx",
    "lootWindowBorderColor",
    "lootWindowBorderColorMode",
    "lootWindowBorderOpacity",
    "lootWindowBorderOffsetX",
    "lootWindowBorderOffsetY",
    "lootWindowBorderShiftX",
    "lootWindowBorderShiftY",
    "lootWindowBorderBehind",
    "lootIconBorderTexture",
    "lootIconBorderThickness",
    "lootIconBorderThicknessPx",
    "lootIconBorderColor",
    "lootIconBorderColorMode",
    "lootIconBorderOpacity",
    "lootIconBorderOffsetX",
    "lootIconBorderOffsetY",
    "lootIconBorderShiftX",
    "lootIconBorderShiftY",
    "lootIconBorderBehind",
    "blizzWindowModernBG",
    "charSheetCollapsedSections",
    "characterFramePos",
    "friendsFramePos",
    "lfgSavedRoles",
    "mailAltHidden",
    "tooltipFixedPos",
    "windowSkinsStockSeeded",
    "mailAltRoster",
    "someOtherSetting"
    }
    for _, k in ipairs(seeded) do CludesUIDB[k] = "x" end
    local ok, err = pcall(cfg.onReset)
    OUT:write("== reset ran " .. tostring(ok) .. " " .. tostring(err) .. "\n")
    local kept = {}
    for _, k in ipairs(seeded) do if CludesUIDB[k] ~= nil then kept[#kept + 1] = k end end
    OUT:write("== kept " .. table.concat(kept, " ") .. "\n")
end
