#!/usr/bin/env python3
"""
Per-champion ARAM: MAYHEM augment stats from Blitz (tier + win rate + pick rate), the same data
that drives blitz.gg's per-champion augment tier list. Reads the cached aram_mayhem_champion
responses (raw/blitz_mayhem/<key>.json) — the `augments` dict, keyed by augment id, has
{tier (1=S … 5=D), rank, win_rate, pick_rate, num_games}. Joined with our catalogue for rarity.

Output: mayhem_augment_stats_<ver>.json keyed by Data Dragon champion id ->
  { augmentId: {tier, wr, pick, games} }
The Swift recommender ranks per rarity by (tier, win_rate) over a games floor (drops sub-sample
noise) and stamps the Blitz tier badge — so the overlay's augment tiers match Blitz exactly.

Personal use.
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw", "blitz_mayhem"); OUT = os.path.join(HERE, "out")


def main():
    champ_file = [f for f in os.listdir(OUT) if f.startswith("mayhem_champions_")][0]
    ver = re.search(r"mayhem_champions_(.+)\.json", champ_file).group(1)
    champs = json.load(open(os.path.join(OUT, champ_file)))["champions"]  # DDragon id -> {key,...}
    catf = [f for f in os.listdir(OUT) if f.startswith("mayhem_catalog_")][0]
    cat_ids = {int(a["id"]) for a in json.load(open(os.path.join(OUT, catf)))["augments"]}

    out, miss = {}, []
    for cid, c in champs.items():
        path = os.path.join(RAW, f"{c['key']}.json")
        if not os.path.exists(path):
            miss.append(c["name"]); continue
        try:
            augs = json.loads(open(path, encoding="utf-8", errors="ignore").read())["data"][0]["data"]["augments"]
        except Exception:
            miss.append(c["name"]); continue
        stats = {}
        for k, v in augs.items():
            aid = int(k)
            if aid not in cat_ids:
                continue
            stats[str(aid)] = {
                "tier": int(v.get("tier", 5)),
                "wr": round(float(v.get("win_rate", 0) or 0) * 100, 1),
                "pick": round(float(v.get("pick_rate", 0) or 0) * 100, 2),
                "games": int(v.get("num_games", 0) or 0),
            }
        if stats:
            out[cid] = stats

    path = os.path.join(OUT, f"mayhem_augment_stats_{ver}.json")
    json.dump({"meta": {"version": ver, "source": "blitz aram_mayhem_champion.augments"}, "champions": out},
              open(path, "w"), ensure_ascii=False, separators=(",", ":"))
    print(f"augment stats: {len(out)}/{len(champs)} champions -> {path}  ({os.path.getsize(path)//1024} KB)")
    if miss: print("missed:", ", ".join(miss[:12]))


if __name__ == "__main__":
    main()
