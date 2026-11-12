-- Balgourde - Désenchantement : ce qu'on obtient en désenchantant un objet, et ce que ça vaut
--
-- Le jeu ne donne pas les résultats de désenchantement aux addons : on utilise les tables
-- de WoW Classic (par niveau d'objet, source warcraft.wiki.gg), puis on les remplace par
-- vos propres désenchantements observés dès qu'il y en a assez (WoW Forever peut différer).
local _, ns = ...
local L = ns.L

ns.Disenchant = {}
local D = ns.Disenchant
local DE_SPELL = 13262
D.MIN_OBSERVED = 10   -- désenchantements observés dans une tranche avant de remplacer la table

-- Matériaux (identifiants d'objets Classic)
local M = {
    strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204,
    lme = 10938, gme = 10939, lae = 10998, gae = 11082, lmy = 11134, gmy = 11135,
    lne = 11174, gne = 11175, lee = 16202, gee = 16203,
    sgs = 10978, lgs = 11084, sgl = 11138, lgl = 11139, srs = 11177, lrs = 11178,
    sbs = 14343, lbs = 14344, nexus = 20725,
}
D.MATS = M

-- Objets verts : niveau d'objet max, poussière + qté, essence + qté, éclat,
-- probabilités armure {poussière, essence, éclat}, probabilités arme {poussière, essence, éclat}
local UNCOMMON = {
    { 15,  M.strange,  { 1, 2 }, M.lme, { 1, 2 }, nil,   { .80, .20, 0 },   { .20, .80, 0 } },
    { 20,  M.strange,  { 2, 3 }, M.gme, { 1, 2 }, M.sgs, { .75, .20, .05 }, { .20, .75, .05 } },
    { 25,  M.strange,  { 4, 6 }, M.lae, { 1, 2 }, M.sgs, { .75, .15, .10 }, { .15, .75, .10 } },
    { 30,  M.soul,     { 1, 2 }, M.gae, { 1, 2 }, M.lgs, { .75, .20, .05 }, { .20, .75, .05 } },
    { 35,  M.soul,     { 2, 5 }, M.lmy, { 1, 2 }, M.sgl, { .75, .20, .05 }, { .20, .75, .05 } },
    { 40,  M.vision,   { 1, 2 }, M.gmy, { 1, 2 }, M.lgl, { .75, .20, .05 }, { .20, .75, .05 } },
    { 45,  M.vision,   { 2, 5 }, M.lne, { 1, 2 }, M.srs, { .75, .20, .05 }, { .20, .75, .05 } },
    { 50,  M.dream,    { 1, 2 }, M.gne, { 1, 2 }, M.lrs, { .75, .20, .05 }, { .20, .75, .05 } },
    { 55,  M.dream,    { 2, 5 }, M.lee, { 1, 2 }, M.sbs, { .75, .20, .05 }, { .22, .75, .03 } },
    { 60,  M.illusion, { 1, 2 }, M.gee, { 1, 2 }, M.lbs, { .75, .20, .05 }, { .22, .75, .03 } },
    { 999, M.illusion, { 2, 5 }, M.gee, { 2, 3 }, M.lbs, { .75, .20, .05 }, { .22, .75, .03 } },
}
-- Objets bleus : 1 éclat (99,5 % + 0,5 % de Cristal de Nexus au-delà du niveau 55)
local RARE = {
    { 25, M.sgs }, { 30, M.lgs }, { 35, M.sgl }, { 40, M.lgl }, { 45, M.srs },
    { 50, M.lrs }, { 55, M.sbs }, { 999, M.lbs, nexus = 0.005 },
}
-- Objets épiques : niveau max, résultat, quantité
local EPIC = {
    { 45, M.srs, { 2, 4 } }, { 50, M.lrs, { 2, 4 } }, { 55, M.sbs, { 2, 4 } },
    { 60, M.nexus, { 1, 1 } }, { 999, M.nexus, { 1, 2 } },
}

local function Bracket(tbl, ilvl)
    for i, row in ipairs(tbl) do
        if ilvl <= row[1] then return i, row end
    end
end

-- Peut-on désenchanter cet objet ? Retourne qualité, niveau d'objet, "armor"/"weapon", clé de tranche
function D.Classify(itemID)
    local _, _, quality, ilvl, _, _, _, _, equipLoc, _, _, classID = ns.GetItemInfo(itemID)
    if not quality or not ilvl then return nil end
    if quality < 2 or quality > 4 then return nil end
    if classID ~= 2 and classID ~= 4 then return nil end
    if equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" or equipLoc == "" or equipLoc == nil then return nil end
    if ilvl < 5 then return nil end
    local kind = classID == 2 and "weapon" or "armor"
    local idx
    if quality == 2 then idx = Bracket(UNCOMMON, ilvl)
    elseif quality == 3 then idx = Bracket(RARE, ilvl)
    else
        if ilvl < 40 then return nil end -- pas de données fiables pour les épiques de bas niveau
        idx = Bracket(EPIC, ilvl)
    end
    if not idx then return nil end
    return quality, ilvl, kind, quality .. ":" .. (quality == 2 and kind or "any") .. ":" .. idx
end

-- Résultats de la table Classic : { {itemID, prob, min, max}, ... }
local function TableOutcomes(quality, ilvl, kind)
    local out = {}
    if quality == 2 then
        local _, r = Bracket(UNCOMMON, ilvl)
        local p = kind == "weapon" and r[8] or r[7]
        if p[1] > 0 then out[#out + 1] = { itemID = r[2], prob = p[1], min = r[3][1], max = r[3][2] } end
        if p[2] > 0 then out[#out + 1] = { itemID = r[4], prob = p[2], min = r[5][1], max = r[5][2] } end
        if r[6] and p[3] > 0 then out[#out + 1] = { itemID = r[6], prob = p[3], min = 1, max = 1 } end
    elseif quality == 3 then
        local _, r = Bracket(RARE, ilvl)
        local nexus = r.nexus or 0
        out[#out + 1] = { itemID = r[2], prob = 1 - nexus, min = 1, max = 1 }
        if nexus > 0 then out[#out + 1] = { itemID = M.nexus, prob = nexus, min = 1, max = 1 } end
    else
        local _, r = Bracket(EPIC, ilvl)
        out[#out + 1] = { itemID = r[2], prob = 1, min = r[3][1], max = r[3][2] }
    end
    for _, o in ipairs(out) do o.avg = (o.min + o.max) / 2 end
    return out
end

-- Vos désenchantements + ceux reçus (si l'option est active)
function D.MergedObs(key)
    local own = BalgourdeDB.disenchant[key]
    local sh = BalgourdeDB.settings.useShared and BalgourdeDB.disenchantShared[key]
    if not sh then return own end
    if not own then return sh end
    local merged = { n = own.n + sh.n, mats = {} }
    for _, src in ipairs({ own, sh }) do
        for id, m in pairs(src.mats) do
            local t = merged.mats[id] or { hits = 0, qty = 0 }
            merged.mats[id] = t
            t.hits, t.qty = t.hits + m.hits, t.qty + m.qty
            t.min = math.min(t.min or m.min or 1, m.min or 1)
            t.max = math.max(t.max or m.max or 1, m.max or 1)
        end
    end
    return merged
end

-- Enregistre un désenchantement dans une tranche. got = { [itemID] = quantité }
local deSeen = {}
function D.Record(key, got, remote, token)
    if token then
        if deSeen[token] then return false end
        deSeen[token] = true
    end
    local store = remote and BalgourdeDB.disenchantShared or BalgourdeDB.disenchant
    local obs = store[key] or { n = 0, mats = {} }
    store[key] = obs
    obs.n = obs.n + 1
    for matID, qty in pairs(got) do
        local m = obs.mats[matID] or { hits = 0, qty = 0 }
        obs.mats[matID] = m
        m.hits, m.qty = m.hits + 1, m.qty + qty
        m.min = math.min(m.min or qty, qty)
        m.max = math.max(m.max or qty, qty)
    end
    if not remote then ns.Count("disenchants") end
    if ns.Auction then ns.Auction.InvalidateCache() end
    ns.Fire("PRICES_CHANGED")
    return true
end

-- Résultats pour un objet : table Classic, ou vos observations s'il y en a assez dans la tranche
-- Retourne outcomes, source ("table" | "obs"), nb d'observations
function D.GetOutcomes(itemID)
    local quality, ilvl, kind, key = D.Classify(itemID)
    if not quality then return nil end
    local obs = D.MergedObs(key)
    if obs and obs.n >= D.MIN_OBSERVED then
        local out = {}
        for matID, m in pairs(obs.mats) do
            out[#out + 1] = { itemID = matID, prob = m.hits / obs.n, avg = m.qty / m.hits, min = m.min, max = m.max }
        end
        table.sort(out, function(a, b) return a.prob > b.prob end)
        return out, "obs", obs.n
    end
    return TableOutcomes(quality, ilvl, kind), "table", obs and obs.n or 0
end

-- Prix unitaire d'un matériau : meilleur gain net connu (HV ou marchand)
function D.MatPrice(matID)
    local best = ns.Auction.GetBest(matID)
    return best and best.net or 0
end

-- Valeur espérée d'un désenchantement (cuivre) ; nil si non désenchantable ou aucun prix connu
function D.GetValue(itemID)
    local outcomes, source, n = D.GetOutcomes(itemID)
    if not outcomes then return nil end
    local total, priced = 0, false
    for _, o in ipairs(outcomes) do
        local price = D.MatPrice(o.itemID)
        o.price = price
        o.value = o.prob * o.avg * price
        if price > 0 then priced = true end
        total = total + o.value
    end
    return priced and total or nil, outcomes, source, n
end

-- Le désenchantement doit-il entrer dans le « meilleur marché » ?
function D.InBest()
    local s = BalgourdeDB.settings.deInBest
    if s == nil then
        local knows = (IsPlayerSpell and IsPlayerSpell(DE_SPELL)) or (IsSpellKnown and IsSpellKnown(DE_SPELL))
        return knows and true or false
    end
    return s
end

function D.QtyText(o)
    if o.min and o.max then
        return o.min == o.max and ("×" .. o.min) or ("×" .. o.min .. "-" .. o.max)
    end
    return string.format("×%.1f", o.avg or 1)
end

---------------------------------------------------------------------------
-- Apprentissage : on note les résultats de vos vrais désenchantements
---------------------------------------------------------------------------
local pending -- { itemID, done = GetTime() du succès }

local function LockedBagItem()
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (ns.GetContainerNumSlots(bag) or 0) do
            local locked, itemID
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then locked, itemID = info.isLocked, info.itemID end
            elseif GetContainerItemInfo then
                local _, _, l, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
                locked, itemID = l, id
            end
            if locked and itemID then return itemID end
        end
    end
end

ns:On("UNIT_SPELLCAST_START", function(unit, _, spellID)
    if unit ~= "player" or ns.Safe(spellID) ~= DE_SPELL then return end
    local itemID = LockedBagItem()
    pending = itemID and { itemID = itemID } or nil
end)
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit == "player" and ns.Safe(spellID) == DE_SPELL and pending then pending.done = GetTime() end
end)
local function Cancel(unit, _, spellID)
    if unit == "player" and ns.Safe(spellID) == DE_SPELL and pending and not pending.done then pending = nil end
end
ns:On("UNIT_SPELLCAST_INTERRUPTED", Cancel)
ns:On("UNIT_SPELLCAST_FAILED", Cancel)

ns:On("LOOT_OPENED", function()
    if not pending or not pending.done or GetTime() - pending.done > 5 then return end
    local itemID = pending.itemID
    pending = nil
    local quality, _, _, key = D.Classify(itemID)
    if not quality then return end
    local got = {}
    for slot = 1, GetNumLootItems() do
        local matID = ns.ItemIDFromLink(ns.Safe(GetLootSlotLink(slot)))
        local qty = ns.Safe(select(3, GetLootSlotInfo(slot))) or 1
        if matID then got[matID] = (got[matID] or 0) + math.max(1, qty) end
    end
    if not next(got) then return end
    local token = string.format("%x%04x", time() % 0x10000000, math.random(0, 0xffff))
    D.Record(key, got, false, token)
    if ns.Sync then ns.Sync.SendDisenchant(token, key, got) end
end)
