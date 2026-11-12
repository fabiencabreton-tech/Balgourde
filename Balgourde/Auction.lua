-- Balgourde - Hôtel des ventes : relevé des prix et comparaison des marchés
local _, ns = ...
local L = ns.L

ns.Auction = {}
local AH = ns.Auction

-- Commission prélevée sur la vente (valeurs vanilla ; à ajuster si WoW Forever diffère)
AH.CUT = { Alliance = 0.05, Horde = 0.05, Neutral = 0.15 }
local LABEL_FR = { Alliance = "HV Alliance", Horde = "HV Horde", Neutral = "HV Neutre", Vendor = "Marchand" }
-- traduit à la lecture (la langue peut être choisie après le chargement)
AH.LABEL = setmetatable({}, { __index = function(_, k) local v = LABEL_FR[k]; return v and L[v] end })
AH.STALE = 3 * 24 * 3600 -- au-delà de 3 jours, un prix est signalé comme ancien
AH.HISTORY_DAYS = 14     -- jours d'historique conservés
-- Dépôt perdu si l'objet ne se vend pas, en fraction du prix marchand (estimation, à ajuster)
AH.DEPOSIT = { Alliance = 0.15, Horde = 0.15, Neutral = 0.15 }
AH.MIN_SALES = 3         -- nb de mises en vente avant d'utiliser votre taux de vente réel
AH.MAX_AGE = 7 * 24 * 3600 -- au-delà de 7 jours, un prix n'est plus utilisé pour les conseils
AH.MIN_RATE_SAMPLES = 3  -- ventes lues avant de remplacer la commission / le dépôt par défaut

---------------------------------------------------------------------------
-- Commission et dépôt réels, appris dans les courriers « Vente réussie »
---------------------------------------------------------------------------
-- BalgourdeDB.ahRates[marché] = { bid, cut, n, depRatio, depN }
function AH.Cut(mkt)
    local r = BalgourdeDB.ahRates[mkt]
    if r and r.n >= AH.MIN_RATE_SAMPLES and r.bid > 0 then return r.cut / r.bid, true end
    return AH.CUT[mkt] or 0.05, false
end
function AH.Deposit(mkt)
    local r = BalgourdeDB.ahRates[mkt]
    if r and (r.depN or 0) >= AH.MIN_RATE_SAMPLES then return r.depRatio / r.depN, true end
    return AH.DEPOSIT[mkt] or 0.15, false
end

local isOpen, market, scanning = false, nil, false

local function RealmKey() return GetRealmName() or "?" end

local function PriceTable(mkt)
    local realm = RealmKey()
    BalgourdeDB.prices[realm] = BalgourdeDB.prices[realm] or {}
    BalgourdeDB.prices[realm][mkt] = BalgourdeDB.prices[realm][mkt] or {}
    return BalgourdeDB.prices[realm][mkt]
end

function AH.IsScanning() return scanning end
function AH.CurrentMarket() return market end

-- Les commissaires-priseurs neutres (Gadgetzan, Baie-du-Butin, Long-guet) n'ont pas de faction
local NEUTRAL_SUBZONES = {
    ["Gadgetzan"] = true, ["Booty Bay"] = true, ["Baie-du-Butin"] = true,
    ["Everlook"] = true, ["Long-guet"] = true,
}
local function DetectMarket()
    local f = UnitExists("npc") and UnitFactionGroup("npc")
    if f == "Alliance" or f == "Horde" then return f end
    if UnitExists("npc") then return "Neutral" end
    if NEUTRAL_SUBZONES[GetSubZoneText() or ""] then return "Neutral" end
    return UnitFactionGroup("player")
end

---------------------------------------------------------------------------
-- Statistiques de prix
---------------------------------------------------------------------------
-- listings = { {unit, count}, ... }
-- min    = enchère la moins chère
-- market = médiane (pondérée par la quantité) du quart le moins cher de l'offre :
--          une enchère isolée bradée ou un prix délirant ne fausse plus le conseil.
function AH.ComputeStats(listings)
    if #listings == 0 then return nil end
    table.sort(listings, function(a, b) return a[1] < b[1] end)
    local total = 0
    for _, l in ipairs(listings) do total = total + l[2] end
    local target = math.max(1, total * 0.25)
    local subset, sub = {}, 0
    for _, l in ipairs(listings) do
        subset[#subset + 1] = l
        sub = sub + l[2]
        if sub >= target then break end
    end
    -- médiane pondérée du sous-ensemble
    local half, acc, market = sub / 2, 0, subset[#subset][1]
    for _, l in ipairs(subset) do
        acc = acc + l[2]
        if acc >= half then market = l[1]; break end
    end
    return { min = listings[1][1], market = market, qty = total, n = #listings }
end

local function AddListing(scratch, itemID, count, buyout)
    if not itemID or not buyout or buyout <= 0 then return end
    count = (count and count > 0) and count or 1
    local list = scratch[itemID]
    if not list then list = {}; scratch[itemID] = list end
    list[#list + 1] = { buyout / count, count }
end

-- Prix retenu pour vendre : valeur de marché, sinon le plus bas
function AH.SellPrice(e)
    return e and (e.market or e.min)
end

---------------------------------------------------------------------------
-- API classique (QueryAuctionItems / GetAuctionItemInfo) et moderne (ReplicateItems)
---------------------------------------------------------------------------
local HAS_LEGACY = QueryAuctionItems ~= nil and GetAuctionItemInfo ~= nil
local HAS_REPLICATE = (C_AuctionHouse and C_AuctionHouse.ReplicateItems) ~= nil

-- Analyse d'un scan complet, par paquets pour ne pas figer le jeu.
--   * vos propres enchères sont exclues (elles fausseraient le prix)
--   * les enchères dont le jeu n'a pas encore fourni l'objet sont relues jusqu'à 3 fois
--   * si l'HV est fermé pendant l'analyse, rien n'est écrit : vos prix restent intacts
local function ReadRow(getRow, idx, scratch, me, stats)
    local name, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID, hasAllInfo = getRow(idx)
    if not itemID then return false end
    if hasAllInfo == false and (not name or name == "") then return false end
    if owner and me and owner == me then stats.mine = stats.mine + 1; return true end
    AddListing(scratch, itemID, count, buyout)
    if name and name ~= "" then BalgourdeDB.itemNames[itemID] = name end
    return true
end

local function ProcessInBatches(total, getRow, offset, onDone)
    local scratch, missing = {}, {}
    local stats = { mine = 0, incomplete = 0, total = total }
    local me = UnitName("player")
    local i = 0
    local ticker

    local function Abort()
        if ticker then ticker:Cancel() end
        scanning = false
        ns.Print(L["Scan interrompu (HV fermé) : vos prix précédents sont conservés."])
        if ns.UI and ns.UI.SetStatus then ns.UI.SetStatus("") end
        ns.Fire("AH_STATE")
    end

    local function Finalize()
        if not isOpen or scanning ~= "processing" then return Abort() end
        stats.incomplete = #missing
        local tbl, now = PriceTable(market), time()
        local seen = 0
        for itemID, listings in pairs(scratch) do
            local st = AH.ComputeStats(listings)
            if st then st.t = now; tbl[itemID] = st; seen = seen + 1 end
        end
        if seen == 0 then
            scanning = false
            ns.Print(L["Scan vide : vos prix précédents sont conservés."])
            ns.Fire("AH_STATE")
            return
        end
        -- objets absents de ce scan : plus en vente, on garde leur dernier prix connu
        for itemID, e in pairs(tbl) do
            if not scratch[itemID] then e.qty, e.n = 0, 0 end
        end
        AH.RecordHistory(market, tbl, now)
        onDone(total, stats)
    end

    -- relecture des enchères incomplètes (le jeu charge les objets en arrière-plan)
    local function Retry(attempt)
        if not isOpen or scanning ~= "processing" then return Abort() end
        local still = {}
        for _, idx in ipairs(missing) do
            if not ReadRow(getRow, idx, scratch, me, stats) then still[#still + 1] = idx end
        end
        missing = still
        if #missing > 0 and attempt < 3 then
            C_Timer.After(1.5, function() Retry(attempt + 1) end)
        else
            Finalize()
        end
    end

    ticker = C_Timer.NewTicker(0.01, function()
        if not isOpen or scanning ~= "processing" then return Abort() end
        local stop = math.min(i + 800, total)
        for idx = i + 1, stop do
            local row = idx - 1 + offset
            if not ReadRow(getRow, row, scratch, me, stats) then missing[#missing + 1] = row end
        end
        i = stop
        if ns.UI and ns.UI.SetStatus then
            ns.UI.SetStatus(string.format(L["Analyse HV : %d / %d"], i, total))
        end
        if i >= total then
            ticker:Cancel()
            if #missing > 0 then
                C_Timer.After(1.5, function() Retry(1) end)
            else
                Finalize()
            end
        end
    end)
end

local function FinishScan(total, stats)
    scanning = false
    ns.Count("scans")
    BalgourdeDB.lastScan = BalgourdeDB.lastScan or {}
    BalgourdeDB.lastScan[RealmKey() .. "-" .. market] = time()
    AH.InvalidateCache()
    ns.Print(string.format(L["Scan terminé (%s) : %d enchères analysées."], AH.LABEL[market] or market, total))
    if stats and (stats.mine > 0 or stats.incomplete > 0) then
        ns.Print(string.format(L["  dont %d à vous (exclues du prix) et %d incomplètes (ignorées)."], stats.mine, stats.incomplete))
    end
    if ns.UI and ns.UI.SetStatus then ns.UI.SetStatus("") end
    ns.Fire("AH_STATE")
    ns.Fire("PRICES_CHANGED")
end

function AH.StartScan()
    if not AH.IsOpen() then ns.Print(L["Ouvrez d'abord l'Hôtel des ventes (parlez à un commissaire-priseur)."]) return end
    if scanning then ns.Print(L["Scan déjà en cours…"]) return end

    if HAS_LEGACY then
        local canQuery, canQueryAll = CanSendAuctionQuery()
        if not canQueryAll then
            ns.Print(L["Le serveur n'autorise un scan complet que toutes les 15 minutes environ. Réessayez plus tard."])
            return
        end
        scanning = "legacy"
        ns.Print(L["Scan complet de l'HV lancé, le jeu peut figer quelques secondes…"])
        local ok, err = pcall(QueryAuctionItems, "", nil, nil, 0, false, nil, true, false, nil)
        if not ok then scanning = false; ns.Print(L["Échec du scan : "] .. tostring(err)) return end
    elseif HAS_REPLICATE then
        scanning = "replicate"
        ns.Print(L["Scan complet de l'HV lancé…"])
        local ok, err = pcall(C_AuctionHouse.ReplicateItems)
        if not ok then scanning = false; ns.Print(L["Échec du scan : "] .. tostring(err)) return end
    else
        ns.Print(L["API de l'Hôtel des ventes non reconnue sur ce client. Tapez /balg hv et envoyez le résultat."])
        return
    end
    ns.Fire("AH_STATE")
    -- si le serveur ne répond pas, on débloque le bouton au bout de 60 s
    local started = scanning
    C_Timer.After(60, function()
        if scanning == started then
            scanning = false
            ns.Print(L["Le serveur n'a pas répondu au scan. Réessayez dans quelques minutes."])
            ns.Fire("AH_STATE")
        end
    end)
end

ns:On("AUCTION_ITEM_LIST_UPDATE", function()
    if not isOpen or not HAS_LEGACY then return end
    if scanning == "legacy" then
        scanning = "processing"
        local total = GetNumAuctionItems("list")
        ProcessInBatches(total, function(i) return GetAuctionItemInfo("list", i) end, 1, FinishScan)
    elseif not scanning then
        -- capture passive des recherches manuelles (une page = 50 enchères max)
        local scratch = {}
        local stats, me = { mine = 0 }, UnitName("player")
        for i = 1, GetNumAuctionItems("list") do
            ReadRow(function(idx) return GetAuctionItemInfo("list", idx) end, i, scratch, me, stats)
        end
        local tbl, now = PriceTable(market), time()
        for itemID, listings in pairs(scratch) do
            local st = AH.ComputeStats(listings)
            local e = tbl[itemID]
            -- on remplace si plus récent d'1 h, sinon on garde le plus bas et la valeur de marché existante
            if st and (not e or (now - (e.t or 0)) > 3600) then
                st.t = now; tbl[itemID] = st
            elseif st and st.min < e.min then
                e.min = st.min
            end
        end
        AH.InvalidateCache()
        ns.Fire("PRICES_CHANGED")
    end
end)

ns:On("REPLICATE_ITEM_LIST_UPDATE", function()
    if scanning ~= "replicate" then return end
    scanning = "processing"
    local total = C_AuctionHouse.GetNumReplicateItems()
    ProcessInBatches(total, function(i) return C_AuctionHouse.GetReplicateItemInfo(i) end, 0, FinishScan)
end)

---------------------------------------------------------------------------
-- Ouverture / fermeture
---------------------------------------------------------------------------
local scanButton
local function EnsureScanButton()
    local parent = AuctionFrame or AuctionHouseFrame
    if not parent or scanButton then return end
    scanButton = CreateFrame("Button", "BalgourdeScanButton", parent, "UIPanelButtonTemplate")
    scanButton:SetSize(130, 22)
    scanButton:SetText(L["Balgourde : scan"])
    scanButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -60, -14)
    scanButton:SetScript("OnClick", AH.StartScan)
    scanButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Balgourde")
        GameTooltip:AddLine(L["Relève le prix le plus bas de chaque objet de cet HV."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    scanButton:SetScript("OnLeave", GameTooltip_Hide)
end

local function OnOpen()
    if isOpen then return end
    isOpen = true
    market = DetectMarket()
    EnsureScanButton()
    ns.Debug(L["HV ouvert, marché : "] .. tostring(market))
    ns.Fire("AH_STATE")
end
local closedAt = -1e9
local function OnClose()
    if not isOpen then return end
    isOpen = false
    closedAt = GetTime()
    -- pendant l'analyse, c'est elle qui s'arrête proprement et prévient
    if scanning and scanning ~= "processing" then
        scanning = false
        ns.Print(L["HV fermé : scan interrompu."])
    end
    ns.Fire("AH_STATE")
end

-- Ancien événement (client Classic)
ns:On("AUCTION_HOUSE_SHOW", OnOpen)
ns:On("AUCTION_HOUSE_CLOSED", OnClose)

-- Client moderne (moteur Midnight / Forever) : interactions avec les PNJ
local AUCTIONEER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Auctioneer or 21
ns:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
    if kind == AUCTIONEER then OnOpen() end
end)
ns:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
    if kind == AUCTIONEER then OnClose() end
end)

-- Filet de sécurité : la fenêtre d'HV de Blizzard elle-même
local hooked = {}
local function HookAHFrames()
    for _, name in ipairs({ "AuctionFrame", "AuctionHouseFrame" }) do
        local fr = _G[name]
        if fr and not hooked[name] then
            hooked[name] = true
            fr:HookScript("OnShow", OnOpen)
            fr:HookScript("OnHide", OnClose)
            if fr:IsShown() then OnOpen() end
        end
    end
end
ns:On("ADDON_LOADED", function() HookAHFrames() end)
ns.Listen("LOADED", HookAHFrames)

function AH.IsOpen()
    -- secours si le jeu n'a signalé aucune ouverture : la fenêtre de l'HV est-elle visible ?
    -- (jamais juste après une fermeture : la fenêtre peut encore être affichée un instant)
    if not isOpen and GetTime() - closedAt > 3 then
        local fr = AuctionHouseFrame or AuctionFrame
        if fr and fr:IsShown() then OnOpen() end
    end
    return isOpen
end

-- Diagnostic : /balg hv
function AH.Diagnose()
    ns.Print(L["HV ouvert : "] .. tostring(AH.IsOpen()) .. L[" – marché : "] .. tostring(market) .. L[" – scan : "] .. tostring(scanning))
    ns.Print(L["API ancienne (QueryAuctionItems) : "] .. tostring(HAS_LEGACY) .. L[" – API moderne (ReplicateItems) : "] .. tostring(HAS_REPLICATE))
    if HAS_LEGACY and CanSendAuctionQuery then
        local q, all = CanSendAuctionQuery()
        ns.Print(L["Recherche possible : "] .. tostring(q) .. L[" – scan complet possible : "] .. tostring(all))
    end
    ns.Print(L["Fenêtres : AuctionFrame="] .. tostring(AuctionFrame ~= nil) .. " AuctionHouseFrame=" .. tostring(AuctionHouseFrame ~= nil))
end

---------------------------------------------------------------------------
-- Historique des prix (une valeur par jour et par marché)
---------------------------------------------------------------------------
local function Today(t) return math.floor((t or time()) / 86400) end

-- anciennes versions : un simple nombre par jour
-- Une journée d'historique est stockée en texte compact "marché,plus bas,quantité"
-- (anciennes versions : nombre ou table, toujours lisibles)
function AH.DayEntry(v)
    if type(v) == "number" then return { m = v } end
    if type(v) == "string" then
        local m, l, q = v:match("^(%d+),(%d*),(%d*)$")
        return { m = tonumber(m) or 0, l = tonumber(l), q = tonumber(q) }
    end
    return v
end
local function Pack(m, l, q)
    return string.format("%d,%s,%s", math.floor(m or 0), l and tostring(math.floor(l)) or "", q and tostring(q) or "")
end

-- Objets dont on garde l'historique : ceux qui vous concernent
--   vos sacs (et objets déjà possédés), loots connus, cuirs, composants d'enchantement,
--   objets vendus par courrier, objets consultés dans leur fiche
function AH.WatchedItems()
    local w = {}
    for id in pairs(BalgourdeDB.watch) do w[id] = true end
    for _, mob in pairs(BalgourdeDB.mobs) do
        for id in pairs(mob.drops or {}) do w[id] = true end
        if mob.shared then for id in pairs(mob.shared.drops or {}) do w[id] = true end end
        if mob.pp then for id in pairs(mob.pp.drops or {}) do w[id] = true end end
        if mob.skin then for id in pairs(mob.skin.mats or {}) do w[id] = true end end
    end
    if ns.Seed then
        for _, mob in pairs(ns.Seed.mobs) do for id in pairs(mob.drops or {}) do w[id] = true end end
    end
    if ns.Disenchant then for _, id in pairs(ns.Disenchant.MATS) do w[id] = true end end
    if ns.Skinning then for _, l in ipairs(ns.Skinning.LEATHER) do w[l[1]] = true end end
    for k in pairs(BalgourdeDB.sales) do if type(k) == "number" then w[k] = true end end
    return w
end

function AH.Watch(itemID)
    if itemID then BalgourdeDB.watch[itemID] = true end
end

function AH.RecordHistory(mkt, tbl, now)
    local realm = RealmKey()
    BalgourdeDB.history[realm] = BalgourdeDB.history[realm] or {}
    local hist = BalgourdeDB.history[realm][mkt] or {}
    BalgourdeDB.history[realm][mkt] = hist
    local day, oldest = Today(now), Today(now) - AH.HISTORY_DAYS
    local watched = AH.WatchedItems()
    for itemID, e in pairs(tbl) do
        if watched[itemID] then
            local h = hist[itemID]
            if not h then h = {}; hist[itemID] = h end
            h[day] = Pack(AH.SellPrice(e), e.min, e.qty)
        end
    end
    -- purge : jours trop anciens, objets plus suivis, conversion des anciens formats
    for itemID, h in pairs(hist) do
        if not watched[itemID] then
            hist[itemID] = nil
        else
            local any = false
            for d, v in pairs(h) do
                if d < oldest then
                    h[d] = nil
                else
                    any = true
                    if type(v) ~= "string" then
                        local e = AH.DayEntry(v)
                        h[d] = Pack(e.m, e.l, e.q)
                    end
                end
            end
            if not any then hist[itemID] = nil end
        end
    end
end

-- Moyenne sur les N derniers jours (aujourd'hui exclu si possible) ; retourne moyenne, nb de jours
function AH.GetAverage(itemID, mkt, days)
    days = days or 7
    local realm = BalgourdeDB.history[RealmKey()]
    local h = realm and realm[mkt] and realm[mkt][itemID]
    if not h then return nil end
    local today = Today()
    local sum, n = 0, 0
    for d, v in pairs(h) do
        if d < today and d >= today - days then sum, n = sum + AH.DayEntry(v).m, n + 1 end
    end
    if n == 0 then return nil end
    return sum / n, n
end

---------------------------------------------------------------------------
-- Statistiques détaillées d'un objet sur un marché
---------------------------------------------------------------------------
function AH.MarketLabel(mkt) return AH.LABEL[mkt] or mkt end

-- Marchés accessibles à ce personnage et pour lesquels on a des données
function AH.ListMarkets()
    local list, seen = {}, {}
    local realm = RealmKey()
    for _, src in ipairs({ BalgourdeDB.prices[realm] or {}, BalgourdeDB.history[realm] or {} }) do
        for mkt in pairs(src) do
            if not seen[mkt] and AH.IsAccessible(mkt) then seen[mkt] = true; list[#list + 1] = mkt end
        end
    end
    table.sort(list)
    return list
end

function AH.DefaultMarket()
    if isOpen and market then return market end
    local list = AH.ListMarkets()
    local faction = UnitFactionGroup("player")
    for _, m in ipairs(list) do if m == faction then return m end end
    return list[1] or faction
end

-- Tous les objets connus sur un marché (prix actuel ou historique)
function AH.ListItems(mkt)
    local realm = RealmKey()
    local set, list = {}, {}
    local cur = BalgourdeDB.prices[realm] and BalgourdeDB.prices[realm][mkt]
    local hist = BalgourdeDB.history[realm] and BalgourdeDB.history[realm][mkt]
    for id in pairs(cur or {}) do set[id] = true end
    for id in pairs(hist or {}) do set[id] = true end
    for id in pairs(set) do list[#list + 1] = id end
    return list
end

-- Retrouve un objet par son nom (noms relevés pendant les scans de l'HV)
local nameIndex, nameIndexSize = nil, 0
function AH.ItemIDByName(name)
    if not name then return nil end
    local size = 0
    for _ in pairs(BalgourdeDB.itemNames) do size = size + 1; if size > nameIndexSize then break end end
    if not nameIndex or size ~= nameIndexSize then
        nameIndex, nameIndexSize = {}, 0
        for id, n in pairs(BalgourdeDB.itemNames) do nameIndex[n] = id; nameIndexSize = nameIndexSize + 1 end
    end
    return nameIndex[name]
end

function AH.ItemName(itemID)
    return BalgourdeDB.itemNames[itemID] or ns.GetItemInfo(itemID)
end

-- Historique trié du plus ancien au plus récent : { {day, m, l, q}, ... }
function AH.GetHistory(itemID, mkt)
    local realm = BalgourdeDB.history[RealmKey()]
    local h = realm and realm[mkt] and realm[mkt][itemID]
    local list = {}
    for d, v in pairs(h or {}) do
        local e = AH.DayEntry(v)
        list[#list + 1] = { day = d, m = e.m, l = e.l or e.m, q = e.q }
    end
    table.sort(list, function(a, b) return a.day < b.day end)
    return list
end

-- Statistiques : prix actuels, moyennes 7 et 14 jours, plus bas / plus haut sur 14 jours, tendance
function AH.GetStats(itemID, mkt)
    local realm = BalgourdeDB.prices[RealmKey()]
    local e = realm and realm[mkt] and realm[mkt][itemID]
    local history = AH.GetHistory(itemID, mkt)
    local st = {
        market = mkt, current = e and AH.SellPrice(e), min = e and e.min, qty = e and e.qty, n = e and e.n,
        age = e and e.t and (time() - e.t), history = history, days = #history,
        avg7 = AH.GetAverage(itemID, mkt, 7), avg14 = AH.GetAverage(itemID, mkt, 14),
    }
    local qsum, qn = 0, 0
    for _, d in ipairs(history) do
        if d.l then st.low14 = math.min(st.low14 or d.l, d.l) end
        if d.m then st.high14 = math.max(st.high14 or d.m, d.m) end
        if d.q then qsum, qn = qsum + d.q, qn + 1 end
    end
    if st.min then st.low14 = math.min(st.low14 or st.min, st.min) end
    if st.current then st.high14 = math.max(st.high14 or st.current, st.current) end
    if qn > 0 then st.qtyAvg = qsum / qn end
    if st.current and st.avg7 and st.avg7 > 0 then st.trend = st.current / st.avg7 - 1 end
    -- vos ventes : prix moyen réellement encaissé (commission déduite)
    local sold, expired, copper = AH.GetSales(itemID)
    if sold then
        st.sold, st.expired = sold, expired
        if sold > 0 then st.avgSale = copper / sold end
    end
    return st
end

---------------------------------------------------------------------------
-- Vos ventes réelles (courriers « Vente réussie » / « Enchère expirée »)
---------------------------------------------------------------------------
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)")
    p = p:gsub("%%s", "(.+)")
    return "^" .. p .. "$"
end
local SOLD_PAT = ToPattern(AUCTION_SOLD_MAIL_SUBJECT)
local EXPIRED_PAT = ToPattern(AUCTION_EXPIRED_MAIL_SUBJECT)
local processedMail = {}

local function SalesKey(itemID, name)
    if itemID then return itemID end
    return name and name:lower()
end

function AH.GetSales(itemID)
    local name = ns.GetItemInfo(itemID)
    local a = BalgourdeDB.sales[itemID]
    local b = name and BalgourdeDB.sales[name:lower()]
    if not a and not b then return nil end
    local sold = (a and a.sold or 0) + (b and b.sold or 0)
    local expired = (a and a.expired or 0) + (b and b.expired or 0)
    local copper = (a and a.soldCopper or 0) + (b and b.soldCopper or 0)
    return sold, expired, copper
end

-- Taux de vente réel (nil tant qu'il y a moins de AH.MIN_SALES mises en vente)
function AH.GetSellRate(itemID)
    local sold, expired = AH.GetSales(itemID)
    if not sold or sold + expired < AH.MIN_SALES then return nil end
    return sold / (sold + expired), sold, expired
end

-- Lit le détail d'une vente : prix, dépôt rendu, commission prélevée
local function SenderMarket(sender)
    sender = tostring(sender or "")
    if sender:find("Alliance") then return "Alliance" end
    if sender:find("Horde") then return "Horde" end
    return "Neutral"
end

function AH.LearnFromInvoice(index, itemID)
    if not GetInboxInvoiceInfo then return end
    local invoiceType, _, _, bid, _, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
    if invoiceType ~= "seller" or not bid or bid <= 0 or not consignment then return end
    local sender = select(3, GetInboxHeaderInfo(index))
    local mkt = SenderMarket(sender)
    local r = BalgourdeDB.ahRates[mkt] or { bid = 0, cut = 0, n = 0, depRatio = 0, depN = 0 }
    BalgourdeDB.ahRates[mkt] = r
    r.bid, r.cut, r.n = r.bid + bid, r.cut + consignment, r.n + 1
    -- dépôt rapporté au prix marchand de la pile vendue
    local vendor = itemID and select(11, ns.GetItemInfo(itemID))
    if deposit and deposit > 0 and vendor and vendor > 0 then
        local ratio = deposit / (vendor * math.max(1, tonumber(count) or 1))
        if ratio > 0 and ratio < 10 then r.depRatio, r.depN = r.depRatio + ratio, (r.depN or 0) + 1 end
    end
end

local function ProcessMail(index)
    if not GetInboxHeaderInfo then return end
    local _, _, _, subject, money, _, daysLeft = GetInboxHeaderInfo(index)
    if type(subject) ~= "string" then return end
    local key = subject .. "|" .. tostring(money) .. "|" .. string.format("%.2f", daysLeft or 0)
    if processedMail[key] then return end

    local name = SOLD_PAT and subject:match(SOLD_PAT)
    local kind = name and "sold"
    if not name then
        name = EXPIRED_PAT and subject:match(EXPIRED_PAT)
        kind = name and "expired"
    end
    if not kind then return end
    processedMail[key] = true

    local itemID
    if kind == "expired" and GetInboxItemLink then
        itemID = ns.ItemIDFromLink(GetInboxItemLink(index, 1))
    end
    itemID = itemID or ns.ItemIDFromLink(select(2, ns.GetItemInfo(name))) or AH.ItemIDByName(name)
    local k = SalesKey(itemID, name)
    if not k then return end
    local e = BalgourdeDB.sales[k] or { sold = 0, expired = 0, soldCopper = 0, name = name }
    BalgourdeDB.sales[k] = e
    ns.Count("mails")
    if kind == "sold" then
        e.sold = e.sold + 1
        e.soldCopper = e.soldCopper + (money or 0)
        AH.LearnFromInvoice(index, itemID)
    else
        e.expired = e.expired + 1
    end
    AH.InvalidateCache()
    ns.Fire("PRICES_CHANGED")
end

-- On compte un courrier quand vous en retirez l'or ou l'objet (y compris « Tout ouvrir »)
for _, fname in ipairs({ "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem" }) do
    if _G[fname] then
        hooksecurefunc(fname, function(index) ns.SafeCall("courrier", ProcessMail, index) end)
    end
end

---------------------------------------------------------------------------
-- Comparaison des marchés pour un objet
---------------------------------------------------------------------------
local cache = {}
function AH.InvalidateCache() wipe(cache) end

-- Marchés où ce personnage peut vendre : HV de sa faction + HV neutre
function AH.IsAccessible(mkt)
    return mkt == "Neutral" or mkt == UnitFactionGroup("player")
end

-- Retourne une liste triée (plus rentable d'abord) :
-- { { market, label, gross = prix de vente conseillé, net = ce que vous touchez, min, age, qty, n }, ... }
function AH.GetMarkets(itemID)
    local c = cache[itemID]
    if c then return c end
    local out = {}
    local sell = select(11, ns.GetItemInfo(itemID))
    local cacheable = sell ~= nil
    if sell and sell > 0 then
        out[#out + 1] = { market = "Vendor", label = AH.LABEL.Vendor, gross = sell, net = sell }
    end
    local realm = BalgourdeDB.prices[RealmKey()]
    local sellRate = AH.GetSellRate(itemID)
    if realm then
        local now = time()
        for mkt, tbl in pairs(realm) do
            local e = tbl[itemID]
            if e and e.min and AH.IsAccessible(mkt) then
                local cut = AH.Cut(mkt)
                local price = AH.SellPrice(e)
                local m = {
                    market = mkt, label = AH.LABEL[mkt] or mkt,
                    gross = price, net = math.floor(price * (1 - cut)), min = e.min,
                    age = now - (e.t or now), qty = e.qty, n = e.n,
                    avg7 = AH.GetAverage(itemID, mkt, 7),
                }
                -- prix trop ancien : affiché, mais plus utilisé pour conseiller
                if m.age > AH.MAX_AGE then m.stale = true end
                -- gain espéré selon votre taux de vente réel : un invendu fait perdre le dépôt
                if sellRate then
                    local deposit = (sell or 0) * AH.Deposit(mkt)
                    m.expected = math.floor(sellRate * m.net - (1 - sellRate) * deposit)
                end
                out[#out + 1] = m
            end
        end
    end
    -- désenchantement (si activé : par défaut quand le personnage sait désenchanter)
    local D = ns.Disenchant
    if D and D.InBest() then
        local v = D.GetValue(itemID)
        if v and v > 0 then
            out[#out + 1] = { market = "Disenchant", label = L["Désenchanter"], gross = math.floor(v), net = math.floor(v) }
        end
    end
    -- classement : gain espéré si on connaît votre taux de vente, sinon gain net
    table.sort(out, function(a, b)
        if (a.stale or false) ~= (b.stale or false) then return not a.stale end
        return (a.expected or a.net) > (b.expected or b.net)
    end)
    if cacheable then cache[itemID] = out end
    return out
end

function AH.GetBest(itemID)
    local m = AH.GetMarkets(itemID)
    return m[1], m
end

-- Meilleur HV accessible (hors marchand)
function AH.GetBestAH(itemID)
    for _, m in ipairs(AH.GetMarkets(itemID)) do
        if m.market ~= "Vendor" and m.market ~= "Disenchant" and not m.stale then return m end
    end
end
