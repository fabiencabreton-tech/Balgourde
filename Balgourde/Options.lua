-- Balgourde - Panneau de réglages (Échap > Options > AddOns > Balgourde)
local _, ns = ...
local L = ns.L

ns.Options = {}
local O = ns.Options
local panel, category

local function Changed()
    if ns.Auction then ns.Auction.InvalidateCache() end
    ns.InvalidateDropIndex()
    ns.Fire("SETTINGS_CHANGED")
end

local function CreatePanel()
    panel = CreateFrame("Frame")
    panel.name = "Balgourde"
    -- contenu défilable : la liste des réglages dépasse la hauteur du panneau
    local scroll = CreateFrame("ScrollFrame", "BalgourdeOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 1000)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Balgourde " .. ns.VERSION)
    local sub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText(L["Monstres de la zone, loots, taux de drop et meilleur marché pour vendre."])

    local y = -70
    local checks = {}
    local function Section(text)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("TOPLEFT", 16, y)
        fs:SetText(text)
        y = y - 24
    end
    local function Check(key, label, tip, onSet)
        local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 24, y)
        local text = cb.Text or cb.text
        if not text then
            text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        end
        text:SetText(label)
        cb:SetScript("OnClick", function(self)
            local v = self:GetChecked() and true or false
            if key == "minimapShown" then
                BalgourdeDB.settings.minimapHidden = not v
                if BalgourdeMinimapButton then BalgourdeMinimapButton:SetShown(v) end
            else
                BalgourdeDB.settings[key] = v
            end
            if onSet then onSet(v) end
            Changed()
        end)
        if tip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(label)
                GameTooltip:AddLine(tip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", GameTooltip_Hide)
        end
        checks[key] = cb
        y = y - 28
    end

    Section(L["Affichage"])
    Check("autoShow", L["Ouvrir la fenêtre en entrant dans une zone connue"])
    Check("followTarget", L["L'onglet Monstre suit la cible"])
    Check("minimapShown", L["Afficher le bouton autour de la minimap"])
    Check("hideGrey", L["Cacher les objets gris (camelote)"])
    Check("hideEmpty", L["Cacher les monstres sans loot connu"])

    Section(L["Infobulles"])
    Check("tooltipUnits", L["Loots et taux dans l'infobulle des monstres (survol)"])
    Check("targetCard", L["Carte de loot sous le cadre de cible"],
        L["Petite infobulle permanente avec les taux de loot du monstre sélectionné. Clic : fiche du monstre. Maj + glisser : déplacer. Clic droit : masquer."])
    Check("tooltipItems", L["Prix par marché et sources dans l'infobulle des objets"])
    Check("tooltipDE", L["Résultats de désenchantement dans l'infobulle des objets"])
    Check("tooltipSkin", L["Dépeçage sur les monstres (compétence requise et cuirs)"])
    Check("deInBest", L["Proposer « Désenchanter » comme meilleur marché"],
        L["Par défaut, activé seulement si votre personnage sait désenchanter."])

    Section(L["Hôtel des ventes"])
    Check("autoFillPrice", L["Remplir automatiquement le prix conseillé en posant un objet à vendre"],
        L["Sinon, cliquez sur « Remplir » sous la fenêtre de l'HV."])

    Section(L["Partage des observations"])
    Check("syncGuild", L["Partager avec la guilde"],
        L["Vos kills et loots sont envoyés aux membres de la guilde qui ont Balgourde, et les leurs vous sont ajoutés. Les taux deviennent fiables bien plus vite."])
    Check("syncGroup", L["Partager avec le groupe / raid"])
    Check("useShared", L["Inclure les données reçues dans les taux"],
        L["Décochez pour n'afficher que vos propres observations. Les données reçues sont conservées à part."])
    local purge = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    purge:SetSize(260, 22)
    purge:SetPoint("TOPLEFT", 28, y)
    purge:SetText(L["Effacer les données reçues des autres"])
    purge:SetScript("OnClick", function()
        ns.PurgeShared()
        ns.Print(L["Données reçues effacées."])
    end)
    local purgeHint = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    purgeHint:SetPoint("LEFT", purge, "RIGHT", 10, 0)
    purgeHint:SetText(L["/balg sync : qui envoie quoi – /balg ignorer Nom"])
    y = y - 32

    Section(L["Fiabilité des taux"])
    local label = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 28, y - 4)
    label:SetText(L["Nombre de kills avant d'afficher un taux en % :"])
    local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    box:SetSize(40, 20)
    box:SetPoint("LEFT", label, "RIGHT", 12, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(3)
    local function Apply(self)
        local v = tonumber(self:GetText()) or 10
        v = math.max(1, math.min(200, v))
        BalgourdeDB.settings.reliableKills = v
        self:SetText(tostring(v))
        self:ClearFocus()
        Changed()
    end
    box:SetScript("OnEnterPressed", Apply)
    box:SetScript("OnEditFocusLost", Apply)
    local hint = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    hint:SetText(L["En dessous, le taux s'affiche en gris sous la forme « drops / kills »."])
    y = y - 60

    Section(L["Données"])
    local reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    reset:SetSize(220, 22)
    reset:SetPoint("TOPLEFT", 24, y)
    reset:SetText(L["Effacer les prix HV enregistrés"])
    reset:SetScript("OnClick", function()
        BalgourdeDB.prices = {}
        Changed()
        ns.Print(L["Prix HV effacés."])
    end)

    content:SetHeight(-y + 60)

    panel:SetScript("OnShow", function()
        local s = BalgourdeDB.settings
        for key, cb in pairs(checks) do
            if key == "minimapShown" then cb:SetChecked(not s.minimapHidden)
            elseif key == "deInBest" then cb:SetChecked(ns.Disenchant.InBest())
            else cb:SetChecked(s[key]) end
        end
        box:SetText(tostring(s.reliableKills or 10))
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "Balgourde")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function O.Open()
    if not panel then return end
    if Settings and Settings.OpenToCategory and category then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel) -- double appel : contournement d'un vieux bug Blizzard
    end
end

ns.Listen("LOADED", CreatePanel)
