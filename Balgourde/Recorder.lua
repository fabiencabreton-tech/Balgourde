-- Balgourde - Enregistrement : monstres vus, kills, loots, or, vol à la tire
--
-- WoW Forever utilise le moteur de Midnight : le journal de combat
-- (COMBAT_LOG_EVENT_UNFILTERED) est interdit aux addons. Les kills sont donc
-- détectés via les unités visibles (cible, survol, barres de vie) qui passent
-- à l'état "mort" sans être "tapées" par quelqu'un d'autre, et via les loots.
local _, ns = ...
local L = ns.L

ns.Recorder = {}
local R = ns.Recorder

local LOOT_ITEM  = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or LOOT_SLOT_ITEM or 1
local LOOT_MONEY = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or LOOT_SLOT_MONEY or 2
local PICK_POCKET = 921
local Safe = ns.Safe

-- États de la session (communs à vos observations et à celles reçues de la guilde/du groupe)
local killCounted = {}   -- [guid] = true
local lootCounted = {}   -- [guid] = true
local ppCounted = {}     -- [guid] = true
local engaged = {}       -- [guid] = true : vous ou votre groupe étiez sur sa liste de menace
local lastPickpocket = 0

-- Compartiment où ranger une observation : la vôtre, ou celle reçue d'un autre joueur
local function Bucket(mob, remote)
    if not remote then return mob end
    mob.shared = mob.shared or { kills = 0, loots = 0, money = 0, drops = {} }
    return mob.shared
end

-- Bestioles (lapins, rats...) : on ne les liste pas
local CRITTER = { ["Critter"] = true, ["Bestiole"] = true, ["Non-combat Pet"] = true, ["Mascotte pacifique"] = true }

---------------------------------------------------------------------------
-- Application des observations (locales ou reçues)
---------------------------------------------------------------------------
function R.ApplyKill(guid, npcID, mapID, name, remote, silent)
    if not guid or killCounted[guid] then return false end
    npcID = npcID or ns.NpcIDFromGUID(guid)
    if not npcID then return false end
    killCounted[guid] = true
    local mob = ns.GetMob(npcID, true)
    if name and name ~= "" and not mob.name then mob.name = name end
    local b = Bucket(mob, remote)
    b.kills = (b.kills or 0) + 1
    if not remote then ns.Count("kills") end
    ns.AddMobToZone(npcID, mapID)
    ns.Fire("DATA_CHANGED")
    if not remote and not silent and ns.Sync then ns.Sync.SendKill(guid, mapID, mob.name) end
    return true
end

-- items = { [itemID] = true }, copper = or ramassé sur ce cadavre
function R.ApplyLoot(guid, npcID, mapID, name, items, copper, remote)
    if not guid or lootCounted[guid] then return false end
    npcID = npcID or ns.NpcIDFromGUID(guid)
    if not npcID then return false end
    lootCounted[guid] = true
    -- un cadavre fouillé = un kill, même s'il n'a pas été vu mourir (pas d'envoi : le loot suffit)
    R.ApplyKill(guid, npcID, mapID, name, remote, true)
    local mob = ns.GetMob(npcID, true)
    if name and name ~= "" and not mob.name then mob.name = name end
    local b = Bucket(mob, remote)
    b.loots = (b.loots or 0) + 1
    if not remote then ns.Count("loots") end
    b.money = (b.money or 0) + (copper or 0)
    for itemID in pairs(items or {}) do
        b.drops[itemID] = (b.drops[itemID] or 0) + 1
    end
    ns.Fire("DATA_CHANGED")
    return true
end

local function ApplyPickpocket(guid, npcID, items, copper)
    if ppCounted[guid] then return end
    ppCounted[guid] = true
    local mob = ns.GetMob(npcID, true)
    mob.pp = mob.pp or { count = 0, money = 0, drops = {} }
    mob.pp.count = mob.pp.count + 1
    mob.pp.money = (mob.pp.money or 0) + (copper or 0)
    for itemID in pairs(items or {}) do
        mob.pp.drops[itemID] = (mob.pp.drops[itemID] or 0) + 1
    end
    ns.Fire("DATA_CHANGED")
end

---------------------------------------------------------------------------
-- Monstres vus (cible, survol, barres de vie)
---------------------------------------------------------------------------
-- Vous, votre familier ou un membre du groupe êtes sur la liste de menace de ce monstre ?
local GROUP_UNITS = { "player", "pet", "party1", "party2", "party3", "party4" }
local function IsEngaged(unit)
    for _, who in ipairs(GROUP_UNITS) do
        if UnitExists(who) then
            local th = UnitThreatSituation(who, unit)
            -- valeur secrète (contenu restreint) : on ne peut pas vérifier, on fait confiance
            if issecretvalue and issecretvalue(th) then return true end
            if th ~= nil then return true end
        end
    end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local who = "raid" .. i
            if UnitExists(who) then
                local th = UnitThreatSituation(who, unit)
                if (issecretvalue and issecretvalue(th)) or th ~= nil then return true end
            end
        end
    end
    return false
end

local function RecordUnit(unit)
    if not ns.loaded or not unit or not UnitExists(unit) then return end
    if Safe(UnitPlayerControlled(unit)) ~= false then return end
    if not Safe(UnitCanAttack("player", unit)) then return end
    if CRITTER[Safe(UnitCreatureType(unit)) or ""] then return end
    local guid = Safe(UnitGUID(unit))
    local npcID = ns.NpcIDFromGUID(guid)
    if not npcID then return end

    local mob = ns.GetMob(npcID, true)
    mob.name = Safe(UnitName(unit)) or mob.name
    local lvl = Safe(UnitLevel(unit))
    if lvl and lvl > 0 then
        mob.minLevel = math.min(mob.minLevel or lvl, lvl)
        mob.maxLevel = math.max(mob.maxLevel or lvl, lvl)
    elseif lvl == -1 then
        mob.minLevel, mob.maxLevel = mob.minLevel or -1, mob.maxLevel or -1 -- "??" (boss)
    end
    mob.classif = Safe(UnitClassification(unit)) or mob.classif
    mob.ctype = Safe(UnitCreatureType(unit)) or mob.ctype

    local mapID, zoneName = ns.GetCurrentZone()
    ns.AddMobToZone(npcID, mapID, zoneName)

    local dead = Safe(UnitIsDead(unit))
    if not dead and IsEngaged(unit) then engaged[guid] = true end
    -- mort, pas tapé par un autre joueur, et combattu par vous ou votre groupe
    -- (évite de compter les monstres tués par des gardes PNJ sous vos yeux)
    if dead and engaged[guid] and Safe(UnitIsTapDenied(unit)) == false then
        R.ApplyKill(guid, npcID, mapID, mob.name, false)
    end
end
R.RecordUnit = RecordUnit

local function IsTrackedUnit(unit)
    return unit == "target" or unit == "focus" or unit == "mouseover"
        or (type(unit) == "string" and unit:find("^nameplate%d+$") ~= nil)
end

-- mémoire : on oublie les vieux monstres engagés
C_Timer.NewTicker(600, function()
    local n = 0
    for _ in pairs(engaged) do n = n + 1 end
    if n > 2000 then wipe(engaged) end
end)

ns:On("PLAYER_TARGET_CHANGED", function() RecordUnit("target") end)
ns:On("UPDATE_MOUSEOVER_UNIT", function() RecordUnit("mouseover") end)
ns:On("NAME_PLATE_UNIT_ADDED", function(unit) RecordUnit(unit) end)
ns:On("NAME_PLATE_UNIT_REMOVED", function(unit) RecordUnit(unit) end)
ns:On("UNIT_HEALTH", function(unit)
    if IsTrackedUnit(unit) and Safe(UnitIsDead(unit)) then RecordUnit(unit) end
end)
ns:On("UNIT_THREAT_LIST_UPDATE", function(unit)
    if IsTrackedUnit(unit) then RecordUnit(unit) end
end)
ns:On("UNIT_FLAGS", function(unit)
    if IsTrackedUnit(unit) then RecordUnit(unit) end
end)

---------------------------------------------------------------------------
-- Vol à la tire
---------------------------------------------------------------------------
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit == "player" and Safe(spellID) == PICK_POCKET then lastPickpocket = GetTime(); ns.Count("pickpockets") end
end)

-- Un loot est un vol à la tire si on vient de lancer le sort, ou si la source est vivante
local function IsPickpocket(guid)
    if GetTime() - lastPickpocket < 3 then return true end
    for _, unit in ipairs({ "target", "mouseover" }) do
        if UnitExists(unit) and Safe(UnitGUID(unit)) == guid and Safe(UnitIsDead(unit)) == false then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Loots
---------------------------------------------------------------------------
local moneyFallback -- { guid, npcID, before } : or non détaillé par la source

ns:On("LOOT_OPENED", function()
    if not ns.loaded then return end
    -- dépeçage / récolte sur un cadavre : ce n'est pas le butin du monstre
    if ns.Skinning and ns.Skinning.IsGatherLoot() then return end
    local corpses, items, copper = {}, {}, {}
    local moneySlotWithoutAmount = false

    for slot = 1, GetNumLootItems() do
        local slotType = Safe(GetLootSlotType(slot))
        local itemID = (slotType == LOOT_ITEM) and ns.ItemIDFromLink(Safe(GetLootSlotLink(slot)))
        local sources = { GetLootSourceInfo(slot) }
        for i = 1, #sources, 2 do
            local guid = Safe(sources[i])
            local qty = Safe(sources[i + 1])
            local npcID = ns.NpcIDFromGUID(guid)
            if npcID then
                corpses[guid] = npcID
                if itemID then
                    items[guid] = items[guid] or {}
                    items[guid][itemID] = true
                elseif slotType == LOOT_MONEY then
                    if qty and qty > 0 then
                        ns.Count("moneyBySource")
                        copper[guid] = (copper[guid] or 0) + qty
                    else
                        moneySlotWithoutAmount = true
                    end
                end
            end
        end
    end

    local mapID, zoneName = ns.GetCurrentZone()
    local count, lastGuid = 0, nil
    for guid, npcID in pairs(corpses) do
        count, lastGuid = count + 1, guid
        if IsPickpocket(guid) then
            ApplyPickpocket(guid, npcID, items[guid], copper[guid])
        elseif not lootCounted[guid] then
            ns.AddMobToZone(npcID, mapID, zoneName)
            local mob = ns.GetMob(npcID, true)
            R.ApplyLoot(guid, npcID, mapID, mob.name, items[guid], copper[guid], false)
            if ns.Sync then ns.Sync.QueueLoot(guid, mapID, mob.name, items[guid], copper[guid]) end
        end
    end

    -- Repli : le client ne donne pas le montant par cadavre -> on mesure la variation d'or
    if moneySlotWithoutAmount and count == 1 then
        moneyFallback = { guid = lastGuid, npcID = corpses[lastGuid], before = GetMoney(), pp = IsPickpocket(lastGuid) }
    end
end)

ns:On("PLAYER_MONEY", function()
    if not moneyFallback then return end
    local delta = GetMoney() - moneyFallback.before
    if delta > 0 then
        ns.Count("moneyFallback")
        local mob = ns.GetMob(moneyFallback.npcID, true)
        if moneyFallback.pp then
            if mob.pp then mob.pp.money = (mob.pp.money or 0) + delta end
        else
            mob.money = (mob.money or 0) + delta
            if ns.Sync then ns.Sync.AddQueuedMoney(moneyFallback.guid, delta) end
        end
        moneyFallback.before = GetMoney()
        ns.Fire("DATA_CHANGED")
    end
end)

ns:On("LOOT_CLOSED", function()
    moneyFallback = nil
    if ns.Sync then ns.Sync.FlushLoot() end
end)
