-- Balgourde - Aide à la mise en vente : prix conseillé quand vous posez un objet à vendre à l'HV,
-- avec un bouton pour remplir les prix (enchère de départ et achat immédiat).
local _, ns = ...
local L = ns.L

ns.Posting = {}
local P = ns.Posting
local AH = ns.Auction

local panel, current -- current = { itemID, count, perUnit, kind = "legacy"|"commodity"|"item", frame }

---------------------------------------------------------------------------
-- Prix conseillé (par unité)
---------------------------------------------------------------------------
-- Retourne prix, raison, entrée de prix ; nil si aucun prix connu sur ce marché
function P.Suggest(itemID, mkt)
    local realm = BalgourdeDB.prices[GetRealmName() or "?"]
    local e = realm and realm[mkt] and realm[mkt][itemID]
    if not e or not e.min then return nil end
    local market = AH.SellPrice(e) or e.min
    local price, reason
    if (e.qty or 0) == 0 then
        price, reason = market, L["aucun en vente : dernier prix connu"]
    elseif e.min >= market * 0.8 then
        price, reason = math.max(1, e.min - 1), L["1 pc sous la moins chère"]
    else
        -- l'enchère la moins chère est bradée : inutile de s'aligner dessus
        price, reason = market, L["valeur de marché (l'enchère la moins chère est bradée)"]
    end
    return price, reason, e
end

---------------------------------------------------------------------------
-- Panneau sous la fenêtre de l'HV
---------------------------------------------------------------------------
local function CreatePanel(parent)
    panel = CreateFrame("Frame", "BalgourdeSellHelper", parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(420, 58)
    panel:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 12, -2)
    panel:SetFrameStrata("HIGH")
    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
    end
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 10, -8)
    panel.title:SetPoint("RIGHT", -120, 0)
    panel.title:SetJustifyH("LEFT")
    panel.detail = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.detail:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
    panel.detail:SetPoint("RIGHT", -120, 0)
    panel.detail:SetJustifyH("LEFT")
    panel.detail:SetWordWrap(true)

    panel.fill = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.fill:SetSize(105, 22)
    panel.fill:SetPoint("RIGHT", -8, 0)
    panel.fill:SetText(L["Remplir"])
    panel.fill:SetScript("OnClick", function() P.Fill() end)
    panel.fill:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Remplir les prix"])
        GameTooltip:AddLine(L["Achat immédiat = prix conseillé, enchère de départ = 95 %. Vérifiez puis cliquez sur « Créer une vente »."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.fill:SetScript("OnLeave", GameTooltip_Hide)
    panel:Hide()
end

local function Update()
    if not panel then return end
    if not current or not current.itemID or not AH.IsOpen() then panel:Hide() return end
    local mkt = AH.CurrentMarket() or UnitFactionGroup("player")
    local price, reason, e = P.Suggest(current.itemID, mkt)
    local name = ns.GetItemInfo(current.itemID) or AH.ItemName(current.itemID) or ("#" .. current.itemID)
    if not price then
        panel.title:SetText(name)
        panel.detail:SetText(L["Aucun prix connu sur ce marché : lancez un scan de l'HV."])
        panel.fill:Disable()
        current.price = nil
        panel:Show()
        return
    end
    current.price = price
    local count = current.count or 1
    panel.title:SetText(string.format(L["Prix conseillé : %s /u"], ns.Money(price))
        .. (count > 1 and ("  |cffaaaaaa(×" .. count .. " = " .. ns.Money(price * count) .. ")|r") or ""))
    local detail = string.format(L["%s · plus bas %s · marché %s · %d en vente"], reason, ns.Money(e.min),
        ns.Money(AH.SellPrice(e)), e.qty or 0)
    -- avertissement si le marchand ou le désenchantement rapporte plus
    local best = AH.GetBest(current.itemID)
    local net = price * (1 - AH.Cut(mkt))
    if best and (best.market == "Vendor" or best.market == "Disenchant") and best.net > net then
        detail = detail .. "\n|cffff8800" .. string.format(L["Attention : %s rapporte plus (%s)."], best.label, ns.Money(best.net)) .. "|r"
    end
    panel.detail:SetText(detail)
    panel:SetHeight(detail:find("\n") and 72 or 58)
    panel.fill:Enable()
    panel:Show()
    if BalgourdeDB.settings.autoFillPrice then P.Fill() end
end
P.Update = Update

---------------------------------------------------------------------------
-- Remplissage des prix
---------------------------------------------------------------------------
function P.Fill()
    if not current or not current.price then return end
    local unit = current.price
    local ok = ns.SafeCall("remplissage des prix", function()
        if current.kind == "legacy" then
            local count = current.count or 1
            -- l'HV classique peut afficher les prix par unité ou par pile
            local perUnit = AuctionFrameAuctions and AuctionFrameAuctions.priceType == (PRICE_TYPE_UNIT or 1)
            local buyout = perUnit and unit or unit * count
            MoneyInputFrame_SetCopper(BuyoutPrice, buyout)
            MoneyInputFrame_SetCopper(StartPrice, math.max(1, math.floor(buyout * 0.95)))
        elseif current.kind == "commodity" then
            current.frame.PriceInput:SetAmount(unit)
        elseif current.kind == "item" then
            current.frame.PriceInput:SetAmount(unit)
            if current.frame.SecondaryPriceInput then
                current.frame.SecondaryPriceInput:SetAmount(math.max(1, math.floor(unit * 0.95)))
            end
        end
    end)
    if ok then ns.Count("priceFills") end
end

---------------------------------------------------------------------------
-- Détection de l'objet posé dans la fenêtre de vente
---------------------------------------------------------------------------
-- HV classique : la fenêtre « Enchères » signale chaque changement d'objet
ns:On("NEW_AUCTION_UPDATE", function()
    if not GetAuctionSellItemInfo then return end
    if not panel and AuctionFrame then CreatePanel(AuctionFrame) end
    local _, _, count, _, _, _, _, _, _, itemID = GetAuctionSellItemInfo()
    if itemID then
        current = { itemID = itemID, count = count or 1, kind = "legacy" }
    else
        current = nil
    end
    Update()
end)

-- HV moderne : on suit les fenêtres de vente d'objets et de marchandises
local hookedModern = false
local function HookModern()
    if hookedModern or not AuctionHouseFrame then return end
    hookedModern = true
    for kind, frame in pairs({ commodity = AuctionHouseFrame.CommoditiesSellFrame, item = AuctionHouseFrame.ItemSellFrame }) do
        if frame and frame.SetItem then
            hooksecurefunc(frame, "SetItem", function(self, itemLocation)
                ns.SafeCall("vente moderne", function()
                    if not panel then CreatePanel(AuctionHouseFrame) end
                    local itemID = itemLocation and C_Item and C_Item.GetItemID and C_Item.GetItemID(itemLocation)
                    current = itemID and { itemID = itemID, count = 1, kind = kind, frame = self } or nil
                    Update()
                end)
            end)
        end
    end
end

ns.Listen("AH_STATE", function()
    HookModern()
    if not AH.IsOpen() then current = nil end
    Update()
end)
ns.Listen("PRICES_CHANGED", Update)
