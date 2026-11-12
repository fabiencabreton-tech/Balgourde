-- Balgourde - Dépeçage : compétence requise et cuirs/peaux possibles sur chaque monstre
--
-- Compétence requise (formule Classic) : 1 jusqu'au niveau 10, niveau×10−100 du 11 au 20,
-- niveau×5 au-delà. Cuirs possibles selon le niveau du monstre (tranches Classic).
-- Les vrais résultats de vos dépeçages sont enregistrés par monstre et remplacent la table.
local _, ns = ...
local L = ns.L

ns.Skinning = {}
local S = ns.Skinning
local Safe = ns.Safe

local SKINNING_LINE = 393                         -- identifiant de la compétence (client moderne)
local SKIN_SPELLS = { [8613] = true, [8617] = true, [8618] = true, [10768] = true }
-- autres récoltes possibles sur un cadavre : on les ignore pour les taux de loot
local GATHER_SPELLS = { [2366] = true, [2368] = true, [3570] = true, [11993] = true,
                        [2575] = true, [2576] = true, [3564] = true, [10248] = true }

-- Cuirs et peaux Classic : itemID, niveau de monstre min, max
local LEATHER = {
    { 2934, 1, 16 },   -- Restes de cuir abîmés
    { 2318, 1, 27 },   -- Cuir léger
    { 783, 10, 27 },   -- Peau légère
    { 2319, 15, 36 },  -- Cuir moyen
    { 4232, 15, 36 },  -- Peau moyenne
    { 4234, 25, 46 },  -- Cuir lourd
    { 4235, 25, 46 },  -- Peau lourde
    { 4304, 35, 63 },  -- Cuir épais
    { 8169, 40, 59 },  -- Peau épaisse
    { 8170, 43, 63 },  -- Cuir robuste
    { 8171, 47, 63 },  -- Peau robuste
}
S.LEATHER = LEATHER

-- Types de créatures habituellement dépeçables
local SKINNABLE_TYPES = { ["Beast"] = true, ["Bête"] = true, ["Dragonkin"] = true, ["Draconien"] = true }

function S.RequiredSkill(level)
    if not level or level < 1 then return nil end
    if level <= 10 then return 1 end
    if level <= 20 then return level * 10 - 100 end
    return level * 5
end

---------------------------------------------------------------------------
-- Compétence du joueur
---------------------------------------------------------------------------
local skillName, playerSkill
local function SkinningName()
    if skillName then return skillName end
    if C_Spell and C_Spell.GetSpellName then skillName = C_Spell.GetSpellName(8613)
    elseif GetSpellInfo then skillName = GetSpellInfo(8613) end
    return skillName
end

function S.UpdateSkill()
    playerSkill = nil
    -- client moderne
    if GetProfessions and GetProfessionInfo then
        local p1, p2 = GetProfessions()
        for _, idx in ipairs({ p1, p2 }) do
            if idx then
                local _, _, rank, _, _, _, line = GetProfessionInfo(idx)
                if line == SKINNING_LINE then playerSkill = rank end
            end
        end
    end
    -- client Classic
    if not playerSkill and GetNumSkillLines and GetSkillLineInfo then
        local name = SkinningName()
        for i = 1, GetNumSkillLines() do
            local lineName, isHeader, _, rank = GetSkillLineInfo(i)
            if not isHeader and name and lineName == name then playerSkill = rank end
        end
    end
    return playerSkill
end

function S.PlayerSkill() return playerSkill end

---------------------------------------------------------------------------
-- Résultats : vos observations pour ce monstre, sinon la table par niveau
---------------------------------------------------------------------------
-- Retourne outcomes, source ("obs" | "table"), nb de dépeçages observés
--   outcomes = { {itemID, prob (obs), avg, min, max}, ... }  (table : prob = nil = « possible »)
-- Vos dépeçages + ceux reçus de la guilde / du groupe (si l'option est active)
local function MergedSkin(mob)
    if not mob then return nil end
    local own, sh = mob.skin, BalgourdeDB.settings.useShared and mob.skinShared
    if not sh or (sh.n or 0) == 0 then return own end
    if not own or own.n == 0 then return sh end
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

function S.GetOutcomes(npcID, level)
    local mob = BalgourdeDB.mobs[npcID]
    local skin = MergedSkin(mob)
    if skin and skin.n > 0 then
        local out = {}
        for itemID, m in pairs(skin.mats) do
            out[#out + 1] = { itemID = itemID, prob = m.hits / skin.n, avg = m.qty / m.hits, min = m.min, max = m.max }
        end
        table.sort(out, function(a, b) return a.prob > b.prob end)
        return out, "obs", skin.n
    end
    level = level or (mob and (mob.maxLevel or mob.minLevel))
    if not level or level < 1 then return nil end
    local out = {}
    for _, l in ipairs(LEATHER) do
        if level >= l[2] and level <= l[3] then out[#out + 1] = { itemID = l[1] } end
    end
    return out, "table", 0
end

-- Valeur moyenne d'un dépeçage (observations seulement)
function S.GetValue(npcID)
    local out, source = S.GetOutcomes(npcID)
    if source ~= "obs" then return nil end
    local total = 0
    for _, o in ipairs(out) do
        local best = ns.Auction.GetBest(o.itemID)
        o.price = best and best.net or 0
        total = total + o.prob * o.avg * o.price
    end
    return total, out
end

-- Ce monstre est-il (probablement) dépeçable ?
function S.IsSkinnable(npcID, unit)
    local mob = BalgourdeDB.mobs[npcID]
    if mob and ((mob.skin and mob.skin.n > 0) or (mob.skinShared and mob.skinShared.n > 0)) then return true end
    local ctype = unit and Safe(UnitCreatureType(unit)) or (mob and mob.ctype)
    return ctype and SKINNABLE_TYPES[ctype] or false
end

-- Lignes pour les infobulles / la carte de cible
function S.AddLines(npcID, unit, add)
    if not BalgourdeDB.settings.tooltipSkin or not S.IsSkinnable(npcID, unit) then return end
    local mob = BalgourdeDB.mobs[npcID]
    local level = unit and Safe(UnitLevel(unit)) or (mob and mob.maxLevel)
    if level == -1 then level = nil end
    local req = S.RequiredSkill(level)
    local skill = playerSkill
    local skillTxt = ""
    if req then
        skillTxt = L["compétence "] .. req
        if skill then
            local color = skill >= req and "|cff00ff00" or "|cffff5555"
            skillTxt = skillTxt .. " " .. color .. L["(vous : "] .. skill .. ")|r"
        end
    end
    local value = S.GetValue(npcID)
    add(L["|cffc79c6eDépeçage|r  |cff999999"] .. skillTxt .. "|r", value and ("~" .. ns.Money(value)) or "")
    local out, source, n = S.GetOutcomes(npcID, level)
    if not out or #out == 0 then return end
    if source == "obs" then
        for i = 1, math.min(4, #out) do
            local o = out[i]
            local name = ns.GetItemInfo(o.itemID) or (L["Objet #"] .. o.itemID)
            local q = (o.min and o.max and o.min ~= o.max) and (" ×" .. o.min .. "-" .. o.max) or (" ×" .. (o.min or 1))
            add("    " .. name .. q, ns.Percent(o.prob) .. (n < ns.ReliableKills() and string.format(" |cff888888(%d)|r", n) or ""),
                0.85, 0.75, 0.6)
        end
    else
        local names = {}
        for _, o in ipairs(out) do names[#names + 1] = ns.GetItemInfo(o.itemID) or (L["Objet #"] .. o.itemID) end
        add(L["    Possible : "] .. table.concat(names, ", "), nil, 0.7, 0.7, 0.7)
    end
end

---------------------------------------------------------------------------
-- Apprentissage : résultats de vos dépeçages
---------------------------------------------------------------------------
local gatherAt, skinAt = -1e9, -1e9 -- jamais : un loot ordinaire ne doit pas passer pour un dépeçage

-- Une fenêtre de loot vient-elle d'un dépeçage / d'une récolte (et non d'un cadavre) ?
function S.IsGatherLoot()
    return GetTime() - gatherAt < 3
end

local function IsSkinSpell(spellID)
    if SKIN_SPELLS[spellID] then return true end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
        or (GetSpellInfo and GetSpellInfo(spellID))
    return name ~= nil and name == SkinningName()
end

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    spellID = Safe(spellID)
    if unit ~= "player" or not spellID then return end
    if IsSkinSpell(spellID) then
        gatherAt, skinAt = GetTime(), GetTime()
    elseif GATHER_SPELLS[spellID] then
        gatherAt = GetTime()
    end
end)

local skinSeen = {} -- [guid] = true : cadavre déjà compté (vous ou reçu)

-- Enregistre un dépeçage. items = { [itemID] = quantité }
function S.Record(guid, npcID, items, remote)
    if not guid or skinSeen[guid] or not npcID or not next(items) then return false end
    skinSeen[guid] = true
    local mob = ns.GetMob(npcID, true)
    local key = remote and "skinShared" or "skin"
    mob[key] = mob[key] or { n = 0, mats = {} }
    local skin = mob[key]
    skin.n = skin.n + 1
    for itemID, qty in pairs(items) do
        local m = skin.mats[itemID] or { hits = 0, qty = 0 }
        skin.mats[itemID] = m
        m.hits, m.qty = m.hits + 1, m.qty + qty
        m.min, m.max = math.min(m.min or qty, qty), math.max(m.max or qty, qty)
    end
    if not remote then ns.Count("skins") end
    ns.Fire("DATA_CHANGED")
    return true
end

ns:On("LOOT_OPENED", function()
    if GetTime() - skinAt > 3 then return end
    skinAt = -1e9
    local perCorpse = {}
    for slot = 1, GetNumLootItems() do
        local itemID = ns.ItemIDFromLink(Safe(GetLootSlotLink(slot)))
        local qty = Safe(select(3, GetLootSlotInfo(slot))) or 1
        local sources = { GetLootSourceInfo(slot) }
        local guid = Safe(sources[1]) or Safe(UnitGUID("target"))
        local npcID = ns.NpcIDFromGUID(guid)
        if itemID and npcID then
            perCorpse[guid] = perCorpse[guid] or { npcID = npcID, items = {} }
            local it = perCorpse[guid].items
            it[itemID] = (it[itemID] or 0) + math.max(1, qty)
        end
    end
    local mapID = ns.GetCurrentZone()
    for guid, c in pairs(perCorpse) do
        if S.Record(guid, c.npcID, c.items, false) and ns.Sync then
            ns.Sync.SendSkin(guid, mapID, c.items)
        end
    end
end)

ns.Listen("LOADED", function() S.UpdateSkill() end)
ns:On("SKILL_LINES_CHANGED", function() S.UpdateSkill() end)
ns:On("CHAT_MSG_SKILL", function() S.UpdateSkill() end)
