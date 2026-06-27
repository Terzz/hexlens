#!/usr/bin/env python3
"""
ARAM: Mayhem ("ARAM du Chaos") augment data pipeline — v2 (build-aware).

Produces, from free static sources, the JSON the Swift overlay consumes to recommend
augments per champion AND per live item build. Compliance: deterministic heuristic,
NO win rates (Mayhem match data is API-blocked + Riot forbids displaying augment win rates).

Sources (all free, no key):
  - CommunityDragon kiwi.bin.json (game/maps/modespecificdata/) — canonical Mayhem augment list
    (220 records, current pool incl. new gen), with description string-KEYS + AugmentDisplayTags.
  - CommunityDragon lol.stringtable.json (game/en_us/data/menu/en_us/) — resolves those keys -> text
    (100% description coverage).
  - CommunityDragon cherry-augments.json — .png icon paths (join on AugmentPlatformId for the overlap).
  - Data Dragon champion.json — champion tags/info/partype -> champion stat vector.
  - Data Dragon item.json — item `tags` -> item stat vector (NOT `stats`, which is legacy/incomplete).

Outputs (out/):
  - mayhem_catalog_<ver>.json         220 augments: id, name, rarity, primaryCategory, damageType,
                                       stat vector, pivot flag, icon, description.
  - mayhem_champions_<ver>.json       per-champion stat vector C (for champion-prior scoring).
  - mayhem_items_<ver>.json           itemID -> stat vector (for runtime build profile B in Swift).
  - mayhem_recommendations_compact_<ver>.json   per-champion top augments/rarity (offline, build-agnostic).

Usage: python3 mayhem_pipeline.py [--verify] [--refresh]
"""
import json, math, os, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
OUT = os.path.join(HERE, "out")
CDRAGON = "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default"
CD_GAME = "https://raw.communitydragon.org/latest/game"
DDRAGON = "https://ddragon.leagueoflegends.com"

# Shared stat-class space for champions, augments and items.
DIMS = ["ap", "ad", "crit", "on_hit", "attack_speed", "ah", "tank", "heal_shield", "pen", "mana"]
RARITY_KIWI = {None: "Silver", 0: "Silver", 1: "Gold", 2: "Prismatic"}

# Build-defining "pivot" augments: change what you should build. Keyed by apiName stem.
# value = the champion dim that must be present for the pivot to be viable.
PIVOTS = {
    "ADAPt": "ad", "Marksmage": "on_hit", "JeweledGauntlet": "ap", "HeavyHitter": "tank",
    "TankEngine": "tank", "ApexInventor": "ah", "AllForYou": "heal_shield",
}


# ---------------------------------------------------------------- fetch helpers
def _get(url, dest, refresh=False):
    if os.path.exists(dest) and not refresh:
        return open(dest, encoding="utf-8").read()
    req = urllib.request.Request(url, headers={"User-Agent": "mayhem-pipeline/2.0 (personal overlay)"})
    with urllib.request.urlopen(req, timeout=200) as r:
        data = r.read().decode("utf-8")
    open(dest, "w").write(data)
    return data


def ddragon_version(refresh=False):
    return json.loads(_get(f"{DDRAGON}/api/versions.json", os.path.join(RAW, "versions.json"), refresh))[0]


# ---------------------------------------------------------------- text helpers
def strip_markup(s):
    s = re.sub(r"<br\s*/?>", " ", s)
    s = re.sub(r"@[^@]*@", "", s)            # @Var@ placeholders
    s = re.sub(r"<[^>]+>", "", s)            # typed/html tags
    s = re.sub(r"%i:[^%]*%", "", s)          # icon refs
    return re.sub(r"\s+", " ", s).strip()


def cdragon_icon_url(asset_path):
    """ASSETS/UX/Cherry/Augments/Icons/X_small.tex -> CDragon .png URL."""
    if not asset_path:
        return ""
    p = asset_path.lower().replace(".tex", ".png")
    marker = "/lol-game-data/assets/"
    i = p.find(marker)
    rel = p[i + len(marker):] if i >= 0 else p.lstrip("/")
    if not rel.startswith("assets/"):
        rel = "assets/" + rel
    return f"{CDRAGON}/{rel}"


# ------------------------------------------------------- augment categorisation
# Typed-markup tag -> (primaryCategory, damageType, stat-dims). First tag in the tooltip wins.
TYPED = [
    ("physicalDamage", "Offense", "AD", ["ad"]),
    ("scaleAD", "Offense", "AD", ["ad"]),
    ("magicDamage", "Offense", "AP", ["ap"]),
    ("scaleAP", "Offense", "AP", ["ap"]),
    ("scaleAF", "Offense", "ADAPTIVE", ["ap", "ad"]),
    ("crit", "Offense-Crit", "AD", ["crit", "ad"]),
    ("attackSpeed", "Offense-AS", None, ["attack_speed", "on_hit"]),
    ("lifeSteal", "Sustain", None, ["heal_shield"]),
    ("healing", "Sustain", None, ["heal_shield"]),
    ("shield", "Sustain", None, ["heal_shield"]),
    ("scaleHealth", "Tank", None, ["tank"]),
    ("scaleArmor", "Tank", None, ["tank"]),
    ("scaleMR", "Tank", None, ["tank"]),
    ("trueDamage", "Offense", None, []),
    ("scaleAbilityHaste", "Utility", None, ["ah"]),
    ("speed", "Utility", None, []),
    ("status", "Utility", None, []),
]
# Riot's own AugmentDisplayTags (coarse fallback for augments without typed markup).
DISPLAY_TAG = {0: ("Sustain", ["heal_shield"]), 1: ("Offense", ["ad", "ap"]), 2: ("Utility", []),
               3: ("Tank", ["tank"]), 4: ("Utility", []), 5: ("Sustain", ["heal_shield"]),
               7: ("Utility", []), 8: ("Utility", []), 9: ("Utility", [])}
# Last-resort keywords over the cleaned description (first match wins).
KEYWORDS = [
    ("ability power", "Offense", "AP", ["ap"]), ("attack damage", "Offense", "AD", ["ad"]),
    ("attack speed", "Offense-AS", None, ["attack_speed", "on_hit"]),
    ("critical", "Offense-Crit", "AD", ["crit"]), ("on-hit", "Offense", None, ["on_hit"]),
    ("heal", "Sustain", None, ["heal_shield"]), ("shield", "Sustain", None, ["heal_shield"]),
    ("armor", "Tank", None, ["tank"]), ("health", "Tank", None, ["tank"]),
    ("ability haste", "Utility", None, ["ah"]), ("movement speed", "Utility", None, []),
]


def categorize(tooltip, display_tags):
    # Tier A: first typed markup tag.
    best, bestpos, dims, dmg = None, 10**9, set(), set()
    for tag, cat, dt, ds in TYPED:
        m = re.search(r"<%s>" % tag, tooltip)
        if m:
            dims.update(ds)
            if dt in ("AD", "AP"):
                dmg.add(dt)
            elif dt == "ADAPTIVE":
                dmg.update(["AD", "AP"])
            if m.start() < bestpos:
                bestpos, best = m.start(), cat
    if best:
        damage = "ADAPTIVE" if dmg == {"AD", "AP"} else (next(iter(dmg)) if dmg else "NONE")
        return best, damage, sorted(dims)
    # Tier B: Riot AugmentDisplayTags.
    for t in (display_tags or []):
        if t in DISPLAY_TAG:
            cat, ds = DISPLAY_TAG[t]
            return cat, "NONE", ds
    # Tier C: keyword over cleaned text.
    plain = strip_markup(tooltip).lower()
    for kw, cat, dt, ds in KEYWORDS:
        if kw in plain:
            return cat, (dt or "NONE"), ds
    return "Other", "NONE", []


# ------------------------------------------------------------------- vectors
def unit(vec):
    n = math.sqrt(sum(v * v for v in vec.values())) or 1.0
    return {k: v / n for k, v in vec.items()}


def cosine(a, b):
    dot = sum(a.get(k, 0) * b.get(k, 0) for k in DIMS)
    na = math.sqrt(sum(v * v for v in a.values())) or 1.0
    nb = math.sqrt(sum(v * v for v in b.values())) or 1.0
    return dot / (na * nb)


def augment_vector(damage_type, dims):
    v = {d: 0.0 for d in DIMS}
    for d in dims:
        v[d] = 1.0
    if damage_type == "AD":
        v["ad"] = max(v["ad"], 1.0)
    elif damage_type == "AP":
        v["ap"] = max(v["ap"], 1.0)
    elif damage_type == "ADAPTIVE":
        v["ad"] = max(v["ad"], 0.7); v["ap"] = max(v["ap"], 0.7)
    return v


# --------------------------------------------------------------- build augments
def build_catalog(ver, refresh=False):
    kiwi = json.loads(_get(f"{CD_GAME}/maps/modespecificdata/kiwi.bin.json", os.path.join(RAW, "kiwi.bin.json"), refresh))
    st = json.loads(_get(f"{CD_GAME}/en_us/data/menu/en_us/lol.stringtable.json", os.path.join(RAW, "stringtable_en.json"), refresh))
    ent = {k.lower(): v for k, v in st.get("entries", st).items()}
    cherry = json.loads(_get(f"{CDRAGON}/v1/cherry-augments.json", os.path.join(RAW, "cherry-augments.json"), refresh))
    cherry_icon = {a.get("id"): a.get("augmentSmallIconPath") for a in cherry}

    records = []
    def walk(o):
        if isinstance(o, dict):
            if o.get("__type") == "AugmentData":
                records.append(o)
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(kiwi)

    res = lambda k: ent.get(str(k).lower(), "") if k else ""
    catalog = []
    for a in records:
        api = a.get("AugmentNameId", "")
        stem = re.sub(r"^ARAM_|^Kiwi_", "", api)
        tooltip = res(a.get("AugmentTooltipTra")) or res(a.get("DescriptionTra"))
        desc = strip_markup(res(a.get("DescriptionTra")) or tooltip)
        cat, dmg, dims = categorize(tooltip, a.get("AugmentDisplayTags"))
        pid = a.get("AugmentPlatformId")
        icon = cdragon_icon_url(cherry_icon.get(pid) or a.get("AugmentSmallIconPath"))
        catalog.append({
            "id": pid,
            "apiName": api,
            "name": res(a.get("NameTra")) or stem,
            "rarity": RARITY_KIWI.get(a.get("rarity"), "Silver"),
            "primaryCategory": cat,
            "damageType": dmg,
            "vector": {d: round(v, 3) for d, v in augment_vector(dmg, dims).items() if v},
            "pivot": stem in PIVOTS,
            "pivotDim": PIVOTS.get(stem),
            "iconUrl": icon,
            "description": desc[:240],
        })
    return {"meta": {"version": ver, "augment_count": len(catalog)}, "augments": catalog}


# --------------------------------------------------------------- champions
def build_champions(ver, refresh=False):
    data = json.loads(_get(f"{DDRAGON}/cdn/{ver}/data/en_US/champion.json", os.path.join(RAW, f"champion-{ver}.json"), refresh))["data"]
    out = {}
    for cid, c in data.items():
        tags = set(c.get("tags", []))
        info = c.get("info", {}) or {}
        atk, mag, dfn = info.get("attack", 0), info.get("magic", 0), info.get("defense", 0)
        tot = max(atk + mag, 1)
        v = {d: 0.0 for d in DIMS}
        v["ap"] = mag / tot
        v["ad"] = atk / tot
        v["tank"] = dfn / 10.0 + (0.5 if "Tank" in tags else 0)
        if "Marksman" in tags:
            v["crit"] += 0.7; v["attack_speed"] += 0.6; v["on_hit"] += 0.6; v["ad"] += 0.3
        if "Fighter" in tags:
            v["on_hit"] += 0.3; v["tank"] += 0.2; v["ad"] += 0.2
        if "Assassin" in tags:
            v["pen"] += 0.5
        if "Mage" in tags:
            v["ap"] += 0.3; v["ah"] += 0.3
        if "Support" in tags and atk <= 4:
            v["heal_shield"] += 0.8; v["ah"] += 0.3
        if str(c.get("partype")) == "Mana":
            v["mana"] += 0.3; v["ah"] += 0.1
        out[cid] = {"key": c.get("key"), "name": c.get("name"), "tags": sorted(tags),
                    "vector": {k: round(x, 3) for k, x in unit(v).items() if x > 0.01}}
    return {"meta": {"version": ver}, "champions": out}


# --------------------------------------------------------------- items
TAG_DIMS = {
    "SpellDamage": ["ap"], "MagicPenetration": ["pen", "ap"], "Damage": ["ad"],
    "CriticalStrike": ["crit", "ad"], "AttackSpeed": ["attack_speed"], "OnHit": ["on_hit", "attack_speed"],
    "ArmorPenetration": ["pen", "ad"], "Armor": ["tank"], "SpellBlock": ["tank"], "Health": ["tank"],
    "HealthRegen": ["tank"], "CooldownReduction": ["ah"], "AbilityHaste": ["ah"],
    "LifeSteal": ["heal_shield", "ad"], "SpellVamp": ["heal_shield", "ap"], "Mana": ["mana"], "ManaRegen": ["mana"],
}
# Enchanter heal/shield items not distinguishable by tags (research side-table).
ENCHANTER_ITEMS = {6617: ["heal_shield"], 6620: ["heal_shield"], 4005: ["heal_shield"],
                   6616: ["heal_shield"], 3504: ["heal_shield"], 3222: ["heal_shield"], 6657: ["heal_shield"]}


def build_items(ver, refresh=False):
    data = json.loads(_get(f"{DDRAGON}/cdn/{ver}/data/en_US/item.json", os.path.join(RAW, f"item-{ver}.json"), refresh))["data"]
    out = {}
    for iid, it in data.items():
        tags = it.get("tags", [])
        if {"Consumable", "Trinket"} & set(tags):
            continue
        v = {d: 0.0 for d in DIMS}
        for t in tags:
            for d in TAG_DIMS.get(t, []):
                v[d] += 1.0
        for d in ENCHANTER_ITEMS.get(int(iid), []):
            v[d] += 2.0
        if sum(v.values()) == 0:
            continue
        out[iid] = {k: round(x, 3) for k, x in unit(v).items() if x > 0.01}
    return {"meta": {"version": ver}, "items": out}


# --------------------------------------------------------------- recommendations
def load_arammayhem(catalog, ver):
    """From arammayhem_data: per champion -> (ordered meta augment IDs, {augId: winrate}, [build itemIDs])."""
    path = os.path.join(OUT, f"arammayhem_data_{ver}.json")
    if not os.path.exists(path):
        return {}, {}, {}
    data = json.load(open(path))
    norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
    by_name = {norm(a["name"]): a["id"] for a in catalog["augments"]}
    meta, wr, builds = {}, {}, {}
    for cid, d in data.items():
        ids, wmap = [], {}
        for a in d.get("augments", []):
            s = a["slug"]
            aid = by_name.get(norm(s)) or by_name.get(norm(s.replace("quest-", "")))
            if aid and aid not in ids:
                ids.append(aid)
                if a.get("wr") is not None:
                    wmap[aid] = a["wr"]
        meta[cid] = ids
        wr[cid] = wmap
        builds[cid] = [int(x) for x in d.get("build", [])]
    return meta, wr, builds


def build_recommendations(catalog, champions, meta, wr):
    """Primary order = arammayhem real meta rank; heuristic (champion-fit) fills the rest."""
    TIER_PRIOR = {"Prismatic": 1.0, "Gold": 0.6, "Silver": 0.35}
    augs = catalog["augments"]
    recs = {}
    for cid, c in champions["champions"].items():
        C = {k: v for k, v in c["vector"].items()}
        metarank = {aid: i for i, aid in enumerate(meta.get(cid, []))}
        wmap = wr.get(cid, {})
        scored = []
        for a in augs:
            A = a["vector"]
            prior = cosine(C, A) if A else 0.25
            pivot = 0.15 if (a["pivot"] and C.get(a.get("pivotDim") or "", 0) > 0.25) else 0
            heur = 0.8 * prior + 0.15 * pivot + 0.05 * TIER_PRIOR.get(a["rarity"], 0.5)
            is_meta = a["id"] in metarank
            # Meta augments sort first (by real rank); heuristic fills below them.
            score = (1000 - metarank[a["id"]]) if is_meta else round(heur, 4)
            label = "Meta" if is_meta else ("Strong" if heur >= 0.45 else "Situational")
            scored.append({"id": a["id"], "name": a["name"], "rarity": a["rarity"],
                           "cat": a["primaryCategory"], "dmg": a["damageType"], "pivot": a["pivot"],
                           "meta": is_meta, "score": score, "label": label, "wr": wmap.get(a["id"])})
        by = {}
        for s in scored:
            by.setdefault(s["rarity"], []).append(s)
        for t in by:
            by[t].sort(key=lambda x: x["score"], reverse=True)
        recs[cid] = {"key": c["key"], "name": c["name"], "tags": c["tags"], "by_rarity": by}
    return recs


def main():
    refresh = "--refresh" in sys.argv
    verify = "--verify" in sys.argv
    os.makedirs(RAW, exist_ok=True); os.makedirs(OUT, exist_ok=True)
    ver = ddragon_version(refresh)
    print(f"Data Dragon version: {ver}")

    catalog = build_catalog(ver, refresh)
    json.dump(catalog, open(os.path.join(OUT, f"mayhem_catalog_{ver}.json"), "w"), ensure_ascii=False, indent=2)
    from collections import Counter
    cats = Counter(a["primaryCategory"] for a in catalog["augments"])
    dmgs = Counter(a["damageType"] for a in catalog["augments"])
    other = sum(1 for a in catalog["augments"] if a["primaryCategory"] == "Other")
    print(f"Catalog: {catalog['meta']['augment_count']} augments | categories={dict(cats)}")
    print(f"  damageType={dict(dmgs)} | uncategorized(Other)={other} | pivots={sum(a['pivot'] for a in catalog['augments'])}")

    champions = build_champions(ver, refresh)
    json.dump(champions, open(os.path.join(OUT, f"mayhem_champions_{ver}.json"), "w"), ensure_ascii=False, indent=2)
    print(f"Champions: {len(champions['champions'])} vectors")

    items = build_items(ver, refresh)
    json.dump(items, open(os.path.join(OUT, f"mayhem_items_{ver}.json"), "w"), ensure_ascii=False, indent=2)
    print(f"Items: {len(items['items'])} stat vectors")

    meta, wr, builds = load_arammayhem(catalog, ver)
    print(f"Meta (arammayhem): {len(meta)} champions, {sum(len(v) for v in meta.values())} ranked picks, "
          f"{sum(len(b) for b in builds.values())} build items")
    recs = build_recommendations(catalog, champions, meta, wr)
    full = {"meta": {"version": ver, "champion_count": len(recs)}, "champions": recs}
    json.dump(full, open(os.path.join(OUT, f"mayhem_recommendations_{ver}.json"), "w"), ensure_ascii=False, indent=2)
    # compact: top 6 per rarity
    compact = {"meta": full["meta"], "champions": {}}
    for cid, c in recs.items():
        compact["champions"][cid] = {"key": c["key"], "name": c["name"], "tags": c["tags"],
            "by_rarity": {t: [{"id": a["id"], "name": a["name"], "label": a["label"], "score": a["score"],
                              "cat": a["cat"], "dmg": a["dmg"], "pivot": a["pivot"], "meta": a["meta"], "wr": a["wr"]} for a in lst[:6]]
                          for t, lst in c["by_rarity"].items()}}
    cmpath = os.path.join(OUT, f"mayhem_recommendations_compact_{ver}.json")
    json.dump(compact, open(cmpath, "w"), ensure_ascii=False, separators=(",", ":"))
    print(f"Recommendations: {len(recs)} champions, compact {os.path.getsize(cmpath)//1024} KB")

    # Per-champion recommended build (item IDs) for the overlay's BUILD section.
    bpath = os.path.join(OUT, f"mayhem_builds_{ver}.json")
    json.dump({"meta": {"version": ver}, "builds": builds}, open(bpath, "w"), ensure_ascii=False, separators=(",", ":"))
    print(f"Builds: {len(builds)} champions -> {bpath}")

    if verify:
        print("\n=== VERIFY: spot-check augment categorization ===")
        idx = {a["name"]: a for a in catalog["augments"]}
        for n in ["ADAPt", "Marksmage", "Blunt Force", "Soul Siphon", "Jeweled Gauntlet", "Circle of Death", "Celestial Body", "First Aid Kit"]:
            a = idx.get(n)
            if a:
                print(f"  {n:18} cat={a['primaryCategory']:13} dmg={a['damageType']:8} pivot={a['pivot']} vec={list(a['vector'])}")
        print("\n=== VERIFY: top augments per rarity (build-agnostic) ===")
        for s in ["Ahri", "Jinx", "Sett", "Soraka", "MasterYi"]:
            c = recs.get(s)
            if not c: continue
            print(f"\n{c['name']} {c['tags']}")
            for t in ["Prismatic", "Gold", "Silver"]:
                top = (c["by_rarity"].get(t) or [])[:3]
                if top:
                    print(f"   {t:9}: " + ", ".join(f"{x['name']}({x['label']},{x['dmg']})" for x in top))


if __name__ == "__main__":
    main()
