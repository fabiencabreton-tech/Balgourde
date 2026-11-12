#!/usr/bin/env python3
"""
Balgourde - convertit un fichier CSV de taux de drop en Data/Seed.lua

Utilisation (Python 3, aucune bibliothèque à installer) :
    python convert_seed.py drops.csv
    python convert_seed.py drops.csv ../Data/Seed.lua

Le fichier CSV doit avoir une ligne d'en-tête. Colonnes reconnues
(l'ordre n'a pas d'importance, séparateur , ou ; détecté automatiquement) :

    npc_id      (obligatoire) identifiant du monstre    ex. 299
    item_id     (obligatoire) identifiant de l'objet    ex. 2589
    drop_rate   (obligatoire) taux : 25 / 25% / 25,5 / 0.25 (fraction si <= 1 et sans %)
    npc_name    (optionnel)   nom du monstre
    map_id      (optionnel)   mapID de la zone (/balg mapid en jeu) ; plusieurs : 1429|1436
    min_level   (optionnel)
    max_level   (optionnel)

Noms de colonnes alternatifs acceptés : npc, npcid, mob_id / item, itemid /
rate, chance, taux / name, nom / map, zone_id, mapid / level_min, level_max.

Une ligne par couple (monstre, objet). Exemple :
    npc_id;npc_name;map_id;min_level;max_level;item_id;drop_rate
    299;Jeune loup;1429;1;2;2589;35%
"""
import csv
import io
import os
import sys

ALIASES = {
    "npc_id": {"npc_id", "npc", "npcid", "mob_id", "mobid", "creature_id"},
    "item_id": {"item_id", "item", "itemid"},
    "drop_rate": {"drop_rate", "rate", "chance", "taux", "droprate", "drop_chance"},
    "npc_name": {"npc_name", "name", "nom", "mob_name", "creature"},
    "map_id": {"map_id", "map", "zone_id", "mapid", "uimapid"},
    "min_level": {"min_level", "level_min", "minlevel", "lvl_min"},
    "max_level": {"max_level", "level_max", "maxlevel", "lvl_max"},
}


def norm_header(h):
    h = h.strip().lower().replace(" ", "_").replace("-", "_")
    for key, names in ALIASES.items():
        if h in names:
            return key
    return h


def parse_rate(raw):
    s = str(raw).strip().replace(",", ".")
    if not s:
        return None
    pct = s.endswith("%")
    s = s.rstrip("%").strip()
    try:
        v = float(s)
    except ValueError:
        return None
    if pct or v > 1:
        v = v / 100.0
    return max(0.0, min(1.0, v))


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def to_int(v):
    try:
        return int(float(str(v).strip()))
    except (TypeError, ValueError):
        return None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    here = os.path.dirname(os.path.abspath(__file__))
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "..", "Data", "Seed.lua")

    with open(src, "r", encoding="utf-8-sig") as fh:
        text = fh.read()
    dialect = csv.Sniffer().sniff(text.splitlines()[0], delimiters=",;\t")
    reader = csv.reader(io.StringIO(text), dialect)
    header = [norm_header(h) for h in next(reader)]
    for needed in ("npc_id", "item_id", "drop_rate"):
        if needed not in header:
            sys.exit(f"Colonne obligatoire manquante : {needed} (en-têtes lus : {header})")

    mobs, zones, skipped = {}, {}, 0
    for line_no, values in enumerate(reader, start=2):
        if not any(v.strip() for v in values):
            continue
        row = dict(zip(header, values))
        npc, item, rate = to_int(row.get("npc_id")), to_int(row.get("item_id")), parse_rate(row.get("drop_rate", ""))
        if not npc or not item or rate is None:
            skipped += 1
            print(f"  ligne {line_no} ignorée : {values}")
            continue
        mob = mobs.setdefault(npc, {"drops": {}})
        mob["drops"][item] = max(rate, mob["drops"].get(item, 0))
        if row.get("npc_name", "").strip():
            mob["name"] = row["npc_name"].strip()
        for k in ("min_level", "max_level"):
            lv = to_int(row.get(k))
            if lv:
                mob[k] = lv
        for m in str(row.get("map_id", "")).replace(",", "|").split("|"):
            mid = to_int(m)
            if mid:
                zones.setdefault(mid, set()).add(npc)

    out = ["-- Balgourde - Données de départ (générées par tools/convert_seed.py)",
           "-- Source : " + os.path.basename(src),
           "local _, ns = ...", "", "ns.Seed = {", "    zones = {"]
    for mid in sorted(zones):
        out.append(f"        [{mid}] = {{ {', '.join(str(n) for n in sorted(zones[mid]))} }},")
    out += ["    },", "    mobs = {"]
    for npc in sorted(mobs):
        m = mobs[npc]
        fields = []
        if "name" in m:
            fields.append("name = " + lua_str(m["name"]))
        if "min_level" in m:
            fields.append(f"minLevel = {m['min_level']}")
        if "max_level" in m:
            fields.append(f"maxLevel = {m['max_level']}")
        drops = ", ".join(f"[{i}] = {r:.4f}" for i, r in sorted(m["drops"].items()))
        fields.append("drops = { " + drops + " }")
        out.append(f"        [{npc}] = {{ {', '.join(fields)} }},")
    out += ["    },", "}", ""]

    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    with open(dst, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out))
    n_drops = sum(len(m["drops"]) for m in mobs.values())
    print(f"OK : {len(mobs)} monstres, {n_drops} objets, {len(zones)} zones -> {dst}")
    if skipped:
        print(f"{skipped} ligne(s) ignorée(s).")


if __name__ == "__main__":
    main()
