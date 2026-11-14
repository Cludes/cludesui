if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_FriendsKit.lua
--  The friends list pieces two modules share, so neither keeps a copy: the
--  Friends List module on retail, and Blizzard Skins+ on WoW Forever, where
--  the Friends List module never loads and the Window Skins "Friends List"
--  card hosts them (CludesUIBlizzardSkin_FriendsForever.lua):
--    - the realm -> region lookup and the region icons (public API);
--    - the 12.1 Social UI friend tiles (CludesUI.FriendsKit.StartTiles);
--    - auto-accepting group invites from friends (FriendsKit.SyncAutoAccept);
--    - the Class Icon Theme choices both settings pages offer.
--  At load this file only defines functions and constant tables: nothing
--  runs, registers or builds until a host starts it.
-------------------------------------------------------------------------------
local Kit = {}
CludesUI.FriendsKit = Kit

local MEDIA = "Interface\\AddOns\\CludesUI\\media\\friends\\"

-------------------------------------------------------------------------------
--  Realm -> region lookup for friend region detection
--  Mini regions: namerica, samerica, australia, europe, russia, korea, taiwan, china
--  Full regions: NA (namerica+samerica+australia), EU (europe+russia), KR, TW, CN
-------------------------------------------------------------------------------
local MINI_TO_FULL = {
    namerica = "NA",
    samerica = "NA",
    australia = "NA",
    europe = "EU",
    russia = "EU",
    korea = "KR",
    taiwan = "TW",
    china = "CN",
}

local REGION_ID_TO_FULL = {
    [1] = "NA", -- Americas + Oceania
    [2] = "KR",
    [3] = "EU", -- Europe + Russia
    [4] = "TW",
    [5] = "CN",
}

-- The realm tables, built on the first lookup (only friends list code reads
-- them, and only while a friends window is painted)
local REALMS_NA, REALMS_EU, REALMS_ASIA
local function LoadRealms()
    -- Region 1: Americas & Oceania
    REALMS_NA = {
        ["Azralon"] = "samerica",
        ["Gallywix"] = "samerica",
        ["Goldrinn"] = "samerica",
        ["Nemesis"] = "samerica",
        ["TolBarad"] = "samerica",
        ["Drakkari"] = "samerica",
        ["Quel'Thalas"] = "samerica",
        ["Ragnaros"] = "samerica",
        ["Loatheb"] = "samerica",
        ["Aman'Thul"] = "australia",
        ["Barthilas"] = "australia",
        ["Caelestrasz"] = "australia",
        ["Dath'Remar"] = "australia",
        ["Dreadmaul"] = "australia",
        ["Frostmourne"] = "australia",
        ["Gundrak"] = "australia",
        ["Jubei'Thos"] = "australia",
        ["Khaz'goroth"] = "australia",
        ["Nagrand"] = "australia",
        ["Saurfang"] = "australia",
        ["Thaurissan"] = "australia",
        ["Arugal"] = "australia",
        ["Yojamba"] = "australia",
        ["Remulos"] = "australia",
        ["Felstriker"] = "australia",
        ["Shadowstrike"] = "australia",
        ["Penance"] = "australia",
        ["Aegwynn"] = "namerica",
        ["AeriePeak"] = "namerica",
        ["Agamaggan"] = "namerica",
        ["Aggramar"] = "namerica",
        ["Akama"] = "namerica",
        ["Alexstrasza"] = "namerica",
        ["Alleria"] = "namerica",
        ["AltarofStorms"] = "namerica",
        ["AlteracMountains"] = "namerica",
        ["Andorhal"] = "namerica",
        ["Anetheron"] = "namerica",
        ["Antonidas"] = "namerica",
        ["Anub'arak"] = "namerica",
        ["Anvilmar"] = "namerica",
        ["Arathor"] = "namerica",
        ["Archimonde"] = "namerica",
        ["Area52"] = "namerica",
        ["ArgentDawn"] = "namerica",
        ["Arthas"] = "namerica",
        ["Arygos"] = "namerica",
        ["Auchindoun"] = "namerica",
        ["Azgalor"] = "namerica",
        ["AzjolNerub"] = "namerica",
        ["Azshara"] = "namerica",
        ["Azuremyst"] = "namerica",
        ["Baelgun"] = "namerica",
        ["Balnazzar"] = "namerica",
        ["BlackDragonflight"] = "namerica",
        ["Blackhand"] = "namerica",
        ["Blackrock"] = "namerica",
        ["BlackwaterRaiders"] = "namerica",
        ["BlackwingLair"] = "namerica",
        ["Blade'sEdge"] = "namerica",
        ["Bladefist"] = "namerica",
        ["BleedingHollow"] = "namerica",
        ["BloodFurnace"] = "namerica",
        ["Bloodhoof"] = "namerica",
        ["Bloodscalp"] = "namerica",
        ["Bonechewer"] = "namerica",
        ["BoreanTundra"] = "namerica",
        ["Boulderfist"] = "namerica",
        ["Bronzebeard"] = "namerica",
        ["BurningBlade"] = "namerica",
        ["BurningLegion"] = "namerica",
        ["Cairne"] = "namerica",
        ["CenarionCircle"] = "namerica",
        ["Cenarius"] = "namerica",
        ["Cho'gall"] = "namerica",
        ["Chromaggus"] = "namerica",
        ["Coilfang"] = "namerica",
        ["Crushridge"] = "namerica",
        ["Daggerspine"] = "namerica",
        ["Dalaran"] = "namerica",
        ["Dalvengyr"] = "namerica",
        ["DarkIron"] = "namerica",
        ["Darkspear"] = "namerica",
        ["Darrowmere"] = "namerica",
        ["Dawnbringer"] = "namerica",
        ["Deathwing"] = "namerica",
        ["DemonSoul"] = "namerica",
        ["Dentarg"] = "namerica",
        ["Destromath"] = "namerica",
        ["Dethecus"] = "namerica",
        ["Detheroc"] = "namerica",
        ["Doomhammer"] = "namerica",
        ["Draenor"] = "namerica",
        ["Dragonblight"] = "namerica",
        ["Dragonmaw"] = "namerica",
        ["Drenden"] = "namerica",
        ["Dunemaul"] = "namerica",
        ["Durotan"] = "namerica",
        ["Duskwood"] = "namerica",
        ["EarthenRing"] = "namerica",
        ["EchoIsles"] = "namerica",
        ["Eitrigg"] = "namerica",
        ["Eldre'Thalas"] = "namerica",
        ["Elune"] = "namerica",
        ["EmeraldDream"] = "namerica",
        ["Eonar"] = "namerica",
        ["Eredar"] = "namerica",
        ["Executus"] = "namerica",
        ["Exodar"] = "namerica",
        ["Farstriders"] = "namerica",
        ["Feathermoon"] = "namerica",
        ["Fenris"] = "namerica",
        ["Firetree"] = "namerica",
        ["Fizzcrank"] = "namerica",
        ["Frostmane"] = "namerica",
        ["Frostwolf"] = "namerica",
        ["Galakrond"] = "namerica",
        ["Garithos"] = "namerica",
        ["Garona"] = "namerica",
        ["Garrosh"] = "namerica",
        ["Ghostlands"] = "namerica",
        ["Gilneas"] = "namerica",
        ["Gnomeregan"] = "namerica",
        ["Gorefiend"] = "namerica",
        ["Gorgonnash"] = "namerica",
        ["Greymane"] = "namerica",
        ["GrizzlyHills"] = "namerica",
        ["Gul'dan"] = "namerica",
        ["Gurubashi"] = "namerica",
        ["Hakkar"] = "namerica",
        ["Haomarush"] = "namerica",
        ["Hellscream"] = "namerica",
        ["Hydraxis"] = "namerica",
        ["Hyjal"] = "namerica",
        ["Icecrown"] = "namerica",
        ["Illidan"] = "namerica",
        ["Jaedenar"] = "namerica",
        ["Kael'thas"] = "namerica",
        ["Kalecgos"] = "namerica",
        ["Kargath"] = "namerica",
        ["Kel'Thuzad"] = "namerica",
        ["Khadgar"] = "namerica",
        ["KhazModan"] = "namerica",
        ["Kil'jaeden"] = "namerica",
        ["Kilrogg"] = "namerica",
        ["KirinTor"] = "namerica",
        ["Korgath"] = "namerica",
        ["Korialstrasz"] = "namerica",
        ["KulTiras"] = "namerica",
        ["LaughingSkull"] = "namerica",
        ["Lethon"] = "namerica",
        ["Lightbringer"] = "namerica",
        ["Lightning'sBlade"] = "namerica",
        ["Lightninghoof"] = "namerica",
        ["Llane"] = "namerica",
        ["Lothar"] = "namerica",
        ["Madoran"] = "namerica",
        ["Maelstrom"] = "namerica",
        ["Magtheridon"] = "namerica",
        ["Maiev"] = "namerica",
        ["Mal'Ganis"] = "namerica",
        ["Malfurion"] = "namerica",
        ["Malorne"] = "namerica",
        ["Malygos"] = "namerica",
        ["Mannoroth"] = "namerica",
        ["Medivh"] = "namerica",
        ["Misha"] = "namerica",
        ["Mok'Nathal"] = "namerica",
        ["MoonGuard"] = "namerica",
        ["Moonrunner"] = "namerica",
        ["Mug'thol"] = "namerica",
        ["Muradin"] = "namerica",
        ["Nathrezim"] = "namerica",
        ["Nazgrel"] = "namerica",
        ["Nazjatar"] = "namerica",
        ["Ner'zhul"] = "namerica",
        ["Nesingwary"] = "namerica",
        ["Nordrassil"] = "namerica",
        ["Norgannon"] = "namerica",
        ["Onyxia"] = "namerica",
        ["Perenolde"] = "namerica",
        ["Proudmoore"] = "namerica",
        ["Quel'dorei"] = "namerica",
        ["Ravencrest"] = "namerica",
        ["Ravenholdt"] = "namerica",
        ["Rexxar"] = "namerica",
        ["Rivendare"] = "namerica",
        ["Runetotem"] = "namerica",
        ["Sargeras"] = "namerica",
        ["ScarletCrusade"] = "namerica",
        ["Scilla"] = "namerica",
        ["Sen'jin"] = "namerica",
        ["Sentinels"] = "namerica",
        ["ShadowCouncil"] = "namerica",
        ["Shadowmoon"] = "namerica",
        ["Shadowsong"] = "namerica",
        ["Shandris"] = "namerica",
        ["ShatteredHalls"] = "namerica",
        ["ShatteredHand"] = "namerica",
        ["Shu'halo"] = "namerica",
        ["SilverHand"] = "namerica",
        ["Silvermoon"] = "namerica",
        ["SistersofElune"] = "namerica",
        ["Skullcrusher"] = "namerica",
        ["Skywall"] = "namerica",
        ["Smolderthorn"] = "namerica",
        ["Spinebreaker"] = "namerica",
        ["Spirestone"] = "namerica",
        ["Staghelm"] = "namerica",
        ["SteamwheedleCartel"] = "namerica",
        ["Stonemaul"] = "namerica",
        ["Stormrage"] = "namerica",
        ["Stormreaver"] = "namerica",
        ["Stormscale"] = "namerica",
        ["Suramar"] = "namerica",
        ["Tanaris"] = "namerica",
        ["Terenas"] = "namerica",
        ["Terokkar"] = "namerica",
        ["TheForgottenCoast"] = "namerica",
        ["TheScryers"] = "namerica",
        ["TheUnderbog"] = "namerica",
        ["TheVentureCo"] = "namerica",
        ["ThoriumBrotherhood"] = "namerica",
        ["Thrall"] = "namerica",
        ["Thunderhorn"] = "namerica",
        ["Thunderlord"] = "namerica",
        ["Tichondrius"] = "namerica",
        ["Tortheldrin"] = "namerica",
        ["Trollbane"] = "namerica",
        ["Turalyon"] = "namerica",
        ["TwistingNether"] = "namerica",
        ["Uldaman"] = "namerica",
        ["Uldum"] = "namerica",
        ["Undermine"] = "namerica",
        ["Ursin"] = "namerica",
        ["Uther"] = "namerica",
        ["Vashj"] = "namerica",
        ["Vek'nilash"] = "namerica",
        ["Velen"] = "namerica",
        ["Warsong"] = "namerica",
        ["Whisperwind"] = "namerica",
        ["Wildhammer"] = "namerica",
        ["Windrunner"] = "namerica",
        ["Winterhoof"] = "namerica",
        ["WyrmrestAccord"] = "namerica",
        ["Ysera"] = "namerica",
        ["Ysondre"] = "namerica",
        ["Zangarmarsh"] = "namerica",
        ["Zul'jin"] = "namerica",
        ["Zuluhed"] = "namerica",
        ["Ashkandi"] = "namerica",
        ["Atiesh"] = "namerica",
        ["Benediction"] = "namerica",
        ["BloodsailBuccaneers"] = "namerica",
        ["Faerlina"] = "namerica",
        ["Grobbulus"] = "namerica",
        ["Mankrik"] = "namerica",
        ["OldBlanchy"] = "namerica",
        ["Westfall"] = "namerica",
        ["Whitemane"] = "namerica",
        ["ChaosBolt"] = "namerica",
        ["CrusaderStrike"] = "namerica",
        ["DefiasPillager"] = "namerica",
        ["Doomhowl"] = "namerica",
        ["Dreamscythe"] = "namerica",
        ["LavaLash"] = "namerica",
        ["LivingFlame"] = "namerica",
        ["LoneWolf"] = "namerica",
        ["Nightslayer"] = "namerica",
        ["Pagle"] = "namerica",
        ["SkullRock"] = "namerica",
        ["WildGrowth"] = "namerica",
        ["Maladath"] = "australia",
    }

    -- Region 3: Europe & Russia
    REALMS_EU = {
        ["Aegwynn"] = "europe",
        ["Alexstrasza"] = "europe",
        ["Alleria"] = "europe",
        ["Ambossar"] = "europe",
        ["Aman'Thul"] = "europe",
        ["Antonidas"] = "europe",
        ["Anub'arak"] = "europe",
        ["Area52"] = "europe",
        ["Arthas"] = "europe",
        ["Arygos"] = "europe",
        ["Azshara"] = "europe",
        ["Baelgun"] = "europe",
        ["Blackhand"] = "europe",
        ["Blackmoore"] = "europe",
        ["Blackrock"] = "europe",
        ["Blutkessel"] = "europe",
        ["Dalvengyr"] = "europe",
        ["DasKonsortium"] = "europe",
        ["DasSyndikat"] = "europe",
        ["DerMithrilorden"] = "europe",
        ["DerRatvonDalaran"] = "europe",
        ["Destromath"] = "europe",
        ["Dethecus"] = "europe",
        ["DieAldor"] = "europe",
        ["DieArguswacht"] = "europe",
        ["DieewigeWacht"] = "europe",
        ["DieNachtwache"] = "europe",
        ["DieSilberneHand"] = "europe",
        ["DieTodeskrallen"] = "europe",
        ["DunMorogh"] = "europe",
        ["Echsenkessel"] = "europe",
        ["Eredar"] = "europe",
        ["Everlook"] = "europe",
        ["FestungderSt\195\188rme"] = "europe",
        ["Forscherliga"] = "europe",
        ["Frostmourne"] = "europe",
        ["Frostwolf"] = "europe",
        ["Garrosh"] = "europe",
        ["Gilneas"] = "europe",
        ["Gorgonnash"] = "europe",
        ["Gul'dan"] = "europe",
        ["Kargath"] = "europe",
        ["Kel'Thuzad"] = "europe",
        ["Khaz'goroth"] = "europe",
        ["Kil'jaeden"] = "europe",
        ["Krag'jin"] = "europe",
        ["Lothar"] = "europe",
        ["Madmortem"] = "europe",
        ["Mal'Ganis"] = "europe",
        ["Malfurion"] = "europe",
        ["Malorne"] = "europe",
        ["Malygos"] = "europe",
        ["Mannoroth"] = "europe",
        ["Mug'thol"] = "europe",
        ["Nathrezim"] = "europe",
        ["Nazjatar"] = "europe",
        ["Nera'thor"] = "europe",
        ["Nethersturm"] = "europe",
        ["Norgannon"] = "europe",
        ["Nozdormu"] = "europe",
        ["Onyxia"] = "europe",
        ["Perenolde"] = "europe",
        ["Proudmoore"] = "europe",
        ["Rajaxx"] = "europe",
        ["Rexxar"] = "europe",
        ["Sen'jin"] = "europe",
        ["Shattrath"] = "europe",
        ["Shen'dralar"] = "europe",
        ["SteamwheedleCartel"] = "europe",
        ["Taerar"] = "europe",
        ["Teldrassil"] = "europe",
        ["Terrordar"] = "europe",
        ["Theradras"] = "europe",
        ["Thrall"] = "europe",
        ["Tichondrius"] = "europe",
        ["Tirion"] = "europe",
        ["Todeswache"] = "europe",
        ["Ulduar"] = "europe",
        ["Un'Goro"] = "europe",
        ["Vek'lor"] = "europe",
        ["Venoxis"] = "europe",
        ["Wrathbringer"] = "europe",
        ["Ysera"] = "europe",
        ["ZirkeldesCenarius"] = "europe",
        ["Zuluhed"] = "europe",
        ["Arak-arahm"] = "europe",
        ["Arathi"] = "europe",
        ["Archimonde"] = "europe",
        ["Auberdine"] = "europe",
        ["Chants\195\169ternels"] = "europe",
        ["Cho'gall"] = "europe",
        ["Chromaggus"] = "europe",
        ["Confr\195\169rieduThorium"] = "europe",
        ["ConseildesOmbres"] = "europe",
        ["CulteDeLaRiveNoire"] = "europe",
        ["Dalaran"] = "europe",
        ["Drek'Thar"] = "europe",
        ["Eitrigg"] = "europe",
        ["Eldre'Thalas"] = "europe",
        ["Elune"] = "europe",
        ["Garona"] = "europe",
        ["Hyjal"] = "europe",
        ["Illidan"] = "europe",
        ["Kael'thas"] = "europe",
        ["KhazModan"] = "europe",
        ["KirinTor"] = "europe",
        ["Krasus"] = "europe",
        ["LaCroisade\195\169carlate"] = "europe",
        ["LesClairvoyants"] = "europe",
        ["LesSentinelles"] = "europe",
        ["Mar\195\169cagedeZangar"] = "europe",
        ["Medivh"] = "europe",
        ["Naxxramas"] = "europe",
        ["Ner'zhul"] = "europe",
        ["Rashgarroth"] = "europe",
        ["Sargeras"] = "europe",
        ["Sinstralis"] = "europe",
        ["Suramar"] = "europe",
        ["Templenoir"] = "europe",
        ["Throk'Feroth"] = "europe",
        ["Uldaman"] = "europe",
        ["Varimathras"] = "europe",
        ["Vol'jin"] = "europe",
        ["Ysondre"] = "europe",
        ["C'Thun"] = "europe",
        ["ColinasPardas"] = "europe",
        ["DunModr"] = "europe",
        ["Exodar"] = "europe",
        ["LosErrantes"] = "europe",
        ["Mandokir"] = "europe",
        ["Minahonda"] = "europe",
        ["Sanguino"] = "europe",
        ["Shen'dralar"] = "europe",
        ["Tyrande"] = "europe",
        ["Uldum"] = "europe",
        ["Zul'jin"] = "europe",
        ["Nemesis"] = "europe",
        ["Pozzodell'Eternit\195\160"] = "europe",
        ["Aggra"] = "europe",
        ["GrimBatol"] = "europe",
        ["Ashenvale"] = "russia",
        ["Azuregos"] = "russia",
        ["Blackscar"] = "russia",
        ["BootyBay"] = "russia",
        ["BoreanTundra"] = "russia",
        ["Chromie"] = "russia",
        ["Deathguard"] = "russia",
        ["Deepholm"] = "russia",
        ["Eversong"] = "russia",
        ["Flamegor"] = "russia",
        ["Fordragon"] = "russia",
        ["Galakrond"] = "russia",
        ["Goldrinn"] = "russia",
        ["Gordunni"] = "russia",
        ["Grommash"] = "russia",
        ["HowlingFjord"] = "russia",
        ["LichKing"] = "russia",
        ["MoltenCore"] = "russia",
        ["Razuvious"] = "russia",
        ["Soulflayer"] = "russia",
        ["Theradras"] = "russia",
        ["Thermaplugg"] = "russia",
        ["Wyrmthalak"] = "russia",
        ["Agamaggan"] = "europe",
        ["Aggramar"] = "europe",
        ["Ahn'Qiraj"] = "europe",
        ["Al'Akir"] = "europe",
        ["Alonsus"] = "europe",
        ["Anachronos"] = "europe",
        ["Arathor"] = "europe",
        ["ArgentDawn"] = "europe",
        ["Aszune"] = "europe",
        ["Auchindoun"] = "europe",
        ["AzjolNerub"] = "europe",
        ["Azuremyst"] = "europe",
        ["Balnazzar"] = "europe",
        ["Blade'sEdge"] = "europe",
        ["Bladefist"] = "europe",
        ["Bloodfeather"] = "europe",
        ["Bloodhoof"] = "europe",
        ["Bloodscalp"] = "europe",
        ["Boulderfist"] = "europe",
        ["Bronzebeard"] = "europe",
        ["BronzeDragonflight"] = "europe",
        ["BurningBlade"] = "europe",
        ["BurningLegion"] = "europe",
        ["BurningSteppes"] = "europe",
        ["ChamberofAspects"] = "europe",
        ["Chromaggus"] = "europe",
        ["Crushridge"] = "europe",
        ["Daggerspine"] = "europe",
        ["DarkmoonFaire"] = "europe",
        ["Darksorrow"] = "europe",
        ["Darkspear"] = "europe",
        ["Deathwing"] = "europe",
        ["DefiasBrotherhood"] = "europe",
        ["Dentarg"] = "europe",
        ["Doomhammer"] = "europe",
        ["Draenor"] = "europe",
        ["Dragonblight"] = "europe",
        ["Dragonmaw"] = "europe",
        ["Drak'thul"] = "europe",
        ["Dunemaul"] = "europe",
        ["EarthenRing"] = "europe",
        ["EmeraldDream"] = "europe",
        ["Emeriss"] = "europe",
        ["Eonar"] = "europe",
        ["Executus"] = "europe",
        ["Frostmane"] = "europe",
        ["Frostwhisper"] = "europe",
        ["Genjuros"] = "europe",
        ["Ghostlands"] = "europe",
        ["GrimBatol"] = "europe",
        ["Hakkar"] = "europe",
        ["Haomarush"] = "europe",
        ["Hellfire"] = "europe",
        ["Hellscream"] = "europe",
        ["Jaedenar"] = "europe",
        ["Karazhan"] = "europe",
        ["Kazzak"] = "europe",
        ["Khadgar"] = "europe",
        ["Kilrogg"] = "europe",
        ["Kor'gall"] = "europe",
        ["KulTiras"] = "europe",
        ["LaughingSkull"] = "europe",
        ["Lightbringer"] = "europe",
        ["Lightning'sBlade"] = "europe",
        ["Magtheridon"] = "europe",
        ["Mazrigos"] = "europe",
        ["Moonglade"] = "europe",
        ["Nagrand"] = "europe",
        ["Neptulon"] = "europe",
        ["Nordrassil"] = "europe",
        ["Outland"] = "europe",
        ["Quel'Thalas"] = "europe",
        ["Ragnaros"] = "europe",
        ["Ravencrest"] = "europe",
        ["Ravenholdt"] = "europe",
        ["Runetotem"] = "europe",
        ["Saurfang"] = "europe",
        ["ScarshieldLegion"] = "europe",
        ["Shadowsong"] = "europe",
        ["ShatteredHalls"] = "europe",
        ["ShatteredHand"] = "europe",
        ["Silvermoon"] = "europe",
        ["Skullcrusher"] = "europe",
        ["Spinebreaker"] = "europe",
        ["Sporeggar"] = "europe",
        ["Stormrage"] = "europe",
        ["Stormreaver"] = "europe",
        ["Stormscale"] = "europe",
        ["Sunstrider"] = "europe",
        ["Sylvanas"] = "europe",
        ["Talnivarr"] = "europe",
        ["TarrenMill"] = "europe",
        ["Terenas"] = "europe",
        ["Terokkar"] = "europe",
        ["TheMaelstrom"] = "europe",
        ["TheSha'tar"] = "europe",
        ["TheVentureCo"] = "europe",
        ["Thunderhorn"] = "europe",
        ["Trollbane"] = "europe",
        ["Turalyon"] = "europe",
        ["Twilight'sHammer"] = "europe",
        ["TwistingNether"] = "europe",
        ["Vashj"] = "europe",
        ["Vek'nilash"] = "europe",
        ["Wildhammer"] = "europe",
        ["Xavius"] = "europe",
        ["Zenedar"] = "europe",
        ["Firemaw"] = "europe",
        ["Gehennas"] = "europe",
        ["Golemagg"] = "europe",
        ["MirageRaceway"] = "europe",
        ["Mograine"] = "europe",
        ["Nek'Rosh"] = "europe",
        ["PyrewoodVillage"] = "europe",
        ["Soulseeker"] = "europe",
        ["Spineshatter"] = "europe",
        ["Stitches"] = "europe",
        ["Thunderstrike"] = "europe",
        ["WildGrowth"] = "europe",
        ["ZandalarTribe"] = "europe",
    }

    -- Regions 2, 4, 5: Korea, Taiwan, China
    REALMS_ASIA = {
        ["AbyssalMaw"] = "china",
        ["AeriePeakCN"] = "china",
        ["Akil'zon"] = "china",
        ["Algalon"] = "china",
        ["Chronos"] = "china",
        ["Goldshire"] = "china",
        ["LichKing"] = "china",
        ["Onyxia"] = "china",
        ["SilverHand"] = "china",
        ["SilvermoonCN"] = "china",
        ["TitanReforged"] = "china",
        ["Azshara"] = "korea",
        ["BurningLegion"] = "korea",
        ["Cenarius"] = "korea",
        ["Deathwing"] = "korea",
        ["Durotan"] = "korea",
        ["Frostmourne"] = "korea",
        ["Hellscream"] = "korea",
        ["Hyjal"] = "korea",
        ["Ragnaros"] = "korea",
        ["Windrunner"] = "korea",
        ["Zul'jin"] = "korea",
        ["Arthas"] = "taiwan",
        ["Arygos"] = "taiwan",
        ["BleedingHollow"] = "taiwan",
        ["ChillwindPoint"] = "taiwan",
        ["CrystalpineStinger"] = "taiwan",
        ["DemonFallCanyon"] = "taiwan",
        ["Dragonmaw"] = "taiwan",
        ["Frostmane"] = "taiwan",
        ["Global"] = "taiwan",
        ["Icecrown"] = "taiwan",
        ["KrolBlade"] = "taiwan",
        ["Light'sHope"] = "taiwan",
        ["Menethil"] = "taiwan",
        ["Nightsong"] = "taiwan",
        ["OldBlanchy"] = "taiwan",
        ["OrderoftheCloudSerpent"] = "taiwan",
        ["Quel'dorei"] = "taiwan",
        ["Shadowmoon"] = "taiwan",
        ["Skywall"] = "taiwan",
        ["Spirestone"] = "taiwan",
        ["Stormscale"] = "taiwan",
        ["WorldTree"] = "taiwan",
        ["Whisperwind"] = "taiwan",
        ["Wrathbringer"] = "taiwan",
        ["ZealotBlade"] = "taiwan",
    }
end

local REGION_ICON_PATH = MEDIA .. "regions\\"

-- Lookup a realm name -> mini region realmName should have spaces removed
local function GetRealmMiniRegion(realmName)
    if not realmName or realmName == "" then
        return nil
    end
    if not REALMS_NA then
        LoadRealms()
    end
    local clean = realmName:gsub("%s+", "")
    -- Check player's own region table first (handles overlapping realm names)
    local myRegion = GetCurrentRegion()
    local primary, secondary
    if myRegion == 3 then
        primary, secondary = REALMS_EU, REALMS_NA
    elseif myRegion == 2 or myRegion == 4 or myRegion == 5 then
        primary, secondary = REALMS_ASIA, REALMS_NA
    else
        primary, secondary = REALMS_NA, REALMS_EU
    end
    return primary[clean] or secondary[clean] or REALMS_ASIA[clean]
end

-- Get the mini region for a BNet friend's game account
local function GetFriendMiniRegion(gameAccountInfo)
    if not gameAccountInfo then
        return nil
    end
    -- Try realmName first
    local realm = gameAccountInfo.realmName
    if realm and realm ~= "" then
        local result = GetRealmMiniRegion(realm)
        if result then
            return result
        end
    end
    -- Fallback: parse richPresence ("Zone - Realm" format)
    -- If realmName was empty, the friend is likely cross-region, so check OTHER tables first
    local rich = gameAccountInfo.richPresence
    if rich and rich ~= "" then
        local realmFromRich = rich:match("%s%-%s(.+)$")
        if realmFromRich and realmFromRich ~= "" then
            if not REALMS_NA then
                LoadRealms()
            end
            local clean = realmFromRich:gsub("%s+", "")
            local myRegion = GetCurrentRegion()
            -- Check the opposite region first since empty realmName = cross-region friend
            if myRegion == 1 then
                return REALMS_EU[clean] or REALMS_ASIA[clean] or REALMS_NA[clean]
            elseif myRegion == 3 then
                return REALMS_NA[clean] or REALMS_ASIA[clean] or REALMS_EU[clean]
            else
                return REALMS_NA[clean] or REALMS_EU[clean] or REALMS_ASIA[clean]
            end
        end
    end
    return nil
end

-- Get the full region for a mini region
local function GetFullRegion(miniRegion)
    return miniRegion and MINI_TO_FULL[miniRegion]
end

-- Get the player's own full region
local function GetMyFullRegion()
    return REGION_ID_TO_FULL[GetCurrentRegion()] or "NA"
end

-- Get the icon path for a mini region
local function GetRegionIcon(miniRegion)
    if not miniRegion then
        return nil
    end
    return REGION_ICON_PATH .. miniRegion .. ".png"
end

-- Public API
CludesUI.GetRealmMiniRegion = GetRealmMiniRegion
CludesUI.GetFriendMiniRegion = GetFriendMiniRegion
CludesUI.GetFullRegion = GetFullRegion
CludesUI.GetMyFullRegion = GetMyFullRegion
CludesUI.GetRegionIcon = GetRegionIcon
CludesUI.MINI_TO_FULL = MINI_TO_FULL

-------------------------------------------------------------------------------
--  Class colour escape per class file (lazy-built cache)
-------------------------------------------------------------------------------
local classColorCodes = {}
function Kit.ClassColorCode(classFile)
    local code = classColorCodes[classFile]
    if code then
        return code
    end
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not cc then
        return nil
    end
    code = CludesUI.HexColor(cc.r, cc.g, cc.b)
    classColorCodes[classFile] = code
    return code
end

-- Class Icon Theme: the choices both settings pages list
Kit.ICON_STYLE_VALUES = {
    blizzard = "Blizzard",
    modern = "Modern",
    pixel = "Pixel",
    pixelsComic = "Comic",
    glyph = "Glyph",
    arcade = "Arcade",
    legend = "Legend",
    midnight = "Midnight",
    runic = "Runic",
}
Kit.ICON_STYLE_ORDER = {
    "blizzard",
    "modern",
    "pixel",
    "pixelsComic",
    "glyph",
    "arcade",
    "legend",
    "midnight",
    "runic",
}

-------------------------------------------------------------------------------
--  12.1 Social UI friend tiles
--
--  DECORATION ONLY. This file never creates a row, never writes element data,
--  and never mutates Blizzard's data provider. That restraint is the entire
--  design, and it is not stylistic caution -- it is the conclusion of a taint
--  bisect run against 12.1:
--
--    overlay off entirely .............................. whispers clean
--    our rows, every decoration disabled .............. whispers TAINTED
--    Blizzard's rows, only MoveNode re-parenting ...... whispers TAINTED
--
--  Any mutation of the friends list data taints the execution that Blizzard's
--  secure OnClick depends on; that reaches SetTellTarget, whose whisper target
--  is a secret value in 12.1, and BNet whispers stop opening. Styling was the
--  one thing the bisect cleared. So we style, and we touch nothing else.
--
--  Blizzard therefore owns: the ScrollBox, the provider, row creation, row
--  population, the click handler and the right-click menu. We own: paint.
--
--  A host starts it once per session (Kit.StartTiles) with its settings,
--  its look and its font, or for the custom friends list alone (cards =
--  false: nothing here touches Blizzard's cards); the host's settings page
--  repaints through Kit.RedecorateTiles.
-------------------------------------------------------------------------------
-- External weak-keyed state. Never write custom keys onto a Blizzard frame.
local FFD, GetFFD = CludesUI.NewFrameData()

-------------------------------------------------------------------------------
--  Tuning
-------------------------------------------------------------------------------
-- ROW HEIGHT IS BLIZZARD'S. DO NOT TRY TO CHANGE IT.
--
-- Their height is 70 (85 with larger text), from
-- FriendsListSocialCardMixin.GetActiveBaseHeight, captured by REFERENCE into the view's
-- extent registration at its OnLoad -- before this addon exists, so replacing the mixin
-- function afterwards cannot reach it. The only lever is overwriting that stored
-- registration, i.e. writing into view's own TemplateRegistrations table.
--
-- That write was TESTED and it TAINTS BNet whispers: the extent calculator is
-- read during layout, layout builds the rows, and a row built from an execution
-- that read our value carries taint into the secure OnClick and on into
-- SetTellTarget (whose whisper target is a secret value in 12.1). With the
-- write disabled and every other decoration below still active, whispers are
-- clean -- so decoration is fine and this one write was the whole problem.
--
-- CLOSED. Two separate in-game tests, both TAINTED:
--   1. reg.baseHeight = 46 AND reg.baseHeightCalculator = our closure
--   2. reg.baseHeightCalculator = nil, reg.baseHeight = 46  (plain number,
--      nothing of ours executing inside their layout pass)
-- Test 2 is the decisive one: Blizzard's own code merely READS a number out of
-- its own table, and that is still enough. So it is not about our code running
-- in their path -- reading any value an addon wrote taints the execution, and
-- that execution builds the rows whose secure OnClick opens the whisper menu.
--
-- 70 (85 at larger text) is therefore a hard floor. The only remaining lever on
-- density is the GAME's text-size setting: CalculateScaledHeight runs the base
-- through TextSizeManager:GetScaledValueWeighted with scaleWeight 0.6, so a
-- below-default text size genuinely scales the row under 70.
--
-- So nothing here writes the row height. Do not re-attempt; both shapes are
-- already disproven. Another tile height is the custom friends list's
-- (CludesUI_FriendsList.lua): rows of our own drawn over Blizzard's list,
-- never a change to Blizzard's cards.
--
-- The tile's icon square: the name starts past it.
local TILE_TARGET_H = 46

-- Kill switch for all tile decoration. Proven taint-free, so this is only a
-- convenience for future bisects -- leave it true.
local TILE_PAINT = true

-- Left inset of the text block, derived rather than fixed: the class icon is a
-- square that spans the row height, so the text starts at rowHeight + a gutter.
-- Resolved per paint from the row's live height.
local TILE_TEXT_GAP = 4
-- Three lines, each its own size: Battle.net name / character name + level / location.
local TILE_NAME_SIZE = 15
local TILE_CHAR_SIZE = 12
local TILE_INFO_SIZE = 12
local TILE_LINE_GAP = -5
-- The row height is Blizzard's now (GetActiveBaseHeight = 70, or 85 in the
-- expanded text-size layout), and we cannot change it without touching their
-- view's extent calculator -- which is provider-adjacent, and provider contact
-- is what taints whispers. So the text block is anchored to the row's vertical
-- CENTRE rather than pinned to the top: it then sits correctly at any height
-- Blizzard picks. The block is centred per paint from its measured height (the
-- line count varies), so there is no fixed vertical offset any more.

local MODERN_BLIZZ_TEX = "Interface\\AddOns\\CludesUI\\media\\modern_blizz.png"
local TEX_BASE = "Interface\\AddOns\\CludesUI\\media\\textures\\"
local MB_L, MB_R, MB_T, MB_B = 0.25, 1, 0, 0.75

local TILE_ONLINE_MASK_TEX = TEX_BASE .. "gradient-lr.tga"
local TILE_ONLINE_BG_ALPHA = 0.25
local TILE_HOVER_MASK_TEX = TEX_BASE .. "fade-right.tga"
local TILE_HOVER_ALPHA = 0.2
-- Selection reuses the hover treatment and draws on its own layer ABOVE it, so
-- a selected row that is also hovered shows both and reads brighter.
local TILE_SEL_ALPHA = 0.4

local OFFLINE_ICON = MEDIA .. "offline.png"
local FACTION_TEX_ALLIANCE = MEDIA .. "alliance.png"
local FACTION_TEX_HORDE = MEDIA .. "horde.png"
local FACTION_TEX_NEUTRAL = MEDIA .. "neutral.png"

local CLASS_ICON_SPRITE_BASE = "Interface\\AddOns\\CludesUI\\media\\icons\\class-full\\"
local CLASS_ICON_SPRITE_TEX = {}
for _, look in ipairs({ "modern", "dark", "light", "clean" }) do
    CLASS_ICON_SPRITE_TEX[look] = CLASS_ICON_SPRITE_BASE .. look .. ".tga"
end
local CLASS_SPRITE_COORDS = CludesUI.CLASS_ICON_SPRITE_COORDS

-- The class icon sprite sheet of a Class Icon Theme style (the tiles and the
-- Friends module's legacy rows)
function Kit.ClassIconSprite(look)
    return CLASS_ICON_SPRITE_TEX[look] or (CLASS_ICON_SPRITE_BASE .. look .. ".tga")
end

local MINI_DISPLAY = {
    namerica = "North America",
    samerica = "South America",
    australia = "Australia",
    europe = "Europe",
    russia = "Russia",
    korea = "Korea",
    taiwan = "Taiwan",
    china = "China",
}

-- The status orb's atlas art, looked up at the first orb painted
local _orbFile, _orbL, _orbR, _orbT, _orbB
local _orbLooked = false
local function LookUpOrb()
    _orbLooked = true
    local details = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("lootroll-animreveal-a")
    if details and details.file then
        _orbFile = details.file
        local aL, aR = details.leftTexCoord or 0, details.rightTexCoord or 1
        local aT, aB = details.topTexCoord or 0, details.bottomTexCoord or 1
        _orbL, _orbR, _orbT, _orbB = aL, aL + (aR - aL) / 6, aT, aT + (aB - aT) / 2
    end
end

-- Paints the status orb's art (the atlas' first of 6 columns, top of 2 rows)
-- on tex (the tiles and the Friends module's legacy rows)
function Kit.StatusOrbArt(texture)
    if not _orbLooked then
        LookUpOrb()
    end
    if _orbFile then
        texture:SetTexture(_orbFile)
        texture:SetTexCoord(_orbL, _orbR, _orbT, _orbB)
    else
        texture:SetAtlas("lootroll-animreveal-a")
        texture:SetTexCoord(0, 1 / 6, 0, 0.5)
    end
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
-- The host this session (Kit.StartTiles): its settings table (the Friends
-- List profile's friends table, or the Blizzard Skins+ card's), its look and
-- its font key.
local hostRegion

local function Settings()
    return hostRegion and hostRegion.Settings()
end

local function Enabled()
    local f = Settings()
    return f ~= nil and f.enabled ~= false
end

local function FontPath()
    return (CludesUI.GetFontPath(hostRegion.fontKey)) or STANDARD_TEXT_FONT
end

local function GetClassFile(accountInfo)
    local gi = accountInfo and accountInfo.gameAccountInfo
    if not gi then
        return nil
    end
    if gi.classID and gi.classID > 0 then
        local _, classFile = GetClassInfo(gi.classID)
        if classFile then
            return classFile
        end
    end
    if gi.className then
        return CludesUI.ClassTokenFromLocalized(gi.className)
    end
    return nil
end

local function IsSameProjectOnline(gi)
    if not (gi and gi.isOnline) then
        return false
    end
    if gi.clientProgram ~= BNET_CLIENT_WOW then
        return false
    end
    return gi.wowProjectID == WOW_PROJECT_ID or gi.wowProjectID == nil
end

local function TileState(accountInfo)
    local gi = accountInfo and accountInfo.gameAccountInfo
    if not (gi and gi.isOnline) then
        return "offline"
    end
    return IsSameProjectOnline(gi) and "retail" or "other_game"
end

-------------------------------------------------------------------------------
--  One-time structure per pooled card
-------------------------------------------------------------------------------
local function SkinStructure(cardFrame)
    local d = GetFFD(cardFrame)
    if d.skinned then
        return d
    end
    d.skinned = true

    d.tileBg = cardFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
    d.tileBg:SetAllPoints()
    d.tileBg:SetColorTexture(0, 0, 0, 0.10)

    d.onlineBg = cardFrame:CreateTexture(nil, "BACKGROUND", nil, 3)
    d.onlineBg:SetTexture(MODERN_BLIZZ_TEX)
    d.onlineBg:SetTexCoord(MB_L, MB_R, MB_T, MB_B)
    d.onlineBg:SetAllPoints()
    d.onlineBg:SetAlpha(TILE_ONLINE_BG_ALPHA)
    d.onlineBg:Hide()
    d.onlineMask = cardFrame:CreateMaskTexture()
    d.onlineMask:SetTexture(TILE_ONLINE_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.onlineMask:SetAllPoints(d.onlineBg)
    d.onlineBg:AddMaskTexture(d.onlineMask)

    d.factionBg = cardFrame:CreateTexture(nil, "BACKGROUND", nil, 4)

    d.hoverBar = cardFrame:CreateTexture(nil, "ARTWORK", nil, -7)
    d.hoverBar:SetAllPoints()
    d.hoverBar:SetTexture(MODERN_BLIZZ_TEX)
    d.hoverBar:SetTexCoord(MB_L, MB_R, MB_T, MB_B)
    d.hoverBar:SetAlpha(TILE_HOVER_ALPHA)
    d.hoverBar:Hide()
    d.hoverMask = cardFrame:CreateMaskTexture()
    d.hoverMask:SetTexture(TILE_HOVER_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.hoverMask:SetAllPoints(d.hoverBar)
    d.hoverBar:AddMaskTexture(d.hoverMask)

    d.hoverFill = cardFrame:CreateTexture(nil, "ARTWORK", nil, -8)
    d.hoverFill:SetAllPoints()
    d.hoverFill:SetColorTexture(1, 1, 1, 0.02)
    d.hoverFill:SetBlendMode("ADD")
    d.hoverFill:Hide()

    cardFrame:HookScript("OnEnter", function()
        d.hoverBar:Show()
        d.hoverFill:Show()
    end)
    cardFrame:HookScript("OnLeave", function()
        d.hoverBar:Hide()
        d.hoverFill:Hide()
    end)

    -- Selection: same look as hover, own sublevels (-5/-6) so it sits above the
    -- hover pair (-7/-8) rather than replacing it. Its own mask texture, since
    -- AddMaskTexture is additive and sharing one would stack on the hover bar.
    d.selBar = cardFrame:CreateTexture(nil, "ARTWORK", nil, -5)
    d.selBar:SetAllPoints()
    d.selBar:SetTexture(MODERN_BLIZZ_TEX)
    d.selBar:SetTexCoord(MB_L, MB_R, MB_T, MB_B)
    d.selBar:SetAlpha(TILE_SEL_ALPHA)
    d.selBar:Hide()
    d.selMask = cardFrame:CreateMaskTexture()
    d.selMask:SetTexture(TILE_HOVER_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.selMask:SetAllPoints(d.selBar)
    d.selBar:AddMaskTexture(d.selMask)

    d.selFill = cardFrame:CreateTexture(nil, "ARTWORK", nil, -6)
    d.selFill:SetAllPoints()
    d.selFill:SetColorTexture(1, 1, 1, 0.02)
    d.selFill:SetBlendMode("ADD")
    d.selFill:Hide()

    d.classIcon = cardFrame:CreateTexture(nil, "ARTWORK", nil, 2)

    -- The three lines show friends' names and notes: font families (a family
    -- draws the scripts the chosen font lacks), never a plain SetFont.
    d.name = cardFrame:CreateFontString(nil, "OVERLAY")
    CludesUI.SetFontFamily(d.name, FontPath(), TILE_NAME_SIZE, "", true)
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)
    -- Horizontal inset is re-resolved per paint in PaintCard (it follows the
    -- row height); this is just the initial placement.
    d.name:SetPoint("TOPLEFT", cardFrame, "TOPLEFT", TILE_TARGET_H + TILE_TEXT_GAP, 0)

    -- Character name + level, its own line under the Battle.net name.
    d.charLine = cardFrame:CreateFontString(nil, "OVERLAY")
    CludesUI.SetFontFamily(d.charLine, FontPath(), TILE_CHAR_SIZE, "", true)
    d.charLine:SetJustifyH("LEFT")
    d.charLine:SetWordWrap(false)
    d.charLine:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, TILE_LINE_GAP)

    d.info = cardFrame:CreateFontString(nil, "OVERLAY")
    CludesUI.SetFontFamily(d.info, FontPath(), TILE_INFO_SIZE, "", true)
    d.info:SetJustifyH("LEFT")
    d.info:SetWordWrap(false)
    -- Anchored per paint: it follows charLine when there is one, otherwise the
    -- name directly, so offline friends do not leave a hole.

    d.orb = cardFrame:CreateTexture(nil, "OVERLAY", nil, 3)
    d.orb:SetSize(18, 18)
    Kit.StatusOrbArt(d.orb)

    return d
end

-- Blizzard repopulates its card art on every recycle, so this runs per paint.
local CARD_TEXT_KEYS = { "FriendName", "Name", "Level", "Class", "Location" }
local function SuppressBlizzardArt(cardFrame)
    if cardFrame.Background then
        cardFrame.Background:Hide()
        cardFrame.Background:SetAlpha(0)
    end
    local highlight = cardFrame.GetHighlightTexture and cardFrame:GetHighlightTexture()
    if highlight then
        highlight:SetAlpha(0)
        highlight:SetVertexColor(0, 0, 0, 0)
    end
    for idx = 1, #CARD_TEXT_KEYS do
        local fontStr = cardFrame[CARD_TEXT_KEYS[idx]]
        if fontStr then
            fontStr:Hide()
            fontStr:SetAlpha(0)
        end
    end
    if cardFrame.PresenceHolder then
        cardFrame.PresenceHolder:Hide()
        cardFrame.PresenceHolder:SetAlpha(0)
    end
    if cardFrame.StateDisplay then
        cardFrame.StateDisplay:Hide()
        cardFrame.StateDisplay:SetAlpha(0)
    end
    if cardFrame.GameIconHolder then
        cardFrame.GameIconHolder:Hide()
    end
end

-------------------------------------------------------------------------------
--  Per-paint passes
-------------------------------------------------------------------------------
local ClassColorCode = Kit.ClassColorCode

-- Line 1: the Battle.net account name on its own.
local function BuildName(accountInfo)
    if FriendsListUtil and FriendsListUtil.BuildFriendNameDisplayText then
        return FriendsListUtil.BuildFriendNameDisplayText(accountInfo)
    end
    return accountInfo.accountName or ""
end

-- The colour Blizzard uses for the location line, so the level suffix can match
-- it rather than the character name.
local function LocationColor(accountInfo)
    local gi = accountInfo.gameAccountInfo
    local online = gi ~= nil and gi.isOnline
    if online then
        return FRIENDS_GRAY_COLOR or NORMAL_FONT_COLOR
    end
    return DARKGRAY_COLOR or GRAY_FONT_COLOR
end

-- Line 2: character name (class-coloured) plus the level, the level tinted to
-- match the location line below it. Empty when the friend is not on a character
-- in this project, which collapses the row to two lines.
local function BuildCharLine(accountInfo)
    local gi = accountInfo.gameAccountInfo
    local charName = gi and gi.characterName
    if not (IsSameProjectOnline(gi) and charName and charName ~= "") then
        return ""
    end

    local isShown = charName
    local p = Settings()
    if p and p.classColorNames then
        local code = ClassColorCode(GetClassFile(accountInfo) or "")
        if code then
            isShown = code .. charName .. "|r"
        end
    end

    local lvl = gi.characterLevel
    if lvl then
        local levelText
        if SOCIAL_UI_RECENT_ALLIES_CARD_LEVEL_DISPLAY_FORMAT then
            levelText = format(SOCIAL_UI_RECENT_ALLIES_CARD_LEVEL_DISPLAY_FORMAT, lvl)
        else
            levelText = CludesUI.Lf("(Level %d)", lvl)
        end
        local c = LocationColor(accountInfo)
        if c and c.WrapTextInColorCode then
            levelText = c:WrapTextInColorCode(levelText)
        end
        isShown = isShown .. " " .. levelText
    end
    return isShown
end

-- WoW Forever friend's ruleset, the middle of richPresence
-- ("Forever - Roleplay PvP - Tirisfal Glades"), plus their region when it is
-- not ours. nil for anyone else. The project id is a literal: the client
-- defines its constant only on WoW Forever, and a viewer on another client
-- has such friends too.
local WOW_PROJECT_FOREVER = 18
-- realmName suffix ("CAMWOWUS2Realm10RPPvP") -> ruleset, for a richPresence
-- that names none: our own names, worded as the rich presence words them.
local function RealmRuleset(suffix)
    if suffix == "PvE" then
        return CludesUI.L("Normal")
    end
    if suffix == "PvP" then
        return CludesUI.L("PvP")
    end
    if suffix == "RP" then
        return CludesUI.L("Roleplay")
    end
    if suffix == "RPPvP" then
        return CludesUI.L("Roleplay PvP")
    end
end
local function ForeverRuleset(accountInfo)
    local gi = accountInfo and accountInfo.gameAccountInfo
    if not (gi and gi.isOnline and gi.wowProjectID == WOW_PROJECT_FOREVER) then
        return nil
    end
    local ruleset = gi.richPresence and gi.richPresence:match("^.- %- (.-) %- ")
    if not ruleset or ruleset == "" then
        ruleset = RealmRuleset(gi.realmName and gi.realmName:match("Realm%d+(%a+)$"))
    end
    if not ruleset then
        return nil
    end
    if gi.isInCurrentRegion == false and FriendsListUtil and FriendsListUtil.GetRegionName then
        ruleset = ruleset .. " (" .. FriendsListUtil.GetRegionName(accountInfo) .. ")"
    end
    return ruleset
end

local function BuildInfo(accountInfo)
    local textValue = ""
    if FriendsListUtil and FriendsListUtil.BuildLocationDisplayText then
        textValue = FriendsListUtil.BuildLocationDisplayText(accountInfo) or ""
    end
    -- A WoW Forever friend on our own client: the ruleset after the zone, in
    -- the zone's colour. Where Blizzard's line is the friend's rich presence
    -- instead (seen from another client, or no zone yet), that names the
    -- ruleset already.
    local gi = accountInfo.gameAccountInfo
    if gi and gi.areaName and IsSameProjectOnline(gi) then
        local ruleset = ForeverRuleset(accountInfo)
        if ruleset then
            textValue = textValue
                .. LocationColor(accountInfo):WrapTextInColorCode(
                    (gi.areaName ~= "" and " - " or "") .. ruleset
                )
        end
    end
    if textValue == "" then
        local cp = gi and gi.clientProgram
        if gi and gi.isOnline and (cp == "App" or cp == "BSAp") then
            local loc = GetLocale()
            textValue = (loc == "enUS" or loc == "enGB") and "In App" or "Battle.Net"
        end
    end
    -- Legacy ||<tag>:Group|| tags are stripped from any note we display.
    local note = CludesUI.StripFriendNoteTag(accountInfo.note)
    if note then
        if textValue ~= "" then
            textValue = textValue .. "  |cff888888|  " .. note .. "|r"
        else
            textValue = CludesUI.COLOR_CODES.DIM .. note .. "|r"
        end
    end
    return textValue
end

-- The chosen Class Icon Theme's art for one class on `icon`. Shared by the
-- CludesUI tile and the stock-style decoration.
local function SetClassIconTex(icon, look, classFile)
    if look == "blizzard" then
        icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then
            icon:SetTexCoord(unpack(coords))
        end
    else
        local coords = CLASS_SPRITE_COORDS[classFile]
        if coords then
            icon:SetTexture(Kit.ClassIconSprite(look))
            icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        end
    end
end

local function UpdateClassIcon(cardFrame, d, accountInfo)
    local p = Settings()
    if not (p and p.showClassIcons ~= false) then
        d.classIcon:Hide()
        return
    end

    local hgt = (cardFrame:GetHeight() or 0) - 4
    if hgt <= 0 then
        d.classIcon:Hide()
        return
    end

    local icon, state = d.classIcon, TileState(accountInfo)
    icon:ClearAllPoints()

    if state == "retail" then
        local inset = math.floor(hgt * 0.025 + 0.5)
        icon:SetPoint("LEFT", cardFrame, "LEFT", 4, 0)
        icon:SetPoint("TOP", cardFrame, "TOP", 0, -(2 + inset))
        icon:SetPoint("BOTTOM", cardFrame, "BOTTOM", 0, 2 + inset)
        local iconH = hgt - inset * 2
        if iconH > 0 then
            icon:SetWidth(iconH)
        end

        local classFile = GetClassFile(accountInfo)
        if not classFile then
            icon:Hide()
            return
        end

        SetClassIconTex(icon, p.iconStyle or "modern", classFile)
        icon:SetDesaturated(false)
        icon:SetAlpha(1)
    else
        local smallH = math.floor(hgt * 0.75)
        icon:SetSize(smallH, smallH)
        icon:SetPoint("LEFT", cardFrame, "LEFT", 4 + math.floor((hgt - smallH) / 2), 0)
        if state == "other_game" then
            local source = cardFrame.GameIconHolder and cardFrame.GameIconHolder.Icon
            local texture = source and source:GetTexture()
            if texture then
                icon:SetTexture(texture)
                icon:SetTexCoord(0, 1, 0, 1)
            end
            icon:SetAlpha(1)
        else
            icon:SetTexture(OFFLINE_ICON)
            icon:SetTexCoord(0, 1, 0, 1)
            icon:SetAlpha(0.5)
        end
        icon:SetDesaturated(false)
    end
    icon:Show()
end

local function UpdateFaction(cardFrame, d, accountInfo)
    local gi = accountInfo.gameAccountInfo
    local isRetail = IsSameProjectOnline(gi)
    local p = Settings()
    local show = not p or p.factionBanners ~= false

    local filePath = FACTION_TEX_NEUTRAL
    if show and isRetail and gi.factionName == "Alliance" then
        filePath = FACTION_TEX_ALLIANCE
    elseif show and isRetail and gi.factionName == "Horde" then
        filePath = FACTION_TEX_HORDE
    end

    local texture = d.factionBg
    texture:SetTexture(filePath)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", cardFrame, "TOPLEFT", 0, 0)
    texture:SetPoint("BOTTOMRIGHT", cardFrame, "BOTTOMRIGHT", 0, 0)
    texture:SetAlpha(0.2)
    texture:Show()
end

local function UpdateOrb(d, accountInfo)
    local gi = accountInfo.gameAccountInfo
    local isOnline = gi and gi.isOnline

    -- AFK/DND can arrive as secret values; never branch on them directly.
    local _isv = issecretvalue
    local rawAFK, rawDND = accountInfo.isAFK, accountInfo.isDND
    local isAFK = (not _isv or not _isv(rawAFK)) and rawAFK or false
    local isDND = (not _isv or not _isv(rawDND)) and rawDND or false

    local orb = d.orb
    orb:ClearAllPoints()
    orb:SetPoint("TOPLEFT", d.name, "TOPLEFT", (d.name:GetStringWidth() or 0) - 1, 2)

    if isOnline then
        if isDND then
            orb:SetVertexColor(1, 0.2, 0.2, 1)
        elseif isAFK then
            orb:SetVertexColor(1, 0.8, 0, 1)
        else
            orb:SetVertexColor(0.2, 1, 0.2, 1)
        end
    else
        orb:SetVertexColor(0.4, 0.4, 0.4, 0.6)
    end
    orb:Show()
end

-- Stock styles: a plain region mark (no mouse, so the row keeps every click
-- and hover; Blizzard's own tooltip already names a friend's region) in the
-- free corner above the 12.1 card's party button, or in the legacy row's
-- empty left gutter under its status icon (clear of the name, the favourite
-- star, the info line and the logo).
local STOCK_REGION_SIZE = 14
local function UpdateStockRegion(cardFrame, d, accountInfo)
    local p = Settings()
    local gi = accountInfo and accountInfo.gameAccountInfo
    -- Same-region friends never carry a mark: skip the realm lookup for them.
    if (p and p.showRegionIcons == false) or not gi or gi.isInCurrentRegion == true then
        if d.regionMark then
            d.regionMark:Hide()
        end
        return
    end
    local myFull = GetMyFullRegion()
    local mini = GetFriendMiniRegion(gi)
    local full = mini and GetFullRegion(mini)
    if not (mini and full and full ~= myFull) then
        if d.regionMark then
            d.regionMark:Hide()
        end
        return
    end
    local mark = d.regionMark
    if not mark then
        mark = cardFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        mark:SetSize(STOCK_REGION_SIZE, STOCK_REGION_SIZE)
        if cardFrame.PartyButton then
            mark:SetPoint("BOTTOM", cardFrame.PartyButton, "TOP", 0, 1)
        elseif cardFrame.status and cardFrame.gameIcon then
            mark:SetSize(12, 12)
            mark:SetPoint("TOP", cardFrame.status, "BOTTOM", 0, -1)
        else
            mark:SetPoint("TOPRIGHT", cardFrame, "TOPRIGHT", -12, -3)
        end
        d.regionMark = mark
    end
    if d.regionMini ~= mini then
        d.regionMini = mini
        mark:SetTexture(GetRegionIcon(mini))
        mark:SetTexCoord(0, 1, 0, 1)
    end
    mark:Show()
end

-- The region icon button on a friend's card or legacy row (frame; its state in
-- d, the frame's FFD entry): shown while show is true and the friend plays in
-- another region than ours, left of anchor (the frame's invite button) when
-- there is one. The tooltip names the region.
local function RegionOnEnter(self)
    CludesUI.ShowWidgetTooltip(self, self._regionLabel or "")
end
local function RegionOnLeave()
    CludesUI.HideWidgetTooltip()
end
function Kit.UpdateRegionButton(widget, d, gameAccountInfo, anchorFrame, show)
    -- Same-region friends never carry a mark.
    local mini = show
        and gameAccountInfo
        and gameAccountInfo.isInCurrentRegion ~= true
        and GetFriendMiniRegion(gameAccountInfo)
    local full = mini and GetFullRegion(mini)
    if not (mini and full and full ~= GetMyFullRegion()) then
        if d.regionBtn then
            d.regionBtn:Hide()
        end
        return
    end

    if not d.regionBtn then
        local rb = CreateFrame("Button", nil, widget)
        rb:SetFrameLevel(widget:GetFrameLevel() + 5)
        rb._tex = rb:CreateTexture(nil, "OVERLAY", nil, 7)
        rb._tex:SetAllPoints()
        rb._tex:SetAlpha(0.25)
        rb:SetScript("OnEnter", RegionOnEnter)
        rb:SetScript("OnLeave", RegionOnLeave)
        local iconH = math.floor((widget:GetHeight() or 40) * 0.8)
        rb:SetSize(iconH, iconH)
        if anchorFrame then
            rb:SetPoint("RIGHT", anchorFrame, "LEFT", -2, 0)
        else
            rb:SetPoint("RIGHT", widget, "RIGHT", -30, 0)
        end
        d.regionBtn = rb
    end

    local rb = d.regionBtn
    if rb._lastMini ~= mini then
        rb._lastMini = mini
        rb._tex:SetTexture(GetRegionIcon(mini))
        rb._tex:SetTexCoord(0, 1, 0, 1)
        rb._regionLabel = MINI_DISPLAY[mini] or mini
    end
    rb:Show()
end

local function UpdateRegion(cardFrame, d, accountInfo)
    local p = Settings()
    Kit.UpdateRegionButton(
        cardFrame,
        d,
        accountInfo.gameAccountInfo,
        cardFrame.PartyButton,
        not (p and p.showRegionIcons == false)
    )
end

-------------------------------------------------------------------------------
--  Paint
-------------------------------------------------------------------------------
local function PaintCard(cardFrame)
    if not TILE_PAINT then
        return
    end
    if not Enabled() then
        return
    end
    -- The custom friends list (CludesUI_FriendsList.lua) covers Blizzard's
    -- cards while it shows: they stay unpainted, on file for the catch-up
    -- when it stands down (Kit.RedecorateTiles).
    if Kit._listShown then
        GetFFD(cardFrame)
        return
    end

    local ed = cardFrame.elementData
    local accountInfo = ed and ed.accountInfo
    if not accountInfo then
        return
    end

    local d = SkinStructure(cardFrame)
    SuppressBlizzardArt(cardFrame)

    local charText = BuildCharLine(accountInfo)
    local hasChar = charText ~= ""

    d.name:SetText(BuildName(accountInfo))
    d.charLine:SetText(charText)
    d.charLine:SetShown(hasChar)
    d.info:SetText(BuildInfo(accountInfo))

    -- Every string arrives pre-wrapped in Blizzard colour codes, so the
    -- FontStrings stay white or they would tint the markup.
    d.name:SetTextColor(1, 1, 1, 1)
    d.charLine:SetTextColor(1, 1, 1, 1)
    d.info:SetTextColor(1, 1, 1, 1)

    -- The location follows whichever line is above it, so a friend with no
    -- character does not leave a gap.
    d.info:ClearAllPoints()
    d.info:SetPoint("TOPLEFT", hasChar and d.charLine or d.name, "BOTTOMLEFT", 0, TILE_LINE_GAP)

    -- Centre the block vertically. Its height depends on the line count, so it
    -- is measured rather than assumed -- Blizzard's row is 70 and the block is
    -- far shorter, and a fixed offset would sit wrong on two-line rows.
    local rowH = cardFrame:GetHeight()
    if rowH and rowH > 0 then
        local gap = -TILE_LINE_GAP
        local blockData = TILE_NAME_SIZE + gap + TILE_INFO_SIZE
        if hasChar then
            blockData = blockData + TILE_CHAR_SIZE + gap
        end
        d.name:ClearAllPoints()
        d.name:SetPoint(
            "TOPLEFT",
            cardFrame,
            "TOPLEFT",
            rowH + TILE_TEXT_GAP,
            -math.max(0, (rowH - blockData) / 2)
        )
    end

    UpdateClassIcon(cardFrame, d, accountInfo)
    d.onlineBg:SetShown(accountInfo.gameAccountInfo ~= nil and accountInfo.gameAccountInfo.isOnline == true)
    UpdateFaction(cardFrame, d, accountInfo)
    UpdateOrb(d, accountInfo)
    UpdateRegion(cardFrame, d, accountInfo)

    d.hoverBar:Hide()
    d.hoverFill:Hide()

    -- Blizzard calls SetSelected during its own Initialize, i.e. BEFORE this
    -- paint runs and before the structure above exists. The hook stashes the
    -- state in FFD; this applies it once the textures are there.
    local sel = d.selected == true
    d.selBar:SetShown(sel)
    d.selFill:SetShown(sel)
end

-- The tile pieces the custom friends list (CludesUI_FriendsList.lua) draws
-- its own rows with, so the two never drift apart. Skin builds the tile art,
-- the three text lines and the status orb on any frame (a row of ours
-- included); its state is the kit's frame data for that frame. LevelColor is
-- the colour the character line's level takes.
Kit._tile = {
    Host = function()
        return hostRegion
    end,
    FontPath = FontPath,
    Skin = SkinStructure,
    Name = BuildName,
    CharLine = BuildCharLine,
    LevelColor = LocationColor,
    Info = BuildInfo,
    Ruleset = ForeverRuleset,
    State = TileState,
    ClassFile = GetClassFile,
    ClassIconTex = SetClassIconTex,
    Faction = UpdateFaction,
    Orb = UpdateOrb,
    Region = UpdateRegion,
    OFFLINE_ICON = OFFLINE_ICON,
}

-------------------------------------------------------------------------------
--  Stock styles (Blizzard Style / Classic WoW UI): Blizzard's own card, laid
--  out and drawn by Blizzard, with the CludesUI additions in its native
--  slots only. No Blizzard region is moved or re-texted; the same write
--  classes as the tile path (our regions on the card, SetAlpha on Blizzard's
--  regions), so the decoration-only rule above still holds.
--    class icon  -> over Blizzard's 20px game-icon slot (same-project friends)
--    class name  -> our string over Blizzard's character name (Class Color Names)
--    region mark -> the free corner above the party button (Show Region Icons)
-------------------------------------------------------------------------------
local function DecorateStockCard(cardFrame)
    if not Enabled() then
        return
    end
    local ed = cardFrame.elementData
    local accountInfo = ed and ed.accountInfo
    if not accountInfo then
        return
    end

    local d = GetFFD(cardFrame)
    local p = Settings()
    local gi = accountInfo.gameAccountInfo
    local classFile
    if IsSameProjectOnline(gi) then
        classFile = (gi.classFilename ~= "" and gi.classFilename) or GetClassFile(accountInfo)
    end

    -- Class icon: a region of the holder, so it follows Blizzard's own show and
    -- hide of the slot (hidden for offline friends and while the RAF summon
    -- button takes the slot). Blizzard re-sets its Icon's alpha whenever it
    -- shows the holder, so the logo needs no restore when ours stands down.
    local holderFrame = cardFrame.GameIconHolder
    if holderFrame then
        local icon = d.stockClassIcon
        -- Only a class the icon theme has art for takes the slot; any other
        -- token (a special game-mode class) keeps Blizzard's own logo.
        local look = (p and p.iconStyle) or "modern"
        local hasArt = classFile
            and not (p and p.showClassIcons == false)
            and (
                (look == "blizzard" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile])
                or (look ~= "blizzard" and CLASS_SPRITE_COORDS[classFile])
            )
        if hasArt then
            if not icon then
                icon = holderFrame:CreateTexture(nil, "OVERLAY")
                icon:SetAllPoints(holderFrame)
                d.stockClassIcon = icon
            end
            if d.stockIconClass ~= classFile or d.stockIconStyle ~= look then
                d.stockIconClass, d.stockIconStyle = classFile, look
                SetClassIconTex(icon, look, classFile)
            end
            icon:Show()
            if holderFrame.Icon then
                holderFrame.Icon:SetAlpha(0)
                d.stockLogoOff = true
            end
        else
            if icon then
                icon:Hide()
            end
            -- A pooled card whose last friend wore our icon gets the logo back
            -- (Blizzard restores it only when it re-shows the holder).
            if d.stockLogoOff and holderFrame.Icon then
                holderFrame.Icon:SetAlpha(1)
            end
            d.stockLogoOff = nil
        end
    end

    -- Class-coloured character name: our string over Blizzard's (same font
    -- object and rect, so its truncation still holds). Blizzard never resets
    -- the name's alpha itself, so it is restored here whenever ours stands down.
    local name = cardFrame.Name
    if name then
        local shade = d.stockName
        local code = classFile and p and p.classColorNames and name:IsShown() and ClassColorCode(classFile)
        if code then
            if not shade then
                shade = cardFrame:CreateFontString(nil, "OVERLAY")
                local fo = name:GetFontObject()
                if fo then
                    shade:SetFontObject(fo)
                else
                    shade:SetFont(name:GetFont())
                end
                shade:SetAllPoints(name)
                shade:SetJustifyH("LEFT")
                shade:SetJustifyV("MIDDLE")
                shade:SetWordWrap(false)
                d.stockName = shade
            end
            local charName = (
                FriendsListUtil
                and FriendsListUtil.GetFormattedCharacterName
                and FriendsListUtil.GetFormattedCharacterName(accountInfo)
            )
                or gi.characterName
                or ""
            shade:SetText(code .. charName .. "|r")
            shade:Show()
            name:SetAlpha(0)
            d.stockNameHidden = true
        else
            if shade then
                shade:Hide()
            end
            if d.stockNameHidden then
                name:SetAlpha(1)
                d.stockNameHidden = nil
            end
        end
    end

    UpdateStockRegion(cardFrame, d, accountInfo)
end

-------------------------------------------------------------------------------
--  Stock styles on the legacy friends window (FriendsFrame, the one Blizzard
--  shows while the Social UI is switched off server-side): the same three
--  additions on Blizzard's own rows, again in native slots, again decoration
--  only (our regions on the row, SetAlpha on Blizzard's).
--    class icon  -> over Blizzard's 24px game logo (same-project friends; an
--                   online character friend's logo slot is empty and takes it)
--    class name  -> our string over Blizzard's name, built from the same
--                   pieces Blizzard uses, the character part class-coloured
--    region mark -> under the status icon (Show Region Icons)
--  Runs from a post-hook on Blizzard's row update, after it has filled the
--  row. A row updated while the list is hidden (or skipped by an options pass
--  while hidden) is marked stale and caught up when the list shows.
-------------------------------------------------------------------------------
-- restore: an options-driven pass, where no Blizzard row update ran first to
-- put its logo alpha back.
local function DecorateStockRow(btnFrame, restore)
    local bt = btnFrame.buttonType
    local isBNet = bt ~= nil and bt == FRIENDS_BUTTON_TYPE_BNET
    local isWoW = bt ~= nil and bt == FRIENDS_BUTTON_TYPE_WOW
    if not (isBNet or isWoW) or not btnFrame.id then
        return
    end
    local d = GetFFD(btnFrame)
    d.legacy = true
    if not btnFrame:IsVisible() then
        d.stale = true
        return
    end
    d.stale = nil
    if not Enabled() then
        return
    end

    -- Every decoration off: stand down whatever is still painted and read no
    -- friend data at all.
    local p = Settings()
    if p and p.showClassIcons == false and not p.classColorNames and p.showRegionIcons == false then
        if d.stockClassIcon then
            d.stockClassIcon:Hide()
        end
        if d.stockLogoOff and restore and btnFrame.gameIcon then
            btnFrame.gameIcon:SetAlpha(1)
        end
        d.stockLogoOff = nil
        if d.stockName then
            d.stockName:Hide()
        end
        if d.stockNameHidden and btnFrame.name then
            btnFrame.name:SetAlpha(1)
        end
        d.stockNameHidden = nil
        if d.regionMark then
            d.regionMark:Hide()
        end
        return
    end

    local accountInfo, gi, details, classFile
    if isBNet then
        accountInfo = C_BattleNet.GetFriendAccountInfo(btnFrame.id)
        gi = accountInfo and accountInfo.gameAccountInfo
        if IsSameProjectOnline(gi) then
            classFile = (gi.classFilename ~= "" and gi.classFilename) or GetClassFile(accountInfo)
        end
    else
        details = C_FriendList.GetFriendInfoByIndex(btnFrame.id)
        if details and details.connected and details.className then
            classFile = CludesUI.ClassTokenFromLocalized(details.className)
        end
    end

    -- Class icon over the logo's rect. A Battle.net friend's slot is Blizzard's
    -- to show or hide (offline, or the summon button in it), so ours follows
    -- the logo's shown state; Blizzard re-sets the logo's alpha on every row
    -- update, so only an options pass has to give it back.
    local logo = btnFrame.gameIcon
    if logo then
        local icon = d.stockClassIcon
        local look = (p and p.iconStyle) or "modern"
        local hasArt = (isWoW or logo:IsShown())
            and classFile
            and not (p and p.showClassIcons == false)
            and (
                (look == "blizzard" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile])
                or (look ~= "blizzard" and CLASS_SPRITE_COORDS[classFile])
            )
        if hasArt then
            if not icon then
                icon = btnFrame:CreateTexture(nil, "OVERLAY")
                icon:SetAllPoints(logo)
                d.stockClassIcon = icon
            end
            if d.stockIconClass ~= classFile or d.stockIconStyle ~= look then
                d.stockIconClass, d.stockIconStyle = classFile, look
                SetClassIconTex(icon, look, classFile)
            end
            icon:Show()
            if isBNet then
                logo:SetAlpha(0)
                d.stockLogoOff = true
            end
        else
            if icon then
                icon:Hide()
            end
            if d.stockLogoOff and restore then
                logo:SetAlpha(1)
            end
            d.stockLogoOff = nil
        end
    end

    -- Class-coloured name: our string over Blizzard's (same font object and
    -- rect, Blizzard's own colour as the base), so the favourite star Blizzard
    -- anchors at the end of its name still lines up. Blizzard never resets
    -- the name's alpha itself, so it is restored whenever ours stands down.
    -- A friend Blizzard greys out as unable to group keeps its grey.
    local name = btnFrame.name
    if name then
        local code = classFile and p and p.classColorNames and ClassColorCode(classFile)
        if
            code
            and isBNet
            and CanCooperateWithGameAccount
            and not CanCooperateWithGameAccount(accountInfo)
        then
            code = nil
        end
        local textValue
        if code and isBNet then
            local acct = FriendsFrame_GetBNetAccountNameAndStatus
                and FriendsFrame_GetBNetAccountNameAndStatus(accountInfo, true)
            local char = gi.characterName
            if char and char ~= "" and FriendsFrame_GetFormattedCharacterName then
                char = FriendsFrame_GetFormattedCharacterName(
                    char,
                    nil,
                    gi.clientProgram,
                    gi.timerunningSeasonID
                )
            end
            if acct and char and char ~= "" then
                textValue = acct .. " " .. code .. "(" .. char .. ")|r"
            end
        elseif code and details and details.name and details.level and FRIENDS_LEVEL_TEMPLATE then
            textValue = code
                .. details.name
                .. "|r, "
                .. format(FRIENDS_LEVEL_TEMPLATE, details.level, details.className)
        end
        local shade = d.stockName
        if textValue then
            if not shade then
                shade = btnFrame:CreateFontString(nil, "OVERLAY")
                local fo = name:GetFontObject()
                if fo then
                    shade:SetFontObject(fo)
                else
                    shade:SetFont(name:GetFont())
                end
                shade:SetAllPoints(name)
                shade:SetJustifyH(name:GetJustifyH())
                shade:SetJustifyV(name:GetJustifyV())
                shade:SetWordWrap(name:CanWordWrap())
                d.stockName = shade
            end
            -- Colour only: a region's alpha and its colour alpha are one
            -- channel on this client, and Blizzard's name sits at our alpha 0
            -- from the last pass (its 3-arg SetTextColor keeps it), so a full
            -- copy would hand ours alpha 0 from the second update on.
            local r, g, b = name:GetTextColor()
            shade:SetTextColor(r, g, b, 1)
            shade:SetText(textValue)
            shade:Show()
            name:SetAlpha(0)
            d.stockNameHidden = true
        else
            if shade then
                shade:Hide()
            end
            if d.stockNameHidden then
                name:SetAlpha(1)
                d.stockNameHidden = nil
            end
        end
    end

    UpdateStockRegion(btnFrame, d, accountInfo)
end

-- The list shows: catch up the rows Blizzard updated, or an options pass
-- skipped, while it was hidden (the latter with that pass's logo restore).
local function CatchUpStaleRows()
    for widget, d in pairs(FFD) do
        if d.stale then
            local restore = d.staleRestore
            d.staleRestore = nil
            DecorateStockRow(widget, restore)
        end
    end
end

-------------------------------------------------------------------------------
--  Hook
--
--  Post-hook on the card mixin, installed by the host's StartTiles at
--  PLAYER_LOGIN -- before the friends list is first shown and therefore before
--  any card frame exists, so every pooled card copies the hooked Initialize
--  when Mixin() runs at creation.
--
--  This is the ONLY contact point with Blizzard's list (under the stock
--  styles, plus the same kind of post-hook on the legacy window's row update
--  and that list's OnShow). We do not touch the ScrollBox, the provider, or
--  any element data.
-------------------------------------------------------------------------------
-- The decorator the Initialize hook runs this session, chosen once from the
-- style latch (pooled cards therefore never mix treatments).
local activeDecorator

-- Starts the tiles for the session, once, from the host's PLAYER_LOGIN.
-- h.Settings: returns the settings table (enabled, showClassIcons, iconStyle,
-- classColorNames, factionBanners, showRegionIcons); h.style: "cui" paints
-- the CludesUI tiles, any other look only decorates Blizzard's cards;
-- h.fontKey: the font the tiles take; h.cards: false starts the host for the
-- custom friends list alone (CludesUI_FriendsList.lua draws its rows with
-- these pieces), with no hook on Blizzard's cards, which stay Blizzard's own.
-- Such a host may start later in the session: it waits for no card.
function Kit.StartTiles(hgt)
    if hostRegion then
        return
    end
    hostRegion = hgt
    if hgt.cards == false then
        return
    end
    if hgt.style ~= "cui" then
        -- Stock styles decorate whichever window Blizzard shows (the switch
        -- is server-side and can flip mid-session). Blizzard keeps its own
        -- selection highlight, so the SetSelected hook below is not needed.
        activeDecorator = DecorateStockCard
        if FriendsListSocialCardMixin then
            hooksecurefunc(FriendsListSocialCardMixin, "Initialize", function(cardFrame)
                DecorateStockCard(cardFrame)
            end)
        end
        if FriendsFrame_UpdateFriendButton then
            hooksecurefunc("FriendsFrame_UpdateFriendButton", function(btnFrame)
                -- Blizzard has just re-set its logo alpha itself.
                local d = FFD[btnFrame]
                if d then
                    d.staleRestore = nil
                end
                DecorateStockRow(btnFrame)
            end)
            if FriendsListFrame then
                FriendsListFrame:HookScript("OnShow", CatchUpStaleRows)
            end
        end
        return
    end
    if not FriendsListSocialCardMixin then
        return
    end
    activeDecorator = PaintCard
    hooksecurefunc(FriendsListSocialCardMixin, "Initialize", function(cardFrame)
        PaintCard(cardFrame)
    end)

    -- Selection state comes from Blizzard's own selection behaviour, which
    -- routes through SetSelected on the card. Post-hooking it means we never
    -- read the provider or the selection behaviour ourselves.
    hooksecurefunc(FriendsListSocialCardMixin, "SetSelected", function(cardFrame, selected)
        local d = GetFFD(cardFrame)
        d.selected = selected and true or false
        if d.selBar then
            d.selBar:SetShown(d.selected)
            d.selFill:SetShown(d.selected)
        end
    end)
end

-- Options-driven repaint that never goes through Blizzard's view: re-run this
-- session's decorator on every card or legacy row we have decorated that is on
-- screen now, from the data Blizzard already gave it. (view:Refresh
-- regenerates the data provider from our execution -- the whisper-taint class
-- above.)
function Kit.RedecorateTiles()
    local func = activeDecorator
    if not func then
        return
    end
    for widget, d in pairs(FFD) do
        if d.legacy then
            -- A row kept shown under a hidden list (another Friends sub-tab)
            -- is caught up when the list shows; a released row is
            -- re-initialised by Blizzard when the pool reuses it.
            if widget:IsVisible() then
                DecorateStockRow(widget, true)
            elseif widget:IsShown() then
                d.stale, d.staleRestore = true, true
            end
        elseif widget.IsVisible and widget:IsVisible() and widget.elementData then
            func(widget)
        end
    end
end

-------------------------------------------------------------------------------
--  Auto-accept group invites from friends (and guildmates, when the host's
--  settings say so). Independent of the friends window and its look: an
--  invite is answered whichever window Blizzard shows. PARTY_INVITE_REQUEST
--  is registered only while the toggle is on; GROUP_ROSTER_UPDATE only
--  between an accept and its popup cleanup.
-------------------------------------------------------------------------------
local autoAcceptFrame, autoAcceptSettings
local autoAcceptHidePopup = false

local function AutoAcceptOnEvent(self, evt, _, _, _, _, _, _, inviterGUID)
    if evt == "PARTY_INVITE_REQUEST" then
        local fp = autoAcceptSettings and autoAcceptSettings()
        if not fp or fp.enabled == false or not fp.autoAcceptFriendInvites then
            return
        end
        if not inviterGUID or inviterGUID == "" or IsInGroup() then
            return
        end
        local isFriend = false
        if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
            isFriend = C_BattleNet.GetGameAccountInfoByGUID(inviterGUID) ~= nil
        end
        if not isFriend and C_FriendList and C_FriendList.IsFriend then
            isFriend = C_FriendList.IsFriend(inviterGUID)
        end
        if not isFriend and fp.autoAcceptGuildInvites then
            isFriend = IsGuildMember(inviterGUID)
        end
        if isFriend then
            AcceptGroup()
            autoAcceptHidePopup = true
            self:RegisterEvent("GROUP_ROSTER_UPDATE")
        end
    elseif evt == "GROUP_ROSTER_UPDATE" and autoAcceptHidePopup then
        autoAcceptHidePopup = false
        self:UnregisterEvent("GROUP_ROSTER_UPDATE")
        StaticPopup_Hide("PARTY_INVITE")
        if LFGInvitePopup then
            StaticPopupSpecial_Hide(LFGInvitePopup)
        end
    end
end

-- settings: the host's function returning its settings table (enabled,
-- autoAcceptFriendInvites, autoAcceptGuildInvites). Call it at the host's
-- load and after every change to those keys. The frame is made the first
-- time the toggle is on.
function Kit.SyncAutoAccept(prefs)
    autoAcceptSettings = prefs
    local fp = prefs and prefs()
    local on = fp and fp.enabled ~= false and fp.autoAcceptFriendInvites
    if on and not autoAcceptFrame then
        autoAcceptFrame = CreateFrame("Frame")
        autoAcceptFrame:SetScript("OnEvent", AutoAcceptOnEvent)
    end
    if not autoAcceptFrame then
        return
    end
    if on then
        autoAcceptFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    else
        autoAcceptFrame:UnregisterEvent("PARTY_INVITE_REQUEST")
    end
end
