-- Balgourde - Bouton autour de la minimap (déplaçable) + menu des addons du client moderne
local _, ns = ...
local L = ns.L

local ICON = "Interface\\AddOns\\Balgourde\\Media\\Icon"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local btn

local function UpdatePosition()
    if not btn then return end
    local angle = math.rad(BalgourdeDB.settings.minimapAngle or 215)
    local w = Minimap:GetWidth()
    if not w or w < 50 then w = 140 end
    local radius = (w / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
    BalgourdeDB.settings.minimapAngle = math.deg(atan2(cy - my, cx - mx)) % 360
    UpdatePosition()
end

local function OnClick(_, button)
    if button == "RightButton" then
        ns.UI.Toggle("bags")
    elseif IsShiftKeyDown() then
        local npcID = ns.NpcIDFromGUID(ns.Safe(UnitGUID("target")))
        if npcID then ns.UI.ShowMob(npcID) else ns.UI.Toggle("zone") end
    else
        ns.UI.Toggle("zone")
    end
end

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffd4a017Balgourde|r")
    GameTooltip:AddLine(L["Clic gauche : monstres de la zone"], 1, 1, 1)
    GameTooltip:AddLine(L["Maj + clic : monstre ciblé"], 1, 1, 1)
    GameTooltip:AddLine(L["Clic droit : mes objets et prix"], 1, 1, 1)
    if owner == btn then GameTooltip:AddLine(L["Glisser : déplacer autour de la minimap"], 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function CreateMinimapButton()
    if not Minimap then ns.Print(L["Minimap introuvable : utilisez /balg."]) return end
    btn = CreateFrame("Button", "BalgourdeMinimapButton", Minimap)
    btn:SetSize(31, 31)
    -- toujours au-dessus de la minimap, quel que soit le client
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 10)
    btn:SetToplevel(true)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    -- si l'image n'est pas encore chargée par le jeu (pas de redémarrage), icône de secours
    if icon:SetTexture(ICON) == false then icon:SetTexture(FALLBACK_ICON) end
    icon:SetSize(21, 21)
    icon:SetPoint("TOPLEFT", 5, -5)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    btn:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 6, -6) end)
    btn:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 5, -5) end)
    btn:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
        icon:SetPoint("TOPLEFT", 5, -5)
    end)
    btn:SetScript("OnClick", OnClick)
    btn:SetScript("OnEnter", ShowTooltip)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    UpdatePosition()
    btn:SetShown(not BalgourdeDB.settings.minimapHidden)
    -- la minimap du client moderne peut changer de taille après le chargement
    Minimap:HookScript("OnSizeChanged", UpdatePosition)
end

-- /balg minimap : afficher/masquer ; /balg minimap reset : remettre en place
function ns.ToggleMinimapButton(arg)
    local s = BalgourdeDB.settings
    if arg == "reset" then
        s.minimapHidden, s.minimapAngle = false, 215
        if btn then UpdatePosition(); btn:Show() end
        ns.Print(L["Bouton de minimap remis en place (en bas à gauche de la minimap)."])
        return
    end
    s.minimapHidden = not s.minimapHidden
    if btn then btn:SetShown(not s.minimapHidden) end
    ns.Print(L["Bouton de minimap : "] .. (s.minimapHidden and L["masqué"] or L["affiché"]))
end

-- Menu des addons du client moderne (petit bouton à côté de la minimap)
function Balgourde_OnCompartmentClick(_, button) OnClick(nil, button) end
function Balgourde_OnCompartmentEnter(_, owner) ShowTooltip(owner) end
function Balgourde_OnCompartmentLeave() GameTooltip:Hide() end

ns.Listen("LOADED", CreateMinimapButton)
