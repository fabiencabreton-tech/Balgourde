-- Balgourde - Diagnostic en jeu (/balg test), journal d'erreurs (/balg erreurs), taille des données (/balg taille)
local _, ns = ...
local L = ns.L

ns.Diag = {}
local G = ns.Diag

local function Line(status, label, detail)
    local tag = status == "ok" and "|cff00ff00[OK]|r" or status == "warn" and "|cffffaa00[?]|r"
        or status == "info" and "|cff88aaff[i]|r" or "|cffff5555[X]|r"
    ns.Print(tag .. " " .. label .. (detail and detail ~= "" and (" |cffaaaaaa– " .. detail .. "|r") or ""))
end

local function C(key) return ns.Counters[key] or 0 end

function G.Run()
    local s = BalgourdeDB.settings
    local _, build, _, iface = GetBuildInfo()
    ns.Print(string.format(L["|cffd4a017=== Diagnostic Balgourde %s (jeu %s, interface %s) ===|r"], ns.VERSION,
        tostring(build), tostring(iface)))

    -- Moteur
    Line(issecretvalue and "info" or "info", L["Valeurs secrètes (moteur Midnight)"],
        issecretvalue and L["présentes : protections actives"] or "absentes")

    -- Monstres et kills
    local mapID, zone = ns.GetCurrentZone()
    Line(mapID and "ok" or "fail", L["Zone détectée"], tostring(zone) .. " (mapID " .. tostring(mapID) .. ")")
    Line(C("kills") > 0 and "ok" or "warn", L["Kills détectés cette session"], C("kills") > 0 and tostring(C("kills"))
        or L["aucun : tuez un monstre en le ciblant, puis relancez /balg test"])
    Line(C("loots") > 0 and "ok" or "warn", L["Cadavres fouillés cette session"], tostring(C("loots")))
    if C("moneyBySource") > 0 then
        Line("ok", L["Or par cadavre"], L["fourni par le jeu ("] .. C("moneyBySource") .. L[" fois)"])
    elseif C("moneyFallback") > 0 then
        Line("warn", L["Or par cadavre"], L["non fourni : mesuré par la variation de votre or ("] .. C("moneyFallback") .. L[" fois)"])
    else
        Line("warn", L["Or par cadavre"], L["pas encore testé : fouillez un cadavre qui a de l'or"])
    end
    if UnitExists("target") then
        local th = UnitThreatSituation("player", "target")
        Line("info", L["Menace sur la cible"], issecretvalue and issecretvalue(th) and L["secrète (kills comptés quand même)"]
            or (L["lisible : "] .. tostring(th)))
    end

    -- Infobulles
    local modern = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and true or false
    Line("info", L["Méthode des infobulles"], modern and L["client moderne"] or L["client classique"])
    Line(C("tooltipUnit") > 0 and "ok" or "warn", L["Infobulle des monstres"], C("tooltipUnit") > 0
        and (L["affichée "] .. C("tooltipUnit") .. L[" fois"]) or L["jamais affichée : survolez un monstre attaquable"])
    Line(C("tooltipItem") > 0 and "ok" or "warn", L["Infobulle des objets"], C("tooltipItem") > 0
        and (L["affichée "] .. C("tooltipItem") .. L[" fois"]) or L["jamais affichée : survolez un objet de vos sacs"])
    Line(BalgourdeTargetCard and "ok" or "fail", L["Carte de loot de la cible"], s.targetCard and L["activée"] or L["désactivée"])

    -- Minimap
    local btn = BalgourdeMinimapButton
    if btn then
        Line(btn:IsShown() and "ok" or "warn", L["Bouton de minimap"], btn:IsShown() and L["affiché"]
            or L["masqué : /balg minimap reset"])
    else
        Line("fail", L["Bouton de minimap"], L["non créé"])
    end
    Line(AddonCompartmentFrame and "ok" or "info", L["Menu des addons (client moderne)"],
        AddonCompartmentFrame and L["Balgourde y est listé"] or L["absent sur ce client"])

    -- Hôtel des ventes
    local legacy = QueryAuctionItems ~= nil
    local modernAH = C_AuctionHouse and C_AuctionHouse.ReplicateItems ~= nil
    Line((legacy or modernAH) and "ok" or "fail", L["API de l'Hôtel des ventes"],
        legacy and L["classique (QueryAuctionItems)"] or modernAH and L["moderne (ReplicateItems)"] or L["aucune reconnue"])
    Line(C("scans") > 0 and "ok" or "warn", L["Scans de l'HV cette session"], tostring(C("scans")))
    local markets = ns.Auction.ListMarkets()
    Line(#markets > 0 and "ok" or "warn", L["Marchés avec des prix"], #markets > 0 and table.concat(markets, ", ") or "aucun")
    Line((AUCTION_SOLD_MAIL_SUBJECT and AUCTION_EXPIRED_MAIL_SUBJECT) and "ok" or "fail", L["Lecture des courriers de l'HV"],
        C("mails") > 0 and (C("mails") .. L[" courriers lus"]) or L["formats connus, aucun courrier lu pour l'instant"])

    for _, mkt in ipairs({ UnitFactionGroup("player"), "Neutral" }) do
        local cut, learned = ns.Auction.Cut(mkt)
        Line(learned and "ok" or "info", string.format(L["Commission %s"], ns.Auction.MarketLabel(mkt)),
            string.format("%.1f %% ", cut * 100) .. (learned and L["(lue dans vos ventes)"] or L["(estimée : vendez 3 objets pour la vérifier)"]))
    end

    -- Métiers
    local skill = ns.Skinning.PlayerSkill()
    Line(skill and "ok" or "info", L["Compétence de dépeçage"], skill and tostring(skill) or L["non trouvée (métier non appris ?)"])
    Line(C("skins") > 0 and "ok" or "info", L["Dépeçages enregistrés cette session"], tostring(C("skins")))
    Line(C("disenchants") > 0 and "ok" or "info", L["Désenchantements enregistrés cette session"], tostring(C("disenchants")))

    -- Partage
    Line("info", L["Partage"], string.format(L["envoyés %d, reçus %d (guilde %s, groupe %s)"], C("syncSent"), C("syncReceived"),
        s.syncGuild and L["oui"] or L["non"], s.syncGroup and L["oui"] or L["non"]))

    -- Erreurs et taille
    Line(#ns.Errors == 0 and "ok" or "fail", L["Erreurs"], #ns.Errors == 0 and "aucune" or (#ns.Errors .. " : /balg erreurs"))
    local size = G.EstimateSize()
    Line(size < 3e6 and "ok" or "warn", L["Taille des données sauvegardées"], string.format(L["~%.1f Mo (/balg taille)"], size / 1e6))
    ns.Print(L["|cffd4a017Envoyez une capture de ce diagnostic au créateur si quelque chose est en [X] ou [?].|r"])
end

function G.ShowErrors(arg)
    if arg == "effacer" then wipe(ns.Errors); ns.Print(L["Journal des erreurs vidé."]) return end
    if #ns.Errors == 0 then ns.Print(L["Aucune erreur enregistrée cette session."]) return end
    ns.Print(string.format(L["%d erreur(s) cette session (les plus récentes en bas) :"], #ns.Errors))
    for i = math.max(1, #ns.Errors - 9), #ns.Errors do
        local e = ns.Errors[i]
        ns.Print(string.format("|cffff5555%s|r ×%d : %s", e.context, e.count, e.msg))
    end
    ns.Print(L["/balg erreurs effacer – vider le journal"])
end

-- Estimation grossière de la taille du fichier de sauvegarde (octets)
local function CountTable(t, depth)
    local n = 0
    for k, v in pairs(t) do
        n = n + 12 + (type(k) == "string" and #k or 6)
        if type(v) == "table" then n = n + CountTable(v, depth + 1)
        elseif type(v) == "string" then n = n + #v
        else n = n + 8 end
    end
    return n
end
function G.EstimateSize()
    return CountTable(BalgourdeDB, 0)
end

function G.ShowSize()
    local db = BalgourdeDB
    local function sz(t) return CountTable(t or {}, 0) / 1e3 end
    local mobs, zones = 0, 0
    for _ in pairs(db.mobs) do mobs = mobs + 1 end
    for _ in pairs(db.zones) do zones = zones + 1 end
    local items, days = 0, 0
    for _, realm in pairs(db.history) do
        for _, mkt in pairs(realm) do
            for _, h in pairs(mkt) do
                items = items + 1
                for _ in pairs(h) do days = days + 1 end
            end
        end
    end
    ns.Print(string.format(L["Monstres : %d (%d zones) – %.0f ko"], mobs, zones, sz(db.mobs) + sz(db.zones)))
    ns.Print(string.format(L["Prix actuels : %.0f ko – noms d'objets : %.0f ko"], sz(db.prices), sz(db.itemNames)))
    ns.Print(string.format(L["Historique : %d objets suivis, %d relevés – %.0f ko"], items, days, sz(db.history)))
    ns.Print(string.format(L["Ventes, désenchantements, partage : %.0f ko"],
        sz(db.sales) + sz(db.disenchant) + sz(db.disenchantShared) + sz(db.senders)))
    ns.Print(string.format(L["Total estimé : %.1f Mo"], G.EstimateSize() / 1e6))
end
