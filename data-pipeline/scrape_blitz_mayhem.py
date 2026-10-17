#!/usr/bin/env python3
"""
Fetch per-champion ARAM: MAYHEM builds from Blitz's Mayhem dataset.

The blitz.gg /aram-mayhem pages read a dedicated REST object (NOT the ARAM GraphQL):
  https://data.v2.iesdev.com/api/v1/query_objects/prod/lol/aram_mayhem_champion?champion_id=<key>
which returns, per champion: items{average_index,pick_rate,win_rate,...}, augments{rank,win_rate,...},
augment_trios{...}, plus Mayhem win_rate/num_games/patch. This is the queue 2400 (Map12 "KIWI") data —
the one the user actually plays — versus HOWLING_ABYSS_ARAM which is normal ARAM.

This endpoint has NO skill/spell/rune info, so those are merged from the existing ARAM Blitz build
(scrape_blitz_builds.py output) — champion mechanics (skill max, Flash/Snowball, keystone) don't
change between ARAM and Mayhem.

Output keeps the SAME schema as blitz_builds_<ver>.json so the Swift decoder is unchanged; only
starting/core/situational/winRate/games/patch become Mayhem-accurate.

Personal use.
"""
import json, os, re, sys, time, urllib.request, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw", "blitz_mayhem"); OUT = os.path.join(HERE, "out")
ENDPOINT = "https://data.v2.iesdev.com/api/v1/query_objects/prod/lol/aram_mayhem_champion"
# Playstyle archetype (Tank/Crit/AP…) — Mayhem has no playstyle split, so we take the DOMINANT
# tag from the ARAM tagged-builds endpoint. The archetype is champion-intrinsic (a mage builds AP
# in both modes), so the LABEL is valid for Mayhem even though that endpoint's win rates are ARAM.
TAGS_ENDPOINT = "https://data.v2.iesdev.com/api/v1/query_objects/prod/lol/champion_builds_tags"

CONSUM = {2003, 2031, 2033, 2055, 2138, 2139, 2140, 2052, 2010, 2150}  # potions/elixirs/biscuits/snax


def fetch(champion_key, refresh=False):
    cache = os.path.join(RAW, f"{champion_key}.json")
    if os.path.exists(cache) and not refresh:
        return open(cache, encoding="utf-8").read()
    qs = urllib.parse.urlencode({"champion_id": str(champion_key)})
    req = urllib.request.Request(f"{ENDPOINT}?{qs}", headers={
        "User-Agent": "Mozilla/5.0", "Origin": "https://blitz.gg", "Referer": "https://blitz.gg/"})
    try:
        body = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "ignore")
    except Exception:
        return None
    os.makedirs(RAW, exist_ok=True)
    open(cache, "w").write(body)
    return body


def fetch_tags(key, refresh=False):
    cache = os.path.join(RAW, f"tags_{key}.json")
    if os.path.exists(cache) and not refresh:
        return open(cache, encoding="utf-8").read()
    qs = urllib.parse.urlencode({"champion_id": str(key), "queue_id": "HOWLING_ABYSS_ARAM"})
    req = urllib.request.Request(f"{TAGS_ENDPOINT}?{qs}", headers={
        "User-Agent": "Mozilla/5.0", "Origin": "https://blitz.gg", "Referer": "https://blitz.gg/"})
    try:
        body = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "ignore")
    except Exception:
        return None
    os.makedirs(RAW, exist_ok=True); open(cache, "w").write(body)
    time.sleep(0.12)  # polite: fresh tag fetches hit the network each champion
    return body


def dominant_archetype(body):
    """Return the playstyle tag (Tank/Crit/AP…) of the most-played tagged build."""
    try:
        builds = json.loads(body).get("data") or []
    except Exception:
        return None
    best, best_games = None, -1
    for b in builds:
        tags = b.get("name_tags") or []
        if not tags:
            continue
        games = sum(int(c.get("games", 0) or 0) for c in (b.get("coreItems") or []) if isinstance(c, dict))
        if games > best_games:
            best_games, best = games, tags[0]
    return best


def load_ddragon_items(ver):
    cache = os.path.join(RAW, f"ddragon_items_{ver}.json")
    if os.path.exists(cache):
        dd = json.load(open(cache))
    else:
        url = f"https://ddragon.leagueoflegends.com/cdn/{ver}/data/en_US/item.json"
        dd = json.loads(urllib.request.urlopen(url, timeout=30).read())
        os.makedirs(RAW, exist_ok=True); json.dump(dd, open(cache, "w"))
    data = dd["data"]
    name = {int(k): v["name"] for k, v in data.items()}
    boots = {int(k) for k, v in data.items() if "Boots" in v.get("tags", [])}
    gold = {int(k): v.get("gold", {}).get("total", 0) for k, v in data.items()}
    # an item is a "final" purchase if nothing builds out of it (empty `into`)
    final = {int(k) for k, v in data.items() if not v.get("into")}
    return set(name), boots, gold, final


def realid(i, valid):
    """Map a possibly mode-prefixed live id to a base Data Dragon id, else None."""
    i = int(i)
    if i in valid: return i
    if (i % 100000) in valid: return i % 100000
    return None


def derive_build(mayhem_data, valid, boots, gold, final):
    raw = mayhem_data["items"]
    items = {}  # realid -> stats (collapse mode-prefixed onto base id, keep best sample)
    for k, v in raw.items():
        r = realid(k, valid)
        if r is None or r in CONSUM:
            continue
        if r not in items or v["pick_rate"] > items[r]["pick_rate"]:
            items[r] = v

    def is_legendary(i):
        return i in final and i not in boots and gold.get(i, 0) >= 1100

    legos = [(i, v) for i, v in items.items() if is_legendary(i)]
    boot_picks = sorted([(i, v) for i, v in items.items() if i in boots],
                        key=lambda x: -x[1]["pick_rate"])

    # core = strong legendaries (pick >= 30%) + the most-picked boots, in build-order
    core_pool = [(i, v) for i, v in legos if v["pick_rate"] >= 0.30]
    if boot_picks:
        core_pool.append(boot_picks[0])
    core = [i for i, v in sorted(core_pool, key=lambda x: x[1]["average_index"])][:4]

    # situational = next legendaries (12%–30% pick) the core didn't take, by popularity
    situ = [i for i, v in sorted(legos, key=lambda x: -x[1]["pick_rate"])
            if 0.12 <= v["pick_rate"] < 0.30 and i not in core][:4]

    # starting = cheapest popular early buys (potions/components first-back), by pick-rate
    starters = [(int(k), v) for k, v in raw.items()
                if realid(k, valid) and gold.get(realid(k, valid), 0) <= 500 and v["average_index"] <= 2.0]
    starting = [realid(i, valid) for i, v in sorted(starters, key=lambda x: -x[1]["pick_rate"])[:2]]

    return {
        "starting": starting,
        "core": core,
        "situational": situ,
        "winRate": round(mayhem_data["win_rate"] * 100, 1),
        "games": int(mayhem_data["num_games"]),
        "tier": mayhem_data.get("tier"),
    }


def main():
    refresh = "--refresh" in sys.argv
    os.makedirs(RAW, exist_ok=True)
    champ_file = [f for f in os.listdir(OUT) if f.startswith("mayhem_champions_")][0]
    ver = re.search(r"mayhem_champions_(.+)\.json", champ_file).group(1)
    champs = json.load(open(os.path.join(OUT, champ_file)))["champions"]  # keyed by DDragon id

    # existing ARAM build = source of skills/spells/runes (mechanics don't differ in Mayhem)
    aram = {}
    aram_path = os.path.join(OUT, f"blitz_builds_{ver}.json")
    if os.path.exists(aram_path):
        aram = json.load(open(aram_path)).get("builds", {})

    dd_ver = ver if re.match(r"\d+\.\d+\.\d+", ver) else "16.13.1"
    valid, boots, gold, final = load_ddragon_items(dd_ver)

    out, miss = {}, []
    for n, (cid, c) in enumerate(champs.items(), 1):
        body = fetch(c["key"], refresh)
        try:
            d = json.loads(body) if body else None
            md = d["data"][0]["data"] if d and d.get("data") else None
        except Exception:
            md = None
        if not md or not md.get("items"):
            miss.append(c["name"]); continue
        build = derive_build(md, valid, boots, gold, final)
        base = aram.get(cid, {})
        tbody = fetch_tags(c["key"], refresh)
        archetype = dominant_archetype(tbody) if tbody else None
        # merge: Mayhem items/winrate + ARAM skills/spells/runes + playstyle label
        out[cid] = {
            "patch": d["data"][0].get("patch", ver),
            "games": build["games"], "winRate": build["winRate"], "tier": build["tier"],
            "archetype": archetype,
            "starting": build["starting"] or base.get("starting", []),
            "core": build["core"], "situational": build["situational"],
            "spells": base.get("spells", []),
            "skillMax": base.get("skillMax", ""),
            "skillOrder": base.get("skillOrder", []),
            "keystone": base.get("keystone"),
            "primaryTree": base.get("primaryTree"),
            "runes": base.get("runes", []),
            "shards": base.get("shards", []),
        }
        if n % 25 == 0: print(f"  {n}/{len(champs)} ... ok={len(out)}")
        if body is None or refresh: time.sleep(0.15)

    path = os.path.join(OUT, f"blitz_builds_{ver}.json")  # overwrite -> bundled file picks it up
    json.dump({"meta": {"version": ver, "source": "blitz/iesdev aram_mayhem_champion",
                        "queue": "MAYHEM_2400"}, "builds": out},
              open(path, "w"), ensure_ascii=False, separators=(",", ":"))
    print(f"\nMayhem builds: {len(out)}/{len(champs)} champions -> {path}  ({os.path.getsize(path)//1024} KB)")
    if miss: print("missed:", ", ".join(miss[:15]))


if __name__ == "__main__":
    main()
