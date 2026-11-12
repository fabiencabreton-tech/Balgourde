-- Balgourde - Carte de loot de la cible : petite infobulle permanente sous le cadre de cible
--   Clic : ouvrir la fiche du monstre   Maj + glisser : déplacer   Clic droit : masquer
local _, ns = ...
local L = ns.L

local card
local currentNpc

local function SavePos()
    local p, _, rp, x, y = card:GetPoint()
    BalgourdeDB.settings.targetCardPos = { p, rp, x, y }
end

local function Place()
    card:ClearAllPoints()
    local pos = BalgourdeDB.settings.targetCardPos
    if pos then
        card:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    elseif TargetFrame then
        card:SetPoint("TOPLEFT", TargetFrame, "BOTTOMLEFT", 10, 6)
    else
        card:SetPoint("TOP", UIParent, "TOP", 0, -200)
    end
end

local function Fill()
    if not card or not currentNpc then return end
    card:SetOwner(UIParent, "ANCHOR_NONE")
    Place()
    local first = true
    local function add(left, right, r, g, b)
        if first then
            -- première ligne : nom du monstre + Balgourde
            card:AddDoubleLine(ns.GetMobInfo(currentNpc), right or "", 1, 0.82, 0, 1, 1, 1)
            first = false
            return
        end
        if right and right ~= "" then
            card:AddDoubleLine(left, right, r or 1, g or 1, b or 1, 1, 1, 1)
        else
            card:AddLine(left, r or 1, g or 1, b or 1)
        end
    end
    ns.UI.AddMobLootLines(currentNpc, add, 8)
    ns.Skinning.AddLines(currentNpc, "target", add)
    card:Show()
end

local function Update()
    if not card then return end
    local s = BalgourdeDB.settings
    local unit = "target"
    local npcID = UnitExists(unit) and ns.NpcIDFromGUID(ns.Safe(UnitGUID(unit)))
    local ok = s.targetCard and npcID
        and ns.Safe(UnitPlayerControlled(unit)) == false
        and ns.Safe(UnitCanAttack("player", unit))
    if not ok then
        currentNpc = nil
        card:Hide()
        return
    end
    currentNpc = npcID
    Fill()
end

local function Create()
    card = CreateFrame("GameTooltip", "BalgourdeTargetCard", UIParent, "GameTooltipTemplate")
    card:SetFrameStrata("LOW")
    card:SetClampedToScreen(true)
    card:SetMovable(true)
    card:EnableMouse(true)
    card:RegisterForDrag("LeftButton")
    card:SetScale(0.9)
    card:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    card:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    card:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            BalgourdeDB.settings.targetCard = false
            card:Hide()
            ns.Print(L["Carte de loot de la cible masquée (réactivez-la dans /balg options ou /balg carte)."])
        elseif not IsShiftKeyDown() and currentNpc then
            ns.UI.ShowMob(currentNpc)
        end
    end)
    card:Hide()
end

function ns.ToggleTargetCard(arg)
    local s = BalgourdeDB.settings
    if arg == "reset" then
        s.targetCardPos = nil
        s.targetCard = true
        ns.Print(L["Carte de loot replacée sous le cadre de cible."])
    else
        s.targetCard = not s.targetCard
        ns.Print(L["Carte de loot de la cible : "] .. (s.targetCard and L["affichée"] or L["masquée"]))
    end
    Update()
end

ns.Listen("LOADED", function()
    if BalgourdeDB.settings.targetCard == nil then BalgourdeDB.settings.targetCard = true end
    Create()
    Update()
end)
ns:On("PLAYER_TARGET_CHANGED", function() Update() end)
ns.Listen("DATA_CHANGED", Update)
ns.Listen("PRICES_CHANGED", Update)
ns.Listen("SETTINGS_CHANGED", Update)
local queued = false
ns:On("GET_ITEM_INFO_RECEIVED", function()
    if not currentNpc or queued then return end
    queued = true
    C_Timer.After(0.3, function() queued = false; Update() end)
end)
