#!/usr/bin/env python3
"""
Fetch full per-champion ARAM builds from Blitz's open GraphQL backend
(datalake.v2.iesdev.com) — the same data the blitz.gg site shows.

Personal use. Output: out/blitz_builds_<ver>.json keyed by Data Dragon champion id, with the
top build: starting items, core item path, situational, summoner spells, skill max order,
keystone + rune trees, win rate. ARAM Mayhem reuses the ARAM (Howling Abyss) item pool, so
queue = HOWLING_ABYSS_ARAM; the Mayhem-specific augment layer comes from arammayhem separately.
"""
import json, os, re, sys, time, urllib.request, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw", "blitz"); OUT = os.path.join(HERE, "out")
API = "https://datalake.v2.iesdev.com/graphql"
QUERY = ('query ChampionBuildsTagged($championId:String! $matchupChampionId:String $queue:String! '
         '$role:String $tier:String){executeDatabricksQuery(game:LEAGUE '
         'queryName:"prod_champion_builds_tags" params:[{name:"individual_position",value:$role}'
         '{name:"queue_id",value:$queue}{name:"champion_id",value:$championId}'
         '{name:"build_tier",value:$tier}{name:"match_up_champion_id",value:$matchupChampionId}])'
         '{metadata{byteSize lastModified parameters}payload}}')


def fetch(champion_key, refresh=False):
    cache = os.path.join(RAW, f"{champion_key}.json")
    if os.path.exists(cache) and not refresh:
        return open(cache, encoding="utf-8").read()
    qs = urllib.parse.urlencode({"query": QUERY,
                                 "variables": json.dumps({"championId": str(champion_key),
                                                          "queue": "HOWLING_ABYSS_ARAM"})})
    req = urllib.request.Request(f"{API}?{qs}", headers={
        "User-Agent": "Mozilla/5.0", "Origin": "https://blitz.gg", "Referer": "https://blitz.gg/"})
    try:
        body = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "ignore")
    except Exception:
        return None
    open(cache, "w").write(body)
    return body


def parse(body):
    d = json.loads(body)
    pl = (d.get("data") or {}).get("executeDatabricksQuery") or {}
    payload = pl.get("payload") or {}
    cols = [c["name"] for c in payload.get("manifest", {}).get("schema", {}).get("columns", [])]
    rows = payload.get("result", {}).get("dataArray") or []
    if not cols or not rows:
        return None
    rec = dict(zip(cols, rows[0]))

    def arr(field):
        v = rec.get(field)
        if isinstance(v, str):
            try: return json.loads(v)
            except: return []
        return v or []

    def top(field, key="games"):
        a = arr(field)
        return sorted(a, key=lambda x: float(x.get(key, 0) or 0), reverse=True) if a else []

    def ids_of(x):
        v = x.get("itemIds") or x.get("summonerSpellIds") or []
        return [int(i) for i in (v.split(",") if isinstance(v, str) else v)]

    starting = top("startingItems"); core = top("coreItems")
    spells = top("summonerSpells"); skills = top("skillOrders", "win_rate")
    keystone = top("keystone"); sit = top("situationalItems", "pick_rate")
    runes = arr("runes"); shards = arr("shards")

    # skill max order (first time each of Q/W/E hits, ignoring R) -> e.g. "Q>E>W"
    skill_seq = skills[0]["skillOrder"] if skills else []
    letter = {1: "Q", 2: "W", 3: "E", 4: "R"}
    maxorder, seen = [], set()
    for s in skill_seq:
        L = letter.get(int(s))
        if L and L != "R" and L not in seen:
            seen.add(L); maxorder.append(L)
        if len(maxorder) == 3: break

    return {
        "patch": rec.get("patch"), "games": int(float(rec.get("games", 0) or 0)),
        "winRate": round(float(rec.get("win_rate", 0) or 0) * 100, 1),
        "starting": ids_of(starting[0]) if starting else [],
        "core": ids_of(core[0]) if core else [],
        "situational": [int(x["itemId"]) for x in sit[:4] if x.get("itemId")],
        "spells": ids_of(spells[0]) if spells else [],
        "skillMax": ">".join(maxorder),
        "skillOrder": [int(x) for x in skill_seq] if skill_seq else [],
        "keystone": int(keystone[0]["keystone_id"]) if keystone else None,
        "primaryTree": int(keystone[0]["treeId"]) if keystone else None,
        "runes": [int(r["runeId"]) for r in sorted(runes, key=lambda x: float(x.get("pick_rate", 0) or 0), reverse=True)[:6]],
        "shards": [int(s.get("shardId") or s.get("perkId") or 0) for s in (shards[:3] if isinstance(shards, list) else [])],
    }


def main():
    refresh = "--refresh" in sys.argv
    os.makedirs(RAW, exist_ok=True)
    champs = json.load(open(os.path.join(OUT, [f for f in os.listdir(OUT) if f.startswith("mayhem_champions_")][0])))["champions"]
    ver = re.search(r"mayhem_champions_(.+)\.json", [f for f in os.listdir(OUT) if f.startswith("mayhem_champions_")][0]).group(1)
    out, miss = {}, []
    for n, (cid, c) in enumerate(champs.items(), 1):
        body = fetch(c["key"], refresh)
        b = parse(body) if body else None
        if b: out[cid] = b
        else: miss.append(c["name"])
        if n % 25 == 0: print(f"  {n}/{len(champs)} ... ok={len(out)}")
        if body is None or refresh: time.sleep(0.2)
    path = os.path.join(OUT, f"blitz_builds_{ver}.json")
    json.dump({"meta": {"version": ver, "source": "blitz/iesdev", "queue": "HOWLING_ABYSS_ARAM"}, "builds": out},
              open(path, "w"), ensure_ascii=False, separators=(",", ":"))
    print(f"\nBlitz builds: {len(out)}/{len(champs)} champions -> {path}  ({os.path.getsize(path)//1024} KB)")
    if miss: print("missed:", ", ".join(miss[:15]))


if __name__ == "__main__":
    main()
