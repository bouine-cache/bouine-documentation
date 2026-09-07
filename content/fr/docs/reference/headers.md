---
title: "En-têtes de réponse"
weight: 93
description: "En-têtes de réponse HTTP ajoutés par bouine."
---

## X-Cache

Indique comment la réponse a été servie.

| Valeur | Description |
|-------|-------------|
| `HIT` | Servi depuis le cache (frais) |
| `MISS` | Récupéré depuis l'origine et mis en cache |
| `STALE` | Servi depuis le cache (stale, dans la fenêtre stale-while-revalidate ou stale-if-error) |
| `BYPASS` | Cache contourné (no-store, no-cache, cache désactivé pour la route, ou requête SSE) |
| `REVALIDATED` | Requête conditionnelle à l'origine a renvoyé 304, servi depuis le cache avec une fraîcheur mise à jour |

```bash
curl -sI http://localhost:8080/get | grep x-cache
# X-Cache: HIT
```

## Age

L'âge de l'objet en cache en secondes, calculé comme le temps écoulé depuis
l'en-tête `Date` de la réponse originale plus tout le temps passé dans les
forward proxies upstream. Mis à jour à chaque cache hit.

```bash
curl -sI http://localhost:8080/get | grep age
# Age: 42
```

## X-Cache-Source

Indique quel tier de stockage a servi la réponse.

| Valeur | Description |
|-------|-------------|
| `hot` | Servi depuis le hot tier en RAM (L0) |
| `warm` | Servi depuis le warm tier mmap (L1) |
| `peer` | Servi depuis un peer du cluster via peer fetch |
| `origin` | Récupéré depuis l'origine upstream |
| _(vide)_ | Non servi depuis un tier de stockage (BYPASS ou only-if-cached 504) |

## X-Bouine-Route

Le label de route qui a correspondu à la requête. Utilisé par le tableau
de bord pour l'attribution par route et par le log d'accès. Ce n'est plus
un label Prometheus : depuis v0.5.8, les métriques RED du data plane
s'attribuent par `upstream_pool` (un petit ensemble borné par la
configuration) au lieu des noms de routes ; voir
[Supervision](/docs/operations/monitoring/#traffic-red).

## X-Bouine-Pool

L'upstream pool de la route servie. Défini par le routeur comme valeur
process-locale et consommé par le middleware de métriques comme label
Prometheus `upstream_pool` ; la forme entrante de l'en-tête est transférée
telle quelle. Les routes sans pool (statiques, catch-all) rapportent
`_default`.
