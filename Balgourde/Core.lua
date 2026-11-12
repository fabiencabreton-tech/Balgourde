-- Balgourde - Noyau : événements, base de données, utilitaires
local ADDON, ns = ...
local L = ns.L
Balgourde = ns -- accès global pratique pour /dump et les macros

ns.VERSION = "0.9.0"
ns.MIN_KILLS_OVERRIDE = 30   -- au-delà, vos observations priment sur la base de départ

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.frame = frame
ns.handlers = {}

function ns:On(event, fn)
    if not self.handlers[event] then
        self.handlers[event] = {}
        -- un événement absent de ce client ne doit pas casser l'addon
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then return end
    end
    table.insert(self.handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = ns.handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then ns.ReportError(event, err) end
    end
end)

---------------------------------------------------------------------------
-- Journal des erreurs : rien n'est avalé en silence (/balg erreurs)
---------------------------------------------------------------------------
ns.Errors = {}
ns.Counters = {}   -- compteurs de session pour /balg test
local errorNotified = false
function ns.Count(key, n) ns.Counters[key] = (ns.Counters[key] or 0) + (n or 1) end

function ns.ReportError(context, err)
    local msg = tostring(err)
    -- même erreur répétée : on incrémente au lieu d'empiler
    for _, e in ipairs(ns.Errors) do
        if e.msg == msg and e.context == context then e.count = e.count + 1; e.last = time(); return end
    end
    table.insert(ns.Errors, { context = tostring(context), msg = msg, count = 1, first = time(), last = time() })
    while #ns.Errors > 30 do table.remove(ns.Errors, 1) end
    if not errorNotified and ns.Print then
        errorNotified = true
        ns.Print(L["|cffff5555Une erreur s'est produite.|r Tapez /balg erreurs pour le détail (et envoyez-le au créateur)."])
    end
end

-- Appel protégé qui journalise l'erreur
function ns.SafeCall(context, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.ReportError(context, err) end
    return ok
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
local PREFIX = "|cffd4a017Balgourde|r : "
function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg)) end
function ns.Debug(msg)
    if BalgourdeDB and BalgourdeDB.settings and BalgourdeDB.settings.debug then
        ns.Print("|cff888888" .. tostring(msg) .. "|r")
    end
end

---------------------------------------------------------------------------
-- Compatibilité API (Classic / moderne)
---------------------------------------------------------------------------
ns.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
ns.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

function ns.GetContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    end
    return GetContainerNumSlots(bag)
end

-- Retourne itemID, quantité, lien
function ns.GetContainerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount, info.hyperlink, info.isBound end
        return
    end
    local _, count, _, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
    if itemID then return itemID, count, link, nil end
end

function ns.IsBound(bag, slot, knownBound)
    if knownBound ~= nil then return knownBound end
    if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local ok, bound = pcall(function()
            return C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot))
        end)
        if ok then return bound end
    end
    return false
end

---------------------------------------------------------------------------
-- Valeurs secrètes (moteur Midnight / Forever) : illisibles par les addons
-- dans certains contextes. On les traite comme "inconnues".
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
function ns.Safe(v)
    if issecret(v) then return nil end
    return v
end

---------------------------------------------------------------------------
-- Identifiants
---------------------------------------------------------------------------
function ns.NpcIDFromGUID(guid)
    if not guid or issecret(guid) or type(guid) ~= "string" then return end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then
        return tonumber(npcID)
    end
end

function ns.ItemIDFromLink(link)
    if not link or issecret(link) or type(link) ~= "string" then return end
    local id = ns.GetItemInfoInstant(link)
    if id then return id end
    return tonumber(link:match("item:(%d+)"))
end

-- Zone courante (on remonte des micro-cartes / grottes vers la zone)
function ns.GetCurrentZone()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return nil, GetRealZoneText() end
    local info = C_Map.GetMapInfo(mapID)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local dungeonType = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
    local guard = 0
    while info and info.mapType and info.mapType > zoneType and info.mapType ~= dungeonType
          and info.parentMapID and info.parentMapID > 0 and guard < 5 do
        mapID = info.parentMapID
        info = C_Map.GetMapInfo(mapID)
        guard = guard + 1
    end
    return mapID, (info and info.name) or GetRealZoneText()
end

---------------------------------------------------------------------------
-- Argent
---------------------------------------------------------------------------
function ns.Money(copper)
    if not copper or copper <= 0 then return "|cff666666-|r" end
    copper = math.floor(copper + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out = ""
    if g > 0 then out = out .. "|cffffd700" .. g .. L["po|r "] end
    if g > 0 or s > 0 then out = out .. "|cffc7c7cf" .. s .. L["pa|r "] end
    if g < 10 then out = out .. "|cffeda55f" .. c .. L["pc|r"] end
    return (out:gsub("%s+$", ""))
end

function ns.Percent(rate)
    if not rate then return "|cff666666?|r" end
    local p = rate * 100
    if p >= 10 then return string.format("%.0f%%", p) end
    if p >= 1 then return string.format("%.1f%%", p) end
    return string.format("%.2f%%", p)
end

---------------------------------------------------------------------------
-- Base de données
---------------------------------------------------------------------------
local DEFAULTS = {
    version = 2,
    mobs = {},     -- [npcID] = { name, minLevel, maxLevel, kills, loots, money, drops = {[itemID]=n},
                   --             pp = { count, money, drops = {[itemID]=n} },   (pp = vol à la tire)
                   --             shared = { kills, loots, money, drops },        (reçu de la guilde/du groupe)
                   --             skin = { n, mats = {[itemID] = {hits, qty, min, max}} } } (vos dépeçages)
    senders = {},  -- [joueur] = nb d'observations reçues
    history = {},  -- [royaume] = { [marché] = { [itemID] = { [jour] = valeur de marché } } }
    sales = {},    -- [itemID ou nom] = { sold, expired, soldCopper, name }
    ahRates = {},  -- [marché] = commission et dépôt réels lus dans les courriers de vente
    watch = {},    -- [itemID] = true : objets suivis (sacs, fiches consultées) pour l'historique
    disenchantShared = {}, -- comme disenchant, mais reçu de la guilde / du groupe
    disenchant = {}, -- [qualité:type:tranche] = { n, mats = { [itemID] = { hits, qty, min, max } } }
    itemNames = {},-- [itemID] = nom (relevé à l'HV, pour la recherche sans requête au serveur)
    zones = {},    -- [mapID] = { name, mobs = {[npcID]=true} }
    prices = {},   -- [royaume] = { [marché] = { [itemID] = { min, market, qty, n, t } } }
    settings = {
        autoShow = true,
        sortAsc = true,
        mobSort = "level",     -- "level" | "value"
        followTarget = true,
        tooltipItems = true,
        tooltipUnits = true,
        minimapHidden = false,
        syncGuild = true,
        syncGroup = true,
        hideGrey = false,
        hideEmpty = false,
        reliableKills = 10,    -- en dessous, le taux est affiché "n/kills" en gris
        collapsed = {},        -- [npcID] = true : monstre replié dans l'onglet Zone
        onlyMine = false,
        tooltipDE = true,
        tooltipSkin = true,
        autoFillPrice = false, -- remplir automatiquement les prix en posant un objet à vendre    -- dépeçage : compétence requise et cuirs sur les monstres      -- résultats de désenchantement dans l'infobulle des objets      -- onglet Prix HV : seulement les objets des sacs
        useShared = true,      -- inclure les observations reçues dans les taux
        ignoredSenders = {},   -- [nom] = true : joueurs dont on refuse les données
        debug = false,
    },
}

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = type(v) == "table" and {} or v
            if type(v) == "table" then ApplyDefaults(dst[k], v) end
        elseif type(v) == "table" and type(dst[k]) == "table" then
            ApplyDefaults(dst[k], v)
        end
    end
end

function ns.GetMob(npcID, create)
    local mob = BalgourdeDB.mobs[npcID]
    if not mob and create then
        mob = { kills = 0, loots = 0, money = 0, drops = {} }
        BalgourdeDB.mobs[npcID] = mob
    end
    if mob and not mob.money then mob.money = 0 end
    return mob
end

function ns.AddMobToZone(npcID, mapID, zoneName)
    if not npcID or not mapID then return end
    local zone = BalgourdeDB.zones[mapID]
    if not zone then
        if not zoneName and C_Map and C_Map.GetMapInfo then
            local info = C_Map.GetMapInfo(mapID)
            zoneName = info and info.name
        end
        zone = { name = zoneName, mobs = {} }
        BalgourdeDB.zones[mapID] = zone
    end
    if zoneName then zone.name = zoneName end
    if not zone.mobs[npcID] then
        zone.mobs[npcID] = true
        ns.Fire("DATA_CHANGED")
    end
end

-- Liste des npcID d'une zone (observés + base de départ)
function ns.GetZoneMobs(mapID)
    local set, list = {}, {}
    local zone = BalgourdeDB.zones[mapID]
    if zone then for id in pairs(zone.mobs) do set[id] = true end end
    local seed = ns.Seed and ns.Seed.zones[mapID]
    if seed then for _, id in ipairs(seed) do set[id] = true end end
    for id in pairs(set) do list[#list + 1] = id end
    return list
end

-- Compteurs combinés : vos observations + celles reçues (si l'option est activée)
-- Retourne kills, loots, money, drops, kills reçus
local EMPTY = {}
function ns.MobTotals(npcID)
    local mob = BalgourdeDB.mobs[npcID]
    if not mob then return 0, 0, 0, EMPTY, 0 end
    local kills, loots, money, drops = mob.kills or 0, mob.loots or 0, mob.money or 0, mob.drops or EMPTY
    local sh = BalgourdeDB.settings.useShared and mob.shared
    if sh and ((sh.kills or 0) > 0 or (sh.loots or 0) > 0) then
        kills, loots, money = kills + (sh.kills or 0), loots + (sh.loots or 0), money + (sh.money or 0)
        local merged = {}
        for id, n in pairs(drops) do merged[id] = n end
        for id, n in pairs(sh.drops or EMPTY) do merged[id] = (merged[id] or 0) + n end
        drops = merged
        return kills, loots, money, drops, sh.kills or 0
    end
    return kills, loots, money, drops, 0
end

-- Efface toutes les observations reçues de la guilde/du groupe
function ns.PurgeShared()
    for _, mob in pairs(BalgourdeDB.mobs) do mob.shared = nil; mob.skinShared = nil end
    wipe(BalgourdeDB.disenchantShared)
    wipe(BalgourdeDB.senders)
    ns.InvalidateDropIndex()
    ns.Fire("DATA_CHANGED")
end

function ns.GetMobInfo(npcID)
    local mob = BalgourdeDB.mobs[npcID]
    local seed = ns.Seed and ns.Seed.mobs[npcID]
    local name = (mob and mob.name) or (seed and seed.name) or (L["PNJ #"] .. npcID)
    local minL = (mob and mob.minLevel) or (seed and seed.minLevel)
    local maxL = (mob and mob.maxLevel) or (seed and seed.maxLevel)
    local kills, loots, _, _, sharedKills = ns.MobTotals(npcID)
    return name, minL, maxL, kills, loots, sharedKills
end

-- Objet de quête ? (classe 12 = Quête) – ne tombe que si on a la quête
local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
function ns.IsQuestItem(itemID)
    local _, _, _, _, _, classID = ns.GetItemInfoInstant(itemID)
    if classID == QUEST_CLASS then return true end
    local bindType = select(14, ns.GetItemInfo(itemID))
    return bindType == 4
end

function ns.ReliableKills()
    return (BalgourdeDB and BalgourdeDB.settings.reliableKills) or 10
end

-- Retourne { {itemID, rate, source, count, kills, quest, reliable}, ... }
-- source = "base" (données de départ) ou "obs" (observations : vous + guilde/groupe)
function ns.GetMobDrops(npcID)
    local seed = ns.Seed and ns.Seed.mobs[npcID]
    local kills, _, _, obsDrops = ns.MobTotals(npcID)
    local useObs = (not seed or not seed.drops) or kills >= ns.MIN_KILLS_OVERRIDE
    local reliable = kills >= ns.ReliableKills()
    local result, seen = {}, {}

    -- 1) taux de la base de départ tant qu'on n'a pas assez de kills
    if seed and seed.drops and not useObs then
        for itemID, rate in pairs(seed.drops) do
            result[#result + 1] = { itemID = itemID, rate = rate, source = "base", reliable = true,
                                    quest = ns.IsQuestItem(itemID) }
            seen[itemID] = true
        end
    end
    -- 2) observations (pour tout objet pas déjà couvert)
    do
        for itemID, n in pairs(obsDrops) do
            if not seen[itemID] then
                local rate = kills > 0 and math.min(1, n / kills) or nil
                result[#result + 1] = { itemID = itemID, rate = rate, source = "obs", count = n, kills = kills,
                                        reliable = reliable, quest = ns.IsQuestItem(itemID) }
                seen[itemID] = true
            end
        end
    end
    return result
end

-- Butin de vol à la tire : liste + nb de poches + or moyen
function ns.GetMobPickpocket(npcID)
    local mob = BalgourdeDB.mobs[npcID]
    local pp = mob and mob.pp
    if not pp or (pp.count or 0) == 0 then return nil end
    local list = {}
    for itemID, n in pairs(pp.drops or {}) do
        list[#list + 1] = { itemID = itemID, rate = math.min(1, n / pp.count), count = n, kills = pp.count,
                            source = "obs", reliable = pp.count >= ns.ReliableKills(), pickpocket = true }
    end
    return list, pp.count, (pp.money or 0) / pp.count
end

-- Valeur moyenne d'un kill (or ramassé + objets au meilleur prix, hors quête)
-- Retourne copper, fiable (bool)
function ns.GetMobValue(npcID)
    local kills, loots, money = ns.MobTotals(npcID)
    local total, any = 0, false
    if kills > 0 and loots > 0 then
        total = total + money / kills
        any = true
    end
    for _, d in ipairs(ns.GetMobDrops(npcID)) do
        if d.rate and not d.quest then
            local best = ns.Auction and ns.Auction.GetBest(d.itemID)
            if best then total = total + d.rate * best.net end
            any = true
        end
    end
    -- dépeçage : ajouté si votre personnage est dépeceur avec la compétence suffisante
    local skinIncluded = false
    local Sk = ns.Skinning
    local skill = Sk and Sk.PlayerSkill()
    if skill and BalgourdeDB.settings.tooltipSkin then
        local sv = Sk.GetValue(npcID)
        local mob = BalgourdeDB.mobs[npcID]
        local req = Sk.RequiredSkill(mob and mob.maxLevel ~= -1 and mob.maxLevel or nil)
        if sv and sv > 0 and (not req or skill >= req) then
            total, any, skinIncluded = total + sv, true, true
        end
    end
    if not any then return nil end
    return total, kills >= ns.ReliableKills() or (ns.Seed and ns.Seed.mobs[npcID] ~= nil), skinIncluded
end

-- Index inverse objet -> monstres (pour l'infobulle des objets)
local dropIndex
function ns.InvalidateDropIndex() dropIndex = nil end
function ns.GetItemSources(itemID)
    if not dropIndex then
        dropIndex = {}
        local function add(npcID)
            for _, d in ipairs(ns.GetMobDrops(npcID)) do
                dropIndex[d.itemID] = dropIndex[d.itemID] or {}
                table.insert(dropIndex[d.itemID], { npcID = npcID, rate = d.rate, reliable = d.reliable,
                                                    count = d.count, kills = d.kills, quest = d.quest })
            end
        end
        local done = {}
        for npcID in pairs(BalgourdeDB.mobs) do done[npcID] = true; add(npcID) end
        if ns.Seed then for npcID in pairs(ns.Seed.mobs) do if not done[npcID] then add(npcID) end end end
        for _, list in pairs(dropIndex) do
            table.sort(list, function(a, b) return (a.rate or 0) > (b.rate or 0) end)
        end
    end
    return dropIndex[itemID]
end

-- Texte de la colonne "Taux"
function ns.RateText(d)
    if d.quest then return L["|cff888888quête|r"] end
    if not d.rate then return "|cff666666?|r" end
    if d.source == "base" then return "|cffaaaaff" .. ns.Percent(d.rate) .. "|r" end
    if not d.reliable then return string.format("|cff888888%d/%d|r", d.count or 0, d.kills or 0) end
    return ns.Percent(d.rate)
end

---------------------------------------------------------------------------
-- Mini bus de messages interne
---------------------------------------------------------------------------
ns.callbacks = {}
function ns.Listen(msg, fn)
    ns.callbacks[msg] = ns.callbacks[msg] or {}
    table.insert(ns.callbacks[msg], fn)
end
local pending = {}
function ns.Fire(msg)
    -- regroupe les rafales (ex. 20 loots d'affilée) en un seul rafraîchissement
    if pending[msg] then return end
    pending[msg] = true
    C_Timer.After(0.25, function()
        pending[msg] = nil
        if msg == "DATA_CHANGED" then ns.InvalidateDropIndex() end
        if msg == "PRICES_CHANGED" and ns.Auction then ns.Auction.InvalidateCache() end
        for _, fn in ipairs(ns.callbacks[msg] or {}) do
            local ok, err = pcall(fn)
            if not ok then ns.ReportError(msg, err) end
        end
    end)
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    -- reprise des données de l'ancien nom (Balgourge) si le fichier de sauvegarde a été renommé
    if BalgourgeDB and not BalgourdeDB then
        BalgourdeDB = BalgourgeDB
        ns.migratedFromOldName = true
    end
    BalgourgeDB = nil
    BalgourdeDB = BalgourdeDB or {}
    ApplyDefaults(BalgourdeDB, DEFAULTS)
    if ns.SetLanguage then ns.SetLanguage(BalgourdeDB.settings.lang) end
    ns.db = BalgourdeDB
    ns.loaded = true
    for _, fn in ipairs(ns.callbacks["LOADED"] or {}) do
        local ok, err = pcall(fn)
        if not ok then
            ns.ReportError("LOADED", err)
            ns.Print(L["|cffff5555Erreur au chargement :|r "] .. tostring(err))
        end
    end
    if ns.migratedFromOldName then ns.Print(L["Données de Balgourge récupérées."]) end
    ns.Print("v" .. ns.VERSION .. L[" chargé. Tapez |cffffff00/balg|r pour l'aide."])
end)
