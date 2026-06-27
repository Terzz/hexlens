#!/usr/bin/env python3
"""
Scrape per-champion "Best Augments" from arammayhem.com/build/<slug>/ to give the overlay
REAL meta recommendations (instead of the generic stat heuristic).

Personal use. We extract the ordered best-augment list (community/meta ranking); the overlay
displays rank + rarity tier, NEVER the win-rate numbers (Riot policy).

Output: out/arammayhem_best_<ver>.json = { championId: ["augment-slug", ...] (ranked) }
"""
import json, os, re, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw", "arammayhem")
OUT = os.path.join(HERE, "out")
BASE = "https://arammayhem.com/build/"


def slugs_for(champ_id, name):
    a = re.sub(r"[^a-z0-9]", "", champ_id.lower())
    b = re.sub(r"[^a-z0-9]", "", name.lower())
    out = []
    for s in (a, b):
        if s and s not in out:
            out.append(s)
    return out


def fetch(slug, refresh=False):
    cache = os.path.join(RAW, f"{slug}.html")
    if os.path.exists(cache) and not refresh:
        return open(cache, encoding="utf-8", errors="ignore").read()
    req = urllib.request.Request(BASE + slug + "/", headers={"User-Agent": "Mozilla/5.0 (Macintosh) personal-overlay"})
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            html = r.read().decode("utf-8", "ignore")
    except Exception:
        return None
    open(cache, "w").write(html)
    return html


def parse_best(html):
    """Ordered augment slugs from the 'Best Augments for' section (kept for compatibility)."""
    return [a["slug"] for a in parse_augments(html)]


def parse_augments(html):
    """Ordered augments with win rate: [{slug, wr}] from the 'Best Augments for' section."""
    i = html.find("Best Augments for")
    if i < 0:
        return []
    sec = html[i:i + 12000]
    seen, out = set(), []
    for m in re.finditer(r'<a href="/augments/([a-z0-9\-]+)"[^>]*>(.*?)</a>', sec, re.DOTALL):
        slug = m.group(1)
        if slug in seen:
            continue
        seen.add(slug)
        inner = re.sub(r"<[^>]+>", " ", m.group(2))
        wr = re.search(r"(\d{2}\.\d{2})\s*%", inner)
        out.append({"slug": slug, "wr": float(wr.group(1)) if wr else None})
    return out


def parse_build(html):
    """Recommended core build item IDs: items before the first 'Boots' label + first boots."""
    items = [(m.start(), m.group(1)) for m in re.finditer(r"/items/(\d{3,5})\.png", html)]
    if not items:
        return []
    bm = re.search(r">\s*Boots\s*<", html)
    boots_pos = bm.start() if bm else None
    core, seen = [], set()
    for pos, iid in items:
        if boots_pos is not None and pos >= boots_pos:
            break
        if iid not in seen:
            seen.add(iid); core.append(iid)
    boots = None
    if boots_pos is not None:
        for pos, iid in items:
            if pos >= boots_pos:
                boots = iid; break
    build = core[:5] + ([boots] if boots else [])
    # fallback if no Boots label: first 6 distinct
    if not build:
        for pos, iid in items:
            if iid not in seen:
                seen.add(iid); build.append(iid)
            if len(build) >= 6:
                break
    return build


def main():
    refresh = "--refresh" in sys.argv
    os.makedirs(RAW, exist_ok=True)
    champs = json.load(open(os.path.join(OUT, [f for f in os.listdir(OUT) if f.startswith("mayhem_champions_")][0])))["champions"]
    result, miss = {}, []
    for n, (cid, c) in enumerate(champs.items(), 1):
        augs, build = [], []
        for slug in slugs_for(cid, c["name"]):
            html = fetch(slug, refresh)
            if html:
                augs = parse_augments(html)
                if augs:
                    build = parse_build(html)
                    break
        if augs:
            result[cid] = {"augments": augs, "build": build}
        else:
            miss.append(c["name"])
        if n % 25 == 0:
            print(f"  {n}/{len(champs)} ... ok={len(result)}")
        time.sleep(0.15)
    ver = re.search(r"mayhem_champions_(.+)\.json", [f for f in os.listdir(OUT) if f.startswith("mayhem_champions_")][0]).group(1)
    path = os.path.join(OUT, f"arammayhem_data_{ver}.json")
    json.dump(result, open(path, "w"), ensure_ascii=False, indent=2)
    print(f"\nScraped {len(result)}/{len(champs)} champions -> {path}")
    if miss:
        print(f"missed ({len(miss)}): " + ", ".join(miss[:20]) + (" ..." if len(miss) > 20 else ""))
    for s in ["Nidalee", "MasterYi", "Ahri"]:
        d = result.get(s, {})
        print(f"  {s}: augs={[(a['slug'], a['wr']) for a in d.get('augments', [])][:3]} build={d.get('build', [])}")


if __name__ == "__main__":
    main()
