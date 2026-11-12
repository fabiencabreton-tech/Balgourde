-- Balgourde - Données de départ (optionnelles)
--
-- Le jeu ne donne pas aux addons la liste des monstres d'une zone ni les taux
-- de drop. Balgourde les apprend en jeu (vos kills et vos loots), mais vous
-- pouvez aussi pré-remplir ce fichier à partir d'une base externe
-- (vos propres relevés, ceux de votre guilde…).
--
-- Format :
--   zones[mapID] = { npcID, npcID, ... }
--   mobs[npcID]  = { name = "Nom", minLevel = 5, maxLevel = 7,
--                    drops = { [itemID] = 0.25, ... } }   -- 0.25 = 25 %
--
-- Le mapID d'une zone s'obtient en jeu avec : /balg mapid
-- Le npcID d'un monstre ciblé s'obtient avec : /balg npcid
--
-- Quand une donnée existe ici ET a été observée en jeu, l'addon affiche le
-- taux de la base de départ tant que vous avez moins de
-- Balgourde.MIN_KILLS_OVERRIDE kills sur ce monstre, puis bascule sur vos
-- propres observations.

local _, ns = ...

ns.Seed = {
    zones = {
        -- [1429] = { 299, 6, 38 },
    },
    mobs = {
        -- [299] = { name = "Exemple", minLevel = 1, maxLevel = 2,
        --           drops = { [2589] = 0.30 } },
    },
}
