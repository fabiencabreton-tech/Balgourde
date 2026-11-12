# Balgourde — addon WoW Forever (v0.9.0)

## Installation
1. Supprimer l'ancien dossier `Balgourde`, puis copier le nouveau dans
   `World of Warcraft\_forever_\Interface\AddOns\` (le dossier de version qui contient WoW Forever).
2. Relancer le jeu (un `/reload` suffit si l'icône existait déjà).

## Fenêtre principale (`/balg`, ou bouton de minimap)
- **Zone** : monstres de la zone, leurs loots et taux de drop.
  - Clic sur un monstre : le replier / déplier. Clic droit : sa fiche.
  - « Tri : niveau / rentabilité » : la rentabilité = or moyen ramassé + Σ (taux × meilleur prix net) des objets, hors quête.
- **Monstre** (ou bouton « Loots » sur la cible) : la même liste pour un seul monstre, avec son butin de vol à la tire.
- **Mes objets** : chaque objet des sacs, prix marchand, prix HV net, meilleur marché, valeur totale.
- **Recherche** (nom de monstre ou d'objet), **Cacher gris**, **Cacher sans loot**, tri des taux croissant/décroissant.
- Fenêtre déplaçable et **redimensionnable** (coin en bas à droite).

## Taux de loot au survol et sur la cible
- **Survol d'un monstre** : son infobulle affiche ses kills, sa valeur moyenne par kill et ses 6 loots les plus fréquents avec leur taux.
- **Monstre sélectionné** : une petite carte apparaît sous le cadre de cible avec ses 8 loots principaux.
  Clic = fiche complète, Maj + glisser = déplacer, clic droit = masquer (`/balg carte` pour la réafficher, `/balg carte reset` pour la replacer).

## Lecture des taux
- `25%` blanc : vos observations (et celles de la guilde/du groupe), assez de kills.
- `2/7` gris : moins de 10 kills (réglable) → « tombé 2 fois sur 7 kills », pas encore fiable.
- `25%` bleu : base de départ (`Data\Seed.lua`).
- `quête` : objet de quête, ne tombe que si vous avez la quête → pas de taux, pas compté dans la rentabilité.
- Le **vol à la tire** est compté à part (« poches ») et ne fausse plus les taux des cadavres.

## Prix
- « Scanner l'HV » auprès d'un commissaire-priseur (scan complet ~ toutes les 15 min). Les recherches manuelles sont aussi enregistrées.
- **Valeur de marché** = médiane du quart le moins cher de l'offre : une enchère bradée isolée ne fausse plus le conseil.
- Seuls les marchés où **ce personnage** peut vendre sont comparés : marchand, HV de sa faction, HV neutre.
- **Historique** : une valeur par jour est gardée 14 jours. Dans la colonne HV, `+` vert = prix au-dessus de la
  moyenne 7 jours (bon moment pour vendre), `-` rouge = en dessous.
- **Concurrence** : l'infobulle indique combien d'exemplaires sont en vente et en combien d'annonces.
- **Vos ventes réelles** : en relevant votre courrier (« Vente réussie », « Enchère expirée »), l'addon calcule
  quelle part de vos mises en vente part vraiment. Dès 3 mises en vente, le conseil utilise un **gain espéré**
  = taux de vente × prix net − taux d'invendus × dépôt (dépôt estimé à 15 % du prix marchand, réglable `AH.DEPOSIT`).
  Un objet cher qui ne part jamais peut ainsi être mieux vendu au marchand.
- Commission déduite : 5 % (faction), 15 % (neutre) — modifiable dans `Auction.lua` (`AH.CUT`).

## Fiabilité des prix
- **Vos propres enchères** sont exclues des prix relevés (elles fausseraient la valeur de marché).
- Les enchères dont le jeu n'a pas encore chargé l'objet sont **relues jusqu'à 3 fois** ; le bilan du scan
  indique combien des vôtres ont été exclues et combien d'enchères restaient incomplètes.
- **Scan interrompu** (HV fermé pendant l'analyse) ou vide : vos prix précédents sont conservés.
- **Commission et dépôt réels** : lus dans les courriers « Vente réussie » (détail de la vente). Après 3 ventes
  sur un HV, ils remplacent les estimations (5 % / 15 % de commission, dépôt 15 % du prix marchand).
- Un prix de **plus de 7 jours** reste affiché mais n'est plus utilisé pour conseiller où vendre.

## Aide à la mise en vente
Quand vous posez un objet dans la fenêtre de vente de l'HV, une bande sous la fenêtre affiche le **prix conseillé**
(1 pc sous l'enchère la moins chère, ou la valeur de marché si celle-ci est bradée), le plus bas, la valeur de marché,
le nombre en vente, et prévient si le marchand ou le désenchantement rapporte plus. Bouton **Remplir** :
achat immédiat = prix conseillé, enchère de départ = 95 %. Option pour remplir automatiquement.

## Statistiques de prix (onglet « Prix HV », `/balg prix`)
- Liste de tous les objets relevés à l'HV : quantité en vente, valeur actuelle, moyenne 7 jours, tendance.
  Recherche, « Seulement mes objets », tri par prix / tendance / quantité / nom, bouton pour changer de marché
  (HV de votre faction ↔ HV neutre). 150 lignes max : affinez avec la recherche.
- **Clic sur n'importe quel objet** (dans tous les onglets) : fiche de prix détaillée
  - valeur de marché et plus bas actuels, nombre en vente et d'annonces, ancienneté du relevé ;
  - moyennes 7 et 14 jours, plus bas / plus haut sur 14 jours, quantité moyenne en vente ;
  - gain net à chaque HV, gain espéré, vos ventes (vendus / expirés) et prix moyen réellement encaissé ;
  - historique jour par jour avec barre de prix et variation d'un jour à l'autre.
- L'historique se construit avec **un scan complet par jour** (14 jours conservés).

## Désenchantement
- L'infobulle de chaque objet désenchantable (vert, bleu, violet ; armes et armures) indique ce qu'on peut obtenir :
  chance, composant, quantité, prix unitaire, et la **valeur espérée** du désenchantement.
  « » Plus rentable de désenchanter » apparaît quand ça rapporte plus que la meilleure vente.
- La fiche de prix de l'objet (clic) détaille aussi le désenchantement.
- « Désenchanter » peut apparaître comme **meilleur marché** (onglet Mes objets, y compris pour les objets liés) :
  activé par défaut si votre personnage sait désenchanter, réglable dans les options.
- Données : tables de WoW Classic par niveau d'objet (warcraft.wiki.gg). Dès que vous avez désenchanté
  10 objets d'une même tranche (qualité, type, niveau), **vos résultats réels remplacent la table**,
  au cas où WoW Forever aurait changé les taux.

## Dépeçage
- Au survol d'une bête (ou d'un draconien), et sur la carte de la cible : **compétence requise** pour le dépecer
  (en rouge si la vôtre est trop basse) et **cuirs / peaux possibles** selon le niveau du monstre.
- Après vos dépeçages, l'addon affiche les **vrais taux pour ce monstre** (cuir obtenu, quantité, %)
  et la **valeur moyenne d'un dépeçage** au prix de l'HV. La fiche du monstre a une section « Dépeçage ».
- Formule Classic de la compétence requise : 1 jusqu'au niveau 10, niveau × 10 − 100 du 11 au 20, niveau × 5 au-delà.
- Le cuir dépecé n'est jamais compté comme loot du monstre.

## Partage guilde / groupe
Les kills et loots sont échangés automatiquement avec les joueurs de votre guilde et de votre groupe qui ont Balgourde,
par paquets toutes les 5 secondes (pas de messages perdus en farm intensif). Un même cadavre n'est compté qu'une fois.
Les données reçues sont **rangées à part** :
- option « Inclure les données reçues dans les taux » pour les activer / désactiver ;
- `/balg sync` : qui vous a envoyé combien d'observations ;
- `/balg ignorer Nom` : refuser les données d'un joueur ; `/balg effacer-recu` : effacer tout ce qui a été reçu.

Un kill n'est compté que si vous ou votre groupe avez combattu le monstre (les monstres tués par des gardes ne comptent plus).

## Importer des taux (`tools/convert_seed.py`)
Avec Python 3 : `python convert_seed.py drops.csv` → réécrit `Data\Seed.lua`.
CSV avec en-tête, séparateur `,` ou `;` :
```
npc_id;npc_name;map_id;min_level;max_level;item_id;drop_rate
299;Jeune loup;1429;1;2;2589;35%
```
`drop_rate` accepte `35%`, `35`, `0.35`. Plusieurs zones : `1429|1436`. `/balg mapid` et `/balg npcid` donnent les identifiants en jeu.

## Options
Échap → Options → AddOns → Balgourde, ou `/balg options`, ou le bouton « Options » de la fenêtre.

## Diagnostic et erreurs
- `/balg test` : vérifie en jeu tout ce qui dépend de WoW Forever (HV, or par cadavre, infobulles, minimap,
  compétence de dépeçage, partage…) et affiche [OK] / [?] / [X]. À envoyer en capture si quelque chose cloche.
- `/balg erreurs` : erreurs de la session (plus aucune n'est avalée en silence). `/balg taille` : poids des données.
- L'historique des prix n'est gardé que pour les objets qui vous concernent (sacs, loots connus, cuirs,
  composants d'enchantement, objets vendus ou consultés) et stocké en texte compact.

## Langue
Interface en français ou en anglais selon la langue du jeu. Forcer : `/balg langue fr | en | auto`, puis `/reload`.

## Commandes
`/balg` · `zone` · `cible` · `objets` · `prix` · `options` · `scan` · `hv` · `sync` · `ignorer Nom` · `effacer-recu` · `minimap` · `minimap reset` · `auto` · `infobulle` ·
`mapid` · `npcid` · `test` · `erreurs` · `taille` · `langue` · `reset confirmer`
