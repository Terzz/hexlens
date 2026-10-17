#!/usr/bin/env python3
"""
Derive a coherent recommended RUNE PAGE per champion and patch it into blitz_builds_<ver>.json,
plus emit a rune/shard id -> icon map for the overlay.

The raw ARAM Blitz response (raw/blitz/<key>.json) has per-rune pick rates and a shards dict, but
not a clean page. We reconstruct the page the standard way (op.gg/u.gg style): authoritative slot
structure from Data Dragon runesReforged + pick rates to choose each slot's rune.

Page = keystone + 3 primary minor runes (one per primary row) + secondary tree + 2 secondary runes
(top 2 distinct rows) + 3 stat shards (offense/flex/defense top pick). Icons from CommunityDragon
(covers stat shards too, unlike runesReforged).

Personal use.
"""
import json, os, re, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw", "blitz"); OUT = os.path.join(HERE, "out")
DDRAGON_VER = "16.13.1"
CDRAGON_PERKS = "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/v1/perks.json"
RUNES_REFORGED = f"https://ddragon.leagueoflegends.com/cdn/{DDRAGON_VER}/data/en_US/runesReforged.json"


def fetch_json(url, cache_name):
    cache = os.path.join(RAW, cache_name)
    if os.path.exists(cache):
        return json.load(open(cache))
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    data = json.loads(urllib.request.urlopen(req, timeout=30).read())
    json.dump(data, open(cache, "w"))
    return data


def load_structure():
    trees = fetch_json(RUNES_REFORGED, "runesReforged.json")
    # tree_rows[tree_id] = [[row0 keystone ids], [row1], [row2], [row3]]
    tree_rows, rune_tree, tree_icon = {}, {}, {}
    for t in trees:
        tree_icon[t["id"]] = f"https://ddragon.leagueoflegends.com/cdn/img/{t['icon']}"
        rows = []
        for slot in t["slots"]:
            ids = [r["id"] for r in slot["runes"]]
            rows.append(ids)
            for rid in ids:
                rune_tree[rid] = t["id"]
        tree_rows[t["id"]] = rows
    # icons from CommunityDragon: id -> served path (covers runes + stat shards)
    perks = fetch_json(CDRAGON_PERKS, "cdragon_perks.json")
    icons = {}
    for p in perks:
        ip = (p.get("iconPath") or "").lower()
        if ip.startswith("/lol-game-data/assets/"):
            ip = ip[len("/lol-game-data/assets/"):]
        icons[p["id"]] = ip
    return tree_rows, rune_tree, icons, tree_icon


def derive_page(raw_body, keystone, primary_tree, tree_rows):
    d = json.loads(raw_body)
    rec_cols = d["data"]["executeDatabricksQuery"]["payload"]["manifest"]["schema"]["columns"]
    rec = dict(zip([c["name"] for c in rec_cols],
                   d["data"]["executeDatabricksQuery"]["payload"]["result"]["dataArray"][0]))

    def arr(f):
        v = rec.get(f)
        try: return json.loads(v) if isinstance(v, str) else v
        except: return v

    runes = arr("runes") or []
    shards_d = arr("shards") or {}
    pick = {}
    for r in runes:
        try: pick[int(r["runeId"])] = pick.get(int(r["runeId"]), 0.0) + float(r["pick_rate"])
        except: pass

    def top_in(ids):  # most-picked rune among a row's options
        return max(ids, key=lambda rid: pick.get(rid, 0.0)) if ids else None

    rows = tree_rows.get(primary_tree, [])
    primary = [top_in(rows[i]) for i in (1, 2, 3) if i < len(rows)]

    # secondary tree = non-primary tree with most total pick across its runes
    tree_pick = {}
    for rid, pr in pick.items():
        for tid, trows in tree_rows.items():
            if tid != primary_tree and any(rid in row for row in trows):
                tree_pick[tid] = tree_pick.get(tid, 0.0) + pr
    sec_tree = max(tree_pick, key=tree_pick.get) if tree_pick else None
    secondary = []
    if sec_tree:
        # best rune per minor row, then take the 2 best rows
        per_row = []
        for i in (1, 2, 3):
            if i < len(tree_rows[sec_tree]):
                best = top_in(tree_rows[sec_tree][i])
                if best is not None:
                    per_row.append((best, pick.get(best, 0.0)))
        secondary = [r for r, _ in sorted(per_row, key=lambda x: -x[1])[:2]]

    # shards: top pick per slot, in display order offense/flex/defense
    def top_shard(slot):
        lst = shards_d.get(slot) or []
        if not lst: return None
        best = max(lst, key=lambda s: float(s.get("pick_rate", 0) or 0))
        try: return int(best["shard_id"])
        except: return None
    shards = [s for s in (top_shard("offenseShard"), top_shard("flexShard"), top_shard("defenseShard")) if s]

    return {"keystone": keystone, "primaryTree": primary_tree, "primary": [p for p in primary if p],
            "secondaryTree": sec_tree, "secondary": secondary, "shards": shards}


def main():
    tree_rows, rune_tree, icons, tree_icon = load_structure()
    ver_file = [f for f in os.listdir(OUT) if re.match(r"blitz_builds_\d", f)][0]
    ver = re.search(r"blitz_builds_(.+)\.json", ver_file).group(1)
    champ_file = [f for f in os.listdir(OUT) if f.startswith("mayhem_champions_")][0]
    champs = json.load(open(os.path.join(OUT, champ_file)))["champions"]
    bundle = json.load(open(os.path.join(OUT, ver_file)))
    builds = bundle["builds"]

    used_icons, done, miss = set(), 0, []
    for cid, c in champs.items():
        b = builds.get(cid)
        raw_path = os.path.join(RAW, f"{c['key']}.json")
        if not b or not os.path.exists(raw_path):
            continue
        ks, pt = b.get("keystone"), b.get("primaryTree")
        if not ks or not pt:
            miss.append(c["name"]); continue
        try:
            page = derive_page(open(raw_path, encoding="utf-8", errors="ignore").read(), ks, pt, tree_rows)
        except Exception as e:
            miss.append(f"{c['name']}({e})"); continue
        b["runePage"] = page
        for rid in [page["keystone"], page["primaryTree"], page["secondaryTree"], *page["primary"],
                    *page["secondary"], *page["shards"]]:
            if rid is not None: used_icons.add(rid)
        done += 1

    # write back builds + a compact rune-icon map (only ids we use).
    # Trees resolve to a full Data Dragon URL; runes/shards to a CommunityDragon relative path.
    json.dump(bundle, open(os.path.join(OUT, ver_file), "w"), ensure_ascii=False, separators=(",", ":"))
    icon_map = {}
    for rid in used_icons:
        if rid in tree_icon:
            icon_map[str(rid)] = tree_icon[rid]
        elif rid in icons:
            icon_map[str(rid)] = icons[rid]
    json.dump({"meta": {"source": "communitydragon perks"}, "icons": icon_map},
              open(os.path.join(OUT, f"rune_icons_{ver}.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    print(f"rune pages: {done}/{len(champs)} champions  |  rune icons mapped: {len(icon_map)}")
    if miss: print("missed:", ", ".join(miss[:12]))
    # sanity print Thresh
    tp = builds.get("Thresh", {}).get("runePage")
    print("Thresh runePage:", json.dumps(tp))


if __name__ == "__main__":
    main()
