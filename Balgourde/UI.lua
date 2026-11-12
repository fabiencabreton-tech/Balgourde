-- Balgourde - Interface : fenêtre principale, bouton sur la cible, infobulles, commandes
local _, ns = ...
local L = ns.L

ns.UI = {}
local UI = ns.UI
local AH = ns.Auction
local Safe = ns.Safe

local ROW_H = 18
local MIN_W, MIN_H, MAX_W, MAX_H = 620, 320, 1100, 1000
-- colonnes à largeur fixe, alignées à droite (le nom prend le reste)
local COL_RATE, COL_VENDOR, COL_AH, COL_BEST = 60, 80, 85, 85

local f, scroll, content, statusText, titleText, emptyText, searchBox
local rows = {}
local mode = "zone"     -- "zone" | "mob" | "bags" | "prices" | "item"
local currentItem, previousMode  -- fiche « prix » d'un objet
local priceMarket                -- marché affiché dans l'onglet Prix HV
local priceSort = "price"        -- "price" | "trend" | "qty" | "name"
local MAX_PRICE_ROWS = 150
local currentMob
local tabButtons = {}
local pendingItems = false

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------
local function ItemName(itemID)
    local name, _, quality = ns.GetItemInfo(itemID)
    if not name then pendingItems = true end
    return name, quality
end

local function SearchText()
    local t = searchBox and searchBox:GetText() or ""
    t = t:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return t ~= "" and t or nil
end

local function Matches(text, search)
    return text and text:lower():find(search, 1, true) ~= nil
end

-- Filtre objet : gris masqués, recherche
local function KeepItem(itemID, search, mobMatched)
    local name, quality = ItemName(itemID)
    if BalgourdeDB.settings.hideGrey and quality == 0 then return false end
    if search and not mobMatched and not Matches(name, search) then return false end
    return true
end

---------------------------------------------------------------------------
-- Lignes
---------------------------------------------------------------------------
local function GetRow(i)
    local row = rows[i]
    if row then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", content, "RIGHT")
        return row
    end
    row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", content, "RIGHT")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 14, 0)

    local function col(width)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetWidth(width); fs:SetJustifyH("RIGHT"); fs:SetWordWrap(false)
        return fs
    end
    row.best = col(COL_BEST);     row.best:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.ah = col(COL_AH);         row.ah:SetPoint("RIGHT", row.best, "LEFT", -4, 0)
    row.vendor = col(COL_VENDOR); row.vendor:SetPoint("RIGHT", row.ah, "LEFT", -4, 0)
    row.rate = col(COL_RATE);     row.rate:SetPoint("RIGHT", row.vendor, "LEFT", -4, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row.rate, "LEFT", -4, 0)

    row.bar = row:CreateTexture(nil, "BORDER")
    row.bar:SetHeight(10)
    row.bar:SetColorTexture(0.83, 0.63, 0.09, 0.55)
    row.bar:Hide()

    row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.header:SetJustifyH("LEFT"); row.header:SetWordWrap(false)
    row.header:SetPoint("LEFT", 2, 0)
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetJustifyH("RIGHT")
    row.value:SetPoint("RIGHT", -4, 0)
    row.header:SetPoint("RIGHT", row.value, "LEFT", -8, 0)

    row:SetScript("OnEnter", function(self)
        if self.itemID then
            self.bg:SetColorTexture(1, 1, 1, 0.08)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemID)
            if self.info then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(self.info, 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        elseif self.npcID then
            self.bg:SetColorTexture(1, 0.8, 0, 0.08)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if mode == "zone" then
                GameTooltip:AddLine(L["Clic : replier / déplier"], 1, 1, 1)
                GameTooltip:AddLine(L["Clic droit : fiche du monstre"], 1, 1, 1)
            end
            if self.info then GameTooltip:AddLine(self.info, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button)
        if self.itemID then
            local _, link = ns.GetItemInfo(self.itemID)
            local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
            if link and insert and IsModifiedClick("CHATLINK") then
                insert(link)
            elseif not IsModifiedClick() and mode ~= "item" then
                UI.ShowItem(self.itemID)
            end
        elseif self.npcID and mode == "zone" then
            if button == "RightButton" or IsShiftKeyDown() then
                UI.ShowMob(self.npcID)
            else
                local c = BalgourdeDB.settings.collapsed
                c[self.npcID] = not c[self.npcID] or nil
                UI.Refresh()
            end
        end
    end)
    rows[i] = row
    return row
end

local COLS = { "name", "rate", "vendor", "ah", "best" }

local function ResetRow(row)
    row.itemID, row.npcID, row.info = nil, nil, nil
    row.icon:Hide(); row.header:Hide(); row.value:Hide(); row.bar:Hide()
    for _, k in ipairs(COLS) do row[k]:SetText(""); row[k]:Show() end
    row.name:SetTextColor(1, 1, 1)
    row:Show()
end

local function SetHeaderRow(row, text, npcID, valueText, small)
    ResetRow(row)
    for _, k in ipairs(COLS) do row[k]:Hide() end
    row.header:SetFontObject(small and "GameFontDisableSmall" or "GameFontNormal")
    row.header:SetText(text)
    row.header:Show()
    row.value:SetText(valueText or "")
    row.value:Show()
    row.npcID = npcID
end

local function BestLabel(best)
    if not best then return "|cff666666?|r" end
    if best.market == "Vendor" then return L["|cffaaaaaaMarchand|r"] end
    if best.market == "Disenchant" then return L["|cffa335eeDésenchanter|r"] end
    local color = best.market == "Neutral" and "|cffffcc00" or (best.market == "Horde" and "|cffff5555" or "|cff55aaff")
    local label = best.market == "Neutral" and L["HV Neutre"] or (L["HV "] .. best.market)
    return color .. label .. "|r"
end

local function SetItemRow(row, itemID, rateText, info)
    ResetRow(row)
    row.itemID, row.info = itemID, info
    local name, quality = ItemName(itemID)
    local icon = select(5, ns.GetItemInfoInstant(itemID))
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    row.icon:SetTexture(icon or 134400)
    row.icon:Show()
    row.name:SetText(name or (L["Objet #"] .. itemID))
    if c then row.name:SetTextColor(c.r, c.g, c.b) end
    row.rate:SetText(rateText or "")

    local best, markets = AH.GetBest(itemID)
    local vendor, bestAH
    for _, m in ipairs(markets) do
        if m.market == "Vendor" then vendor = m.net elseif m.market ~= "Disenchant" and not bestAH and not m.stale then bestAH = m end
    end
    row.vendor:SetText(ns.Money(vendor))
    if bestAH then
        local txt = ns.Money(bestAH.net)
        -- tendance par rapport à la moyenne 7 jours : vert = bon moment pour vendre
        if bestAH.avg7 and bestAH.avg7 > 0 then
            local r = bestAH.gross / bestAH.avg7
            if r >= 1.10 then txt = "|cff00ff00+|r " .. txt elseif r <= 0.90 then txt = "|cffff5555-|r " .. txt end
        end
        row.ah:SetText(txt)
    else
        row.ah:SetText("|cff666666-|r")
    end
    row.best:SetText(BestLabel(best))
end

-- Lignes d'information sur la vente d'un objet (infobulles)
function UI.SaleInfoLines(itemID)
    local lines = {}
    local bestAH = AH.GetBestAH(itemID)
    if bestAH then
        if bestAH.qty then
            lines[#lines + 1] = string.format(L["%s : %d en vente (%d annonce%s)"], bestAH.label, bestAH.qty,
                bestAH.n or 0, (bestAH.n or 0) > 1 and "s" or "")
        end
        local st = AH.GetStats(itemID, bestAH.market)
        if st.low14 and st.days >= 2 then
            lines[#lines + 1] = string.format(L["14 j : de %s à %s"], ns.Money(st.low14), ns.Money(st.high14))
        end
        if bestAH.avg7 then
            local pct = (bestAH.gross / bestAH.avg7 - 1) * 100
            lines[#lines + 1] = string.format(L["Moyenne 7 j : %s (%s%.0f %%)"], ns.Money(bestAH.avg7),
                pct >= 0 and "+" or "", pct)
        end
    end
    local sold, expired = AH.GetSales(itemID)
    if sold then
        local total = sold + expired
        local line = string.format(L["Vos ventes : %d vendu%s, %d expiré%s"], sold, sold > 1 and "s" or "",
            expired, expired > 1 and "s" or "")
        if total >= AH.MIN_SALES then
            line = line .. string.format(L[" (%d %% vendus)"], math.floor(sold / total * 100 + 0.5))
            if bestAH and bestAH.expected then
                line = line .. L[" – gain espéré "] .. ns.Money(math.max(0, bestAH.expected))
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end

---------------------------------------------------------------------------
-- Contenu
---------------------------------------------------------------------------
local function SortDrops(drops)
    local asc = BalgourdeDB.settings.sortAsc
    table.sort(drops, function(a, b)
        -- objets de quête puis taux inconnus en fin de liste
        if (a.quest or false) ~= (b.quest or false) then return not a.quest end
        local ra, rb = a.rate, b.rate
        if (ra == nil) ~= (rb == nil) then return ra ~= nil end
        if ra == rb or ra == nil then return a.itemID < b.itemID end
        if asc then return ra < rb else return ra > rb end
    end)
    return drops
end

local function DropInfo(d)
    if d.quest then return L["Objet de quête : ne tombe que si vous avez la quête, taux non significatif."] end
    if d.source == "base" then return L["Taux issu de la base de départ (Data\\Seed.lua)."] end
    local what = d.pickpocket and L["poches"] or "kills"
    local txt = string.format(L["Observé %d fois sur %d %s."], d.count or 0, d.kills or 0, what)
    if not d.reliable then
        txt = txt .. string.format(L[" Taux peu fiable (moins de %d %s)."], ns.ReliableKills(), what)
    end
    return txt
end

local function LevelText(minL, maxL)
    if minL == -1 then return " (??)" end
    if not minL then return "" end
    return (minL == maxL) and (L[" (niv. "] .. minL .. ")") or (L[" (niv. "] .. minL .. "-" .. maxL .. ")")
end

local function ValueText(npcID)
    local v, reliable, skin = ns.GetMobValue(npcID)
    if not v then return "" end
    if skin then return (reliable and "" or "|cff888888~|r") .. ns.Money(v) .. L[" / kill |cffc79c6e+cuir|r"] end
    local txt = ns.Money(v) .. " / kill"
    return reliable and txt or ("|cff888888~|r" .. txt)
end

-- Ajoute les lignes d'un monstre. Retourne n (nb de lignes) et true si quelque chose a été affiché
local function BuildMobRows(npcID, n, search, inZone)
    local name, minL, maxL, kills, _, sharedKills = ns.GetMobInfo(npcID)
    local mobMatched = not search or Matches(name, search)

    local drops = {}
    for _, d in ipairs(ns.GetMobDrops(npcID)) do
        if KeepItem(d.itemID, search, mobMatched) then drops[#drops + 1] = d end
    end
    local pp, ppCount, ppMoney = ns.GetMobPickpocket(npcID)
    local ppRows = {}
    for _, d in ipairs(pp or {}) do
        if KeepItem(d.itemID, search, mobMatched) then ppRows[#ppRows + 1] = d end
    end

    if inZone then
        if search and not mobMatched and #drops == 0 and #ppRows == 0 then return n, false end
        if BalgourdeDB.settings.hideEmpty and #drops == 0 and #ppRows == 0 then return n, false end
    end

    local collapsed = inZone and BalgourdeDB.settings.collapsed[npcID]
    local prefix = inZone and (collapsed and "|cff888888[+]|r " or "|cff888888[–]|r ") or ""
    n = n + 1
    local row = GetRow(n)
    SetHeaderRow(row, string.format("%s%s%s  |cff999999– %d kill%s|r", prefix, name, LevelText(minL, maxL),
        kills, kills > 1 and "s" or ""), npcID, ValueText(npcID))
    if sharedKills and sharedKills > 0 then
        row.info = string.format(L["Dont %d kill%s reçu%s de la guilde / du groupe."], sharedKills,
            sharedKills > 1 and "s" or "", sharedKills > 1 and "s" or "")
    end
    if collapsed then return n, true end

    if #drops == 0 then
        n = n + 1
        local r = GetRow(n)
        ResetRow(r)
        r.name:SetText(L["|cff888888Aucun loot connu pour l'instant|r"])
    end
    for _, d in ipairs(SortDrops(drops)) do
        n = n + 1
        SetItemRow(GetRow(n), d.itemID, ns.RateText(d), DropInfo(d))
    end

    if #ppRows > 0 then
        n = n + 1
        SetHeaderRow(GetRow(n), string.format(L["    Vol à la tire – %d poche%s"], ppCount, ppCount > 1 and "s" or ""),
            nil, ppMoney > 0 and (L["or moyen "] .. ns.Money(ppMoney)) or "", true)
        for _, d in ipairs(SortDrops(ppRows)) do
            n = n + 1
            SetItemRow(GetRow(n), d.itemID, ns.RateText(d), DropInfo(d))
        end
    end
    -- Dépeçage
    local Sk = ns.Skinning
    if BalgourdeDB.settings.tooltipSkin and Sk.IsSkinnable(npcID) and (not search or mobMatched) then
        local out, source, skinN = Sk.GetOutcomes(npcID)
        if out and #out > 0 then
            local req = Sk.RequiredSkill(maxL ~= -1 and maxL or nil)
            local skill = Sk.PlayerSkill()
            local reqTxt = req and (L["compétence "] .. req .. (skill and (skill >= req and L[" |cff00ff00(ok)|r"]
                or L[" |cffff5555(vous : "] .. skill .. ")|r") or "")) or ""
            local value = Sk.GetValue(npcID)
            n = n + 1
            SetHeaderRow(GetRow(n), L["    Dépeçage – "] .. (source == "obs"
                and string.format(L["%d dépeçage%s"], skinN, skinN > 1 and "s" or "") or L["cuirs possibles"]) .. "  |cff999999" .. reqTxt .. "|r",
                nil, value and ("~" .. ns.Money(value) .. L[" / dépeçage"]) or "", true)
            for _, o in ipairs(out) do
                n = n + 1
                local txt = o.prob and ns.Percent(o.prob) or L["|cff888888possible|r"]
                local info = o.prob and string.format(L["Obtenu sur %d dépeçage(s) sur %d, quantité moyenne %.1f."],
                    math.floor(o.prob * skinN + 0.5), skinN, o.avg)
                    or L["D'après le niveau du monstre (tables Classic). Les vrais taux apparaissent après vos dépeçages."]
                SetItemRow(GetRow(n), o.itemID, txt, info)
            end
        end
    end
    return n, true
end

local function BuildZone(search)
    local mapID, zoneName = ns.GetCurrentZone()
    titleText:SetText("Balgourde – " .. (zoneName or "?"))
    local mobs = ns.GetZoneMobs(mapID)
    local byValue = BalgourdeDB.settings.mobSort == "value"
    local values = {}
    if byValue then for _, id in ipairs(mobs) do values[id] = ns.GetMobValue(id) or -1 end end
    table.sort(mobs, function(a, b)
        if byValue and values[a] ~= values[b] then return values[a] > values[b] end
        local na, la = ns.GetMobInfo(a)
        local nb, lb = ns.GetMobInfo(b)
        la, lb = la or 0, lb or 0
        if la ~= lb then return la < lb end
        return na < nb
    end)
    local n = 0
    for _, npcID in ipairs(mobs) do n = BuildMobRows(npcID, n, search, true) end
    if search and n == 0 then return 0, L["Aucun résultat pour « "] .. search .. L[" »."] end
    return n, L["Aucun monstre connu dans cette zone.\nCiblez, survolez ou tuez des monstres : Balgourde les enregistre automatiquement."]
end

local function BuildMob(search)
    if not currentMob then return 0, L["Aucun monstre sélectionné.\nCiblez un monstre puis cliquez sur « Loots »."] end
    titleText:SetText("Balgourde – " .. ns.GetMobInfo(currentMob))
    return (BuildMobRows(currentMob, 0, search, false)), nil
end

local function BuildBags(search)
    titleText:SetText(L["Balgourde – Mes objets"])
    local items, order = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (ns.GetContainerNumSlots(bag) or 0) do
            local itemID, count, _, bound = ns.GetContainerItem(bag, slot)
            if itemID and KeepItem(itemID, search, false) then
                if not items[itemID] then
                    items[itemID] = { count = 0, bound = ns.IsBound(bag, slot, bound) }
                    order[#order + 1] = itemID
                end
                items[itemID].count = items[itemID].count + (count or 1)
            end
        end
    end
    -- valeur totale de chaque pile, calculée une seule fois
    for _, itemID in ipairs(order) do
        local info = items[itemID]
        if info.bound then
            -- objet lié : marchand ou désenchantement seulement
            info.unit = select(11, ns.GetItemInfo(itemID)) or 0
            info.boundBest = info.unit > 0 and "Vendor" or nil
            local de = ns.Disenchant.InBest() and ns.Disenchant.GetValue(itemID)
            if de and de > info.unit then info.unit, info.boundBest = math.floor(de), "Disenchant" end
        else
            local best = AH.GetBest(itemID)
            info.unit = best and best.net or 0
        end
        info.value = info.unit * info.count
    end
    table.sort(order, function(a, b) return items[a].value > items[b].value end)

    local n, total = 0, 0
    for _, itemID in ipairs(order) do
        local info = items[itemID]
        n = n + 1
        local row = GetRow(n)
        local infoLines = {}
        if info.value > 0 then infoLines[1] = L["Valeur de la pile : "] .. ns.Money(info.value) end
        for _, l in ipairs(UI.SaleInfoLines(itemID)) do infoLines[#infoLines + 1] = l end
        SetItemRow(row, itemID, "×" .. info.count, #infoLines > 0 and table.concat(infoLines, "\n") or nil)
        if info.bound then
            row.ah:SetText(L["|cff888888lié|r"])
            row.best:SetText(info.boundBest and BestLabel({ market = info.boundBest }) or "|cff666666-|r")
        end
        total = total + info.value
    end
    if n > 0 then
        n = n + 1
        SetHeaderRow(GetRow(n), L["Valeur totale estimée (meilleur marché, net)"], nil, ns.Money(total))
    end
    return n, search and (L["Aucun objet pour « "] .. search .. L[" »."]) or L["Vos sacs sont vides."]
end

---------------------------------------------------------------------------
-- Onglet « Prix HV » et fiche de prix d'un objet
---------------------------------------------------------------------------
local function TrendText(trend)
    if not trend then return "|cff666666-|r" end
    local pct = trend * 100
    if pct >= 5 then return string.format("|cff00ff00+%.0f %%|r", pct) end
    if pct <= -5 then return string.format("|cffff5555%.0f %%|r", pct) end
    return string.format("|cffaaaaaa%+.0f %%|r", pct)
end

-- Statistiques légères pour la liste (aucune requête d'objet au serveur)
local function QuickStats(itemID, mkt)
    local realm = BalgourdeDB.prices[GetRealmName() or "?"]
    local e = realm and realm[mkt] and realm[mkt][itemID]
    local cur = e and AH.SellPrice(e)
    local avg7 = AH.GetAverage(itemID, mkt, 7)
    return { current = cur, qty = e and e.qty, avg7 = avg7,
             trend = (cur and avg7 and avg7 > 0) and (cur / avg7 - 1) or nil }
end

local function BagItemSet()
    local set = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (ns.GetContainerNumSlots(bag) or 0) do
            local itemID = ns.GetContainerItem(bag, slot)
            if itemID then set[itemID] = true end
        end
    end
    return set
end

local function BuildPrices(search)
    priceMarket = priceMarket or AH.DefaultMarket()
    titleText:SetText(L["Balgourde – Prix "] .. AH.MarketLabel(priceMarket))
    local items = AH.ListItems(priceMarket)
    if #items == 0 then
        return 0, L["Aucun prix enregistré pour ce marché.\nParlez à un commissaire-priseur puis cliquez sur « Scanner l'HV »."]
    end
    local mine = BalgourdeDB.settings.onlyMine and BagItemSet()
    local list = {}
    for _, id in ipairs(items) do
        local name = BalgourdeDB.itemNames[id]
        if (not mine or mine[id]) and (not search or Matches(name, search)) then
            local st = QuickStats(id, priceMarket)
            st.itemID, st.name = id, name or ""
            list[#list + 1] = st
        end
    end
    table.sort(list, function(a, b)
        if priceSort == "name" then
            if (a.name == "") ~= (b.name == "") then return a.name ~= "" end
            return a.name < b.name
        elseif priceSort == "trend" then
            return (a.trend or -999) > (b.trend or -999)
        elseif priceSort == "qty" then
            return (a.qty or 0) > (b.qty or 0)
        end
        return (a.current or 0) > (b.current or 0)
    end)
    local n = 0
    for i = 1, math.min(MAX_PRICE_ROWS, #list) do
        local st = list[i]
        n = n + 1
        local row = GetRow(n)
        SetItemRow(row, st.itemID, st.qty and tostring(st.qty) or "|cff666666-|r",
            L["Clic : statistiques détaillées et historique"])
        row.vendor:SetText(ns.Money(st.current))
        row.ah:SetText(st.avg7 and ns.Money(st.avg7) or "|cff666666-|r")
        row.best:SetText(TrendText(st.trend))
    end
    if #list > MAX_PRICE_ROWS then
        n = n + 1
        SetHeaderRow(GetRow(n), string.format(L["%d objets de plus : affinez la recherche"], #list - MAX_PRICE_ROWS),
            nil, nil, true)
    end
    return n, search and (L["Aucun objet pour « "] .. search .. L[" » sur ce marché."]) or L["Aucun objet."]
end

local WEEKDAYS = { "dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam." }
local function DayLabel(day)
    local t = day * 86400 + 43200
    return L[WEEKDAYS[tonumber(date("%w", t)) + 1]] .. " " .. date("%d/%m", t)
end

local function BuildItem()
    local itemID = currentItem
    if not itemID then return 0, L["Aucun objet sélectionné."] end
    priceMarket = priceMarket or AH.DefaultMarket()
    local name = ItemName(itemID) or AH.ItemName(itemID) or (L["Objet #"] .. itemID)
    titleText:SetText("Balgourde – " .. name)
    local st = AH.GetStats(itemID, priceMarket)
    local n = 0
    local function Info(label, value)
        n = n + 1
        SetHeaderRow(GetRow(n), "   " .. label, nil, value or "|cff666666-|r", true)
    end

    n = n + 1
    SetItemRow(GetRow(n), itemID, "", nil)
    GetRow(n).best:SetText(BestLabel((AH.GetBest(itemID))))

    n = n + 1
    SetHeaderRow(GetRow(n), L["Statistiques – "] .. AH.MarketLabel(priceMarket), nil,
        st.age and (L["relevé il y a "] .. (st.age < 3600 and (math.floor(st.age / 60) .. " min")
            or st.age < 86400 and (math.floor(st.age / 3600) .. " h") or (math.floor(st.age / 86400) .. L[" j"]))) or "")
    Info(L["Valeur de marché actuelle"], st.current and ns.Money(st.current))
    Info(L["Plus bas actuel"], st.min and ns.Money(st.min))
    Info(L["En vente"], st.qty and string.format(L["%d exemplaire%s (%d annonce%s)"], st.qty, st.qty > 1 and "s" or "",
        st.n or 0, (st.n or 0) > 1 and "s" or ""))
    Info(L["Moyenne 7 jours"], st.avg7 and (ns.Money(st.avg7) .. "  " .. TrendText(st.trend)))
    Info(L["Moyenne 14 jours"], st.avg14 and ns.Money(st.avg14))
    Info(L["Plus bas / plus haut sur 14 jours"], st.low14 and (ns.Money(st.low14) .. L["  à  "] .. ns.Money(st.high14)))
    Info(L["Quantité moyenne en vente"], st.qtyAvg and string.format("%.0f", st.qtyAvg))

    n = n + 1
    SetHeaderRow(GetRow(n), L["Vente"], nil, "")
    local sell = select(11, ns.GetItemInfo(itemID))
    Info(L["Prix marchand"], sell and sell > 0 and ns.Money(sell) or nil)
    for _, m in ipairs(AH.GetMarkets(itemID)) do
        if m.market ~= "Vendor" then
            local txt = ns.Money(m.net) .. " net"
            if m.expected then txt = txt .. L["  |cff888888(espéré "] .. ns.Money(math.max(0, m.expected)) .. ")|r" end
            if m.stale then txt = txt .. L["  |cffff5555(prix de plus de 7 j, ignoré)|r"] end
            Info(L["Gain à l'"] .. m.label, txt)
            local cut, cutLearned = AH.Cut(m.market)
            local dep, depLearned = AH.Deposit(m.market)
            Info("   " .. string.format(L["Commission %.0f %% · dépôt %.0f %% du prix marchand"], cut * 100, dep * 100),
                (cutLearned and depLearned) and L["|cff00ff00lus dans vos ventes|r"]
                or (cutLearned or depLearned) and L["|cffffaa00en partie estimés|r"] or L["|cff888888estimés|r"])
        end
    end
    if st.sold then
        local total = st.sold + st.expired
        Info(L["Vos mises en vente"], string.format(L["%d vendu%s / %d expiré%s (%d %%)"], st.sold, st.sold > 1 and "s" or "",
            st.expired, st.expired > 1 and "s" or "", total > 0 and math.floor(st.sold / total * 100 + 0.5) or 0))
        Info(L["Prix moyen encaissé (vos ventes)"], st.avgSale and ns.Money(st.avgSale))
    else
        Info(L["Vos mises en vente"], L["|cff666666aucune relevée (courrier HV)|r"])
    end

    local deValue, deOut, deSource, deN = ns.Disenchant.GetValue(itemID)
    if deOut then
        n = n + 1
        local origin = deSource == "obs" and string.format(L["vos %d désenchantements"], deN) or L["table Classic"]
        SetHeaderRow(GetRow(n), L["Désenchantement |cff888888("] .. origin .. ")|r", nil,
            deValue and (L["valeur espérée ~"] .. ns.Money(deValue)) or L["prix des composants inconnus"])
        for _, o in ipairs(deOut) do
            n = n + 1
            local row = GetRow(n)
            SetItemRow(row, o.itemID, ns.Percent(o.prob), L["Chance · quantité · prix unitaire · valeur moyenne"])
            row.vendor:SetText(ns.Disenchant.QtyText(o))
            row.ah:SetText(o.price and o.price > 0 and ns.Money(o.price) or "|cff666666?|r")
            row.best:SetText(o.value and o.value > 0 and ns.Money(o.value) or "|cff666666-|r")
        end
    end

    n = n + 1
    SetHeaderRow(GetRow(n), L["Historique – "] .. AH.MarketLabel(priceMarket), nil,
        L["|cff999999en vente · plus bas · marché · variation|r"])
    local hist = st.history
    if #hist == 0 then
        n = n + 1
        local r = GetRow(n); ResetRow(r)
        r.name:SetText(L["|cff888888Pas encore d'historique : un scan complet par jour le construit.|r"])
        return n
    end
    local maxM = 0
    for _, d in ipairs(hist) do maxM = math.max(maxM, d.m or 0) end
    local barMax = math.max(40, (content:GetWidth() or 500) - (COL_RATE + COL_VENDOR + COL_AH + COL_BEST + 30) - 110)
    for i = #hist, 1, -1 do
        local d, prev = hist[i], hist[i - 1]
        n = n + 1
        local row = GetRow(n)
        ResetRow(row)
        row.name:SetText(DayLabel(d.day))
        row.rate:SetText(d.q and tostring(d.q) or "-")
        row.vendor:SetText(ns.Money(d.l))
        row.ah:SetText(ns.Money(d.m))
        row.best:SetText(prev and prev.m and prev.m > 0 and TrendText(d.m / prev.m - 1) or "")
        if maxM > 0 and d.m then
            row.bar:ClearAllPoints()
            row.bar:SetPoint("LEFT", row, "LEFT", 110, 0)
            row.bar:SetWidth(math.max(2, barMax * d.m / maxM))
            row.bar:Show()
        end
    end
    return n
end

function UI.ShowItem(itemID)
    if not f then return end
    AH.Watch(itemID)
    if mode ~= "item" then previousMode = mode end
    currentItem = itemID
    if mode ~= "prices" and mode ~= "item" then priceMarket = nil end
    mode = "item"
    f:Show()
    UI.Refresh()
end

function UI.Refresh()
    if not f or not f:IsShown() then return end
    pendingItems = false
    local search = SearchText()
    local n, emptyMsg
    if mode == "zone" then n, emptyMsg = BuildZone(search)
    elseif mode == "mob" then n, emptyMsg = BuildMob(search)
    elseif mode == "prices" then n, emptyMsg = BuildPrices(search)
    elseif mode == "item" then n, emptyMsg = BuildItem()
    else n, emptyMsg = BuildBags(search) end

    for i = n + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, n * ROW_H))
    emptyText:SetText(n == 0 and (emptyMsg or "") or "")

    local s = BalgourdeDB.settings
    local priceMode = mode == "prices" or mode == "item"
    if mode == "prices" then
        f.colName:SetText(L["Objet"]); f.colRate:SetText(L["En vente"]); f.colVendor:SetText(L["Actuel"])
        f.colAH:SetText(L["Moy. 7 j"]); f.colBest:SetText(L["Tendance"])
    elseif mode == "item" then
        f.colName:SetText(L["Jour"]); f.colRate:SetText(L["En vente"]); f.colVendor:SetText(L["Plus bas"])
        f.colAH:SetText(L["Marché"]); f.colBest:SetText(L["Variation"])
    else
        f.colName:SetText(L["Objet"]); f.colRate:SetText(mode == "bags" and L["Qté"] or L["Taux"])
        f.colVendor:SetText(L["Marchand"]); f.colAH:SetText(L["HV (net)"]); f.colBest:SetText(L["Meilleur"])
    end
    f.sortBtn:SetShown(mode ~= "bags")
    if mode == "prices" then
        local labels = { price = L["Tri : prix"], trend = L["Tri : tendance"], qty = L["Tri : quantité"], name = L["Tri : nom"] }
        f.sortBtn:SetText(labels[priceSort])
    elseif mode == "item" then
        f.sortBtn:SetText(L["« Retour"])
    else
        f.sortBtn:SetText(s.sortAsc and L["Taux croissant"] or L["Taux décroissant"])
    end
    f.mobSortBtn:SetShown(mode == "zone" or priceMode)
    if priceMode then
        f.mobSortBtn:SetText(AH.MarketLabel(priceMarket or AH.DefaultMarket()))
    else
        f.mobSortBtn:SetText(s.mobSort == "value" and L["Tri : rentabilité"] or L["Tri : niveau"])
    end
    f.hideEmpty:SetShown(mode == "zone")
    f.hideGrey:SetShown(not priceMode)
    f.onlyMine:SetShown(mode == "prices")
    f.onlyMine:SetChecked(s.onlyMine)
    searchBox:SetShown(mode ~= "item")
    f.hideGrey:SetChecked(s.hideGrey)
    f.hideEmpty:SetChecked(s.hideEmpty)
    f.scanBtn:SetText(AH.IsScanning() and L["Scan en cours…"] or (AH.IsOpen() and L["Scanner l'HV"] or L["Scanner l'HV*"]))
    for k, b in pairs(tabButtons) do
        if k == mode then b:LockHighlight() else b:UnlockHighlight() end
    end
end

---------------------------------------------------------------------------
-- Fenêtre
---------------------------------------------------------------------------
local function Checkbox(parent, label, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    local text = cb.Text or cb.text
    if not text then
        text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    text:SetFontObject("GameFontHighlightSmall")
    text:SetText(label)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return cb
end

local function SaveGeometry()
    local p, _, rp, x, y = f:GetPoint()
    BalgourdeDB.settings.pos = { p, rp, x, y }
    BalgourdeDB.settings.size = { f:GetWidth(), f:GetHeight() }
end

local function CreateMainFrame()
    local s = BalgourdeDB.settings
    f = CreateFrame("Frame", "BalgourdeFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(s.size and s.size[1] or 640, s.size and s.size[2] or 480)
    f:SetPoint("CENTER", 250, 0)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    else
        f:SetMinResize(MIN_W, MIN_H); f:SetMaxResize(MAX_W, MAX_H)
    end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveGeometry() end)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "BalgourdeFrame") -- Échap ferme la fenêtre
    f:Hide()
    if s.pos then f:ClearAllPoints(); f:SetPoint(s.pos[1], UIParent, s.pos[2], s.pos[3], s.pos[4]) end

    titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 16, -14)
    titleText:SetPoint("RIGHT", -70, 0)
    titleText:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local gear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    gear:SetSize(60, 20)
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
    gear:SetText("Options")
    gear:SetScript("OnClick", function() if ns.Options then ns.Options.Open() end end)

    -- Ligne 1 : onglets + scan
    local function Tab(key, label, x, width)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetPoint("TOPLEFT", x, -38)
        b:SetText(label)
        b:SetScript("OnClick", function()
            if key == "mob" then
                local npcID = ns.NpcIDFromGUID(Safe(UnitGUID("target")))
                if npcID then currentMob = npcID end
            end
            mode = key
            UI.Refresh()
        end)
        tabButtons[key] = b
    end
    Tab("zone", "Zone", 14, 80)
    Tab("mob", L["Monstre"], 96, 80)
    Tab("bags", L["Mes objets"], 178, 95)
    Tab("prices", L["Prix HV"], 275, 80)

    f.scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.scanBtn:SetSize(120, 22)
    f.scanBtn:SetPoint("TOPRIGHT", -16, -38)
    f.scanBtn:SetScript("OnClick", AH.StartScan)
    f.scanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Scanner l'Hôtel des ventes"])
        GameTooltip:AddLine(AH.IsOpen() and L["Relève les prix de tous les objets de cet HV."] or L["* Parlez d'abord à un commissaire-priseur."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.scanBtn:SetScript("OnLeave", GameTooltip_Hide)

    f.mobSortBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.mobSortBtn:SetSize(120, 22)
    f.mobSortBtn:SetPoint("RIGHT", f.scanBtn, "LEFT", -4, 0)
    f.mobSortBtn:SetScript("OnClick", function()
        if mode == "prices" or mode == "item" then
            -- change de marché (HV de votre faction / HV neutre)
            local list = AH.ListMarkets()
            if #list == 0 then return end
            local cur = priceMarket or AH.DefaultMarket()
            local idx = 1
            for i, m in ipairs(list) do if m == cur then idx = i % #list + 1 end end
            priceMarket = list[idx]
        else
            local s2 = BalgourdeDB.settings
            s2.mobSort = s2.mobSort == "value" and "level" or "value"
        end
        UI.Refresh()
    end)
    f.mobSortBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if mode == "prices" or mode == "item" then
            GameTooltip:AddLine(L["Marché affiché"])
            GameTooltip:AddLine(L["Clic : passer de l'HV de votre faction à l'HV neutre."], 1, 1, 1, true)
        else
            GameTooltip:AddLine(L["Ordre des monstres"])
            GameTooltip:AddLine(L["Rentabilité = or moyen ramassé + objets × taux × meilleur prix (hors quête)."], 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    f.mobSortBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Ligne 2 : recherche + filtres + tri des objets
    searchBox = CreateFrame("EditBox", "BalgourdeSearchBox", f, "InputBoxTemplate")
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("TOPLEFT", 22, -66)
    searchBox:SetAutoFocus(false)
    searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchBox.placeholder:SetPoint("LEFT", 2, 0)
    searchBox.placeholder:SetText(L["Rechercher…"])
    searchBox:SetScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "")
        UI.Refresh()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    f.hideGrey = Checkbox(f, L["Cacher gris"], function(v) BalgourdeDB.settings.hideGrey = v; UI.Refresh() end)
    f.hideGrey:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    f.hideEmpty = Checkbox(f, L["Cacher sans loot"], function(v) BalgourdeDB.settings.hideEmpty = v; UI.Refresh() end)
    f.hideEmpty:SetPoint("LEFT", f.hideGrey, "RIGHT", 72, 0)
    f.onlyMine = Checkbox(f, L["Seulement mes objets"], function(v) BalgourdeDB.settings.onlyMine = v; UI.Refresh() end)
    f.onlyMine:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)

    f.sortBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.sortBtn:SetSize(120, 22)
    f.sortBtn:SetPoint("TOPRIGHT", -16, -64)
    f.sortBtn:SetScript("OnClick", function()
        if mode == "prices" then
            local nextSort = { price = "trend", trend = "qty", qty = "name", name = "price" }
            priceSort = nextSort[priceSort]
        elseif mode == "item" then
            mode = previousMode or "prices"
        else
            BalgourdeDB.settings.sortAsc = not BalgourdeDB.settings.sortAsc
        end
        UI.Refresh()
    end)

    -- En-têtes de colonnes (mêmes ancrages à droite que les lignes)
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetHeight(16)
    hdr:SetPoint("TOPLEFT", 16, -92)
    hdr:SetPoint("RIGHT", f, "RIGHT", -34, 0)
    local function H(text, width)
        local fs = hdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetWidth(width); fs:SetJustifyH("RIGHT"); fs:SetText(text)
        return fs
    end
    f.colBest = H(L["Meilleur"], COL_BEST);       f.colBest:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)
    f.colAH = H(L["HV (net)"], COL_AH);           f.colAH:SetPoint("RIGHT", f.colBest, "LEFT", -4, 0)
    f.colVendor = H(L["Marchand"], COL_VENDOR);   f.colVendor:SetPoint("RIGHT", f.colAH, "LEFT", -4, 0)
    f.colRate = H(L["Taux"], COL_RATE);           f.colRate:SetPoint("RIGHT", f.colVendor, "LEFT", -4, 0)
    f.colName = hdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.colName:SetPoint("LEFT", 34, 0); f.colName:SetText(L["Objet"])

    scroll = CreateFrame("ScrollFrame", "BalgourdeScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -110)
    scroll:SetPoint("BOTTOMRIGHT", -34, 30)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(MIN_W - 50, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)

    emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", scroll, "TOPLEFT", 10, -20)
    emptyText:SetPoint("RIGHT", scroll, "RIGHT", -10, 0)
    emptyText:SetJustifyH("LEFT")

    statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", 16, 12)
    statusText:SetPoint("RIGHT", -30, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetWordWrap(false)

    -- Poignée de redimensionnement
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -6, 6)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); SaveGeometry(); UI.Refresh() end)

    f:SetScript("OnShow", UI.Refresh)
end

function UI.SetStatus(text)
    if not statusText then return end
    if text == "" then
        statusText:SetText(L["|cffaaaaffbleu|r = base de départ   |cff888888gris n/k|r = peu de kills   |cff00ff00+|r/|cffff5555-|r = prix au-dessus/en dessous de la moyenne 7 j"])
    else
        statusText:SetText(text)
    end
end

function UI.Toggle(newMode)
    if not f then return end
    if f:IsShown() and (not newMode or newMode == mode) then f:Hide() return end
    if newMode then mode = newMode end
    f:Show()
    UI.Refresh()
end

function UI.ShowZone() mode = "zone"; f:Show(); UI.Refresh() end
function UI.ShowMob(npcID)
    currentMob = npcID or currentMob
    mode = "mob"
    f:Show()
    UI.Refresh()
end

---------------------------------------------------------------------------
-- Bouton sur la fiche de la cible
---------------------------------------------------------------------------
local targetBtn
local function CreateTargetButton()
    if not TargetFrame then return end
    -- parenté à UIParent (et non au cadre de cible, protégé) : simplement ancré dessus
    targetBtn = CreateFrame("Button", "BalgourdeTargetButton", UIParent, "UIPanelButtonTemplate")
    targetBtn:SetSize(64, 18)
    targetBtn:SetText("Loots")
    targetBtn:SetPoint("BOTTOMLEFT", TargetFrame, "TOPLEFT", 18, -14)
    targetBtn:SetFrameStrata("MEDIUM")
    targetBtn:SetScript("OnClick", function()
        local npcID = ns.NpcIDFromGUID(Safe(UnitGUID("target")))
        if npcID then UI.ShowMob(npcID) end
    end)
    targetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Balgourde : loots et taux de drop de ce monstre"])
        GameTooltip:Show()
    end)
    targetBtn:SetScript("OnLeave", GameTooltip_Hide)
    targetBtn:Hide()
end

local function UpdateTargetButton()
    if not targetBtn then return end
    local npcID = ns.NpcIDFromGUID(Safe(UnitGUID("target")))
    local show = npcID and Safe(UnitPlayerControlled("target")) == false
                 and Safe(UnitCanAttack("player", "target"))
    targetBtn:SetShown(show and true or false)
    if show and f and f:IsShown() and mode == "mob" and BalgourdeDB.settings.followTarget then
        currentMob = npcID
        UI.Refresh()
    end
end

---------------------------------------------------------------------------
-- Infobulles
---------------------------------------------------------------------------
-- Bloc « loots du monstre » commun à l'infobulle de survol et à la carte de la cible
-- add(left, right, r, g, b) ajoute une ligne
function UI.AddMobLootLines(npcID, add, maxItems)
    maxItems = maxItems or 6
    local _, _, _, kills = ns.GetMobInfo(npcID)
    local v, reliable = ns.GetMobValue(npcID)
    add(string.format("|cffd4a017Balgourde|r  |cff999999%d kill%s|r", kills, kills > 1 and "s" or ""),
        v and ((reliable and "" or "|cff888888~|r") .. ns.Money(v) .. " /kill") or "")

    local drops, quests = {}, 0
    for _, d in ipairs(ns.GetMobDrops(npcID)) do
        if d.quest then quests = quests + 1 else drops[#drops + 1] = d end
    end
    if #drops == 0 then
        add(kills == 0 and L["  Aucun loot connu : tuez-le pour l'enregistrer"]
            or L["  Aucun objet observé pour l'instant"], nil, 0.6, 0.6, 0.6)
        return
    end
    table.sort(drops, function(a, b)
        if (a.rate == nil) ~= (b.rate == nil) then return a.rate ~= nil end
        return (a.rate or 0) > (b.rate or 0)
    end)
    for i = 1, math.min(maxItems, #drops) do
        local d = drops[i]
        local name, _, quality = ns.GetItemInfo(d.itemID)
        local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        local icon = select(5, ns.GetItemInfoInstant(d.itemID))
        local label = (icon and ("|T" .. icon .. ":14:14:0:0|t ") or "") .. (name or (L["Objet #"] .. d.itemID))
        add("  " .. label, ns.RateText(d), c and c.r or 0.9, c and c.g or 0.9, c and c.b or 0.9)
    end
    local more = #drops - maxItems
    if more > 0 or quests > 0 then
        local parts = {}
        if more > 0 then parts[#parts + 1] = string.format(L["%d autre%s"], more, more > 1 and "s" or "") end
        if quests > 0 then parts[#parts + 1] = string.format(L["%d objet%s de quête"], quests, quests > 1 and "s" or "") end
        add("  + " .. table.concat(parts, ", ") .. L[" (bouton Loots)"], nil, 0.6, 0.6, 0.6)
    end
end

local function AddUnitLines(tt)
    if not BalgourdeDB.settings.tooltipUnits then return end
    local _, unit = tt:GetUnit()
    unit = Safe(unit)
    if not unit and UnitExists("mouseover") then unit = "mouseover" end
    if not unit then return end
    local npcID = ns.NpcIDFromGUID(Safe(UnitGUID(unit)))
    if not npcID or Safe(UnitPlayerControlled(unit)) ~= false then return end
    if not Safe(UnitCanAttack("player", unit)) then return end
    tt:AddLine(" ")
    local function add(left, right, r, g, b)
        if right and right ~= "" then
            tt:AddDoubleLine(left, right, r or 1, g or 1, b or 1, 1, 1, 1)
        else
            tt:AddLine(left, r or 1, g or 1, b or 1)
        end
    end
    UI.AddMobLootLines(npcID, add, 6)
    ns.Skinning.AddLines(npcID, unit, add)
    ns.Count("tooltipUnit")
    tt:Show() -- recalcule la taille de l'infobulle
end

-- Bloc « désenchantement » de l'infobulle d'un objet
function UI.AddDisenchantLines(itemID, tt)
    local D = ns.Disenchant
    local value, outcomes, source, n = D.GetValue(itemID)
    if not outcomes then return end
    local origin = source == "obs" and string.format(L["vos %d désenchantements"], n)
        or (n and n > 0 and string.format(L["table Classic, %d observé%s"], n, n > 1 and "s" or "") or L["table Classic"])
    tt:AddDoubleLine(L["   Désenchantement |cff888888("] .. origin .. ")|r",
        value and ("~" .. ns.Money(value)) or L["|cff888888prix des composants inconnus|r"], 0.64, 0.21, 0.93, 1, 1, 1)
    for _, o in ipairs(outcomes) do
        local name = ns.GetItemInfo(o.itemID) or AH.ItemName(o.itemID) or (L["Objet #"] .. o.itemID)
        tt:AddDoubleLine(string.format(L["      %s %s %s"], ns.Percent(o.prob), name, D.QtyText(o)),
            o.price and o.price > 0 and ns.Money(o.price) .. " /u" or "", 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
    end
    -- comparaison avec la meilleure vente
    if value then
        local bestSale = 0
        for _, m in ipairs(AH.GetMarkets(itemID)) do
            if m.market ~= "Disenchant" then bestSale = math.max(bestSale, m.expected or m.net) end
        end
        if value > bestSale then
            tt:AddLine(L["      » Plus rentable de désenchanter"], 0, 1, 0)
        end
    end
end

local function AddItemLines(tt)
    if not BalgourdeDB.settings.tooltipItems then return end
    local _, link = tt:GetItem()
    local itemID = ns.ItemIDFromLink(Safe(link))
    if not itemID then return end
    local markets = AH.GetMarkets(itemID)
    local sources = ns.GetItemSources(itemID)
    local deable = BalgourdeDB.settings.tooltipDE and ns.Disenchant.Classify(itemID)
    if #markets == 0 and not sources and not deable then return end
    tt:AddLine(" ")
    tt:AddLine("|cffd4a017Balgourde|r")
    ns.Count("tooltipItem")
    for i, m in ipairs(markets) do
        local left = (i == 1 and "|cff00ff00» |r" or "   ") .. m.label
        local right = ns.Money(m.net)
        if m.market ~= "Vendor" and m.market ~= "Disenchant" then
            right = right .. string.format(L[" |cff888888(vente %s, plus bas %s)|r"], ns.Money(m.gross), ns.Money(m.min))
            if m.stale then left = left .. L[" |cffff5555(trop ancien, ignoré)|r"]
            elseif m.age and m.age > AH.STALE then left = left .. L[" |cffff8800(ancien)|r"] end
        end
        tt:AddDoubleLine(left, right, 0.9, 0.9, 0.9)
    end
    for _, line in ipairs(UI.SaleInfoLines(itemID)) do
        tt:AddLine("   " .. line, 0.7, 0.85, 1)
    end
    if BalgourdeDB.settings.tooltipDE then UI.AddDisenchantLines(itemID, tt) end
    if sources then
        for i = 1, math.min(3, #sources) do
            local s = sources[i]
            tt:AddDoubleLine(L["   Lâché par "] .. ns.GetMobInfo(s.npcID),
                ns.RateText({ rate = s.rate, reliable = s.reliable, count = s.count, kills = s.kills,
                              quest = s.quest, source = s.count and "obs" or "base" }),
                0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
        end
    end
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
            if tt == GameTooltip then ns.SafeCall("infobulle monstre", AddUnitLines, tt) end
        end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
            if tt == GameTooltip or tt == ItemRefTooltip then ns.SafeCall("infobulle objet", AddItemLines, tt) end
        end)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt) ns.SafeCall("infobulle monstre", AddUnitLines, tt) end)
        GameTooltip:HookScript("OnTooltipSetItem", function(tt) ns.SafeCall("infobulle objet", AddItemLines, tt) end)
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", function(tt) ns.SafeCall("infobulle objet", AddItemLines, tt) end) end
    end
end

---------------------------------------------------------------------------
-- Branchements
---------------------------------------------------------------------------
ns.Listen("LOADED", function()
    CreateMainFrame()
    CreateTargetButton()
    HookTooltips()
    UI.SetStatus("")
end)

ns.Listen("DATA_CHANGED", UI.Refresh)
ns.Listen("PRICES_CHANGED", UI.Refresh)
ns.Listen("AH_STATE", UI.Refresh)
ns.Listen("SETTINGS_CHANGED", UI.Refresh)

ns:On("PLAYER_TARGET_CHANGED", UpdateTargetButton)
ns:On("BAG_UPDATE_DELAYED", function()
    -- les objets passés dans vos sacs sont suivis dans l'historique des prix
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (ns.GetContainerNumSlots(bag) or 0) do
            local itemID = ns.GetContainerItem(bag, slot)
            if itemID then BalgourdeDB.watch[itemID] = true end
        end
    end
    if mode == "bags" then UI.Refresh() end
end)

-- Rafraîchit quand le serveur renvoie les infos d'objets pas encore en cache
local itemRefreshQueued = false
ns:On("GET_ITEM_INFO_RECEIVED", function()
    if not pendingItems or itemRefreshQueued then return end
    itemRefreshQueued = true
    C_Timer.After(0.5, function()
        itemRefreshQueued = false
        AH.InvalidateCache()
        ns.InvalidateDropIndex()
        UI.Refresh()
    end)
end)

-- Affichage automatique en entrant dans une zone
local lastZone
local function OnZone()
    if not ns.loaded or not f then return end
    local mapID = ns.GetCurrentZone()
    if not mapID or mapID == lastZone then return end
    lastZone = mapID
    if mode == "zone" and f:IsShown() then UI.Refresh() return end
    if BalgourdeDB.settings.autoShow and not InCombatLockdown() and #ns.GetZoneMobs(mapID) > 0 then
        UI.ShowZone()
    end
end
ns:On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(1, OnZone) end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, OnZone) end)

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------
SLASH_BALGOURDE1 = "/balgourde"
SLASH_BALGOURDE2 = "/balg"
SlashCmdList.BALGOURDE = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local s = BalgourdeDB.settings
    if msg == "" then
        UI.Toggle()
    elseif msg == "zone" then
        UI.ShowZone()
    elseif msg == "cible" or msg == "monstre" then
        local npcID = ns.NpcIDFromGUID(Safe(UnitGUID("target")))
        if npcID then UI.ShowMob(npcID) else ns.Print(L["Aucun monstre ciblé."]) end
    elseif msg == "objets" or msg == "sacs" then
        UI.Toggle("bags")
    elseif msg == "prix" then
        UI.Toggle("prices")
    elseif msg == "scan" then
        AH.StartScan()
    elseif msg == "options" or msg == "config" then
        ns.Options.Open()
    elseif msg == "auto" then
        s.autoShow = not s.autoShow
        ns.Print(L["Ouverture automatique en changeant de zone : "] .. (s.autoShow and L["activée"] or L["désactivée"]))
    elseif msg == "infobulle" then
        s.tooltipItems = not s.tooltipItems
        s.tooltipUnits = s.tooltipItems
        ns.Print(L["Lignes Balgourde dans les infobulles : "] .. (s.tooltipItems and L["activées"] or L["désactivées"]))
    elseif msg == "sync" then
        ns.Sync.Status()
    elseif msg:match("^ignorer") then
        ns.Sync.Ignore(msg:match("^ignorer%s+(.+)$"))
    elseif msg == "effacer-recu" then
        ns.PurgeShared()
        ns.Print(L["Toutes les données reçues de la guilde / du groupe ont été effacées."])
    elseif msg == "hv" then
        AH.Diagnose()
    elseif msg == "test" then
        ns.Diag.Run()
    elseif msg == "erreurs" or msg == "erreurs effacer" then
        ns.Diag.ShowErrors(msg:match("effacer"))
    elseif msg == "taille" then
        ns.Diag.ShowSize()
    elseif msg == "carte" or msg == "carte reset" then
        ns.ToggleTargetCard(msg:match("reset"))
    elseif msg == "minimap" or msg == "minimap reset" then
        ns.ToggleMinimapButton(msg:match("reset"))
    elseif msg == "mapid" then
        local mapID, name = ns.GetCurrentZone()
        ns.Print(L["Zone : "] .. tostring(name) .. " – mapID " .. tostring(mapID))
    elseif msg == "npcid" then
        ns.Print(L["Cible : "] .. tostring(Safe(UnitName("target"))) .. " – npcID " .. tostring(ns.NpcIDFromGUID(Safe(UnitGUID("target")))))
    elseif msg:match("^langue") then
        local choice = msg:match("^langue%s+(%a+)$")
        if choice ~= "fr" and choice ~= "en" and choice ~= "auto" then
            ns.Print("/balg langue fr | en | auto")
        else
            s.lang = choice
            ns.SetLanguage(choice)
            ns.Print(choice == "en" and "Language: English. Type /reload to update every window."
                or choice == "fr" and "Langue : français. Tapez /reload pour mettre à jour toutes les fenêtres."
                or "Langue / language: auto. /reload")
        end
    elseif msg == "debug" then
        s.debug = not s.debug
        ns.Print(L["Debug : "] .. (s.debug and "on" or "off"))
    elseif msg == "reset confirmer" then
        BalgourdeDB.mobs, BalgourdeDB.zones, BalgourdeDB.prices = {}, {}, {}
        ns.InvalidateDropIndex()
        AH.InvalidateCache()
        UI.Refresh()
        ns.Print(L["Toutes les données ont été effacées."])
    else
        ns.Print(L["Commandes :"])
        ns.Print(L["  |cffffff00/balg test|r – diagnostic complet (à envoyer au créateur en cas de souci)"])
        ns.Print(L["  /balg erreurs – erreurs de la session   /balg taille – taille des données sauvegardées"])
        ns.Print("  /balg langue fr | en | auto – " .. (ns.lang == "en" and "language" or "langue"))
        ns.Print(L["  /balg – ouvrir/fermer la fenêtre"])
        ns.Print(L["  /balg zone | cible | objets | prix – choisir l'onglet"])
        ns.Print(L["  /balg options – panneau de réglages"])
        ns.Print(L["  /balg scan – scanner l'HV (HV ouvert)   /balg hv – diagnostic HV"])
        ns.Print(L["  /balg sync – état du partage et joueurs qui vous envoient des données"])
        ns.Print(L["  /balg ignorer Nom – refuser les données d'un joueur   /balg effacer-recu – effacer les données reçues"])
        ns.Print(L["  /balg carte – afficher/masquer la carte de loot de la cible   /balg carte reset – la replacer"])
        ns.Print(L["  /balg minimap – afficher/masquer le bouton   /balg minimap reset – le remettre en place"])
        ns.Print(L["  /balg mapid | npcid – identifiants (pour Data\\Seed.lua)"])
        ns.Print(L["  /balg reset confirmer – tout effacer"])
    end
end
