-- Balgourde - Partage des observations avec la guilde et le groupe
--
-- Chaque kill et chaque cadavre fouillé est mis en file, puis envoyé par
-- paquets toutes les 5 secondes (message d'addon invisible) aux autres joueurs
-- qui ont Balgourde. Un même cadavre n'est compté qu'une fois grâce à son GUID.
-- Les observations reçues sont rangées à part (mob.shared) : on peut les
-- exclure des taux, les effacer, ou ignorer un joueur.
local _, ns = ...
local L = ns.L

ns.Sync = {}
local S = ns.Sync
local PREFIX = "Balgourde"
local PROTO = "2"
local MAX_LEN = 240           -- taille max d'un message (limite du jeu : 255)
local FLUSH_EVERY = 5         -- secondes entre deux envois
local MAX_PER_FLUSH = 3       -- messages max par canal et par envoi (le jeu limite le débit)
local Safe = ns.Safe

local SendAddonMessage = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix

local outbox = {}        -- enregistrements en attente d'envoi (chaînes)
local lootQueue = {}     -- [guid] = loot en cours (envoyé à la fermeture de la fenêtre de loot)
S.received = 0

local function Clean(name)
    return (tostring(name or ""):gsub("[;|~:\n]", ""))
end

local function Channels()
    local s = BalgourdeDB.settings
    local list = {}
    if s.syncGroup and IsInGroup and IsInGroup() then
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then
            list[#list + 1] = "INSTANCE_CHAT"
        elseif IsInRaid() then
            list[#list + 1] = "RAID"
        else
            list[#list + 1] = "PARTY"
        end
    end
    if s.syncGuild and IsInGuild and IsInGuild() then
        list[#list + 1] = "GUILD"
    end
    return list
end

---------------------------------------------------------------------------
-- Envoi groupé
---------------------------------------------------------------------------
-- Format v2 : "2;" + enregistrements séparés par "~"
--   D:guid:mapID:nom                      (kill vu mourir)
--   L:guid:mapID:cuivre:id,id,id:nom      (cadavre fouillé)
function S.Flush()
    if #outbox == 0 then return end
    local channels = Channels()
    if #channels == 0 or not SendAddonMessage then wipe(outbox) return end
    local sent = 0
    while #outbox > 0 and sent < MAX_PER_FLUSH do
        local parts, len = {}, #PROTO + 1
        while #outbox > 0 and len + #outbox[1] + 1 <= MAX_LEN do
            local rec = table.remove(outbox, 1)
            parts[#parts + 1] = rec
            len = len + #rec + 1
        end
        if #parts == 0 then table.remove(outbox, 1) else -- enregistrement trop long : abandonné
            local msg = PROTO .. ";" .. table.concat(parts, "~")
            for _, channel in ipairs(channels) do
                if ns.SafeCall("envoi " .. channel, SendAddonMessage, PREFIX, msg, channel) then ns.Count("syncSent") end
            end
            sent = sent + 1
        end
    end
    -- file trop longue (gros farm) : on garde les 200 plus récents
    while #outbox > 200 do table.remove(outbox, 1) end
end

function S.SendKill(guid, mapID, name)
    outbox[#outbox + 1] = table.concat({ "D", guid, tostring(mapID or 0), Clean(name) }, ":")
end

-- items = { [itemID] = quantité } -> "id*qté,id*qté"
local function EncodeItems(items)
    local parts = {}
    for id, q in pairs(items) do
        parts[#parts + 1] = id .. "*" .. math.floor(q)
        if #parts >= 10 then break end
    end
    return table.concat(parts, ",")
end
local function DecodeItems(txt)
    local items, n = {}, 0
    for id, q in tostring(txt or ""):gmatch("(%d+)%*(%d+)") do
        n = n + 1
        if n > 10 then break end
        items[tonumber(id)] = math.min(tonumber(q), 100)
    end
    return items
end

-- Dépeçage : S:guid:mapID:id*qté,...
function S.SendSkin(guid, mapID, items)
    outbox[#outbox + 1] = table.concat({ "S", guid, tostring(mapID or 0), EncodeItems(items) }, ":")
end

-- Désenchantement : E:jeton:tranche(points):id*qté,...
function S.SendDisenchant(token, key, got)
    outbox[#outbox + 1] = table.concat({ "E", token, (key:gsub(":", ".")), EncodeItems(got) }, ":")
end

function S.QueueLoot(guid, mapID, name, items, copper)
    lootQueue[guid] = { mapID = mapID, name = name, items = items, copper = copper or 0 }
end
function S.AddQueuedMoney(guid, delta)
    if lootQueue[guid] then lootQueue[guid].copper = lootQueue[guid].copper + delta end
end
-- appelé à la fermeture de la fenêtre de loot
function S.FlushLoot()
    for guid, q in pairs(lootQueue) do
        local ids = {}
        for itemID in pairs(q.items or {}) do
            ids[#ids + 1] = tostring(itemID)
            if #ids >= 15 then break end
        end
        outbox[#outbox + 1] = table.concat({ "L", guid, tostring(q.mapID or 0), tostring(math.floor(q.copper or 0)),
                                             table.concat(ids, ","), Clean(q.name) }, ":")
    end
    wipe(lootQueue)
end

---------------------------------------------------------------------------
-- Réception
---------------------------------------------------------------------------
local function ShortName(sender)
    if not sender then return nil end
    return Ambiguate and Ambiguate(sender, "none") or sender:match("^[^-]+")
end

local function Apply(kind, guid, mapID, copper, itemList, name, sender)
    local npcID = ns.NpcIDFromGUID(guid)
    if not npcID then return end
    mapID = tonumber(mapID)
    if mapID == 0 then mapID = nil end
    local ok
    if kind == "D" then
        ok = ns.Recorder.ApplyKill(guid, npcID, mapID, name, true)
    elseif kind == "L" then
        copper = math.max(0, math.min(tonumber(copper) or 0, 10000000))
        local items, n = {}, 0
        for id in tostring(itemList or ""):gmatch("%d+") do
            n = n + 1
            if n > 20 then break end
            items[tonumber(id)] = true
        end
        ok = ns.Recorder.ApplyLoot(guid, npcID, mapID, name, items, copper, true)
    end
    if ok then
        ns.Count("syncReceived")
        S.received = S.received + 1
        BalgourdeDB.senders[sender] = (BalgourdeDB.senders[sender] or 0) + 1
    end
end

function S.Handle(text, sender)
    local me = UnitName("player")
    sender = ShortName(sender)
    if not sender or sender == me then return end
    if BalgourdeDB.settings.ignoredSenders[sender:lower()] then return end

    local proto, body = text:match("^(%d+);(.*)$")
    if proto == "2" then
        local count = 0
        for rec in body:gmatch("[^~]+") do
            count = count + 1
            if count > 30 then break end
            local f = { strsplit(":", rec) }
            if f[1] == "D" then
                Apply("D", f[2], f[3], nil, nil, f[4], sender)
            elseif f[1] == "L" then
                Apply("L", f[2], f[3], f[4], f[5], f[6], sender)
            elseif f[1] == "S" then
                local npcID = ns.NpcIDFromGUID(f[2])
                local items = DecodeItems(f[4])
                if npcID and next(items) and ns.Skinning.Record(f[2], npcID, items, true) then
                    local mapID = tonumber(f[3])
                    if mapID and mapID > 0 then ns.AddMobToZone(npcID, mapID) end
                    ns.Count("syncReceived")
                    BalgourdeDB.senders[sender] = (BalgourdeDB.senders[sender] or 0) + 1
                end
            elseif f[1] == "E" then
                local key = tostring(f[3] or ""):gsub("%.", ":")
                local items = DecodeItems(f[4])
                -- tranche valide : qualité 2-4, type, numéro
                if key:match("^[234]:%a+:%d+$") and next(items) and f[2] and #f[2] <= 16
                   and ns.Disenchant.Record(key, items, true, f[2]) then
                    ns.Count("syncReceived")
                    BalgourdeDB.senders[sender] = (BalgourdeDB.senders[sender] or 0) + 1
                end
            end
        end
    elseif proto == "1" then
        -- ancienne version (0.3.x) : un enregistrement par message, séparé par ";"
        local f = { strsplit(";", text) }
        if f[2] == "D" then
            Apply("D", f[3], f[4], nil, nil, f[5], sender)
        elseif f[2] == "L" then
            Apply("L", f[3], f[4], f[5], f[6], f[7], sender)
        end
    end
end

ns:On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    prefix, text, sender = Safe(prefix), Safe(text), Safe(sender)
    if prefix ~= PREFIX or not text then return end
    local s = BalgourdeDB.settings
    if channel == "GUILD" and not s.syncGuild then return end
    if channel ~= "GUILD" and not s.syncGroup then return end
    S.Handle(text, sender)
end)

ns.Listen("LOADED", function()
    if RegisterPrefix then pcall(RegisterPrefix, PREFIX) end
    C_Timer.NewTicker(FLUSH_EVERY, S.Flush)
end)

---------------------------------------------------------------------------
-- Gestion
---------------------------------------------------------------------------
function S.Status()
    local s = BalgourdeDB.settings
    ns.Print(string.format(L["Partage – guilde : %s, groupe : %s, données reçues incluses dans les taux : %s."],
        s.syncGuild and L["oui"] or L["non"], s.syncGroup and L["oui"] or L["non"], s.useShared and L["oui"] or L["non"]))
    ns.Print(string.format(L["Reçu cette session : %d observations. En attente d'envoi : %d."], S.received, #outbox))
    local list = {}
    for name, n in pairs(BalgourdeDB.senders) do list[#list + 1] = { name, n } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(10, #list) do
        local ignored = s.ignoredSenders[list[i][1]:lower()] and L[" |cffff5555(ignoré)|r"] or ""
        ns.Print(string.format("  %s : %d%s", list[i][1], list[i][2], ignored))
    end
    if #list == 0 then ns.Print(L["  Aucune donnée reçue pour l'instant."]) end
end

function S.Ignore(name)
    if not name or name == "" then ns.Print(L["Usage : /balg ignorer NomDuJoueur"]) return end
    local key = name:lower()
    local s = BalgourdeDB.settings
    s.ignoredSenders[key] = not s.ignoredSenders[key] or nil
    ns.Print(name .. (s.ignoredSenders[key] and L[" est ignoré : ses données seront refusées."]
        or L[" n'est plus ignoré."]) .. L[" (Les données déjà reçues restent : /balg effacer-recu pour tout effacer.)"])
end
