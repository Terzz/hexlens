# Mayhem augment data pipeline

Génère, depuis des sources statiques gratuites, les JSON que l'overlay Swift consommera pour la feature
**recommandation d'augments en ARAM du Chaos (ARAM: Mayhem)**.

> Conçu pour rester **compliant Riot** : aucune winrate affichée (les data Mayhem sont bloquées côté match-v5
> et Riot interdit l'affichage de winrates d'augments). La reco est une **heuristique déterministe**
> (fit champion × prior de tier), pas une agrégation de parties.

## Lancer

```bash
cd data-pipeline
python3 mayhem_pipeline.py            # fetch (mis en cache dans raw/) + build dans out/
python3 mayhem_pipeline.py --verify   # idem + affiche un échantillon de recos
python3 mayhem_pipeline.py --refresh   # re-télécharge les sources (à faire à chaque patch)
```

Stdlib Python uniquement, aucun `pip install`. Sorties dans `out/` :
- `mayhem_catalog_<ver>.json` — 170 augments : id, nom (EN/FR), icône, rareté, tier, catégories, description.
- `mayhem_recommendations_<ver>.json` — par champion : augments classés par rareté avec score de fit + label
  (`Core` / `Strong` / `Situational` / `Skip`) et catégories. **Pas de %.**

## Sources de données

| Source | Donne | Limite |
|---|---|---|
| CommunityDragon `cherry-augments.json` (filtre `ARAM_`) | id, nom, icône, rareté — **suit `latest`** | pas de description |
| Wiki `Module:MayhemAugmentData/data` | description + tier (S/G/P) | **lag le pool live (~118/170 joints)**, noms divergents |
| Data Dragon `champion.json` | tags, info(attack/magic/defense), partype | — |

⚠️ **Écart de couverture connu** : ~53% des augments ont une description (le wiki est en retard sur CommunityDragon
après le patch 26.12). Les augments sans description tombent en score neutre. Deux pistes pour améliorer :
1. Trouver une source de descriptions **par `augmentNameId`** dans les game-data CDragon (stringtables) — à sonder.
2. Brancher un **prior de tier curé** (aramgg / arammayhem / metasrc / dataset Lanternko) en option « soft »
   — ça dampe aussi l'artefact des augments sur-taggés. Cf. plan, jamais une dépendance dure.

## Comment marche l'heuristique (et comment la calibrer)

- **Classification champion** (`classify_champion`) : profil de poids (ap, ad, on_hit, tank, heal_shield…)
  dérivé des tags + `info` Data Dragon.
- **Catégorisation augment** (`CATEGORY_KEYWORDS` / `categorize_augment`) : mots-clés scannés dans la description.
  Catégories `IDENTITY` (type de dégâts/rôle) vs `UTILITY` (universel).
- **Score** (`fit_score`) : piloté par le **meilleur match d'identité** + bonus utility + prior de tier
  (`TIER_PRIOR`). Pénalités pour les pièges (augment AD sur caster pur, etc.).

Pour calibrer avec ta connaissance du mode : ajuste `CATEGORY_KEYWORDS` (précision du tagging),
les poids dans `classify_champion`, et `TIER_PRIOR`. Le `--verify` t'aide à juger sur des champions tests.

## Limite intrinsèque

Le matching par mots-clés plafonne : une description longue matche trop de catégories → l'augment remonte
partout. Pour dépasser ça il faut soit une catégorisation curée à la main (réaliste car ~170 augments),
soit un prior de tier réel. C'est le point où **ton expertise Mayhem** vaut plus que l'automatisation.
